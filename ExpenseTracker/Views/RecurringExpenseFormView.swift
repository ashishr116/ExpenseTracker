//
//  RecurringExpenseFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a monthly payment, or editing one when `plan` is non-nil.
struct RecurringExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: RecurringExpense?

    @State private var title: String
    @State private var amount: Decimal?
    @State private var category: ExpenseCategory
    @State private var day: Int
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var isActive: Bool
    @State private var accountType: AccountType
    @State private var bankName: String
    @State private var cardLastFour: String

    init(plan: RecurringExpense? = nil) {
        self.plan = plan
        _title = State(initialValue: plan?.title ?? "")
        _amount = State(initialValue: plan?.amount)
        _category = State(initialValue: plan?.category ?? .rent)
        _day = State(initialValue: plan?.dayOfMonth ?? 1)
        _startDate = State(initialValue: plan?.startDate ?? .now)
        _hasEnd = State(initialValue: plan?.endDate != nil)
        _endDate = State(initialValue: plan?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _isActive = State(initialValue: plan?.isActive ?? true)
        _accountType = State(initialValue: plan?.accountType ?? .upi)
        _bankName = State(initialValue: plan?.bankName ?? "")
        _cardLastFour = State(initialValue: plan?.cardLastFour ?? "")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBank: String { BankName.normalized(bankName) }

    private var isValid: Bool {
        guard !trimmedTitle.isEmpty, let amount, amount > 0 else { return false }
        return true
    }

    /// The first payment this plan will add, so it's clear whether anything is added right away.
    private var firstPayment: Date? {
        RecurringExpense.firstDue(day: day, startingFrom: startDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    TextField("What is it? (e.g. Rent)", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Amount each month", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }

                Section {
                    Picker("Day of the Month", selection: $day) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    DatePicker("Starts From", selection: $startDate, displayedComponents: .date)
                    Toggle("Ends on a Date", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Last Payment By", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("When")
                } footer: {
                    if let firstPayment {
                        Text(firstPayment <= .now
                             ? "First payment, \(firstPayment.formatted(.dateTime.day().month().year())), is added right away. Days after the 28th aren't offered so it works in every month."
                             : "First payment is added on \(firstPayment.formatted(.dateTime.day().month().year())). Days after the 28th aren't offered so it works in every month.")
                    }
                }

                Section {
                    Picker("Paid By", selection: $accountType.animation()) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    PaymentSourceFields(accountType: accountType, bankName: $bankName, cardLastFour: $cardLastFour)
                } header: {
                    Text("Paid From")
                } footer: {
                    if accountType != .cash {
                        Text("Use the same bank and card digits as your account so the payment lands in the right balance.")
                    }
                }

                if plan != nil {
                    Section {
                        Toggle("Active", isOn: $isActive)
                    } footer: {
                        Text("Turn off to pause. Months that pass while it's paused are not added later.")
                    }
                }
            }
            .navigationTitle(plan == nil ? "New Monthly Payment" : "Edit Monthly Payment")
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
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        let bank = accountType.usesBank ? trimmedBank : ""
        let digits = accountType.usesCard ? cardLastFour : ""
        let end: Date? = hasEnd ? endDate : nil

        if let plan {
            let wasPaused = !plan.isActive
            plan.title = trimmedTitle
            plan.amount = amount
            plan.category = category
            plan.dayOfMonth = day
            plan.startDate = startDate
            plan.endDate = end
            plan.accountType = accountType
            plan.bankName = bank
            plan.cardLastFour = digits
            plan.isActive = isActive
            // Months that passed while paused are not added when it is turned back on.
            if wasPaused, isActive {
                plan.startDate = max(startDate, Calendar.current.startOfDay(for: .now))
            }
        } else {
            modelContext.insert(RecurringExpense(
                title: trimmedTitle, amount: amount, category: category, accountType: accountType,
                bankName: bank, cardLastFour: digits, dayOfMonth: day, startDate: startDate, endDate: end
            ))
        }
        // A payment day that has already come is added now, not on the next launch.
        RecurringExpensePoster.run(in: modelContext)
        dismiss()
    }
}

#Preview {
    RecurringExpenseFormView()
        .modelContainer(for: [RecurringExpense.self, PaymentCard.self, Account.self], inMemory: true)
}
