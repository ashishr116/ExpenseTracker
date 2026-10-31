//
//  BudgetLimitFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for setting a monthly limit on a category, or changing or removing one when `budget` is non-nil.
struct BudgetLimitFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Limits already set, so each category gets only one.
    @Query private var budgets: [CategoryBudget]

    let budget: CategoryBudget?

    @State private var category: ExpenseCategory
    @State private var limit: Decimal?

    init(budget: CategoryBudget? = nil) {
        self.budget = budget
        _category = State(initialValue: budget?.category ?? .food)
        _limit = State(initialValue: budget?.limit)
    }

    /// Categories that don't have a limit yet, plus this one when editing.
    private var choices: [ExpenseCategory] {
        let taken = Set(budgets.map(\.category))
        return ExpenseCategory.allCases.filter { !taken.contains($0) || $0 == budget?.category }
    }

    private var isValid: Bool { (limit ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if budget == nil {
                        Picker("Category", selection: $category) {
                            ForEach(choices) { category in
                                Label(category.rawValue, systemImage: category.systemImage)
                                    .tag(category)
                            }
                        }
                    } else {
                        LabeledContent("Category") {
                            Label(category.rawValue, systemImage: category.systemImage)
                        }
                    }
                    TextField("Monthly limit", value: $limit, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                } footer: {
                    Text("The same limit applies every month. You'll get a notice at 80% of it, and again if you go over.")
                }

                if let budget {
                    Section {
                        Button("Remove Limit", role: .destructive) {
                            modelContext.delete(budget)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(budget == nil ? "New Limit" : "Edit Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                // The default category may already have a limit.
                if budget == nil, !choices.contains(category), let first = choices.first {
                    category = first
                }
            }
        }
    }

    private func save() {
        guard let limit, limit > 0 else { return }
        if let budget {
            budget.limit = limit
        } else {
            modelContext.insert(CategoryBudget(category: category, limit: limit))
        }
        let context = modelContext
        Task { await BudgetAlerts.check(in: context) }
        dismiss()
    }
}

#Preview {
    BudgetLimitFormView()
        .modelContainer(for: [CategoryBudget.self], inMemory: true)
}
