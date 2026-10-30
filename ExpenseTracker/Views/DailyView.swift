//
//  DailyView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Shows every transaction (expenses, income, and loans) for a single selected day (today by default).
struct DailyView: View {
    @Binding var selectedDate: Date

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                .padding(.horizontal)
                .padding(.vertical, 8)
            DailyTransactionList(day: selectedDate)
        }
    }
}

private enum DailyItem: Identifiable {
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
        case .income(let i): return i.date
        case .expense(let e): return e.date
        case .loanLent(let loan): return loan.date
        case .loanRepayment(let repayment): return repayment.date
        case .cardPayment(let transfer): return transfer.date
        }
    }
}

/// The list is a separate view so its `@Query` can be rebuilt whenever the day changes.
private struct DailyTransactionList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loansLent: [Loan]
    /// Payments received from friends today, in full or in part.
    @Query private var repayments: [LoanRepayment]

    private var cashRepayments: [LoanRepayment] { repayments.filter(\.isCashInflow) }

    /// Transfers made today. Only card bill payments are listed.
    @Query private var transfers: [Transfer]

    private var cardPayments: [Transfer] { transfers.filter(\.isCardBillPayment) }

    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?
    @State private var editingLoan: Loan?

    init(day: Date) {
        let range = Calendar.current.dayRange(containing: day)
        let start = range.lowerBound
        let end = range.upperBound
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
        // Loans on your card only appear under Loans, not in the daily view.
        let cashMethod = LoanMethod.cash.rawValue
        _loansLent = Query(
            filter: #Predicate<Loan> { $0.date >= start && $0.date < end && $0.methodRaw == cashMethod },
            sort: \Loan.date,
            order: .reverse
        )
        _repayments = Query(
            filter: #Predicate<LoanRepayment> { $0.date >= start && $0.date < end },
            sort: \LoanRepayment.date,
            order: .reverse
        )
        _transfers = Query(
            filter: #Predicate<Transfer> { $0.date >= start && $0.date < end },
            sort: \Transfer.date,
            order: .reverse
        )
    }

    private var transactions: [DailyItem] {
        var items: [DailyItem] = []
        items.append(contentsOf: incomes.map { DailyItem.income($0) })
        items.append(contentsOf: expenses.map { DailyItem.expense($0) })
        items.append(contentsOf: loansLent.map { DailyItem.loanLent($0) })
        items.append(contentsOf: cashRepayments.map { DailyItem.loanRepayment($0) })
        items.append(contentsOf: cardPayments.map { DailyItem.cardPayment($0) })
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            summarySection

            if !transactions.isEmpty {
                transactionsSection
            }
        }
        .overlay {
            if expenses.isEmpty && incomes.isEmpty && loansLent.isEmpty && cashRepayments.isEmpty && cardPayments.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Tap + to add an expense, income or loan for this day.")
                )
            }
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
        }
        .sheet(item: $editingIncome) { income in
            IncomeFormView(income: income)
        }
        .sheet(item: $editingLoan) { loan in
            LoanFormView(loan: loan)
        }
    }

    private var summarySection: some View {
        let income = incomes.totalAmount
        let spent = expenses.spentAmount
        let pending = expenses.plannedAmount
        let loanedOut = loansLent.totalAmount
        let cashRepaid = cashRepayments.totalAmount
        let net = income - spent - loanedOut + cashRepaid

        return Section {
            if income > 0 {
                LabeledContent("Income") {
                    Text(income, format: .rupees)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }

            LabeledContent("Total Spent") {
                Text(spent, format: .rupees)
                    .font((income > 0 || loanedOut > 0) ? .body.weight(.semibold) : .title3.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if pending > 0 {
                LabeledContent("Pending EMIs & Premiums") {
                    Text(pending, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }

            if loanedOut > 0 {
                LabeledContent("Loaned Out") {
                    Text(loanedOut, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }

            if cashRepaid > 0 {
                LabeledContent("Cash Loans Repaid") {
                    Text(cashRepaid, format: .rupees)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }

            if income > 0 || loanedOut > 0 || cashRepaid > 0 {
                LabeledContent("Net for Day") {
                    Text(net > 0 ? "+\(net.formatted(.rupees))" : net.formatted(.rupees))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(net >= 0 ? .green : .red)
                }
            }
        }
    }

    private var transactionsSection: some View {
        Section("Transactions") {
            ForEach(transactions) { item in
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
                    Button {
                        editingLoan = loan
                    } label: {
                        DailyLoanRow(loan: loan)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .leading) {
                        if loan.outstandingAmount > 0 {
                            Button("Mark Repaid", systemImage: "checkmark.circle") {
                                loan.markFullyRepaid(in: modelContext)
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(loan)
                        }
                    }

                case .loanRepayment(let repayment):
                    Button {
                        editingLoan = repayment.loan
                    } label: {
                        CashLoanRepaymentRow(repayment: repayment)
                    }
                    .tint(.primary)
                    .swipeActions {
                        // Removing a payment makes the loan outstanding again.
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            if let loan = repayment.loan {
                                loan.removeRepayment(repayment, in: modelContext)
                            } else {
                                modelContext.delete(repayment)
                            }
                        }
                    }

                case .cardPayment(let transfer):
                    CardPaymentRow(transfer: transfer)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(transfer)
                            }
                        }
                }
            }
        }
    }
}

private struct DailyLoanRow: View {
    let loan: Loan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(.orange.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(loan.friendName)
                        .font(.body.weight(.medium))
                    if loan.isRepaid {
                        Text("Repaid")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12), in: .capsule)
                    } else if loan.isPartlyRepaid {
                        Text("\(loan.repaidAmount.formatted(.rupees)) back")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: .capsule)
                    }
                }
                Text(loan.cardDescription ?? loan.method.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(loan.amount, format: .rupees)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(loan.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CashLoanRepaymentRow: View {
    let repayment: LoanRepayment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cash repayment from \(repayment.loan?.friendName ?? "friend")")
                    .font(.body.weight(.medium))
                Text(repayment.note.isEmpty ? "Loan repayment" : repayment.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("+\(repayment.amount.formatted(.rupees))")
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 2)
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
                Text(income.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DailyView(selectedDate: .constant(.now))
    }
    .modelContainer(for: [Expense.self, Income.self, Loan.self], inMemory: true)
}
