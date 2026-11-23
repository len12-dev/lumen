import SwiftUI

/// Catégorie Musique : lecture Spotify en cours et contrôles au stick.
/// `focus` est l'index du contrôle sélectionné (0 = précédent, 1 = lecture/pause, 2 = suivant ;
/// quand Spotify n'est pas connecté, 0 = Connecter).
struct MusicView: View {
    let focus: Int
    @EnvironmentObject private var spotify: SpotifyService
    @Environment(\.uiScale) private var scale

    static func controlCount(for state: SpotifyState) -> Int {
        state == .connected ? 3 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24 * scale) {
            switch spotify.state {
            case .notConfigured:
                notConfigured
            case .disconnected:
                connectPrompt(label: "Connecter Spotify")
            case .error(let message):
                Text(message)
                    .font(.system(size: 18 * scale))
                    .foregroundStyle(.orange)
                connectPrompt(label: "Reconnecter Spotify")
            case .connected:
                nowPlayingCard
                controls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Text("Spotify n'est pas configuré")
                .font(.system(size: 22 * scale, weight: .semibold))
            Text("Ajoute ton Client ID dans spotify.json, dans le dossier Application Support/Lumen.")
                .font(.system(size: 16 * scale))
                .opacity(0.7)
        }
    }

    private func connectPrompt(label: String) -> some View {
        MusicButton(title: label, symbol: "link", focused: focus == 0)
    }

    private var nowPlayingCard: some View {
        HStack(alignment: .center, spacing: 36 * scale) {
            Group {
                if let url = spotify.nowPlaying?.albumArtURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.1)
                    }
                } else {
                    Color.white.opacity(0.1)
                        .overlay(Image(systemName: "music.note").font(.system(size: 60 * scale)).opacity(0.5))
                }
            }
            .frame(width: 320 * scale, height: 320 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 16 * scale))

            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(spotify.nowPlaying?.title ?? "Rien ne joue")
                    .font(.system(size: 34 * scale, weight: .bold))
                    .lineLimit(2)
                Text(spotify.nowPlaying?.artists ?? "Lance un morceau sur Spotify")
                    .font(.system(size: 22 * scale))
                    .opacity(0.8)
                progressBar
            }
        }
    }

    private var progressBar: some View {
        let fraction = progressFraction
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6 * scale)
        .frame(maxWidth: 640 * scale)
    }

    private var progressFraction: CGFloat {
        guard let np = spotify.nowPlaying, np.durationMs > 0 else { return 0 }
        return min(1, CGFloat(np.progressMs) / CGFloat(np.durationMs))
    }

    private var controls: some View {
        HStack(spacing: 20 * scale) {
            MusicButton(title: "Précédent", symbol: "backward.fill", focused: focus == 0)
            MusicButton(title: spotify.nowPlaying?.isPlaying == true ? "Pause" : "Lecture",
                        symbol: spotify.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                        focused: focus == 1)
            MusicButton(title: "Suivant", symbol: "forward.fill", focused: focus == 2)
        }
    }
}

struct MusicButton: View {
    let title: String
    let symbol: String
    let focused: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 20 * scale, weight: .semibold))
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 12 * scale)
            .background(RoundedRectangle(cornerRadius: 12 * scale).fill(focused ? Color.white : Color.white.opacity(0.12)))
            .foregroundStyle(focused ? Color.black : Color.white)
            .scaleEffect(focused ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
