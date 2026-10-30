//
//  MonthSelector.swift
//  ExpenseTracker
//

import SwiftUI

/// A "‹ October 2026 ›" control for stepping between months.
struct MonthSelector: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button("Previous Month", systemImage: "chevron.left") { shift(by: -1) }
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button("Next Month", systemImage: "chevron.right") { shift(by: 1) }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func shift(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = newMonth
        }
    }
}
