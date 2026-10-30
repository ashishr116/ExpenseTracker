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
        moveCardSecretsToKeychain(in: context)
        try? context.save()
    }

    /// Moves full card details from the database into the Keychain, then removes Keychain items whose
    /// card no longer exists. Cards that were already moved are left alone.
    private static func moveCardSecretsToKeychain(in context: ModelContext) {
        // If the cards can't be read, do nothing: tidying up from a failed read would delete every item.
        guard let cards = try? context.fetch(FetchDescriptor<PaymentCard>()) else { return }
        cards.forEach { $0.moveSecretsToKeychain() }
        CardVault.purge(keeping: Set(cards.map(\.vaultID).filter { !$0.isEmpty }))
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
