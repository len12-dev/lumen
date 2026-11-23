import AppKit
import SwiftUI

/// Feuille pour modifier les informations et les visuels d'un jeu.
struct GameEditSheet: View {
    let gameID: UUID
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var studio = ""
    @State private var year = ""
    @State private var rating = ""
    @State private var loaded = false

    private var game: Game? { library.game(id: gameID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Modifier le jeu").font(.title2.bold())

            Form {
                TextField("Studio", text: $studio)
                TextField("Année de sortie", text: $year)
                TextField("Classification (ex. PEGI 12)", text: $rating)
            }

            Divider()
            Text("Visuels").font(.headline)
            HStack {
                pickButton("Affiche…") { library.setArtwork(from: $0, kind: .poster, for: gameID) }
                pickButton("Bannière de liste…") { library.setArtwork(from: $0, kind: .card, for: gameID) }
            }

            Divider()
            HStack {
                Text("Galerie (\(game?.galleryFileNames.count ?? 0))").font(.headline)
                Spacer()
                Button("Ajouter des images…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        library.addGalleryImages(from: panel.urls, for: gameID)
                    }
                }
            }
            if let game, !game.galleryFileNames.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(game.galleryFileNames.enumerated()), id: \.offset) { index, fileName in
                            HStack {
                                Text("Image \(index + 1)")
                                Spacer()
                                Button("Retirer") {
                                    library.removeGalleryImage(fileName, for: gameID)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    library.updateInfo(id: gameID,
                                       studio: studio,
                                       releaseYear: Int(year.trimmingCharacters(in: .whitespaces)),
                                       rating: rating)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            guard !loaded, let game else { return }
            studio = game.studio ?? ""
            year = game.releaseYear.map(String.init) ?? ""
            rating = game.rating ?? ""
            loaded = true
        }
    }

    private func pickButton(_ title: String, onPick: @escaping (URL) -> Void) -> some View {
        Button(title) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                onPick(url)
            }
        }
    }
}
