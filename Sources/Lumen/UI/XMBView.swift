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

    /// Éléments de la catégorie courante. Le bouton « Ajouter » est toujours en tête pour Jeux.
    private var items: [XMBItem] {
        switch category {
        case .games:
            return [XMBItem(id: "add", title: "+ Ajouter une application", symbol: "plus.circle", icon: nil)]
                + library.games.map { XMBItem(id: $0.id.uuidString, title: $0.name, symbol: nil, icon: library.icon(for: $0)) }
        default:
            return [XMBItem(id: "soon", title: "Bientôt disponible", symbol: "clock", icon: nil)]
        }
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

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = index == itemIndex
                HStack(spacing: 16) {
                    if let icon = item.icon {
                        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                    } else if let symbol = item.symbol {
                        Image(systemName: symbol).font(.system(size: 26)).frame(width: 40, height: 40)
                    }
                    Text(item.title)
                        .font(.system(size: selected ? 28 : 22, weight: selected ? .semibold : .regular))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? Color.white.opacity(0.18) : Color.clear)
                )
                .opacity(selected ? 1 : 0.6)
                .animation(.easeOut(duration: 0.15), value: itemIndex)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Croix / Entrée : valider   ·   Rond / Échap : retour   ·   Guide : overlay")
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
        case .down: itemIndex = min(items.count - 1, itemIndex + 1)
        case .confirm: confirm()
        case .back, .guide: break   // Guide : overlay, traité au jalon 2
        }
    }

    private func confirm() {
        guard category == .games, itemIndex < items.count else { return }
        if itemIndex == 0 {
            pickApp()
        } else {
            library.launch(library.games[itemIndex - 1])
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

struct XMBItem: Identifiable {
    let id: String
    let title: String
    let symbol: String?
    let icon: NSImage?
}
