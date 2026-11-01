//
//  BorrowedView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import ContactsUI

/// All money borrowed from friends: what is still owed grouped by friend, plus paid-back history.
/// It follows the layout of the Loans screen: a row per friend that expands to their debts.
struct BorrowedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Borrowing.date, order: .reverse) private var borrowings: [Borrowing]
    /// Money lent to friends and your EMIs, for the PDF summary and a friend's statement.
    @Query(sort: \Loan.date, order: .reverse) private var loans: [Loan]
    @Query private var emis: [EMI]

    @State private var isAdding = false
    /// A friend a new borrowing is being added for, with their name and number filled in.
    @State private var addingFor: LoanFriend?
    /// The debt whose payments and details are open.
    @State private var detailBorrowing: Borrowing?
    /// The debt a part payment is being recorded for.
    @State private var payingBorrowing: Borrowing?
    /// The message currently being composed.
    @State private var activeMessage: BorrowingMessage?

    // Used when a friend has no phone number saved yet: choose one from Contacts first.
    @State private var waitingFriend = ""
    @State private var waitingBorrowings: [Borrowing] = []
    @State private var isChoosingChannel = false
    @State private var isAskingForNumber = false
    @State private var waitingChannel = ReminderChannel.messages
    @State private var phoneChoices: [CNLabeledValue<CNPhoneNumber>] = []
    @State private var isChoosingPhone = false

    private var outstanding: [Borrowing] { borrowings.filter { !$0.isRepaid } }
    private var repaid: [Borrowing] { borrowings.filter(\.isRepaid) }

    /// Outstanding debts grouped by friend (case-insensitive), largest amount owed first.
    private var outstandingByFriend: [(friend: String, borrowings: [Borrowing])] {
        Dictionary(grouping: outstanding) { $0.friendName.lowercased() }
            .compactMap { _, items in
                items.first.map { (friend: $0.friendName, borrowings: items) }
            }
            .sorted { $0.borrowings.outstandingTotal > $1.borrowings.outstandingTotal }
    }

    var body: some View {
        Group {
            if borrowings.isEmpty {
                ContentUnavailableView(
                    "Nothing Borrowed",
                    systemImage: "person.2.slash",
                    description: Text("Tap + to record money you took from a friend, and pay it back in parts.")
                )
            } else {
                List {
                    Section {
                        LabeledContent("Total You Owe") {
                            Text(outstanding.outstandingTotal, format: .rupees)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(outstanding.isEmpty ? Color.primary : Color.red)
                        }
                    }

                    if !outstandingByFriend.isEmpty {
                        Section {
                            ForEach(outstandingByFriend, id: \.friend) { entry in
                                DisclosureGroup {
                                    ForEach(entry.borrowings) { borrowing in
                                        borrowingButton(borrowing)
                                            .swipeActions {
                                                Button("Repaid", systemImage: "checkmark.circle") {
                                                    borrowing.recordPayment(
                                                        borrowing.outstandingAmount, bankName: borrowing.bankName, in: modelContext
                                                    )
                                                    reschedule()
                                                }
                                                .tint(.green)

                                                Button("Part Paid", systemImage: "indianrupeesign.circle") {
                                                    payingBorrowing = borrowing
                                                }
                                                .tint(.teal)
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button("Message", systemImage: "message") {
                                                    send(friend: entry.friend, borrowings: [borrowing])
                                                }
                                                .tint(.blue)
                                            }
                                    }
                                } label: {
                                    BorrowFriendRow(
                                        friend: entry.friend,
                                        borrowings: entry.borrowings,
                                        onSend: { send(friend: entry.friend, borrowings: entry.borrowings) },
                                        onAddBorrowing: { addingFor = friendDetails(for: entry.friend) }
                                    )
                                }
                            }
                        } header: {
                            Text("Outstanding")
                        } footer: {
                            Text("Tap the message button to send a friend what you owe and every payment so far, or a PDF statement. Swipe a debt to record a payment.")
                        }
                    }

                    if !repaid.isEmpty {
                        Section("Paid Back") {
                            ForEach(repaid) { borrowing in
                                borrowingButton(borrowing, showsFriend: true)
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            modelContext.delete(borrowing)
                                            reschedule()
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Borrowed")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Share PDF Summary", systemImage: "doc.richtext") {
                        if let url = LoanStatementPDF.summary(loans: loans, emis: emis, borrowings: borrowings) {
                            SharePresenter.present(urls: [url])
                        }
                    }
                    .disabled(borrowings.isEmpty)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            BorrowingFormView()
        }
        .sheet(item: $addingFor) { friend in
            BorrowingFormView(friend: friend)
        }
        .sheet(item: $detailBorrowing) { borrowing in
            NavigationStack {
                BorrowingDetailView(borrowing: borrowing)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { detailBorrowing = nil }
                        }
                    }
            }
        }
        .sheet(item: $payingBorrowing, onDismiss: reschedule) { borrowing in
            BorrowingPaymentSheet(borrowing: borrowing)
        }
        .sheet(item: $activeMessage) { message in
            BorrowingMessageSheet(message: message)
        }
        .confirmationDialog("Send to \(waitingFriend)", isPresented: $isChoosingChannel, titleVisibility: .visible) {
            Button("Message", systemImage: "message") { start(channel: .messages) }
            Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") { start(channel: .whatsApp) }
            Button("PDF Statement", systemImage: "doc.richtext") {
                // Opens the share sheet, where it can be sent over WhatsApp, Messages or anything else.
                if let url = LoanStatementPDF.statement(for: waitingFriend, loans: loans, borrowings: borrowings) {
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
                deliver(BorrowingMessage(friendName: waitingFriend, borrowings: waitingBorrowings))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick \(waitingFriend) from your contacts to save their number and send the message.")
        }
        // Asked only when the chosen contact has more than one phone number.
        .confirmationDialog("Choose a Number", isPresented: $isChoosingPhone, titleVisibility: .visible) {
            ForEach(phoneChoices, id: \.identifier) { choice in
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: choice.label ?? "")
                Button("\(label) · \(choice.value.stringValue)") {
                    savePhoneAndSend(choice.value.stringValue)
                }
            }
        }
    }

    private func borrowingButton(_ borrowing: Borrowing, showsFriend: Bool = false) -> some View {
        Button {
            detailBorrowing = borrowing
        } label: {
            BorrowingRow(borrowing: borrowing, showsFriend: showsFriend)
        }
        .tint(.primary)
    }

    /// A friend's name and their most recently saved number, from any of their debts or loans.
    private func friendDetails(for friend: String) -> LoanFriend {
        let fromBorrowings = borrowings
            .filter { $0.friendName.caseInsensitiveCompare(friend) == .orderedSame }
            .sorted { $0.date > $1.date }
            .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
        let fromLoans = loans
            .filter { $0.friendName.caseInsensitiveCompare(friend) == .orderedSame }
            .sorted { $0.date > $1.date }
            .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
        return LoanFriend(name: friend, phone: (fromBorrowings + fromLoans).first { !$0.isEmpty } ?? "")
    }

    // MARK: Messages

    /// Starts a message for a friend by asking how to send it.
    private func send(friend: String, borrowings sending: [Borrowing]) {
        waitingFriend = friend
        waitingBorrowings = sending
        isChoosingChannel = true
    }

    /// Sends the waiting message the chosen way. If no number is saved yet, offers to pick one from Contacts first.
    private func start(channel: ReminderChannel) {
        waitingChannel = channel
        let phone = friendDetails(for: waitingFriend).phone
        let candidate = BorrowingMessage(friendName: waitingFriend, phone: phone, borrowings: waitingBorrowings)
        if phone.isEmpty {
            // Let the first dialog finish closing before the next one opens.
            after(milliseconds: 400) { isAskingForNumber = true }
        } else {
            deliver(candidate)
        }
    }

    private func deliver(_ candidate: BorrowingMessage) {
        switch waitingChannel {
        case .messages:
            activeMessage = candidate
        case .whatsApp:
            if let url = candidate.whatsAppURL { openURL(url) }
        }
    }

    private func handleContact(_ contact: CNContact) {
        let numbers = contact.phoneNumbers
        if numbers.count == 1 {
            let number = numbers[0].value.stringValue
            after(milliseconds: 500) { savePhoneAndSend(number) }
        } else if numbers.count > 1 {
            phoneChoices = numbers
            after(milliseconds: 500) { isChoosingPhone = true }
        }
    }

    /// Saves the number on every debt of this friend, so it is remembered next time, then opens the message.
    private func savePhoneAndSend(_ number: String) {
        for borrowing in borrowings where borrowing.friendName.caseInsensitiveCompare(waitingFriend) == .orderedSame {
            borrowing.friendPhone = number
        }
        deliver(BorrowingMessage(friendName: waitingFriend, phone: number, borrowings: waitingBorrowings))
    }

    private func after(milliseconds: Int, _ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            action()
        }
    }

    private func reschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await BorrowingReminder.reschedule(in: context)
        }
    }
}

/// A friend's name with how many debts you have to them and the total you owe, as on the Loans screen.
private struct BorrowFriendRow: View {
    let friend: String
    let borrowings: [Borrowing]
    var onSend: () -> Void
    var onAddBorrowing: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend)
                    .font(.body.weight(.medium))
                Text(borrowings.count == 1 ? "1 debt" : "\(borrowings.count) debts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(borrowings.outstandingTotal, format: .rupees)
                .fontWeight(.semibold)
            Button("Borrow Again from \(friend)", systemImage: "plus.circle.fill", action: onAddBorrowing)
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.green)
                .buttonStyle(.borderless)
            Button("Send Message to \(friend)", systemImage: "message.circle.fill", action: onSend)
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.blue)
                // Borderless so tapping it doesn't also expand the row.
                .buttonStyle(.borderless)
        }
    }
}

/// A single debt: note (or friend), where the money landed, date and what is left, as a loan row looks.
private struct BorrowingRow: View {
    let borrowing: Borrowing
    var showsFriend = false

    var body: some View {
        HStack {
            Image(systemName: borrowing.bankName.isEmpty ? "banknote" : "building.columns")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(showsFriend ? borrowing.friendName : (borrowing.note.isEmpty ? "Borrowed" : borrowing.note))
                Text(borrowing.bankName.isEmpty ? "Cash" : "Into \(BankName.display(borrowing.bankName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    if let repaidDate = borrowing.repaidDate {
                        Text("Paid back \(repaidDate, format: .dateTime.day().month().year())")
                    } else if borrowing.paidAmount > 0 {
                        Text("\(borrowing.paidAmount.formatted(.rupees)) paid back · \(borrowing.date.formatted(.dateTime.day().month().year()))")
                    } else {
                        Text(borrowing.date, format: .dateTime.day().month().year())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let due = borrowing.dueDate, !borrowing.isRepaid {
                    Text("Due \(due, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(borrowing.isOverdue ? Color.red : Color.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // Owed now; the full amount once it has all been paid back.
                Text(borrowing.isRepaid ? borrowing.amount : borrowing.outstandingAmount, format: .rupees)
                    .foregroundStyle(borrowing.isRepaid ? Color.secondary : Color.primary)
                if borrowing.paidAmount > 0, !borrowing.isRepaid {
                    Text("of \(borrowing.amount.formatted(.rupees))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Add or edit

/// Sheet for recording money borrowed from a friend, or editing it when `borrowing` is non-nil.
struct BorrowingFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]
    @Query(sort: \Borrowing.date, order: .reverse) private var allBorrowings: [Borrowing]
    @Query(sort: \Loan.date, order: .reverse) private var allLoans: [Loan]

    let borrowing: Borrowing?

    @State private var amount: Decimal?
    @State private var friendName: String
    @State private var friendPhone: String
    @State private var note: String
    @State private var date: Date
    /// The bank account the money landed in. Empty means cash.
    @State private var receivedIn: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date

    @State private var phoneChoices: [CNLabeledValue<CNPhoneNumber>] = []
    @State private var isChoosingPhone = false
    @State private var activeMessage: BorrowingMessage?

    init(borrowing: Borrowing? = nil, friend: LoanFriend? = nil) {
        self.borrowing = borrowing
        _amount = State(initialValue: borrowing?.amount)
        _friendName = State(initialValue: borrowing?.friendName ?? friend?.name ?? "")
        _friendPhone = State(initialValue: borrowing?.friendPhone ?? friend?.phone ?? "")
        _note = State(initialValue: borrowing?.note ?? "")
        _date = State(initialValue: borrowing?.date ?? .now)
        _receivedIn = State(initialValue: borrowing?.bankName ?? "")
        _hasDueDate = State(initialValue: borrowing?.dueDate != nil)
        _dueDate = State(initialValue: borrowing?.dueDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
    }

    /// Banks of your open bank accounts, one entry per bank.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var trimmedName: String { friendName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Existing friends known from past borrowings or loans, to quick-fill name and number.
    private var friendSuggestions: [String] {
        var seen = Set<String>()
        let namesFromBorrowings = allBorrowings.map(\.friendName)
        let namesFromLoans = allLoans.map(\.friendName)
        return (namesFromBorrowings + namesFromLoans)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .filter { name in
                name.caseInsensitiveCompare(trimmedName) != .orderedSame
                    && (trimmedName.isEmpty || name.localizedCaseInsensitiveContains(trimmedName))
            }
    }

    private var friendSuggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(friendSuggestions, id: \.self) { name in
                    Button(name, systemImage: "person.crop.circle") {
                        friendName = name
                        if friendPhone.isEmpty {
                            if let phone = (allBorrowings.first(where: { $0.friendName.caseInsensitiveCompare(name) == .orderedSame && !$0.friendPhone.isEmpty })?.friendPhone
                                            ?? allLoans.first(where: { $0.friendName.caseInsensitiveCompare(name) == .orderedSame && !$0.friendPhone.isEmpty })?.friendPhone) {
                                friendPhone = phone
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        }
    }

    private var isValid: Bool {
        guard let amount, amount > 0 else { return false }
        // An amount can't be lowered below what has already been paid back.
        if let borrowing, amount < borrowing.paidAmount { return false }
        return !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Borrowed") {
                    TextField("Amount", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))

                    HStack {
                        TextField("Friend's Name", text: $friendName)
                            .textInputAutocapitalization(.words)

                        Button {
                            ContactPickerPresenter.shared.present { contact in
                                handleContactSelection(contact)
                            }
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Select from Contacts")
                    }

                    TextField("Phone Number (optional)", text: $friendPhone)
                        .keyboardType(.phonePad)

                    if !friendSuggestions.isEmpty {
                        friendSuggestionChips
                    }

                    TextField("Note (optional)", text: $note)
                }

                Section {
                    Picker("Money Came Into", selection: $receivedIn) {
                        Text("Cash").tag("")
                        ForEach(bankChoices, id: \.self) { bank in
                            Text(BankName.display(bank)).tag(bank)
                        }
                    }
                    DatePicker("Received On", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Where It Went")
                } footer: {
                    Text("This account goes up now. It isn't income, because you have to pay it back.")
                }

                Section {
                    Toggle("Promised Pay-Back Date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Pay Back By", selection: $dueDate, in: date..., displayedComponents: .date)
                    }
                } footer: {
                    if hasDueDate {
                        Text("You get a reminder the day before and on the day.")
                    }
                }

                Section {
                    Button {
                        saveAndMessage()
                    } label: {
                        Label(borrowing == nil ? "Save & Send Message" : "Send Confirmation Message", systemImage: "message.fill")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)

                    Button {
                        saveAndWhatsApp()
                    } label: {
                        Label(borrowing == nil ? "Save & Send on WhatsApp" : "Send on WhatsApp", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)
                } footer: {
                    Text("Pre-fills an SMS / iMessage or WhatsApp with the amount, received date, payment form, and promised return date.")
                }

                if let borrowing {
                    Section {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(borrowing)
                            reschedule()
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting also removes the payments you recorded for it.")
                    }
                }
            }
            .navigationTitle(borrowing == nil ? "Borrowed Money" : "Edit")
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
            .confirmationDialog("Choose a Number", isPresented: $isChoosingPhone, titleVisibility: .visible) {
                ForEach(phoneChoices, id: \.identifier) { choice in
                    let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: choice.label ?? "")
                    Button("\(label) · \(choice.value.stringValue)") {
                        friendPhone = choice.value.stringValue
                    }
                }
            }
            .sheet(item: $activeMessage) { message in
                BorrowingMessageSheet(message: message) {
                    dismiss()
                }
            }
        }
    }

    private func handleContactSelection(_ contact: CNContact) {
        let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let fallback = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let resolvedName = fullName.isEmpty ? fallback : fullName
        if !resolvedName.isEmpty {
            friendName = resolvedName
        }

        let numbers = contact.phoneNumbers
        if numbers.count == 1 {
            friendPhone = numbers[0].value.stringValue
        } else if numbers.count > 1 {
            phoneChoices = numbers
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                isChoosingPhone = true
            }
        }
    }

    @discardableResult
    private func persistBorrowing() -> Borrowing? {
        guard let amount, isValid else { return nil }
        let trimmedPhone = friendPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let due: Date? = hasDueDate ? dueDate : nil

        let target: Borrowing
        if let borrowing {
            borrowing.amount = amount
            borrowing.friendName = trimmedName
            borrowing.friendPhone = trimmedPhone
            borrowing.note = trimmedNote
            borrowing.date = date
            borrowing.bankName = receivedIn
            borrowing.dueDate = due
            borrowing.syncRepaidState()
            target = borrowing
        } else {
            let created = Borrowing(
                amount: amount, friendName: trimmedName, friendPhone: trimmedPhone,
                note: trimmedNote, date: date, bankName: receivedIn, dueDate: due
            )
            modelContext.insert(created)
            target = created
        }
        reschedule()
        return target
    }

    private func save() {
        if persistBorrowing() != nil {
            dismiss()
        }
    }

    private func saveAndWhatsApp() {
        guard let saved = persistBorrowing() else { return }
        let msg = BorrowingMessage(borrowing: saved)
        guard let url = msg.whatsAppURL else {
            dismiss()
            return
        }
        openURL(url)
        dismiss()
    }

    private func saveAndMessage() {
        guard let saved = persistBorrowing() else { return }
        activeMessage = BorrowingMessage(borrowing: saved)
    }

    private func reschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await BorrowingReminder.reschedule(in: context)
        }
    }
}

// MARK: - Detail

/// One debt to a friend: what is left, the payments made, and a way to record another.
struct BorrowingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let borrowing: Borrowing

    @Query private var allLoans: [Loan]
    @Query private var allBorrowings: [Borrowing]

    @State private var isPaying = false
    @State private var isEditing = false
    @State private var activeMessage: BorrowingMessage?
    /// The payment just recorded with Mark Fully Repaid, so the friend can be told.
    @State private var settledPayment: BorrowingPayment?

    var body: some View {
        List {
            Section {
                LabeledContent("Still Owe") {
                    Text(borrowing.outstandingAmount, format: .rupees)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(borrowing.isRepaid ? Color.green : Color.red)
                }
                LabeledContent("Borrowed") { Text(borrowing.amount, format: .rupees) }
                LabeledContent("Paid Back") { Text(borrowing.paidAmount, format: .rupees) }
                LabeledContent("Received On") {
                    Text(borrowing.date, format: .dateTime.day().month().year())
                }
                LabeledContent("Came Into", value: borrowing.bankName.isEmpty ? "Cash" : BankName.display(borrowing.bankName))
                if let due = borrowing.dueDate {
                    LabeledContent("Pay Back By") {
                        Text(due, format: .dateTime.day().month().year())
                            .foregroundStyle(borrowing.isOverdue ? Color.red : Color.primary)
                    }
                }
                if !borrowing.note.isEmpty {
                    LabeledContent("Note", value: borrowing.note)
                }
            }

            if !borrowing.isRepaid {
                Section {
                    Button("Record a Payment", systemImage: "arrow.up.right.circle") { isPaying = true }
                    Button("Mark Fully Repaid", systemImage: "checkmark.circle") {
                        settledPayment = borrowing.recordPayment(
                            borrowing.outstandingAmount, bankName: borrowing.bankName, in: modelContext
                        )
                        reschedule()
                    }
                } footer: {
                    Text("A payment comes out of the account you pay from. Mark Fully Repaid pays what is left from the account the money came into.")
                }
            }

            Section("Payments") {
                if borrowing.payments.isEmpty {
                    Text("No payments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(borrowing.sortedPayments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.date, format: .dateTime.day().month().year())
                            Text(payment.bankName.isEmpty ? "Cash" : BankName.display(payment.bankName))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !payment.note.isEmpty {
                                Text(payment.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(payment.amount, format: .rupees)
                            .fontWeight(.semibold)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            borrowing.removePayment(payment, in: modelContext)
                            reschedule()
                        }
                    }
                }
            }
        }
        .navigationTitle(borrowing.friendName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Menu("Send Confirmation", systemImage: "paperplane") {
                        Button("Message", systemImage: "message") {
                            activeMessage = BorrowingMessage(borrowing: borrowing)
                        }
                        Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") {
                            let msg = BorrowingMessage(borrowing: borrowing)
                            if let url = msg.whatsAppURL {
                                openURL(url)
                            }
                        }
                    }
                    if let latest = borrowing.sortedPayments.first {
                        // The latest payment, with every payment so far.
                        Menu("Send Payment Update", systemImage: "arrow.up.message") {
                            Button("Message", systemImage: "message") {
                                activeMessage = BorrowingMessage(borrowing: borrowing, paying: latest)
                            }
                            Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") {
                                if let url = BorrowingMessage(borrowing: borrowing, paying: latest).whatsAppURL {
                                    openURL(url)
                                }
                            }
                        }
                    }
                    Button("PDF Statement", systemImage: "doc.richtext") {
                        sharePDF()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPaying, onDismiss: reschedule) {
            BorrowingPaymentSheet(borrowing: borrowing)
        }
        .sheet(isPresented: $isEditing) {
            BorrowingFormView(borrowing: borrowing)
        }
        .sheet(item: $activeMessage) { message in
            BorrowingMessageSheet(message: message)
        }
        .confirmationDialog(
            "Tell \(borrowing.friendName)?",
            isPresented: Binding(get: { settledPayment != nil }, set: { if !$0 { settledPayment = nil } }),
            titleVisibility: .visible
        ) {
            Button("Message", systemImage: "message") {
                if let payment = settledPayment { activeMessage = BorrowingMessage(borrowing: borrowing, paying: payment) }
            }
            Button("WhatsApp", systemImage: "bubble.left.and.text.bubble.right") {
                if let payment = settledPayment,
                   let url = BorrowingMessage(borrowing: borrowing, paying: payment).whatsAppURL {
                    openURL(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Send a note that the full amount is paid back, with every payment listed.")
        }
    }

    /// A statement for this friend with every borrowing and each part payment, shared from the share sheet.
    private func sharePDF() {
        if let url = LoanStatementPDF.statement(for: borrowing.friendName, loans: allLoans, borrowings: allBorrowings) {
            SharePresenter.present(urls: [url])
        }
    }

    private func reschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await BorrowingReminder.reschedule(in: context)
        }
    }
}

/// Sheet for recording a payment to a friend. It can be less than what is left.
private struct BorrowingPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    let borrowing: Borrowing

    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""
    /// The bank account it is paid from. Empty means cash.
    @State private var paidFrom: String
    @State private var activeMessage: BorrowingMessage?

    init(borrowing: Borrowing) {
        self.borrowing = borrowing
        _amount = State(initialValue: borrowing.outstandingAmount)
        // By default it goes back out of the account it came into.
        _paidFrom = State(initialValue: borrowing.bankName)
    }

    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0 && amount <= borrowing.outstandingAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Still Owe") { Text(borrowing.outstandingAmount, format: .rupees) }
                    TextField("Amount Paid", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Picker("Paid From", selection: $paidFrom) {
                        Text("Cash").tag("")
                        ForEach(bankChoices, id: \.self) { bank in
                            Text(BankName.display(bank)).tag(bank)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if let amount, amount > borrowing.outstandingAmount {
                        Text("That is more than you owe.")
                            .foregroundStyle(.red)
                    } else {
                        Text("After this you will owe \(max(0, borrowing.outstandingAmount - (amount ?? 0)).formatted(.rupees)).")
                    }
                }

                Section {
                    Button {
                        if let payment = record() {
                            activeMessage = BorrowingMessage(borrowing: borrowing, paying: payment)
                        }
                    } label: {
                        Label("Save & Send Message", systemImage: "message.fill")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)

                    Button {
                        if let payment = record() {
                            if let url = BorrowingMessage(borrowing: borrowing, paying: payment).whatsAppURL {
                                openURL(url)
                            }
                            dismiss()
                        }
                    } label: {
                        Label("Save & Send on WhatsApp", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)
                } footer: {
                    Text("Tells \(borrowing.friendName) what you just paid, every payment so far, and what is left. You tap Send yourself.")
                }
            }
            .sheet(item: $activeMessage) { message in
                BorrowingMessageSheet(message: message) {
                    dismiss()
                }
            }
            .navigationTitle("Pay \(borrowing.friendName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if record() != nil { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    /// Records the payment and returns it.
    private func record() -> BorrowingPayment? {
        guard let amount, isValid else { return nil }
        return borrowing.recordPayment(
            amount, on: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            bankName: paidFrom, in: modelContext
        )
    }
}
