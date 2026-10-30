//
//  InsuranceView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Lists your health insurance and term plans with premiums, validity and upcoming dues.
/// Each policy's premiums are added to expenses on their debit dates (see `InsurancePolicy`).
struct InsuranceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InsurancePolicy.endDate) private var policies: [InsurancePolicy]

    @State private var isAddingPolicy = false
    @State private var editingPolicy: InsurancePolicy?
    @State private var reminders = NotificationStatus()

    private var activePolicies: [InsurancePolicy] { policies.filter { !$0.isExpired } }

    private var yearlyPremiums: Decimal {
        activePolicies.reduce(0) { $0 + $1.annualPremium }
    }

    /// The soonest upcoming premium across active policies.
    private var nextDue: (policy: InsurancePolicy, date: Date)? {
        activePolicies
            .compactMap { policy in policy.nextPremiumDate.map { (policy: policy, date: $0) } }
            .min { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if policies.isEmpty {
                ContentUnavailableView(
                    "No Policies",
                    systemImage: "cross.case",
                    description: Text("Tap + to add your health insurance or term plan.")
                )
            } else {
                List {
                    NotificationStatusSection(model: reminders)
                    summarySection
                    ForEach(InsuranceType.allCases) { type in
                        let items = policies.filter { $0.type == type }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { policyRow($0) }
                            } header: {
                                Label(type.rawValue, systemImage: type.systemImage)
                            }
                        }
                    }
                }
            }
        }
        .trackNotificationStatus(reminders)
        .navigationTitle("Insurance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Policy", systemImage: "plus") {
                    isAddingPolicy = true
                }
            }
        }
        .sheet(isPresented: $isAddingPolicy) {
            InsuranceFormView()
        }
        .sheet(item: $editingPolicy) { policy in
            InsuranceFormView(policy: policy)
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Yearly Premiums") {
                Text(yearlyPremiums, format: .rupees)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            if let nextDue {
                LabeledContent("Next Premium") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(nextDue.policy.premiumAmount, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("\(nextDue.policy.insurerName) · \(nextDue.date, format: .dateTime.day().month().year())")
                            .font(.caption)
                    }
                }
            }
        } footer: {
            Text("Premiums are added to your expenses automatically on each debit date.")
        }
    }

    private func policyRow(_ policy: InsurancePolicy) -> some View {
        Button {
            editingPolicy = policy
        } label: {
            PolicyRow(policy: policy)
        }
        .tint(.primary)
        .swipeActions(edge: .leading) {
            // Lets you record a premium paid early, before the due-date pop-up appears.
            if let next = policy.pendingPremiums.first {
                Button("Mark Paid", systemImage: "checkmark.circle") {
                    policy.markPaid(next)
                }
                .tint(.green)
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                policy.delete(from: modelContext)
            }
        }
    }
}

private struct PolicyRow: View {
    let policy: InsurancePolicy

    private var overdueCount: Int { policy.overduePremiums().count }

    /// How many days the oldest unpaid premium is past due.
    private var oldestOverdueDays: Int {
        guard let oldest = policy.overduePremiums().first else { return 0 }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: oldest.date), to: calendar.startOfDay(for: .now)).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.title)
                        .font(.body.weight(.medium))
                    if policy.coverAmount > 0 {
                        Text("\(policy.type.coverLabel): \(policy.coverAmount, format: .rupees)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !policy.policyNumber.isEmpty {
                        Text("Policy No. \(policy.policyNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(policy.premiumAmount, format: .rupees)
                        .fontWeight(.semibold)
                    Text(policy.frequency.perLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                validityBadge
                Spacer()
                if let next = policy.nextPremiumDate, !policy.isExpired {
                    Text("Next: \(next, format: .dateTime.day().month(.abbreviated))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if overdueCount > 0 {
                Label("\(overdueCount) overdue, the oldest by \(oldestOverdueDays) day\(oldestOverdueDays == 1 ? "" : "s"). Cover may lapse once the grace period ends, usually 15 to 30 days. Swipe right to mark paid.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    /// "Valid till 12 Mar 2027", turning orange within 30 days of expiry and red once expired.
    private var validityBadge: some View {
        let days = policy.daysUntilExpiry
        let color: Color = days < 0 ? .red : (days <= 30 ? .orange : .secondary)
        return Group {
            if days < 0 {
                Text("Expired \(policy.endDate, format: .dateTime.day().month().year())")
            } else if days <= 30 {
                Text("Renews in \(days) day\(days == 1 ? "" : "s")")
            } else {
                Text("\(policy.type.validityLabel) \(policy.endDate, format: .dateTime.day().month().year())")
            }
        }
        .font(.caption.weight(days <= 30 ? .semibold : .regular))
        .foregroundStyle(color)
    }
}

#Preview("Sample Policies") {
    let container = try! ModelContainer(
        for: InsurancePolicy.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let context = container.mainContext
    context.insert(InsurancePolicy(
        type: .health, insurerName: "Star Health", planName: "Family Health Optima", policyNumber: "P/1234/56",
        coverAmount: 1_000_000, premiumAmount: 24_500, frequency: .annually,
        startDate: calendar.date(byAdding: .month, value: -11, to: .now)!,
        endDate: calendar.date(byAdding: .day, value: 20, to: .now)!,
        nomineeOrMembers: "Self, Spouse"
    ))
    context.insert(InsurancePolicy(
        type: .term, insurerName: "HDFC Life", planName: "Click 2 Protect",
        coverAmount: 10_000_000, premiumAmount: 1_250, frequency: .monthly,
        startDate: calendar.date(byAdding: .year, value: -2, to: .now)!,
        endDate: calendar.date(byAdding: .year, value: 30, to: .now)!,
        nomineeOrMembers: "Spouse"
    ))

    return NavigationStack {
        InsuranceView()
    }
    .modelContainer(container)
}
