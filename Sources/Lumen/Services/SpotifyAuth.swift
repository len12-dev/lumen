import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Configuration Spotify, lue dans `~/Library/Application Support/Lumen/spotify.json` :
/// `{ "clientID": "…", "port": 8888 }`. Le Client ID n'est pas un secret avec PKCE.
struct SpotifyConfig: Codable {
    var clientID: String
    var port: UInt16 = 8888

    static let fileURL = GameLibrary.supportDir.appendingPathComponent("spotify.json")

    static func load() -> SpotifyConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SpotifyConfig.self, from: data)
    }

    /// Spotify exige 127.0.0.1 (et non localhost) avec un port explicite.
    var redirectURI: String { "http://127.0.0.1:\(port)/callback" }
}

struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum SpotifyAuthError: LocalizedError {
    case callbackFailed(String)
    case timeout
    case tokenRequestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .callbackFailed(let reason): "Connexion Spotify annulée : \(reason)"
        case .timeout: "Pas de réponse de Spotify (délai dépassé)"
        case .tokenRequestFailed(let code): "Échange de jeton refusé (HTTP \(code))"
        }
    }
}

/// PKCE : verifier aléatoire et challenge S256 (base64url).
enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Flux d'autorisation Authorization Code avec PKCE, callback sur un port local.
@MainActor
final class SpotifyAuth {
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    /// Ouvre le navigateur, attend le retour sur le port local et échange le code contre des jetons.
    func authorize(config: SpotifyConfig) async throws -> SpotifyTokens {
        let verifier = PKCE.verifier()
        let state = PKCE.verifier().prefix(24).description

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]

        let callback = CallbackServer(port: config.port)
        let codeTask = Task { try await callback.waitForCode(expectedState: state) }

        NSWorkspace.shared.open(components.url!)
        let code = try await codeTask.value

        return try await exchange([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier,
        ])
    }

    func refresh(_ tokens: SpotifyTokens, config: SpotifyConfig) async throws -> SpotifyTokens {
        var refreshed = try await exchange([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": config.clientID,
        ])
        // Spotify peut ne pas renvoyer de nouveau refresh token : on garde l'ancien.
        if refreshed.refreshToken.isEmpty { refreshed.refreshToken = tokens.refreshToken }
        return refreshed
    }

    private func exchange(_ params: [String: String]) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpotifyAuthError.tokenRequestFailed(status) }

        struct Response: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? "",
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        )
    }
}

/// Petit serveur HTTP sur 127.0.0.1 qui reçoit la redirection de Spotify.
final class CallbackServer {
    private let port: UInt16
    private var listener: NWListener?

    init(port: UInt16) { self.port = port }

    func waitForCode(expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let finish: (Result<String, Error>) -> Void = { [weak self] result in
                guard !finished else { return }
                finished = true
                self?.listener?.cancel()
                continuation.resume(with: result)
            }

            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: port)!
            )
            guard let listener = try? NWListener(using: parameters) else {
                finish(.failure(SpotifyAuthError.callbackFailed("port \(port) indisponible")))
                return
            }
            self.listener = listener

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let line = request.components(separatedBy: "\r\n").first ?? ""
                    let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let items = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []
                    let code = items.first { $0.name == "code" }?.value
                    let state = items.first { $0.name == "state" }?.value
                    let error = items.first { $0.name == "error" }?.value

                    let (status, body): (String, String)
                    if let code, state == expectedState {
                        (status, body) = ("200 OK", "Connexion à Spotify réussie. Tu peux fermer cet onglet.")
                        finish(.success(code))
                    } else {
                        (status, body) = ("400 Bad Request", "Connexion annulée.")
                        finish(.failure(SpotifyAuthError.callbackFailed(error ?? "réponse invalide")))
                    }
                    let html = "<html><body style=\"font-family:-apple-system;background:#0b1a4d;color:white;padding:40px\">\(body)</body></html>"
                    let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            listener.start(queue: .global())

            // Délai de sécurité : 2 minutes pour finir la connexion dans le navigateur.
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                finish(.failure(SpotifyAuthError.timeout))
            }
        }
    }
}

/// Stockage des jetons dans le Keychain.
enum SpotifyTokenStore {
    private static let service = "dev.len12.lumen.spotify"

    static func save(_ tokens: SpotifyTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClassGenericPassword as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "tokens",
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> SpotifyTokens? {
        let query: [String: Any] = [
            kSecClassGenericPassword as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    static func delete() {
        SecItemDelete([
            kSecClassGenericPassword as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "tokens",
        ] as CFDictionary)
    }
}
