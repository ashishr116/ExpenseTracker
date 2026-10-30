//
//  OnboardingView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Whether the first-launch setup has been done, and whether it is needed.
enum Onboarding {
    static let completedKey = "onboardingCompleted"

    /// An install that already has data, such as one updated from an older version, skips the setup.
    @MainActor
    static func hasExistingData(in context: ModelContext) -> Bool {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return count(Expense.self) + count(Income.self) + count(Account.self) + count(Loan.self)
            + count(Holding.self) + count(EMI.self) + count(InsurancePolicy.self) > 0
    }
}

/// A short guided setup shown the first time the app opens: bank accounts, cash and cards, then monthly salary,
/// then investments. Every step can be skipped, and everything can be changed later under More.
struct OnboardingView: View {
    /// Called when setup is finished or skipped.
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Holding.updatedAt, order: .reverse) private var holdings: [Holding]

    private enum Step: Int {
        case welcome, accounts, salary, investments, done

        var title: String {
            switch self {
            case .welcome: ""
            case .accounts: "Accounts & Cards"
            case .salary: "Monthly Salary"
            case .investments: "Investments"
            case .done: "All Set"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var accountKindToAdd: AccountKind?
    @State private var isAddingHolding = false
    @State private var isChoosingBackup = false
    @State private var errorMessage: String?

    @State private var salaryAmount: Decimal?
    @State private var salaryDay = 1
    @State private var salaryBank = ""

    /// Banks from the accounts added so far, for choosing where the salary arrives.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return accounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .accounts: accountsStep
                case .salary: salaryStep
                case .investments: investmentsStep
                case .done: doneStep
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .done {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip Setup") { finish() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if step != .welcome { bottomBar }
            }
        }
        .sheet(item: $accountKindToAdd) { kind in
            AccountFormView(kind: kind)
        }
        .sheet(isPresented: $isAddingHolding) {
            HoldingFormView()
        }
        .fileImporter(isPresented: $isChoosingBackup, allowedContentTypes: [.json]) { result in
            restore(from: result)
        }
        .alert("Couldn't Restore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "indianrupeesign.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Welcome")
                    .font(.largeTitle.weight(.bold))
                Text("A minute of setup makes your balances, net worth and reminders work from day one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("building.columns", "Your bank accounts, cash and cards, with real balances")
                feature("indianrupeesign.arrow.circlepath", "Salary added to your income every month")
                feature("bell.badge", "Reminders before EMIs and premiums are due")
            }
            .padding(.horizontal, 8)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    step = .accounts
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Restore from a Backup") { isChoosingBackup = true }
                    .controlSize(.large)

                Button("Skip for Now") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
        }
    }

    private var accountsStep: some View {
        List {
            Section {
                Text("Add each bank account, your cash and every credit card, with what it holds today. Entries from today on will move these balances.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !accounts.isEmpty {
                Section("Added") {
                    ForEach(accounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: account.kind.systemImage)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.body.weight(.medium))
                                if !account.detail.isEmpty {
                                    Text(account.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(account.openingBalance, format: .rupees)
                                .foregroundStyle(account.kind.isLiability ? Color.red : Color.primary)
                        }
                    }
                }
            }

            Section {
                Button("Add Bank Account", systemImage: "building.columns") { accountKindToAdd = .bank }
                if !accounts.contains(where: { $0.kind == .cash }) {
                    Button("Add Cash", systemImage: "banknote") { accountKindToAdd = .cash }
                }
                Button("Add Credit Card", systemImage: "creditcard.fill") { accountKindToAdd = .creditCard }
            } footer: {
                Text("Use the real balance from your bank app, and for a card, what you owe right now. You can skip this and add accounts later under More.")
            }
        }
    }

    private var salaryStep: some View {
        Form {
            Section {
                Text("Enter your take-home salary and the day it arrives. It is added to your income each month, so you never have to enter it. Leave it empty to skip.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            SalaryPlanFields(amount: $salaryAmount, day: $salaryDay, bankName: $salaryBank, bankChoices: bankChoices)
        }
        .onAppear {
            if salaryBank.isEmpty, let first = bankChoices.first { salaryBank = first }
        }
    }

    private var investmentsStep: some View {
        List {
            Section {
                Text("Add stocks, mutual funds, fixed deposits, gold or any loans you owe, so your net worth is complete. This is optional, and you can update values any time under More.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !holdings.isEmpty {
                Section("Added") {
                    ForEach(holdings) { holding in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(holding.name)
                                    .font(.body.weight(.medium))
                                Text(holding.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(holding.currentValue, format: .rupees)
                                .foregroundStyle(holding.kind.isDebt ? Color.red : Color.primary)
                        }
                    }
                }
            }

            Section {
                Button("Add Investment or Debt", systemImage: "plus.circle") { isAddingHolding = true }
            } footer: {
                Text("Your bank balances and card dues come from Accounts, so you don't need to add those here.")
            }
        }
    }

    private var doneStep: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.green)
                    Text("You're ready")
                        .font(.title2.weight(.bold))
                    Text("Here is what's set up. Everything can be changed under More.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Bank & Cash Accounts", value: accounts.filter { !$0.kind.isLiability }.count, format: .number)
                LabeledContent("Credit Cards", value: accounts.filter(\.kind.isLiability).count, format: .number)
                LabeledContent("Monthly Salary") {
                    if let plan = SalaryPlanStore.current {
                        Text("\(plan.amount.formatted(.rupees)) on day \(plan.day)")
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Investments & Debts", value: holdings.count, format: .number)
            }

            Section {
                Label("Add loans to friends, EMIs and insurance under More. Reminders for due EMIs and premiums are switched on once you allow notifications.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Bottom bar and actions

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Back") { goBack() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Button {
                advance()
            } label: {
                Text(step == .done ? "Start Using the App" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.bar)
    }

    private func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    private func advance() {
        if step == .salary { saveSalary() }
        if step == .done {
            finish()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    /// Saves the salary, and adds this month's if its day has already passed.
    private func saveSalary() {
        guard let salaryAmount, salaryAmount > 0 else { return }
        SalaryPlanStore.save(SalaryPlan(amount: salaryAmount, day: salaryDay, bankName: salaryBank))
        SalaryPlanStore.postDue(in: modelContext)
    }

    private func finish() {
        try? modelContext.save()
        onFinish()
    }

    private func restore(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try BackupManager.restore(data, into: modelContext)
                onFinish()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    OnboardingView {}
        .modelContainer(for: [Account.self, Holding.self, Income.self, Expense.self], inMemory: true)
}
