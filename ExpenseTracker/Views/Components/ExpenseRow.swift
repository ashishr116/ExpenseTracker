//
//  ExpenseRow.swift
//  ExpenseTracker
//

import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    var showsTime = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.displayTitle)
                    .font(.body.weight(.medium))
                Text(expense.accountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if expense.isRefund {
                    Text("+\((-expense.amount).formatted(.rupees))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Refund")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text(expense.amount, format: .rupees)
                        .font(.body.weight(.semibold))
                }
                if expense.isRefund {
                    EmptyView()
                } else if expense.isPlanned {
                    Text("Not paid yet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if showsTime {
                    Text(expense.date, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
