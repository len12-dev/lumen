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
                pickButton("Affiche…", .poster)
                pickButton("Bannière 1…", .banner)
                pickButton("Bannière 2…", .banner2)
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
        .frame(width: 520)
        .onAppear {
            guard !loaded, let game = library.game(id: gameID) else { return }
            studio = game.studio ?? ""
            year = game.releaseYear.map(String.init) ?? ""
            rating = game.rating ?? ""
            loaded = true
        }
    }

    private func pickButton(_ title: String, _ kind: ArtKind) -> some View {
        Button(title) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                library.setArtwork(from: url, kind: kind, for: gameID)
            }
        }
    }
}
