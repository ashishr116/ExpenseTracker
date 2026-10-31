# ExpenseTracker

A personal finance app for iPhone, built for Indian rupees. It tracks daily spending, income, bank accounts and credit cards, EMIs, insurance premiums, investments, and money lent to friends. Everything is stored on the device. There is no server and no account.

Built with SwiftUI and SwiftData. Requires the iOS version set in the Xcode project (currently iOS 27).

## What it does

| Area | What you can do |
|---|---|
| **Daily / Monthly** | See every expense, income, loan and card bill payment for a day or a month, with totals. |
| **Budget** | Summary, monthly limits per category, fixed vs variable spending, bank vs credit card vs cash, a category pie chart, and how much you saved. Each page is built only when opened. |
| **Category limits** | Set the most you want to spend each month on a category, such as food. The Limits page shows how much is used, and you get a notice at 80% and again if you go over. |
| **Accounts** | Bank accounts, cash and credit cards with balances worked out from your entries. Transfers, card bill payments, and "match real balance" adjustments. |
| **EMIs** | Instalment plans. Each month is a real expense that counts only once you record it as paid. |
| **Insurance** | Health and term plans, with premiums handled the same way as EMIs. |
| **Loans** | Money lent to friends: cash loans, friends using your card (one-off or as an EMI), and personal loans in your name. Part payments, monthly EMI reminders, and reminders by message or WhatsApp. |
| **Recurring expenses** | Rent, the maid, subscriptions. Enter each once with its day of the month, and the app adds the expense on that day. Pause, end or change it any time. |
| **Goals** | Save up for something you want to buy. Say what it costs and what you can spare each month, or the date you want it by, and the app works out the other. The monthly amount is set aside from what is left over at month end. The money stays in your savings and is only marked for the goal. |
| **Net worth** | Investments, savings and debts, plus what friends owe you. |
| **Saved Cards** | Card details behind Face ID. |
| **Backup** | CSV export for spreadsheets, and a full JSON backup that can be saved to iCloud Drive and restored. |
| **Reminders** | Local notifications before, on and after each EMI or premium due date. A pop-up on the due date lets you record the payment. |

## Money rules the app follows

- **Spending counts when paid.** An EMI or premium that has not been recorded as paid is a commitment, not spending.
- **Transfers are not income or spending.** Moving money between your accounts, or paying a card bill, changes balances only.
- **Credit cards are debts.** A card's balance is what you owe. Paying the bill lowers it.
- **Loans on your card or in your name stay out of cash flow and net worth.** If a friend uses your card or takes a personal loan in your name, they owe the bank or card, not your cash. These appear only under Loans, and under "Lent to Friends" on the card.
- **Cash loans** do count: lending lowers the account it was paid from, and repayments raise the account they arrive in.
- **Amounts are stored in paise** (whole numbers) to avoid rounding errors.

## Project layout

```
ExpenseTracker/
├── ExpenseTracker/            App source
│   ├── ExpenseTrackerApp.swift   App entry, database setup, launch tasks
│   ├── ContentView.swift         Tab bar and the + menu
│   ├── Models/                   SwiftData records and their rules
│   ├── Helpers/                  Logic with no screen: ledger, reminders, backup, export
│   ├── Views/                    Screens and forms
│   │   └── Components/           Small reusable pieces
│   └── Assets.xcassets
├── ExpenseTracker.xcodeproj
├── Scripts/GenerateAppIcon.swift  Draws the app icon
└── docs/                          What each file does
```

File-by-file notes:

- [App entry and tabs](docs/App.md)
- [Models](docs/Models.md)
- [Helpers (backend logic)](docs/Helpers.md)
- [Views (screens and forms)](docs/Views.md)
- [Components (reusable pieces)](docs/Components.md)

## Running it

1. Open `ExpenseTracker.xcodeproj` in Xcode.
2. Choose an iPhone simulator or a device and press Run.
3. On first launch a short setup asks for your accounts, cards, salary and investments. Every step can be skipped and changed later under **More**.

## Privacy

- All data stays on the device. Backups go only where you save them.
- Only the last four digits of a card are used for matching entries. The full number, expiry and CVV are kept only for the Saved Cards screen, shown after Face ID, and are never written to a backup or CSV file.
- The full number, expiry and CVV are kept in the iPhone's Keychain, not in the app's database. They are available only while the phone is unlocked and only on this phone, so they are not copied to a new phone. Re-enter them there if needed.

## Known limits

- Custom expense categories count under "Other" in budget views.
- A WhatsApp reminder is recorded as sent when WhatsApp opens, because WhatsApp cannot confirm it was sent.
- Notifications on a real device fire at 9am. They have been checked in the simulator only.
