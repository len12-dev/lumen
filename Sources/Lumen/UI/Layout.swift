import SwiftUI

/// Échelle d'interface dérivée de la taille de la fenêtre.
/// 1.0 à 2560×1080 ; environ 1.33 à 3440×1440 ; bornée pour rester lisible.
enum LumenLayout {
    static func scale(for size: CGSize) -> CGFloat {
        min(max(min(size.height / 1080, size.width / 2560), 0.6), 1.8)
    }
}

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

/// Fond commun à tout l'écran.
struct LumenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.03, blue: 0.10)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
