import Foundation

/// Lecture en cours telle qu'affichée par Lumen.
struct NowPlaying: Equatable {
    var title: String
    var artists: String
    var albumArtURL: URL?
    var isPlaying: Bool
    var progressMs: Int
    var durationMs: Int
}

enum SpotifyState: Equatable {
    case notConfigured
    case disconnected
    case connected
    case error(String)
}

/// Client Spotify Web API : état de connexion, lecture en cours et commandes de lecture.
@MainActor
final class SpotifyService: ObservableObject {
    @Published private(set) var state: SpotifyState = .disconnected
    @Published private(set) var nowPlaying: NowPlaying?

    private let auth = SpotifyAuth()
    private var config: SpotifyConfig?
    private var tokens: SpotifyTokens?
    private var pollTask: Task<Void, Never>?

    init() {
        config = SpotifyConfig.load()
        guard let config, !config.clientID.isEmpty else {
            state = .notConfigured
            return
        }
        tokens = SpotifyTokenStore.load()
        if tokens != nil {
            state = .connected
            startPolling()
        }
    }

    /// Lance la connexion (navigateur + retour sur le port local).
    func connect() {
        guard let config, !config.clientID.isEmpty else {
            state = .notConfigured
            return
        }
        Task {
            do {
                let newTokens = try await auth.authorize(config: config)
                tokens = newTokens
                SpotifyTokenStore.save(newTokens)
                state = .connected
                startPolling()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        tokens = nil
        nowPlaying = nil
        SpotifyTokenStore.delete()
        state = .disconnected
    }

    func togglePlayPause() {
        guard let playing = nowPlaying?.isPlaying else {
            send(method: "PUT", path: "/me/player/play")
            return
        }
        send(method: "PUT", path: playing ? "/me/player/pause" : "/me/player/play")
    }

    func next() { send(method: "POST", path: "/me/player/next") }
    func previous() { send(method: "POST", path: "/me/player/previous") }

    // MARK: - Interne

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNowPlaying()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func refreshNowPlaying() async {
        do {
            let (data, status) = try await request(method: "GET", path: "/me/player/currently-playing")
            switch status {
            case 200:
                nowPlaying = try Self.decodeNowPlaying(data)
            case 204:
                nowPlaying = nil   // rien ne joue
            case 401, 403:
                state = .error("Accès Spotify refusé, reconnecte-toi")
            default:
                state = .error("Spotify a répondu HTTP \(status)")
            }
            if case .error = state { return }
            state = .connected
        } catch {
            state = .error("Connexion Spotify perdue")
        }
    }

    private func send(method: String, path: String) {
        Task {
            do {
                let (_, status) = try await request(method: method, path: path)
                if status == 404 {
                    state = .error("Aucun appareil actif : lance Spotify sur un appareil")
                } else if status >= 400 {
                    state = .error("Commande refusée (HTTP \(status)) : Spotify Premium requis")
                }
                await refreshNowPlaying()
            } catch {
                state = .error("Commande Spotify impossible")
            }
        }
    }

    /// Appel Web API avec jeton valide (rafraîchi si nécessaire).
    private func request(method: String, path: String) async throws -> (Data, Int) {
        guard let config else { throw SpotifyAuthError.callbackFailed("non configuré") }
        if var current = tokens, current.expiresAt.timeIntervalSinceNow < 60 {
            current = try await auth.refresh(current, config: config)
            tokens = current
            SpotifyTokenStore.save(current)
        }
        guard let accessToken = tokens?.accessToken else { throw SpotifyAuthError.timeout }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if method == "PUT" || method == "POST" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func decodeNowPlaying(_ data: Data) throws -> NowPlaying? {
        struct Image: Decodable { let url: String }
        struct Album: Decodable { let images: [Image] }
        struct Artist: Decodable { let name: String }
        struct Item: Decodable {
            let name: String
            let duration_ms: Int
            let artists: [Artist]?
            let album: Album?
        }
        struct Response: Decodable {
            let is_playing: Bool
            let progress_ms: Int?
            let item: Item?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let item = decoded.item else { return nil }
        return NowPlaying(
            title: item.name,
            artists: (item.artists ?? []).map(\.name).joined(separator: ", "),
            albumArtURL: item.album?.images.first.flatMap { URL(string: $0.url) },
            isPlaying: decoded.is_playing,
            progressMs: decoded.progress_ms ?? 0,
            durationMs: item.duration_ms
        )
    }
}
