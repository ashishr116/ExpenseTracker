//
//  EMIsView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Lists every EMI plan with its progress, monthly commitment and amount left to pay.
struct EMIsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EMI.endMonth) private var emis: [EMI]
    @State private var isAddingEMI = false
    @State private var editingEMI: EMI?
    @State private var deletingEMI: EMI?
    @State private var reminders = NotificationStatus()

    private var activeEMIs: [EMI] { emis.filter(\.isActive) }
    private var completedEMIs: [EMI] { emis.filter { !$0.isActive } }

    var body: some View {
        Group {
            if emis.isEmpty {
                ContentUnavailableView(
                    "No EMIs",
                    systemImage: "calendar.badge.clock",
                    description: Text("Tap + to add an EMI. Its monthly instalments are added to your expenses automatically.")
                )
            } else {
                List {
                    NotificationStatusSection(model: reminders)

                    Section {
                        LabeledContent("Monthly EMIs") {
                            Text(activeEMIs.reduce(0) { $0 + $1.monthlyAmount }, format: .rupees)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        LabeledContent("Left to Pay") {
                            Text(activeEMIs.reduce(0) { $0 + $1.remainingAmount }, format: .rupees)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !activeEMIs.isEmpty {
                        Section("Active") {
                            ForEach(activeEMIs) { emiRow($0) }
                        }
                    }
                    if !completedEMIs.isEmpty {
                        Section("Completed") {
                            ForEach(completedEMIs) { emiRow($0) }
                        }
                    }
                }
            }
        }
        .trackNotificationStatus(reminders)
        .navigationTitle("EMIs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add EMI", systemImage: "plus") {
                    isAddingEMI = true
                }
            }
        }
        .sheet(isPresented: $isAddingEMI) {
            EMIFormView()
        }
        .sheet(item: $editingEMI) { emi in
            EMIFormView(emi: emi)
        }
        .confirmationDialog(
            "Delete \(deletingEMI?.name ?? "EMI")?",
            isPresented: Binding(get: { deletingEMI != nil }, set: { if !$0 { deletingEMI = nil } }),
            titleVisibility: .visible,
            presenting: deletingEMI
        ) { emi in
            Button("Delete EMI", role: .destructive) {
                emi.delete(from: modelContext)
                deletingEMI = nil
            }
        } message: { emi in
            let kept = emi.installmentsKeptOnDelete()
            let future = emi.installments.count - kept.count
            Text(kept.isEmpty
                 ? "Removes its \(future) instalment\(future == 1 ? "" : "s") still to come."
                 : "Keeps the \(kept.count) instalment\(kept.count == 1 ? "" : "s") already paid (\(kept.totalAmount.formatted(.rupees))) as past expenses, so your balances and past months don't change. Removes the \(future) still to come.")
        }
    }

    private func emiRow(_ emi: EMI) -> some View {
        Button {
            editingEMI = emi
        } label: {
            EMIRow(emi: emi)
        }
        .tint(.primary)
        .swipeActions(edge: .leading) {
            // Lets you record a payment made early, before the due-date pop-up appears.
            if let next = emi.pendingInstallments.first {
                Button("Mark Paid", systemImage: "checkmark.circle") {
                    emi.markPaid(next)
                }
                .tint(.green)
            }
            // The bank's payment bounced: back to unpaid, and auto-debit leaves it that way.
            if emi.isAutoDebited, let last = AutoDebit.lastAutoPaid(in: emi.installments) {
                Button("Didn't Go Through", systemImage: "arrow.uturn.backward") {
                    last.paidAt = nil
                }
                .tint(.orange)
            }
        }
        .swipeActions {
            // Asks first: a full swipe would otherwise delete straight away.
            Button("Delete", systemImage: "trash") {
                deletingEMI = emi
            }
            .tint(.red)
        }
    }
}

private struct EMIRow: View {
    let emi: EMI

    private var overdueCount: Int { emi.overdueInstallments().count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(emi.name)
                        .font(.body.weight(.medium))
                    Text(emi.accountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(emi.monthlyAmount, format: .rupees)
                        .fontWeight(.semibold)
                    Text("per month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(emi.paidCount), total: Double(max(emi.totalCount, 1)))
                .tint(emi.isActive ? .accentColor : .green)

            HStack {
                Text("\(emi.paidCount) of \(emi.totalCount) paid")
                Spacer()
                Text("Billed on day \(emi.billingDay) · Ends \(emi.endMonth, format: .dateTime.month(.abbreviated).year())")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if overdueCount > 0 {
                Label("\(overdueCount) overdue. Late fees may apply and your credit score can suffer. Swipe right to mark paid.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        EMIsView()
    }
    .modelContainer(for: [Expense.self, EMI.self], inMemory: true)
}
