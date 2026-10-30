//
//  Brand.swift
//  ExpenseTracker
//

import SwiftUI

/// Brand colours shared by the splash screen (and matching the app icon).
extension Color {
    /// #0B2A5B
    static let brandNavy = Color(red: 0.043, green: 0.165, blue: 0.357)
    /// #FFC93C
    static let brandYellow = Color(red: 1.0, green: 0.788, blue: 0.235)
    /// #FFE07A
    static let brandLightYellow = Color(red: 1.0, green: 0.878, blue: 0.478)
}

/// Popular banks for fast one-tap selection when entering expenses, cards, or income.
enum PopularBank {
    static let names: [String] = [
        "HDFC Bank",
        "ICICI Bank",
        "SBI",
        "Axis Bank",
        "Kotak Mahindra Bank",
        "IDFC FIRST Bank",
        "IndusInd Bank",
        "Punjab National Bank",
        "Bank of Baroda",
        "Canara Bank",
        "Yes Bank",
        "Federal Bank",
        "Amex",
        "Standard Chartered",
        "HSBC",
        "RBL Bank"
    ]
}
