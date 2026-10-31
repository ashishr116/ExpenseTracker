//
//  AccountDetailView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// One account's balance and every movement that built it, with a way to match it to the real balance.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loans: [Loan]
    @Query private var repayments: [LoanRepayment]
    @Query private var transfers: [Transfer]
    @Query private var savedCards: [PaymentCard]
    @Environment(\.openURL) private var openURL

    let account: Account

    @State private var isEditing = false
    @State private var isReconciling = false
    @State private var isPayingBill = false
    /// The friend being reminded about this card's bill, and how.
    @State private var remindingShare: CardBillShare?
    @State private var isChoosingChannel = false
    @State private var reminder: LoanReminder?

    /// The saved card that holds this credit card's bill dates.
    private var card: PaymentCard? {
        account.kind == .creditCard ? savedCards.first { $0.accountUID == account.uid } : nil
    }

    private var ledger: AccountLedger {
        AccountLedger(
            accounts: accounts, expenses: expenses, incomes: incomes,
            loans: loans, repayments: repayments, transfers: transfers
        )
    }

    var body: some View {
        let ledger = ledger
        let balance = ledger.balance(of: account)
        let lines = ledger.lines(for: account)
        let runningBalances = runningBalances(for: lines)
        // A card paid past zero is in credit: the bank owes you, so it is shown as a positive credit.
        let isInCredit = account.kind.isLiability && balance < 0
        // Friends' purchases on this card. They are not your spending or your debt.
        let lentLines = ledger.lentLines(for: account)
        let lent = ledger.lentOutstanding(of: account)
        let hasFriends = account.kind.isLiability && !lentLines.isEmpty
        let lentRunning = lentRunningBalances(for: lentLines)

        List {
            Section {
                if hasFriends {
                    // The total comes first, matching the card's row in the list. Below it, the two parts.
                    LabeledContent("Total on Card") {
                        Text(balance + lent, format: .rupees)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(balance + lent > 0 ? Color.red : Color.primary)
                    }
                    LabeledContent("Mine") {
                        Text(balance, format: .rupees)
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Lent to Friends") {
                        Text(lent, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                } else {
                    LabeledContent(isInCredit ? "In Credit" : account.kind.balanceLabel) {
                        Text(isInCredit ? -balance : balance, format: .rupees)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(
                                isInCredit ? Color.green
                                    : (account.kind.isLiability ? (balance > 0 ? Color.red : Color.primary) : (balance < 0 ? Color.red : Color.primary))
                            )
                    }
                }
                LabeledContent("Opening \(account.kind.balanceLabel)") {
                    Text(account.openingBalance, format: .rupees)
                }
                LabeledContent("Counting From") {
                    Text(account.openingDate, format: .dateTime.day().month().year())
                }
            } footer: {
                if hasFriends {
                    Text("Mine is what you owe for your own spending. Lent to friends is what they owe the card, so Total on Card should match your bank's statement.")
                } else {
                    Text("Entries before this date are already part of the opening figure and aren't counted again.")
                }
            }

            Section {
                if account.kind == .creditCard, !account.isArchived {
                    Button("Pay Bill", systemImage: "creditcard.and.123") {
                        isPayingBill = true
                    }
                }
                Button("Match Real \(account.kind.balanceLabel)", systemImage: "checkmark.seal") {
                    isReconciling = true
                }
                Button("Edit Account", systemImage: "pencil") {
                    isEditing = true
                }
            }

            if account.kind == .creditCard, !account.isArchived {
                billSection(statement: card.flatMap {
                    CardBill.statement(for: $0, lines: lines, lentLines: lentLines, owed: balance + lent)
                })
            }

            Section(hasFriends ? "My Movements" : "Movements") {
                if lines.isEmpty {
                    Text("Nothing has moved this account since it was opened.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(lines) { line in
                    LedgerLineRow(
                        line: line,
                        isLiability: account.kind.isLiability,
                        balanceAfter: runningBalances[line.id]
                    )
                        .swipeActions {
                            // Only transfers and adjustments are removed here. Other entries are edited where they were made.
                            if let transfer = line.transfer {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(transfer)
                                }
                            }
                        }
                }
            }

            if hasFriends {
                Section {
                    ForEach(lentLines) { line in
                        LedgerLineRow(
                            line: line,
                            isLiability: false,
                            balanceAfter: lentRunning[line.id],
                            isFriendLine: true
                        )
                    }
                } header: {
                    Text("Loaned to Friends")
                } footer: {
                    Text("Friends' purchases on this card. They pay the bank directly. Record each payment from Loans, and it comes off here. None of this is counted in your spending or your net worth.")
                }
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            AccountFormView(account: account)
        }
        .sheet(isPresented: $isReconciling) {
            // A card statement includes friends' purchases, so compare against mine plus theirs.
            ReconcileView(account: account, computedBalance: balance + lent, friendsShare: lent)
        }
        .sheet(isPresented: $isPayingBill) {
            TransferFormView(payingCard: account, owed: balance)
        }
        .sheet(item: $reminder) { reminder in
            ReminderSheet(reminder: reminder) {
                // Note when each friend was last reminded.
                for loan in reminder.loans { loan.lastRemindedAt = .now }
            }
        }
        .confirmationDialog(
            "Remind \(remindingShare?.friendName ?? "Friend")",
            isPresented: $isChoosingChannel,
            titleVisibility: .visible
        ) {
            Button("Message", systemImage: "message") { sendReminder(.messages) }
            Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") { sendReminder(.whatsApp) }
            Button("PDF Statement", systemImage: "doc.richtext") {
                if let share = remindingShare,
                   let url = LoanStatementPDF.statement(for: share.friendName, loans: share.loans) {
                    SharePresenter.present(urls: [url])
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Bill

    /// When the bill is generated and due, and what each friend who used the card should pay towards it.
    @ViewBuilder
    private func billSection(statement: CardStatement?) -> some View {
        let dueDate = card?.nextDueDate()
        let shares = CardBill.friendShares(bankName: account.bankName, lastFour: account.cardLastFour, loans: loans)

        Section {
            if let card, card.hasDueDate, let dueDate {
                if let statement {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(statement.billed, format: .rupees)
                                .fontWeight(.semibold)
                                .foregroundStyle(statement.billed > 0 ? Color.red : Color.green)
                            Text(statement.billed > 0 ? "Bill of \(statement.billDate.formatted(.dateTime.day().month()))" : "Nothing left to pay")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Billed")
                    }
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(statement.unbilled, format: .rupees)
                                .fontWeight(.semibold)
                            Text("Since \(statement.billDate.formatted(.dateTime.day().month()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Unbilled")
                    }
                }
                if let statement = card.nextStatementDate() {
                    LabeledContent("Next Bill Generated") {
                        Text(statement, format: .dateTime.day().month().year())
                    }
                }
                LabeledContent("Payment Due") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(dueDate, format: .dateTime.day().month().year())
                            .fontWeight(.semibold)
                        Text(Self.countdown(to: dueDate))
                            .font(.caption)
                            .foregroundStyle(Self.daysUntil(dueDate) <= 3 ? Color.red : Color.secondary)
                    }
                }
                ForEach(shares) { share in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.friendName)
                            Text("Their part of this bill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(share.amount, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Button("Remind \(share.friendName)", systemImage: "message.circle.fill") {
                            remindingShare = share
                            isChoosingChannel = true
                        }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        // Borderless so the tap doesn't count for the whole row.
                        .buttonStyle(.borderless)
                    }
                }
            } else {
                Button("Set Bill Dates", systemImage: "calendar.badge.clock") {
                    isEditing = true
                }
            }
        } header: {
            Text("Bill")
        } footer: {
            if card?.hasDueDate == true {
                Text(shares.isEmpty
                     ? "You'll get a reminder 3 days and 1 day before the due date."
                     : "You'll get a reminder 3 days and 1 day before the due date, saying who to remind. Friends pay the bank directly. The button opens a message or WhatsApp with the amount and due date already written.")
            } else {
                Text("Add the day your bill is generated. The due date is taken as 18 days later unless you set it, and you get reminders before it falls due.")
            }
        }
    }

    /// Opens the reminder for the friend chosen in the dialog.
    private func sendReminder(_ channel: ReminderChannel) {
        guard let share = remindingShare, let due = card?.nextDueDate() else { return }
        var message = LoanReminder(friendName: share.friendName, loans: share.loans, phone: share.phone)
        let cardName = account.bankName.isEmpty ? "credit card" : "\(account.bankName) credit card"
        message.billDue = CardBillDue(cardName: cardName, date: due)

        switch channel {
        case .messages:
            reminder = message
        case .whatsApp:
            guard let url = message.whatsAppURL else { return }
            openURL(url)
            // WhatsApp can't say whether it was sent, so it is noted when WhatsApp opens.
            for loan in share.loans { loan.lastRemindedAt = .now }
        }
    }

    private static func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "Today", "Tomorrow" or "In 12 days".
    private static func countdown(to date: Date) -> String {
        switch daysUntil(date) {
        case ..<1: "Due today"
        case 1: "Tomorrow"
        case let days: "In \(days) days"
        }
    }

    /// What friends owed the card after each of their purchases or repayments, adding up from zero.
    private func lentRunningBalances(for lines: [LedgerLine]) -> [String: Decimal] {
        var running: Decimal = 0
        var result: [String: Decimal] = [:]
        for line in lines.reversed() {
            running += line.effect
            result[line.id] = running
        }
        return result
    }

    /// What the account showed after each movement, found by adding the movements up from the opening balance.
    private func runningBalances(for lines: [LedgerLine]) -> [String: Decimal] {
        var running = account.openingBalance
        var result: [String: Decimal] = [:]
        // The lines are newest first, so add them up oldest first.
        for line in lines.reversed() {
            running += line.effect
            result[line.id] = running
        }
        return result
    }
}

// MARK: - Reconcile

/// Compares the computed balance with the real one and posts the difference as an adjustment.
struct ReconcileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account
    /// What the app shows. For a credit card this is the whole statement: your part plus friends' purchases.
    let computedBalance: Decimal
    /// For a credit card: the part of `computedBalance` that friends owe.
    var friendsShare: Decimal = 0

    @State private var actual: Decimal?

    private var difference: Decimal {
        (actual ?? computedBalance) - computedBalance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("In the App") {
                        Text(computedBalance, format: .rupees)
                    }
                    TextField("Real \(account.kind.balanceLabel)", value: $actual, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                } header: {
                    Text("Check Against Your Statement")
                } footer: {
                    Text(account.kind.isLiability
                         ? (friendsShare > 0
                            ? "Enter the total your card statement or app shows right now. That includes the \(friendsShare.formatted(.rupees)) friends owe on this card, which the app adds to your part."
                            : "Enter the amount your card statement or app says you owe right now.")
                         : "Enter the balance your bank app or statement shows right now, or the cash you are holding.")
                }

                if actual != nil {
                    Section {
                        if difference == 0 {
                            Label("Matches. Nothing to fix.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            LabeledContent("Difference") {
                                Text("\(difference > 0 ? "+" : "")\(difference.formatted(.rupees))")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } footer: {
                        if difference != 0 {
                            Text("A difference usually means an entry is missing or has the wrong bank. Check the entries first. If you can't find it, post an adjustment to bring the balance in line.")
                        }
                    }
                }
            }
            .navigationTitle("Match Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post Adjustment", action: postAdjustment)
                        .disabled(actual == nil || difference == 0)
                }
            }
        }
    }

    /// Adds a one-sided transfer so the balance equals the real one.
    private func postAdjustment() {
        guard difference != 0 else { return }
        let adjustment = Transfer(amount: abs(difference), date: .now, note: "Matched to real balance")
        modelContext.insert(adjustment)

        // For money you hold, a higher balance means money came in. A credit card is the other way round:
        // a higher amount owed means money was drawn from it.
        let raisesFigure = difference > 0
        let movesInto = account.kind.isLiability ? !raisesFigure : raisesFigure
        if movesInto {
            adjustment.toAccount = account
        } else {
            adjustment.fromAccount = account
        }
        dismiss()
    }
}
