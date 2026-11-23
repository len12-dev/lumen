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
struct XMBView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var input: ControllerInput

    @State private var categoryIndex = 0
    @State private var itemIndex = 0

    private var category: Category { Category.allCases[categoryIndex] }

    /// Nombre d'éléments de la catégorie courante (la case 0 est « Ajouter » dans Jeux).
    private var itemCount: Int {
        category == .games ? library.games.count + 1 : 1
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer().frame(height: 90)
                categoryBar
                Spacer().frame(height: 48)
                HStack(alignment: .top, spacing: 0) {
                    Spacer()
                    itemList
                        .frame(maxWidth: 760)   // lisible même sur 3440×1440
                    Spacer()
                }
                Spacer()
                footer
            }
        }
        .foregroundStyle(.white)
        .onChange(of: input.actionID) {
            handle(input.lastAction)
        }
    }

    // MARK: - Fond

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.03, blue: 0.10)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Catégories

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(Category.allCases.enumerated()), id: \.element.id) { index, cat in
                let selected = index == categoryIndex
                VStack(spacing: 10) {
                    Image(systemName: cat.symbol)
                        .font(.system(size: selected ? 64 : 40))
                        .frame(width: 96, height: 96)
                        .opacity(selected ? 1 : 0.45)
                    Text(cat.rawValue)
                        .font(.system(size: 18, weight: selected ? .semibold : .regular))
                        .opacity(selected ? 1 : 0.0)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.2), value: categoryIndex)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Éléments

    @ViewBuilder
    private var itemList: some View {
        if category == .games {
            VStack(alignment: .leading, spacing: 14) {
                addRow(selected: itemIndex == 0)
                ForEach(Array(library.games.enumerated()), id: \.element.id) { index, game in
                    bannerCard(game: game, selected: itemIndex == index + 1)
                }
            }
        } else {
            textRow(title: "Bientôt disponible", symbol: "clock", selected: true)
        }
    }

    private func addRow(selected: Bool) -> some View {
        textRow(title: "+ Ajouter une application", symbol: "plus.circle", selected: selected)
    }

    private func textRow(title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 26)).frame(width: 40, height: 40)
            Text(title).font(.system(size: selected ? 28 : 22, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.white.opacity(0.18) : .clear))
        .opacity(selected ? 1 : 0.6)
        .animation(.easeOut(duration: 0.15), value: itemIndex)
    }

    /// Carte bannière 21:9 d'un jeu. Sans bannière, un dégradé avec le nom.
    private func bannerCard(game: Game, selected: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let banner = library.banner(for: game) {
                Image(nsImage: banner).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(nsImage: library.icon(for: game))
                    .resizable().scaledToFit().padding(24).opacity(0.5)
            }
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            Text(game.name)
                .font(.system(size: selected ? 26 : 20, weight: .semibold))
                .padding(16)
        }
        .frame(height: selected ? 200 : 150)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
        .opacity(selected ? 1 : 0.6)
        .scaleEffect(selected ? 1 : 0.97)
        .animation(.easeOut(duration: 0.15), value: itemIndex)
    }

    private var footer: some View {
        HStack {
            Text("Croix / Entrée : valider   ·   Y / B : changer la bannière   ·   Rond / Échap : retour   ·   Guide : overlay")
                .font(.caption)
                .opacity(0.6)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
    }

    // MARK: - Navigation

    private func handle(_ action: InputAction?) {
        guard let action else { return }
        switch action {
        case .left: categoryIndex = max(0, categoryIndex - 1); itemIndex = 0
        case .right: categoryIndex = min(Category.allCases.count - 1, categoryIndex + 1); itemIndex = 0
        case .up: itemIndex = max(0, itemIndex - 1)
        case .down: itemIndex = min(itemCount - 1, itemIndex + 1)
        case .confirm: confirm()
        case .banner: changeBanner()
        case .back, .guide: break   // Guide : overlay, jalon 2
        }
    }

    private func confirm() {
        guard category == .games else { return }
        if itemIndex == 0 {
            pickApp()
        } else if itemIndex - 1 < library.games.count {
            library.launch(library.games[itemIndex - 1])
        }
    }

    private func changeBanner() {
        guard category == .games, itemIndex > 0, itemIndex - 1 < library.games.count else { return }
        let game = library.games[itemIndex - 1]
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choisir une bannière pour \(game.name)"
        if panel.runModal() == .OK, let url = panel.url {
            library.setBanner(from: url, for: game)
        }
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
