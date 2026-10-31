//
//  BackupManager.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - File format

/// Everything in the app, as one file that can be saved to Files or iCloud Drive and restored later.
///
/// Records that point at each other (an expense and its EMI, a repayment and its loan, a transfer and its
/// accounts) refer to one another by position in these lists. Full card numbers and CVV are never written.
struct BackupFile: Codable {
    var version = 1
    var createdAt = Date.now
    var accounts: [AccountDTO] = []
    var incomes: [IncomeDTO] = []
    var emis: [EMIDTO] = []
    var policies: [PolicyDTO] = []
    var loans: [LoanDTO] = []
    var expenses: [ExpenseDTO] = []
    var repayments: [RepaymentDTO] = []
    var holdings: [HoldingDTO] = []
    var cards: [CardDTO] = []
    var transfers: [TransferDTO] = []
    var monthlySavings: [SavingsDTO] = []
    /// Missing in backups made before goals existed.
    var goals: [GoalDTO]?
    /// Missing in backups made before recurring expenses existed.
    var recurringExpenses: [RecurringExpenseDTO]?
    /// Missing in backups made before category limits existed.
    var categoryBudgets: [CategoryBudgetDTO]?
}

struct CategoryBudgetDTO: Codable {
    var categoryRaw: String
    var limitPaise: Int64
    var createdAt: Date
}

struct RecurringExpenseDTO: Codable {
    var title: String
    var amountPaise: Int64
    var categoryRaw: String
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
    var dayOfMonth: Int
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    var lastPostedMonth: Date?
    var createdAt: Date
}

struct GoalDTO: Codable {
    var name: String
    var targetPaise: Int64
    var monthlyPaise: Int64
    var startMonth: Date
    var targetDate: Date?
    var lastProcessedMonth: Date?
    var completedAt: Date?
    var createdAt: Date
    var contributions: [GoalContributionDTO]
}

struct GoalContributionDTO: Codable {
    var amountPaise: Int64
    var date: Date
    var note: String
    var month: Date?
}

struct AccountDTO: Codable {
    var uid: String
    var name: String
    var kindRaw: String
    var bankName: String
    var cardLastFour: String
    var openingBalancePaise: Int64
    var openingDate: Date
    var isArchived: Bool
    var createdAt: Date
}

struct IncomeDTO: Codable {
    var amountPaise: Int64
    var sourceRaw: String
    var note: String
    var bankName: String
    var date: Date
}

struct EMIDTO: Codable {
    var name: String
    var monthlyAmountPaise: Int64
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
    var billingDay: Int
    var startMonth: Date
    var endMonth: Date
    var annualInterestRate: Double?
    var includedInNetWorth: Bool
}

struct PolicyDTO: Codable {
    var typeRaw: String
    var insurerName: String
    var planName: String
    var policyNumber: String
    var coverAmountPaise: Int64
    var premiumAmountPaise: Int64
    var frequencyRaw: String
    var startDate: Date
    var endDate: Date
    var nomineeOrMembers: String
    var note: String
    var firstPremiumDate: Date?
    var addsToExpenses: Bool
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
}

struct LoanDTO: Codable {
    var amountPaise: Int64
    var friendName: String
    var note: String
    var date: Date
    var repaidDate: Date?
    var methodRaw: String
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
    var friendPhone: String
    var lastRemindedAt: Date?
    var monthlyReminderEnabled: Bool
    var monthlyReminderDay: Int
    var monthlyInstalmentPaise: Int64
    /// Missing in backups made before personal loans had instalments.
    var installmentCount: Int?
}

struct ExpenseDTO: Codable {
    var title: String
    var amountPaise: Int64
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
    var categoryRaw: String
    var date: Date
    var paidAt: Date?
    /// Position in `emis`, if this is an EMI instalment.
    var emi: Int?
    /// Position in `policies`, if this is an insurance premium.
    var policy: Int?
    /// Name typed for a custom category. Missing in backups made before custom categories existed.
    var customCategory: String?
}

struct RepaymentDTO: Codable {
    var amountPaise: Int64
    var date: Date
    var note: String
    var bankName: String
    /// Position in `loans`.
    var loan: Int?
}

struct HoldingDTO: Codable {
    var name: String
    var kindRaw: String
    var platform: String
    var investedAmountPaise: Int64
    var currentValuePaise: Int64
    var quantity: Double?
    var interestRate: Double?
    var maturityDate: Date?
    var note: String
    var updatedAt: Date
}

struct CardDTO: Codable {
    var bankName: String
    var cardLastFour: String
    var cardholderName: String
    var accountTypeRaw: String
    var nickname: String
    var createdAt: Date
    /// Missing in backups made before cards were linked to accounts.
    var accountUID: String?
}

struct TransferDTO: Codable {
    var amountPaise: Int64
    var date: Date
    var note: String
    /// Positions in `accounts`.
    var from: Int?
    var to: Int?
}

struct SavingsDTO: Codable {
    var month: Date
    var leftoverPaise: Int64
    var appliedPaise: Int64
    var bankName: String
    var createdAt: Date
    /// Position in `transfers`.
    var transfer: Int?
}

// MARK: - Document for the save and open sheets

/// Wraps the backup bytes so the system file exporter can save them where the user chooses.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Making and restoring a backup

enum BackupError: LocalizedError {
    case unreadable
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file isn't an ExpenseTracker backup, or it is damaged."
        case .newerVersion: "This backup was made by a newer version of the app. Update the app first."
        }
    }
}

enum BackupManager {
    static let lastBackupKey = "lastBackupDate"
    private static let currentVersion = 1

    // MARK: Make

    static func makeBackup(from context: ModelContext) throws -> Data {
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>())
        }

        let accounts = try all(Account.self)
        let emis = try all(EMI.self)
        let policies = try all(InsurancePolicy.self)
        let loans = try all(Loan.self)
        let transfers = try all(Transfer.self)

        func index<T: PersistentModel>(_ items: [T]) -> [PersistentIdentifier: Int] {
            Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.persistentModelID, $0) })
        }
        let accountIndex = index(accounts)
        let emiIndex = index(emis)
        let policyIndex = index(policies)
        let loanIndex = index(loans)
        let transferIndex = index(transfers)

        var file = BackupFile(version: currentVersion)

        file.accounts = accounts.map {
            AccountDTO(
                uid: $0.uid, name: $0.name, kindRaw: $0.kindRaw, bankName: $0.bankName,
                cardLastFour: $0.cardLastFour, openingBalancePaise: $0.openingBalancePaise,
                openingDate: $0.openingDate, isArchived: $0.isArchived, createdAt: $0.createdAt
            )
        }
        file.incomes = try all(Income.self).map {
            IncomeDTO(
                amountPaise: Money.paise(from: $0.amount), sourceRaw: $0.sourceRaw, note: $0.note,
                bankName: $0.bankName, date: $0.date
            )
        }
        file.emis = emis.map {
            EMIDTO(
                name: $0.name, monthlyAmountPaise: Money.paise(from: $0.monthlyAmount),
                accountTypeRaw: $0.accountTypeRaw, bankName: $0.bankName, cardLastFour: $0.cardLastFour,
                billingDay: $0.billingDay, startMonth: $0.startMonth, endMonth: $0.endMonth,
                annualInterestRate: $0.annualInterestRate, includedInNetWorth: $0.includedInNetWorth
            )
        }
        file.policies = policies.map {
            PolicyDTO(
                typeRaw: $0.typeRaw, insurerName: $0.insurerName, planName: $0.planName,
                policyNumber: $0.policyNumber, coverAmountPaise: Money.paise(from: $0.coverAmount),
                premiumAmountPaise: Money.paise(from: $0.premiumAmount), frequencyRaw: $0.frequencyRaw,
                startDate: $0.startDate, endDate: $0.endDate, nomineeOrMembers: $0.nomineeOrMembers,
                note: $0.note, firstPremiumDate: $0.firstPremiumDate, addsToExpenses: $0.addsToExpenses,
                accountTypeRaw: $0.accountTypeRaw, bankName: $0.bankName, cardLastFour: $0.cardLastFour
            )
        }
        file.loans = loans.map {
            LoanDTO(
                amountPaise: Money.paise(from: $0.amount), friendName: $0.friendName, note: $0.note,
                date: $0.date, repaidDate: $0.repaidDate, methodRaw: $0.methodRaw,
                accountTypeRaw: $0.accountTypeRaw, bankName: $0.bankName, cardLastFour: $0.cardLastFour,
                friendPhone: $0.friendPhone, lastRemindedAt: $0.lastRemindedAt,
                monthlyReminderEnabled: $0.monthlyReminderEnabled, monthlyReminderDay: $0.monthlyReminderDay,
                monthlyInstalmentPaise: $0.monthlyInstalmentPaise,
                installmentCount: $0.installmentCount
            )
        }
        file.expenses = try all(Expense.self).map { expense in
            ExpenseDTO(
                title: expense.title, amountPaise: Money.paise(from: expense.amount),
                accountTypeRaw: expense.accountTypeRaw, bankName: expense.bankName,
                cardLastFour: expense.cardLastFour, categoryRaw: expense.categoryRaw, date: expense.date,
                paidAt: expense.paidAt,
                emi: expense.emi.flatMap { emiIndex[$0.persistentModelID] },
                policy: expense.insurancePolicy.flatMap { policyIndex[$0.persistentModelID] },
                customCategory: expense.customCategory
            )
        }
        file.repayments = try all(LoanRepayment.self).map { repayment in
            RepaymentDTO(
                amountPaise: Money.paise(from: repayment.amount), date: repayment.date, note: repayment.note,
                bankName: repayment.bankName,
                loan: repayment.loan.flatMap { loanIndex[$0.persistentModelID] }
            )
        }
        file.holdings = try all(Holding.self).map {
            HoldingDTO(
                name: $0.name, kindRaw: $0.kindRaw, platform: $0.platform,
                investedAmountPaise: Money.paise(from: $0.investedAmount),
                currentValuePaise: Money.paise(from: $0.currentValue), quantity: $0.quantity,
                interestRate: $0.interestRate, maturityDate: $0.maturityDate, note: $0.note,
                updatedAt: $0.updatedAt
            )
        }
        // Only the last four digits, never the full number, expiry or CVV.
        file.cards = try all(PaymentCard.self).map {
            CardDTO(
                bankName: $0.bankName, cardLastFour: $0.cardLastFour, cardholderName: $0.cardholderName,
                accountTypeRaw: $0.accountTypeRaw, nickname: $0.nickname, createdAt: $0.createdAt,
                accountUID: $0.accountUID
            )
        }
        file.transfers = transfers.map { transfer in
            TransferDTO(
                amountPaise: transfer.amountPaise, date: transfer.date, note: transfer.note,
                from: transfer.fromAccount.flatMap { accountIndex[$0.persistentModelID] },
                to: transfer.toAccount.flatMap { accountIndex[$0.persistentModelID] }
            )
        }
        file.monthlySavings = try all(MonthlySavings.self).map { record in
            SavingsDTO(
                month: record.month, leftoverPaise: record.leftoverPaise, appliedPaise: record.appliedPaise,
                bankName: record.bankName, createdAt: record.createdAt,
                transfer: record.transfer.flatMap { transferIndex[$0.persistentModelID] }
            )
        }

        file.goals = try all(Goal.self).map { goal in
            GoalDTO(
                name: goal.name, targetPaise: goal.targetPaise, monthlyPaise: goal.monthlyPaise,
                startMonth: goal.startMonth, targetDate: goal.targetDate,
                lastProcessedMonth: goal.lastProcessedMonth, completedAt: goal.completedAt,
                createdAt: goal.createdAt,
                contributions: goal.contributions.map {
                    GoalContributionDTO(amountPaise: $0.amountPaise, date: $0.date, note: $0.note, month: $0.month)
                }
            )
        }

        file.recurringExpenses = try all(RecurringExpense.self).map {
            RecurringExpenseDTO(
                title: $0.title, amountPaise: $0.amountPaise, categoryRaw: $0.categoryRaw,
                accountTypeRaw: $0.accountTypeRaw, bankName: $0.bankName, cardLastFour: $0.cardLastFour,
                dayOfMonth: $0.dayOfMonth, startDate: $0.startDate, endDate: $0.endDate, isActive: $0.isActive,
                lastPostedMonth: $0.lastPostedMonth, createdAt: $0.createdAt
            )
        }

        file.categoryBudgets = try all(CategoryBudget.self).map {
            CategoryBudgetDTO(categoryRaw: $0.categoryRaw, limitPaise: $0.limitPaise, createdAt: $0.createdAt)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // MARK: Restore

    /// Replaces everything in the app with the contents of a backup. Nothing is changed if the file can't be read.
    static func restore(_ data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        guard file.version <= currentVersion else { throw BackupError.newerVersion }

        try deleteEverything(in: context)

        // Records other records point at come first.
        let accounts = file.accounts.map { dto -> Account in
            let account = Account(
                name: dto.name, kind: AccountKind(rawValue: dto.kindRaw) ?? .bank, bankName: dto.bankName,
                cardLastFour: dto.cardLastFour, openingBalance: Money.amount(fromPaise: dto.openingBalancePaise),
                openingDate: dto.openingDate
            )
            account.uid = dto.uid
            account.isArchived = dto.isArchived
            account.createdAt = dto.createdAt
            context.insert(account)
            return account
        }

        for dto in file.incomes {
            let income = Income(
                amount: Money.amount(fromPaise: dto.amountPaise),
                source: IncomeSource(rawValue: dto.sourceRaw) ?? .other,
                note: dto.note, bankName: dto.bankName, date: dto.date
            )
            context.insert(income)
        }

        let emis = file.emis.map { dto -> EMI in
            let emi = EMI(
                name: dto.name, monthlyAmount: Money.amount(fromPaise: dto.monthlyAmountPaise),
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .creditCard,
                bankName: dto.bankName, cardLastFour: dto.cardLastFour, billingDay: dto.billingDay,
                startMonth: dto.startMonth, endMonth: dto.endMonth
            )
            emi.annualInterestRate = dto.annualInterestRate
            emi.includedInNetWorth = dto.includedInNetWorth
            context.insert(emi)
            return emi
        }

        let policies = file.policies.map { dto -> InsurancePolicy in
            let policy = InsurancePolicy(
                type: InsuranceType(rawValue: dto.typeRaw) ?? .health, insurerName: dto.insurerName,
                planName: dto.planName, policyNumber: dto.policyNumber,
                coverAmount: Money.amount(fromPaise: dto.coverAmountPaise),
                premiumAmount: Money.amount(fromPaise: dto.premiumAmountPaise),
                frequency: PremiumFrequency(rawValue: dto.frequencyRaw) ?? .annually,
                startDate: dto.startDate, endDate: dto.endDate, nomineeOrMembers: dto.nomineeOrMembers,
                note: dto.note, firstPremiumDate: dto.firstPremiumDate, addsToExpenses: dto.addsToExpenses,
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .upi,
                bankName: dto.bankName, cardLastFour: dto.cardLastFour
            )
            context.insert(policy)
            return policy
        }

        let loans = file.loans.map { dto -> Loan in
            let loan = Loan(
                amount: Money.amount(fromPaise: dto.amountPaise), friendName: dto.friendName,
                friendPhone: dto.friendPhone, note: dto.note, date: dto.date, repaidDate: dto.repaidDate,
                method: LoanMethod(rawValue: dto.methodRaw) ?? .cash,
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .creditCard,
                bankName: dto.bankName, cardLastFour: dto.cardLastFour
            )
            loan.lastRemindedAt = dto.lastRemindedAt
            loan.monthlyReminderEnabled = dto.monthlyReminderEnabled
            loan.monthlyReminderDay = dto.monthlyReminderDay
            loan.monthlyInstalmentPaise = dto.monthlyInstalmentPaise
            loan.installmentCount = dto.installmentCount ?? 0
            context.insert(loan)
            return loan
        }

        // Then the records that point at them.
        for dto in file.expenses {
            let expense = Expense(
                title: dto.title, amount: Money.amount(fromPaise: dto.amountPaise),
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .cash,
                bankName: dto.bankName, cardLastFour: dto.cardLastFour,
                category: ExpenseCategory(rawValue: dto.categoryRaw) ?? .other, date: dto.date
            )
            expense.paidAt = dto.paidAt
            expense.customCategory = dto.customCategory ?? ""
            context.insert(expense)
            if let index = dto.emi, emis.indices.contains(index) { expense.emi = emis[index] }
            if let index = dto.policy, policies.indices.contains(index) { expense.insurancePolicy = policies[index] }
        }

        for dto in file.repayments {
            let repayment = LoanRepayment(
                amount: Money.amount(fromPaise: dto.amountPaise), date: dto.date, note: dto.note,
                bankName: dto.bankName
            )
            context.insert(repayment)
            if let index = dto.loan, loans.indices.contains(index) { repayment.loan = loans[index] }
        }

        for dto in file.holdings {
            let holding = Holding(
                name: dto.name, kind: HoldingKind(rawValue: dto.kindRaw) ?? .otherAsset, platform: dto.platform,
                investedAmount: Money.amount(fromPaise: dto.investedAmountPaise),
                currentValue: Money.amount(fromPaise: dto.currentValuePaise), quantity: dto.quantity,
                interestRate: dto.interestRate, maturityDate: dto.maturityDate, note: dto.note,
                updatedAt: dto.updatedAt
            )
            context.insert(holding)
        }

        for dto in file.cards {
            let card = PaymentCard(
                bankName: dto.bankName, cardLastFour: dto.cardLastFour, cardholderName: dto.cardholderName,
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .creditCard,
                nickname: dto.nickname, createdAt: dto.createdAt
            )
            card.accountUID = dto.accountUID ?? ""
            context.insert(card)
        }

        let transfers = file.transfers.map { dto -> Transfer in
            let transfer = Transfer(amount: Money.amount(fromPaise: dto.amountPaise), date: dto.date, note: dto.note)
            context.insert(transfer)
            if let index = dto.from, accounts.indices.contains(index) { transfer.fromAccount = accounts[index] }
            if let index = dto.to, accounts.indices.contains(index) { transfer.toAccount = accounts[index] }
            return transfer
        }

        for dto in file.monthlySavings {
            let record = MonthlySavings(
                month: dto.month, leftover: Money.amount(fromPaise: dto.leftoverPaise),
                applied: Money.amount(fromPaise: dto.appliedPaise), bankName: dto.bankName
            )
            record.createdAt = dto.createdAt
            context.insert(record)
            if let index = dto.transfer, transfers.indices.contains(index) { record.transfer = transfers[index] }
        }

        for dto in file.goals ?? [] {
            let goal = Goal(
                name: dto.name, target: Money.amount(fromPaise: dto.targetPaise),
                monthly: Money.amount(fromPaise: dto.monthlyPaise), targetDate: dto.targetDate,
                startMonth: dto.startMonth
            )
            goal.lastProcessedMonth = dto.lastProcessedMonth
            goal.completedAt = dto.completedAt
            goal.createdAt = dto.createdAt
            context.insert(goal)
            for item in dto.contributions {
                let contribution = GoalContribution(
                    amount: Money.amount(fromPaise: item.amountPaise), date: item.date, note: item.note, month: item.month
                )
                context.insert(contribution)
                goal.contributions.append(contribution)
            }
        }

        for dto in file.recurringExpenses ?? [] {
            let plan = RecurringExpense(
                title: dto.title, amount: Money.amount(fromPaise: dto.amountPaise),
                category: ExpenseCategory(rawValue: dto.categoryRaw) ?? .other,
                accountType: AccountType(rawValue: dto.accountTypeRaw) ?? .cash,
                bankName: dto.bankName, cardLastFour: dto.cardLastFour, dayOfMonth: dto.dayOfMonth,
                startDate: dto.startDate, endDate: dto.endDate
            )
            plan.isActive = dto.isActive
            plan.lastPostedMonth = dto.lastPostedMonth
            plan.createdAt = dto.createdAt
            context.insert(plan)
        }

        for dto in file.categoryBudgets ?? [] {
            let budget = CategoryBudget(
                category: ExpenseCategory(rawValue: dto.categoryRaw) ?? .other,
                limit: Money.amount(fromPaise: dto.limitPaise)
            )
            budget.createdAt = dto.createdAt
            context.insert(budget)
        }

        // The restored instalments and premiums already carry their paid status. Without this, the one-time
        // upgrade that treats past-dated items as paid would run again and mark unpaid ones as paid.
        UserDefaults.standard.set(true, forKey: EMI.paidStateMigrationKey)
        UserDefaults.standard.set(true, forKey: InsurancePolicy.paidStateMigrationKey)

        try context.save()
    }

    private static func deleteEverything(in context: ModelContext) throws {
        func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
            for item in try context.fetch(FetchDescriptor<T>()) {
                context.delete(item)
            }
        }
        // Records that point at others first.
        try deleteAll(CategoryBudget.self)
        try deleteAll(RecurringExpense.self)
        try deleteAll(GoalContribution.self)
        try deleteAll(Goal.self)
        try deleteAll(MonthlySavings.self)
        try deleteAll(Transfer.self)
        try deleteAll(LoanRepayment.self)
        try deleteAll(Expense.self)
        try deleteAll(Loan.self)
        try deleteAll(EMI.self)
        try deleteAll(InsurancePolicy.self)
        try deleteAll(Account.self)
        try deleteAll(Income.self)
        try deleteAll(Holding.self)
        try deleteAll(PaymentCard.self)
    }
}
