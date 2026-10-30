# Views (screens and forms)

## Daily, Monthly and Budget tabs
- **`DailyView.swift`**: every expense, income, loan and card bill payment for one day, with totals.
- **`MonthlyView.swift`**: a month's entries grouped by day, with income, spent, pending and balance.
- **`BudgetView.swift`**: the Budget tab. A switcher at the top picks one of five pages and builds only that one. Holds the Summary page and the income and expense breakdowns.
- **`BudgetInsightViews.swift`**: the other Budget pages: Fixed vs variable, Bank vs credit card vs cash, the category pie chart, and Saved this month.

## Entry forms
- **`ExpenseFormView.swift`**: add or edit an expense, with category (and a custom name under Other), payment type and saved-card chips.
- **`IncomeFormView.swift`**: add or edit income.
- **`LoanFormView.swift`**: lend money to a friend by cash, your card (one-off or EMI), or a personal loan. Instalments, monthly reminder, already-paid months, and sending by message or WhatsApp.
- **`RepaymentFormView.swift`**: record a full or part payment from a friend.
- **`EMIFormView.swift`**: add or edit an EMI plan, including how many instalments are already paid.
- **`InsuranceFormView.swift`**: add or edit an insurance plan, including premiums already paid.
- **`HoldingFormView.swift`**: add or edit an investment, savings balance or debt.
- **`AccountFormView.swift`**: add or edit a bank, cash or credit-card account.
- **`TransferFormView.swift`**: move money between accounts or pay a card bill.
- **`CardFormView.swift`**: add or edit a saved card with full details.

## Lists and detail screens
- **`LoansView.swift`**: loans grouped by friend, outstanding and repaid, with swipe actions and the reminder flow.
- **`EMIsView.swift`**: EMI plans with progress and what is left to pay.
- **`InsuranceView.swift`**: insurance plans with premiums and upcoming dues.
- **`PortfolioView.swift`**: net worth: investments, savings, debts, accounts, money friends owe you, and EMIs still to pay.
- **`AccountsView.swift`**: all accounts with balances and totals. Also the line row used in account histories and the screen for entries not linked to any account.
- **`AccountDetailView.swift`**: one account's movements with running balances, Pay Bill, and the screen for matching your real balance. For a credit card, splits mine from lent to friends.
- **`CardsView.swift`**: saved cards, masked until you unlock with Face ID.
- **`MoreView.swift`**: the More tab, linking to everything else.

## Money setup and tools
- **`OnboardingView.swift`**: the first-launch setup for accounts, cards, salary and investments.
- **`SalaryPlanView.swift`**: the monthly salary fields and the screen to change or switch them off.
- **`MonthlySavingsView.swift`**: the record of month-end leftovers moved to savings, and where they go.
- **`DataBackupView.swift`**: export CSV, save a backup, and restore.

## Reminders
- **`PaymentDueSheet.swift`**: the pop-up for EMIs and premiums due today, and the logic for when to show it.
- **`NotificationStatusSection.swift`**: shows whether reminders are allowed, how many are scheduled, and the next one.

## Launch
- **`SplashView.swift`**: the animated rupee shown on launch.
