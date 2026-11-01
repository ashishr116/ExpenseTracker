# ExpenseTracker work list

Kept by the **orchestrator**. The owner adds lines under **Queue**. See `.claude/WORKFLOW.md` for the loop.

Item format:

```
### W-000 Title
- Use case: ...
- Acceptance criteria: 1. ... 2. ...
- Money impact: accounts / cash left / spending / net worth / card balance (or "none")
- Status: Queue | In progress | Ready for you | Done
- Rounds: 0
- Notes / tester verdict / commit:
```

## Queue

### W-002 Consistent bank names on screen
- Use case: bank chips and labels mix "ICICI BANK" with "HDFC Bank", "SBI", "Axis Bank".
- Acceptance criteria: 1. Every bank chip and bank label in the expense, loan, split, borrowed, repayment and investment forms shows one style. 2. Stored values and matching do not change (an account, card or entry still links to the same bank). 3. Nothing else on screen changes.
- Money impact: none.
- Status: In progress (round 1 fixes done by dev, tester re-check running)
- Rounds: 1
- Notes: Dev added `BankName.display(_:)` (display only; stored values and matching unchanged) and applied it across chips, pickers, row subtitles, Account/PaymentCard descriptions, ledger lines, reminder and PDF text. About 30 files changed. Tester round 1: criteria 2 and 3 passed; criterion 1 failed in two places (Loan form Paid From picker, Budget Expenses By Bank & Card subtitle). Dev fixed both and also the Monthly Savings Savings Account row and footer. Not committed.

### W-003 Accounts "Net" label
- Use case: the Accounts "Net" line leaves out EMIs, what friends owe you and what you owe friends, so it differs from Net Worth.
- Acceptance criteria: 1. The line reads "Net (accounts only)". 2. A short footnote says Net Worth on the Investments screen includes loans, borrowed money and EMIs. 3. The numbers do not change.
- Money impact: none.
- Status: Queue
- Rounds: 0

### W-004 One shared month-figures helper
- Use case: Daily, Monthly, Budget, Recap and the month-end savings sweep each work out "leftover" with their own formula. They must agree.
- Acceptance criteria: 1. One helper computes the month's income, spending, lent, repaid, borrowed, paid back, card bills paid and cash left, and all five places use it. 2. No visible change for existing data. 3. For the same month the Monthly cash left, Budget remaining and the savings sweep leftover agree, including borrowed money, a card purchase, a card bill payment and a loan.
- Money impact: none by design. The tester compares all five before and after.
- Status: Queue
- Rounds: 0

### W-005 Withdraw or sell an investment into an account
- Use case: money coming back from an investment into a bank or cash is not recorded.
- Acceptance criteria: 1. A "Withdraw" action on a holding takes an amount, an account to credit and a date. 2. That account goes up by the amount (a one-sided transfer shown as "Withdrawn"). 3. The holding's current value and invested amount go down by the amount, and it cannot withdraw more than its value. 4. Net worth is unchanged by the withdrawal itself. 5. It is not income and not spending.
- Money impact: account up, holding down, net worth unchanged, cash left unchanged.
- Status: Queue
- Rounds: 0

### W-006 CSV export for borrowed money
- Use case: borrowed and repaid amounts are missing from the CSV export.
- Acceptance criteria: 1. The export has a borrowed table (friend, amount, date, bank, due date, repaid date, note) and a payments table (friend, amount, date, bank). 2. Existing tables are unchanged. 3. Rows match what is on the Borrowed screen.
- Money impact: none.
- Status: Queue
- Rounds: 0

### W-007 Test reminder button
- Use case: card bill and borrowing reminders cannot be tapped in the simulator and are hard to check.
- Acceptance criteria: 1. A button in the notification settings schedules a test reminder in about 10 seconds, for a chosen card or debt. 2. Its text shows the real amount and friends as the real reminder would. 3. Tapping it opens that card (or the debt).
- Money impact: none.
- Status: Queue
- Rounds: 0

## In progress

_None._

## Ready for you (verify on your phone)

### W-001 Batch awaiting your phone check (built and tested in the simulator, not committed)
- Use case: money-trail fixes and recent screens, all built since commit `cfda1ae`.
- Phone checklist:
  1. **Friend's card share, you paid.** Loans, open the friend, tap "I Paid Card Bill". Save. Expect your bank down once, the card's friend share gone, and the friend owing you a cash loan. Net worth unchanged. (The extra "Record Payment to Card Account" toggle is gone.)
  2. **Borrowed money.** More, Borrowed, add ₹2,000 into a bank and pay ₹500 back. Expect Daily, Monthly and Budget Summary to show "Borrowed from Friends" and "Repaid to Friends", and Remaining to move by +2,000 and -500.
  3. **Investment paid from an account.** Add an investment with an invested amount and choose "Paid From". Expect that account down by the amount and net worth unchanged.
  4. **Budget income.** Budget, Summary shows "Income Sources". "Fixed Expenses" page shows Income, Fixed, Variable and Left After Expenses. Bank/Card shows "Money In". Chart shows income by source.
  5. **Split a bill.** Daily, +, Split a Bill. Pay ₹900 by UPI, share equally with one friend. Expect your share as an expense and the friend's share as a loan "Split: ...". Try "A Friend" paid, "I Owe Them": expect a debt under Borrowed.
  6. **Also in this batch (your earlier changes, read only by the agents):** bank names shown in capitals, stricter card matching, cards getting accounts automatically, upcoming rent shown as fixed commitments in Budget, EMIs listed in Recurring Expenses.
- Money impact: see the list above.
- Status: Ready for you
- Notes: Tested in the simulator: points 1, 2, 3, 4. Point 5 tested for UPI equal split only. Committed and pushed as `225c3bf` at the owner's request, before the phone check. Still needs the owner's phone verification. Any problem found goes back to dev as a fix.

## Done

| Id | Item | Commit |
|---|---|---|
| , | Items from before this workflow (goals, recurring, limits, recap, card bills, borrowed money, billed and unbilled, and more) are in `git log`. | , |

## Ideas (not approved, the orchestrator must not start these)

- Show bank names in one consistent style in the chips (capitals now mix with "HDFC Bank", "SBI").
- Rename Accounts "Net" to "Net (accounts only)".
- One shared "month figures" helper so Daily, Monthly, Budget, Recap and the savings sweep cannot disagree.
- A People screen: one page per friend with loans, borrowed money, splits and one net figure.
- A "Money check" card on Accounts for unlinked entries and balance mismatches.
- Credit limit and utilisation per card (warn over about 30%).
- "Left this month" and today's spend in Budget.
- Net worth over time (monthly line chart).
- Face ID app lock.
- Selling or withdrawing an investment back into an account.
- A "test reminder" button in Settings for card and borrowing notifications.
- CSV export for borrowed money.
