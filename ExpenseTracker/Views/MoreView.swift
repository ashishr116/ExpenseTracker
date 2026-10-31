//
//  MoreView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// The "More" tab: entry points to Investments, Insurance, Loans, EMIs and Saved Cards.
struct MoreView: View {
    @Query(filter: #Predicate<Loan> { $0.repaidDate == nil })
    private var outstandingLoans: [Loan]
    @Query private var borrowings: [Borrowing]
    @Query private var emis: [EMI]
    @Query private var savedCards: [PaymentCard]
    @Query private var monthlySavings: [MonthlySavings]
    @Query private var policies: [InsurancePolicy]
    @Query private var goals: [Goal]
    @Query private var recurringPlans: [RecurringExpense]
    @AppStorage(PaymentDetails.upiKey) private var upiID = ""

    private var activeGoals: [Goal] { goals.filter { !$0.isCompleted } }

    /// EMIs that are due today or overdue.
    private var emisNeedingAttention: Int {
        emis.reduce(0) { $0 + $1.overdueInstallments().count + $1.dueTodayInstallments().count }
    }

    /// Premiums that are due today or overdue.
    private var premiumsNeedingAttention: Int {
        policies.reduce(0) { $0 + $1.overduePremiums().count + $1.dueTodayPremiums().count }
    }

    private var monthlyEMITotal: Decimal {
        emis.filter(\.isActive).reduce(0) { $0 + $1.monthlyAmount }
    }

    var body: some View {
        List {
            NavigationLink {
                AccountsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accounts")
                        Text("Bank, cash and card balances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "building.columns")
                }
            }

            NavigationLink {
                SalarySettingsView()
            } label: {
                LabeledContent {
                    if let plan = SalaryPlanStore.current {
                        Text(plan.amount, format: .rupees)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly Salary")
                            Text("Added to your income each month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "indianrupeesign.arrow.circlepath")
                    }
                }
            }

            NavigationLink {
                PortfolioView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Investments & Net Worth")
                        Text("Stocks, funds, FDs, savings and debt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
            }

            NavigationLink {
                MonthlySavingsView()
            } label: {
                LabeledContent {
                    if !monthlySavings.isEmpty {
                        Text(monthlySavings.reduce(0) { $0 + $1.applied }, format: .rupees)
                            .foregroundStyle(.green)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly Savings")
                            Text("Leftover moved to savings each month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "banknote")
                    }
                }
            }

            NavigationLink {
                RecurringExpensesView()
            } label: {
                LabeledContent {
                    if !recurringPlans.isEmpty {
                        Text(recurringPlans.monthlyTotal, format: .rupees)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recurring Expenses")
                            Text("Rent, maid and subscriptions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }

            NavigationLink {
                GoalsView()
            } label: {
                LabeledContent {
                    if !activeGoals.isEmpty {
                        Text(activeGoals.reduce(Decimal(0)) { $0 + $1.saved }, format: .rupees)
                            .foregroundStyle(.green)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Goals")
                            Text("Save up for something you want to buy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "target")
                    }
                }
            }

            NavigationLink {
                InsuranceView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Insurance")
                        if premiumsNeedingAttention > 0 {
                            Text("\(premiumsNeedingAttention) premium\(premiumsNeedingAttention == 1 ? "" : "s") due or overdue")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        } else {
                            Text("Health insurance and term plans")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "cross.case")
                }
            }

            NavigationLink {
                LoansView()
            } label: {
                LabeledContent {
                    Text(outstandingLoans.outstandingTotal, format: .rupees)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loans")
                            Text("Owed to you by friends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.circle")
                    }
                }
            }

            NavigationLink {
                BorrowedView()
            } label: {
                LabeledContent {
                    Text(borrowings.filter { !$0.isRepaid }.outstandingTotal, format: .rupees)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Borrowed")
                            Text("Money you owe friends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.slash")
                    }
                }
            }

            NavigationLink {
                EMIsView()
            } label: {
                LabeledContent {
                    Text(monthlyEMITotal, format: .rupees)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EMIs")
                            if emisNeedingAttention > 0 {
                                Text("\(emisNeedingAttention) due or overdue")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            } else {
                                Text("Per month")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
            }

            NavigationLink {
                PaymentDetailsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Payment Details")
                        // Shows the UPI ID once it is set, and what the screen is for until then.
                        Text(upiID.isEmpty ? "Your UPI ID, added to reminders" : upiID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "indianrupeesign.bank.building")
                }
            }

            NavigationLink {
                CardsView()
            } label: {
                LabeledContent {
                    if !savedCards.isEmpty {
                        Text("\(savedCards.count)")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saved Cards")
                            Text("Credit and debit cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "creditcard.fill")
                    }
                }
            }

            // Kept apart from the money screens above.
            Section {
                NavigationLink {
                    DataBackupView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup & Export")
                            Text("CSV files and iCloud backup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("More")
    }
}

#Preview {
    NavigationStack {
        MoreView()
    }
    .modelContainer(for: [Expense.self, Loan.self, EMI.self, PaymentCard.self, MonthlySavings.self], inMemory: true)
}
