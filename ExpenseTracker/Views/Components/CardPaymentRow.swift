//
//  CardPaymentRow.swift
//  ExpenseTracker
//

import SwiftUI

/// A credit card bill payment, shown in the Daily and Monthly lists so you can see when the cash left your bank.
/// It is a transfer, not spending, so it is grey and is never added to any total.
struct CardPaymentRow: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.and.123")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.secondary.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("Paid \(transfer.toAccount?.displayName ?? "card") bill")
                    .font(.body.weight(.medium))
                Text("From \(transfer.fromAccount?.displayName ?? "account") · Not counted as spending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transfer.amount, format: .rupees)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension Transfer {
    /// A payment from one of your accounts towards a credit card.
    var isCardBillPayment: Bool {
        toAccount?.kind.isLiability == true && fromAccount != nil
    }
}
