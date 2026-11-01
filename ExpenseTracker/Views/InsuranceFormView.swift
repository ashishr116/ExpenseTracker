//
//  InsuranceFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a health insurance or term plan, or editing one when `policy` is non-nil.
/// Saving (re)generates the policy's premium expenses on each debit date.
struct InsuranceFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let policy: InsurancePolicy?

    @State private var type: InsuranceType
    @State private var insurerName: String
    @State private var planName: String
    @State private var policyNumber: String
    @State private var coverAmount: Decimal?
    @State private var premiumAmount: Decimal?
    @State private var frequency: PremiumFrequency
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var firstPremiumDate: Date
    @State private var addsToExpenses: Bool
    @State private var accountType: AccountType
    @State private var bankName: String
    @State private var cardLastFour: String
    @State private var nomineeOrMembers: String
    @State private var note: String
    /// How many past premiums are already paid. `nil` until changed, then it follows the schedule.
    @State private var paidOverride: Int?

    init(policy: InsurancePolicy? = nil) {
        self.policy = policy
        let initialType = policy?.type ?? .health
        _type = State(initialValue: initialType)
        _insurerName = State(initialValue: policy?.insurerName ?? "")
        _planName = State(initialValue: policy?.planName ?? "")
        _policyNumber = State(initialValue: policy?.policyNumber ?? "")
        _coverAmount = State(initialValue: policy.flatMap { $0.coverAmount > 0 ? $0.coverAmount : nil })
        _premiumAmount = State(initialValue: policy?.premiumAmount)
        _frequency = State(initialValue: policy?.frequency ?? initialType.defaultFrequency)
        _startDate = State(initialValue: policy?.startDate ?? .now)
        // Health policies typically renew yearly.
        _endDate = State(initialValue: policy?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _firstPremiumDate = State(initialValue: policy?.firstPremiumDate ?? policy?.startDate ?? .now)
        _addsToExpenses = State(initialValue: policy?.addsToExpenses ?? true)
        _accountType = State(initialValue: policy?.accountType ?? .upi)
        _bankName = State(initialValue: policy?.bankName ?? "")
        _cardLastFour = State(initialValue: policy?.cardLastFour ?? "")
        _nomineeOrMembers = State(initialValue: policy?.nomineeOrMembers ?? "")
        _note = State(initialValue: policy?.note ?? "")
    }

    private var trimmedInsurer: String {
        insurerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        guard let premiumAmount else { return false }
        return premiumAmount > 0 && !trimmedInsurer.isEmpty && endDate > startDate
    }

    /// Number of premium debits between the first debit and the end date.
    private var premiumCount: Int {
        InsurancePolicy.premiumDates(first: firstPremiumDate, frequency: frequency, endDate: endDate).count
    }

    /// Premium debits dated before today in the schedule.
    private var pastCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return InsurancePolicy.premiumDates(first: firstPremiumDate, frequency: frequency, endDate: endDate)
            .filter { $0 < startOfToday }
            .count
    }

    /// Past premiums to record as already paid. Defaults to all of them.
    private var alreadyPaid: Int {
        min(paidOverride ?? pastCount, pastCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(InsuranceType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newType in
                        // Only switch the frequency default for new policies.
                        if policy == nil {
                            frequency = newType.defaultFrequency
                        }
                    }
                }

                Section("Policy") {
                    TextField("Insurer (e.g. \(type == .health ? "Star Health" : "HDFC Life"))", text: $insurerName)
                        .textInputAutocapitalization(.words)
                    TextField("Plan Name (optional)", text: $planName)
                        .textInputAutocapitalization(.words)
                    TextField("Policy Number (optional)", text: $policyNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("\(type.coverLabel) (optional)", value: $coverAmount, format: .rupees)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Payment Mode", selection: $frequency) {
                        ForEach(PremiumFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    TextField("Premium per payment", value: $premiumAmount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                    DatePicker("First Debit Date", selection: $firstPremiumDate, displayedComponents: .date)
                } header: {
                    Text("Premium")
                } footer: {
                    if let premiumAmount, premiumAmount > 0, frequency != .annually {
                        Text("\(premiumAmount * Decimal(frequency.paymentsPerYear), format: .rupees) per year. Debited on the same day every \(frequency == .monthly ? "month" : "period").")
                    } else {
                        Text("Later premiums are debited on the same date each period.")
                    }
                }

                Section {
                    Toggle("Add Premiums to Expenses", isOn: $addsToExpenses.animation())
                    if addsToExpenses {
                        Picker("Paid From", selection: $accountType) {
                            ForEach(AccountType.allCases) { type in
                                Label(type.rawValue, systemImage: type.systemImage)
                                    .tag(type)
                            }
                        }
                        // Your saved cards and banks, one tap away, as on the expense form.
                        PaymentSourceFields(accountType: accountType, bankName: $bankName, cardLastFour: $cardLastFour)
                    }
                    if policy == nil, addsToExpenses, pastCount > 0 {
                        Stepper(
                            "Already paid: \(alreadyPaid) of \(pastCount)",
                            value: Binding(get: { alreadyPaid }, set: { paidOverride = $0 }),
                            in: 0...pastCount
                        )
                    }
                } header: {
                    Text("Auto Expense")
                } footer: {
                    if addsToExpenses {
                        Text("\(premiumCount) premium\(premiumCount == 1 ? "" : "s") will be added to your expenses on each debit date until the policy ends.")
                        if policy == nil, pastCount > 0 {
                            Text("\(pastCount) of them \(pastCount == 1 ? "is" : "are") dated before today. The earliest ones you mark as paid are recorded as paid. Any you leave unpaid show as overdue until you record them.")
                        }
                    }
                }

                Section("Validity") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker(type.validityLabel, selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section(type == .health ? "Members Covered" : "Nominee") {
                    TextField(type == .health ? "e.g. Self, Spouse, Parents" : "Nominee name (optional)", text: $nomineeOrMembers)
                        .textInputAutocapitalization(.words)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }

                if let policy {
                    Section {
                        Button("Delete Policy", role: .destructive) {
                            policy.delete(from: modelContext)
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting also removes this policy's premium expenses.")
                    }
                }
            }
            .navigationTitle(policy == nil ? "Add Policy" : "Edit Policy")
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
        guard let premiumAmount, isValid else { return }

        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let bank = accountType.usesBank ? BankName.normalized(bankName) : ""
        let card = accountType.usesCard ? cardLastFour : ""

        let target: InsurancePolicy
        if let policy {
            target = policy
            target.type = type
            target.insurerName = trimmedInsurer
            target.planName = trim(planName)
            target.policyNumber = trim(policyNumber)
            target.coverAmount = coverAmount ?? 0
            target.premiumAmount = premiumAmount
            target.frequency = frequency
            target.startDate = startDate
            target.endDate = endDate
            target.firstPremiumDate = firstPremiumDate
            target.addsToExpenses = addsToExpenses
            target.accountType = accountType
            target.bankName = bank
            target.cardLastFour = card
            target.nomineeOrMembers = trim(nomineeOrMembers)
            target.note = trim(note)
        } else {
            target = InsurancePolicy(
                type: type,
                insurerName: trimmedInsurer,
                planName: trim(planName),
                policyNumber: trim(policyNumber),
                coverAmount: coverAmount ?? 0,
                premiumAmount: premiumAmount,
                frequency: frequency,
                startDate: startDate,
                endDate: endDate,
                nomineeOrMembers: trim(nomineeOrMembers),
                note: trim(note),
                firstPremiumDate: firstPremiumDate,
                addsToExpenses: addsToExpenses,
                accountType: accountType,
                bankName: bank,
                cardLastFour: card
            )
            modelContext.insert(target)
        }
        // Only a new policy gets past premiums recorded as paid; an edited one keeps its own history.
        target.regeneratePremiumExpenses(in: modelContext, markingFirstPaid: policy == nil ? alreadyPaid : 0)
        dismiss()
    }
}

#Preview {
    InsuranceFormView()
        .modelContainer(for: [InsurancePolicy.self, Expense.self], inMemory: true)
}
