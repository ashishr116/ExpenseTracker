//
//  BorrowedView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Money borrowed from friends: what you still owe, and what you have paid back.
struct BorrowedView: View {
    @Query(sort: \Borrowing.date, order: .reverse) private var borrowings: [Borrowing]

    @State private var isAdding = false

    private var outstanding: [Borrowing] { borrowings.filter { !$0.isRepaid } }
    private var repaid: [Borrowing] { borrowings.filter(\.isRepaid) }

    var body: some View {
        List {
            if borrowings.isEmpty {
                ContentUnavailableView(
                    "Nothing Borrowed",
                    systemImage: "person.2.slash",
                    description: Text("Tap + to record money you took from a friend, and pay it back in parts.")
                )
            } else {
                Section {
                    LabeledContent("Total You Owe") {
                        Text(outstanding.outstandingTotal, format: .rupees)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(outstanding.isEmpty ? Color.primary : Color.red)
                    }
                }

                if !outstanding.isEmpty {
                    Section("Outstanding") {
                        ForEach(outstanding) { borrowing in
                            NavigationLink {
                                BorrowingDetailView(borrowing: borrowing)
                            } label: {
                                BorrowingRow(borrowing: borrowing)
                            }
                        }
                    }
                }

                if !repaid.isEmpty {
                    Section("Paid Back") {
                        ForEach(repaid) { borrowing in
                            NavigationLink {
                                BorrowingDetailView(borrowing: borrowing)
                            } label: {
                                BorrowingRow(borrowing: borrowing)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Borrowed")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            BorrowingFormView()
        }
    }
}

private struct BorrowingRow: View {
    let borrowing: Borrowing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(borrowing.friendName)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(borrowing.date, format: .dateTime.day().month().year())
                    if let due = borrowing.dueDate, !borrowing.isRepaid {
                        Text("· Due \(due.formatted(.dateTime.day().month()))")
                            .foregroundStyle(borrowing.isOverdue ? Color.red : Color.secondary)
                    }
                    if !borrowing.note.isEmpty { Text("· \(borrowing.note)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(borrowing.isRepaid ? borrowing.amount : borrowing.outstandingAmount, format: .rupees)
                    .fontWeight(.semibold)
                    .foregroundStyle(borrowing.isRepaid ? Color.secondary : Color.red)
                if !borrowing.isRepaid, borrowing.paidAmount > 0 {
                    Text("of \(borrowing.amount.formatted(.rupees))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Add or edit

/// Sheet for recording money borrowed from a friend, or editing it when `borrowing` is non-nil.
struct BorrowingFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    let borrowing: Borrowing?

    @State private var amount: Decimal?
    @State private var friendName: String
    @State private var friendPhone: String
    @State private var note: String
    @State private var date: Date
    /// The bank account the money landed in. Empty means cash.
    @State private var receivedIn: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date

    init(borrowing: Borrowing? = nil) {
        self.borrowing = borrowing
        _amount = State(initialValue: borrowing?.amount)
        _friendName = State(initialValue: borrowing?.friendName ?? "")
        _friendPhone = State(initialValue: borrowing?.friendPhone ?? "")
        _note = State(initialValue: borrowing?.note ?? "")
        _date = State(initialValue: borrowing?.date ?? .now)
        _receivedIn = State(initialValue: borrowing?.bankName ?? "")
        _hasDueDate = State(initialValue: borrowing?.dueDate != nil)
        _dueDate = State(initialValue: borrowing?.dueDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
    }

    /// Banks of your open bank accounts, one entry per bank.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var trimmedName: String { friendName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        guard let amount, amount > 0 else { return false }
        // An amount can't be lowered below what has already been paid back.
        if let borrowing, amount < borrowing.paidAmount { return false }
        return !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Borrowed") {
                    TextField("Amount", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    TextField("Friend's Name", text: $friendName)
                        .textInputAutocapitalization(.words)
                    TextField("Phone Number (optional)", text: $friendPhone)
                        .keyboardType(.phonePad)
                    TextField("Note (optional)", text: $note)
                }

                Section {
                    Picker("Money Came Into", selection: $receivedIn) {
                        Text("Cash").tag("")
                        ForEach(bankChoices, id: \.self) { bank in
                            Text(bank).tag(bank)
                        }
                    }
                    DatePicker("Received On", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Where It Went")
                } footer: {
                    Text("This account goes up now. It isn't income, because you have to pay it back.")
                }

                Section {
                    Toggle("Promised Pay-Back Date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Pay Back By", selection: $dueDate, in: date..., displayedComponents: .date)
                    }
                } footer: {
                    if hasDueDate {
                        Text("You get a reminder the day before and on the day.")
                    }
                }

                if let borrowing {
                    Section {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(borrowing)
                            reschedule()
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting also removes the payments you recorded for it.")
                    }
                }
            }
            .navigationTitle(borrowing == nil ? "Borrowed Money" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        let trimmedPhone = friendPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let due: Date? = hasDueDate ? dueDate : nil

        if let borrowing {
            borrowing.amount = amount
            borrowing.friendName = trimmedName
            borrowing.friendPhone = trimmedPhone
            borrowing.note = trimmedNote
            borrowing.date = date
            borrowing.bankName = receivedIn
            borrowing.dueDate = due
            borrowing.syncRepaidState()
        } else {
            modelContext.insert(Borrowing(
                amount: amount, friendName: trimmedName, friendPhone: trimmedPhone,
                note: trimmedNote, date: date, bankName: receivedIn, dueDate: due
            ))
        }
        reschedule()
        dismiss()
    }

    private func reschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await BorrowingReminder.reschedule(in: context)
        }
    }
}

// MARK: - Detail

/// One debt to a friend: what is left, the payments made, and a way to record another.
struct BorrowingDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let borrowing: Borrowing

    @State private var isPaying = false
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Still Owe") {
                    Text(borrowing.outstandingAmount, format: .rupees)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(borrowing.isRepaid ? Color.green : Color.red)
                }
                LabeledContent("Borrowed") { Text(borrowing.amount, format: .rupees) }
                LabeledContent("Paid Back") { Text(borrowing.paidAmount, format: .rupees) }
                LabeledContent("Received On") {
                    Text(borrowing.date, format: .dateTime.day().month().year())
                }
                LabeledContent("Came Into", value: borrowing.bankName.isEmpty ? "Cash" : borrowing.bankName)
                if let due = borrowing.dueDate {
                    LabeledContent("Pay Back By") {
                        Text(due, format: .dateTime.day().month().year())
                            .foregroundStyle(borrowing.isOverdue ? Color.red : Color.primary)
                    }
                }
                if !borrowing.note.isEmpty {
                    LabeledContent("Note", value: borrowing.note)
                }
            }

            if !borrowing.isRepaid {
                Section {
                    Button("Record a Payment", systemImage: "arrow.up.right.circle") { isPaying = true }
                    Button("Mark Fully Repaid", systemImage: "checkmark.circle") {
                        borrowing.recordPayment(
                            borrowing.outstandingAmount, bankName: borrowing.bankName, in: modelContext
                        )
                        reschedule()
                    }
                } footer: {
                    Text("A payment comes out of the account you pay from. Mark Fully Repaid pays what is left from the account the money came into.")
                }
            }

            Section("Payments") {
                if borrowing.payments.isEmpty {
                    Text("No payments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(borrowing.sortedPayments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.date, format: .dateTime.day().month().year())
                            Text(payment.bankName.isEmpty ? "Cash" : payment.bankName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !payment.note.isEmpty {
                                Text(payment.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(payment.amount, format: .rupees)
                            .fontWeight(.semibold)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            borrowing.removePayment(payment, in: modelContext)
                            reschedule()
                        }
                    }
                }
            }
        }
        .navigationTitle(borrowing.friendName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isPaying, onDismiss: reschedule) {
            BorrowingPaymentSheet(borrowing: borrowing)
        }
        .sheet(isPresented: $isEditing) {
            BorrowingFormView(borrowing: borrowing)
        }
    }

    private func reschedule() {
        let context = modelContext
        Task {
            try? context.save()
            await BorrowingReminder.reschedule(in: context)
        }
    }
}

/// Sheet for recording a payment to a friend. It can be less than what is left.
private struct BorrowingPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    let borrowing: Borrowing

    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""
    /// The bank account it is paid from. Empty means cash.
    @State private var paidFrom: String

    init(borrowing: Borrowing) {
        self.borrowing = borrowing
        _amount = State(initialValue: borrowing.outstandingAmount)
        // By default it goes back out of the account it came into.
        _paidFrom = State(initialValue: borrowing.bankName)
    }

    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0 && amount <= borrowing.outstandingAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Still Owe") { Text(borrowing.outstandingAmount, format: .rupees) }
                    TextField("Amount Paid", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Picker("Paid From", selection: $paidFrom) {
                        Text("Cash").tag("")
                        ForEach(bankChoices, id: \.self) { bank in
                            Text(bank).tag(bank)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if let amount, amount > borrowing.outstandingAmount {
                        Text("That is more than you owe.")
                            .foregroundStyle(.red)
                    } else {
                        Text("After this you will owe \(max(0, borrowing.outstandingAmount - (amount ?? 0)).formatted(.rupees)).")
                    }
                }
            }
            .navigationTitle("Pay \(borrowing.friendName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount, isValid else { return }
                        borrowing.recordPayment(
                            amount, on: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            bankName: paidFrom, in: modelContext
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
