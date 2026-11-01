//
//  CardsView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Displays all saved payment cards (Credit & Debit) with masked details by default,
/// tap-to-reveal security toggle, and options to add, edit, or remove cards.
struct CardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PaymentCard.createdAt, order: .reverse) private var cards: [PaymentCard]

    @Environment(\.scenePhase) private var scenePhase

    @State private var isAddingCard = false
    @State private var editingCard: PaymentCard?
    @State private var revealedCardIDs = Set<PersistentIdentifier>()
    @State private var isShowingUnavailableAlert = false

    var body: some View {
        List {
            if !cards.isEmpty {
                ForEach(cards) { card in
                    let isRevealed = revealedCardIDs.contains(card.persistentModelID)
                    CardTile(
                        card: card,
                        isRevealed: isRevealed,
                        onToggleReveal: {
                            if isRevealed {
                                // Hiding needs no check.
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    _ = revealedCardIDs.remove(card.persistentModelID)
                                }
                            } else {
                                Task {
                                    guard await unlock(reason: "Show your full card details.") else { return }
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        _ = revealedCardIDs.insert(card.persistentModelID)
                                    }
                                }
                            }
                        },
                        onEdit: {
                            edit(card)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(card)
                        }
                        Button("Edit", systemImage: "pencil") {
                            edit(card)
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        // Full details lock again as soon as you leave the app or this screen.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealedCardIDs.removeAll() }
        }
        .onDisappear { revealedCardIDs.removeAll() }
        .alert("Set Up Face ID or a Passcode", isPresented: $isShowingUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Card details can only be shown on a device protected by Face ID or a passcode. Set one up in Settings, then try again.")
        }
        .listStyle(.plain)
        .navigationTitle("Saved Cards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Card", systemImage: "plus") {
                    isAddingCard = true
                }
            }
        }
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Cards Saved",
                    systemImage: "creditcard",
                    description: Text("Add your credit and debit cards to securely store your card details and quickly pick them when entering expenses.")
                )
            }
        }
        .sheet(isPresented: $isAddingCard) {
            CardFormView()
        }
        .sheet(item: $editingCard) { card in
            CardFormView(card: card)
        }
    }

    // MARK: Face ID

    /// Asks for Face ID (or the passcode). Explains if the device has neither.
    private func unlock(reason: String) async -> Bool {
        switch await BiometricAuth.authenticate(reason: reason) {
        case .success:
            return true
        case .failed:
            return false
        case .unavailable:
            isShowingUnavailableAlert = true
            return false
        }
    }

    /// The edit screen shows the full number and CVV, so it needs the same check as showing them.
    private func edit(_ card: PaymentCard) {
        Task {
            guard await unlock(reason: "Edit your card details.") else { return }
            editingCard = card
        }
    }
}

/// Sleek credit/debit card UI representation with masked/revealed state.
private struct CardTile: View {
    let card: PaymentCard
    let isRevealed: Bool
    let onToggleReveal: () -> Void
    let onEdit: () -> Void

    private var gradient: LinearGradient {
        if card.accountType == .creditCard {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.16, blue: 0.32), Color(red: 0.03, green: 0.07, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.26, blue: 0.22), Color(red: 0.01, green: 0.14, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Bank & Nickname + Card Type Pill + Show/Hide Button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.bankName.isEmpty ? "Card" : BankName.display(card.bankName))
                        .font(.headline)
                        .foregroundStyle(.white)
                    if !card.nickname.isEmpty {
                        Text(card.nickname)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Text(card.accountType.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: .capsule)

                    Button(action: onToggleReveal) {
                        HStack(spacing: 4) {
                            Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            Text(isRevealed ? "Hide" : "Show")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.25), in: .capsule)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Card Number
            HStack(spacing: 8) {
                if isRevealed && !card.cardNumber.isEmpty {
                    Text(card.formattedFullNumber)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                } else {
                    Text(card.maskedNumber)
                        .font(.system(.headline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()

                if isRevealed && !card.cardNumber.isEmpty {
                    Button {
                        UIPasteboard.general.string = card.cardNumber
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(6)
                            .background(.white.opacity(0.2), in: .circle)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy Card Number")
                }
            }
            .padding(.vertical, 2)

            // Bottom row: Cardholder, Expiry, CVV & Edit Button
            HStack(alignment: .bottom) {
                if !card.cardholderName.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARDHOLDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(card.cardholderName.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                if !card.expiryDate.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EXPIRES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(isRevealed ? card.expiryDate : "••/••")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }

                if !card.cvv.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CVV")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(isRevealed ? card.cvv : "•••")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 10)
                }

                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        }
        .padding(18)
        .background(gradient, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        CardsView()
    }
    .modelContainer(for: PaymentCard.self, inMemory: true)
}
