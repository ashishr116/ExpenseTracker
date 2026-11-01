//
//  AccountsView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Bank accounts, cash and credit cards, each with a balance worked out from your entries.
struct AccountsView: View {
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loans: [Loan]
    @Query private var repayments: [LoanRepayment]
    @Query private var transfers: [Transfer]
    @Query private var borrowings: [Borrowing]
    @Query private var borrowingPayments: [BorrowingPayment]
    @Query private var savedCards: [PaymentCard]

    @State private var isAddingAccount = false
    @State private var isAddingTransfer = false

    private var ledger: AccountLedger {
        AccountLedger(
            accounts: accounts, expenses: expenses, incomes: incomes,
            loans: loans, repayments: repayments, transfers: transfers,
            borrowings: borrowings, borrowingPayments: borrowingPayments
        )
    }

    /// The next day this credit card's bill is due, if its dates are set.
    private func dueDate(of account: Account) -> Date? {
        guard account.kind == .creditCard, !account.isArchived else { return nil }
        return savedCards.first { $0.accountUID == account.uid }?.nextDueDate()
    }

    /// Cash, transfer and personal loans friends still owe. Loans on your card are in "Friends Owe on Cards".
    private var friendsOweMe: Decimal {
        loans.filter { !$0.isRepaid && $0.method != .card }.outstandingTotal
    }

    /// Money borrowed from friends and not yet paid back.
    private var iOweFriends: Decimal {
        borrowings.filter { !$0.isRepaid }.outstandingTotal
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    var body: some View {
        let ledger = ledger
        List {
            if accounts.isEmpty {
                introSection
            } else {
                summarySection(ledger)
                unlinkedSection(ledger)

                ForEach(AccountKind.allCases) { kind in
                    let items = activeAccounts.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section(kind.rawValue) {
                            ForEach(items) { account in
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    AccountRow(
                                        account: account,
                                        balance: ledger.balance(of: account),
                                        lent: ledger.lentOutstanding(of: account),
                                        due: dueDate(of: account)
                                    )
                                }
                            }
                        }
                    }
                }

                if !archivedAccounts.isEmpty {
                    Section("Closed") {
                        ForEach(archivedAccounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountRow(
                                        account: account,
                                        balance: ledger.balance(of: account),
                                        lent: ledger.lentOutstanding(of: account),
                                        due: dueDate(of: account)
                                    )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Add", systemImage: "plus") {
                    Button("Add Account", systemImage: "building.columns") { isAddingAccount = true }
                    Button("Add Transfer", systemImage: "arrow.left.arrow.right") { isAddingTransfer = true }
                        .disabled(activeAccounts.count < 2)
                }
            }
        }
        .sheet(isPresented: $isAddingAccount) {
            AccountFormView()
        }
        .sheet(isPresented: $isAddingTransfer) {
            TransferFormView()
        }
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            Label("Track where your money is", systemImage: "building.columns")
                .font(.headline)
            Text("Add each bank account, your cash and every credit card once, with what it holds today. From then on, income, spending and loans move these balances, and net worth uses them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add Your First Account", systemImage: "plus") { isAddingAccount = true }
        }
    }

    private func summarySection(_ ledger: AccountLedger) -> some View {
        let assets = ledger.assetTotal
        let dues = ledger.cardDuesTotal
        return Section {
            LabeledContent("In Bank & Cash") {
                Text(assets, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(assets >= 0 ? Color.green : Color.red)
            }
            if dues != 0 {
                LabeledContent(dues < 0 ? "Credit on Cards" : "Owed on Cards") {
                    Text(abs(dues), format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(dues < 0 ? Color.green : Color.red)
                }
            }
            // Friends' purchases on your cards: shown for reference, and not part of what you owe or your net.
            if ledger.lentTotal > 0 {
                LabeledContent("Friends Owe on Cards") {
                    Text(ledger.lentTotal, format: .rupees)
                        .foregroundStyle(.orange)
                }
            }
            // Money out with friends, apart from card purchases (those are the line above). Not in Net.
            if friendsOweMe > 0 {
                NavigationLink {
                    LoansView()
                } label: {
                    LabeledContent("Friends Owe Me") {
                        Text(friendsOweMe, format: .rupees)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if iOweFriends > 0 {
                NavigationLink {
                    BorrowedView()
                } label: {
                    LabeledContent("I Owe Friends") {
                        Text(iOweFriends, format: .rupees)
                            .foregroundStyle(.red)
                    }
                }
            }
            LabeledContent("Net") {
                Text(assets - dues, format: .rupees)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(assets - dues >= 0 ? Color.green : Color.red)
            }
        }
    }

    @ViewBuilder
    private func unlinkedSection(_ ledger: AccountLedger) -> some View {
        let lines = ledger.unlinked
        if !lines.isEmpty {
            Section {
                NavigationLink {
                    UnlinkedEntriesView(lines: lines)
                } label: {
                    Label(
                        "\(lines.count) entr\(lines.count == 1 ? "y" : "ies") not linked to an account",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            } footer: {
                Text("These don't change any balance, so the balances may be off. Open them to see what's missing.")
            }
        }
    }
}

// MARK: - Row

private struct AccountRow: View {
    let account: Account
    let balance: Decimal
    /// For a credit card: what friends still owe on it. The row shows it added to your own amount, as the
    /// card's total. Open the card to see the two apart.
    var lent: Decimal = 0
    /// For a credit card: when its bill is next due.
    var due: Date?

    var body: some View {
        // What the bank's statement shows: your part plus your friends'.
        let hasFriends = account.kind.isLiability && lent > 0
        let balance = hasFriends ? self.balance + lent : self.balance

        HStack(spacing: 12) {
            Image(systemName: account.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.body.weight(.medium))
                if !account.detail.isEmpty {
                    Text(account.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let due {
                    // Turns red in the last three days, when a reminder is due.
                    let days = Calendar.current.dateComponents(
                        [.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: due)
                    ).day ?? 0
                    Text("Bill due \(due.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(days <= 3 ? Color.red : Color.secondary)
                }
            }
            // Keep the name on one line when the amounts on the right are wide.
            .layoutPriority(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // A card paid past zero is in credit, shown as a positive amount in green.
                if account.kind.isLiability, balance < 0 {
                    Text(-balance, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Text("credit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(balance, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(account.kind.isLiability ? (balance > 0 ? Color.red : Color.primary) : (balance < 0 ? Color.red : Color.primary))
                    if account.kind.isLiability {
                        Text(hasFriends ? "on card" : "owed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Unlinked entries

/// Entries that belong to no account, so they change no balance.
struct UnlinkedEntriesView: View {
    let lines: [LedgerLine]

    var body: some View {
        List {
            Section {
                ForEach(lines) { line in
                    // A friend's card loan on a card that isn't an account: what they owe, not money in.
                    LedgerLineRow(line: line, isLiability: false, isFriendLine: line.id.hasPrefix("card-loan-unlinked"))
                }
            } footer: {
                Text("To link an entry, give it the same bank name, and card digits for a credit card, as one of your accounts. Cash spending needs a Cash account. Income needs a bank. Loans take the account they were paid from. A loan on your card needs that card added under Accounts.")
            }
        }
        .navigationTitle("Not Linked")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One movement: the title, where it came from, the date and its effect.
struct LedgerLineRow: View {
    let line: LedgerLine
    /// For a credit card, an increase is money owed, so it is shown in red.
    let isLiability: Bool
    /// What the account showed after this entry. Shown under the amount when given.
    var balanceAfter: Decimal?
    /// A friend's purchase on your card or their repayment. These are what friends owe the card, not your
    /// own spending, so they use their own colours and wording.
    var isFriendLine = false

    private var color: Color {
        if isFriendLine { return line.effect > 0 ? .orange : .green }
        if line.effect == 0 { return .secondary }
        let isIncrease = line.effect > 0
        return (isIncrease != isLiability) ? .green : .red
    }

    /// "Owed ₹4,000", "Credit ₹500", "Settled" or "Balance ₹9,000".
    private func balanceText(_ value: Decimal) -> String {
        if isFriendLine {
            return value > 0 ? "Friends owe \(value.formatted(.rupees))" : "Settled"
        }
        if isLiability {
            if value > 0 { return "Owed \(value.formatted(.rupees))" }
            if value < 0 { return "Credit \((-value).formatted(.rupees))" }
            return "Settled"
        }
        return "Balance \(value.formatted(.rupees))"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(line.date, format: .dateTime.day().month().year())
                    if !line.subtitle.isEmpty {
                        Text("· \(line.subtitle)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(line.effect > 0 ? "+" : "")\(line.effect.formatted(.rupees))")
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                if let balanceAfter {
                    Text(balanceText(balanceAfter))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountsView()
    }
    .modelContainer(for: [Account.self, Transfer.self, Expense.self, Income.self, Loan.self], inMemory: true)
}
