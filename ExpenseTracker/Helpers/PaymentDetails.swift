//
//  PaymentDetails.swift
//  ExpenseTracker
//

import Foundation

/// How friends should pay you back, added to every reminder and PDF statement.
///
/// - Money lent as cash or a transfer, and personal loans in your name, are paid to your UPI ID.
/// - Money a friend spent on your card is paid to that card, so the card's name and last four digits are shown.
///   The last four digits can be left out.
enum PaymentDetails {
    static let upiKey = "payUPIID"
    static let nameKey = "payPayeeName"
    static let includeCardKey = "payIncludeCardDigits"

    static var upiID: String {
        (UserDefaults.standard.string(forKey: upiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name shown beside the UPI ID, so a friend can check they are paying the right person.
    static var payeeName: String {
        (UserDefaults.standard.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the last four digits of a card are shown. On unless switched off.
    static var includesCardDigits: Bool {
        UserDefaults.standard.object(forKey: includeCardKey) as? Bool ?? true
    }

    /// A UPI ID looks like `name@bank`: something, an @, and something, with no spaces.
    static func isValidUPI(_ id: String) -> Bool {
        let parts = id.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty && !id.contains(" ")
    }

    /// "UPI: name@bank (Name)".
    static var upiLine: String? {
        guard !upiID.isEmpty else { return nil }
        return payeeName.isEmpty ? "UPI: \(upiID)" : "UPI: \(upiID) (\(payeeName))"
    }

    /// "Card: HDFC Bank credit card ending 0214", for a loan on one of your cards.
    static func cardLine(for loan: Loan) -> String {
        let type = loan.accountType.rawValue.lowercased()
        let name = loan.bankName.isEmpty ? type : "\(loan.bankName) \(type)"
        let digits = includesCardDigits && !loan.cardLastFour.isEmpty ? " ending \(loan.cardLastFour)" : ""
        return "Card: \(name)\(digits)"
    }

    /// The ways to pay for these loans, one line each, without bullets. Empty when there is nothing to tell.
    static func lines(for loans: [Loan]) -> [String] {
        var result: [String] = []
        if loans.contains(where: { $0.method != .card }), let upi = upiLine {
            result.append(upi)
        }
        var seen = Set<String>()
        for loan in loans where loan.method == .card {
            let line = cardLine(for: loan)
            if seen.insert(line).inserted { result.append(line) }
        }
        return result
    }
}
