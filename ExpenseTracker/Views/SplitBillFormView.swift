//
//  SplitBillFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import ContactsUI

/// Sheet for recording a bill shared with friends.
///
/// - When you paid: Your share becomes an expense, and each friend's share becomes a loan to them.
///   Payments can be made via Credit Card, Debit Card, UPI, or Cash.
/// - When a friend paid: Your share becomes an expense, and you can track it as money you owe them
///   (recorded under Borrowed), or mark that you already settled your share.
/// - Splitting can be equal across all people or with custom amounts per person.
struct SplitBillFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PaymentCard.createdAt, order: .reverse) private var storedCards: [PaymentCard]
    @Query(sort: \Loan.date, order: .reverse) private var allLoans: [Loan]
    @Query(sort: \Borrowing.date, order: .reverse) private var allBorrowings: [Borrowing]
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    /// Who paid the bill up front.
    private enum Payer: String, CaseIterable, Identifiable {
        case me = "You"
        case friend = "A Friend"

        var id: String { rawValue }
    }

    /// How your share is handled when a friend paid the bill.
    private enum FriendSettlement: String, CaseIterable, Identifiable {
        case owe = "I Owe Them"
        case settled = "I Settled Now"

        var id: String { rawValue }
    }

    /// Split distribution mode.
    private enum Mode: String, CaseIterable, Identifiable {
        case equal = "Equal"
        case custom = "Custom"

        var id: String { rawValue }
    }

    /// One friend sharing the bill.
    private struct Friend: Identifiable {
        let id = UUID()
        var name = ""
        var phone = ""
        /// Custom share in custom mode. Equal mode works it out.
        var custom: Decimal?
    }

    @State private var total: Decimal?
    @State private var title = ""
    @State private var category: ExpenseCategory = .food
    @State private var date: Date

    // Payer selection
    @State private var payer: Payer = .me
    @State private var payerFriendName = ""
    @State private var payerFriendPhone = ""
    @State private var friendSettlement: FriendSettlement = .owe

    // Payment method
    @State private var accountType: AccountType = .upi
    @State private var bankName = ""
    @State private var cardLastFour = ""

    // Participants and Split Mode
    @State private var includesMe = true
    @State private var mode: Mode = .equal
    @State private var friends: [Friend] = [Friend()]
    @State private var myCustom: Decimal?

    // Contact picker state
    @State private var phoneChoices: [CNLabeledValue<CNPhoneNumber>] = []
    @State private var isChoosingPhone = false
    @State private var contactTargetFriendIndex: Int?

    // Credit card billing cycle prompt
    @State private var cardAskingBillDay: PaymentCard?

    init(defaultDate: Date = .now) {
        _date = State(initialValue: defaultDate)
    }

    // MARK: - Shares & Calculations

    private var totalPaise: Int64 {
        total.map { Money.paise(from: $0) } ?? 0
    }

    private var participantsCount: Int {
        friends.count + (includesMe ? 1 : 0)
    }

    /// Each friend's share in paise, in order.
    private var friendPaise: [Int64] {
        guard totalPaise > 0, !friends.isEmpty else { return friends.map { _ in 0 } }
        switch mode {
        case .custom:
            return friends.map { $0.custom.map { Money.paise(from: $0) } ?? 0 }
        case .equal:
            let count = Int64(participantsCount)
            guard count > 0 else { return friends.map { _ in 0 } }
            let base = totalPaise / count
            let remainder = totalPaise % count
            return friends.indices.map { index in
                base + (Int64(index) < remainder ? 1 : 0)
            }
        }
    }

    private var friendsAllocatedPaise: Int64 {
        friendPaise.reduce(0, +)
    }

    private var autoMyPaise: Int64 {
        max(0, totalPaise - friendsAllocatedPaise)
    }

    /// Your share in paise.
    private var myPaise: Int64 {
        guard includesMe else { return 0 }
        switch mode {
        case .equal:
            return max(0, totalPaise - friendsAllocatedPaise)
        case .custom:
            if let myCustom {
                return Money.paise(from: myCustom)
            } else {
                return autoMyPaise
            }
        }
    }

    private var totalAllocatedPaise: Int64 {
        friendsAllocatedPaise + (includesMe ? myPaise : 0)
    }

    private var unallocatedPaise: Int64 {
        totalPaise - totalAllocatedPaise
    }

    private var usesBankOnly: Bool {
        accountType == .upi || accountType == .debitCard
    }

    private var isValid: Bool {
        guard totalPaise > 0 else { return false }
        guard !friends.isEmpty else { return false }
        guard friends.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }

        if payer == .friend {
            guard !payerFriendName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            if friendSettlement == .settled && usesBankOnly {
                guard !bankName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            }
        } else {
            if usesBankOnly {
                guard !bankName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            }
        }

        switch mode {
        case .equal:
            guard friendPaise.allSatisfy({ $0 > 0 }) else { return false }
            if includesMe {
                guard myPaise > 0 else { return false }
            }
        case .custom:
            guard friendPaise.allSatisfy({ $0 > 0 }) else { return false }
            if includesMe {
                if myCustom != nil {
                    guard unallocatedPaise == 0, myPaise > 0 else { return false }
                } else {
                    guard totalPaise >= friendsAllocatedPaise else { return false }
                }
            } else {
                guard unallocatedPaise == 0 else { return false }
            }
        }
        return true
    }

    /// Unique past friend names from earlier loans and borrowings for one-tap suggestions.
    private var suggestions: [String] {
        var seen = Set(friends.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        if payer == .friend {
            seen.insert(payerFriendName.trimmingCharacters(in: .whitespaces).lowercased())
        }
        seen.insert("")

        var result: [String] = []
        for loan in allLoans.sorted(by: { $0.date > $1.date }) {
            let name = loan.friendName.trimmingCharacters(in: .whitespaces)
            if seen.insert(name.lowercased()).inserted {
                result.append(name)
            }
        }
        for borrowing in allBorrowings.sorted(by: { $0.date > $1.date }) {
            let name = borrowing.friendName.trimmingCharacters(in: .whitespaces)
            if seen.insert(name.lowercased()).inserted {
                result.append(name)
            }
        }
        return result
    }

    /// Clean shareable summary text to send to friends via WhatsApp or Messages.
    private var shareSummaryText: String {
        let desc = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let billName = desc.isEmpty ? category.rawValue : desc
        let totalStr = Money.amount(fromPaise: totalPaise).formatted(.rupees)
        let payerStr = payer == .me ? "You" : (payerFriendName.isEmpty ? "Friend" : payerFriendName)

        var lines: [String] = []
        lines.append("🧾 Bill: \(billName) (\(totalStr))")
        lines.append("Paid by: \(payerStr)")
        lines.append("Date: \(date.formatted(.dateTime.day().month(.abbreviated).year()))")
        lines.append("")
        lines.append("Split Breakdown:")
        if includesMe && myPaise > 0 {
            lines.append("• Your share: \(Money.amount(fromPaise: myPaise).formatted(.rupees))")
        }
        for (friend, paise) in zip(friends, friendPaise) {
            let name = friend.name.isEmpty ? "Friend" : friend.name
            lines.append("• \(name): \(Money.amount(fromPaise: paise).formatted(.rupees))")
        }
        lines.append("")
        lines.append("Sent via ExpenseTracker")
        return lines.joined(separator: "\n")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                billSection
                payerSection
                paymentSourceSection
                splitSection
                if totalPaise > 0 {
                    summarySection
                }
            }
            .navigationTitle("Split a Bill")
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
                        if let index = contactTargetFriendIndex, index < friends.count {
                            friends[index].phone = choice.value.stringValue
                        } else {
                            payerFriendPhone = choice.value.stringValue
                        }
                    }
                }
            }
            .sheet(item: $cardAskingBillDay, onDismiss: { dismiss() }) { card in
                BillingCycleSheet(card: card)
            }
        }
    }

    // MARK: - Subviews

    private var billSection: some View {
        Section("Bill") {
            TextField("Total Amount", value: $total, format: .rupees)
                .keyboardType(.decimalPad)
                .font(.title2.weight(.semibold))

            TextField("What was it for? (e.g. Dinner with team)", text: $title)
                .textInputAutocapitalization(.sentences)

            Picker("Category", selection: $category) {
                ForEach(ExpenseCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                }
            }

            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
    }

    private var payerSection: some View {
        Section {
            Picker("Who Paid", selection: $payer.animation()) {
                ForEach(Payer.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if payer == .friend {
                HStack {
                    TextField("Friend's Name", text: $payerFriendName)
                        .textInputAutocapitalization(.words)

                    Button {
                        openContactPicker(for: nil)
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Select from Contacts")
                }

                TextField("Phone Number (optional)", text: $payerFriendPhone)
                    .keyboardType(.phonePad)

                // Quick tap to pick from friends added to the bill
                let namedFriends = friends.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if !namedFriends.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("From bill:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(namedFriends, id: \.self) { name in
                                Button {
                                    payerFriendName = name
                                    if let match = friends.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                                       !match.phone.isEmpty {
                                        payerFriendPhone = match.phone
                                    }
                                } label: {
                                    Text(name)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Picker("Your Share Settlement", selection: $friendSettlement.animation()) {
                    ForEach(FriendSettlement.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Who Paid")
        } footer: {
            if payer == .friend {
                if friendSettlement == .owe {
                    Text("Your share is added as an expense, and recorded as money you owe \(payerFriendName.isEmpty ? "your friend" : payerFriendName) under Borrowed.")
                } else {
                    Text("Your share is recorded as an expense paid directly from your chosen account.")
                }
            } else {
                Text("The full bill is paid from your account. Your share is recorded as an expense, and friends' shares become loans to them.")
            }
        }
    }

    @ViewBuilder
    private var paymentSourceSection: some View {
        if payer == .me || (payer == .friend && friendSettlement == .settled) {
            Section {
                Picker("Paid With", selection: $accountType.animation()) {
                    ForEach(AccountType.allCases) { type in
                        Label(type.rawValue, systemImage: type.systemImage).tag(type)
                    }
                }
                PaymentSourceFields(accountType: accountType, bankName: $bankName, cardLastFour: $cardLastFour)
            } header: {
                Text(payer == .me ? "Payment Method" : "How You Paid Your Share")
            } footer: {
                if usesBankOnly {
                    Text("Choose the bank this payment came from to keep your account balance accurate.")
                }
            }
        }
    }

    private var splitSection: some View {
        Section {
            Toggle("I'm Sharing This Bill", isOn: $includesMe.animation())

            Picker("Split", selection: $mode.animation()) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            // In custom mode with includesMe, show user's custom share input
            if mode == .custom, includesMe {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Share")
                            .font(.body.weight(.medium))
                        if myCustom == nil {
                            Text("Auto-balances remainder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    TextField("Share", value: $myCustom, format: .rupees, prompt: Text(Money.amount(fromPaise: autoMyPaise), format: .rupees))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                if myCustom != nil {
                    Button("Auto-balance Your Share") {
                        myCustom = nil
                    }
                    .font(.caption)
                }
            }

            ForEach($friends) { $friend in
                friendRow($friend)
            }
            .onDelete { indices in
                friends.remove(atOffsets: indices)
            }

            Button("Add Friend", systemImage: "plus.circle") {
                friends.append(Friend())
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions.prefix(8), id: \.self) { name in
                            Button {
                                addSuggestedFriend(name)
                            } label: {
                                Label(name, systemImage: "person.crop.circle")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                }
            }
        } header: {
            Text("Shared With")
        } footer: {
            if mode == .custom {
                if unallocatedPaise > 0 {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text("\(Money.amount(fromPaise: unallocatedPaise).formatted(.rupees)) left to allocate.")
                            .foregroundStyle(.orange)
                    }
                } else if unallocatedPaise < 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("The shares add up to \(Money.amount(fromPaise: -unallocatedPaise).formatted(.rupees)) more than the bill.")
                            .foregroundStyle(.red)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All shares match the total bill.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: Binding<Friend>) -> some View {
        let index = friends.firstIndex { $0.id == friend.wrappedValue.id } ?? 0
        let share = index < friendPaise.count ? friendPaise[index] : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Friend's Name", text: friend.name)
                    .textInputAutocapitalization(.words)

                Button {
                    openContactPicker(for: index)
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.body)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Select from Contacts")

                Spacer()

                if mode == .custom {
                    TextField("Share", value: friend.custom, format: .rupees)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                } else {
                    Text(Money.amount(fromPaise: share), format: .rupees)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Phone (optional)", text: friend.phone)
                .keyboardType(.phonePad)
                .font(.subheadline)
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            if includesMe {
                LabeledContent("Your Share") {
                    Text(Money.amount(fromPaise: max(0, myPaise)), format: .rupees)
                        .fontWeight(.semibold)
                }
            }

            if payer == .me {
                LabeledContent("Friends Owe You") {
                    Text(Money.amount(fromPaise: friendsAllocatedPaise), format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            } else if includesMe && friendSettlement == .owe {
                let payerTitle = payerFriendName.isEmpty ? "Friend" : payerFriendName
                LabeledContent("You Owe \(payerTitle)") {
                    Text(Money.amount(fromPaise: max(0, myPaise)), format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
            }

            ShareLink(item: shareSummaryText) {
                Label("Share Bill Breakdown", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Actions

    private func addSuggestedFriend(_ name: String) {
        let phone = allLoans.first(where: { $0.friendName.caseInsensitiveCompare(name) == .orderedSame && !$0.friendPhone.isEmpty })?.friendPhone
            ?? allBorrowings.first(where: { $0.friendName.caseInsensitiveCompare(name) == .orderedSame && !$0.friendPhone.isEmpty })?.friendPhone
            ?? ""
        let newFriend = Friend(name: name, phone: phone)
        if let blank = friends.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            friends[blank] = newFriend
        } else {
            friends.append(newFriend)
        }
    }

    private func openContactPicker(for friendIndex: Int?) {
        contactTargetFriendIndex = friendIndex
        ContactPickerPresenter.shared.present { contact in
            handleContactSelection(contact)
        }
    }

    private func handleContactSelection(_ contact: CNContact) {
        let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let fallback = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let resolvedName = fullName.isEmpty ? fallback : fullName

        let numbers = contact.phoneNumbers
        let pickedPhone = numbers.first?.value.stringValue ?? ""

        if let index = contactTargetFriendIndex {
            if index < friends.count {
                if !resolvedName.isEmpty { friends[index].name = resolvedName }
                if numbers.count == 1 {
                    friends[index].phone = pickedPhone
                } else if numbers.count > 1 {
                    phoneChoices = numbers
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        isChoosingPhone = true
                    }
                }
            }
        } else {
            if !resolvedName.isEmpty { payerFriendName = resolvedName }
            if numbers.count == 1 {
                payerFriendPhone = pickedPhone
            } else if numbers.count > 1 {
                phoneChoices = numbers
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    isChoosingPhone = true
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard isValid else { return }

        let description = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = "Split: " + (description.isEmpty ? category.rawValue : description)
        let expenseTitle = description.isEmpty ? "Split Bill (\(category.rawValue))" : "\(description) (my share)"

        let isBank = accountType.usesBank
        let isCard = accountType.usesCard
        let trimmedBank = (isBank || isCard) ? BankName.normalized(bankName) : ""
        let digits = isCard ? cardLastFour : ""

        var newCreditCard: PaymentCard?

        if payer == .me {
            // Auto-save new credit/debit card to stored PaymentCard
            if isCard && (!trimmedBank.isEmpty || !digits.isEmpty) {
                let alreadySaved = storedCards.contains {
                    $0.accountType == accountType &&
                    BankName.matches($0.bankName, trimmedBank) &&
                    $0.cardLastFour == digits
                }
                if !alreadySaved {
                    let saved = PaymentCard(
                        bankName: trimmedBank,
                        cardLastFour: digits,
                        accountType: accountType
                    )
                    modelContext.insert(saved)
                    if accountType == .creditCard {
                        newCreditCard = saved
                    }
                }
            }

            if accountType == .creditCard {
                CardSync.sync(in: modelContext)
            }

            // 1. My own share is recorded as an expense
            if includesMe && myPaise > 0 {
                let mine = Expense(
                    title: expenseTitle,
                    amount: Money.amount(fromPaise: myPaise),
                    accountType: accountType,
                    bankName: trimmedBank,
                    cardLastFour: digits,
                    category: category,
                    date: date
                )
                modelContext.insert(mine)
            }

            // 2. Each friend's share is a loan from the account the bill was paid from
            for (friend, paise) in zip(friends, friendPaise) where paise > 0 {
                let isCredit = accountType == .creditCard
                let loan = Loan(
                    amount: Money.amount(fromPaise: paise),
                    friendName: friend.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    friendPhone: friend.phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: note,
                    date: date,
                    method: isCredit ? .card : .cash,
                    accountType: isCredit ? .creditCard : .cash,
                    bankName: trimmedBank,
                    cardLastFour: digits
                )
                modelContext.insert(loan)
            }

            let context = modelContext
            Task {
                try? context.save()
                await BudgetAlerts.check(in: context)
                await CardBillReminder.reschedule(in: context)
            }
        } else {
            // Friend Paid
            let payerName = payerFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
            let payerPhone = payerFriendPhone.trimmingCharacters(in: .whitespacesAndNewlines)

            if includesMe && myPaise > 0 {
                if friendSettlement == .owe {
                    // Record my share as an expense
                    let mine = Expense(
                        title: expenseTitle,
                        amount: Money.amount(fromPaise: myPaise),
                        accountType: .cash,
                        bankName: "",
                        cardLastFour: "",
                        category: category,
                        date: date
                    )
                    modelContext.insert(mine)

                    // Record money owed to friend as Borrowing
                    let borrowing = Borrowing(
                        amount: Money.amount(fromPaise: myPaise),
                        friendName: payerName,
                        friendPhone: payerPhone,
                        note: note,
                        date: date,
                        bankName: ""
                    )
                    modelContext.insert(borrowing)

                    let context = modelContext
                    Task {
                        try? context.save()
                        await BudgetAlerts.check(in: context)
                        await BorrowingReminder.reschedule(in: context)
                    }
                } else {
                    // User already settled their share with the friend
                    let mine = Expense(
                        title: expenseTitle,
                        amount: Money.amount(fromPaise: myPaise),
                        accountType: accountType,
                        bankName: trimmedBank,
                        cardLastFour: digits,
                        category: category,
                        date: date
                    )
                    modelContext.insert(mine)

                    let context = modelContext
                    Task {
                        try? context.save()
                        await BudgetAlerts.check(in: context)
                        if accountType == .creditCard {
                            await CardBillReminder.reschedule(in: context)
                        }
                    }
                }
            }
        }

        if let newCreditCard {
            cardAskingBillDay = newCreditCard
        } else {
            dismiss()
        }
    }
}

#Preview {
    SplitBillFormView()
        .modelContainer(for: [Expense.self, Loan.self, Borrowing.self, PaymentCard.self, Account.self], inMemory: true)
}
