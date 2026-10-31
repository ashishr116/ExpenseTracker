//
//  BillingCycleSheet.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Asks for the day a new credit card's bill is generated, shown after a card is first used on an expense.
/// The due date is taken as 18 days later unless it is set on the card.
struct BillingCycleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let card: PaymentCard

    @State private var day = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Bill Generated On", selection: $day) {
                        Text("Not Sure").tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text(BillDatesSection.ordinal(day)).tag(day)
                        }
                    }
                } header: {
                    Text(card.displayName)
                } footer: {
                    Text("The day of the month your bill is generated, as printed on your statement. The due date is taken as \(PaymentCard.defaultDueGap) days later, and you can change it in Saved Cards. It lets the card show what is billed and what is not yet billed.")
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        card.statementDay = day
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(day == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
