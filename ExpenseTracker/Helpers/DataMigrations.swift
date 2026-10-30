//
//  DataMigrations.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// One-off upgrades of data saved by earlier versions. Safe to run on every launch.
enum DataMigrations {
    @MainActor
    static func run(in context: ModelContext) {
        migrateLegacyMoney(in: context)
        migrateRepaidLoans(in: context)
        EMI.migratePaidStateIfNeeded(in: context)
        InsurancePolicy.migratePaidStateIfNeeded(in: context)
        try? context.save()
    }

    /// A loan marked repaid before part payments existed gets one repayment for its full amount,
    /// dated on its repaid date, so totals based on repayments include it.
    private static func migrateRepaidLoans(in context: ModelContext) {
        let repaidLoans = (try? context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { $0.repaidDate != nil }))) ?? []
        for loan in repaidLoans where loan.repayments.isEmpty {
            let repayment = LoanRepayment(amount: loan.amount, date: loan.repaidDate ?? loan.date)
            context.insert(repayment)
            loan.repayments.append(repayment)
        }
    }

    /// Copies old floating-point amounts into the exact paise fields, so sorting and totals
    /// work on old rows too. Only rows still holding a zero paise value are fetched.
    private static func migrateLegacyMoney(in context: ModelContext) {
        (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.amountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
        (try? context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.amountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
        (try? context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { $0.amountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
        (try? context.fetch(FetchDescriptor<EMI>(predicate: #Predicate { $0.monthlyAmountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
        (try? context.fetch(FetchDescriptor<Holding>(predicate: #Predicate { $0.currentValuePaise == 0 || $0.investedAmountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
        (try? context.fetch(FetchDescriptor<InsurancePolicy>(predicate: #Predicate { $0.premiumAmountPaise == 0 || $0.coverAmountPaise == 0 })))?
            .forEach { $0.migrateLegacyMoney() }
    }
}
