//
//  LoanFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import ContactsUI

/// A friend already saved from an earlier loan, to start a new loan with their name and number filled in.
struct LoanFriend: Identifiable {
    let name: String
    let phone: String

    var id: String { name.lowercased() }
}

/// Sheet for recording money lent to a friend — either as cash/transfer or by letting them
/// use your card — or editing an existing loan when `loan` is non-nil.
struct LoanFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Stored cards for quick selection.
    @Query(sort: \PaymentCard.createdAt, order: .reverse) private var storedCards: [PaymentCard]
    /// All loans, used to suggest friends you've lent to before.
    @Query(sort: \Loan.date, order: .reverse) private var allLoans: [Loan]
    /// Accounts, so a cash loan can say which one it was paid from.
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]
    /// All expenses, used to suggest cards you've used before.
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    let loan: Loan?

    @State private var amount: Decimal?
    @State private var friendName: String
    @State private var friendPhone: String
    @State private var note: String
    @State private var date: Date
    @State private var method: LoanMethod
    /// For a cash or transfer loan: the bank the money left from. Empty means cash.
    @State private var paidFrom: String
    @State private var monthlyReminder: Bool
    @State private var reminderDay: Int
    /// For a personal loan: the amount of each instalment. For a card loan: the friend's monthly EMI.
    @State private var monthlyAmount: Decimal?
    /// For a personal loan or a card EMI: how many instalments.
    @State private var installmentCount: Int
    /// For a card loan: the friend is repaying it as an EMI rather than as one amount.
    @State private var cardIsEMI: Bool
    /// How many past monthly payments are already received. `nil` until changed, then it follows the dates.
    @State private var repaidOverride: Int?
    @State private var accountType: AccountType
    @State private var bankName: String
    @State private var cardLastFour: String

    /// Phone numbers of the chosen contact, when there is more than one to pick from.
    @State private var phoneChoices: [CNLabeledValue<CNPhoneNumber>] = []
    @State private var isChoosingPhone = false
    /// A credit card saved for the first time by this loan, waiting for the form to finish before its bill day is asked.
    @State private var cardToAsk: PaymentCard?
    /// The card whose bill day is being asked now.
    @State private var cardAskingBillDay: PaymentCard?
    @State private var isRecordingRepayment = false
    @State private var activeReminder: LoanReminder?

    /// - Parameters:
    ///   - defaultDate: Date used for new loans from a selected day or month.
    ///   - friend: For a new loan, a friend whose name and number are already known, so they needn't be typed again.
    init(loan: Loan? = nil, defaultDate: Date = .now, friend: LoanFriend? = nil) {
        self.loan = loan
        _amount = State(initialValue: loan?.amount)
        _friendName = State(initialValue: loan?.friendName ?? friend?.name ?? "")
        _friendPhone = State(initialValue: loan?.friendPhone ?? friend?.phone ?? "")
        _note = State(initialValue: loan?.note ?? "")
        _date = State(initialValue: loan?.date ?? defaultDate)
        _method = State(initialValue: loan?.method ?? .cash)
        _paidFrom = State(initialValue: loan?.method == .cash ? (loan?.bankName ?? "") : "")
        _monthlyReminder = State(initialValue: loan?.monthlyReminderEnabled ?? false)
        // Default to the day of the month the card was used.
        let usedOn = loan?.date ?? defaultDate
        _reminderDay = State(initialValue: loan?.monthlyReminderDay ?? min(Calendar.current.component(.day, from: usedOn), 28))

        // A personal loan is entered as a number of instalments and the amount of each.
        var instalments = loan?.installmentCount ?? 0
        var perInstalment = loan?.monthlyInstalment
        if let loan, loan.method == .personalLoan, instalments == 0 {
            // A personal loan saved as one amount: show it as a single instalment, or split by its monthly EMI.
            if let emi = perInstalment, emi > 0 {
                instalments = max(1, Int(NSDecimalNumber(decimal: loan.amount / emi).doubleValue.rounded()))
            } else {
                instalments = 1
                perInstalment = loan.amount
            }
        }
        _installmentCount = State(initialValue: instalments > 0 ? instalments : 12)
        _cardIsEMI = State(initialValue: loan?.method == .card && (loan?.installmentCount ?? 0) > 0)
        _monthlyAmount = State(initialValue: perInstalment)
        _accountType = State(initialValue: loan?.accountType ?? .creditCard)
        _bankName = State(initialValue: loan?.bankName ?? "")
        _cardLastFour = State(initialValue: loan?.cardLastFour ?? "")
    }

    private var trimmedFriendName: String {
        friendName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Repaid as a number of equal instalments: always for a personal loan, and for a card loan the friend chose to split.
    private var usesInstalments: Bool {
        method == .personalLoan || (method == .card && cardIsEMI)
    }

    /// The whole amount. An instalment loan works it out from the instalments; any other loan is typed in.
    private var effectiveAmount: Decimal? {
        guard usesInstalments else { return amount }
        guard let monthlyAmount, monthlyAmount > 0, installmentCount > 0 else { return nil }
        return Decimal(installmentCount) * monthlyAmount
    }

    /// Monthly payment dates between the loan date and today, for a new loan with a monthly reminder.
    private var pastPaymentDates: [Date] {
        guard loan == nil, method.isOnMyName, monthlyReminder else { return [] }
        return Loan.monthlyPaymentDates(after: date, day: reminderDay)
    }

    /// Past months that could already be repaid: those on or before today, and only as many as the amount covers.
    private var pastCount: Int {
        guard let monthlyAmount, monthlyAmount > 0, let amount = effectiveAmount, amount > 0 else { return 0 }
        var wholeMonths = amount / monthlyAmount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &wholeMonths, 0, .down)
        let coveredByAmount = NSDecimalNumber(decimal: rounded).intValue
        return min(pastPaymentDates.count, coveredByAmount)
    }

    /// Past months to record as already repaid. Defaults to all of them.
    private var alreadyRepaid: Int {
        min(repaidOverride ?? pastCount, pastCount)
    }

    /// Banks of your open bank accounts, one entry per bank, for "Paid From".
    private var paidFromChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var isValid: Bool {
        guard let amount = effectiveAmount else { return false }
        return amount > 0 && !trimmedFriendName.isEmpty
    }

    /// Distinct friend names from earlier loans that match what's typed so far.
    private var friendSuggestions: [String] {
        var seen = Set<String>()
        return allLoans
            .map(\.friendName)
            .filter { seen.insert($0.lowercased()).inserted }
            .filter { name in
                name.caseInsensitiveCompare(trimmedFriendName) != .orderedSame
                    && (trimmedFriendName.isEmpty || name.localizedCaseInsensitiveContains(trimmedFriendName))
            }
    }

    /// A card you've used before, for one-tap selection.
    private struct SavedCard: Hashable {
        let accountType: AccountType
        let bankName: String
        let cardLastFour: String

        var title: String {
            let bank = bankName.isEmpty ? accountType.rawValue : bankName
            return cardLastFour.isEmpty ? bank : "\(bank) •••• \(cardLastFour)"
        }
    }

    /// Distinct cards from stored cards, past expenses, and earlier card loans, most recently used first.
    private var savedCards: [SavedCard] {
        var seen = Set<SavedCard>()
        let fromStored = storedCards.map {
            SavedCard(accountType: $0.accountType, bankName: $0.bankName, cardLastFour: $0.cardLastFour)
        }
        let fromExpenses = allExpenses
            .filter { $0.accountType.usesCard }
            .map { SavedCard(accountType: $0.accountType, bankName: $0.bankName, cardLastFour: $0.cardLastFour) }
        let fromLoans = allLoans
            .filter { $0.method == .card }
            .map { SavedCard(accountType: $0.accountType, bankName: $0.bankName, cardLastFour: $0.cardLastFour) }

        return (fromStored + fromExpenses + fromLoans).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loan") {
                    // An instalment loan is entered as instalments below, so the total isn't typed here.
                    if !usesInstalments {
                        TextField("Amount", value: $amount, format: .rupees)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                    }

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
                    Picker("How", selection: $method.animation()) {
                        ForEach(LoanMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if method == .card {
                        cardFields
                    } else if method == .personalLoan {
                        TextField("Lender / Bank (e.g. HDFC Bank)", text: $bankName)
                            .textInputAutocapitalization(.words)
                    } else if !paidFromChoices.isEmpty {
                        Picker("Paid From", selection: $paidFrom) {
                            Text("Cash").tag("")
                            ForEach(paidFromChoices, id: \.self) { bank in
                                Text(bank).tag(bank)
                            }
                        }
                    }
                } header: {
                    Text("How")
                } footer: {
                    if let explanation = method.explanation {
                        Text(explanation)
                    }
                }

                if method == .card {
                    Section {
                        Toggle("Friend Pays This as an EMI", isOn: $cardIsEMI.animation())
                    } footer: {
                        Text("Turn this on when your friend converted their purchase into an EMI on your card. You enter the number of instalments and the EMI instead of the whole amount.")
                    }
                }

                if usesInstalments {
                    Section {
                        Stepper("Instalments: \(installmentCount)", value: $installmentCount, in: 1...360)
                        TextField("Amount per instalment", value: $monthlyAmount, format: .rupees)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                        if let total = effectiveAmount {
                            LabeledContent("Total to Repay") {
                                Text(total, format: .rupees)
                                    .fontWeight(.semibold)
                            }
                        }
                    } header: {
                        Text("Instalments")
                    } footer: {
                        Text("Enter how many instalments and how much each one is. The total is worked out for you. Reminders ask your friend for the instalment, not the whole amount.")
                    }
                }

                if method.isOnMyName {
                    Section {
                        Toggle("Remind Me Every Month", isOn: $monthlyReminder.animation())
                        if monthlyReminder {
                            Picker("Remind On Day", selection: $reminderDay) {
                                ForEach(1...28, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                            // An instalment loan already has its instalment amount above.
                            if method == .card, !usesInstalments {
                                TextField("Friend's Monthly EMI (optional)", value: $monthlyAmount, format: .rupees)
                                    .keyboardType(.decimalPad)
                            }
                            if pastCount > 0 {
                                Stepper(
                                    "Already repaid: \(alreadyRepaid) of \(pastCount) months",
                                    value: Binding(get: { alreadyRepaid }, set: { repaidOverride = $0 }),
                                    in: 0...pastCount
                                )
                            }
                        }
                    } header: {
                        Text("Monthly EMI Reminder")
                    } footer: {
                        if loan == nil, monthlyReminder {
                            if pastCount > 0 {
                                Text("Months since the loan are recorded as repaid on the reminder day, using the monthly EMI. Lower the count if your friend has paid fewer.")
                            } else if monthlyAmount == nil, !pastPaymentDates.isEmpty {
                                Text("Enter your friend's monthly EMI to record the months already repaid.")
                            }
                        }
                        Text("Use this when your friend is paying back an EMI on your card or a personal loan in your name. You get a notification on this day every month until the loan is fully repaid. Days after the 28th aren't offered so it works in every month.")
                    }
                }

                Section("When") {
                    DatePicker(
                        method == .card ? "Used On" : (method == .personalLoan ? "Taken On" : "Lent On"),
                        selection: $date,
                        displayedComponents: .date
                    )
                }

                repaymentSection

                Section {
                    Button {
                        saveAndMessage()
                    } label: {
                        Label(loan == nil ? "Save & Send Message" : "Send Reminder / Message", systemImage: "message.fill")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)

                    Button {
                        saveAndWhatsApp()
                    } label: {
                        Label(loan == nil ? "Save & Send on WhatsApp" : "Send Reminder on WhatsApp", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.body.weight(.medium))
                    }
                    .disabled(!isValid)
                } footer: {
                    Text("Pre-fills an SMS / iMessage, or a WhatsApp chat, with the loan amount and details. You tap Send yourself.")
                }

                if let loan {
                    Section {
                        Button("Delete Loan", role: .destructive) {
                            modelContext.delete(loan)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(loan == nil ? "Lend Money" : "Edit Loan")
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
            .sheet(isPresented: $isRecordingRepayment) {
                if let loan {
                    RepaymentFormView(loan: loan)
                }
            }
            // Asked only when the chosen contact has more than one phone number.
            .confirmationDialog("Choose a Number", isPresented: $isChoosingPhone, titleVisibility: .visible) {
                ForEach(phoneChoices, id: \.identifier) { choice in
                    let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: choice.label ?? "")
                    Button("\(label) · \(choice.value.stringValue)") {
                        friendPhone = choice.value.stringValue
                    }
                }
            }
            .sheet(item: $activeReminder) { reminder in
                ReminderSheet(reminder: reminder) {
                    finish()
                }
            }
            // The loan is already saved. Once the bill day is answered or skipped, the form closes.
            .sheet(item: $cardAskingBillDay, onDismiss: { dismiss() }) { card in
                BillingCycleSheet(card: card)
            }
        }
    }

    /// Payments received so far, with buttons to record another. Friends often repay in parts.
    @ViewBuilder
    private var repaymentSection: some View {
        if let loan {
            Section {
                LabeledContent("Repaid") {
                    Text(loan.repaidAmount, format: .rupees)
                        .foregroundStyle(.green)
                }
                LabeledContent("Still Owed") {
                    Text(loan.outstandingAmount, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(loan.outstandingAmount > 0 ? Color.orange : Color.secondary)
                }
                if loan.amount > 0 {
                    ProgressView(
                        value: min(NSDecimalNumber(decimal: loan.repaidAmount).doubleValue, NSDecimalNumber(decimal: loan.amount).doubleValue),
                        total: NSDecimalNumber(decimal: loan.amount).doubleValue
                    )
                    .tint(loan.isRepaid ? .green : .accentColor)
                }

                ForEach(loan.sortedRepayments) { repayment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repayment.date, format: .dateTime.day().month().year())
                            if !repayment.note.isEmpty {
                                Text(repayment.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("+\(repayment.amount.formatted(.rupees))")
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            loan.removeRepayment(repayment, in: modelContext)
                        }
                    }
                }

                if loan.outstandingAmount > 0 {
                    Button("Record Repayment", systemImage: "plus.circle") {
                        isRecordingRepayment = true
                    }
                    Button("Mark Fully Repaid", systemImage: "checkmark.circle") {
                        loan.markFullyRepaid(in: modelContext)
                    }
                }
            } header: {
                Text("Repayments")
            } footer: {
                Text("Your friend can pay back in parts. Each payment reduces what they owe. Swipe a payment left to delete it.")
            }
        } else {
            Section {
                Text("Save the loan first, then record each payment your friend makes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Repayments")
            }
        }
    }

    /// Card picker shown when the friend used your card.
    @ViewBuilder
    private var cardFields: some View {
        if !savedCards.isEmpty {
            Menu {
                ForEach(savedCards, id: \.self) { card in
                    Button(card.title, systemImage: card.accountType.systemImage) {
                        accountType = card.accountType
                        bankName = card.bankName
                        cardLastFour = card.cardLastFour
                    }
                }
            } label: {
                Label("Choose a Saved Card", systemImage: "creditcard.and.123")
            }
        }

        Picker("Card Type", selection: $accountType) {
            ForEach(AccountType.allCases.filter(\.usesCard)) { type in
                Label(type.rawValue, systemImage: type.systemImage)
                    .tag(type)
            }
        }
        TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
            .textInputAutocapitalization(.words)
        TextField("Card No. (last 4 digits)", text: $cardLastFour)
            .keyboardType(.numberPad)
            .onChange(of: cardLastFour) { _, newValue in
                // Keep only digits and at most 4 of them.
                let digits = String(newValue.filter(\.isNumber).prefix(4))
                if digits != newValue { cardLastFour = digits }
            }
    }

    /// Tap-to-fill chips for friends you've lent to before.
    private var friendSuggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(friendSuggestions, id: \.self) { name in
                    Button(name, systemImage: "person.crop.circle") {
                        friendName = name
                        if friendPhone.isEmpty,
                           let existingPhone = allLoans.first(where: {
                               $0.friendName.caseInsensitiveCompare(name) == .orderedSame && !$0.friendPhone.isEmpty
                           })?.friendPhone {
                            friendPhone = existingPhone
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
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
            // Wait for the picker to finish closing before asking which number to use.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                isChoosingPhone = true
            }
        }
    }

    @discardableResult
    private func persistLoan() -> Loan? {
        guard let amount = effectiveAmount, amount > 0, !trimmedFriendName.isEmpty else { return nil }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = friendPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCard = method == .card
        // A card loan keeps the bank and card digits; a personal loan keeps just the lender.
        let trimmedBank = method.isOnMyName
            ? BankName.normalized(bankName)
            : (method == .cash ? BankName.normalized(paidFrom) : "")
        let card = isCard ? cardLastFour : ""

        // Auto-save card to stored PaymentCard
        if isCard && (!trimmedBank.isEmpty || !card.isEmpty) {
            let alreadySaved = storedCards.contains {
                $0.accountType == accountType &&
                BankName.matches($0.bankName, trimmedBank) &&
                $0.cardLastFour == card
            }
            if !alreadySaved {
                let saved = PaymentCard(
                    bankName: trimmedBank,
                    cardLastFour: card,
                    accountType: accountType
                )
                modelContext.insert(saved)
                if accountType == .creditCard { cardToAsk = saved }
            }
        }
        // A friend's purchase on a saved credit card must have an Account to update its card balance.
        if accountType == .creditCard {
            CardSync.sync(in: modelContext)
        }

        if let loan {
            loan.amount = amount
            loan.friendName = trimmedFriendName
            loan.friendPhone = trimmedPhone
            loan.note = trimmedNote
            loan.date = date
            loan.method = method
            loan.accountType = accountType
            loan.bankName = trimmedBank
            loan.cardLastFour = card
            applyMonthlyReminder(to: loan)
            // A lower amount may mean the payments received already cover it.
            loan.syncRepaidState()
            return loan
        } else {
            let newLoan = Loan(
                amount: amount,
                friendName: trimmedFriendName,
                friendPhone: trimmedPhone,
                note: trimmedNote,
                date: date,
                method: method,
                accountType: accountType,
                bankName: trimmedBank,
                cardLastFour: card
            )
            applyMonthlyReminder(to: newLoan)
            modelContext.insert(newLoan)
            // A loan that is already part-way through: record the months your friend has repaid.
            if alreadyRepaid > 0, let monthlyAmount {
                for paidOn in pastPaymentDates.prefix(alreadyRepaid) {
                    newLoan.recordRepayment(monthlyAmount, on: paidOn, note: "Monthly EMI", in: modelContext)
                }
            }
            return newLoan
        }
    }

    /// Stores the monthly reminder choice. It only applies to loans on your card.
    private func applyMonthlyReminder(to loan: Loan) {
        let isOn = method.isOnMyName && monthlyReminder
        loan.monthlyReminderEnabled = isOn
        loan.monthlyReminderDay = reminderDay
        if usesInstalments {
            // The instalment is part of the loan itself, whether or not a reminder is on.
            loan.installmentCount = installmentCount
            loan.monthlyInstalment = monthlyAmount
        } else {
            loan.installmentCount = 0
            loan.monthlyInstalment = isOn ? monthlyAmount : nil
        }
    }

    /// Closes the form, first asking for the bill day if this loan saved a new credit card.
    private func finish() {
        guard let card = cardToAsk else {
            dismiss()
            return
        }
        cardToAsk = nil
        let isMessageOpen = activeReminder != nil
        Task {
            // Let the message sheet finish closing before another one opens.
            if isMessageOpen { try? await Task.sleep(for: .milliseconds(500)) }
            cardAskingBillDay = card
        }
    }

    private func save() {
        if persistLoan() != nil {
            finish()
        }
    }

    private func saveAndWhatsApp() {
        guard let saved = persistLoan() else { return }
        let reminder = LoanReminder(friendName: saved.friendName, loans: [saved], phone: saved.friendPhone)
        guard let url = reminder.whatsAppURL else { return }
        openURL(url)
        // WhatsApp can't say whether it was sent, so the reminder is noted when it is opened.
        saved.lastRemindedAt = .now
        finish()
    }

    private func saveAndMessage() {
        guard let saved = persistLoan() else { return }
        activeReminder = LoanReminder(
            friendName: saved.friendName,
            loans: [saved],
            phone: saved.friendPhone
        )
    }
}

#Preview {
    LoanFormView()
        .modelContainer(for: [Loan.self, Expense.self, PaymentCard.self], inMemory: true)
}
