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
    @Query(sort: \EMI.endMonth) private var emis: [EMI]

    @State private var isAdding = false
    @State private var editing: RecurringExpense?
    @State private var month = Date.now

    /// The actual EMI expense for each scheduled month. These are owned by the EMI, not duplicate plans.
    private var monthlyEMIs: [Expense] {
        let range = Calendar.current.monthRange(containing: month)
        return emis
            .flatMap(\.installments)
            .filter { $0.date >= range.lowerBound && $0.date < range.upperBound }
            .sorted { $0.date < $1.date }
    }

    private var monthlyEMITotal: Decimal { monthlyEMIs.totalAmount }

    var body: some View {
        List {
            Section {
                MonthSelector(month: $month)
                    .listRowInsets(EdgeInsets())
            }

            if !plans.isEmpty {
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

            if !monthlyEMIs.isEmpty {
                Section {
                    LabeledContent("Due This Month") {
                        Text(monthlyEMITotal, format: .rupees)
                            .font(.title3.weight(.bold))
                    }
                    ForEach(monthlyEMIs) { installment in
                        EMIRecurringRow(installment: installment)
                    }
                } header: {
                    Text("EMIs · \(month.formatted(.dateTime.month(.wide).year()))")
                } footer: {
                    Text("EMIs are shown for their scheduled month. They are managed under EMIs, and appear here as fixed recurring commitments.")
                }
            }

            if plans.isEmpty && monthlyEMIs.isEmpty {
                Section {
                    Label("Add what you pay every month", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text("Rent, the maid, subscriptions, and scheduled EMIs will appear here for their payment month.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Your First One", systemImage: "plus") { isAdding = true }
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

private struct EMIRecurringRow: View {
    let installment: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(installment.displayTitle)
                    .font(.body.weight(.medium))
                Text("Due \(installment.date.formatted(.dateTime.day().month(.abbreviated))) · \(installment.accountDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(installment.isPlanned ? "Planned" : "Paid")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(installment.isPlanned ? .orange : .green)
            }
            .layoutPriority(1)

            Spacer()

            Text(installment.amount, format: .rupees)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 2)
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
    .modelContainer(for: [RecurringExpense.self, Expense.self, EMI.self], inMemory: true)
}
