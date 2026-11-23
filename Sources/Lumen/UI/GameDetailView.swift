import AppKit
import SwiftUI

/// Actions focusables de la page détail, dans l'ordre gauche → droite.
enum DetailAction: Int, CaseIterable {
    case start, edit
}

/// Page détail d'un jeu : Démarrer (focus par défaut), titre et sous-titre à droite, affiche et deux bannières.
struct GameDetailView: View {
    let game: Game
    let focus: DetailAction
    @EnvironmentObject private var library: GameLibrary

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.03, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .top) {
                    actions
                    Spacer()
                    header
                }
                HStack(alignment: .top, spacing: 36) {
                    poster
                    banners
                }
                Spacer(minLength: 0)
                Text("Croix / Entrée : valider   ·   Gauche / Droite : choisir   ·   Rond / Échap : retour")
                    .font(.caption)
                    .opacity(0.6)
            }
            .padding(.horizontal, 60)
            .padding(.top, 90)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Haut

    private var actions: some View {
        HStack(spacing: 16) {
            FocusButton(title: "Démarrer", symbol: "play.fill", focused: focus == .start, prominent: true)
            FocusButton(title: "Modifier", symbol: "pencil", focused: focus == .edit, prominent: false)
        }
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(game.name)
                .font(.system(size: 56, weight: .bold))
                .multilineTextAlignment(.trailing)
            Text(game.subtitle)
                .font(.title3)
                .opacity(0.8)
        }
    }

    // MARK: - Visuels

    private var poster: some View {
        Artwork(image: library.artwork(.poster, for: game), fallback: game.name)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(width: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 20)
    }

    private var banners: some View {
        VStack(spacing: 20) {
            Artwork(image: library.artwork(.banner, for: game), fallback: game.name)
                .aspectRatio(21.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Artwork(image: library.artwork(.banner2, for: game), fallback: game.name)
                .aspectRatio(21.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: 1000)
    }
}

/// Image de visuel avec repli dégradé + nom quand aucun fichier n'est défini.
struct Artwork: View {
    let image: NSImage?
    let fallback: String

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(fallback)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .opacity(0.7)
            }
        }
        .clipped()
    }
}

/// Bouton qui affiche visuellement le focus (manette ou clavier).
struct FocusButton: View {
    let title: String
    let symbol: String
    let focused: Bool
    let prominent: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 22, weight: .semibold))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(focused ? Color.white : Color.white.opacity(prominent ? 0.2 : 0.1))
            )
            .foregroundStyle(focused ? Color.black : Color.white)
            .scaleEffect(focused ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
