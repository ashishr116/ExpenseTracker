//
//  GoalDetailView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// One goal's progress, plan and history, with ways to add money, close it when bought, edit or delete it.
struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let goal: Goal

    @State private var isEditing = false
    @State private var isAddingMoney = false
    @State private var isConfirmingPurchase = false
    @State private var isConfirmingDelete = false
    @State private var isAddingExpense = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.saved, format: .rupees)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(goal.isFunded || goal.isCompleted ? Color.green : Color.primary)
                    Text("of \(goal.target.formatted(.rupees))")
                        .foregroundStyle(.secondary)
                    ProgressView(value: goal.progress)
                        .tint(goal.isFunded || goal.isCompleted ? .green : .accentColor)
                    GoalStatusLabel(goal: goal)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)

                if !goal.isCompleted {
                    LabeledContent("Still to Go") {
                        Text(goal.remaining, format: .rupees)
                            .fontWeight(.semibold)
                    }
                }
            }

            if !goal.isCompleted {
                Section {
                    LabeledContent("Set Aside Each Month") {
                        Text(goal.monthly, format: .rupees)
                    }
                    if let finish = goal.projectedFinish(), let months = goal.monthsToFinish {
                        LabeledContent("Ready By") {
                            Text(finish, format: .dateTime.month(.wide).year())
                        }
                        LabeledContent("Months to Go") {
                            Text("\(months)")
                        }
                    }
                    if let targetDate = goal.targetDate {
                        LabeledContent("You Wanted It By") {
                            Text(targetDate, format: .dateTime.day().month().year())
                        }
                    }
                } header: {
                    Text("Plan")
                } footer: {
                    Text("At the end of each month the planned amount is set aside from what was left over. If less was left, only that much is set aside and the goal shows as behind.")
                }
            }

            Section {
                if goal.isCompleted {
                    Button("Reopen Goal", systemImage: "arrow.uturn.backward") {
                        goal.completedAt = nil
                    }
                } else {
                    Button("Add Money", systemImage: "plus.circle") {
                        isAddingMoney = true
                    }
                    Button("I Bought It", systemImage: "bag.fill") {
                        isConfirmingPurchase = true
                    }
                }
                Button("Edit Goal", systemImage: "pencil") {
                    isEditing = true
                }
                Button("Delete Goal", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }

            Section {
                if goal.contributions.isEmpty {
                    Text("Nothing set aside yet. The first amount goes in when this month ends.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(goal.sortedContributions) { contribution in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contribution.date, format: .dateTime.day().month().year())
                            Text(contribution.note.isEmpty ? (contribution.isAutomatic ? "Month-end savings" : "Added by hand") : contribution.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(contribution.amount.formatted(.rupees))")
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            goal.contributions.removeAll { $0 === contribution }
                            modelContext.delete(contribution)
                        }
                    }
                }
            } header: {
                Text("Set Aside So Far")
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            GoalFormView(goal: goal)
        }
        .sheet(isPresented: $isAddingMoney) {
            GoalContributionFormView(goal: goal)
        }
        .sheet(isPresented: $isAddingExpense) {
            // The price is filled in so the purchase can be recorded in one tap.
            ExpenseFormView(prefillTitle: goal.name, prefillAmount: goal.target)
        }
        .confirmationDialog("You bought \(goal.name)?", isPresented: $isConfirmingPurchase, titleVisibility: .visible) {
            Button("Mark as Bought") {
                goal.completedAt = .now
            }
            Button("Mark as Bought and Add the Expense") {
                goal.completedAt = .now
                isAddingExpense = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The money set aside is released. You can also record what you paid as an expense.")
        }
        .confirmationDialog("Delete \(goal.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) {
                modelContext.delete(goal)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its history is removed. No money moves, because it was only set aside.")
        }
    }
}
