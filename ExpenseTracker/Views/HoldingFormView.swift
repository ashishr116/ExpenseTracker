//
//  HoldingFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding an investment, savings balance or debt, or editing one when `holding` is non-nil.
/// The fields shown adapt to the selected type (e.g. units for stocks, maturity for FDs).
struct HoldingFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// All holdings, used to suggest platforms/banks you've used before.
    @Query private var allHoldings: [Holding]

    let holding: Holding?

    @State private var kind: HoldingKind
    @State private var name: String
    @State private var platform: String
    @State private var investedAmount: Decimal?
    @State private var currentValue: Decimal?
    @State private var quantity: Double?
    @State private var interestRate: Double?
    @State private var hasMaturity: Bool
    @State private var maturityDate: Date
    @State private var note: String

    init(holding: Holding? = nil) {
        self.holding = holding
        _kind = State(initialValue: holding?.kind ?? .stock)
        _name = State(initialValue: holding?.name ?? "")
        _platform = State(initialValue: holding?.platform ?? "")
        _investedAmount = State(initialValue: holding.flatMap { $0.investedAmount > 0 ? $0.investedAmount : nil })
        _currentValue = State(initialValue: holding?.currentValue)
        _quantity = State(initialValue: holding?.quantity)
        _interestRate = State(initialValue: holding?.interestRate)
        _hasMaturity = State(initialValue: holding?.maturityDate != nil)
        _maturityDate = State(
            initialValue: holding?.maturityDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        )
        _note = State(initialValue: holding?.note ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Falls back to the invested amount when no current value is entered (e.g. a new FD).
    private var finalValue: Decimal {
        currentValue ?? (kind.tracksInvested ? investedAmount : nil) ?? 0
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && finalValue > 0
    }

    /// Suggested platforms: common ones for this type plus any you've used before.
    private var platformSuggestions: [String] {
        let previous = allHoldings
            .filter { $0.kind.isMarketLinked == kind.isMarketLinked && $0.kind.isDebt == kind.isDebt }
            .map(\.platform)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (kind.suggestedPlatforms + previous)
            .filter { seen.insert($0.lowercased()).inserted }
            .filter { $0.caseInsensitiveCompare(platform) != .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind.animation()) {
                        Section("Investments & Savings") {
                            ForEach(HoldingKind.assetKinds) { kind in
                                Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                        Section("Debt") {
                            ForEach(HoldingKind.debtKinds) { kind in
                                Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                    }
                    TextField(kind.namePlaceholder, text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(kind.platformLabel, text: $platform)
                        .textInputAutocapitalization(.words)
                    if !platformSuggestions.isEmpty {
                        platformChips
                    }
                }

                Section {
                    if kind.tracksQuantity {
                        TextField("Units / Shares (optional)", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    if kind.tracksInvested {
                        TextField(kind.investedLabel, value: $investedAmount, format: .rupees)
                            .keyboardType(.decimalPad)
                    }
                    TextField(kind.valueLabel, value: $currentValue, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                    if kind.tracksInterest {
                        TextField("Interest Rate % p.a. (optional)", value: $interestRate, format: .number)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if kind.tracksInvested {
                        Text("Leave \(kind.valueLabel) empty to use the \(kind.investedLabel.lowercased()). Update it whenever you check your app or bank.")
                    }
                }

                if kind.tracksMaturity {
                    Section("Maturity") {
                        Toggle("Has Maturity Date", isOn: $hasMaturity.animation())
                        if hasMaturity {
                            DatePicker("Matures On", selection: $maturityDate, displayedComponents: .date)
                        }
                    }
                }

                Section("Note") {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }

                if let holding {
                    Section {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(holding)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(holding == nil ? (kind.isDebt ? "Add Debt" : "Add Investment") : "Edit")
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

    /// Tap-to-fill chips for platforms/banks.
    private var platformChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(platformSuggestions, id: \.self) { name in
                    Button(name) { platform = name }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
    }

    private func save() {
        guard isValid else { return }

        // Drop values that don't apply to the selected type.
        let invested = kind.tracksInvested ? (investedAmount ?? 0) : 0
        let units = kind.tracksQuantity ? quantity : nil
        let rate = kind.tracksInterest ? interestRate : nil
        let maturity = kind.tracksMaturity && hasMaturity ? maturityDate : nil
        let trimmedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let holding {
            holding.kind = kind
            holding.name = trimmedName
            holding.platform = trimmedPlatform
            holding.investedAmount = invested
            holding.currentValue = finalValue
            holding.quantity = units
            holding.interestRate = rate
            holding.maturityDate = maturity
            holding.note = trimmedNote
            holding.updatedAt = .now
        } else {
            modelContext.insert(
                Holding(
                    name: trimmedName,
                    kind: kind,
                    platform: trimmedPlatform,
                    investedAmount: invested,
                    currentValue: finalValue,
                    quantity: units,
                    interestRate: rate,
                    maturityDate: maturity,
                    note: trimmedNote
                )
            )
        }
        dismiss()
    }
}

#Preview {
    HoldingFormView()
        .modelContainer(for: Holding.self, inMemory: true)
}
