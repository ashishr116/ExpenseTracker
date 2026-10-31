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
    @Query private var monthExpenses: [Expense]

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
    }

    private var expenses: [Expense] { monthExpenses.filter { !$0.isPlanned } }

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
        let fixedTotal = fixed.reduce(Decimal(0)) { $0 + $1.total }
        let variableTotal = variable.reduce(Decimal(0)) { $0 + $1.total }
        let whole = fixedTotal + variableTotal

        List {
            Section {
                LabeledContent("Fixed") {
                    Text(fixedTotal, format: .rupees).fontWeight(.semibold)
                }
                LabeledContent("Variable") {
                    Text(variableTotal, format: .rupees).fontWeight(.semibold)
                }
                if whole > 0 {
                    ProgressView(value: share(fixedTotal, of: whole))
                    Text("\(share(fixedTotal, of: whole).formatted(.percent.precision(.fractionLength(0)))) of your spending is fixed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Fixed is rent, EMIs, insurance, groceries, maid, bills and subscriptions. Everything else is variable, and is where you can cut back.")
            }

            group("Fixed Spending", fixed, total: fixedTotal, whole: whole)
            group("Variable Spending", variable, total: variableTotal, whole: whole)
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

// MARK: - Bank and card

/// Spending split by how it was paid: bank (debit card and UPI), credit card, or cash.
struct BudgetPaymentModeView: View {
    @Query private var monthExpenses: [Expense]

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
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
            if expenses.isEmpty {
                ContentUnavailableView("No Spending", systemImage: "creditcard", description: Text("Nothing has been spent this month."))
            }
        }
    }
}

// MARK: - Category chart

/// A donut chart of where the month's money went, with each category's share.
struct BudgetCategoryChartView: View {
    @Query private var monthExpenses: [Expense]

    init(month: Date) {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end }, sort: \Expense.date, order: .reverse)
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

        List {
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
            if whole == 0 {
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
        let saved = income - spent - lent + repaid
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
