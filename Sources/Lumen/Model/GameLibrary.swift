import AppKit
import ApplicationServices
import Foundation

struct Game: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundlePath: String
    var playSeconds: Double = 0
    /// Nom du fichier de bannière dans le dossier `banners`. Optionnel pour rester compatible avec l'ancien JSON.
    var bannerFileName: String?
}

/// Bibliothèque persistée en JSON dans Application Support.
@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []

    static let supportDir: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let fileURL = GameLibrary.supportDir.appendingPathComponent("games.json")
    private let bannersDir = GameLibrary.supportDir.appendingPathComponent("banners", isDirectory: true)

    init() { load() }

    func add(appURL: URL) {
        guard appURL.pathExtension == "app" else { return }
        let name = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        guard !games.contains(where: { $0.bundlePath == appURL.path }) else { return }
        games.append(Game(name: name, bundlePath: appURL.path))
        save()
    }

    func remove(_ game: Game) {
        games.removeAll { $0.id == game.id }
        save()
    }

    /// Copie l'image choisie dans le dossier de Lumen et l'associe au jeu.
    func setBanner(from source: URL, for game: Game) {
        guard let idx = games.firstIndex(where: { $0.id == game.id }) else { return }
        try? FileManager.default.createDirectory(at: bannersDir, withIntermediateDirectories: true)
        let fileName = "\(game.id.uuidString).\(source.pathExtension.lowercased())"
        let dest = bannersDir.appendingPathComponent(fileName)
        if let old = games[idx].bannerFileName, old != fileName {
            try? FileManager.default.removeItem(at: bannersDir.appendingPathComponent(old))
        }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            games[idx].bannerFileName = fileName
            save()
        } catch {
            NSLog("Lumen: copie de bannière impossible: \(error)")
        }
    }

    func banner(for game: Game) -> NSImage? {
        guard let name = game.bannerFileName else { return nil }
        return NSImage(contentsOf: bannersDir.appendingPathComponent(name))
    }

    /// Lance l'app puis tente de la passer en plein écran via l'API d'accessibilité.
    func launch(_ game: Game) {
        let url = URL(fileURLWithPath: game.bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            guard let app, error == nil else { return }
            Task { @MainActor in await self.enterFullscreen(pid: app.processIdentifier) }
        }
    }

    func icon(for game: Game) -> NSImage {
        NSWorkspace.shared.icon(forFile: game.bundlePath)
    }

    private func enterFullscreen(pid: pid_t) async {
        // Demande l'autorisation Accessibilité la première fois (Réglages > Confidentialité > Accessibilité).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let axApp = AXUIElementCreateApplication(pid)
        // La fenêtre peut mettre quelques secondes à apparaître.
        for _ in 0..<60 {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement], let window = windows.first {
                AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue)
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Game].self, from: data) else { return }
        games = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
