//
//  LoanStatementPDF.swift
//  ExpenseTracker
//

import UIKit

/// Makes PDF summaries of loans and EMIs, as files that can be shared.
///
/// - `summary`: everything, for your own records: money friends owe you, and your own EMIs.
/// - `statement`: one friend's loans and payments, to send to them. It holds nothing about anyone else.
enum LoanStatementPDF {
    // MARK: Whole summary

    /// A summary of every loan to a friend and every EMI of yours. Returns the file, or `nil` if it couldn't be written.
    static func summary(loans: [Loan], emis: [EMI], now: Date = .now) -> URL? {
        let open = loans.filter { !$0.isRepaid && $0.outstandingAmount > 0 }
        let byFriend = Dictionary(grouping: open) { $0.friendName.trimmingCharacters(in: .whitespaces).lowercased() }
            .values
            .sorted { $0.outstandingTotal > $1.outstandingTotal }
        let activeEMIs = emis.filter(\.isActive)
        let repaidCount = loans.count - open.count

        let data = PDFPage().data { page in
            page.title("Loans & EMIs Summary")
            page.text("As of \(now.formatted(.dateTime.day().month(.wide).year()))", font: .systemFont(ofSize: 11), color: .darkGray)
            page.gap(14)

            page.row("Owed to me by friends", open.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
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
                drawFriend(group, on: page, showPayments: false)
            }
            if repaidCount > 0 {
                page.gap(4)
                page.text("\(repaidCount) other loan\(repaidCount == 1 ? " is" : "s are") fully repaid.", font: .italicSystemFont(ofSize: 10), color: .darkGray)
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

            drawHowToPay(for: open, on: page)
        }
        return write(data, name: "Loans-and-EMIs-\(now.fileNameStamp)")
    }

    // MARK: One friend

    /// A statement for one friend: what they owe, what they have paid, and how to pay.
    static func statement(for friendName: String, loans: [Loan], now: Date = .now) -> URL? {
        let theirs = loans.filter {
            $0.friendName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(friendName.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }
        let open = theirs.filter { !$0.isRepaid && $0.outstandingAmount > 0 }
        let dueNow = open.reduce(Decimal(0)) { $0 + ($1.isInstalmentLoan ? $1.emiDueAmount : $1.outstandingAmount) }

        let data = PDFPage().data { page in
            page.title("Payment Statement")
            page.text("For \(friendName) · \(now.formatted(.dateTime.day().month(.wide).year()))", font: .systemFont(ofSize: 11), color: .darkGray)
            page.gap(14)

            page.row("Still owed", open.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 14))
            if open.contains(where: \.isInstalmentLoan) {
                page.row("To pay now", dueNow.formatted(.rupees), font: .boldSystemFont(ofSize: 14))
            }
            page.divider()

            if open.isEmpty {
                page.text("Nothing is owed. Thank you!", font: .systemFont(ofSize: 12))
            } else {
                drawFriend(open, on: page, showPayments: true, showName: false)
            }

            drawHowToPay(for: open, on: page)
        }
        let safeName = friendName.filter { $0.isLetter || $0.isNumber }
        return write(data, name: "Statement-\(safeName.isEmpty ? "Friend" : safeName)-\(now.fileNameStamp)")
    }

    // MARK: Drawing

    /// One friend's open loans, with what is still owed on each and, optionally, the payments received.
    private static func drawFriend(_ loans: [Loan], on page: PDFPage, showPayments: Bool, showName: Bool = true) {
        guard let first = loans.first else { return }
        if showName {
            page.gap(6)
            page.row(first.friendName, loans.outstandingTotal.formatted(.rupees), font: .boldSystemFont(ofSize: 13))
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
