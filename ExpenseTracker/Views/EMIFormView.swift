//
//  EMIFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding an EMI plan, or editing an existing one when `emi` is non-nil.
/// Saving (re)generates one expense per month on the billing day until the end month.
struct EMIFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let emi: EMI?

    @State private var name: String
    @State private var monthlyAmount: Decimal?
    @State private var accountType: AccountType
    @State private var bankName: String
    @State private var cardLastFour: String
    @State private var billingDay: Int
    @State private var startMonth: Date
    @State private var endMonth: Date
    @State private var annualRate: Double?
    @State private var includedInNetWorth: Bool
    /// How many past instalments are already paid. `nil` until changed, then it follows the schedule.
    @State private var paidOverride: Int?
    /// A credit card saved for the first time by this EMI, while its bill day is being asked.
    @State private var cardAskingBillDay: PaymentCard?

    init(emi: EMI? = nil) {
        self.emi = emi
        let now = Date.now
        _name = State(initialValue: emi?.name ?? "")
        _monthlyAmount = State(initialValue: emi?.monthlyAmount)
        _accountType = State(initialValue: emi?.accountType ?? .creditCard)
        _bankName = State(initialValue: emi?.bankName ?? "")
        _cardLastFour = State(initialValue: emi?.cardLastFour ?? "")
        _billingDay = State(initialValue: emi?.billingDay ?? Calendar.current.component(.day, from: now))
        _startMonth = State(initialValue: emi?.startMonth ?? now)
        // Default to a 12-month plan.
        _endMonth = State(initialValue: emi?.endMonth ?? Calendar.current.date(byAdding: .month, value: 11, to: now) ?? now)
        _annualRate = State(initialValue: emi?.annualInterestRate)
        _includedInNetWorth = State(initialValue: emi?.includedInNetWorth ?? true)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var installmentCount: Int {
        EMI.installmentDates(billingDay: billingDay, startMonth: startMonth, endMonth: endMonth).count
    }

    /// Instalments dated before today in the schedule.
    private var pastCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return EMI.installmentDates(billingDay: billingDay, startMonth: startMonth, endMonth: endMonth)
            .filter { $0 < startOfToday }
            .count
    }

    /// Past instalments to record as already paid. Defaults to all of them.
    private var alreadyPaid: Int {
        min(paidOverride ?? pastCount, pastCount)
    }

    private var isValid: Bool {
        guard let monthlyAmount else { return false }
        return monthlyAmount > 0 && !trimmedName.isEmpty && installmentCount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("EMI") {
                    TextField("Name (e.g. iPhone 17 Pro)", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Monthly EMI", value: $monthlyAmount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                }

                Section("Card") {
                    Picker("Account Type", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    // Your saved cards and banks, one tap away, as on the expense form.
                    PaymentSourceFields(accountType: accountType, bankName: $bankName, cardLastFour: $cardLastFour)
                }

                Section {
                    Picker("Billing Day", selection: $billingDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    MonthStepperRow(title: "First EMI", month: $startMonth)
                    MonthStepperRow(title: "Last EMI", month: $endMonth)
                    if emi == nil, pastCount > 0 {
                        Stepper(
                            "Already paid: \(alreadyPaid) of \(pastCount)",
                            value: Binding(get: { alreadyPaid }, set: { paidOverride = $0 }),
                            in: 0...pastCount
                        )
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    if emi == nil, pastCount > 0 {
                        Text("\(pastCount) instalment\(pastCount == 1 ? " is" : "s are") dated before today. The earliest ones you mark as paid are recorded as paid. Any you leave unpaid show as overdue until you record them.")
                    }
                    if installmentCount > 0, let monthlyAmount, monthlyAmount > 0 {
                        Text("\(installmentCount) instalments · Total \(Decimal(installmentCount) * monthlyAmount, format: .rupees)")
                    } else if installmentCount == 0 {
                        Text("The last EMI month must be on or after the first.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Interest rate % p.a. (optional)", value: $annualRate, format: .number)
                        .keyboardType(.decimalPad)
                    Toggle("Count in Net Worth Debt", isOn: $includedInNetWorth)
                } header: {
                    Text("Net Worth")
                } footer: {
                    Text("With an interest rate, net worth counts only the principal you still owe, not future interest. Turn the toggle off if you also track this loan under Investments, so it isn't counted twice.")
                }

                if let emi {
                    Section {
                        Button("Delete EMI", role: .destructive) {
                            for expense in emi.installments {
                                modelContext.delete(expense)
                            }
                            modelContext.delete(emi)
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting removes all of this EMI's monthly expenses, past and future.")
                    }
                }
            }
            .navigationTitle(emi == nil ? "New EMI" : "Edit EMI")
            .navigationBarTitleDisplayMode(.inline)
            // The EMI is already saved. Once the bill day is answered or skipped, the form closes.
            .sheet(item: $cardAskingBillDay, onDismiss: { dismiss() }) { card in
                BillingCycleSheet(card: card)
            }
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
        guard let monthlyAmount, isValid else { return }

        let trimmedBank = accountType.usesBank ? BankName.normalized(bankName) : ""
        let card = accountType.usesCard ? cardLastFour : ""
        // The card is saved, and a credit card gets its account, so it shows under Accounts.
        let newCard = CardSync.saveCard(accountType: accountType, bankName: trimmedBank, lastFour: card, in: modelContext)

        let target: EMI
        if let emi {
            target = emi
            target.name = trimmedName
            target.monthlyAmount = monthlyAmount
            target.accountType = accountType
            target.bankName = trimmedBank
            target.cardLastFour = card
            target.billingDay = billingDay
            target.startMonth = startMonth
            target.endMonth = endMonth
            target.annualInterestRate = annualRate
            target.includedInNetWorth = includedInNetWorth
        } else {
            target = EMI(
                name: trimmedName,
                monthlyAmount: monthlyAmount,
                accountType: accountType,
                bankName: trimmedBank,
                cardLastFour: card,
                billingDay: billingDay,
                startMonth: startMonth,
                endMonth: endMonth
            )
            target.annualInterestRate = annualRate
            target.includedInNetWorth = includedInNetWorth
            modelContext.insert(target)
        }
        // Only a new EMI gets past instalments recorded as paid; an edited one keeps its own history.
        target.regenerateInstallments(in: modelContext, markingFirstPaid: emi == nil ? alreadyPaid : 0)
        if let newCard {
            cardAskingBillDay = newCard
        } else {
            dismiss()
        }
    }
}

/// A form row with "‹ Mar 2027 ›" buttons for choosing a month.
private struct MonthStepperRow: View {
    let title: String
    @Binding var month: Date

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Button("Previous Month", systemImage: "chevron.left") { shift(by: -1) }
                Text(month, format: .dateTime.month(.abbreviated).year())
                    .monospacedDigit()
                    .frame(minWidth: 80)
                Button("Next Month", systemImage: "chevron.right") { shift(by: 1) }
            }
            .labelStyle(.iconOnly)
            // Borderless so each button is tappable on its own inside a Form row.
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
    }

    private func shift(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = newMonth
        }
    }
}

#Preview {
    EMIFormView()
        .modelContainer(for: [Expense.self, EMI.self], inMemory: true)
}
