import SwiftUI
import UserNotifications

enum Priority: String, Codable, CaseIterable, Identifiable {
    case must, maybe
    var id: String { rawValue }
    var label: String { self == .must ? "Must do" : "Maybe" }
    var icon: String { self == .must ? "flame.fill" : "shuffle" }
}

enum Period: String, Codable, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String { self == .day ? "Day" : "Week" }

    func start(of date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    func previousStart(before start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: self == .day ? .day : .weekOfYear, value: -1, to: start) ?? start
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var priority: Priority
    var oneTime = false
    var lastPicked: Date?
}

struct PlanItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var priority: Priority
    var done = false
}

struct Plan: Codable, Equatable {
    var period: Period
    var start: Date
    var items: [PlanItem]
    var rerollsUsed = 0

    var doneCount: Int { items.filter(\.done).count }
    var isComplete: Bool { !items.isEmpty && items.allSatisfy(\.done) }
}

struct Settings: Codable, Equatable {
    var period: Period = .day
    var dayCount = 4
    var weekCount = 10
    var allowReroll = true
    var reminderOn = false
    var reminderHour = 8
    var reminderMinute = 0
}

struct SavedState: Codable {
    var tasks: [TaskItem] = []
    var plan: Plan?
    var settings = Settings()
    var streak = 0
    var lastCompletedStart: Date?
}

@MainActor
final class Store: ObservableObject {
    @Published var state: SavedState {
        didSet { save() }
    }
    @Published var now = Date()

    private static var fileURL: URL {
        URL.documentsDirectory.appending(path: "lockin.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = saved
        } else {
            state = SavedState()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Reading

    /// The locked-in list, if it's still for the current day/week.
    var currentPlan: Plan? {
        guard let plan = state.plan, plan.start == plan.period.start(of: now) else { return nil }
        return plan
    }

    /// The period shown on screen: the current list's, or the setting for the next one.
    var activePeriod: Period { currentPlan?.period ?? state.settings.period }

    var targetCount: Int {
        state.settings.period == .day ? state.settings.dayCount : state.settings.weekCount
    }

    var mustCount: Int { state.tasks.filter { $0.priority == .must }.count }
    var maybeCount: Int { state.tasks.filter { $0.priority == .maybe }.count }

    /// How many lists in a row were finished. Resets if a whole day/week is missed.
    var streak: Int {
        guard let last = state.lastCompletedStart, let period = state.plan?.period else { return 0 }
        let current = period.start(of: now)
        return (last == current || last == period.previousStart(before: current)) ? state.streak : 0
    }

    var canReroll: Bool {
        guard let plan = currentPlan else { return false }
        return state.settings.allowReroll && plan.rerollsUsed == 0 && plan.doneCount == 0
    }

    // MARK: - Drawing

    /// Every must-do, then random maybes until the list is full.
    /// Maybes that haven't come up for a while are more likely to be picked.
    func draw() -> [TaskItem] {
        let finished = finishedOneTimeIDs
        let available = state.tasks.filter { !finished.contains($0.id) }
        let musts = available.filter { $0.priority == .must }
        var pool = available.filter { $0.priority == .maybe }
        var picked = musts
        let slots = max(0, targetCount - musts.count)

        for _ in 0..<slots {
            guard !pool.isEmpty else { break }
            let weights = pool.map(weight)
            var roll = Double.random(in: 0..<weights.reduce(0, +))
            var index = pool.count - 1
            for (i, w) in weights.enumerated() {
                if roll < w { index = i; break }
                roll -= w
            }
            picked.append(pool.remove(at: index))
        }
        return picked
    }

    /// One-time tasks checked off on the last list. They won't be drawn again.
    private var finishedOneTimeIDs: Set<UUID> {
        guard let plan = state.plan else { return [] }
        let done = Set(plan.items.filter(\.done).map(\.id))
        return Set(state.tasks.filter { $0.oneTime && done.contains($0.id) }.map(\.id))
    }

    private func weight(_ task: TaskItem) -> Double {
        guard let last = task.lastPicked else { return 15 }
        let days = max(0, now.timeIntervalSince(last) / 86_400)
        return 1 + min(14, days)
    }

    // MARK: - Changing

    func lockIn(with picked: [TaskItem]) {
        var s = state
        // One-time tasks finished on the earlier list are gone for good.
        let finished = finishedOneTimeIDs
        s.tasks.removeAll { finished.contains($0.id) }
        let pickedIDs = Set(picked.map(\.id))
        for i in s.tasks.indices where pickedIDs.contains(s.tasks[i].id) {
            s.tasks[i].lastPicked = now
        }
        let period = s.settings.period
        s.plan = Plan(
            period: period,
            start: period.start(of: now),
            items: picked.map { PlanItem(id: $0.id, title: $0.title, priority: $0.priority) }
        )
        state = s
    }

    func reroll(with picked: [TaskItem]) {
        guard canReroll else { return }
        let used = (currentPlan?.rerollsUsed ?? 0) + 1
        lockIn(with: picked)
        state.plan?.rerollsUsed = used
    }

    func toggle(_ id: UUID) {
        guard var plan = currentPlan, let i = plan.items.firstIndex(where: { $0.id == id }) else { return }
        plan.items[i].done.toggle()

        var s = state
        if plan.isComplete && s.lastCompletedStart != plan.start {
            let previous = plan.period.previousStart(before: plan.start)
            s.streak = s.lastCompletedStart == previous ? s.streak + 1 : 1
            s.lastCompletedStart = plan.start
        }
        s.plan = plan
        state = s
    }

    func upsert(_ task: TaskItem) {
        if let i = state.tasks.firstIndex(where: { $0.id == task.id }) {
            state.tasks[i] = task
        } else {
            state.tasks.append(task)
        }
    }

    func delete(_ ids: [UUID]) {
        state.tasks.removeAll { ids.contains($0.id) }
    }

    // MARK: - Reminder

    func updateReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["lockin.reminder"])
        let settings = state.settings
        guard settings.reminderOn else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            state.settings.reminderOn = false
            return
        }

        var when = DateComponents()
        when.hour = settings.reminderHour
        when.minute = settings.reminderMinute
        if settings.period == .week { when.weekday = Calendar.current.firstWeekday }

        let content = UNMutableNotificationContent()
        content.title = "Time to lock in"
        content.body = settings.period == .day ? "Draw today's list." : "Draw this week's list."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lockin.reminder",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        )
        try? await center.add(request)
    }
}
