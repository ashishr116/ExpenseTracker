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

_Empty. Add items here._

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
- Notes: Tested in the simulator: points 1, 2, 3, 4. Point 5 tested for UPI equal split only. Nothing committed yet. Ten earlier commits are not pushed.

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
