//
//  GoalsView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Things you are saving up for, each with how much is set aside and when it should be ready.
struct GoalsView: View {
    @Query(sort: \Goal.createdAt) private var goals: [Goal]

    @State private var isAddingGoal = false

    private var active: [Goal] { goals.filter { !$0.isCompleted } }
    private var completed: [Goal] { goals.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } }

    var body: some View {
        List {
            if goals.isEmpty {
                Section {
                    Label("Save up for something", systemImage: "target")
                        .font(.headline)
                    Text("Pick what you want to buy, how much it costs, and what you can spare each month. The app sets that amount aside from what is left over at month end, and shows when you'll have it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Your First Goal", systemImage: "plus") { isAddingGoal = true }
                }
            } else {
                if !active.isEmpty {
                    summarySection
                    Section("Saving For") {
                        ForEach(active) { goal in
                            NavigationLink {
                                GoalDetailView(goal: goal)
                            } label: {
                                GoalRow(goal: goal)
                            }
                        }
                    }
                }
                if !completed.isEmpty {
                    Section("Bought") {
                        ForEach(completed) { goal in
                            NavigationLink {
                                GoalDetailView(goal: goal)
                            } label: {
                                GoalRow(goal: goal)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Goal", systemImage: "plus") { isAddingGoal = true }
            }
        }
        .sheet(isPresented: $isAddingGoal) {
            GoalFormView()
        }
    }

    private var summarySection: some View {
        let setAside = active.reduce(Decimal(0)) { $0 + $1.saved }
        // What goes in at the end of this month if there is enough left over.
        let planned = active.filter { !$0.isFunded }.reduce(Decimal(0)) { $0 + min($1.monthly, $1.remaining) }
        return Section {
            LabeledContent("Set Aside") {
                Text(setAside, format: .rupees)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
            }
            if planned > 0 {
                LabeledContent("Planned This Month") {
                    Text(planned, format: .rupees)
                        .fontWeight(.semibold)
                }
            }
        } footer: {
            Text("This money is still in your savings. It is only marked as belonging to a goal, so your balances and net worth don't change.")
        }
    }
}

// MARK: - Row

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: goal.progress)
                .tint(goal.isCompleted || goal.isFunded ? .green : .accentColor)
            HStack {
                Text("\(goal.saved.formatted(.rupees)) of \(goal.target.formatted(.rupees))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                GoalStatusLabel(goal: goal)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "On track · by Mar 2027", "Behind by ₹3,000", "Ready to buy" or "Bought 12 Oct 2026".
struct GoalStatusLabel: View {
    let goal: Goal

    var body: some View {
        if let completedAt = goal.completedAt {
            Text("Bought \(completedAt.formatted(.dateTime.day().month().year()))")
                .foregroundStyle(.secondary)
        } else if goal.isFunded {
            Text("Ready to buy")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        } else if goal.shortfall() > 0 {
            Text("Behind by \(goal.shortfall().formatted(.rupees))")
                .foregroundStyle(.orange)
        } else if let finish = goal.projectedFinish() {
            Text("On track · by \(finish.formatted(.dateTime.month(.abbreviated).year()))")
                .foregroundStyle(.green)
        } else {
            Text("Set a monthly amount")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        GoalsView()
    }
    .modelContainer(for: [Goal.self, GoalContribution.self], inMemory: true)
}
