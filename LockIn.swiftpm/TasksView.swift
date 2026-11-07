import SwiftUI

@MainActor
struct TasksView: View {
    @EnvironmentObject private var store: Store
    @State private var adding = false
    @State private var editing: TaskItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Priority.allCases) { priority in
                    let items = store.state.tasks.filter { $0.priority == priority }
                    Section {
                        if items.isEmpty {
                            Text("Nothing yet. Tap + to add one.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(items) { task in
                            Button {
                                editing = task
                            } label: {
                                HStack {
                                    Text(task.title).foregroundStyle(Color.primary)
                                    Spacer()
                                    if task.oneTime {
                                        Text("One-time")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            store.delete(offsets.map { items[$0].id })
                        }
                    } header: {
                        Label(priority.label, systemImage: priority.icon)
                    } footer: {
                        Text(priority == .must
                             ? "On every list, no matter what."
                             : "Picked at random to fill the rest of the list. Ones you haven't had in a while come up more often.")
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $adding) { TaskEditor(task: nil) }
            .sheet(item: $editing) { task in TaskEditor(task: task) }
        }
    }
}

@MainActor
struct TaskEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private let original: TaskItem?
    @State private var title: String
    @State private var priority: Priority
    @State private var oneTime: Bool
    @FocusState private var focused: Bool

    init(task: TaskItem?) {
        original = task
        _title = State(initialValue: task?.title ?? "")
        _priority = State(initialValue: task?.priority ?? .maybe)
        _oneTime = State(initialValue: task?.oneTime ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to do?", text: $title)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("One-time", isOn: $oneTime)
                } footer: {
                    Text("One-time tasks are removed after you check them off.")
                }
                if let original {
                    Section {
                        Button("Delete", role: .destructive) {
                            store.delete([original.id])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmed.isEmpty)
                }
            }
            .onAppear {
                if original == nil { focused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !title.trimmed.isEmpty else { return }
        var task = original ?? TaskItem(title: "", priority: .maybe)
        task.title = title.trimmed
        task.priority = priority
        task.oneTime = oneTime
        store.upsert(task)
        dismiss()
    }
}
