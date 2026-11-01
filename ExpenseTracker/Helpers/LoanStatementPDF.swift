//
//  LoanStatementPDF.swift
//  ExpenseTracker
//

import UIKit

/// Makes PDF summaries of loans, borrowings, and EMIs, as files that can be shared.
///
/// - `summary`: everything, for your own records: money friends owe you, money you owe friends, and your EMIs.
/// - `statement`: one friend's loans, borrowings, and payments, to send to them.
enum LoanStatementPDF {
    // MARK: Whole summary

    /// A summary of every loan to a friend, money borrowed from friends, and EMIs of yours.
    static func summary(loans: [Loan], emis: [EMI], borrowings: [Borrowing] = [], now: Date = .now) -> URL? {
        let openLoans = loans.filter { !$0.isRepaid && $0.outstandingAmount > 0 }
        let byFriend = Dictionary(grouping: openLoans) { $0.friendName.trimmingCharacters(in: .whitespaces).lowercased() }
            .values
            .sorted { $0.outstandingTotal > $1.outstandingTotal }
        let activeEMIs = emis.filter(\.isActive)
        let repaidLoansCount = loans.count - openLoans.count

        let openBorrowings = borrowings.filter { !$0.isRepaid && $0.outstandingAmount > 0 }
        let borrowingsByFriend = Dictionary(grouping: openBorrowings) { $0.friendName.trimmingCharacters(in: .whitespaces).lowercased() }
            .values
            .sorted { $0.outstandingTotal > $1.outstandingTotal }
        let repaidBorrowingsCount = borrowings.count - openBorrowings.count

        let data = PDFPage().data { page in
            page.title("Loans & EMIs Summary")
            page.text("As of \(now.formatted(.dateTime.day().month(.wide).year()))", font: .systemFont(ofSize: 11), color: .darkGray)
            page.gap(14)

            page.row("Owed to me by friends", openLoans.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
            if !openBorrowings.isEmpty {
                page.row("Owed by me to friends", openBorrowings.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13), color: .darkGray)
                let net = openLoans.outstandingTotal - openBorrowings.outstandingTotal
                if net > 0 {
                    page.row("Net friends position (favour)", net.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
                } else if net < 0 {
                    page.row("Net friends position (you owe)", (-net).formatted(.rupees), font: .boldSystemFont(ofSize: 13))
                } else {
                    page.row("Net friends position", "Settled (₹0)", font: .boldSystemFont(ofSize: 13))
                }
            }
            page.row(
                "My EMIs each month",
                activeEMIs.reduce(Decimal(0)) { $0 + $1.monthlyAmount }.formatted(.rupees),
                font: .boldSystemFont(ofSize: 13)
            )
            page.divider()

            page.heading("Money lent to friends")
            if byFriend.isEmpty {
                page.text("Nobody owes you anything right now.", font: .systemFont(ofSize: 11), color: .darkGray)
            }
            for group in byFriend {
                let friendName = group.first?.friendName ?? ""
                let matchingBorrowings = openBorrowings.filter {
                    $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(friendName.trimmingCharacters(in: .whitespaces)) == .orderedSame
                }
                drawFriend(group, borrowings: matchingBorrowings, on: page, showPayments: false)
            }
            if repaidLoansCount > 0 {
                page.gap(4)
                page.text("\(repaidLoansCount) other loan\(repaidLoansCount == 1 ? " is" : "s are") fully repaid.", font: .italicSystemFont(ofSize: 10), color: .darkGray)
            }

            let standaloneBorrowings = borrowingsByFriend.filter { group in
                guard let friend = group.first?.friendName.trimmingCharacters(in: .whitespaces) else { return false }
                return !openLoans.contains { $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(friend) == .orderedSame }
            }

            if !openBorrowings.isEmpty {
                page.gap(10)
                page.heading("Money borrowed from friends")
                if standaloneBorrowings.isEmpty {
                    page.text("All borrowed amounts are cross-summarized with loans above.", font: .italicSystemFont(ofSize: 10), color: .darkGray)
                } else {
                    for group in standaloneBorrowings {
                        drawBorrowings(group, on: page, showPayments: false, showName: true)
                    }
                }
                if repaidBorrowingsCount > 0 {
                    page.gap(4)
                    page.text("\(repaidBorrowingsCount) other borrowed debt\(repaidBorrowingsCount == 1 ? " is" : "s are") fully repaid.", font: .italicSystemFont(ofSize: 10), color: .darkGray)
                }
            }

            page.gap(10)
            page.heading("My EMIs")
            if activeEMIs.isEmpty {
                page.text("No EMIs running.", font: .systemFont(ofSize: 11), color: .darkGray)
            }
            for emi in activeEMIs.sorted(by: { $0.name < $1.name }) {
                page.row(emi.name, "\(emi.remainingAmount.formatted(.rupees)) left", font: .systemFont(ofSize: 12), rightFont: .boldSystemFont(ofSize: 12))
                page.text(
                    "\(emi.monthlyAmount.formatted(.rupees)) a month · \(emi.paidCount) of \(emi.totalCount) paid",
                    font: .systemFont(ofSize: 10), color: .darkGray
                )
                page.gap(5)
            }

            drawHowToPay(for: openLoans, on: page)
        }
        return write(data, name: "Loans-and-EMIs-\(now.fileNameStamp)")
    }

    // MARK: One friend

    /// A statement for one friend: what they owe, what you borrowed from them, net position, and payments.
    static func statement(for friendName: String, loans: [Loan], borrowings: [Borrowing] = [], now: Date = .now) -> URL? {
        let trimmedFriend = friendName.trimmingCharacters(in: .whitespaces)
        let theirsLoans = loans.filter {
            $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedFriend) == .orderedSame
        }
        let openLoans = theirsLoans.filter { !$0.isRepaid && $0.outstandingAmount > 0 }
        let dueNow = openLoans.reduce(Decimal(0)) { $0 + ($1.isInstalmentLoan ? $1.emiDueAmount : $1.outstandingAmount) }

        let theirsBorrowings = borrowings.filter {
            $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedFriend) == .orderedSame
        }
        let openBorrowings = theirsBorrowings.filter { !$0.isRepaid && $0.outstandingAmount > 0 }

        let lentOutstanding = openLoans.outstandingTotal
        let borrowedOutstanding = openBorrowings.outstandingTotal
        let hasBoth = !theirsLoans.isEmpty && !theirsBorrowings.isEmpty
        let netPosition = lentOutstanding - borrowedOutstanding

        let data = PDFPage().data { page in
            page.title("Payment Statement")
            page.text("For \(friendName) · \(now.formatted(.dateTime.day().month(.wide).year()))", font: .systemFont(ofSize: 11), color: .darkGray)
            page.gap(14)

            if hasBoth || !openBorrowings.isEmpty {
                page.row("Owed by \(friendName) to you", lentOutstanding.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
                page.row("Owed by you to \(friendName)", borrowedOutstanding.formatted(.rupees), font: .boldSystemFont(ofSize: 13), color: .darkGray)

                if netPosition > 0 {
                    page.row("Net owed to you", netPosition.formatted(.rupees), font: .boldSystemFont(ofSize: 14))
                } else if netPosition < 0 {
                    page.row("Net you owe \(friendName)", (-netPosition).formatted(.rupees), font: .boldSystemFont(ofSize: 14))
                } else {
                    page.row("Net balance", "Settled (₹0)", font: .boldSystemFont(ofSize: 14))
                }
            } else {
                page.row("Total Owed", lentOutstanding.formatted(.rupees), font: .boldSystemFont(ofSize: 14))
            }

            if dueNow > 0 && dueNow != lentOutstanding {
                page.row("Due Now", dueNow.formatted(.rupees), font: .systemFont(ofSize: 12), color: .darkGray)
            }

            page.divider()

            if !openLoans.isEmpty {
                if hasBoth || !openBorrowings.isEmpty {
                    page.heading("Money lent to \(friendName)")
                }
                drawFriend(openLoans, on: page, showPayments: true, showName: false)
            }

            if !openBorrowings.isEmpty {
                page.gap(10)
                page.heading("Money you borrowed from \(friendName)")
                drawBorrowings(openBorrowings, on: page, showPayments: true, showName: false)
            }

            let repaidLoans = theirsLoans.filter(\.isRepaid)
            if !repaidLoans.isEmpty {
                page.gap(8)
                page.text(
                    "\(repaidLoans.count) other loan\(repaidLoans.count == 1 ? " is" : "s are") fully repaid.",
                    font: .italicSystemFont(ofSize: 10), color: .darkGray
                )
            }

            let repaidBorrowings = theirsBorrowings.filter(\.isRepaid)
            if !repaidBorrowings.isEmpty {
                page.gap(4)
                page.text(
                    "\(repaidBorrowings.count) other borrowed debt\(repaidBorrowings.count == 1 ? " is" : "s are") fully repaid.",
                    font: .italicSystemFont(ofSize: 10), color: .darkGray
                )
            }

            if openLoans.isEmpty && openBorrowings.isEmpty {
                page.gap(10)
                page.text("All settled! No outstanding amounts.", font: .systemFont(ofSize: 12), color: .darkGray)
            }

            drawHowToPay(for: openLoans, on: page)
        }
        let safeName = friendName.filter { $0.isLetter || $0.isNumber }
        return write(data, name: "Statement-\(safeName.isEmpty ? "Friend" : safeName)-\(now.fileNameStamp)")
    }

    // MARK: Helpers

    /// One friend's open loans, with what is still owed on each and, optionally, any borrowings and payments.
    private static func drawFriend(_ loans: [Loan], borrowings: [Borrowing] = [], on page: PDFPage, showPayments: Bool, showName: Bool = true) {
        guard let first = loans.first else { return }
        let hasBoth = !loans.isEmpty && !borrowings.isEmpty
        let lentTotal = loans.outstandingTotal
        let borrowedTotal = borrowings.outstandingTotal

        if showName {
            page.gap(6)
            if hasBoth {
                let net = lentTotal - borrowedTotal
                let netText: String
                if net > 0 {
                    netText = "Net: \(net.formatted(.rupees)) owed to you"
                } else if net < 0 {
                    netText = "Net: \((-net).formatted(.rupees)) you owe"
                } else {
                    netText = "Net: Settled (₹0)"
                }
                page.row(first.friendName, netText, font: .boldSystemFont(ofSize: 13))
                page.text("Lent: \(lentTotal.formatted(.rupees))  ·  Borrowed: \(borrowedTotal.formatted(.rupees))", font: .systemFont(ofSize: 10), color: .darkGray)
            } else {
                page.row(first.friendName, lentTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
            }
        }
        if hasBoth {
            page.text("Money lent to \(first.friendName):", font: .boldSystemFont(ofSize: 10), color: .darkGray)
        }
        for loan in loans.sorted(by: { $0.date < $1.date }) {
            let date = loan.date.formatted(.dateTime.day().month(.abbreviated).year())
            var title = "\(date) · \(kind(of: loan))"
            if !loan.note.isEmpty { title += " · \(loan.note)" }
            page.row(title, "\(loan.outstandingAmount.formatted(.rupees)) owed", font: .systemFont(ofSize: 11), rightFont: .systemFont(ofSize: 11))

            var detail = "Amount \(loan.amount.formatted(.rupees))"
            if loan.repaidAmount > 0 { detail += " · paid \(loan.repaidAmount.formatted(.rupees))" }
            if loan.isInstalmentLoan, let emi = loan.monthlyInstalment {
                detail += " · EMI \(emi.formatted(.rupees)), \(loan.installmentsPaid) of \(loan.installmentCount) paid"
            }
            page.text(detail, font: .systemFont(ofSize: 9.5), color: .darkGray)

            if showPayments {
                for payment in loan.sortedRepayments.reversed() {
                    page.row(
                        "   Paid on \(payment.date.formatted(.dateTime.day().month(.abbreviated).year()))",
                        "+\(payment.amount.formatted(.rupees))",
                        font: .systemFont(ofSize: 9.5), color: .darkGray
                    )
                }
            }
            page.gap(4)
        }

        if hasBoth {
            page.gap(2)
            page.text("Money borrowed from \(first.friendName):", font: .boldSystemFont(ofSize: 10), color: .darkGray)
            for borrowing in borrowings.sorted(by: { $0.date < $1.date }) {
                let date = borrowing.date.formatted(.dateTime.day().month(.abbreviated).year())
                let method = borrowing.bankName.isEmpty ? "Cash" : "Bank transfer (\(borrowing.bankName))"
                var title = "\(date) · \(method)"
                if !borrowing.note.isEmpty { title += " · \(borrowing.note)" }
                page.row(title, "\(borrowing.outstandingAmount.formatted(.rupees)) owed", font: .systemFont(ofSize: 11), rightFont: .systemFont(ofSize: 11))

                var detail = "Amount \(borrowing.amount.formatted(.rupees))"
                if borrowing.paidAmount > 0 { detail += " · paid back \(borrowing.paidAmount.formatted(.rupees))" }
                if let due = borrowing.dueDate {
                    detail += " · Due \(due.formatted(.dateTime.day().month(.abbreviated).year()))"
                }
                page.text(detail, font: .systemFont(ofSize: 9.5), color: .darkGray)

                if showPayments {
                    for payment in borrowing.sortedPayments.reversed() {
                        page.row(
                            "   Paid back on \(payment.date.formatted(.dateTime.day().month(.abbreviated).year()))",
                            "+\(payment.amount.formatted(.rupees))",
                            font: .systemFont(ofSize: 9.5), color: .darkGray
                        )
                    }
                }
                page.gap(4)
            }
        }
    }

    /// One friend's open borrowings, with what is still owed and payments made back.
    private static func drawBorrowings(_ borrowings: [Borrowing], on page: PDFPage, showPayments: Bool, showName: Bool = true) {
        guard let first = borrowings.first else { return }
        if showName {
            page.gap(6)
            page.row(first.friendName, borrowings.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
        }
        for borrowing in borrowings.sorted(by: { $0.date < $1.date }) {
            let date = borrowing.date.formatted(.dateTime.day().month(.abbreviated).year())
            let method = borrowing.bankName.isEmpty ? "Cash" : "Bank transfer (\(borrowing.bankName))"
            var title = "\(date) · \(method)"
            if !borrowing.note.isEmpty { title += " · \(borrowing.note)" }
            page.row(title, "\(borrowing.outstandingAmount.formatted(.rupees)) owed", font: .systemFont(ofSize: 11), rightFont: .systemFont(ofSize: 11))

            var detail = "Amount \(borrowing.amount.formatted(.rupees))"
            if borrowing.paidAmount > 0 { detail += " · paid back \(borrowing.paidAmount.formatted(.rupees))" }
            if let due = borrowing.dueDate {
                detail += " · Due \(due.formatted(.dateTime.day().month(.abbreviated).year()))"
            }
            page.text(detail, font: .systemFont(ofSize: 9.5), color: .darkGray)

            if showPayments {
                for payment in borrowing.sortedPayments.reversed() {
                    page.row(
                        "   Paid back on \(payment.date.formatted(.dateTime.day().month(.abbreviated).year()))",
                        "+\(payment.amount.formatted(.rupees))",
                        font: .systemFont(ofSize: 9.5), color: .darkGray
                    )
                }
            }
            page.gap(4)
        }
    }

    /// "Cash / Transfer", "HDFC Bank credit card ending 0214" or "Personal loan from HDFC Bank".
    private static func kind(of loan: Loan) -> String {
        switch loan.method {
        case .cash:
            return "Cash / Transfer"
        case .personalLoan:
            return loan.bankName.isEmpty ? "Personal loan" : "Personal loan from \(loan.bankName)"
        case .card:
            return PaymentDetails.cardLine(for: loan).replacingOccurrences(of: "Card: ", with: "")
        }
    }

    private static func drawHowToPay(for loans: [Loan], on page: PDFPage) {
        let lines = PaymentDetails.lines(for: loans)
        guard !lines.isEmpty else { return }
        page.gap(12)
        page.divider()
        page.heading("How to pay")
        for line in lines {
            page.text("• \(line)", font: .systemFont(ofSize: 12))
        }
    }

    private static func write(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Page layout

/// Lays text out down A4 pages, starting a new page when one fills up.
private final class PDFPage {
    private let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private let margin: CGFloat = 44
    private var y: CGFloat = 0
    private var context: UIGraphicsPDFRendererContext?

    private var contentWidth: CGFloat { pageRect.width - margin * 2 }

    func data(_ draw: (PDFPage) -> Void) -> Data {
        UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
            self.context = context
            startPage()
            draw(self)
            self.context = nil
        }
    }

    private func startPage() {
        context?.beginPage()
        y = margin
    }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > pageRect.height - margin { startPage() }
    }

    func gap(_ height: CGFloat) { y += height }

    func title(_ string: String) {
        text(string, font: .boldSystemFont(ofSize: 24))
        gap(2)
    }

    func heading(_ string: String) {
        ensureSpace(30)
        text(string, font: .boldSystemFont(ofSize: 15))
        gap(4)
    }

    func divider() {
        gap(6)
        ensureSpace(8)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        gap(10)
    }

    func text(_ string: String, font: UIFont, color: UIColor = .black) {
        let height = measure(string, font: font, width: contentWidth)
        ensureSpace(height)
        draw(string, font: font, color: color, alignment: .left, in: CGRect(x: margin, y: y, width: contentWidth, height: height))
        y += height + 2
    }

    /// Text on the left and an amount on the right, on one line.
    func row(
        _ left: String,
        _ right: String,
        font: UIFont,
        rightFont: UIFont? = nil,
        color: UIColor = .black
    ) {
        let rightWidth: CGFloat = 130
        let leftWidth = contentWidth - rightWidth - 10
        let leftHeight = measure(left, font: font, width: leftWidth)
        let rightHeight = measure(right, font: rightFont ?? font, width: rightWidth)
        let height = max(leftHeight, rightHeight)
        ensureSpace(height)
        draw(left, font: font, color: color, alignment: .left, in: CGRect(x: margin, y: y, width: leftWidth, height: leftHeight))
        draw(
            right, font: rightFont ?? font, color: color, alignment: .right,
            in: CGRect(x: pageRect.width - margin - rightWidth, y: y, width: rightWidth, height: rightHeight)
        )
        y += height + 3
    }

    private func attributes(font: UIFont, color: UIColor, alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    private func measure(_ string: String, font: UIFont, width: CGFloat) -> CGFloat {
        let bounds = (string as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font: font, color: .black, alignment: .left),
            context: nil
        )
        return ceil(bounds.height)
    }

    private func draw(_ string: String, font: UIFont, color: UIColor, alignment: NSTextAlignment, in rect: CGRect) {
        (string as NSString).draw(in: rect, withAttributes: attributes(font: font, color: color, alignment: alignment))
    }
}
