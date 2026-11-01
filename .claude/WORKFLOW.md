# ExpenseTracker: team workflow and shared rules

Every agent reads this file first. The roles are `orchestrator`, `dev` and `tester`. The owner verifies on a real phone.

## The loop

1. The owner adds items to `WORKLIST.md` (Queue). Each item has a use case and acceptance criteria.
2. **orchestrator** takes one item, briefs **dev**, then briefs **tester** with the same criteria.
3. **dev** builds the use case. It does not test on the simulator and does not commit.
4. **tester** tests only. It does not edit app code. It returns PASS or FAIL for each criterion, with evidence.
5. FAIL goes back to dev with the tester's findings. Three failed rounds on one item go to the owner.
6. PASS moves the item to "Ready for you" with a phone checklist. The orchestrator then stops and waits.
7. The owner verifies on the phone and says "verified". Only then: docs updated, committed, pushed, item moved to Done.
8. If the owner reports a problem, the item goes back to dev with the owner's words. Nothing is pushed.

Subagents cannot start other subagents. So the orchestrator must be the main session: run Claude Code with `--agent orchestrator`, or in Xcode say "act as orchestrator and run the list" and the main session follows `.claude/agents/orchestrator.md`.

## Project facts

- Project root: `/Users/aadvik/Desktop/ExpenseTracker`. App sources: `ExpenseTracker/ExpenseTracker/`. SwiftUI + SwiftData, iOS, amounts in Indian rupees.
- Scheme `ExpenseTracker`. Bundle id `com.self.Budget.ExpenseTracker`.
- Prefer the `xcode-tools` MCP tools: `BuildProject`, `XcodeRefreshCodeIssuesInFile`, `DocumentationSearch`. Avoid `ls` and `find` for basic project facts.
- Xcode groups are filesystem-synchronized. After adding or deleting a file, the first build may fail with "cannot find X in scope". Build again.
- Style: PascalCase types, camelCase members, 4 spaces, async/await instead of Combine, no force unwraps, comments for non-obvious logic. Match the surrounding file.
- Keep changes to the item's scope. No unrelated refactors.
- The app is in development. Do not spend effort on migrating or protecting old data.

## Money rules (do not break these)

- Money is stored as `Int64` paise (`Money.paise(from:)`, `Money.amount(fromPaise:)`).
- Spending counts when paid. Exceptions: card purchases count at purchase time for categories, limits, recap and charts. Cash left drops only when the card bill is paid.
- Transfers and card bill payments are not spending or income. Investments paid from an account are a one-sided transfer.
- A friend's purchase or EMI on your card is a `Loan` with `method == .card`. It stays out of cash flow. A friend's repayment of a card loan settles the card and is NOT income and does not add to cash.
- "I paid their card share" (Loans, "I Paid Card Bill"; Pay Bill with the friend switch) must lower the paying account exactly ONCE: a cash loan from that account plus a repayment on the card loan. Never add a second transfer for the same money.
- A friend's EMI on your card bills one instalment a month (`Loan.cardCharges`). Your own EMI or premium paid by credit card is on the card from its billing date, paid or not.
- Money borrowed from a friend (`Borrowing`, `BorrowingPayment`) raises or lowers the account it landed in, is a debt in net worth, and is part of cash left on Daily, Monthly, Budget, Saved, Recap and the month-end savings sweep. It is not income.
- Any new money-moving feature must say what it does to: account balances, cash left, spending totals, net worth, and card balance. State this in the brief and verify it in the test.

## Testing method (tester only)

- Simulator: "iPhone 18 Pro", UUID `323FC9B2-DC56-48B9-8F1F-5BC0267CE439`. Never test on the real iPhone.
- Switch destination with `XcodeSwitchRunDestination` and the parameter `displayTitle` (for example `"iPhone 18 Pro"`). When done, switch back to `"iPhone"`.
- Start a `DeviceInteractionStartSession`, drive the UI with `DeviceInteractionSynthesize`. Taps lag: wait 2 to 3 seconds and read a screenshot after every step. Banners belong to SpringBoard.
- Plant data with sqlite3 in the app container: `$(xcrun simctl get_app_container 323FC9B2-DC56-48B9-8F1F-5BC0267CE439 com.self.Budget.ExpenseTracker data)/Library/Application Support/default.store`. Terminate the app before editing. Core Data dates are Unix seconds minus 978307200. Names start with `ZTEST` so they are easy to remove.
- Record the balances BEFORE and AFTER each money flow (Accounts, Net Worth, the affected list) and compare them with the expected arithmetic.
- Remove all test data you planted, end the session, and report that you did.
- Typing: `sender keyboard kbd <text>` must be the last command in a chain.

## Commits, docs, push (orchestrator only, after "verified")

- Update `README.md` and the matching `docs/*.md` file (`Models.md`, `Helpers.md`, `Views.md`, `Components.md`, `App.md`) for every file or behaviour that changed.
- Stage with `git add -A && git reset -q ExpenseTracker.xcodeproj/xcuserdata`.
- Commit message: a short imperative summary, then a blank line, then `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Push only after the owner says "verified" (or "push"). Offer a version tag after a set of items.
