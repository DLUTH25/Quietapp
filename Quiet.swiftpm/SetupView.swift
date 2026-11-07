import SwiftUI

/// First-run screen: enter your TikTok developer app keys, then connect your account.
@MainActor
struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    @State private var clientKey = ""
    @State private var clientSecret = ""
    @State private var redirectURI = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quiet")
                            .font(.system(size: 40, weight: .light, design: .serif))
                        Text("Post to TikTok without numbers, feeds or comments.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Client key", text: $clientKey)
                    SecureField("Client secret", text: $clientSecret)
                    TextField("Redirect URI", text: $redirectURI, prompt: Text("https://…/callback.html"))
                        .keyboardType(.URL)
                } header: {
                    Text("TikTok app keys")
                } footer: {
                    Text("From your app on developers.tiktok.com. The redirect URI must match the one registered there exactly. See the README for step-by-step setup.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Connect TikTok") }
                            Spacer()
                        }
                    }
                    .disabled(working || !canConnect)
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear {
            if let config = model.config {
                clientKey = config.clientKey
                clientSecret = config.clientSecret
                redirectURI = config.redirectURI
            }
        }
    }

    private var canConnect: Bool {
        !clientKey.trimmed.isEmpty && !clientSecret.trimmed.isEmpty && URL(string: redirectURI.trimmed)?.scheme == "https"
    }

    private func connect() async {
        working = true
        errorText = nil
        defer { working = false }
        model.saveConfig(TikTokConfig(
            clientKey: clientKey.trimmed,
            clientSecret: clientSecret.trimmed,
            redirectURI: redirectURI.trimmed
        ))
        do {
            try await model.connect()
        } catch is CancellationError {
            // User closed the sign-in sheet.
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
