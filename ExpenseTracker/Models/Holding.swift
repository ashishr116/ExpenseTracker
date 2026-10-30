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

extension Sequence where Element == Holding {
    var totalValue: Decimal { reduce(0) { $0 + $1.currentValue } }
}
