//
//  HoldingFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding an investment, savings balance or debt, or editing one when `holding` is non-nil.
/// The fields shown adapt to the selected type (e.g. units for stocks, maturity for FDs).
struct HoldingFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// All holdings, used to suggest platforms/banks you've used before.
    @Query private var allHoldings: [Holding]
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]
    /// Money moved in and out of investments, for this one's history.
    @Query(filter: #Predicate<Transfer> { $0.holdingUID != "" }, sort: \Transfer.date, order: .reverse)
    private var investmentMoves: [Transfer]

    let holding: Holding?

    @State private var kind: HoldingKind
    @State private var name: String
    @State private var platform: String
    @State private var investedAmount: Decimal?
    @State private var currentValue: Decimal?
    @State private var quantity: Double?
    @State private var interestRate: Double?
    @State private var hasMaturity: Bool
    @State private var maturityDate: Date
    @State private var note: String
    /// The cash or bank account the money for a new investment came out of. Empty means none.
    @State private var paidFromUID = ""
    @State private var sipOn: Bool
    @State private var sipAmount: Decimal?
    @State private var sipDay: Int
    @State private var sipAccountUID: String
    @State private var moneyMode: HoldingMoneySheet.Mode?

    init(holding: Holding? = nil) {
        self.holding = holding
        _kind = State(initialValue: holding?.kind ?? .stock)
        _name = State(initialValue: holding?.name ?? "")
        _platform = State(initialValue: holding?.platform ?? "")
        _investedAmount = State(initialValue: holding.flatMap { $0.investedAmount > 0 ? $0.investedAmount : nil })
        _currentValue = State(initialValue: holding?.currentValue)
        _quantity = State(initialValue: holding?.quantity)
        _interestRate = State(initialValue: holding?.interestRate)
        _hasMaturity = State(initialValue: holding?.maturityDate != nil)
        _maturityDate = State(
            initialValue: holding?.maturityDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        )
        _note = State(initialValue: holding?.note ?? "")
        _sipOn = State(initialValue: holding?.hasSIP ?? false)
        _sipAmount = State(initialValue: holding?.sipAmount)
        _sipDay = State(initialValue: holding?.hasSIP == true ? holding?.sipDay ?? 5 : 5)
        _sipAccountUID = State(initialValue: holding?.sipAccountUID ?? "")
    }

    /// This investment's money moves, newest first.
    private var moves: [Transfer] {
        guard let uid = holding?.uid, !uid.isEmpty else { return [] }
        return investmentMoves.filter { $0.holdingUID == uid }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Falls back to the invested amount when no current value is entered (e.g. a new FD).
    private var finalValue: Decimal {
        currentValue ?? (kind.tracksInvested ? investedAmount : nil) ?? 0
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty && finalValue > 0 else { return false }
        // A SIP needs an amount and an account to take it from.
        if sipOn && !kind.isDebt {
            return (sipAmount ?? 0) > 0 && paymentAccounts.contains { $0.uid == sipAccountUID }
        }
        return true
    }

    /// Cash and bank accounts a new investment can be paid from.
    private var paymentAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    /// Paying from an account only applies to a new investment with an amount put in.
    private var offersPaidFrom: Bool {
        holding == nil && !kind.isDebt && kind.tracksInvested && (investedAmount ?? 0) > 0 && !paymentAccounts.isEmpty
    }

    /// Suggested platforms: common ones for this type plus any you've used before.
    private var platformSuggestions: [String] {
        let previous = allHoldings
            .filter { $0.kind.isMarketLinked == kind.isMarketLinked && $0.kind.isDebt == kind.isDebt }
            .map(\.platform)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (kind.suggestedPlatforms + previous)
            .filter { seen.insert($0.lowercased()).inserted }
            .filter { $0.caseInsensitiveCompare(platform) != .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind.animation()) {
                        Section("Investments & Savings") {
                            ForEach(HoldingKind.assetKinds) { kind in
                                Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                        Section("Debt") {
                            ForEach(HoldingKind.debtKinds) { kind in
                                Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                    }
                    TextField(kind.namePlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(kind.platformLabel, text: $platform)
                        .textInputAutocapitalization(.words)
                    if !platformSuggestions.isEmpty {
                        platformChips
                    }
                }

                Section {
                    if kind.tracksQuantity {
                        TextField("Units / Shares (optional)", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    if kind.tracksInvested {
                        TextField(kind.investedLabel, value: $investedAmount, format: .rupees)
                            .keyboardType(.decimalPad)
                    }
                    TextField(kind.valueLabel, value: $currentValue, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                    if kind.tracksInterest {
                        TextField("Interest Rate % p.a. (optional)", value: $interestRate, format: .number)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if kind.tracksInvested {
                        Text("Leave \(kind.valueLabel) empty to use the \(kind.investedLabel.lowercased()). Update it whenever you check your app or bank.")
                    }
                }

                if offersPaidFrom {
                    Section {
                        Picker("Paid From", selection: $paidFromUID) {
                            Text("Not from an account").tag("")
                            ForEach(paymentAccounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                    } header: {
                        Text("Where The Money Came From")
                    } footer: {
                        Text("Choose the account you paid with, and its balance goes down by the amount you put in. Without this, the money is counted twice in your net worth: once in the account and again here.")
                    }
                }

                if let holding, holding.movesMoney, !kind.isDebt {
                    moneySection(holding)
                }

                if !kind.isDebt, !paymentAccounts.isEmpty {
                    sipSection
                }

                if kind.tracksMaturity {
                    Section("Maturity") {
                        Toggle("Has Maturity Date", isOn: $hasMaturity.animation())
                        if hasMaturity {
                            DatePicker("Matures On", selection: $maturityDate, displayedComponents: .date)
                        }
                    }
                }

                Section("Note") {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }

                if let holding {
                    Section {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(holding)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(holding == nil ? (kind.isDebt ? "Add Debt" : "Add Investment") : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $moneyMode, onDismiss: refreshAmounts) { mode in
                if let holding {
                    HoldingMoneySheet(holding: holding, mode: mode)
                }
            }
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

    /// Tap-to-fill chips for platforms/banks.
    private var platformChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(platformSuggestions, id: \.self) { name in
                    Button(name) { platform = name }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
    }

    private func save() {
        guard isValid else { return }

        // Drop values that don't apply to the selected type.
        let invested = kind.tracksInvested ? (investedAmount ?? 0) : 0
        let units = kind.tracksQuantity ? quantity : nil
        let rate = kind.tracksInterest ? interestRate : nil
        let maturity = kind.tracksMaturity && hasMaturity ? maturityDate : nil
        let trimmedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let holding {
            holding.kind = kind
            holding.name = trimmedName
            holding.platform = trimmedPlatform
            holding.investedAmount = invested
            holding.currentValue = finalValue
            holding.quantity = units
            holding.interestRate = rate
            holding.maturityDate = maturity
            holding.note = trimmedNote
            holding.updatedAt = .now
            applySIP(to: holding)
        } else {
            // The money put in leaves the account it was paid from. It isn't spending, so it is a one-sided transfer.
            var payment: Transfer?
            if offersPaidFrom, let account = paymentAccounts.first(where: { $0.uid == paidFromUID }), invested > 0 {
                let transfer = Transfer(amount: invested, date: .now, note: "Invested in \(trimmedName)")
                modelContext.insert(transfer)
                transfer.fromAccount = account
                payment = transfer
            }
            let newHolding = Holding(
                name: trimmedName,
                kind: kind,
                platform: trimmedPlatform,
                investedAmount: invested,
                currentValue: finalValue,
                quantity: units,
                interestRate: rate,
                maturityDate: maturity,
                note: trimmedNote
            )
            modelContext.insert(newHolding)
            // The first payment shows in this investment's history.
            payment?.holdingUID = newHolding.uid
            applySIP(to: newHolding)
        }
        try? modelContext.save()
        // A SIP whose day is today is added now.
        SIPPoster.run(in: modelContext)
        dismiss()
    }
}

extension HoldingFormView {
    /// Add Money and Withdraw, with every amount moved so far.
    private func moneySection(_ holding: Holding) -> some View {
        Section {
            HStack {
                Button("Add Money", systemImage: "plus.circle") { moneyMode = .add }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Withdraw", systemImage: "minus.circle") { moneyMode = .withdraw }
                    .buttonStyle(.bordered)
                    .disabled(holding.currentValue <= 0)
            }
            ForEach(moves) { move in
                let isIn = move.investedEffect > 0
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isIn ? "Put in" : "Taken out")
                        Text("\(move.date.formatted(.dateTime.day().month().year())) · \((isIn ? move.fromAccount : move.toAccount)?.displayName ?? "account")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(isIn ? "+" : "−")\(move.amount.formatted(.rupees))")
                        .foregroundStyle(isIn ? .primary : Color.green)
                }
            }
        } header: {
            Text("Money In and Out")
        } footer: {
            Text("Moves money between this investment and your accounts, so both stay right. Update the value as usual when it changes in the market.")
        }
    }

    private var sipSection: some View {
        Section {
            Toggle("Monthly SIP", isOn: $sipOn.animation())
            if sipOn {
                TextField("SIP Amount", value: $sipAmount, format: .rupees)
                    .keyboardType(.decimalPad)
                Picker("Day of Month", selection: $sipDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Picker("Paid From", selection: $sipAccountUID) {
                    Text("Choose").tag("")
                    ForEach(paymentAccounts) { account in
                        Text(account.displayName).tag(account.uid)
                    }
                }
            }
        } header: {
            Text("SIP")
        } footer: {
            if sipOn {
                Text("On day \(sipDay) each month, the SIP amount is taken from the account and added to this investment. It starts from the next SIP day, and coming SIPs are counted in Monthly and Budget for the months ahead.")
            } else {
                Text("Turn on to add a fixed amount every month on its own.")
            }
        }
    }

    /// The form's amounts after money was added or taken out, so Save doesn't put back the old ones.
    private func refreshAmounts() {
        guard let holding else { return }
        currentValue = holding.currentValue
        investedAmount = holding.investedAmount > 0 ? holding.investedAmount : nil
    }

    /// Saves the SIP. Starting it, or changing its day or amount, starts it from the next SIP day.
    private func applySIP(to holding: Holding) {
        guard sipOn, !kind.isDebt, let amount = sipAmount, amount > 0 else {
            holding.sipAmountPaise = 0
            holding.sipStartDate = nil
            holding.sipLastPosted = nil
            return
        }
        let isChanged = !holding.hasSIP || holding.sipDay != sipDay || holding.sipAmount != amount
            || holding.sipAccountUID != sipAccountUID
        holding.sipAmount = amount
        holding.sipDay = sipDay
        holding.sipAccountUID = sipAccountUID
        holding.ensureUID()
        if isChanged {
            // Never adds months before today. What was already added stays.
            holding.sipStartDate = .now
        }
    }
}

#Preview {
    HoldingFormView()
        .modelContainer(for: [Holding.self, Account.self, Transfer.self], inMemory: true)
}
