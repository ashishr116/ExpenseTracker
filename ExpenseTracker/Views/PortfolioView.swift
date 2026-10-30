//
//  PortfolioView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Investments, savings and debts with a net-worth summary.
/// Also folds in money friends owe you (Loans) and EMIs still to be paid.
struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Holding.currentValuePaise, order: .reverse) private var holdings: [Holding]
    @Query(filter: #Predicate<Loan> { $0.repaidDate == nil }) private var outstandingLoans: [Loan]
    @Query private var emis: [EMI]

    // Everything the account balances are built from.
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var allLoans: [Loan]
    @Query private var repayments: [LoanRepayment]
    @Query private var transfers: [Transfer]

    @State private var isAddingHolding = false
    @State private var editingHolding: Holding?

    // MARK: Totals

    /// Once accounts are set up they track bank balances and card dues, so the typed-in
    /// savings and credit card due holdings are left out to avoid counting the same money twice.
    private var usesAccounts: Bool { !accounts.isEmpty }

    private var assets: [Holding] {
        holdings.filter { !$0.kind.isDebt && !(usesAccounts && $0.kind == .savings) }
    }
    private var debts: [Holding] {
        holdings.filter { $0.kind.isDebt && !(usesAccounts && $0.kind == .creditCardDue) }
    }

    private var ledger: AccountLedger {
        AccountLedger(
            accounts: accounts, expenses: expenses, incomes: incomes,
            loans: allLoans, repayments: repayments, transfers: transfers
        )
    }
    /// Bank and cash balances, worked out from your entries.
    private var accountAssets: Decimal { usesAccounts ? ledger.assetTotal : 0 }
    /// What you owe on credit cards, worked out from your entries.
    private var cardDues: Decimal { usesAccounts ? ledger.cardDuesTotal : 0 }

    /// Cash and transfer loans only. A loan on your card is owed to the card, not to you, so it is
    /// neither an asset nor a debt here.
    private var owedToYou: Decimal { outstandingLoans.filter { $0.method == .cash }.outstandingTotal }
    /// Principal still owed on EMIs counted in net worth (future interest is not debt yet).
    private var emiRemaining: Decimal {
        emis.filter(\.includedInNetWorth).reduce(0) { $0 + $1.outstandingPrincipal }
    }

    /// True when loan-type debts are tracked here and EMIs also count towards debt, which risks double counting.
    private var mayDoubleCountLoans: Bool {
        emiRemaining > 0 && debts.contains { $0.kind != .creditCardDue }
    }

    private var totalAssets: Decimal { assets.totalValue + owedToYou + accountAssets }
    private var totalDebt: Decimal { debts.totalValue + emiRemaining + cardDues }
    private var netWorth: Decimal { totalAssets - totalDebt }

    /// Holdings with an invested amount, used for overall returns.
    private var investedHoldings: [Holding] { assets.filter { $0.gain != nil } }
    private var totalInvested: Decimal { investedHoldings.reduce(0) { $0 + $1.investedAmount } }
    private var totalReturns: Decimal { investedHoldings.totalValue - totalInvested }

    /// Holdings grouped by type, in the order types are declared.
    private func grouped(_ items: [Holding]) -> [(kind: HoldingKind, items: [Holding])] {
        let groups = Dictionary(grouping: items, by: \.kind)
        return HoldingKind.allCases.compactMap { kind in
            groups[kind].map { (kind: kind, items: $0) }
        }
    }

    var body: some View {
        Group {
            if holdings.isEmpty && !usesAccounts {
                ContentUnavailableView(
                    "No Investments Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Tap + to add stocks, mutual funds, FDs, savings or debts and see your net worth. Add your bank accounts and cards under More, Accounts, so balances follow your entries.")
                )
            } else {
                List {
                    summarySection

                    if usesAccounts {
                        accountsSection
                    }

                    ForEach(grouped(assets), id: \.kind) { group in
                        holdingSection(group.kind, items: group.items)
                    }
                    ForEach(grouped(debts), id: \.kind) { group in
                        holdingSection(group.kind, items: group.items)
                    }

                    if owedToYou > 0 || emiRemaining > 0 {
                        appDataSection
                    }
                }
            }
        }
        .navigationTitle("Investments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Investment", systemImage: "plus") {
                    isAddingHolding = true
                }
            }
        }
        .sheet(isPresented: $isAddingHolding) {
            HoldingFormView()
        }
        .sheet(item: $editingHolding) { holding in
            HoldingFormView(holding: holding)
        }
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            LabeledContent("Net Worth") {
                Text(netWorth, format: .rupees)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(netWorth >= 0 ? .green : .red)
            }
            LabeledContent("Total Assets") {
                Text(totalAssets, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            LabeledContent("Total Debt") {
                Text(totalDebt, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }
            if totalInvested > 0 {
                LabeledContent("Invested") {
                    Text(totalInvested, format: .rupees)
                        .foregroundStyle(.primary)
                }
                LabeledContent("Returns") {
                    GainText(gain: totalReturns, fraction: totalReturns / totalInvested)
                }
            }
        }
    }

    /// Bank, cash and card balances from Accounts, which move with every entry.
    private var accountsSection: some View {
        Section {
            NavigationLink {
                AccountsView()
            } label: {
                LabeledContent {
                    Text(accountAssets, format: .rupees)
                        .foregroundStyle(.primary)
                } label: {
                    Label("Bank & Cash", systemImage: "building.columns")
                }
            }
            if cardDues != 0 {
                NavigationLink {
                    AccountsView()
                } label: {
                    LabeledContent {
                        Text(cardDues, format: .rupees)
                            .foregroundStyle(.red)
                    } label: {
                        Label("Credit Card Dues", systemImage: "creditcard.fill")
                    }
                }
            }
        } header: {
            Text("From Accounts")
        } footer: {
            Text("Worked out from your entries, so they update on their own. Savings accounts and credit card dues added as investments are replaced by these.")
        }
    }

    private func holdingSection(_ kind: HoldingKind, items: [Holding]) -> some View {
        Section {
            ForEach(items) { holding in
                Button {
                    editingHolding = holding
                } label: {
                    HoldingRow(holding: holding)
                }
                .tint(.primary)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        modelContext.delete(holding)
                    }
                }
            }
        } header: {
            HStack {
                Label(kind.rawValue, systemImage: kind.systemImage)
                Spacer()
                Text(items.totalValue, format: .rupees)
            }
        }
    }

    /// Amounts pulled automatically from the Loans and EMIs sections.
    private var appDataSection: some View {
        Section {
            if owedToYou > 0 {
                LabeledContent {
                    Text(owedToYou, format: .rupees)
                        .foregroundStyle(.primary)
                } label: {
                    Label("Owed to You by Friends", systemImage: "person.2.circle")
                }
            }
            if emiRemaining > 0 {
                LabeledContent {
                    Text(emiRemaining, format: .rupees)
                        .foregroundStyle(.red)
                } label: {
                    Label("EMI Principal Outstanding", systemImage: "calendar.badge.clock")
                }
            }
        } header: {
            Text("From Loans & EMIs")
        } footer: {
            Text(mayDoubleCountLoans
                 ? "Included automatically: cash you lent to friends counts as an asset (loans on your card are left out), and the principal left on EMIs counts as debt. You also track loans above, so if one is also an EMI, turn off \"Count in Net Worth Debt\" on that EMI to avoid counting it twice."
                 : "Included automatically: cash you lent to friends counts as an asset (loans on your card are left out), and the principal left on EMIs counts as debt.")
        }
    }
}

// MARK: - Rows

private struct HoldingRow: View {
    let holding: Holding

    /// e.g. "Groww · 12 units" or "SBI · 7.1% · Matures 12 Mar 2027"
    private var subtitle: String {
        var parts: [String] = []
        if !holding.platform.isEmpty { parts.append(holding.platform) }
        if let quantity = holding.quantity {
            parts.append("\(quantity.formatted(.number)) units")
        }
        if let rate = holding.interestRate {
            parts.append("\(rate.formatted(.number))%")
        }
        if let maturity = holding.maturityDate {
            parts.append("Matures \(maturity.formatted(.dateTime.day().month().year()))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(holding.currentValue, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(holding.kind.isDebt ? .red : .primary)
                if let gain = holding.gain, let fraction = holding.gainFraction {
                    GainText(gain: gain, fraction: fraction)
                        .font(.caption)
                } else {
                    Text("Updated \(holding.updatedAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// "+₹1,200 (+8.5%)" in green, or a red loss.
private struct GainText: View {
    let gain: Decimal
    let fraction: Decimal

    var body: some View {
        Text("\(gain >= 0 ? "+" : "")\(gain, format: .rupees) (\(fraction, format: .percent.precision(.fractionLength(1))))")
            .foregroundStyle(gain >= 0 ? .green : .red)
    }
}

#Preview("Sample Portfolio") {
    let container = try! ModelContainer(
        for: Holding.self, Loan.self, EMI.self, Expense.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(Holding(name: "Reliance Industries", kind: .stock, platform: "Groww", investedAmount: 25000, currentValue: 28400, quantity: 10))
    context.insert(Holding(name: "Tata Motors", kind: .stock, platform: "Groww", investedAmount: 15000, currentValue: 13200, quantity: 20))
    context.insert(Holding(name: "Parag Parikh Flexi Cap", kind: .mutualFund, platform: "Groww", investedAmount: 60000, currentValue: 71500, quantity: 812.4))
    context.insert(Holding(name: "SBI FD", kind: .fixedDeposit, platform: "SBI", investedAmount: 100000, currentValue: 100000, interestRate: 7.1, maturityDate: .now.addingTimeInterval(86400 * 300)))
    context.insert(Holding(name: "HDFC Savings", kind: .savings, platform: "HDFC Bank", currentValue: 42000))
    context.insert(Holding(name: "HDFC Credit Card", kind: .creditCardDue, platform: "HDFC Bank", currentValue: 18500))
    context.insert(Loan(amount: 5000, friendName: "Rahul"))

    return NavigationStack {
        PortfolioView()
    }
    .modelContainer(container)
}
