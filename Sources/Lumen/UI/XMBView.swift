import AppKit
import SwiftUI

enum Category: String, CaseIterable, Identifiable {
    case games = "Jeux", music = "Musique", social = "Social", settings = "Réglages"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .games: "gamecontroller.fill"
        case .music: "music.note"
        case .social: "person.2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Courbes communes à toutes les transitions de l'interface.
enum LumenMotion {
    static let switchSpring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    static let page = Animation.easeInOut(duration: 0.35)
    static let focus = Animation.easeOut(duration: 0.18)
}

/// Navigation XMB : catégories en ligne horizontale, éléments en colonne.
/// Un jeu ouvre sa page « À propos » ; Démarrer y lance l'app.
struct XMBView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var input: ControllerInput
    @EnvironmentObject private var spotify: SpotifyService

    @State private var categoryIndex = 0
    @State private var itemIndex = 0
    @State private var detailGameID: UUID?
    @State private var detailRow: DetailRow = .actions
    @State private var detailButton: DetailAction = .start
    @State private var galleryIndex = 0
    @State private var editingGameID: UUID?
    /// Échelle courante, mise à jour quand la fenêtre change de taille.
    @State private var scale: CGFloat = 1
    /// Contrôle sélectionné dans la catégorie Musique.
    @State private var musicFocus = 0

    private var category: Category { Category.allCases[categoryIndex] }

    private var detailGame: Game? { detailGameID.flatMap { library.game(id: $0) } }

    /// Nombre d'éléments de la catégorie courante (la case 0 est « Ajouter » dans Jeux).
    private var itemCount: Int {
        category == .games ? library.games.count + 1 : 1
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LumenBackground()
                if let game = detailGame {
                    GameDetailView(game: game, row: detailRow, button: detailButton, galleryIndex: galleryIndex)
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                } else {
                    browser
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .environment(\.uiScale, scale)
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { scale = LumenLayout.scale(for: geo.size) }
            .onChange(of: geo.size) { newSize in
                scale = LumenLayout.scale(for: newSize)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: input.actionID) {
            handle(input.lastAction)
        }
        .sheet(isPresented: Binding(
            get: { editingGameID != nil },
            set: { if !$0 { editingGameID = nil } }
        )) {
            if let id = editingGameID {
                GameEditSheet(gameID: id)
                    .environmentObject(library)
            }
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            categoryBar
                .padding(.top, 90 * scale)
            Spacer().frame(height: 48 * scale)
            HStack(alignment: .top, spacing: 0) {
                Spacer()
                itemList
                    .id(categoryIndex)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(maxWidth: 760 * scale)   // lisible même sur 3440×1440
                Spacer()
            }
            Spacer()
            footer
        }
    }

    // MARK: - Catégories

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(Category.allCases.enumerated()), id: \.element.id) { index, cat in
                let selected = index == categoryIndex
                VStack(spacing: 10 * scale) {
                    Image(systemName: cat.symbol)
                        .font(.system(size: (selected ? 64 : 40) * scale))
                        .frame(width: 96 * scale, height: 96 * scale)
                        .opacity(selected ? 1 : 0.45)
                    Text(cat.rawValue)
                        .font(.system(size: 18 * scale, weight: selected ? .semibold : .regular))
                        .opacity(selected ? 1 : 0.0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 40 * scale)
        .animation(LumenMotion.switchSpring, value: categoryIndex)
    }

    // MARK: - Éléments

    @ViewBuilder
    private var itemList: some View {
        if category == .games {
            VStack(alignment: .leading, spacing: 14 * scale) {
                textRow(title: "+ Ajouter une application", symbol: "plus.circle", selected: itemIndex == 0)
                ForEach(Array(library.games.enumerated()), id: \.element.id) { index, game in
                    bannerCard(game: game, selected: itemIndex == index + 1)
                }
            }
        } else if category == .music {
            MusicView(focus: musicFocus)
        } else {
            textRow(title: "Bientôt disponible", symbol: "clock", selected: true)
        }
    }

    private func textRow(title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 16 * scale) {
            Image(systemName: symbol).font(.system(size: 26 * scale)).frame(width: 40 * scale, height: 40 * scale)
            Text(title).font(.system(size: (selected ? 28 : 22) * scale, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 20 * scale)
        .padding(.vertical, 12 * scale)
        .background(RoundedRectangle(cornerRadius: 12 * scale).fill(selected ? Color.white.opacity(0.18) : .clear))
        .opacity(selected ? 1 : 0.6)
        .animation(LumenMotion.focus, value: itemIndex)
    }

    /// Carte de la liste : la bannière de liste du jeu, distincte de sa page « À propos ».
    private func bannerCard(game: Game, selected: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(image: library.artwork(.card, for: game), fallback: game.name)
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            Text(game.name)
                .font(.system(size: (selected ? 26 : 20) * scale, weight: .semibold))
                .padding(16 * scale)
        }
        .frame(height: (selected ? 200 : 150) * scale)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).stroke(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
        .opacity(selected ? 1 : 0.6)
        .scaleEffect(selected ? 1 : 0.97)
        .animation(LumenMotion.focus, value: itemIndex)
    }

    private var footer: some View {
        HStack {
            Text("Stick / Croix : naviguer et ouvrir   ·   L1 / R1 : catégories   ·   Y : modifier   ·   Rond : retour   ·   Guide : overlay")
                .font(.system(size: 12 * scale))
                .opacity(0.6)
            Spacer()
        }
        .padding(.horizontal, 40 * scale)
        .padding(.bottom, 24 * scale)
    }

    // MARK: - Navigation

    private func handle(_ action: InputAction?) {
        guard let action, editingGameID == nil else { return }

        if let game = detailGame {
            handleDetail(action, game: game)
            return
        }

        // Dans Musique, gauche/droite parcourent les contrôles ; L1/R1 changent de catégorie.
        if category == .music, action == .left || action == .right {
            let count = MusicView.controlCount(for: spotify.state)
            musicFocus = action == .left ? max(0, musicFocus - 1) : min(count - 1, musicFocus + 1)
            return
        }

        withAnimation(LumenMotion.switchSpring) {
            switch action {
            case .left, .prevTab: categoryIndex = max(0, categoryIndex - 1); itemIndex = 0; musicFocus = 0
            case .right, .nextTab: categoryIndex = min(Category.allCases.count - 1, categoryIndex + 1); itemIndex = 0; musicFocus = 0
            case .up: itemIndex = max(0, itemIndex - 1)
            case .down: itemIndex = min(itemCount - 1, itemIndex + 1)
            case .confirm:
                if category == .music { musicConfirm() } else { openSelection() }
            case .banner: editSelectedGame()
            case .back, .guide: break   // Guide : overlay, jalon 2
            }
        }
    }

    private func handleDetail(_ action: InputAction, game: Game) {
        let galleryCount = game.galleryFileNames.count
        withAnimation(LumenMotion.focus) {
            switch action {
            case .left:
                if detailRow == .actions { detailButton = .start }
                else { galleryIndex = max(0, galleryIndex - 1) }
            case .right:
                if detailRow == .actions { detailButton = .edit }
                else if galleryCount > 0 { galleryIndex = min(galleryCount - 1, galleryIndex + 1) }
            case .down:
                if detailRow == .actions, galleryCount > 0 {
                    detailRow = .gallery
                    galleryIndex = 0
                }
            case .up:
                if detailRow == .gallery { detailRow = .actions }
            case .confirm:
                if detailRow == .actions {
                    switch detailButton {
                    case .start: library.launch(game)
                    case .edit: editingGameID = game.id
                    }
                }
            case .banner:
                editingGameID = game.id
            case .back:
                if detailRow == .gallery {
                    detailRow = .actions
                } else {
                    closeDetail()
                }
            case .prevTab, .nextTab, .guide:
                break
            }
        }
    }

    private func musicConfirm() {
        switch spotify.state {
        case .connected:
            switch musicFocus {
            case 0: spotify.previous()
            case 1: spotify.togglePlayPause()
            default: spotify.next()
            }
        case .notConfigured:
            break
        case .disconnected, .error:
            spotify.connect()
        }
    }

    private func openSelection() {
        guard category == .games else { return }
        if itemIndex == 0 {
            pickApp()
        } else if itemIndex - 1 < library.games.count {
            openDetail(library.games[itemIndex - 1])
        }
    }

    private func openDetail(_ game: Game) {
        detailRow = .actions
        detailButton = .start
        galleryIndex = 0
        withAnimation(LumenMotion.page) {
            detailGameID = game.id
        }
    }

    private func closeDetail() {
        withAnimation(LumenMotion.page) {
            detailGameID = nil
        }
        detailRow = .actions
        detailButton = .start
    }

    private func editSelectedGame() {
        guard category == .games, itemIndex > 0, itemIndex - 1 < library.games.count else { return }
        editingGameID = library.games[itemIndex - 1].id
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            library.add(appURL: url)
        }
    }
}
