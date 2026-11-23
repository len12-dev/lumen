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

/// Navigation XMB : catégories en ligne horizontale, éléments en colonne.
/// Un jeu ouvre sa page détail ; Démarrer y lance l'app.
struct XMBView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var input: ControllerInput

    @State private var categoryIndex = 0
    @State private var itemIndex = 0
    @State private var detailGameID: UUID?
    @State private var detailFocus: DetailAction = .start
    @State private var editingGameID: UUID?
    /// Échelle courante, mise à jour quand la fenêtre change de taille.
    @State private var scale: CGFloat = 1

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
                    GameDetailView(game: game, focus: detailFocus)
                } else {
                    browser
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
                .animation(.easeOut(duration: 0.2), value: categoryIndex)
            }
        }
        .padding(.horizontal, 40 * scale)
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
        .animation(.easeOut(duration: 0.15), value: itemIndex)
    }

    /// Carte bannière 21:9 d'un jeu.
    private func bannerCard(game: Game, selected: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(image: library.artwork(.banner, for: game), fallback: game.name)
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
        .animation(.easeOut(duration: 0.15), value: itemIndex)
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

        switch action {
        case .left: categoryIndex = max(0, categoryIndex - 1); itemIndex = 0
        case .right: categoryIndex = min(Category.allCases.count - 1, categoryIndex + 1); itemIndex = 0
        case .prevTab: categoryIndex = max(0, categoryIndex - 1); itemIndex = 0
        case .nextTab: categoryIndex = min(Category.allCases.count - 1, categoryIndex + 1); itemIndex = 0
        case .up: itemIndex = max(0, itemIndex - 1)
        case .down: itemIndex = min(itemCount - 1, itemIndex + 1)
        case .confirm: openSelection()
        case .banner: editSelectedGame()
        case .back, .guide: break   // Guide : overlay, jalon 2
        }
    }

    private func handleDetail(_ action: InputAction, game: Game) {
        switch action {
        case .left: detailFocus = .start
        case .right: detailFocus = .edit
        case .confirm:
            switch detailFocus {
            case .start: library.launch(game)
            case .edit: editingGameID = game.id
            }
        case .banner: editingGameID = game.id
        case .back: detailGameID = nil; detailFocus = .start
        case .up, .down, .prevTab, .nextTab, .guide: break
        }
    }

    private func openSelection() {
        guard category == .games else { return }
        if itemIndex == 0 {
            pickApp()
        } else if itemIndex - 1 < library.games.count {
            detailGameID = library.games[itemIndex - 1].id
            detailFocus = .start
        }
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
