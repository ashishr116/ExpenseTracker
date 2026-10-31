//
//  BillDatesSection.swift
//  ExpenseTracker
//

import SwiftUI

/// The two days of the month that matter for a credit card: when the bill is generated and when it is due.
/// Used by both the Accounts form and the Saved Cards form, so the two always agree.
struct BillDatesSection: View {
    /// 0 means not set.
    @Binding var statementDay: Int
    @Binding var dueDay: Int

    var body: some View {
        Section {
            Picker("Bill Generated On", selection: $statementDay) {
                Text("Not Set").tag(0)
                ForEach(1...31, id: \.self) { day in
                    Text(Self.ordinal(day)).tag(day)
                }
            }
            Picker("Payment Due On", selection: $dueDay) {
                Text(statementDay > 0 ? "\(PaymentCard.defaultDueGap) Days After Bill" : "Not Set").tag(0)
                ForEach(1...31, id: \.self) { day in
                    Text(Self.ordinal(day)).tag(day)
                }
            }
        } header: {
            Text("Bill Dates")
        } footer: {
            Text("Both are days of the month, as printed on your statement. Add the bill day and the due date is taken as \(PaymentCard.defaultDueGap) days later, unless you choose a due day. It sets the Billed and Unbilled amounts, and you get a reminder before the due date, and so can friends who used this card. A day a month doesn't have, such as the 31st in April, means that month's last day.")
        }
    }

    /// "1st", "2nd", "3rd", "4th".
    static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
