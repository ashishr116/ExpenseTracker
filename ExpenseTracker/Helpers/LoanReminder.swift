//
//  LoanReminder.swift
//  ExpenseTracker
//

import Foundation

/// How a reminder is sent.
enum ReminderChannel {
    case messages
    case whatsApp
}

/// A credit card bill that is coming due, for a reminder that is about the bill and not just the money owed.
struct CardBillDue {
    /// How the card is named in the message, e.g. "HDFC Bank credit card". No digits, for privacy.
    let cardName: String
    let date: Date
}

/// A ready-to-send payment reminder for one friend.
struct LoanReminder: Identifiable {
    let friendName: String
    /// Recipient number; empty if unknown (the person can type it in Messages).
    let phone: String
    let loans: [Loan]
    /// Set when the reminder is about a card bill that is due soon.
    var billDue: CardBillDue?

    var id: String { friendName.lowercased() }

    init(friendName: String, loans: [Loan], phone: String? = nil) {
        self.friendName = friendName
        // Sort oldest first so the message reads chronologically.
        self.loans = loans.sorted { $0.date < $1.date }
        if let phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            self.phone = phone.trimmingCharacters(in: .whitespaces)
        } else {
            // Use the most recently entered phone number for this friend.
            self.phone = loans
                .sorted { $0.date > $1.date }
                .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
        }
    }

    init(
        friendName: String,
        amount: Decimal,
        note: String = "",
        phone: String = "",
        date: Date = .now,
        method: LoanMethod = .cash,
        accountType: AccountType = .creditCard,
        bankName: String = ""
    ) {
        let tempLoan = Loan(
            amount: amount,
            friendName: friendName,
            friendPhone: phone,
            note: note,
            date: date,
            method: method,
            accountType: accountType,
            bankName: bankName
        )
        self.friendName = friendName
        self.phone = phone.trimmingCharacters(in: .whitespaces)
        self.loans = [tempLoan]
    }

    /// A link that opens WhatsApp with this reminder typed out, ready to send. With a number it opens that
    /// chat. Without one, WhatsApp asks who to send it to. If WhatsApp isn't installed it opens in the browser.
    var whatsAppURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        // wa.me needs the number as digits with the country code, no + or spaces.
        var digits = phone.filter(\.isNumber)
        if digits.hasPrefix("0") { digits.removeFirst() }
        // A 10-digit mobile number is an Indian one.
        if digits.count == 10 { digits = "91" + digits }
        components.path = digits.isEmpty ? "/" : "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: messageBody)]
        return components.url
    }

    /// What is asked for now: the EMI for an instalment loan, and what is still owed for any other loan.
    var total: Decimal { loans.reduce(0) { $0 + Self.dueAmount(for: $1) } }

    private static func dueAmount(for loan: Loan) -> Decimal {
        loan.isInstalmentLoan ? loan.emiDueAmount : loan.outstandingAmount
    }

    /// Every loan is an instalment loan, so the message is about EMIs.
    private var isAllInstalments: Bool { !loans.isEmpty && loans.allSatisfy(\.isInstalmentLoan) }

    /// The summarised text message, e.g.
    ///
    ///     Hi Rahul, a friendly reminder about the money pending with you:
    ///
    ///     • 12 Oct 2026 – ₹2,000 – Cash/Transfer (Trip advance)
    ///     • 20 Oct 2026 – ₹1,500 – Used my HDFC Bank credit card (Flight ticket)
    ///
    ///     Total due: ₹3,500
    ///
    ///     Please repay when you can. Thanks!
    var messageBody: String {
        let lines = loans.map { loan -> String in
            if loan.isInstalmentLoan {
                return Self.instalmentLine(for: loan)
            }
            let date = loan.date.formatted(.dateTime.day().month(.abbreviated).year())
            let amount = loan.outstandingAmount.formatted(.rupees)
            var line = "• \(date) – \(amount) – \(Self.methodDescription(for: loan))"
            if !loan.note.isEmpty {
                line += " (\(loan.note))"
            }
            if loan.repaidAmount > 0 {
                line += " [\(loan.repaidAmount.formatted(.rupees)) already repaid]"
            }
            return line
        }

        let intro: String
        if let billDue {
            let date = billDue.date.formatted(.dateTime.day().month(.wide).year())
            intro = "Hi \(friendName), a reminder that my \(billDue.cardName) bill is due on \(date). Your part of it:"
        } else if isAllInstalments {
            intro = loans.count == 1
                ? "Hi \(friendName), a friendly reminder that your EMI is due:"
                : "Hi \(friendName), a friendly reminder that your EMIs are due:"
        } else {
            intro = loans.count == 1
                ? "Hi \(friendName), a friendly reminder about the money pending with you:"
                : "Hi \(friendName), a friendly reminder about the \(loans.count) payments pending with you:"
        }

        // How to pay, as set under Payment Details. Left out when nothing is set.
        let paymentLines = PaymentDetails.lines(for: loans)
        let paymentBlock = paymentLines.isEmpty
            ? ""
            : "How to pay:\n" + paymentLines.map { "• \($0)" }.joined(separator: "\n") + "\n\n"

        return """
        \(intro)

        \(lines.joined(separator: "\n"))

        \(isAllInstalments ? "EMI due" : "Total due"): \(total.formatted(.rupees))

        \(paymentBlock)\(closing)
        """
    }

    private var closing: String {
        if billDue != nil { return "Please pay it to the card before the due date. Thanks!" }
        return isAllInstalments
            ? "Please pay the EMI when it's due each month. Thanks!"
            : "Please repay when you can. Thanks!"
    }

    /// "• EMI 4 of 12 – ₹5,000 – Personal loan from HDFC Bank taken in my name". Only the EMI is asked for.
    private static func instalmentLine(for loan: Loan) -> String {
        let first = loan.installmentsPaid + 1
        let last = loan.installmentsPaid + loan.emiDueCount
        let which = first == last
            ? "EMI \(first) of \(loan.installmentCount)"
            : "EMIs \(first) to \(last) of \(loan.installmentCount)"
        var line = "• \(which) – \(loan.emiDueAmount.formatted(.rupees)) – \(methodDescription(for: loan))"
        if !loan.note.isEmpty {
            line += " (\(loan.note))"
        }
        return line
    }

    /// "Cash/Transfer" or "Used my HDFC Bank credit card". Card digits are left out for privacy.
    private static func methodDescription(for loan: Loan) -> String {
        switch loan.method {
        case .cash:
            return "Cash/Transfer"
        case .personalLoan:
            return loan.bankName.isEmpty
                ? "Personal loan taken in my name"
                : "Personal loan from \(BankName.display(loan.bankName)) taken in my name"
        case .card:
            let cardType = loan.accountType.rawValue.lowercased()
            return loan.bankName.isEmpty
                ? "Used my \(cardType)"
                : "Used my \(BankName.display(loan.bankName)) \(cardType)"
        }
    }
}
