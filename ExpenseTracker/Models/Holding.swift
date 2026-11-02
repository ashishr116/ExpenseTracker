//
//  Holding.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

// MARK: - Holding Kind

/// What a holding is. Assets add to net worth; debts (`isDebt`) subtract from it.
enum HoldingKind: String, CaseIterable, Identifiable, Codable {
    // Assets
    case stock = "Stocks"
    case mutualFund = "Mutual Funds"
    case fixedDeposit = "Fixed Deposit"
    case recurringDeposit = "Recurring Deposit"
    case savings = "Savings Account"
    case gold = "Gold"
    case retirement = "PPF / EPF / NPS"
    case crypto = "Crypto"
    case otherAsset = "Other Investment"
    // Debts
    case creditCardDue = "Credit Card Due"
    case personalLoan = "Personal Loan"
    case homeLoan = "Home Loan"
    case vehicleLoan = "Vehicle Loan"
    case educationLoan = "Education Loan"
    case otherDebt = "Other Debt"

    var id: String { rawValue }

    static var assetKinds: [HoldingKind] { allCases.filter { !$0.isDebt } }
    static var debtKinds: [HoldingKind] { allCases.filter(\.isDebt) }

    var isDebt: Bool {
        switch self {
        case .creditCardDue, .personalLoan, .homeLoan, .vehicleLoan, .educationLoan, .otherDebt: true
        default: false
        }
    }

    var systemImage: String {
        switch self {
        case .stock: "chart.line.uptrend.xyaxis"
        case .mutualFund: "chart.pie"
        case .fixedDeposit: "building.columns"
        case .recurringDeposit: "arrow.triangle.2.circlepath"
        case .savings: "banknote"
        case .gold: "seal"
        case .retirement: "shield.lefthalf.filled"
        case .crypto: "bitcoinsign.circle"
        case .otherAsset: "square.stack.3d.up"
        case .creditCardDue: "creditcard.trianglebadge.exclamationmark"
        case .personalLoan: "indianrupeesign.circle"
        case .homeLoan: "house"
        case .vehicleLoan: "car"
        case .educationLoan: "graduationcap"
        case .otherDebt: "exclamationmark.circle"
        }
    }

    // MARK: Form behaviour

    /// Whether an invested/principal amount is tracked (to show gain or loss).
    var tracksInvested: Bool { !isDebt && self != .savings }

    /// Whether units/shares are tracked.
    var tracksQuantity: Bool { self == .stock || self == .mutualFund || self == .crypto }

    /// Whether an interest rate is tracked.
    var tracksInterest: Bool { isDebt || self == .fixedDeposit || self == .recurringDeposit }

    /// Whether a maturity date is tracked.
    var tracksMaturity: Bool { self == .fixedDeposit || self == .recurringDeposit }

    /// Whether this is a market-linked investment held on a broker/app.
    var isMarketLinked: Bool { self == .stock || self == .mutualFund || self == .crypto }

    var namePlaceholder: String {
        switch self {
        case .stock: "Stock (e.g. Reliance Industries)"
        case .mutualFund: "Fund (e.g. Parag Parikh Flexi Cap)"
        case .fixedDeposit, .recurringDeposit: "Name (e.g. SBI FD)"
        case .savings: "Account (e.g. HDFC Savings)"
        case .gold: "Name (e.g. Sovereign Gold Bond)"
        case .retirement: "Name (e.g. PPF)"
        case .crypto: "Coin (e.g. Bitcoin)"
        case .otherAsset: "Name"
        default: "Name (e.g. HDFC Personal Loan)"
        }
    }

    var platformLabel: String {
        switch self {
        case .stock, .mutualFund, .crypto: "Platform (e.g. Groww)"
        case .fixedDeposit, .recurringDeposit, .savings: "Bank"
        case _ where isDebt: "Lender / Bank"
        default: "Held With (optional)"
        }
    }

    var investedLabel: String {
        tracksMaturity ? "Principal" : "Invested Amount"
    }

    var valueLabel: String {
        switch self {
        case .savings: "Balance"
        case _ where isDebt: "Outstanding Amount"
        default: "Current Value"
        }
    }

    /// Common platforms suggested for market-linked investments.
    var suggestedPlatforms: [String] {
        isMarketLinked ? ["Groww", "Zerodha", "Upstox", "Angel One", "Kuvera", "INDmoney"] : []
    }
}

// MARK: - Holding Model

/// An investment, savings balance or debt, entered manually and persisted on-device.
/// Values aren't fetched live — update `currentValue` whenever you check your apps.
@Model
final class Holding {
    var name: String
    var kindRaw: String
    /// Broker/app (e.g. Groww), bank, or lender.
    var platform: String
    /// Amount put in (principal for FDs). 0 when not tracked.
    @Attribute(originalName: "investedAmount") private var legacyInvestedAmount: Double = 0
    var investedAmountPaise: Int64 = 0
    /// Today's value, balance, or outstanding debt.
    @Attribute(originalName: "currentValue") private var legacyCurrentValue: Double = 0
    var currentValuePaise: Int64 = 0
    /// Units/shares, for stocks, funds and crypto.
    var quantity: Double?
    /// Annual interest rate in percent (e.g. 7.1).
    var interestRate: Double?
    var maturityDate: Date?
    var note: String
    /// When the values were last edited.
    var updatedAt: Date
    /// Links money moved in and out of this investment (`Transfer.holdingUID`). Set on first use for older ones.
    var uid: String = ""

    // Monthly SIP: an amount moved from one of your accounts into this investment on the same day each month.
    var sipAmountPaise: Int64 = 0
    /// Day of the month, 1 to 28 so it exists in every month.
    var sipDay: Int = 1
    /// The bank or cash account the SIP is paid from.
    var sipAccountUID: String = ""
    /// The SIP was set up on this day. Earlier months are never added.
    var sipStartDate: Date?
    /// The last SIP added, so none is added twice.
    var sipLastPosted: Date?

    init(
        name: String,
        kind: HoldingKind,
        platform: String = "",
        investedAmount: Decimal = 0,
        currentValue: Decimal,
        quantity: Double? = nil,
        interestRate: Double? = nil,
        maturityDate: Date? = nil,
        note: String = "",
        updatedAt: Date = .now
    ) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.platform = platform
        self.investedAmountPaise = Money.paise(from: investedAmount)
        self.currentValuePaise = Money.paise(from: currentValue)
        self.quantity = quantity
        self.interestRate = interestRate
        self.maturityDate = maturityDate
        self.note = note
        self.updatedAt = updatedAt
        self.uid = UUID().uuidString
    }

    var kind: HoldingKind {
        get { HoldingKind(rawValue: kindRaw) ?? .otherAsset }
        set { kindRaw = newValue.rawValue }
    }

    var investedAmount: Decimal {
        get {
            investedAmountPaise == 0 && legacyInvestedAmount != 0
                ? Money.amount(fromLegacy: legacyInvestedAmount)
                : Money.amount(fromPaise: investedAmountPaise)
        }
        set { investedAmountPaise = Money.paise(from: newValue) }
    }

    var currentValue: Decimal {
        get {
            currentValuePaise == 0 && legacyCurrentValue != 0
                ? Money.amount(fromLegacy: legacyCurrentValue)
                : Money.amount(fromPaise: currentValuePaise)
        }
        set { currentValuePaise = Money.paise(from: newValue) }
    }

    func migrateLegacyMoney() {
        if investedAmountPaise == 0, legacyInvestedAmount != 0 {
            investedAmountPaise = Money.paise(from: Money.amount(fromLegacy: legacyInvestedAmount))
        }
        if currentValuePaise == 0, legacyCurrentValue != 0 {
            currentValuePaise = Money.paise(from: Money.amount(fromLegacy: legacyCurrentValue))
        }
    }

    /// Profit or loss versus the invested amount; `nil` when not applicable.
    var gain: Decimal? {
        guard kind.tracksInvested, investedAmount > 0 else { return nil }
        return currentValue - investedAmount
    }

    /// Gain as a fraction of the invested amount (0.12 = 12%).
    var gainFraction: Decimal? {
        gain.map { $0 / investedAmount }
    }
}

// MARK: - Money in and out

extension Holding {
    /// Debts are paid off elsewhere; only investments and savings take money in and out.
    var movesMoney: Bool { !kind.isDebt }

    /// The id used to link this investment's money moves, created when first needed.
    @discardableResult
    func ensureUID() -> String {
        if uid.isEmpty { uid = UUID().uuidString }
        return uid
    }

    /// Puts more money in: the value and the amount invested go up, and the account it came from goes down.
    /// Without an account, only the investment changes.
    func addMoney(_ amount: Decimal, from account: Account?, on date: Date = .now, in context: ModelContext) {
        guard amount > 0 else { return }
        if kind.tracksInvested { investedAmount += amount }
        currentValue += amount
        updatedAt = .now
        guard let account else { return }
        let transfer = Transfer(amount: amount, date: date, note: "Invested in \(name)")
        transfer.holdingUID = ensureUID()
        context.insert(transfer)
        transfer.fromAccount = account
    }

    /// Takes money out: the value goes down, and the account it went to goes up. The amount invested goes down
    /// in the same proportion, so the gain on what is left stays the same.
    func withdraw(_ amount: Decimal, to account: Account?, on date: Date = .now, in context: ModelContext) {
        let taken = min(amount, currentValue)
        guard taken > 0 else { return }
        if kind.tracksInvested, currentValue > 0 {
            investedAmount = max(0, investedAmount - investedAmount * taken / currentValue)
        }
        currentValue -= taken
        updatedAt = .now
        guard let account else { return }
        let transfer = Transfer(amount: taken, date: date, note: "Withdrawn from \(name)")
        transfer.holdingUID = ensureUID()
        context.insert(transfer)
        transfer.toAccount = account
    }

    // MARK: SIP

    var sipAmount: Decimal? {
        get { sipAmountPaise > 0 ? Money.amount(fromPaise: sipAmountPaise) : nil }
        set { sipAmountPaise = newValue.map { Money.paise(from: $0) } ?? 0 }
    }

    var hasSIP: Bool { movesMoney && sipAmountPaise > 0 && !sipAccountUID.isEmpty }

    /// The SIP day in the month containing `month`, at 9:00.
    func sipDate(inMonth month: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(max(sipDay, 1), 28)
        components.hour = 9
        return calendar.date(from: components)
    }

    /// Whether this month's SIP is still to be added: due in that month, on or after the SIP started,
    /// and not added yet.
    func isSIPOutstanding(inMonth month: Date) -> Bool {
        guard hasSIP, let date = sipDate(inMonth: month), let start = sipStartDate else { return false }
        if date < Calendar.current.startOfDay(for: start) { return false }
        if let last = sipLastPosted, date <= last { return false }
        return true
    }

    /// SIPs due by `now` that haven't been added yet, oldest first.
    func dueSIPDates(now: Date = .now) -> [Date] {
        guard hasSIP, let start = sipStartDate else { return [] }
        let calendar = Calendar.current
        var month = calendar.monthRange(containing: start).lowerBound
        var dates: [Date] = []
        while month <= now, dates.count < 600 {
            if isSIPOutstanding(inMonth: month), let date = sipDate(inMonth: month), date <= now {
                dates.append(date)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }

    /// The next SIP day from now, for showing on the form.
    func nextSIPDate(now: Date = .now) -> Date? {
        guard hasSIP else { return nil }
        let calendar = Calendar.current
        var month = calendar.monthRange(containing: now).lowerBound
        for _ in 0..<13 {
            if isSIPOutstanding(inMonth: month), let date = sipDate(inMonth: month), date > now { return date }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return nil
    }
}

/// Adds each investment's monthly SIP once its day comes, taking it from the chosen account.
enum SIPPoster {
    @MainActor
    static func run(in context: ModelContext, now: Date = .now) {
        let holdings = (try? context.fetch(FetchDescriptor<Holding>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var changed = false
        for holding in holdings where holding.hasSIP {
            // An account that was removed or closed stops the SIP from being added, rather than guessing another.
            guard let amount = holding.sipAmount,
                  let account = accounts.first(where: { $0.uid == holding.sipAccountUID && !$0.isArchived }) else { continue }
            for date in holding.dueSIPDates(now: now) {
                holding.addMoney(amount, from: account, on: date, in: context)
                holding.sipLastPosted = date
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// SIPs still to be paid in the month containing `month`, for the forecast of coming months.
    static func outstanding(in month: Date, holdings: [Holding]) -> Decimal {
        holdings.filter { $0.isSIPOutstanding(inMonth: month) }.reduce(Decimal(0)) { $0 + ($1.sipAmount ?? 0) }
    }
}

extension Sequence where Element == Holding {
    var totalValue: Decimal { reduce(0) { $0 + $1.currentValue } }
}
