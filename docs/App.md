# App entry and tabs

## `ExpenseTrackerApp.swift`
The app entry point.
- Creates the SwiftData database with every record type (expenses, income, loans, repayments, EMIs, holdings, insurance, cards, monthly savings, accounts, transfers).
- Sets the notification delegate so reminders show while the app is open.
- Shows the splash animation over the Daily view, then the first-launch setup if it has not been done.
- On launch runs one-off data upgrades, syncs credit-card accounts into Saved Cards, adds the month-end savings, posts the monthly salary, and keeps reminders up to date.
- Saves the database whenever the app leaves the foreground so nothing is lost.

## `ContentView.swift`
The tab bar: **Daily**, **Monthly**, **Budget** and **More**. Adds the **+** menu (Expense, Income, Loan) and the sheets it opens. Shows a badge on More when EMIs or premiums are due or overdue.

## `Info.plist`
Holds the Face ID usage text and the launch screen colour. Other settings are in the Xcode project.
