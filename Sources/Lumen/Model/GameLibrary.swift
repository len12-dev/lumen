import AppKit
import ApplicationServices
import Foundation

/// Visuels à emplacement unique. La galerie de la page détail est une liste à part.
enum ArtKind: CaseIterable {
    case poster, card

    var suffix: String {
        switch self {
        case .poster: "poster"
        case .card: "card"
        }
    }
}

struct Game: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundlePath: String
    var playSeconds: Double = 0
    var studio: String?
    var releaseYear: Int?
    /// Classification (ex. PEGI 12). Texte libre pour l'instant.
    var rating: String?
    /// Bannière affichée dans la liste de tous les jeux.
    var cardFileName: String?
    /// Affiche de la page « À propos du jeu ».
    var posterFileName: String?
    /// Images de la page « À propos du jeu » ; il n'y a pas de limite.
    var galleryFileNames: [String] = []

    // Champs de l'ancien format, lus seulement pour migrer les données.
    var bannerFileName: String?
    var banner2FileName: String?

    /// Ligne « Studio · Année · Classification », sans les champs vides.
    var subtitle: String {
        var parts: [String] = []
        if let studio, !studio.isEmpty { parts.append(studio) }
        if let releaseYear { parts.append(String(releaseYear)) }
        if let rating, !rating.isEmpty { parts.append(rating) }
        return parts.isEmpty ? "Informations à compléter" : parts.joined(separator: " · ")
    }
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
    private let artDir = GameLibrary.supportDir.appendingPathComponent("artwork", isDirectory: true)

    init() { load() }

    func game(id: UUID) -> Game? {
        games.first { $0.id == id }
    }

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

    /// Met à jour les informations textuelles d'un jeu.
    func updateInfo(id: UUID, studio: String?, releaseYear: Int?, rating: String?) {
        guard let idx = games.firstIndex(where: { $0.id == id }) else { return }
        games[idx].studio = studio?.trimmingCharacters(in: .whitespaces).nonEmpty
        games[idx].releaseYear = releaseYear
        games[idx].rating = rating?.trimmingCharacters(in: .whitespaces).nonEmpty
        save()
    }

    /// Remplace un visuel à emplacement unique (affiche ou bannière de liste).
    func setArtwork(from source: URL, kind: ArtKind, for id: UUID) {
        guard let idx = games.firstIndex(where: { $0.id == id }) else { return }
        let fileName = "\(id.uuidString)-\(kind.suffix).\(source.pathExtension.lowercased())"
        let key = keyPath(for: kind)
        if let old = games[idx][keyPath: key], old != fileName {
            removeFile(old)
        }
        guard copyFile(from: source, to: fileName) else { return }
        games[idx][keyPath: key] = fileName
        save()
    }

    /// Ajoute une ou plusieurs images à la galerie, sans limite.
    func addGalleryImages(from sources: [URL], for id: UUID) {
        guard let idx = games.firstIndex(where: { $0.id == id }) else { return }
        for source in sources {
            let fileName = "\(id.uuidString)-gallery-\(UUID().uuidString).\(source.pathExtension.lowercased())"
            if copyFile(from: source, to: fileName) {
                games[idx].galleryFileNames.append(fileName)
            }
        }
        save()
    }

    func removeGalleryImage(_ fileName: String, for id: UUID) {
        guard let idx = games.firstIndex(where: { $0.id == id }) else { return }
        games[idx].galleryFileNames.removeAll { $0 == fileName }
        removeFile(fileName)
        save()
    }

    func artwork(_ kind: ArtKind, for game: Game) -> NSImage? {
        guard let name = game[keyPath: keyPath(for: kind)] else { return nil }
        return image(named: name)
    }

    func image(named fileName: String) -> NSImage? {
        NSImage(contentsOf: artDir.appendingPathComponent(fileName))
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

    private func keyPath(for kind: ArtKind) -> WritableKeyPath<Game, String?> {
        switch kind {
        case .poster: \.posterFileName
        case .card: \.cardFileName
        }
    }

    @discardableResult
    private func copyFile(from source: URL, to fileName: String) -> Bool {
        try? FileManager.default.createDirectory(at: artDir, withIntermediateDirectories: true)
        let dest = artDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return true
        } catch {
            NSLog("Lumen: copie impossible: \(error)")
            return false
        }
    }

    private func removeFile(_ fileName: String) {
        try? FileManager.default.removeItem(at: artDir.appendingPathComponent(fileName))
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
              var decoded = try? JSONDecoder().decode([Game].self, from: data) else { return }
        // Migration : les anciennes bannières deviennent la bannière de liste et les premières images de la galerie.
        var migrated = false
        for i in decoded.indices {
            let legacy = [decoded[i].bannerFileName, decoded[i].banner2FileName].compactMap { $0 }
            if !legacy.isEmpty {
                if decoded[i].cardFileName == nil { decoded[i].cardFileName = legacy[0] }
                decoded[i].galleryFileNames.insert(contentsOf: legacy, at: 0)
                decoded[i].bannerFileName = nil
                decoded[i].banner2FileName = nil
                migrated = true
            }
        }
        games = decoded
        if migrated { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
