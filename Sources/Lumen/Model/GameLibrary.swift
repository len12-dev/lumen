import AppKit
import Foundation
import SwiftUI

struct Game: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundlePath: String
    var playSeconds: Double = 0
}

/// Bibliothèque persistée en JSON dans Application Support.
@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("games.json")
    }()

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

    func launch(_ game: Game) {
        let url = URL(fileURLWithPath: game.bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func icon(for game: Game) -> NSImage {
        NSWorkspace.shared.icon(forFile: game.bundlePath)
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
