//
//  RecurringExpensesView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Payments that repeat every month, such as rent, the maid and subscriptions. Each is added by itself on its day.
struct RecurringExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringExpense.createdAt) private var plans: [RecurringExpense]

    @State private var isAdding = false
    @State private var editing: RecurringExpense?

    var body: some View {
        List {
            if plans.isEmpty {
                Section {
                    Label("Add what you pay every month", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text("Rent, the maid, subscriptions. Enter each one once, with the day it is paid. From then on the app adds it to your expenses on that day, so you don't have to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Your First One", systemImage: "plus") { isAdding = true }
                }
            } else {
                Section {
                    LabeledContent("Every Month") {
                        Text(plans.monthlyTotal, format: .rupees)
                            .font(.title3.weight(.bold))
                    }
                } footer: {
                    Text("Added to your expenses automatically on each payment day. Tap one to change it, or swipe to delete. Deleting a plan keeps the expenses it already added.")
                }

                Section {
                    ForEach(plans) { plan in
                        Button {
                            editing = plan
                        } label: {
                            RecurringRow(plan: plan)
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(plan)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recurring Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            RecurringExpenseFormView()
        }
        .sheet(item: $editing) { plan in
            RecurringExpenseFormView(plan: plan)
        }
    }
}

private struct RecurringRow: View {
    let plan: RecurringExpense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.category.systemImage)
                .font(.title3)
                .foregroundStyle(plan.isActive ? Color.accentColor : Color.secondary)
                .frame(width: 36, height: 36)
                .background((plan.isActive ? Color.accentColor : Color.secondary).opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.body.weight(.medium))
                Text("Day \(plan.dayOfMonth) of every month · \(plan.paymentDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !plan.isActive {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if plan.hasEnded() {
                    Text("Ended")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let next = plan.nextDue() {
                    Text("Next: \(next.formatted(.dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)

            Spacer()

            Text(plan.amount, format: .rupees)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        RecurringExpensesView()
    }
    .modelContainer(for: [RecurringExpense.self, Expense.self], inMemory: true)
}
