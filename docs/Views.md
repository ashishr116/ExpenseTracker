# Views (screens and forms)

## Daily, Monthly and Budget tabs
- **`DailyView.swift`**: every expense, income, loan and card bill payment for one day, with totals. Shows the backup reminder banner when one is due, and opens the backup screen from it.
- **`BackupNudgeBanner.swift`**: the "Back up your data" note, with Back Up Now and Later buttons.
- **`MonthlyView.swift`**: a month's entries grouped by day, with income, spent, pending and balance.
- **`BudgetView.swift`**: the Budget tab. A switcher at the top picks one of five pages and builds only that one. Holds the Summary page and the income and expense breakdowns.
- **`BudgetInsightViews.swift`**: the other Budget pages: Recap (opens with a bar chart of income, spending, last month's spending and what was kept), Limits, Fixed vs variable, Bank vs credit card vs cash, the category pie chart, and Saved this month.
- **`BudgetLimitFormView.swift`**: set, change or remove a category's monthly limit.

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
- **`BillDatesSection.swift`**: the "bill generated on" and "payment due on" pickers, shared by the Accounts form and the Saved Cards form.
- **`CardsView.swift`**: saved cards, masked until you unlock with Face ID.
- **`MoreView.swift`**: the More tab, linking to everything else.

## Recurring expenses
- **`RecurringExpensesView.swift`**: your monthly payments with the total per month, each one's next payment day, and swipe to delete.
- **`RecurringExpenseFormView.swift`**: add or edit a monthly payment, with a preview of when the first one is added, an optional end date, and a pause switch.

## Goals
- **`GoalsView.swift`**: your goals with progress, how much is set aside, and whether each is on track or behind.
- **`GoalFormView.swift`**: add or edit a goal, planning by monthly amount or by finish date. Also the sheet for adding money to a goal by hand.
- **`GoalDetailView.swift`**: one goal's progress, plan and history, with Add Money, I Bought It (which can open an expense form with the price filled in), Edit and Delete.

## Cash and purchases
- **`SpendingBasisPicker.swift`**: the Cash | Purchases switch at the top of the Monthly and Budget summaries, and the setting behind it. It only changes the main Spent and Balance figures.

## Payment details
- **`PaymentDetailsView.swift`**: where you enter your UPI ID and choose whether card digits are shown, with a live preview of the "How to pay" lines friends will see.

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
