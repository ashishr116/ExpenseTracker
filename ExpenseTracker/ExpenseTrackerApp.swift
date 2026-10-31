//
//  ExpenseTrackerApp.swift
//  ExpenseTracker
//
//  Created by Ashish on 29/10/26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct ExpenseTrackerApp: App {
    init() {
        // Show reminders as banners even while the app is open.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    /// On-device SwiftData store for all expenses, income, loans, EMIs, investments, insurance and saved cards.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            Income.self,
            Loan.self,
            LoanRepayment.self,
            EMI.self,
            Holding.self,
            InsurancePolicy.self,
            PaymentCard.self,
            MonthlySavings.self,
            Account.self,
            Transfer.self,
            Goal.self,
            GoalContribution.self,
            RecurringExpense.self,
            CategoryBudget.self,
            Borrowing.self,
            BorrowingPayment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Shows the splash animation on top of the Daily view, then fades it away.
/// ContentView loads underneath so it's ready the moment the splash disappears.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSplash = true
    @AppStorage(Onboarding.completedKey) private var onboardingCompleted = false
    /// The first-launch setup is waiting to be shown once the splash is gone.
    @State private var needsOnboarding = false

    /// Shown over everything on the first launch of a fresh install, after the splash.
    private var isShowingOnboarding: Bool { needsOnboarding && !isShowingSplash && !onboardingCompleted }

    var body: some View {
        ZStack {
            ContentView()
            if isShowingSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isShowingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // Upgrade data saved by earlier versions before anything is totalled.
        .task {
            DataMigrations.run(in: modelContext)
            // Credit cards added under Accounts before this existed get their saved card now.
            CardSync.sync(in: modelContext)
            // Monthly payments are added before the month-end totals look at the finished months.
            RecurringExpensePoster.run(in: modelContext)
            SavingsSweep.run(in: modelContext)
            GoalAllocator.run(in: modelContext)
            SalaryPlanStore.postDue(in: modelContext)
            await BudgetAlerts.check(in: modelContext)
            await RecapReminder.scheduleIfNeeded()
            await CardBillReminder.reschedule(in: modelContext)
            await BorrowingReminder.reschedule(in: modelContext)
            BackupNudge.recordFirstSeen()
            await BackupNudge.scheduleReminder()

            // A fresh install gets the guided setup. An install that already has data skips it.
            if !onboardingCompleted {
                if Onboarding.hasExistingData(in: modelContext) {
                    onboardingCompleted = true
                } else {
                    needsOnboarding = true
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { isShowingOnboarding }, set: { _ in })) {
            OnboardingView {
                onboardingCompleted = true
                needsOnboarding = false
            }
        }
        // A new month may have started while the app was in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                RecurringExpensePoster.run(in: modelContext)
                Task {
                    await BudgetAlerts.check(in: modelContext)
                    // Who owes what on a card may have changed since the reminders were set.
                    await CardBillReminder.reschedule(in: modelContext)
                    await BorrowingReminder.reschedule(in: modelContext)
                }
                SavingsSweep.run(in: modelContext)
                GoalAllocator.run(in: modelContext)
                SalaryPlanStore.postDue(in: modelContext)
            } else {
                // SwiftData saves a few seconds after a change. Save now, so leaving the app never loses an entry.
                try? modelContext.save()
            }
        }
        // Pops up due EMIs and premiums (and schedules due-date notifications) once the splash is gone.
        // Held back during the setup, so the notification prompt doesn't appear on top of it.
        .paymentDueReminders(isEnabled: !isShowingSplash && !isShowingOnboarding)
    }
}
