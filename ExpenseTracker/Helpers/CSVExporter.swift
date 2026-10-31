//
//  CSVExporter.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import UIKit

/// Writes each list in the app to its own CSV file, ready to open in Numbers, Excel or Google Sheets.
///
/// Amounts are plain numbers in rupees, dates read like 2026-10-30 14:05, and text starting with = + - or @
/// gets a leading apostrophe so a spreadsheet can't treat it as a formula. Full card numbers and CVV are
/// never exported.
enum CSVExporter {
    // MARK: Cell formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func date(_ value: Date?) -> String {
        value.map { dateFormatter.string(from: $0) } ?? ""
    }

    /// 1234.5 becomes "1234.50", with no grouping so spreadsheets read it as a number.
    private static func money(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }

    /// Text from the user. A leading formula character is neutralised.
    private static func text(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        return "'" + value
    }

    private struct Table {
        let fileName: String
        let header: [String]
        var rows: [[String]] = []

        /// Wraps a cell in quotes when it holds a comma, quote or line break.
        private nonisolated static func escape(_ cell: String) -> String {
            guard cell.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return cell }
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        var contents: String {
            // The byte order mark lets Excel read the rupee sign and other characters correctly.
            let lines = ([header] + rows).map { $0.map(Table.escape).joined(separator: ",") }
            return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        }
    }

    // MARK: Export

    /// Builds every table and writes it to a fresh temporary folder. Returns the files created.
    static func makeFiles(from context: ModelContext) throws -> [URL] {
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>())
        }

        let accounts = try all(Account.self)
        let expenses = try all(Expense.self).sorted { $0.date < $1.date }
        let incomes = try all(Income.self).sorted { $0.date < $1.date }
        let loans = try all(Loan.self).sorted { $0.date < $1.date }
        let goals = try all(Goal.self).sorted { $0.createdAt < $1.createdAt }
        let repayments = try all(LoanRepayment.self).sorted { $0.date < $1.date }
        let transfers = try all(Transfer.self).sorted { $0.date < $1.date }
        let ledger = AccountLedger(
            accounts: accounts, expenses: expenses, incomes: incomes,
            loans: loans, repayments: repayments, transfers: transfers
        )

        var tables: [Table] = []

        var expenseTable = Table(fileName: "expenses.csv", header: [
            "Date", "Title", "Category", "Amount", "Payment Type", "Bank", "Card Last 4",
            "Status", "Paid On", "Part Of"
        ])
        for expense in expenses {
            let status: String
            if expense.emi != nil || expense.insurancePolicy != nil {
                status = expense.paidAt == nil ? "Unpaid" : "Paid"
            } else {
                status = ""
            }
            expenseTable.rows.append([
                date(expense.date), text(expense.title), text(expense.categoryName), money(expense.amount),
                expense.accountTypeRaw, text(expense.bankName), expense.cardLastFour,
                status, date(expense.paidAt),
                text(expense.emi?.name ?? expense.insurancePolicy?.title ?? "")
            ])
        }
        tables.append(expenseTable)

        var incomeTable = Table(fileName: "income.csv", header: ["Date", "Source", "Note", "Amount", "Bank"])
        for income in incomes {
            incomeTable.rows.append([
                date(income.date), income.sourceRaw, text(income.note), money(income.amount), text(income.bankName)
            ])
        }
        tables.append(incomeTable)

        var loanTable = Table(fileName: "loans.csv", header: [
            "Date", "Friend", "Note", "Amount", "Repaid", "Still Owed", "Type", "Bank", "Card Last 4",
            "Fully Repaid On", "Phone", "Instalments", "Instalment Amount"
        ])
        for loan in loans {
            loanTable.rows.append([
                date(loan.date), text(loan.friendName), text(loan.note), money(loan.amount),
                money(loan.repaidAmount), money(loan.outstandingAmount), loan.methodRaw,
                text(loan.bankName), loan.cardLastFour, date(loan.repaidDate), text(loan.friendPhone),
                loan.installmentCount > 0 ? String(loan.installmentCount) : "",
                loan.isInstalmentLoan ? money(loan.monthlyInstalment ?? 0) : ""
            ])
        }
        tables.append(loanTable)

        var goalTable = Table(fileName: "goals.csv", header: [
            "Name", "Target", "Set Aside", "Monthly Amount", "Start Month", "Finish By", "Bought On"
        ])
        for goal in goals {
            goalTable.rows.append([
                text(goal.name), money(goal.target), money(goal.saved), money(goal.monthly),
                date(goal.startMonth), date(goal.targetDate), date(goal.completedAt)
            ])
        }
        tables.append(goalTable)

        var repaymentTable = Table(fileName: "loan_repayments.csv", header: [
            "Date", "Friend", "Amount", "Received In", "Note"
        ])
        for repayment in repayments {
            repaymentTable.rows.append([
                date(repayment.date), text(repayment.loan?.friendName ?? ""), money(repayment.amount),
                repayment.bankName.isEmpty ? "Cash" : text(repayment.bankName), text(repayment.note)
            ])
        }
        tables.append(repaymentTable)

        var emiTable = Table(fileName: "emis.csv", header: [
            "Name", "Monthly Amount", "Payment Type", "Bank", "Card Last 4", "Billing Day",
            "First Month", "Last Month", "Interest Rate %", "Instalments", "Paid", "Counted In Net Worth"
        ])
        for emi in try all(EMI.self).sorted(by: { $0.name < $1.name }) {
            emiTable.rows.append([
                text(emi.name), money(emi.monthlyAmount), emi.accountTypeRaw, text(emi.bankName),
                emi.cardLastFour, String(emi.billingDay), date(emi.startMonth), date(emi.endMonth),
                number(emi.annualInterestRate), String(emi.totalCount), String(emi.paidCount),
                yesNo(emi.includedInNetWorth)
            ])
        }
        tables.append(emiTable)

        var policyTable = Table(fileName: "insurance_policies.csv", header: [
            "Insurer", "Plan", "Type", "Policy Number", "Cover", "Premium", "Frequency", "Start",
            "End", "Members Or Nominee", "Note"
        ])
        for policy in try all(InsurancePolicy.self).sorted(by: { $0.insurerName < $1.insurerName }) {
            policyTable.rows.append([
                text(policy.insurerName), text(policy.planName), policy.typeRaw, text(policy.policyNumber),
                money(policy.coverAmount), money(policy.premiumAmount), policy.frequencyRaw,
                date(policy.startDate), date(policy.endDate), text(policy.nomineeOrMembers), text(policy.note)
            ])
        }
        tables.append(policyTable)

        var holdingTable = Table(fileName: "investments_and_debts.csv", header: [
            "Name", "Type", "Held With", "Invested", "Current Value", "Units", "Interest Rate %",
            "Matures", "Note", "Updated"
        ])
        for holding in try all(Holding.self).sorted(by: { $0.name < $1.name }) {
            holdingTable.rows.append([
                text(holding.name), holding.kindRaw, text(holding.platform), money(holding.investedAmount),
                money(holding.currentValue), number(holding.quantity), number(holding.interestRate),
                date(holding.maturityDate), text(holding.note), date(holding.updatedAt)
            ])
        }
        tables.append(holdingTable)

        var accountTable = Table(fileName: "accounts.csv", header: [
            "Name", "Type", "Bank", "Card Last 4", "Opening Balance", "Opening Date", "Current Balance", "Closed"
        ])
        for account in accounts.sorted(by: { $0.createdAt < $1.createdAt }) {
            accountTable.rows.append([
                text(account.displayName), account.kindRaw, text(account.bankName), account.cardLastFour,
                money(account.openingBalance), date(account.openingDate), money(ledger.balance(of: account)),
                yesNo(account.isArchived)
            ])
        }
        tables.append(accountTable)

        var transferTable = Table(fileName: "transfers.csv", header: ["Date", "From", "To", "Amount", "Note"])
        for transfer in transfers {
            transferTable.rows.append([
                date(transfer.date), text(transfer.fromAccount?.displayName ?? "Outside"),
                text(transfer.toAccount?.displayName ?? "Outside"), money(transfer.amount), text(transfer.note)
            ])
        }
        tables.append(transferTable)

        var savingsTable = Table(fileName: "monthly_savings.csv", header: [
            "Month", "Leftover", "Moved To Savings", "Account"
        ])
        for record in try all(MonthlySavings.self).sorted(by: { $0.month < $1.month }) {
            savingsTable.rows.append([
                date(record.month), money(record.leftover), money(record.applied), text(record.bankName)
            ])
        }
        tables.append(savingsTable)

        // Saved cards: names and last four digits only.
        var cardTable = Table(fileName: "saved_cards.csv", header: ["Bank", "Type", "Last 4", "Nickname"])
        for card in try all(PaymentCard.self).sorted(by: { $0.createdAt < $1.createdAt }) {
            cardTable.rows.append([text(card.bankName), card.accountTypeRaw, card.cardLastFour, text(card.nickname)])
        }
        tables.append(cardTable)

        // A fresh folder each time, named for the moment of export.
        let stamp = Date.now.fileNameStamp
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExpenseTracker-\(stamp)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return try tables.map { table in
            let url = folder.appendingPathComponent(table.fileName)
            try table.contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }
}

/// Opens the system share sheet over whatever is on screen, so the files can be saved to Files or iCloud Drive.
@MainActor
enum SharePresenter {
    static func present(urls: [URL]) {
        guard let presenter = ContactPickerPresenter.topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        // On iPad the sheet needs somewhere to anchor.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
        )
        sheet.popoverPresentationController?.permittedArrowDirections = []
        presenter.present(sheet, animated: true)
    }
}
