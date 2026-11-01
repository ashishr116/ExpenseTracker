# Helpers (backend logic)

Code with no screen of its own.

## `AccountLedger.swift`
Works out each account's balance from the entries. Spending lowers a bank or cash account and raises what a card owes. Income, cash loans, repayments and transfers move balances. Finds entries that match no account. Also tracks what friends owe on each credit card, kept apart from your own balance. An EMI instalment or premium paid by credit card is on the card from its billing date, because the bank bills it whether or not you have marked it paid. Any other EMI or premium moves money when you mark it paid. When a friend pays you for a purchase on your card, the money raises your account and their share of the card becomes yours, so the card's total stays the same until you pay the bill. A friend's loan on a card that isn't one of your accounts is listed with the entries not linked to any account.

## `BorrowingReminder.swift`
Reminders to you the day before and on the day money you borrowed from a friend is due back. Rebuilt whenever the app opens or a debt changes.

## Borrowing messages
`BorrowingMessage` (in `BorrowingReminder.swift`) writes the text to a friend you borrowed from: a confirmation when you receive money, and a payment update with the amount just paid, every payment so far and the balance. The statement PDF for a friend shows money you borrowed from them as a short ledger: totals (borrowed, paid back, balance left) and a table of dates, details, amounts and the balance after each line, covering every borrowing and every part payment.

## `PaymentReminder.swift`
Schedules local notifications for EMIs and premiums: the day before, on the due date, and again after it is overdue. Also schedules the repeating monthly reminder for a friend's card or personal-loan EMI.

## `NotificationDelegate.swift`
Lets reminders appear as a banner while the app is open. Without it iOS drops them.

## `LoanReminder.swift`
Builds the reminder message for a friend: the full amount for ordinary loans, or just the EMI for instalment loans. Also builds the WhatsApp link for sending it.

## `BackupManager.swift`
Saves everything to one JSON file and restores it. Records that point at each other are linked by position. Full card numbers and CVV are never written.

## `CSVExporter.swift`
Writes each list to its own CSV file for spreadsheets, guarding against spreadsheet formulas. Also holds the share-sheet helper.

## `CardSync.swift`
Keeps Saved Cards in step with credit-card accounts, so a card added under Accounts can be chosen when adding an expense. `saveCard` does the other direction for forms: a card picked on the EMI, insurance, monthly payment (and similar) forms is saved, and a credit card gets its account, so it shows under Accounts. The first time a credit card is saved this way, the form asks for its bill day.

## `CardBillForecast.swift`
Works out which credit card bills fall due in a month, your own part only, for the cash forecast in Budget and Monthly. The bill already generated is counted in the month of its due date (an overdue unpaid one counts this month). What has been spent since is counted in the month the next bill falls due, labelled "unbilled so far". A card needs its bill day set. EMIs and premiums already on such a card are left out of the Pending figure, because the card's bill already has them.

## `SalaryPlan.swift`
Remembers your monthly salary, day and bank, and adds it to income each month, unless you already entered that month's salary yourself. It also adds the next twelve months ahead of time, dated on their salary day, so Budget and Monthly show them. Those show as "Expected" until the day arrives, and don't touch account balances until then. Changing or stopping the plan removes the coming months it added, and the plan adds them again with the new amount.

## `DataMigrations.swift`
One-off upgrades for data saved by earlier versions. Safe to run on every launch.

## `MonthCashView.swift`
Works out a month in terms of real cash: spending in cash, UPI and on a debit card, card bills paid, spending on credit cards (card by card, including EMIs and premiums on a card from their billing date), and the cash left. A friend's card share paid to you counts as cash in. Used by the Budget summary and the Monthly screen. It adds to the existing totals and changes none of them.

## `BackupNudge.swift`
Reminds you to back up after 30 days without one. Counts from your last backup, or from the first time the app opened with this feature if you've never made one. Works out whether the Daily screen banner shows, lets "Later" hide it for a week, and schedules a notification for when the 30 days are up, or weekly once they have passed.

## `PaymentDetails.swift`
Your UPI ID, the name shown with it, and whether a card's last 4 digits are shown, kept in the app's settings. Works out the "How to pay" lines for a set of loans: the UPI ID for cash, transfer and personal loans, and the card's name and digits for loans on your card. Used by reminder messages and PDFs.

## `LoanStatementPDF.swift`
Makes PDFs that can be shared. A summary of every loan to a friend plus your own EMIs, for your records, and a statement for one friend with only their loans, the payments they made, and how to pay. Lays text out over as many A4 pages as it needs.

## `CardBill.swift`
- `CardBill.friendShares`: works out what each friend owes towards a credit card's bill, using the EMI for an instalment loan and the amount still owed for any other loan.
- `CardBill.statement` and `CardBill.cycle`: split a card's total into the latest bill (Billed) and the spending since (Unbilled), and find the span of days of each bill.
- `CardBillReminder`: schedules notifications 5, 3 and 1 days before each credit card's next two due dates. Each says what your bill is and which friends to remind, and is skipped when the bill is already paid. Tapping one opens that card. It rebuilds them whenever the app opens or a card changes.
- `NotificationRouter` (in `NotificationDelegate.swift`): passes a tapped reminder's card to the screen that opens it.

## `MonthlyRecap.swift`
Works out a month's recap: income, spending, what was kept, the comparison with the month before, the top three categories, the biggest expense, the category that rose most, fixed vs variable spending, limits that were exceeded, money set aside for goals, the daily average and no-spend days. Also writes a one-paragraph summary, used when sharing the recap and read aloud by VoiceOver in place of the chart. `RecapReminder` schedules the notification on the 1st of each month.

## `CardVault.swift`
Stores each card's full number, expiry and CVV in the iPhone's Keychain, available only while the phone is unlocked and only on this phone. Also removes the items of cards that were deleted.

## `BiometricAuth.swift`
Face ID check, falling back to the device passcode.

## `ContactPickerPresenter.swift`
Shows the system contact picker directly through UIKit, so choosing a contact does not close the form underneath. Needs no Contacts permission.

## `Formatting.swift`
Money helpers: converting between rupees and paise, the rupee display format, and date text for file names.

## `Brand.swift`
Brand colours and the list of popular banks used for one-tap selection.
