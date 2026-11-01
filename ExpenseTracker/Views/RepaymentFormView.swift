//
//  RepaymentFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for recording a payment a friend has made towards a loan. It can be less than the full balance.
/// For credit card loans, the friend can pay the card or pay you, or you can record that you paid the card bill yourself,
/// which moves the debt to a cash loan. For a personal loan in your name, you can record that you paid the EMI yourself.
struct RepaymentFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let loan: Loan

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    enum RepayMode: String, CaseIterable, Identifiable {
        case friendPaid
        /// A card loan only: the friend paid you, and you pay the card.
        case paidMe
        case iPaid
        var id: String { rawValue }
    }

    /// The choices for this loan. A cash loan has none: the friend always pays you.
    private var modes: [RepayMode] {
        switch loan.method {
        case .cash: []
        case .card: [.friendPaid, .paidMe, .iPaid]
        case .personalLoan: [.friendPaid, .iPaid]
        }
    }

    private func title(of mode: RepayMode) -> String {
        switch (mode, loan.method) {
        case (.friendPaid, .personalLoan): "Friend Paid the EMI"
        case (.friendPaid, _): "Friend Paid the Card"
        case (.paidMe, _): "Friend Paid Me"
        case (.iPaid, .personalLoan): "I Paid the EMI Myself"
        case (.iPaid, _): "I Paid the Card Myself"
        }
    }

    /// You paid the card or the EMI for the friend, so it becomes a cash loan.
    private var isCovering: Bool { repayMode == .iPaid && loan.method.isOnMyName }

    @State private var repayMode: RepayMode
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""
    /// The bank the money arrived in. Empty means cash.
    @State private var receivedIn: String
    /// The bank/cash account paid from when you cover the card bill.
    @State private var fromUID: String = ""

    init(loan: Loan, initialMode: RepayMode = .friendPaid) {
        self.loan = loan
        _repayMode = State(initialValue: initialMode)
        // Start with the full balance; change it for a part payment.
        _amount = State(initialValue: loan.outstandingAmount)
        // By default the money comes back to the account it was lent from.
        _receivedIn = State(initialValue: loan.method == .cash ? loan.bankName : "")
    }

    /// Banks of your open bank accounts, one entry per bank.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var eligibleAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    private var fromAccount: Account? {
        eligibleAccounts.first { $0.uid == fromUID }
    }

    private var isValid: Bool {
        guard let amount else { return false }
        if amount <= 0 || amount > loan.outstandingAmount { return false }
        if isCovering && fromAccount == nil {
            return false
        }
        return true
    }

    /// What will still be owed after this payment.
    private var balanceAfter: Decimal {
        max(0, loan.outstandingAmount - (amount ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Friend", value: loan.friendName)
                    LabeledContent("Lent") {
                        Text(loan.amount, format: .rupees)
                    }
                    if loan.repaidAmount > 0 {
                        LabeledContent("Repaid So Far") {
                            Text(loan.repaidAmount, format: .rupees)
                                .foregroundStyle(.green)
                        }
                    }
                    LabeledContent("Still Owed") {
                        Text(loan.outstandingAmount, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    if loan.method == .card, let cardDesc = loan.cardDescription {
                        LabeledContent("Card", value: cardDesc)
                    }
                }

                if !modes.isEmpty {
                    Section {
                        Picker("Repayment Option", selection: $repayMode) {
                            ForEach(modes) { mode in
                                Text(title(of: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Who Paid")
                    } footer: {
                        switch repayMode {
                        case .friendPaid:
                            Text(loan.method == .card
                                 ? "\(loan.friendName) paid the credit card company directly. Nothing moves in your accounts."
                                 : "\(loan.friendName) paid this month's EMI, to the bank or to you to pass on. Nothing moves in your accounts.")
                        case .paidMe:
                            Text("\(loan.friendName) sent the money to you. It goes into your account, and their share of the card becomes yours, so pay the full bill from Pay Bill as usual.")
                        case .iPaid:
                            Text(loan.method == .card
                                 ? "\(loan.friendName) hasn't paid and you paid the card bill yourself. It clears this card loan and moves the amount to a cash loan owed by \(loan.friendName) to you."
                                 : "\(loan.friendName) hasn't paid and the EMI came out of your account. It moves the amount to a cash loan owed by \(loan.friendName) to you.")
                        }
                    }
                }

                Section {
                    TextField(isCovering ? "Amount Paid for Friend" : "Amount Received", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))

                    DatePicker(isCovering ? "Paid On" : "Received On", selection: $date, displayedComponents: .date)

                    if isCovering {
                        if eligibleAccounts.isEmpty {
                            Text("Add a bank account or cash first so there is somewhere to pay from.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Paid From", selection: $fromUID) {
                                ForEach(eligibleAccounts) { account in
                                    Text(account.displayName).tag(account.uid)
                                }
                            }
                        }
                    } else if loan.method == .cash || repayMode == .paidMe, !bankChoices.isEmpty {
                        Picker("Received In", selection: $receivedIn) {
                            Text("Cash").tag("")
                            ForEach(bankChoices, id: \.self) { bank in
                                Text(BankName.display(bank)).tag(bank)
                            }
                        }
                    }

                    TextField("Note (optional)", text: $note)
                } header: {
                    Text(isCovering ? "Payment You Made" : "Payment")
                } footer: {
                    if let amount, amount > loan.outstandingAmount {
                        Text("That's more than the \(loan.outstandingAmount.formatted(.rupees)) still owed.")
                            .foregroundStyle(.red)
                    } else if isValid {
                        if isCovering {
                            Text(loan.method == .card
                                 ? "Takes \(amount?.formatted(.rupees) ?? "this") off their card loan, creates a cash loan to \(loan.friendName) from \(fromAccount?.displayName ?? "account"), and lowers that account once. Pay the rest of the bill from the card's Pay Bill as usual: don't include their share in it."
                                 : "Takes \(amount?.formatted(.rupees) ?? "this") off their personal loan, creates a cash loan to \(loan.friendName) from \(fromAccount?.displayName ?? "account"), and lowers that account once.")
                        } else {
                            Text(balanceAfter == 0
                                 ? "This clears the loan."
                                 : "\(balanceAfter.formatted(.rupees)) will still be owed after this payment.")
                        }
                    }
                }

            }
            .navigationTitle(isCovering ? (loan.method == .card ? "I Paid Card Bill" : "I Paid the EMI") : "Record Repayment")
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
            .onAppear {
                if fromUID.isEmpty {
                    fromUID = eligibleAccounts.first?.uid ?? ""
                }
                // A friend paying you for a card loan usually sends it to a bank.
                if loan.method == .card, receivedIn.isEmpty {
                    receivedIn = bankChoices.first ?? ""
                }
            }
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if isCovering {
            let repaymentNote = trimmedNote.isEmpty
                ? (loan.method == .card ? "Card paid for loan" : "EMI paid for loan")
                : trimmedNote
            loan.recordRepayment(amount, on: date, note: repaymentNote, bankName: "", in: modelContext)

            let fromAcc = fromAccount
            let newCashLoan = Loan(
                amount: amount,
                friendName: loan.friendName,
                friendPhone: loan.friendPhone,
                note: repaymentNote,
                date: date,
                method: .cash,
                bankName: fromAcc?.kind == .bank ? (fromAcc?.bankName ?? "") : ""
            )
            modelContext.insert(newCashLoan)
        } else if repayMode == .paidMe && loan.method == .card {
            let repayment = loan.recordRepayment(
                amount, on: date, note: trimmedNote.isEmpty ? "Paid to you" : trimmedNote,
                bankName: receivedIn, in: modelContext
            )
            repayment?.receivedByMe = true
        } else {
            loan.recordRepayment(amount, on: date, note: trimmedNote, bankName: loan.method == .cash ? receivedIn : "", in: modelContext)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Loan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let loan = Loan(amount: 5000, friendName: "Rahul")
    container.mainContext.insert(loan)
    return RepaymentFormView(loan: loan)
        .modelContainer(container)
}
