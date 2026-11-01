//
//  BudgetView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Auto-summarises a month's spending by account type, and by bank + card.
struct BudgetView: View {
    @Binding var month: Date
    @State private var page = BudgetPage.summary

    /// The views on this tab. Only the selected one is built, so the others cost nothing until opened.
    private enum BudgetPage: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case recap = "Recap"
        case limits = "Limits"
        case fixed = "Fixed Expenses"
        case payment = "Bank/Card"
        case chart = "Chart"
        case saved = "Saved"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthSelector(month: $month)
            // Scrolls sideways, since there are more pages than fit across in one row.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BudgetPage.allCases) { item in
                            Button {
                                page = item
                            } label: {
                                Text(item.rawValue)
                                    .font(.subheadline.weight(page == item ? .semibold : .regular))
                                    .foregroundStyle(page == item ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(page == item ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .id(item)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
                .onChange(of: page) { _, newPage in
                    withAnimation { proxy.scrollTo(newPage, anchor: .center) }
                }
            }

            switch page {
            case .summary: BudgetSummaryList(month: month)
            case .recap: BudgetRecapView(month: month)
            case .limits: BudgetLimitsView(month: month)
            case .fixed: BudgetFixedVariableView(month: month)
            case .payment: BudgetPaymentModeView(month: month)
            case .chart: BudgetCategoryChartView(month: month)
            case .saved: BudgetSavedView(month: month)
            }
        }
    }
}

private struct BudgetSummaryList: View {
    let month: Date
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loansLent: [Loan]
    @Query private var repayments: [LoanRepayment]
    /// The month's transfers, for the card bills paid.
    @Query private var transfers: [Transfer]
    @Query private var recurringPlans: [RecurringExpense]
    /// Money borrowed from friends this month, and payments back to them.
    @Query private var borrowed: [Borrowing]
    @Query private var borrowPayments: [BorrowingPayment]

    private var cashRepayments: [LoanRepayment] { repayments.filter(\.isCashInflow) }

    /// Rent and subscriptions due in this month but not yet posted as transactions.
    private var scheduledFixedExpenses: Decimal {
        recurringPlans
            .filter { $0.hasUnpostedCommitment(in: month) }
            .reduce(0) { $0 + $1.amount }
    }

    /// Cash spending kept apart from credit card spending. See `MonthCashView`.
    private var cashView: MonthCashView {
        MonthCashView(
            income: incomes.totalAmount,
            expenses: expenses,
            cardPayments: transfers,
            cashLent: loansLent.totalAmount,
            cashRepaid: cashRepayments.totalAmount,
            borrowed: borrowed.reduce(Decimal(0)) { $0 + $1.amount },
            paidBack: borrowPayments.totalAmount
        )
    }

    init(month: Date) {
        self.month = month
        let range = Calendar.current.monthRange(containing: month)
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
        // Loans on your card only appear under Loans, not in the budget.
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
        _transfers = Query(filter: #Predicate<Transfer> { $0.date >= start && $0.date < end })
        _borrowed = Query(filter: #Predicate<Borrowing> { $0.date >= start && $0.date < end })
        _borrowPayments = Query(filter: #Predicate<BorrowingPayment> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        List {
            summarySection
            incomeSourcesSection
            cashSection

            if !incomes.isEmpty || !expenses.isEmpty {
                Section("Breakdown") {
                    if !incomes.isEmpty {
                        NavigationLink {
                            BudgetIncomesView(month: month)
                        } label: {
                            HStack {
                                Label("Incomes", systemImage: "arrow.down.circle.fill")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(incomes.totalAmount, format: .rupees)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !expenses.isEmpty {
                        NavigationLink {
                            BudgetExpensesView(month: month)
                        } label: {
                            HStack {
                                Label("Expenses", systemImage: "creditcard.fill")
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(expenses.spentAmount, format: .rupees)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if expenses.isEmpty && incomes.isEmpty && loansLent.isEmpty && cashRepayments.isEmpty {
                ContentUnavailableView(
                    "Nothing to Summarise",
                    systemImage: "chart.pie",
                    description: Text("Add expenses, income or loans to see your budget plan.")
                )
            }
        }
    }

    /// Credit card purchases, card by card. Shown only in months where a credit card was used.
    @ViewBuilder
    private var cashSection: some View {
        let view = cashView
        if view.hasCardActivity, !view.cards.isEmpty {
            Section("Credit Card Spending") {
                ForEach(view.cards) { card in
                    DisclosureGroup {
                        ForEach(card.expenses) { expense in
                            ExpenseRow(expense: expense)
                        }
                    } label: {
                        LabeledContent {
                            Text(card.total, format: .rupees)
                                .fontWeight(.semibold)
                        } label: {
                            Label(card.name, systemImage: "creditcard")
                        }
                    }
                }
            }
        }
    }

    /// Where this month's income came from, source by source.
    @ViewBuilder
    private var incomeSourcesSection: some View {
        let total = incomes.totalAmount
        let bySource = Dictionary(grouping: incomes, by: \.source)
            .map { (source: $0.key, total: $0.value.totalAmount) }
            .sorted { $0.total > $1.total }
        if total > 0 {
            Section("Income Sources") {
                ForEach(bySource, id: \.source) { entry in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.total, format: .rupees)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            Text((total > 0 ? Double(truncating: (entry.total / total) as NSDecimalNumber) : 0), format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label(entry.source.rawValue, systemImage: entry.source.systemImage)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        let income = incomes.totalAmount
        let spent = expenses.spentAmount
        let pending = expenses.plannedAmount + scheduledFixedExpenses
        let loanedOut = loansLent.totalAmount
        let cashRepaid = cashRepayments.totalAmount
        // A plan should hold back money for EMIs and premiums that are still to be paid.
        let borrowedIn = borrowed.reduce(Decimal(0)) { $0 + $1.amount }
        let paidBack = borrowPayments.totalAmount
        let balance = income - spent - pending - loanedOut + cashRepaid + borrowedIn - paidBack
        // When a card was used, the main figures count what left your cash. Credit card purchases wait for the bill.
        let cash = cashView
        let usesCash = cash.hasCardActivity
        let cashSpentOut = cash.cashSpent + cash.billsPaid
        let remaining = usesCash ? cash.cashLeft - pending : balance

        return Section {
            if income > 0 {
                LabeledContent("Income") {
                    Text(income, format: .rupees)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }

            LabeledContent("Total Spent") {
                Text(usesCash ? cashSpentOut : spent, format: .rupees)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if usesCash {
                LabeledContent("Via UPI, Cash & Debit") {
                    Text(cash.cashSpent, format: .rupees)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Card Bills Paid") {
                    Text(cash.billsPaid, format: .rupees)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Credit Card Expenses") {
                    Text(cash.cardSpent, format: .rupees)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }

            let emiTotal = expenses.filter { $0.emi != nil && !$0.isPlanned }.totalAmount
            if emiTotal > 0, !usesCash {
                LabeledContent("Includes EMIs") {
                    Text(emiTotal, format: .rupees)
                        .foregroundStyle(.secondary)
                }
            }

            if scheduledFixedExpenses > 0 {
                LabeledContent("Scheduled Fixed Expenses") {
                    Text(scheduledFixedExpenses, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }

            if expenses.plannedAmount > 0 {
                LabeledContent("Pending EMIs & Premiums") {
                    Text(expenses.plannedAmount, format: .rupees)
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

            if borrowedIn > 0 {
                LabeledContent("Borrowed from Friends") {
                    Text(borrowedIn, format: .rupees)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }

            if paidBack > 0 {
                LabeledContent("Repaid to Friends") {
                    Text(paidBack, format: .rupees)
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }

            if income > 0 {
                LabeledContent(usesCash ? "Cash Left" : "Remaining Budget") {
                    Text(remaining, format: .rupees)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(remaining >= 0 ? .green : .red)
                }
            }
        }
    }
}

/// Detailed income breakdown by source and by bank.
struct BudgetIncomesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var incomes: [Income]
    @State private var editingIncome: Income?

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _incomes = Query(
            filter: #Predicate<Income> { $0.date >= start && $0.date < end },
            sort: \Income.date,
            order: .reverse
        )
    }

    private var sourceSummaries: [SourceSummary] {
        Dictionary(grouping: incomes, by: \.source)
            .map { SourceSummary(source: $0.key, total: $0.value.totalAmount, count: $0.value.count, incomes: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var bankSummaries: [BankIncomeSummary] {
        Dictionary(grouping: incomes, by: \.bankName)
            .map { BankIncomeSummary(bankName: $0.key, total: $0.value.totalAmount, count: $0.value.count, incomes: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        List {
            Section("By Source") {
                ForEach(sourceSummaries) { entry in
                    DisclosureGroup {
                        ForEach(entry.incomes) { income in
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
                        }
                    } label: {
                        HStack {
                            Image(systemName: entry.source.systemImage)
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.source.rawValue)
                                    .font(.body.weight(.medium))
                                Text("\(entry.count) txn\(entry.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.total, format: .rupees)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Section("By Bank / Account") {
                ForEach(bankSummaries) { entry in
                    DisclosureGroup {
                        ForEach(entry.incomes) { income in
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
                        }
                    } label: {
                        HStack {
                            Image(systemName: "building.columns")
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .font(.body.weight(.medium))
                                Text("\(entry.count) txn\(entry.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.total, format: .rupees)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Incomes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if incomes.isEmpty {
                ContentUnavailableView(
                    "No Incomes",
                    systemImage: "arrow.down.circle",
                    description: Text("No income recorded for this month.")
                )
            }
        }
        .sheet(item: $editingIncome) { income in
            IncomeFormView(income: income)
        }
    }
}

/// Detailed expenses breakdown by account type and by bank & card.
struct BudgetExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var monthExpenses: [Expense]
    @State private var editingExpense: Expense?

    /// Only money actually spent; unpaid EMIs and premiums are shown separately on the summary.
    private var expenses: [Expense] { monthExpenses.filter { !$0.isPlanned } }

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(
            filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
            sort: \Expense.date,
            order: .reverse
        )
    }

    /// Totals per account type, highest first.
    private var typeTotals: [(type: AccountType, total: Decimal)] {
        Dictionary(grouping: expenses, by: \.accountType)
            .map { (type: $0.key, total: $0.value.totalAmount) }
            .sorted { $0.total > $1.total }
    }

    /// Totals per (account type, bank, card), highest first.
    private var accountSummaries: [AccountSummary] {
        Dictionary(grouping: expenses) {
            AccountKey(accountType: $0.accountType, bankName: $0.bankName, cardLastFour: $0.cardLastFour)
        }
        .map { key, items in
            AccountSummary(
                accountType: key.accountType,
                bankName: key.bankName,
                cardLastFour: key.cardLastFour,
                total: items.totalAmount,
                count: items.count
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// Card-wise totals for a given account type.
    private func cardGroups(for type: AccountType) -> [CardGroup] {
        let typeExpenses = expenses.filter { $0.accountType == type }
        let grouped = Dictionary(grouping: typeExpenses) { "\($0.bankName)|\($0.cardLastFour)" }
        return grouped.map { key, items in
            let first = items[0]
            var parts: [String] = []
            if !first.bankName.isEmpty { parts.append(first.bankName) }
            if !first.cardLastFour.isEmpty { parts.append("•••• \(first.cardLastFour)") }
            let name = parts.isEmpty ? type.rawValue : parts.joined(separator: " · ")
            return CardGroup(
                id: key,
                displayName: name,
                bankName: first.bankName,
                cardLastFour: first.cardLastFour,
                total: items.totalAmount,
                count: items.count
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// Transactions matching a specific bank & card summary.
    private func expenses(for summary: AccountSummary) -> [Expense] {
        expenses.filter {
            $0.accountType == summary.accountType &&
            $0.bankName == summary.bankName &&
            $0.cardLastFour == summary.cardLastFour
        }
    }

    var body: some View {
        List {
            accountTypeSection
            bankAndCardSection
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses",
                    systemImage: "creditcard",
                    description: Text("No expenses recorded for this month.")
                )
            }
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(expense: expense)
        }
    }

    private var accountTypeSection: some View {
        Section("By Account Type") {
            ForEach(typeTotals, id: \.type) { entry in
                DisclosureGroup {
                    let cards = cardGroups(for: entry.type)
                    ForEach(cards) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.displayName)
                                    .font(.body.weight(.medium))
                                Text("\(card.count) txn\(card.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(card.total, format: .rupees)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    LabeledContent {
                        Text(entry.total, format: .rupees)
                            .foregroundStyle(.primary)
                            .fontWeight(.semibold)
                    } label: {
                        Label(entry.type.rawValue, systemImage: entry.type.systemImage)
                    }
                }
            }
        }
    }

    private var bankAndCardSection: some View {
        Section("By Bank & Card") {
            ForEach(accountSummaries) { summary in
                let txns = expenses(for: summary)
                DisclosureGroup {
                    ForEach(txns) { expense in
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
                    }
                } label: {
                    HStack {
                        Image(systemName: summary.accountType.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.accountType.rawValue)
                                .font(.body.weight(.medium))
                            Text(summary.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(summary.total, format: .rupees)
                                .fontWeight(.semibold)
                            Text("\(summary.count) txns")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// One aggregated line in the budget summary.
private struct AccountSummary: Identifiable {
    let accountType: AccountType
    let bankName: String
    let cardLastFour: String
    let total: Decimal
    let count: Int

    var id: String { "\(accountType.rawValue)|\(bankName)|\(cardLastFour)" }

    var subtitle: String {
        var parts: [String] = []
        if !bankName.isEmpty { parts.append(bankName) }
        if !cardLastFour.isEmpty { parts.append("•••• \(cardLastFour)") }
        return parts.isEmpty ? accountType.rawValue : parts.joined(separator: " · ")
    }
}

/// Grouping key for summarising expenses by account.
private struct AccountKey: Hashable {
    let accountType: AccountType
    let bankName: String
    let cardLastFour: String
}

/// Grouping card-wise totals under an account type.
private struct CardGroup: Identifiable {
    let id: String
    let displayName: String
    let bankName: String
    let cardLastFour: String
    let total: Decimal
    let count: Int
}

private struct SourceSummary: Identifiable {
    let source: IncomeSource
    let total: Decimal
    let count: Int
    let incomes: [Income]

    var id: IncomeSource { source }
}

private struct BankIncomeSummary: Identifiable {
    let bankName: String
    let total: Decimal
    let count: Int
    let incomes: [Income]

    var id: String { bankName }
    var displayName: String { bankName.isEmpty ? "Direct / Other" : bankName }
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
                Text(income.amount, format: .rupees)
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
        BudgetView(month: .constant(.now))
    }
    .modelContainer(for: [Expense.self, Income.self, Loan.self], inMemory: true)
}
