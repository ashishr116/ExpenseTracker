//
//  BudgetInsightViews.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import Charts

private extension Decimal {
    var asDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Share of `part` in `whole` as a fraction, 0 when there is nothing to divide.
private func share(_ part: Decimal, of whole: Decimal) -> Double {
    whole > 0 ? part.asDouble / whole.asDouble : 0
}

// MARK: - Fixed and variable

/// Spending split into fixed (rent, EMIs, groceries and similar) and variable (everything else).
struct BudgetFixedVariableView: View {
    let month: Date
    @Query private var monthExpenses: [Expense]
    @Query private var monthIncomes: [Income]
    @Query private var recurringPlans: [RecurringExpense]

    init(month: Date) {
        self.month = month
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthIncomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end })
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
    }

    /// Fixed commitments include scheduled EMIs and premiums even before they are marked paid.
    private var expenses: [Expense] { monthExpenses }

    private var scheduledRecurringPlans: [RecurringExpense] {
        recurringPlans.filter { $0.hasUnpostedCommitment(in: month) }
    }

    private var scheduledRecurringTotal: Decimal {
        scheduledRecurringPlans.reduce(0) { $0 + $1.amount }
    }

    private struct CategoryTotal: Identifiable {
        let category: ExpenseCategory
        let items: [Expense]
        var id: ExpenseCategory { category }
        var total: Decimal { items.totalAmount }
    }

    private func totals(fixed: Bool) -> [CategoryTotal] {
        let matching = expenses.filter { $0.isFixedSpending == fixed }
        // EMIs and premiums sit under their own categories, so they group with Loan EMI and Insurance.
        return Dictionary(grouping: matching, by: \.category)
            .map { CategoryTotal(category: $0.key, items: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        let fixed = totals(fixed: true)
        let variable = totals(fixed: false)
        let fixedTotal = fixed.reduce(Decimal(0)) { $0 + $1.total } + scheduledRecurringTotal
        let variableTotal = variable.reduce(Decimal(0)) { $0 + $1.total }
        let whole = fixedTotal + variableTotal
        let income = monthIncomes.totalAmount

        List {
            Section {
                if income > 0 {
                    LabeledContent("Income") {
                        Text(income, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                LabeledContent("Fixed Expenses") {
                    Text(fixedTotal, format: .rupees).fontWeight(.semibold)
                }
                LabeledContent("Variable Expenses") {
                    Text(variableTotal, format: .rupees).fontWeight(.semibold)
                }
                if income > 0 {
                    LabeledContent("Left After Expenses") {
                        Text(income - whole, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(income - whole >= 0 ? Color.green : Color.red)
                    }
                    ProgressView(value: min(1, share(fixedTotal, of: income)))
                    Text("\(share(fixedTotal, of: income).formatted(.percent.precision(.fractionLength(0)))) of your income goes to fixed expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if whole > 0 {
                    ProgressView(value: share(fixedTotal, of: whole))
                    Text("\(share(fixedTotal, of: whole).formatted(.percent.precision(.fractionLength(0)))) of your spending is fixed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Fixed expenses include rent, subscriptions, scheduled EMIs and insurance premiums before payment is recorded. Everything else is variable, and is where you can cut back.")
            }

            if !scheduledRecurringPlans.isEmpty {
                Section {
                    ForEach(scheduledRecurringPlans) { plan in
                        BudgetRecurringCommitmentRow(plan: plan, month: month)
                    }
                } header: {
                    Text("Scheduled Fixed Expenses")
                } footer: {
                    Text("These are included in Fixed Expenses and Remaining Budget before their payment day. They become regular expenses automatically on the due date.")
                }
            }

            group("Fixed Expenses", fixed, total: fixedTotal, whole: whole)
            group("Variable Expenses", variable, total: variableTotal, whole: whole)
        }
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView("No Spending", systemImage: "list.bullet", description: Text("Nothing has been spent this month."))
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [CategoryTotal], total: Decimal, whole: Decimal) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { entry in
                    DisclosureGroup {
                        ForEach(entry.items) { expense in
                            ExpenseRow(expense: expense)
                        }
                    } label: {
                        HStack {
                            Label(entry.category.rawValue, systemImage: entry.category.systemImage)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(entry.total, format: .rupees).fontWeight(.semibold)
                                Text(share(entry.total, of: whole), format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(total, format: .rupees)
                }
            }
        }
    }
}

private struct BudgetRecurringCommitmentRow: View {
    let plan: RecurringExpense
    let month: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.body.weight(.medium))
                if let due = plan.dueDate(inMonth: month) {
                    Text("Due \(due.formatted(.dateTime.day().month(.abbreviated))) · \(plan.paymentDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(plan.amount, format: .rupees)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Bank and card

/// Spending split by how it was paid: bank (debit card and UPI), credit card, or cash.
struct BudgetPaymentModeView: View {
    @Query private var monthExpenses: [Expense]
    @Query private var monthIncomes: [Income]

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
        _monthIncomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end }, sort: \Income.date, order: .reverse)
    }

    /// Income received this month, bank by bank.
    private var incomeByBank: [(name: String, total: Decimal, count: Int)] {
        Dictionary(grouping: monthIncomes) { $0.bankName.isEmpty ? "No Bank Chosen" : $0.bankName }
            .map { (name: $0.key, total: $0.value.totalAmount, count: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    private enum Mode: String, CaseIterable, Identifiable {
        case bank = "Bank & UPI"
        case creditCard = "Credit Card"
        case cash = "Cash"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .bank: "building.columns"
            case .creditCard: "creditcard"
            case .cash: "banknote"
            }
        }

        init(_ type: AccountType) {
            switch type {
            case .creditCard: self = .creditCard
            case .cash: self = .cash
            case .debitCard, .upi: self = .bank
            }
        }
    }

    private var expenses: [Expense] { monthExpenses.filter { !$0.isPlanned } }

    /// One bank or card within a mode, e.g. "HDFC Bank · •••• 0214".
    private struct Source: Identifiable {
        let name: String
        let items: [Expense]
        var id: String { name }
        var total: Decimal { items.totalAmount }
    }

    private func sources(in items: [Expense], mode: Mode) -> [Source] {
        Dictionary(grouping: items) { expense -> String in
            var parts: [String] = []
            if !expense.bankName.isEmpty { parts.append(expense.bankName) }
            if !expense.cardLastFour.isEmpty { parts.append("•••• \(expense.cardLastFour)") }
            return parts.isEmpty ? mode.rawValue : parts.joined(separator: " · ")
        }
        .map { Source(name: $0.key, items: $0.value) }
        .sorted { $0.total > $1.total }
    }

    var body: some View {
        let whole = expenses.totalAmount
        let byMode = Dictionary(grouping: expenses) { Mode($0.accountType) }

        List {
            Section {
                ForEach(Mode.allCases) { mode in
                    let items = byMode[mode] ?? []
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(items.totalAmount, format: .rupees).fontWeight(.semibold)
                            Text(share(items.totalAmount, of: whole), format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                }
            } footer: {
                Text("Credit card spending is paid later with a bill payment, which is not counted again here.")
            }

            if !monthIncomes.isEmpty {
                Section {
                    LabeledContent("Total Income") {
                        Text(monthIncomes.totalAmount, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    ForEach(incomeByBank, id: \.name) { bank in
                        LabeledContent {
                            Text(bank.total, format: .rupees).fontWeight(.semibold)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(bank.name, systemImage: "building.columns")
                                Text("\(bank.count) credit\(bank.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Money In")
                }
            }

            ForEach(Mode.allCases) { mode in
                let items = byMode[mode] ?? []
                if !items.isEmpty {
                    Section(mode.rawValue) {
                        ForEach(sources(in: items, mode: mode)) { source in
                            DisclosureGroup {
                                ForEach(source.items) { expense in
                                    ExpenseRow(expense: expense)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.name).font(.body.weight(.medium))
                                        Text("\(source.items.count) txn\(source.items.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(source.total, format: .rupees).fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if expenses.isEmpty && monthIncomes.isEmpty {
                ContentUnavailableView("No Spending", systemImage: "creditcard", description: Text("Nothing has been spent this month."))
            }
        }
    }
}

// MARK: - Category chart

/// A donut chart of where the month's money went, with each category's share.
struct BudgetCategoryChartView: View {
    @Query private var monthExpenses: [Expense]
    @Query private var monthIncomes: [Income]

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
        _monthIncomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end }, sort: \Income.date, order: .reverse)
    }

    /// Income received this month, by source, biggest first.
    private var incomeBySource: [(source: IncomeSource, total: Decimal)] {
        Dictionary(grouping: monthIncomes, by: \.source)
            .map { (source: $0.key, total: $0.value.totalAmount) }
            .sorted { $0.total > $1.total }
    }

    private static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .gray]
    /// Categories beyond this many are folded into one slice so the chart stays readable.
    private static let visibleSlices = 7

    private struct Slice: Identifiable {
        let name: String
        let total: Decimal
        let color: Color
        var id: String { name }
    }

    private var slices: [Slice] {
        let spent = monthExpenses.filter { !$0.isPlanned }
        let sorted = Dictionary(grouping: spent, by: \.category)
            .map { (name: $0.key.rawValue, total: $0.value.totalAmount) }
            .sorted { $0.total > $1.total }

        var result = sorted.prefix(Self.visibleSlices).enumerated().map {
            Slice(name: $1.name, total: $1.total, color: Self.palette[$0])
        }
        let rest = sorted.dropFirst(Self.visibleSlices).reduce(Decimal(0)) { $0 + $1.total }
        if rest > 0 {
            result.append(Slice(name: "Remaining Categories", total: rest, color: Self.palette[Self.visibleSlices]))
        }
        return result
    }

    var body: some View {
        let slices = slices
        let whole = slices.reduce(Decimal(0)) { $0 + $1.total }

        let income = monthIncomes.totalAmount

        List {
            if income > 0 {
                Section {
                    LabeledContent("Income") {
                        Text(income, format: .rupees).fontWeight(.semibold).foregroundStyle(.green)
                    }
                    LabeledContent("Spent") {
                        Text(whole, format: .rupees).fontWeight(.semibold)
                    }
                    LabeledContent("Left") {
                        Text(income - whole, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(income - whole >= 0 ? Color.green : Color.red)
                    }
                }

                Section("Where Income Came From") {
                    ForEach(incomeBySource, id: \.source) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.source.systemImage)
                                .foregroundStyle(.green)
                                .frame(width: 22)
                            Text(entry.source.rawValue)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(share(entry.total, of: income), format: .percent.precision(.fractionLength(1)))
                                    .fontWeight(.semibold)
                                Text(entry.total, format: .rupees)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if whole > 0 {
                Section {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Spent", slice.total.asDouble),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(slice.color)
                    }
                    .chartBackground { _ in
                        VStack(spacing: 2) {
                            Text("Spent").font(.caption).foregroundStyle(.secondary)
                            Text(whole, format: .rupees).font(.headline)
                        }
                    }
                    .frame(height: 240)
                    .padding(.vertical, 8)
                }

                Section("Where It Went") {
                    ForEach(slices) { slice in
                        HStack(spacing: 10) {
                            Circle().fill(slice.color).frame(width: 12, height: 12)
                            Text(slice.name)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(share(slice.total, of: whole), format: .percent.precision(.fractionLength(1)))
                                    .fontWeight(.semibold)
                                Text(slice.total, format: .rupees)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if whole == 0 && income == 0 {
                ContentUnavailableView("No Spending", systemImage: "chart.pie", description: Text("Nothing has been spent this month."))
            }
        }
    }
}

// MARK: - Saved this month

/// How much of the month's income was kept.
struct BudgetSavedView: View {
    let month: Date
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loansLent: [Loan]
    @Query private var repayments: [LoanRepayment]
    @Query private var savingsRecords: [MonthlySavings]
    @Query private var goalContributions: [GoalContribution]
    @Query private var borrowed: [Borrowing]
    @Query private var borrowPayments: [BorrowingPayment]

    init(month: Date) {
        self.month = month
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _goalContributions = Query(filter: #Predicate<GoalContribution> { $0.date >= start && $0.date < end })
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end })
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end })
        let cashMethod = LoanMethod.cash.rawValue
        _loansLent = Query(filter: #Predicate<Loan> { $0.date >= start && $0.date < end && $0.methodRaw == cashMethod })
        _repayments = Query(filter: #Predicate<LoanRepayment> { $0.date >= start && $0.date < end })
        _savingsRecords = Query(filter: #Predicate<MonthlySavings> { $0.month >= start && $0.month < end })
        _borrowed = Query(filter: #Predicate<Borrowing> { $0.date >= start && $0.date < end })
        _borrowPayments = Query(filter: #Predicate<BorrowingPayment> { $0.date >= start && $0.date < end })
    }

    private var isFinished: Bool {
        Calendar.current.monthRange(containing: month).upperBound <= .now
    }

    var body: some View {
        let income = incomes.totalAmount
        let spent = expenses.spentAmount
        let pending = expenses.plannedAmount
        let lent = loansLent.totalAmount
        let repaid = repayments.filter(\.isCashInflow).totalAmount
        // Money lent leaves your account and repayments come back, so both move what you kept.
        let borrowedIn = borrowed.reduce(Decimal(0)) { $0 + $1.amount }
        let paidBack = borrowPayments.totalAmount
        let saved = income - spent - lent + repaid + borrowedIn - paidBack
        let record = savingsRecords.first

        List {
            Section {
                LabeledContent(isFinished ? "Saved This Month" : "Saved So Far") {
                    Text(saved, format: .rupees)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(saved >= 0 ? Color.green : Color.red)
                }
                if income > 0 {
                    LabeledContent("Savings Rate") {
                        Text(saved.asDouble / income.asDouble, format: .percent.precision(.fractionLength(0)))
                            .fontWeight(.semibold)
                            .foregroundStyle(saved >= 0 ? Color.green : Color.red)
                    }
                    ProgressView(value: min(max(share(saved, of: income), 0), 1))
                        .tint(saved >= 0 ? .green : .red)
                }
            } footer: {
                if income == 0 {
                    Text("Add this month's income to see your savings rate.")
                }
            }

            Section("How It Adds Up") {
                LabeledContent("Income") {
                    Text(income, format: .rupees).foregroundStyle(.green)
                }
                LabeledContent("Spent") {
                    Text(spent > 0 ? "−\(spent.formatted(.rupees))" : spent.formatted(.rupees))
                }
                if lent > 0 {
                    LabeledContent("Lent to Friends") {
                        Text("−\(lent.formatted(.rupees))").foregroundStyle(.orange)
                    }
                }
                if repaid > 0 {
                    LabeledContent("Repaid to You") {
                        Text("+\(repaid.formatted(.rupees))").foregroundStyle(.green)
                    }
                }
                if borrowedIn > 0 {
                    LabeledContent("Borrowed from Friends") {
                        Text("+\(borrowedIn.formatted(.rupees))").foregroundStyle(.green)
                    }
                }
                if paidBack > 0 {
                    LabeledContent("Repaid to Friends") {
                        Text("−\(paidBack.formatted(.rupees))").foregroundStyle(.orange)
                    }
                }
                LabeledContent("Saved") {
                    Text(saved, format: .rupees).fontWeight(.semibold)
                }
            }

            if pending > 0 {
                Section {
                    LabeledContent("EMIs & Premiums Still to Pay") {
                        Text(pending, format: .rupees).foregroundStyle(.orange)
                    }
                    LabeledContent("Left After Paying Them") {
                        Text(saved - pending, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(saved - pending >= 0 ? Color.green : Color.red)
                    }
                } footer: {
                    Text("These are due this month but not paid yet, so they are not in the saved figure above.")
                }
            }

            if goalContributions.totalAmount > 0 {
                Section {
                    LabeledContent("Set Aside for Goals") {
                        Text(goalContributions.totalAmount, format: .rupees)
                            .foregroundStyle(.green)
                    }
                } footer: {
                    Text("Part of what you saved, marked for your goals. It is still in your savings.")
                }
            }

            if let record, record.applied > 0 {
                Section {
                    LabeledContent("Moved to \(record.bankName)") {
                        Text(record.applied, format: .rupees).foregroundStyle(.green)
                    }
                } footer: {
                    Text("This month's leftover was added to your savings at month end.")
                }
            }
        }
        .overlay {
            if income == 0 && spent == 0 && lent == 0 {
                ContentUnavailableView("Nothing Yet", systemImage: "banknote", description: Text("Add income or expenses to see what you saved."))
            }
        }
    }
}

// MARK: - Limits

/// Monthly limits per category, with how much of each is used so far this month.
struct BudgetLimitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryBudget.createdAt) private var budgets: [CategoryBudget]
    @Query private var monthExpenses: [Expense]

    @State private var isAdding = false
    @State private var editing: CategoryBudget?

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end })
    }

    private func spent(in category: ExpenseCategory) -> Decimal {
        monthExpenses.filter { !$0.isPlanned && $0.category == category }.totalAmount
    }

    var body: some View {
        let totalLimit = budgets.reduce(Decimal(0)) { $0 + $1.limit }
        let totalSpent = budgets.reduce(Decimal(0)) { $0 + spent(in: $1.category) }

        List {
            if budgets.isEmpty {
                Section {
                    Label("Set a limit for a category", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.headline)
                    Text("Say the most you want to spend each month on something, such as food or shopping. You'll see how much is used, and get a notice at 80% and again if you go over.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    LabeledContent("Limits Add Up To") {
                        Text(totalLimit, format: .rupees).fontWeight(.semibold)
                    }
                    LabeledContent("Spent in Those") {
                        Text(totalSpent, format: .rupees).fontWeight(.semibold)
                    }
                    ProgressView(value: min(1, max(0, totalLimit > 0 ? (totalSpent / totalLimit).asDouble : 0)))
                        .tint(totalSpent > totalLimit ? .red : .accentColor)
                }

                Section("Categories") {
                    ForEach(budgets) { budget in
                        Button {
                            editing = budget
                        } label: {
                            LimitRow(budget: budget, spent: spent(in: budget.category))
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(budget)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Add a Limit", systemImage: "plus.circle") { isAdding = true }
                    .disabled(budgets.count >= ExpenseCategory.allCases.count)
            }
        }
        .sheet(isPresented: $isAdding) {
            BudgetLimitFormView()
        }
        .sheet(item: $editing) { budget in
            BudgetLimitFormView(budget: budget)
        }
    }
}

private struct LimitRow: View {
    let budget: CategoryBudget
    let spent: Decimal

    private var level: CategoryBudget.Level { budget.level(spent: spent) }

    private var color: Color {
        switch level {
        case .fine: .green
        case .near: .orange
        case .over: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(budget.category.rawValue, systemImage: budget.category.systemImage)
                    .font(.body.weight(.medium))
                Spacer()
                Text(share(spent, of: budget.limit), format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            ProgressView(value: min(1, share(spent, of: budget.limit)))
                .tint(color)
            HStack {
                Text("\(spent.formatted(.rupees)) of \(budget.limit.formatted(.rupees))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if spent > budget.limit {
                    Text("\((spent - budget.limit).formatted(.rupees)) over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("\((budget.limit - spent).formatted(.rupees)) left")
                        .font(.caption)
                        .foregroundStyle(level == .near ? Color.orange : Color.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Recap

/// A short summary of the month: what you spent and kept, where it went, and what stood out.
struct BudgetRecapView: View {
    let month: Date

    @Query private var expenses: [Expense]
    @Query private var previousExpenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loansLent: [Loan]
    @Query private var repayments: [LoanRepayment]
    @Query private var contributions: [GoalContribution]
    @Query private var borrowed: [Borrowing]
    @Query private var borrowPayments: [BorrowingPayment]
    @Query private var budgets: [CategoryBudget]

    init(month: Date) {
        self.month = month
        let calendar = Calendar.current
        let range = calendar.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        let previousStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start

        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end })
        _previousExpenses = Query(filter: #Predicate<Expense> { $0.date >= previousStart && $0.date < start })
        _incomes = Query(filter: #Predicate<Income> { $0.date >= start && $0.date < end })
        let cashMethod = LoanMethod.cash.rawValue
        _loansLent = Query(filter: #Predicate<Loan> { $0.date >= start && $0.date < end && $0.methodRaw == cashMethod })
        _repayments = Query(filter: #Predicate<LoanRepayment> { $0.date >= start && $0.date < end })
        _contributions = Query(filter: #Predicate<GoalContribution> { $0.date >= start && $0.date < end })
        _borrowed = Query(filter: #Predicate<Borrowing> { $0.date >= start && $0.date < end })
        _borrowPayments = Query(filter: #Predicate<BorrowingPayment> { $0.date >= start && $0.date < end })
    }

    private var recap: MonthlyRecap {
        MonthlyRecap(
            month: month,
            expenses: expenses,
            previousExpenses: previousExpenses,
            incomes: incomes,
            cashLoans: loansLent,
            cashRepayments: repayments.filter(\.isCashInflow),
            budgets: budgets,
            contributions: contributions,
            borrowed: borrowed.reduce(Decimal(0)) { $0 + $1.amount },
            paidBack: borrowPayments.totalAmount
        )
    }

    var body: some View {
        let recap = recap

        List {
            if recap.hasData {
                overview(recap)
                numbers(recap)
                whereItWent(recap)
                highlights(recap)
                splits(recap)

                Section {
                    ShareLink(item: recap.shareText) {
                        Label("Share This Recap", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .overlay {
            if !recap.hasData {
                ContentUnavailableView(
                    "Nothing to Recap",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Add income or expenses for this month to see its recap.")
                )
            }
        }
    }

    // MARK: Sections

    /// One bar in the overview chart.
    private struct OverviewBar: Identifiable {
        let name: String
        let amount: Decimal
        let color: Color
        var id: String { name }
    }

    /// Income, spending, last month's spending and what was kept, drawn as bars so they can be compared at a glance.
    private func overview(_ recap: MonthlyRecap) -> some View {
        var bars = [
            OverviewBar(name: "Income", amount: recap.income, color: .green),
            OverviewBar(name: "Spent", amount: recap.spent, color: .accentColor)
        ]
        if let previous = recap.previousSpent {
            let name = recap.previousMonth.formatted(.dateTime.month(.abbreviated))
            bars.append(OverviewBar(name: "Spent in \(name)", amount: previous, color: .gray))
        }
        bars.append(OverviewBar(name: recap.isFinished ? "Kept" : "Kept so far", amount: recap.saved, color: recap.saved >= 0 ? .teal : .red))

        // Room on the right (and left, for a negative amount) for the amount written beside each bar.
        let amounts = bars.map { $0.amount.asDouble }
        let high = max(amounts.max() ?? 0, 0)
        let low = min(amounts.min() ?? 0, 0)
        let lower = low < 0 ? low * 1.5 : 0
        let upper = high * 1.4

        return Section {
            Chart(bars) { bar in
                BarMark(
                    x: .value("Amount", bar.amount.asDouble),
                    y: .value("Item", bar.name)
                )
                .foregroundStyle(bar.color)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(bar.amount, format: .rupees.precision(.fractionLength(0)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: bars.map(\.name))
            .chartXScale(domain: lower...max(upper, 1))
            .chartXAxis(.hidden)
            .frame(height: CGFloat(bars.count) * 48 + 8)
            .padding(.vertical, 6)
            // The chart is a picture, so describe it in words for VoiceOver.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recap.headline)
        } header: {
            Text(recap.isFinished ? "Your Month" : "So Far This Month")
        }
    }

    private func numbers(_ recap: MonthlyRecap) -> some View {
        Section("The Month in Numbers") {
            LabeledContent("Income") {
                Text(recap.income, format: .rupees).foregroundStyle(.green)
            }
            LabeledContent("Spent") {
                Text(recap.spent, format: .rupees).fontWeight(.semibold)
            }
            LabeledContent(recap.isFinished ? "Kept" : "Kept So Far") {
                Text(recap.saved, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(recap.saved >= 0 ? Color.green : Color.red)
            }
            if let rate = recap.savingsRate {
                LabeledContent("Savings Rate") {
                    Text(rate, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(rate >= 0 ? Color.green : Color.red)
                }
            }
            if let change = recap.spendingChange {
                LabeledContent("Spending vs Last Month") {
                    // Spending going down is good news, so it is green.
                    Text("\(change > 0 ? "+" : "")\(change.formatted(.percent.precision(.fractionLength(0))))")
                        .fontWeight(.semibold)
                        .foregroundStyle(change <= 0 ? Color.green : Color.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func whereItWent(_ recap: MonthlyRecap) -> some View {
        if !recap.topCategories.isEmpty {
            Section("Where It Went") {
                ForEach(recap.topCategories) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(item.category.rawValue, systemImage: item.category.systemImage)
                            Spacer()
                            Text(item.total, format: .rupees).fontWeight(.semibold)
                        }
                        ProgressView(value: share(item.total, of: recap.spent))
                        Text("\(share(item.total, of: recap.spent).formatted(.percent.precision(.fractionLength(0)))) of your spending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func highlights(_ recap: MonthlyRecap) -> some View {
        Section("Highlights") {
            if let biggest = recap.biggestExpense {
                LabeledContent("Biggest Expense") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(biggest.amount, format: .rupees).fontWeight(.semibold)
                        Text("\(biggest.displayTitle) · \(biggest.date.formatted(.dateTime.day().month()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let rise = recap.biggestRise {
                LabeledContent("Rose the Most") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(rise.total.formatted(.rupees))")
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Text(rise.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if recap.daysCounted > 0 {
                LabeledContent("Daily Average") {
                    Text(recap.dailyAverage, format: .rupees)
                }
                LabeledContent("Days With No Spending") {
                    Text("\(recap.noSpendDays) of \(recap.daysCounted)")
                }
            }
        }
    }

    @ViewBuilder
    private func splits(_ recap: MonthlyRecap) -> some View {
        if recap.spent > 0 || !recap.overLimit.isEmpty || recap.goalsSetAside > 0 {
            Section("Planning") {
                if recap.spent > 0 {
                    LabeledContent("Fixed Expenses") {
                        Text(recap.fixedSpent, format: .rupees)
                    }
                    LabeledContent("Variable Expenses") {
                        Text(recap.variableSpent, format: .rupees)
                    }
                }
                if !recap.overLimit.isEmpty {
                    LabeledContent("Over Their Limit") {
                        Text(recap.overLimit.map(\.rawValue).joined(separator: ", "))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if recap.goalsSetAside > 0 {
                    LabeledContent("Set Aside for Goals") {
                        Text(recap.goalsSetAside, format: .rupees).foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
