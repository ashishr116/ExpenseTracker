//
//  IncomeFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding income (e.g. salary), or editing an existing entry when `income` is non-nil.
struct IncomeFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let income: Income?

    @State private var amount: Decimal?
    @State private var source: IncomeSource
    @State private var note: String
    @State private var bankName: String
    @State private var date: Date

    /// - Parameter defaultDate: Date used for new entries, so income added while
    ///   viewing a past month lands in that month.
    init(income: Income? = nil, defaultDate: Date = .now) {
        self.income = income
        _amount = State(initialValue: income?.amount)
        _source = State(initialValue: income?.source ?? .salary)
        _note = State(initialValue: income?.note ?? "")
        _bankName = State(initialValue: income?.bankName ?? "")
        _date = State(initialValue: income?.date ?? defaultDate)
    }

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Income") {
                    TextField("Amount", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Picker("Source", selection: $source) {
                        ForEach(IncomeSource.allCases) { source in
                            Label(source.rawValue, systemImage: source.systemImage)
                                .tag(source)
                        }
                    }
                    TextField("Note (optional)", text: $note)
                }

                Section("Credited To") {
                    TextField("Bank Name (optional)", text: $bankName)
                        .textInputAutocapitalization(.words)

                    popularBankChips
                }

                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if let income {
                    Section {
                        Button("Delete Income", role: .destructive) {
                            modelContext.delete(income)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(income == nil ? "Add Income" : "Edit Income")
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
        guard let amount, amount > 0 else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBank = BankName.normalized(bankName)

        if let income {
            income.amount = amount
            income.source = source
            income.note = trimmedNote
            income.bankName = trimmedBank
            income.date = date
        } else {
            modelContext.insert(
                Income(amount: amount, source: source, note: trimmedNote, bankName: trimmedBank, date: date)
            )
        }
        dismiss()
    }

    private var popularBankChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popular Banks")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PopularBank.names, id: \.self) { bank in
                        let isSelected = bankName.caseInsensitiveCompare(bank) == .orderedSame
                        Button {
                            bankName = bank
                        } label: {
                            Text(BankName.display(bank))
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? Color.accentColor : Color(.secondarySystemFill),
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

#Preview {
    IncomeFormView()
        .modelContainer(for: Income.self, inMemory: true)
}
