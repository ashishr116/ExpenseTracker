//
//  PaymentDueSheet.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Pop-up listing EMI instalments and insurance premiums due today, so each can be recorded as paid.
/// Overdue ones are not shown here; they appear as a badge in the EMI and Insurance lists.
struct PaymentDueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let due: [Expense]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(due) { payment in
                        DueRow(payment: payment)
                    }
                } footer: {
                    Text("Tap Mark Paid once you've paid. Anything you leave unpaid is shown again as overdue, and also appears in the EMI and Insurance lists.")
                }
            }
            .navigationTitle("Payments Due")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
            // Close automatically once everything has been recorded.
            .onChange(of: due.isEmpty) { _, isEmpty in
                if isEmpty { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DueRow: View {
    let payment: Expense

    private var name: String {
        payment.emi?.name ?? payment.insurancePolicy?.title ?? payment.title
    }

    /// e.g. "EMI · Credit Card · HDFC Bank · •••• 1234"
    private var detail: String {
        var parts = [payment.emi != nil ? "EMI" : "Insurance", payment.accountType.rawValue]
        if payment.accountType.usesBank, !payment.bankName.isEmpty { parts.append(payment.bankName) }
        if payment.accountType.usesCard, !payment.cardLastFour.isEmpty { parts.append("•••• \(payment.cardLastFour)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(payment.amount, format: .rupees)
                    .fontWeight(.semibold)
            }
            HStack {
                if payment.date < Calendar.current.startOfDay(for: .now) {
                    Text("Overdue since \(payment.date.formatted(.dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Due today")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Mark Paid", systemImage: "checkmark.circle.fill") {
                    payment.paidAt = .now
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shows `PaymentDueSheet` when the app becomes active (once `isEnabled`) and keeps
/// due-date notifications in step with what has been paid.
struct PaymentDueReminders: ViewModifier {
    let isEnabled: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Query private var emis: [EMI]
    @Query private var policies: [InsurancePolicy]
    @Query private var loans: [Loan]
    @State private var isPresented = false

    private var dueToday: [Expense] {
        emis.flatMap { $0.dueTodayInstallments() } + policies.flatMap { $0.dueTodayPremiums() }
    }

    private var overdue: [Expense] {
        emis.flatMap { $0.overdueInstallments() } + policies.flatMap { $0.overduePremiums() }
    }

    /// Everything shown in the pop-up: what is due today, and what is already overdue.
    private var due: [Expense] {
        (dueToday + overdue).sorted { $0.date < $1.date }
    }

    private static let overduePromptKey = "overduePromptDay"

    /// Items due today always bring the pop-up up. Overdue items bring it up the first time you open the app each day,
    /// so a missed payment can't sit unnoticed, without nagging on every launch.
    private func shouldPresent() -> Bool {
        if !dueToday.isEmpty { return true }
        guard !overdue.isEmpty else { return false }
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        return UserDefaults.standard.double(forKey: Self.overduePromptKey) < today
    }

    private var pendingCount: Int {
        emis.reduce(0) { $0 + $1.pendingInstallments.count }
            + policies.reduce(0) { $0 + $1.pendingPremiums.count }
    }

    /// Changes whenever a loan's monthly reminder is switched on or off, moved, re-priced or cleared.
    private var loanReminderSignature: Int {
        var hasher = Hasher()
        for loan in loans where loan.hasActiveMonthlyReminder {
            hasher.combine(loan.friendName)
            hasher.combine(loan.monthlyReminderDay)
            hasher.combine(loan.monthlyInstalmentPaise)
        }
        return hasher.finalize()
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                PaymentDueSheet(due: due)
            }
            .onChange(of: isEnabled, initial: true) { _, enabled in
                if enabled { refresh(presenting: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isEnabled { refresh(presenting: true) }
            }
            // Re-sync notifications whenever payments are recorded, added or regenerated.
            .onChange(of: pendingCount) {
                refresh(presenting: false)
            }
            .onChange(of: loanReminderSignature) {
                refresh(presenting: false)
            }
    }

    private func refresh(presenting: Bool) {
        if presenting, shouldPresent() {
            isPresented = true
            if !overdue.isEmpty {
                // Overdue items are now shown for today. Due-today items still appear on every open.
                UserDefaults.standard.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: Self.overduePromptKey)
            }
        }
        let currentEMIs = emis
        let currentPolicies = policies
        let currentLoans = loans
        Task { await PaymentReminder.sync(emis: currentEMIs, policies: currentPolicies, loans: currentLoans) }
    }
}

extension View {
    func paymentDueReminders(isEnabled: Bool) -> some View {
        modifier(PaymentDueReminders(isEnabled: isEnabled))
    }
}
