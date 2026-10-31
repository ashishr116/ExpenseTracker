//
//  ContentView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedDay = Date.now
    @State private var selectedMonth = Date.now
    @State private var selectedBudgetMonth = Date.now

    @Query private var accounts: [Account]
    @State private var router = NotificationRouter.shared
    @Query private var emis: [EMI]
    @Query private var policies: [InsurancePolicy]

    /// EMIs and premiums that are due today or overdue, shown as a badge on the More tab.
    private var attentionCount: Int {
        emis.reduce(0) { $0 + $1.overdueInstallments().count + $1.dueTodayInstallments().count }
            + policies.reduce(0) { $0 + $1.overduePremiums().count + $1.dueTodayPremiums().count }
    }

    var body: some View {
        TabView {
            NavigationStack {
                DailyView(selectedDate: $selectedDay)
                    .navigationTitle("Today")
                    .addEntryToolbar(defaultDate: selectedDay)
            }
            .tabItem {
                Label("Daily", systemImage: "calendar.day.timeline.left")
            }

            NavigationStack {
                MonthlyView(month: $selectedMonth)
                    .navigationTitle("Monthly")
                    .addEntryToolbar(defaultDate: selectedMonth)
            }
            .tabItem {
                Label("Monthly", systemImage: "calendar")
            }

            NavigationStack {
                BudgetView(month: $selectedBudgetMonth)
                    .navigationTitle("Budget Plan")
                    .addEntryToolbar(defaultDate: selectedBudgetMonth)
            }
            .tabItem {
                Label("Budget", systemImage: "chart.pie")
            }

            NavigationStack {
                MoreView()
                    .navigationTitle("More")
            }
            .tabItem {
                Label("More", systemImage: "ellipsis")
            }
            .badge(attentionCount)
        }
        // A tapped card bill reminder opens that card.
        .sheet(item: Binding(
            get: { router.cardUID.flatMap { uid in accounts.first { $0.uid == uid } } },
            set: { if $0 == nil { router.cardUID = nil } }
        )) { account in
            NavigationStack {
                AccountDetailView(account: account)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { router.cardUID = nil }
                        }
                    }
            }
        }
    }
}

// MARK: - Add Expense / Income / Loan toolbar

/// Which add-entry sheet is currently presented from the + menu.
private enum AddSheet: Identifiable {
    case expense, income, loan

    var id: Self { self }
}

/// Adds the "+" toolbar menu (Expense / Income / Loan) and its sheets to a tab's root view.
private struct AddEntryToolbar: ViewModifier {
    let defaultDate: Date
    @State private var addSheet: AddSheet?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Icon-only "+" in the toolbar; tapping it shows the dropdown.
                    Menu {
                        Button("Expense", systemImage: "minus.circle") {
                            addSheet = .expense
                        }
                        Button("Income", systemImage: "plus.circle") {
                            addSheet = .income
                        }
                        Button("Loan", systemImage: "person.2") {
                            addSheet = .loan
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
                }
            }
            .sheet(item: $addSheet) { sheet in
                switch sheet {
                case .expense: ExpenseFormView(defaultDate: defaultDate)
                case .income: IncomeFormView(defaultDate: defaultDate)
                case .loan: LoanFormView(defaultDate: defaultDate)
                }
            }
    }
}

extension View {
    /// Adds the "+" menu for adding an expense, income, or loan.
    func addEntryToolbar(defaultDate: Date) -> some View {
        modifier(AddEntryToolbar(defaultDate: defaultDate))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Expense.self, Income.self, Loan.self, EMI.self, Holding.self, InsurancePolicy.self], inMemory: true)
}
