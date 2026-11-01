//
//  MonthlySavingsView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Month-by-month record of leftover money added to the savings account in Net Worth.
struct MonthlySavingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MonthlySavings.month, order: .reverse) private var records: [MonthlySavings]

    @AppStorage(SavingsSweep.enabledKey) private var isEnabled = false
    @AppStorage(SavingsSweep.bankKey) private var bank = ""
    @AppStorage(SavingsSweep.startKey) private var start = 0.0
    @AppStorage(SavingsSweep.fromAccountKey) private var fromUID = ""
    @AppStorage(SavingsSweep.toAccountKey) private var toUID = ""
    @Query private var accounts: [Account]

    @State private var isShowingSetup = false
    /// Leftover for the month in progress, shown as a preview of what will be added.
    @State private var thisMonthLeftover: Decimal = 0

    private var totalAdded: Decimal { records.reduce(0) { $0 + $1.applied } }

    /// Accounts exist, but the source and savings accounts haven't been picked (or one was removed).
    private var needsAccountSetup: Bool {
        guard !accounts.isEmpty else { return false }
        let hasFrom = accounts.contains { $0.uid == fromUID }
        let hasTo = accounts.contains { $0.uid == toUID }
        return !hasFrom || !hasTo || fromUID == toUID
    }

    var body: some View {
        List {
            if isEnabled {
                if needsAccountSetup {
                    Section {
                        Label("Choose the accounts to move the leftover between. Nothing is moved until you do.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Button("Choose Accounts", systemImage: "gearshape") { isShowingSetup = true }
                    }
                }
                summarySection
                monthsSection
            } else {
                introSection
            }
        }
        .navigationTitle("Monthly Savings")
        .toolbar {
            if isEnabled {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { isShowingSetup = true }
                }
            }
        }
        .sheet(isPresented: $isShowingSetup) {
            SavingsSweepSetupView()
        }
        .task(id: isEnabled) {
            thisMonthLeftover = SavingsSweep.leftover(for: .now, in: modelContext)
        }
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            Label("Add each month's leftover to savings", systemImage: "banknote")
                .font(.headline)
            Text("At the end of every month, what's left after expenses, unpaid EMIs and premiums, and loans is added to a savings account in Net Worth, under the bank you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Set Up", systemImage: "gearshape") { isShowingSetup = true }
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Savings Account", value: BankName.display(bank))
            LabeledContent("Added So Far") {
                Text(totalAdded, format: .rupees)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
            }
            LabeledContent("This Month So Far") {
                Text(thisMonthLeftover, format: .rupees)
                    .foregroundStyle(thisMonthLeftover >= 0 ? Color.primary : Color.red)
            }
        } footer: {
            Text("This month's leftover is added to \(BankName.display(bank)) when the month ends. It starts from \(Date(timeIntervalSince1970: start).formatted(.dateTime.month(.wide).year())).")
        }
    }

    private var monthsSection: some View {
        Section("Month by Month") {
            if records.isEmpty {
                Text("Nothing added yet. The first addition happens when the current month ends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                SavingsRow(record: record)
            }
        }
    }
}

private struct SavingsRow: View {
    @Environment(\.modelContext) private var modelContext
    let record: MonthlySavings

    /// The month's leftover as it stands now; differs from the snapshot if entries changed afterwards.
    @State private var currentLeftover: Decimal?

    private var hasChanged: Bool {
        guard let currentLeftover else { return false }
        return max(0, currentLeftover) != record.applied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.month, format: .dateTime.month(.wide).year())
                        .font(.body.weight(.medium))
                    Text(record.applied > 0 ? "Added to \(BankName.display(record.bankName))" : "Nothing left to add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.applied, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(record.applied > 0 ? .green : .secondary)
                    if record.leftover < 0 {
                        Text("Overspent by \((-record.leftover).formatted(.rupees))")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if hasChanged, let currentLeftover {
                HStack {
                    Text("Entries changed. Leftover is now \(currentLeftover.formatted(.rupees)).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Update") {
                        SavingsSweep.refresh(record, in: modelContext)
                        self.currentLeftover = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
        .task(id: record.appliedPaise) {
            currentLeftover = SavingsSweep.leftover(for: record.month, in: modelContext)
        }
    }
}

// MARK: - Setup

/// Chooses the savings account and the first month to sweep.
struct SavingsSweepSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var holdings: [Holding]
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    @AppStorage(SavingsSweep.enabledKey) private var isEnabled = false
    @AppStorage(SavingsSweep.bankKey) private var savedBank = ""
    @AppStorage(SavingsSweep.startKey) private var savedStart = 0.0
    @AppStorage(SavingsSweep.fromAccountKey) private var savedFromUID = ""
    @AppStorage(SavingsSweep.toAccountKey) private var savedToUID = ""

    @State private var bankName = ""
    @State private var startMonth = Date.now
    @State private var fromUID = ""
    @State private var toUID = ""

    /// Open bank and cash accounts the leftover can come out of.
    private var sourceAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    /// Open bank accounts the leftover can go into.
    private var savingsAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && $0.kind == .bank }
    }

    /// With accounts set up, the leftover moves between them as a transfer.
    private var usesAccounts: Bool { !allAccounts.isEmpty }

    private var canSave: Bool {
        usesAccounts ? (!fromUID.isEmpty && !toUID.isEmpty && fromUID != toUID) : !trimmedBank.isEmpty
    }

    /// Banks that already have a savings account in Net Worth.
    private var savingsBanks: [String] {
        var seen = Set<String>()
        return holdings
            .filter { $0.kind == .savings && !$0.platform.isEmpty }
            .map(\.platform)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var trimmedBank: String {
        BankName.normalized(bankName)
    }

    var body: some View {
        NavigationStack {
            Form {
                if usesAccounts {
                    Section {
                        Picker("Move From", selection: $fromUID) {
                            Text("Choose").tag("")
                            ForEach(sourceAccounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                        Picker("Savings Account", selection: $toUID) {
                            Text("Choose").tag("")
                            ForEach(savingsAccounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                    } header: {
                        Text("Accounts")
                    } footer: {
                        if !fromUID.isEmpty, fromUID == toUID {
                            Text("Choose two different accounts.")
                                .foregroundStyle(.red)
                        } else {
                            Text("At the end of each month the leftover is moved from the first account to the savings account as a transfer. Net worth stays the same, because the money only changes accounts.")
                        }
                    }
                } else {
                    Section {
                        TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
                            .textInputAutocapitalization(.words)
                        chips(title: savingsBanks.isEmpty ? "Popular Banks" : "Your Savings Accounts",
                              names: savingsBanks.isEmpty ? PopularBank.names : savingsBanks)
                    } header: {
                        Text("Savings Account")
                    } footer: {
                        Text("Use the same bank name as your savings account in Net Worth. If there is none for this bank, one is created. Add your accounts under More, Accounts, to move the money between real balances instead.")
                    }
                }

                Section {
                    DatePicker("Start From", selection: $startMonth, displayedComponents: .date)
                } header: {
                    Text("First Month")
                } footer: {
                    Text("Months before this one are left alone, so your current balance isn't counted twice. The first addition happens when that month ends.")
                }

                if isEnabled {
                    Section {
                        Button("Turn Off", role: .destructive) {
                            isEnabled = false
                            dismiss()
                        }
                    } footer: {
                        Text("Amounts already moved stay where they are.")
                    }
                }
            }
            .navigationTitle("Monthly Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                bankName = savedBank
                fromUID = savedFromUID
                toUID = savedToUID
                if savedStart > 0 { startMonth = Date(timeIntervalSince1970: savedStart) }
            }
        }
    }

    private func chips(title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        let isSelected = trimmedBank.caseInsensitiveCompare(name) == .orderedSame
                        Button {
                            bankName = name
                        } label: {
                            Text(BankName.display(name))
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func save() {
        let monthStart = Calendar.current.monthRange(containing: startMonth).lowerBound
        savedStart = monthStart.timeIntervalSince1970
        isEnabled = true

        if usesAccounts {
            savedFromUID = fromUID
            savedToUID = toUID
            // Shown on the Monthly Savings screen.
            savedBank = allAccounts.first { $0.uid == toUID }?.storedName ?? ""
        } else {
            savedBank = trimmedBank
            // Make sure the account shows up in Net Worth straight away.
            _ = SavingsSweep.savingsHolding(for: trimmedBank, in: modelContext, createIfMissing: true)
        }
        SavingsSweep.run(in: modelContext)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MonthlySavingsView()
    }
    .modelContainer(for: [MonthlySavings.self, Holding.self, Income.self, Expense.self, Loan.self, EMI.self, InsurancePolicy.self], inMemory: true)
}
