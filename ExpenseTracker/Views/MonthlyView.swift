//
//  MonthlyView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Shows a month's income and its expenses consolidated into per-day totals.
struct MonthlyView: View {
    @Binding var month: Date

    var body: some View {
        VStack(spacing: 0) {
            MonthSelector(month: $month)
            MonthlyExpenseList(month: month)
        }
    }
}

private enum MonthlyTransaction: Identifiable {
    case income(Income)
    case expense(Expense)
    case loanLent(Loan)
    case loanRepayment(LoanRepayment)
    /// A credit card bill payment. Shown for reference and never counted in the totals.
    case cardPayment(Transfer)

    var id: String {
        switch self {
        case .income(let income): return "income-\(income.persistentModelID)"
        case .expense(let expense): return "expense-\(expense.persistentModelID)"
        case .loanLent(let loan): return "loan-lent-\(loan.persistentModelID)"
        case .loanRepayment(let repayment): return "loan-repayment-\(repayment.persistentModelID)"
        case .cardPayment(let transfer): return "card-payment-\(transfer.persistentModelID)"
        }
    }

    var date: Date {
        switch self {
        case .income(let income): return income.date
        case .expense(let expense): return expense.date
        case .loanLent(let loan): return loan.date
        case .loanRepayment(let repayment): return repayment.date
        case .cardPayment(let transfer): return transfer.date
        }
    }
}

private struct DayGroup: Identifiable {
    let day: Date
    let items: [MonthlyTransaction]
    let totalIncome: Decimal
    let totalExpense: Decimal
    let totalLent: Decimal
    let totalRepaid: Decimal

    var id: Date { day }
    var inflow: Decimal { totalIncome + totalRepaid }
    var outflow: Decimal { totalExpense + totalLent }
    var netDiff: Decimal { inflow - outflow }
}

private struct MonthlyExpenseList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    /// Loans given out during this month.
    @Query private var loansLent: [Loan]
    /// Payments received from friends this month, in full or in part, whenever the loan was made.
    @Query private var repayments: [LoanRepayment]

    private var cashRepayments: [LoanRepayment] { repayments.filter(\.isCashInflow) }

    /// Transfers made this month. Only card bill payments are listed.
    @Query private var transfers: [Transfer]

    private var cardPayments: [Transfer] { transfers.filter(\.isCardBillPayment) }

    @State private var editingIncome: Income?
    @State private var editingExpense: Expense?
    /// Whether the credit card figures inside Balance are showing. Closed to begin with, so the summary stays short.
    @State private var isBalanceExpanded = false

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        // Loans on your card only appear under Loans, not in the monthly view.
        let cashMethod = LoanMethod.cash.rawValue
        _loansLent = Query(filter: #Predicate<Loan> { $0.date >= start && $0.date < end && $0.methodRaw == cashMethod })
        _repayments = Query(filter: #Predicate<LoanRepayment> { $0.date >= start && $0.date < end })
        _transfers = Query(filter: #Predicate<Transfer> { $0.date >= start && $0.date < end })
        _expenses = Query(
            filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
            sort: \Expense.date,
            order: .reverse
        )
        _incomes = Query(
            filter: #Predicate<Income> { $0.date >= start && $0.date < end },
            sort: \Income.date,
            order: .reverse
        )
    }

    /// Unified income and expense transactions grouped by day, most recent day first.
    private var dayGroups: [DayGroup] {
        var txns: [MonthlyTransaction] = []
        txns.append(contentsOf: incomes.map { MonthlyTransaction.income($0) })
        txns.append(contentsOf: expenses.map { MonthlyTransaction.expense($0) })
        txns.append(contentsOf: loansLent.map { MonthlyTransaction.loanLent($0) })
        txns.append(contentsOf: cashRepayments.map { MonthlyTransaction.loanRepayment($0) })
        txns.append(contentsOf: cardPayments.map { MonthlyTransaction.cardPayment($0) })

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: txns) { calendar.startOfDay(for: $0.date) }

        return grouped.map { day, dayTxns in
            let sortedItems = dayTxns.sorted { $0.date > $1.date }
            var dayIncome: Decimal = 0
            var dayExpense: Decimal = 0
            var dayLent: Decimal = 0
            var dayRepaid: Decimal = 0
            for item in dayTxns {
                switch item {
                case .income(let inc): dayIncome += inc.amount
                case .expense(let exp): if !exp.isPlanned { dayExpense += exp.amount }
                case .loanLent(let loan): dayLent += loan.amount
                case .loanRepayment(let repayment): dayRepaid += repayment.amount
                case .cardPayment: break   // a transfer, not spending: left out of every total
                }
            }
            return DayGroup(
                day: day,
                items: sortedItems,
                totalIncome: dayIncome,
                totalExpense: dayExpense,
                totalLent: dayLent,
                totalRepaid: dayRepaid
            )
        }
        .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if expenses.isEmpty && incomes.isEmpty && loansLent.isEmpty && cashRepayments.isEmpty && cardPayments.isEmpty {
                ContentUnavailableView(
                    "Nothing This Month",
                    systemImage: "calendar",
                    description: Text("Tap + to add your salary, an expense or a loan.")
                )
            } else {
                list
            }
        }
        .sheet(item: $editingIncome) { income in
            IncomeFormView(income: income)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
        }
    }

    private var list: some View {
        List {
            summarySection

            if !dayGroups.isEmpty {
                Section("Transactions") {
                    ForEach(dayGroups) { entry in
                        DisclosureGroup {
                            ForEach(entry.items) { item in
                                switch item {
                                case .income(let income):
                                    Button {
                                        editingIncome = income
                                    } label: {
                                        IncomeRow(income: income)
                                    }
                                    .tint(.primary)
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            modelContext.delete(income)
                                        }
                                    }

                                case .expense(let expense):
                                    Button {
                                        editingExpense = expense
                                    } label: {
                                        ExpenseRow(expense: expense)
                                    }
                                    .tint(.primary)
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            modelContext.delete(expense)
                                        }
                                    }

                                case .loanLent(let loan):
                                    LoanRow(loan: loan, showsFriend: true)

                                case .loanRepayment(let repayment):
                                    MonthlyCashLoanRepaymentRow(repayment: repayment)

                                case .cardPayment(let transfer):
                                    CardPaymentRow(transfer: transfer)
                                        .swipeActions {
                                            Button("Delete", systemImage: "trash", role: .destructive) {
                                                modelContext.delete(transfer)
                                            }
                                        }
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.day, format: .dateTime.weekday(.abbreviated).day().month())
                                        .font(.body.weight(.medium))
                                    Text("In: \(entry.inflow.formatted(.rupees)) · Out: \(entry.outflow.formatted(.rupees))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                let diff = entry.netDiff
                                Text(diff > 0 ? "+\(diff.formatted(.rupees))" : diff.formatted(.rupees))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(diff > 0 ? .green : (diff < 0 ? .primary : .secondary))
                            }
                        }
                    }
                }
            }
        }
    }

    /// A line under Spent, showing one way the money was paid.
    private func splitRow(_ title: String, _ amount: Decimal, color: Color) -> some View {
        LabeledContent {
            Text(amount, format: .rupees)
                .foregroundStyle(color)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.leading, 16)
    }

    /// One line of the sum behind Cash Left.
    private func workingRow(_ title: String, _ amount: Decimal) -> some View {
        LabeledContent {
            Text(amount, format: .rupees)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    /// Why Balance and Cash Left differ: card spending counts as spent when you buy, and as cash only when you pay.
    private func gapExplanation(cardSpent: Decimal, billsPaid: Decimal) -> String {
        let gap = cardSpent - billsPaid
        if gap > 0 {
            return "Balance is \(gap.formatted(.rupees)) lower than Cash Left because that much of this month's card spending isn't paid yet."
        } else if gap < 0 {
            return "Balance is \((-gap).formatted(.rupees)) higher than Cash Left because you paid card bills from earlier months."
        }
        return "Balance and Cash Left match: the card spending this month has been paid."
    }

    private func balanceRow(_ balance: Decimal) -> some View {
        LabeledContent("Balance") {
            Text(balance, format: .rupees)
                .font(.title3.weight(.bold))
                .foregroundStyle(balance >= 0 ? .green : .red)
        }
    }

    private var summarySection: some View {
        let income = incomes.totalAmount
        let spent = expenses.spentAmount
        let pending = expenses.plannedAmount
        let lent = loansLent.totalAmount
        let repaid = cashRepayments.totalAmount
        // Money lent leaves your account this month; repayments come back in.
        let balance = income - spent - lent + repaid
        // Credit card spending isn't taken from cash until the bill is paid. Shown only when a card was used.
        let cash = MonthCashView(
            income: income, expenses: expenses, cardPayments: transfers, cashLent: lent, cashRepaid: repaid
        )

        return Section {
            LabeledContent("Income") {
                Text(income, format: .rupees)
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
            }
            LabeledContent("Spent") {
                Text(spent, format: .rupees)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
            // How the spending was paid for. Only when a credit card was used, since otherwise it is all one kind.
            if cash.cardSpent > 0 {
                splitRow("Via Credit Card", cash.cardSpent, color: .orange)
                splitRow("Via UPI, Cash & Debit", cash.cashSpent, color: .primary)
            }
            if pending > 0 {
                LabeledContent("Pending EMIs & Premiums") {
                    Text(pending, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }
            if lent > 0 {
                LabeledContent("Lent to Friends") {
                    Text(lent, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }
            if repaid > 0 {
                LabeledContent("Repaid to You") {
                    Text(repaid, format: .rupees)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }
            if cash.hasCardActivity {
                // Cash Left and the sum behind it sit inside Balance, and open when it is tapped.
                DisclosureGroup(isExpanded: $isBalanceExpanded) {
                    LabeledContent("Cash Left") {
                        Text(cash.cashLeft, format: .rupees)
                            .font(.body.weight(.bold))
                            .foregroundStyle(cash.cashLeft >= 0 ? .green : .red)
                    }
                    workingRow("Income", income)
                    workingRow("− Spent via UPI, Cash & Debit", cash.cashSpent)
                    workingRow("− Card Bills Paid", cash.billsPaid)
                    if lent > 0 { workingRow("− Lent to Friends", lent) }
                    if repaid > 0 { workingRow("+ Repaid to You", repaid) }
                    Text(gapExplanation(cardSpent: cash.cardSpent, billsPaid: cash.billsPaid))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    balanceRow(balance)
                }
            } else {
                balanceRow(balance)
            }
            if pending > 0 {
                LabeledContent("Left After Pending") {
                    Text(balance - pending, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(balance - pending >= 0 ? .green : .red)
                }
            }
            LabeledContent(
                "Transactions",
                value: expenses.count + incomes.count + loansLent.count + cashRepayments.count,
                format: .number
            )
        }
    }
}

private struct MonthlyCashLoanRepaymentRow: View {
    let repayment: LoanRepayment

    var body: some View {
        LabeledContent("Cash repayment from \(repayment.loan?.friendName ?? "friend")") {
            Text("+\(repayment.amount.formatted(.rupees))")
                .foregroundStyle(.green)
                .fontWeight(.semibold)
        }
    }
}

private struct IncomeRow: View {
    let income: Income

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: income.source.systemImage)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(income.displayTitle)
                    .font(.body.weight(.medium))
                Text(income.bankName.isEmpty ? income.source.rawValue : income.bankName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(income.amount.formatted(.rupees))")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                Text(income.date, format: .dateTime.day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        MonthlyView(month: .constant(.now))
    }
    .modelContainer(for: [Expense.self, Income.self, Loan.self], inMemory: true)
}
