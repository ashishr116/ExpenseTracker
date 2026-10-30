//
//  SalaryPlanView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// The salary fields, shared by the first-launch setup and the Monthly Salary screen.
struct SalaryPlanFields: View {
    @Binding var amount: Decimal?
    @Binding var day: Int
    @Binding var bankName: String
    /// Banks from your accounts. When there are none, the bank is typed in.
    let bankChoices: [String]

    var body: some View {
        Section {
            TextField("Monthly Take-Home Salary", value: $amount, format: .rupees)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))

            Picker("Credited On Day", selection: $day) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }

            if bankChoices.isEmpty {
                TextField("Credited To (bank name)", text: $bankName)
                    .textInputAutocapitalization(.words)
            } else {
                Picker("Credited To", selection: $bankName) {
                    ForEach(bankChoices, id: \.self) { bank in
                        Text(bank).tag(bank)
                    }
                }
            }
        } footer: {
            Text("Your salary is added to your income on this day each month, starting this month, so you don't have to enter it. If you add a salary yourself for a month, that month isn't added again. In a month without that day, it falls on the last day.")
        }
    }
}

/// Edit or switch off the automatic monthly salary.
struct SalarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    @State private var amount: Decimal?
    @State private var day = 1
    @State private var bankName = ""
    @State private var hasLoaded = false

    private var bankChoices: [String] {
        var seen = Set<String>()
        return accounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0
    }

    var body: some View {
        Form {
            SalaryPlanFields(amount: $amount, day: $day, bankName: $bankName, bankChoices: bankChoices)

            if SalaryPlanStore.current != nil {
                Section {
                    Button("Stop Adding Salary Automatically", role: .destructive) {
                        SalaryPlanStore.turnOff()
                        dismiss()
                    }
                } footer: {
                    Text("Salary already added stays in your income.")
                }
            }
        }
        .navigationTitle("Monthly Salary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount else { return }
                    SalaryPlanStore.save(SalaryPlan(amount: amount, day: day, bankName: bankName))
                    SalaryPlanStore.postDue(in: modelContext)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            if let plan = SalaryPlanStore.current {
                amount = plan.amount
                day = plan.day
                bankName = plan.bankName
            } else if let first = bankChoices.first {
                bankName = first
            }
        }
    }
}

#Preview {
    NavigationStack {
        SalarySettingsView()
    }
    .modelContainer(for: [Account.self, Income.self], inMemory: true)
}
