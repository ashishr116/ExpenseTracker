//
//  Loan.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// How the friend received the money.
enum LoanMethod: String, CaseIterable, Identifiable, Codable {
    /// Cash or a bank/UPI transfer.
    case cash = "Cash / Transfer"
    /// The friend used your card for their own purchase.
    case card = "Used My Card"
    /// The friend took a personal loan from a bank in your name.
    case personalLoan = "Personal Loan"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .card: "creditcard"
        case .personalLoan: "building.columns"
        }
    }

    /// Borrowed or spent on your card or in your name. The friend owes it to the card or the bank,
    /// so it stays out of cash flow and net worth and appears only under Loans.
    var isOnMyName: Bool { self != .cash }

    /// A one-line explanation shown under the picker.
    var explanation: String? {
        switch self {
        case .cash:
            nil
        case .card:
            "Your friend used your card for their own purchase. It's on your card bill, but they owe it back to you."
        case .personalLoan:
            "Your friend took a personal loan in your name. The bank bills you, but your friend owes it back."
        }
    }
}

/// Money lent to a friend, persisted on-device with SwiftData.
/// The friend can pay it back in several parts; each part is a `LoanRepayment`.
@Model
final class Loan {
    @Attribute(originalName: "amount") private var legacyAmount: Double = 0
    var amountPaise: Int64 = 0
    var friendName: String
    var note: String
    /// The day the money was lent (or the day the friend used your card).
    var date: Date
    /// The day the last payment cleared the loan; `nil` while any amount is still owed.
    var repaidDate: Date?

    // Defaults let existing loans migrate automatically as cash loans.
    var methodRaw: String = LoanMethod.cash.rawValue
    /// Card details when `method == .card`; empty otherwise.
    var accountTypeRaw: String = AccountType.creditCard.rawValue
    var bankName: String = ""
    var cardLastFour: String = ""

    /// Friend's mobile number, used for payment reminders.
    var friendPhone: String = ""
    /// When a reminder for this loan was last sent.
    var lastRemindedAt: Date?

    /// For a friend's EMI on your card: remind me on the same day every month until it is repaid.
    var monthlyReminderEnabled: Bool = false
    /// Day of the month for the reminder, 1 to 28 so it exists in every month.
    var monthlyReminderDay: Int = 1
    /// What the friend owes each month, shown in the reminder. 0 means not set.
    var monthlyInstalmentPaise: Int64 = 0
    /// For a personal loan or a card EMI repaid in equal instalments: how many. The loan amount is this
    /// times the instalment. 0 for every other loan.
    var installmentCount: Int = 0

    /// Payments received so far.
    @Relationship(deleteRule: .cascade, inverse: \LoanRepayment.loan)
    var repayments: [LoanRepayment] = []

    init(
        amount: Decimal,
        friendName: String,
        friendPhone: String = "",
        note: String = "",
        date: Date = .now,
        repaidDate: Date? = nil,
        method: LoanMethod = .cash,
        accountType: AccountType = .creditCard,
        bankName: String = "",
        cardLastFour: String = ""
    ) {
        self.amountPaise = Money.paise(from: amount)
        self.friendName = friendName
        self.friendPhone = friendPhone
        self.note = note
        self.date = date
        self.repaidDate = repaidDate
        self.methodRaw = method.rawValue
        self.accountTypeRaw = accountType.rawValue
        self.bankName = bankName
        self.cardLastFour = cardLastFour
    }

    /// True once the full amount has been paid back.
    var isRepaid: Bool { repaidDate != nil }

    var amount: Decimal {
        get { amountPaise == 0 && legacyAmount != 0 ? Money.amount(fromLegacy: legacyAmount) : Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    func migrateLegacyMoney() {
        guard amountPaise == 0, legacyAmount != 0 else { return }
        amountPaise = Money.paise(from: Money.amount(fromLegacy: legacyAmount))
    }

    var method: LoanMethod {
        get { LoanMethod(rawValue: methodRaw) ?? .cash }
        set { methodRaw = newValue.rawValue }
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .creditCard }
        set { accountTypeRaw = newValue.rawValue }
    }

    /// e.g. "Credit Card · HDFC Bank · •••• 1234" for card loans; `nil` for cash loans.
    var cardDescription: String? {
        switch method {
        case .cash:
            return nil
        case .personalLoan:
            return bankName.isEmpty ? "Personal loan" : "Personal loan · \(BankName.display(bankName))"
        case .card:
            var parts = [accountType.rawValue]
            if !bankName.isEmpty { parts.append(BankName.display(bankName)) }
            if !cardLastFour.isEmpty { parts.append("•••• \(cardLastFour)") }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: Monthly reminder

    /// The friend's monthly share of the EMI, if you entered one.
    var monthlyInstalment: Decimal? {
        get { monthlyInstalmentPaise > 0 ? Money.amount(fromPaise: monthlyInstalmentPaise) : nil }
        set { monthlyInstalmentPaise = newValue.map { Money.paise(from: $0) } ?? 0 }
    }

    // MARK: Instalments

    /// A personal loan, or an EMI the friend took on your card, repaid in equal monthly instalments.
    var isInstalmentLoan: Bool {
        method.isOnMyName && installmentCount > 0 && (monthlyInstalment ?? 0) > 0
    }

    /// How many whole instalments the money received so far covers.
    var installmentsPaid: Int {
        guard isInstalmentLoan, let instalment = monthlyInstalment else { return 0 }
        var wholeInstalments = repaidAmount / instalment
        var rounded = Decimal()
        NSDecimalRound(&rounded, &wholeInstalments, 0, .down)
        return min(installmentCount, NSDecimalNumber(decimal: rounded).intValue)
    }

    /// How many instalments are due by now, counted on the reminder day of each month after the loan.
    var installmentsDueSoFar: Int {
        guard isInstalmentLoan else { return 0 }
        return min(installmentCount, Loan.monthlyPaymentDates(after: date, day: monthlyReminderDay).count)
    }

    /// How many instalments to ask for now: this month's, plus any earlier ones still unpaid.
    /// Never fewer than one while something is owed, and never more than remain.
    var emiDueCount: Int {
        guard isInstalmentLoan, !isRepaid else { return 0 }
        let remaining = max(0, installmentCount - installmentsPaid)
        let behind = installmentsDueSoFar - installmentsPaid
        return min(remaining, max(1, behind))
    }

    /// What to ask the friend for now. For an instalment loan that is the EMI, not the whole balance.
    var emiDueAmount: Decimal {
        guard isInstalmentLoan, let instalment = monthlyInstalment else { return outstandingAmount }
        return min(Decimal(emiDueCount) * instalment, outstandingAmount)
    }

    /// A monthly reminder is on for a card loan that still has something owed.
    var hasActiveMonthlyReminder: Bool {
        method.isOnMyName && monthlyReminderEnabled && !isRepaid
    }

    /// The monthly payment dates after a loan was made: `day` of each following month, up to `limit`.
    /// Used when adding a loan that is already partly repaid month by month.
    static func monthlyPaymentDates(after loanDate: Date, day: Int, through limit: Date = .now) -> [Date] {
        let calendar = Calendar.current
        guard var month = calendar.date(byAdding: .month, value: 1, to: calendar.monthRange(containing: loanDate).lowerBound) else {
            return []
        }
        var dates: [Date] = []
        // Cap at 50 years as a safety net against a bad date.
        while dates.count < 600 {
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(max(day, 1), 28)
            components.hour = 9
            guard let date = calendar.date(from: components), date <= limit else { break }
            dates.append(date)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }

    // MARK: Card charges

    /// One amount billed to your card for this loan.
    struct CardCharge {
        let id: String
        let date: Date
        let amount: Decimal
        /// Wording for an instalment, such as "EMI 2 of 6". `nil` for a loan billed whole.
        let subtitle: String?
    }

    /// What this loan has put on your card up to `now`. A plain card loan is one charge on its day. An EMI is
    /// one charge a month, starting on its day, so the card shows what the bank has billed so far.
    func cardCharges(upTo now: Date) -> [CardCharge] {
        let base = "card-loan-\(persistentModelID)"
        guard isInstalmentLoan, let instalment = monthlyInstalment else {
            return date <= now ? [CardCharge(id: base, date: date, amount: amount, subtitle: nil)] : []
        }
        let calendar = Calendar.current
        var charges: [CardCharge] = []
        for index in 0..<installmentCount {
            guard let due = calendar.date(byAdding: .month, value: index, to: date), due <= now else { break }
            // The last instalment takes any rounding, so the charges add up to the loan.
            let isLast = index == installmentCount - 1
            let share = isLast ? amount - instalment * Decimal(installmentCount - 1) : instalment
            charges.append(CardCharge(
                id: "\(base)-\(index)", date: due, amount: share,
                subtitle: "EMI \(index + 1) of \(installmentCount)"
            ))
        }
        return charges
    }

    // MARK: Repayments

    /// Total received so far. A loan marked repaid before part payments existed counts as fully repaid.
    var repaidAmount: Decimal {
        if repayments.isEmpty { return repaidDate != nil ? amount : 0 }
        return repayments.reduce(0) { $0 + $1.amount }
    }

    /// What the friend still owes.
    var outstandingAmount: Decimal { max(0, amount - repaidAmount) }

    /// Whether lending and repaying this loan move money in your cash flow. A loan on your card isn't
    /// recorded as an expense, and its repayment settles the card instead of coming to you, so it stays
    /// out of cash flow. It still counts as owed to you in net worth.
    var countsInCashFlow: Bool { method == .cash }

    /// Some of it has been paid back, but not all.
    var isPartlyRepaid: Bool { !isRepaid && repaidAmount > 0 }

    /// Payments received, newest first.
    var sortedRepayments: [LoanRepayment] { repayments.sorted { $0.date > $1.date } }

    /// Sets `repaidDate` from the repayments: the date of the last payment once nothing is owed, otherwise `nil`.
    func syncRepaidState() {
        if repayments.isEmpty || outstandingAmount > 0 {
            repaidDate = nil
        } else {
            repaidDate = repayments.map(\.date).max()
        }
    }

    /// Records money received from the friend. The amount is capped at what is still owed.
    @discardableResult
    func recordRepayment(
        _ received: Decimal,
        on date: Date = .now,
        note: String = "",
        bankName receivedIn: String? = nil,
        in context: ModelContext
    ) -> LoanRepayment? {
        let amount = min(received, outstandingAmount)
        guard amount > 0 else { return nil }
        // By default the money comes back to the account it was lent from.
        let bank = receivedIn ?? (method == .cash ? bankName : "")
        let repayment = LoanRepayment(amount: amount, date: date, note: note, bankName: bank)
        context.insert(repayment)
        repayments.append(repayment)
        syncRepaidState()
        return repayment
    }

    /// Records the whole remaining balance as received.
    func markFullyRepaid(on date: Date = .now, in context: ModelContext) {
        recordRepayment(outstandingAmount, on: date, in: context)
    }

    /// Deletes a payment, for example one entered by mistake. The loan becomes outstanding again.
    func removeRepayment(_ repayment: LoanRepayment, in context: ModelContext) {
        repayments.removeAll { $0 === repayment }
        context.delete(repayment)
        syncRepaidState()
    }
}

// MARK: - Repayment

/// One payment received from the friend towards a loan.
@Model
final class LoanRepayment {
    var amountPaise: Int64 = 0
    var date: Date = Date.now
    var note: String = ""
    /// The bank account the money arrived in. Empty means cash.
    var bankName: String = ""
    /// For a loan on your card: the friend paid you rather than the card. The money is in your account, and
    /// their share of the card is now yours to pay.
    var receivedByMe: Bool = false
    var loan: Loan?

    init(amount: Decimal, date: Date = .now, note: String = "", bankName: String = "") {
        self.amountPaise = Money.paise(from: amount)
        self.date = date
        self.note = note
        self.bankName = bankName
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    /// Money back that counts as income in cash flow: repayments of cash or transfer loans only.
    var isCashInflow: Bool { loan?.countsInCashFlow ?? true }

    /// A friend paid you their share of your card. It raises your account, and the card bill you pay with it
    /// lowers it again, so it counts in cash left but not as income.
    var isCardShareReceived: Bool { receivedByMe && loan?.method == .card }
}

extension Sequence where Element == LoanRepayment {
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }
}

extension Sequence where Element == Loan {
    /// The full amounts lent, whether or not they've been repaid.
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }

    /// What friends still owe after any part payments.
    var outstandingTotal: Decimal { reduce(0) { $0 + $1.outstandingAmount } }
}
