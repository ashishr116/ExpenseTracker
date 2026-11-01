//
//  LoansView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import ContactsUI

/// All money lent to friends: outstanding loans grouped by friend, plus repaid history.
struct LoansView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Loan.date, order: .reverse) private var loans: [Loan]
    /// Your own EMIs, for the PDF summary.
    @Query private var emis: [EMI]
    /// Borrowed amounts, to show cross-summary in statements & summary PDF.
    @Query(sort: \Borrowing.date, order: .reverse) private var borrowings: [Borrowing]

    @State private var isAddingLoan = false
    /// A saved friend a new loan is being added for, with their name and number filled in.
    @State private var addingLoanFor: LoanFriend?
    @State private var editingLoan: Loan?
    /// The loan a friend is paying part of back.
    @State private var repaymentLoan: Loan?
    /// The friend and their card loans whose bill you are paying yourself to move to cash.
    @State private var coveringCardFriend: FriendCardLoans?
    /// The payment reminder currently being composed.
    @State private var reminder: LoanReminder?

    // Used when a friend has no phone number saved yet: choose one from Contacts before reminding.
    /// The friend and loans a reminder is waiting to be sent for.
    @State private var waitingFriend = ""
    @State private var waitingLoans: [Loan] = []
    @State private var isAskingForNumber = false
    /// Asked first: send the reminder as a text message or on WhatsApp.
    @State private var isChoosingChannel = false
    @State private var waitingChannel = ReminderChannel.messages
    @State private var phoneChoices: [CNLabeledValue<CNPhoneNumber>] = []
    @State private var isChoosingPhone = false

    private var outstanding: [Loan] { loans.filter { !$0.isRepaid } }
    private var repaid: [Loan] { loans.filter(\.isRepaid) }

    /// Outstanding loans grouped by friend (case-insensitive), largest amount owed first.
    private var outstandingByFriend: [(friend: String, loans: [Loan])] {
        Dictionary(grouping: outstanding) { $0.friendName.lowercased() }
            .compactMap { _, loans in
                loans.first.map { (friend: $0.friendName, loans: loans) }
            }
            .sorted { $0.loans.outstandingTotal > $1.loans.outstandingTotal }
    }

    var body: some View {
        Group {
            if loans.isEmpty {
                ContentUnavailableView(
                    "No Loans",
                    systemImage: "person.2.circle",
                    description: Text("Tap + to record money you've lent to a friend.")
                )
            } else {
                List {
                    Section {
                        LabeledContent("Total Owed to You") {
                            Text(outstanding.outstandingTotal, format: .rupees)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }

                    if !outstandingByFriend.isEmpty {
                        Section {
                            ForEach(outstandingByFriend, id: \.friend) { entry in
                                let cardLoans = entry.loans.filter { $0.method == .card && !$0.isRepaid }
                                DisclosureGroup {
                                    if !cardLoans.isEmpty {
                                        Button {
                                            coveringCardFriend = FriendCardLoans(friendName: entry.friend, loans: cardLoans)
                                        } label: {
                                            HStack {
                                                Label("I Paid Card Bill for \(entry.friend)", systemImage: "creditcard.badge.arrow.forward")
                                                    .font(.subheadline.weight(.medium))
                                                Spacer()
                                                Text("Move to Cash (\(cardLoans.outstandingTotal.formatted(.rupees)))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .foregroundStyle(.purple)
                                        }
                                    }

                                    ForEach(entry.loans) { loan in
                                        loanButton(loan)
                                            .swipeActions {
                                                Button("Repaid", systemImage: "checkmark.circle") {
                                                    loan.markFullyRepaid(in: modelContext)
                                                }
                                                .tint(.green)

                                                Button("Part Paid", systemImage: "indianrupeesign.circle") {
                                                    repaymentLoan = loan
                                                }
                                                .tint(.teal)

                                                if loan.method == .card {
                                                    Button("I Paid Card", systemImage: "creditcard.badge.arrow.forward") {
                                                        coveringCardFriend = FriendCardLoans(friendName: entry.friend, loans: [loan])
                                                    }
                                                    .tint(.purple)
                                                }
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button("Remind", systemImage: "message") {
                                                    remind(friend: entry.friend, loans: [loan])
                                                }
                                                .tint(.blue)
                                            }
                                    }
                                } label: {
                                    FriendSummaryRow(
                                        friend: entry.friend,
                                        loans: entry.loans,
                                        hasCardLoans: !cardLoans.isEmpty,
                                        onCoverCard: { coveringCardFriend = FriendCardLoans(friendName: entry.friend, loans: cardLoans) },
                                        onRemind: { remind(friend: entry.friend, loans: entry.loans) },
                                        onAddLoan: { addingLoanFor = friendDetails(for: entry.friend) }
                                    )
                                }
                            }
                        } header: {
                            Text("Outstanding")
                        } footer: {
                            Text("Tap the message button to send a friend a reminder. For card loans, tap the purple card button or swipe left to record that you covered the bill and move it to cash.")
                        }
                    }

                    if !repaid.isEmpty {
                        Section("Repaid") {
                            ForEach(repaid) { loan in
                                loanButton(loan)
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            modelContext.delete(loan)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Loans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Share PDF Summary", systemImage: "doc.richtext") {
                        if let url = LoanStatementPDF.summary(loans: loans, emis: emis, borrowings: borrowings) {
                            SharePresenter.present(urls: [url])
                        }
                    }
                    .disabled(loans.isEmpty && emis.isEmpty && borrowings.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Loan", systemImage: "plus") {
                    isAddingLoan = true
                }
            }
        }
        .sheet(isPresented: $isAddingLoan) {
            LoanFormView()
        }
        .sheet(item: $addingLoanFor) { friend in
            LoanFormView(friend: friend)
        }
        .sheet(item: $editingLoan) { loan in
            LoanFormView(loan: loan)
        }
        .sheet(item: $repaymentLoan) { loan in
            RepaymentFormView(loan: loan)
        }
        .sheet(item: $coveringCardFriend) { item in
            CoverCardLoanSheet(friendName: item.friendName, cardLoans: item.loans)
        }
        .sheet(item: $reminder) { reminder in
            ReminderSheet(reminder: reminder) {
                // Record when the friend was last reminded.
                for loan in reminder.loans {
                    loan.lastRemindedAt = .now
                }
            }
        }
        .confirmationDialog("Send Reminder to \(waitingFriend)", isPresented: $isChoosingChannel, titleVisibility: .visible) {
            Button("Message", systemImage: "message") { start(channel: .messages) }
            Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") { start(channel: .whatsApp) }
            Button("PDF Statement", systemImage: "doc.richtext") {
                // Opens the share sheet, where it can be sent over WhatsApp, Messages or anything else.
                let friendLoans = loans.filter {
                    $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(waitingFriend.trimmingCharacters(in: .whitespaces)) == .orderedSame
                }
                if let url = LoanStatementPDF.statement(for: waitingFriend, loans: friendLoans.isEmpty ? waitingLoans : friendLoans, borrowings: borrowings) {
                    SharePresenter.present(urls: [url])
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "No number saved for \(waitingFriend)",
            isPresented: $isAskingForNumber,
            titleVisibility: .visible
        ) {
            Button("Choose from Contacts") {
                // Let the dialog finish closing before the picker opens.
                after(milliseconds: 400) {
                    ContactPickerPresenter.shared.present { contact in handleContact(contact) }
                }
            }
            Button("Send Without a Number") {
                deliver(LoanReminder(friendName: waitingFriend, loans: waitingLoans))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick \(waitingFriend) from your contacts to save their number and send the reminder.")
        }
        // Asked only when the chosen contact has more than one phone number.
        .confirmationDialog("Choose a Number", isPresented: $isChoosingPhone, titleVisibility: .visible) {
            ForEach(phoneChoices, id: \.identifier) { choice in
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: choice.label ?? "")
                Button("\(label) · \(choice.value.stringValue)") {
                    savePhoneAndRemind(choice.value.stringValue)
                }
            }
        }
    }

    /// A friend's name and their most recently saved number, taken from any of their loans.
    private func friendDetails(for friend: String) -> LoanFriend {
        let theirs = loans.filter { $0.friendName.caseInsensitiveCompare(friend) == .orderedSame }
        let phone = theirs
            .sorted { $0.date > $1.date }
            .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return LoanFriend(name: friend, phone: phone)
    }

    // MARK: Reminders

    /// Starts a reminder for a friend by asking how to send it.
    private func remind(friend: String, loans reminderLoans: [Loan]) {
        waitingFriend = friend
        waitingLoans = reminderLoans
        isChoosingChannel = true
    }

    /// Sends the waiting reminder the chosen way. If no number is saved for the friend yet, offers to pick one from Contacts first.
    private func start(channel: ReminderChannel) {
        waitingChannel = channel
        // Use any number already saved for this friend, even on a different loan.
        let knownPhone = loans
            .filter { $0.friendName.caseInsensitiveCompare(waitingFriend) == .orderedSame }
            .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let candidate = LoanReminder(friendName: waitingFriend, loans: waitingLoans, phone: knownPhone)
        if candidate.phone.isEmpty {
            // Let the first dialog finish closing before the next one opens.
            after(milliseconds: 400) { isAskingForNumber = true }
        } else {
            deliver(candidate)
        }
    }

    /// Opens the reminder in Messages, or in WhatsApp.
    private func deliver(_ candidate: LoanReminder) {
        switch waitingChannel {
        case .messages:
            reminder = candidate
        case .whatsApp:
            guard let url = candidate.whatsAppURL else { return }
            openURL(url)
            // WhatsApp can't say whether it was sent, so the reminder is noted when it is opened.
            for loan in candidate.loans {
                loan.lastRemindedAt = .now
            }
        }
    }

    private func handleContact(_ contact: CNContact) {
        let numbers = contact.phoneNumbers
        if numbers.count == 1 {
            let number = numbers[0].value.stringValue
            after(milliseconds: 500) { savePhoneAndRemind(number) }
        } else if numbers.count > 1 {
            phoneChoices = numbers
            after(milliseconds: 500) { isChoosingPhone = true }
        }
    }

    /// Saves the number on every loan of this friend, so it's remembered next time, then opens the reminder.
    private func savePhoneAndRemind(_ number: String) {
        for loan in loans where loan.friendName.caseInsensitiveCompare(waitingFriend) == .orderedSame {
            loan.friendPhone = number
        }
        deliver(LoanReminder(friendName: waitingFriend, loans: waitingLoans, phone: number))
    }

    private func after(milliseconds: Int, _ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            action()
        }
    }

    private func loanButton(_ loan: Loan) -> some View {
        Button {
            editingLoan = loan
        } label: {
            LoanRow(loan: loan, showsFriend: loan.isRepaid)
        }
        .tint(.primary)
    }
}

/// Helper identifier for opening the card loan cover sheet for a friend.
struct FriendCardLoans: Identifiable {
    let id = UUID()
    let friendName: String
    let loans: [Loan]
}

/// A friend's name with how many loans they have and the total they owe.
/// Pass `onCoverCard` to show a "cover card bill" button, `onRemind` to show a "send reminder" button, and `onAddLoan` to show a "+" for lending to them again.
struct FriendSummaryRow: View {
    let friend: String
    let loans: [Loan]
    var hasCardLoans: Bool = false
    var onCoverCard: (() -> Void)? = nil
    var onRemind: (() -> Void)? = nil
    var onAddLoan: (() -> Void)? = nil

    private var lastReminded: Date? {
        loans.compactMap(\.lastRemindedAt).max()
    }

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend)
                    .font(.body.weight(.medium))
                Text(loans.count == 1 ? "1 loan" : "\(loans.count) loans")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastReminded {
                    Text("Reminded \(lastReminded, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(loans.outstandingTotal, format: .rupees)
                .fontWeight(.semibold)
            if hasCardLoans, let onCoverCard {
                Button("I Paid Card Bill for \(friend)", systemImage: "creditcard.badge.arrow.forward", action: onCoverCard)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("I Paid Card Bill for \(friend)")
            }
            if let onAddLoan {
                Button("Add Another Loan for \(friend)", systemImage: "plus.circle.fill", action: onAddLoan)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .buttonStyle(.borderless)
            }
            if let onRemind {
                Button("Send Reminder to \(friend)", systemImage: "message.circle.fill", action: onRemind)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    // Borderless so tapping it doesn't also expand the row.
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// A single loan: note (or friend), the card used if any, date and amount.
struct LoanRow: View {
    let loan: Loan
    var showsFriend = false

    var body: some View {
        HStack {
            Image(systemName: loan.method.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(showsFriend ? loan.friendName : (loan.note.isEmpty ? defaultTitle : loan.note))
                if let cardDescription = loan.cardDescription {
                    Text(cardDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if loan.isInstalmentLoan, let instalment = loan.monthlyInstalment {
                    Text("EMI \(instalment.formatted(.rupees)) · \(loan.installmentsPaid) of \(loan.installmentCount) paid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if loan.hasActiveMonthlyReminder {
                    Label("Reminds on day \(loan.monthlyReminderDay) each month", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Group {
                    if let repaidDate = loan.repaidDate {
                        Text("Repaid \(repaidDate, format: .dateTime.day().month().year())")
                    } else if loan.isPartlyRepaid {
                        Text("\(loan.repaidAmount.formatted(.rupees)) repaid · \(loan.date.formatted(.dateTime.day().month().year()))")
                    } else {
                        Text(loan.date, format: .dateTime.day().month().year())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // Owed now; the full amount once it's all been paid back.
                Text(loan.isRepaid ? loan.amount : loan.outstandingAmount, format: .rupees)
                    .foregroundStyle(loan.isRepaid ? .secondary : .primary)
                if loan.isPartlyRepaid {
                    Text("of \(loan.amount.formatted(.rupees))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var defaultTitle: String {
        switch loan.method {
        case .cash: "Loan"
        case .card: "Used your card"
        case .personalLoan: "Personal loan in your name"
        }
    }
}

/// Sheet for recording that you covered/paid the credit card bill for a friend's card loan,
/// which marks the card loan repaid and moves the amount to a cash loan owed to you.
struct CoverCardLoanSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let friendName: String
    let cardLoans: [Loan]

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    @State private var amount: Decimal?
    @State private var fromUID: String = ""
    @State private var date = Date.now
    @State private var note: String = "Card paid for loan"

    init(friendName: String, cardLoans: [Loan]) {
        self.friendName = friendName
        self.cardLoans = cardLoans
        _amount = State(initialValue: cardLoans.outstandingTotal > 0 ? cardLoans.outstandingTotal : nil)
    }

    private var eligibleAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    private var fromAccount: Account? {
        eligibleAccounts.first { $0.uid == fromUID }
    }

    private var primaryCardLoan: Loan? {
        cardLoans.first
    }

    private var isValid: Bool {
        guard let amount, amount > 0, amount <= cardLoans.outstandingTotal, fromAccount != nil else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Loan Details") {
                    LabeledContent("Friend", value: friendName)
                    LabeledContent("Owed on Card", value: cardLoans.outstandingTotal.formatted(.rupees))
                    if cardLoans.count > 1 {
                        LabeledContent("Loans Count", value: "\(cardLoans.count) card loans")
                    } else if let loan = primaryCardLoan {
                        if let cardDesc = loan.cardDescription {
                            LabeledContent("Card", value: cardDesc)
                        }
                    }
                }

                Section {
                    TextField("Amount Paid", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))

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

                    DatePicker("Date Paid", selection: $date, displayedComponents: .date)
                    TextField("Note", text: $note)
                } header: {
                    Text("Payment You Made")
                } footer: {
                    if let amount, amount > cardLoans.outstandingTotal {
                        Text("That's more than the \(cardLoans.outstandingTotal.formatted(.rupees)) owed on the card.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Takes \(amount?.formatted(.rupees) ?? "this") off the card loan, lowers \(fromAccount?.displayName ?? "that account") once, and creates a Cash loan to \(friendName), so they now owe you directly. Pay the rest of the card bill from the card's Pay Bill, without their share.")
                    }
                }

            }
            .navigationTitle("I Paid Card Bill")
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
            }
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        var left = amount
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let repaymentNote = trimmedNote.isEmpty ? "Card paid for loan" : trimmedNote

        for loan in cardLoans.sorted(by: { $0.date < $1.date }) where left > 0 {
            let part = min(left, loan.outstandingAmount)
            guard part > 0 else { continue }
            loan.recordRepayment(part, on: date, note: repaymentNote, bankName: "", in: modelContext)
            left -= part
        }

        let covered = amount - left
        guard covered > 0 else { return }

        let phone = cardLoans.first(where: { !$0.friendPhone.isEmpty })?.friendPhone ?? ""
        let fromAcc = fromAccount
        let newCashLoan = Loan(
            amount: covered,
            friendName: friendName,
            friendPhone: phone,
            note: repaymentNote,
            date: date,
            method: .cash,
            bankName: fromAcc?.kind == .bank ? (fromAcc?.bankName ?? "") : ""
        )
        modelContext.insert(newCashLoan)

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LoansView()
    }
}
