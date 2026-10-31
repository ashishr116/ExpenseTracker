//
//  GoalFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a goal, or editing one when `goal` is non-nil.
struct GoalFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: Goal?

    /// Which of the two you decide, and the app works out the other.
    private enum PlanMode: String, CaseIterable, Identifiable {
        case monthly = "Monthly Amount"
        case date = "Finish Date"

        var id: String { rawValue }
    }

    @State private var name: String
    @State private var target: Decimal?
    @State private var mode: PlanMode
    @State private var monthly: Decimal?
    @State private var targetDate: Date
    /// For a new goal: money you have already put aside.
    @State private var alreadySaved: Decimal?

    init(goal: Goal? = nil) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal?.target)
        _mode = State(initialValue: goal?.targetDate != nil ? .date : .monthly)
        _monthly = State(initialValue: goal?.monthly)
        _targetDate = State(initialValue: goal?.targetDate ?? Calendar.current.date(byAdding: .month, value: 12, to: .now) ?? .now)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What is still to be set aside.
    private var remainingToSave: Decimal {
        max(0, (target ?? 0) - (goal?.saved ?? alreadySaved ?? 0))
    }

    /// The monthly amount that will be used: typed in, or worked out from the finish date.
    private var effectiveMonthly: Decimal? {
        switch mode {
        case .monthly:
            return monthly
        case .date:
            guard remainingToSave > 0 else { return nil }
            return Goal.monthly(toSave: remainingToSave, over: Goal.monthEnds(until: targetDate))
        }
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty, let target, target > 0, let effectiveMonthly else { return false }
        return effectiveMonthly > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("What are you saving for? (e.g. iPhone)", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("How much does it cost?", value: $target, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    if goal == nil {
                        TextField("Already set aside (optional)", value: $alreadySaved, format: .rupees)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    Picker("You decide", selection: $mode.animation()) {
                        ForEach(PlanMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .monthly:
                        TextField("How much can you spare each month?", value: $monthly, format: .rupees)
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold))
                    case .date:
                        DatePicker("Finish By", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    }
                } header: {
                    Text("Plan")
                } footer: {
                    Text(mode == .monthly
                         ? "Tell the app what you can spare each month, and it works out when you'll have enough."
                         : "Pick the date you want it by, and the app works out what to spare each month.")
                }

                preview
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let target, target > 0, let effectiveMonthly, effectiveMonthly > 0 {
            Section("What It Means") {
                switch mode {
                case .monthly:
                    if let months = Goal.months(toSave: remainingToSave, monthly: effectiveMonthly),
                       let finish = Goal.finishMonth(afterMonths: months) {
                        LabeledContent("You'll Have It By") {
                            Text(finish, format: .dateTime.month(.wide).year())
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Months to Go") {
                            Text("\(months)")
                        }
                    } else {
                        Label("Already fully set aside", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                case .date:
                    LabeledContent("You Need to Spare") {
                        Text(effectiveMonthly, format: .rupees)
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Each Month For") {
                        Text("\(Goal.monthEnds(until: targetDate)) month\(Goal.monthEnds(until: targetDate) == 1 ? "" : "s")")
                    }
                }
            }
        }
    }

    private func save() {
        guard let target, let effectiveMonthly, isValid else { return }
        let finishDate: Date? = mode == .date ? targetDate : nil

        if let goal {
            goal.name = trimmedName
            goal.target = target
            goal.monthly = effectiveMonthly
            goal.targetDate = finishDate
        } else {
            let newGoal = Goal(name: trimmedName, target: target, monthly: effectiveMonthly, targetDate: finishDate)
            modelContext.insert(newGoal)
            if let alreadySaved, alreadySaved > 0 {
                let contribution = GoalContribution(amount: alreadySaved, note: "Already set aside")
                modelContext.insert(contribution)
                newGoal.contributions.append(contribution)
            }
        }
        dismiss()
    }
}

// MARK: - Add money

/// Sheet for putting money towards a goal by hand, for example a bonus.
struct GoalContributionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""

    private var isValid: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Still to go: \(goal.remaining.formatted(.rupees)). This only marks the money as set aside. Nothing leaves your account.")
                }
            }
            .navigationTitle("Add to \(goal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let contribution = GoalContribution(
            amount: amount, date: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(contribution)
        goal.contributions.append(contribution)
        dismiss()
    }
}

#Preview {
    GoalFormView()
        .modelContainer(for: [Goal.self, GoalContribution.self], inMemory: true)
}
