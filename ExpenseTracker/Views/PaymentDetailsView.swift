//
//  PaymentDetailsView.swift
//  ExpenseTracker
//

import SwiftUI

/// Where friends should send money, added to every reminder message and PDF statement.
struct PaymentDetailsView: View {
    @AppStorage(PaymentDetails.upiKey) private var upiID = ""
    @AppStorage(PaymentDetails.nameKey) private var payeeName = ""
    @AppStorage(PaymentDetails.includeCardKey) private var includeCardDigits = true

    private var trimmedUPI: String { upiID.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("UPI ID (e.g. name@okhdfc)", text: $upiID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                TextField("Name shown with it (optional)", text: $payeeName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("UPI")
            } footer: {
                if !trimmedUPI.isEmpty, !PaymentDetails.isValidUPI(trimmedUPI) {
                    Text("A UPI ID looks like name@bank. Check it before sending reminders.")
                        .foregroundStyle(.red)
                } else {
                    Text("Friends who owe you cash, a transfer or a personal loan are asked to pay this UPI ID.")
                }
            }

            Section {
                Toggle("Show Last 4 Digits", isOn: $includeCardDigits)
            } header: {
                Text("Cards")
            } footer: {
                Text("For money a friend spent on your card, reminders say which card to pay: its name, and the last 4 digits if this is on. It uses the card chosen on that loan, so there is nothing else to enter.")
            }

            Section {
                preview
            } header: {
                Text("What Friends Will See")
            }
        }
        .navigationTitle("Payment Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The "How to pay" block as it will appear in a message.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to pay:")
                .fontWeight(.semibold)
            if trimmedUPI.isEmpty {
                Text("• UPI: add your UPI ID above")
                    .foregroundStyle(.secondary)
            } else {
                Text("• \(previewUPI)")
            }
            Text("• Card: HDFC Bank credit card\(includeCardDigits ? " ending 0214" : "")")
        }
        .font(.subheadline)
    }

    private var previewUPI: String {
        payeeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "UPI: \(trimmedUPI)"
            : "UPI: \(trimmedUPI) (\(payeeName.trimmingCharacters(in: .whitespacesAndNewlines)))"
    }
}

#Preview {
    NavigationStack {
        PaymentDetailsView()
    }
}
