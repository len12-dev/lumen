import AppKit
import SwiftUI

/// Actions focusables de la page détail, dans l'ordre gauche → droite.
enum DetailAction: Int, CaseIterable {
    case start, edit
}

/// Page détail d'un jeu : Démarrer (focus par défaut), titre et sous-titre à droite, affiche et deux bannières.
/// Les tailles découlent de la hauteur disponible : l'affiche garde son 2:3, les bannières leur 21:9.
struct GameDetailView: View {
    let game: Game
    let focus: DetailAction
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.uiScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let topPad = 90 * scale
            let headerHeight = 150 * scale
            let footerHeight = 50 * scale
            let available = max(geo.size.height - topPad - headerHeight - footerHeight, 200)
            let posterHeight = min(available, geo.size.height * 0.8)
            let posterWidth = posterHeight * 2 / 3
            let gap = 20 * scale
            let bannerHeight = (posterHeight - gap) / 2
            let bannerWidth = bannerHeight * 21 / 9

            VStack(alignment: .leading, spacing: 32 * scale) {
                HStack(alignment: .top) {
                    actions
                    Spacer()
                    header
                }
                HStack(alignment: .top, spacing: 36 * scale) {
                    poster
                        .frame(width: posterWidth, height: posterHeight)
                    VStack(spacing: gap) {
                        Artwork(image: library.artwork(.banner, for: game), fallback: game.name)
                            .frame(width: bannerWidth, height: bannerHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                        Artwork(image: library.artwork(.banner2, for: game), fallback: game.name)
                            .frame(width: bannerWidth, height: bannerHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                Text("Stick / Croix : choisir et valider   ·   Gauche / Droite : choisir   ·   Rond : retour")
                    .font(.system(size: 12 * scale))
                    .opacity(0.6)
            }
            .padding(.horizontal, 60 * scale)
            .padding(.top, topPad)
            .padding(.bottom, 24 * scale)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Haut

    private var actions: some View {
        HStack(spacing: 16 * scale) {
            FocusButton(title: "Démarrer", symbol: "play.fill", focused: focus == .start, prominent: true)
            FocusButton(title: "Modifier", symbol: "pencil", focused: focus == .edit, prominent: false)
        }
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: 8 * scale) {
            Text(game.name)
                .font(.system(size: 56 * scale, weight: .bold))
                .multilineTextAlignment(.trailing)
            Text(game.subtitle)
                .font(.system(size: 22 * scale))
                .opacity(0.8)
        }
    }

    private var poster: some View {
        Artwork(image: library.artwork(.poster, for: game), fallback: game.name)
            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
            .shadow(radius: 20 * scale)
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
    @Environment(\.uiScale) private var scale

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 22 * scale, weight: .semibold))
            .padding(.horizontal, 28 * scale)
            .padding(.vertical, 14 * scale)
            .background(
                RoundedRectangle(cornerRadius: 12 * scale)
                    .fill(focused ? Color.white : Color.white.opacity(prominent ? 0.2 : 0.1))
            )
            .foregroundStyle(focused ? Color.black : Color.white)
            .scaleEffect(focused ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
