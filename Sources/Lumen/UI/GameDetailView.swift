import AppKit
import SwiftUI

/// Actions de la rangée du haut de la page détail.
enum DetailAction: Int, CaseIterable {
    case start, edit
}

/// Rangées focusables de la page détail : les boutons, ou la galerie en dessous.
enum DetailRow {
    case actions, gallery
}

/// Page « À propos du jeu » : boutons en haut, titre et sous-titre à droite,
/// affiche à gauche et galerie illimitée défilante à droite.
/// Les tailles découlent de la hauteur de la fenêtre.
struct GameDetailView: View {
    let game: Game
    let row: DetailRow
    let button: DetailAction
    let galleryIndex: Int

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
            let thumbHeight = posterHeight * 0.55
            let thumbWidth = thumbHeight * 21 / 9

            VStack(alignment: .leading, spacing: 32 * scale) {
                HStack(alignment: .top) {
                    actions
                    Spacer()
                    header
                }
                HStack(alignment: .top, spacing: 36 * scale) {
                    poster
                        .frame(width: posterWidth, height: posterHeight)
                    gallery(thumbWidth: thumbWidth, thumbHeight: thumbHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                Text("Stick : naviguer   ·   Croix : valider   ·   Haut / Bas : boutons ↔ galerie   ·   Rond : retour")
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
            FocusButton(title: "Démarrer", symbol: "play.fill",
                        focused: row == .actions && button == .start, prominent: true)
            FocusButton(title: "Modifier", symbol: "pencil",
                        focused: row == .actions && button == .edit, prominent: false)
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
        Artwork(url: library.artURL(.poster, for: game), fallback: game.name)
            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
            .shadow(radius: 20 * scale)
    }

    // MARK: - Galerie

    @ViewBuilder
    private func gallery(thumbWidth: CGFloat, thumbHeight: CGFloat) -> some View {
        if game.galleryFileNames.isEmpty {
            Text("Ajoutez des images dans « Modifier »")
                .font(.system(size: 18 * scale))
                .opacity(0.5)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20 * scale) {
                        ForEach(Array(game.galleryFileNames.enumerated()), id: \.offset) { index, fileName in
                            let focused = row == .gallery && index == galleryIndex
                            Artwork(url: library.imageURL(named: fileName), fallback: game.name)
                                .frame(width: thumbWidth, height: thumbHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14 * scale)
                                        .stroke(.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
                                )
                                .scaleEffect(focused ? 1.04 : 1)
                                .opacity(row == .gallery && !focused ? 0.7 : 1)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 8 * scale)
                }
                .onChange(of: galleryIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
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
