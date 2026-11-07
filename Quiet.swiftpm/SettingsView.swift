import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let name = model.creator?.creatorNickname ?? model.creator?.creatorUsername {
                        LabeledContent("Posting as", value: name)
                    }
                    Button("Disconnect TikTok", role: .destructive) {
                        Task {
                            await model.disconnect()
                            dismiss()
                        }
                    }
                }

                Section {
                    Text("Quiet never asks TikTok for views, likes, comments or follower counts, and it has no feed. You post, then you put the phone down.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
