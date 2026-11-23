import SwiftUI

/// Réglages Spotify : saisie du Client ID (enregistré localement dans les préférences).
struct SpotifySettingsSheet: View {
    @EnvironmentObject private var spotify: SpotifyService
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = UserDefaults.standard.string(forKey: SpotifyConfig.defaultsKey) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spotify").font(.title2.bold())
            Text("Client ID de ton application Spotify. Redirect URI à enregistrer : http://127.0.0.1:8888/callback")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Client ID", text: $clientID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    SpotifyConfig.saveClientID(clientID)
                    spotify.reloadConfig()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
