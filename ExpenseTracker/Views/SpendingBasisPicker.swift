//
//  SpendingBasisPicker.swift
//  ExpenseTracker
//

import SwiftUI

/// Which way the main Spent and Balance figures are worked out on Monthly and Budget.
///
/// Only the headline figures change. Categories, limits, charts and the recap always count a purchase when you
/// make it.
enum SpendingBasis: String, CaseIterable, Identifiable {
    /// What has actually left your cash: spending in cash, UPI and on a debit card, and card bills when you pay
    /// them. Credit card purchases are shown on their own line and not subtracted.
    case cash = "Cash"
    /// Every purchase counts when you make it, including on a credit card.
    case purchases = "Purchases"

    var id: String { rawValue }

    static let storageKey = "spendingBasis"
}

/// The Cash | Purchases switch at the top of the Monthly and Budget summaries.
struct SpendingBasisPicker: View {
    @Binding var basis: SpendingBasis

    var body: some View {
        Section {
            Picker("Show Spending As", selection: $basis) {
                ForEach(SpendingBasis.allCases) { basis in
                    Text(basis.rawValue).tag(basis)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(basis == .cash
                 ? "Cash: Spent is what has left your cash. A credit card purchase comes out when you pay the bill."
                 : "Purchases: Spent counts every purchase when you make it, including on a credit card.")
        }
    }
}
