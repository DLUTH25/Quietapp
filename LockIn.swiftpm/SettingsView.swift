import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Lock in for a", selection: $store.state.settings.period) {
                        ForEach(Period.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if store.state.settings.period == .day {
                        Stepper("Things per day: \(store.state.settings.dayCount)",
                                value: $store.state.settings.dayCount, in: 1...12)
                    } else {
                        Stepper("Things per week: \(store.state.settings.weekCount)",
                                value: $store.state.settings.weekCount, in: 1...40)
                    }
                } header: {
                    Text("Your list")
                } footer: {
                    Text("Must-dos always make the list, even if there are more of them than this number. Changes apply the next time you lock in.")
                }

                Section {
                    Toggle("Allow one reroll", isOn: $store.state.settings.allowReroll)
                } footer: {
                    Text("Lets you redraw a list once, but only before you've checked anything off. Turn it off to fully commit.")
                }

                Section {
                    Toggle("Remind me to lock in", isOn: $store.state.settings.reminderOn)
                    if store.state.settings.reminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(store.state.settings.period == .day
                         ? "A notification every morning."
                         : "A notification at the start of each week.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: store.state.settings) { _, _ in
                Task { await store.updateReminder() }
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let s = store.state.settings
                return Calendar.current.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.state.settings.reminderHour = parts.hour ?? 8
                store.state.settings.reminderMinute = parts.minute ?? 0
            }
        )
    }
}
