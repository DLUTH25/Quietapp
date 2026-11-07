import SwiftUI

@MainActor
struct TodayView: View {
    @EnvironmentObject private var store: Store
    @State private var rollingText: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if let rollingText {
                        RollingView(text: rollingText)
                    } else if let plan = store.currentPlan {
                        planView(plan)
                    } else {
                        lockInPrompt
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text(dateLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(store.activePeriod == .day ? "Today" : "This week")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            if store.streak > 0 {
                Label("\(store.streak)-\(store.activePeriod == .day ? "day" : "week") streak", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dateLabel: String {
        if store.activePeriod == .day {
            return store.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        let start = Period.week.start(of: store.now)
        return "Week of " + start.formatted(.dateTime.month(.wide).day())
    }

    private var lockInPrompt: some View {
        VStack(spacing: 20) {
            if store.state.tasks.isEmpty {
                Text("Add the things you want to get done in the **Tasks** tab. Mark the important ones as **Must do**. The rest get picked at random.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(summary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await draw(reroll: false) }
            } label: {
                Text("Lock in")
                    .font(.title2.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.state.tasks.isEmpty)
        }
        .padding(.top, 20)
    }

    private var summary: String {
        let musts = store.mustCount
        let total = store.state.tasks.count
        let size = max(musts, min(store.targetCount, total))
        let period = store.state.settings.period == .day ? "today" : "this week"
        if musts == 0 {
            return "You'll get \(size) random \(size == 1 ? "thing" : "things") for \(period)."
        }
        return "You'll get \(size) \(size == 1 ? "thing" : "things") for \(period): your \(musts) must-do\(musts == 1 ? "" : "s"), plus random picks for the rest."
    }

    private func planView(_ plan: Plan) -> some View {
        VStack(spacing: 24) {
            ProgressRing(done: plan.doneCount, total: plan.items.count)

            VStack(spacing: 10) {
                ForEach(plan.items) { item in
                    PlanRow(item: item) {
                        withAnimation(.snappy) { store.toggle(item.id) }
                    }
                }
            }

            if plan.isComplete {
                VStack(spacing: 6) {
                    Text("Locked in.")
                        .font(.title2.weight(.heavy))
                    Text(plan.period == .day ? "Everything's done. Enjoy the rest of your day." : "Everything's done for the week.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .transition(.scale.combined(with: .opacity))
            } else if store.canReroll {
                Button("Reroll (1 left)") {
                    Task { await draw(reroll: true) }
                }
                .font(.subheadline)
            }

            Text(plan.period == .day ? "New list tomorrow." : "New list next week.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Draw animation

    private func draw(reroll: Bool) async {
        let picked = store.draw()
        let names = store.state.tasks.map(\.title)
        var delay = 0.04
        for _ in 0..<16 {
            rollingText = names.randomElement() ?? ""
            try? await Task.sleep(for: .seconds(delay))
            delay *= 1.12
        }
        if reroll {
            store.reroll(with: picked)
        } else {
            store.lockIn(with: picked)
        }
        withAnimation(.spring(duration: 0.4)) { rollingText = nil }
    }
}

// MARK: - Subviews

private struct RollingView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity, minHeight: 220)
            .sensoryFeedback(.selection, trigger: text)
    }
}

private struct PlanRow: View {
    let item: PlanItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? Color.orange : Color.secondary)
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.priority == .must {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Must do")
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: item.done)
    }
}

private struct ProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: total == 0 ? 0 : CGFloat(done) / CGFloat(total))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: done)
            VStack(spacing: 0) {
                Text("\(done)/\(total)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
    }
}
