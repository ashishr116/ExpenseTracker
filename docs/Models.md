# Models

SwiftData records saved on the device. Money is stored as whole paise and read back as `Decimal`.

## `Expense.swift`
- `AccountType`: how something was paid (cash, credit card, debit card, UPI).
- `ExpenseCategory`: the built-in categories, each with an icon and a fixed/variable flag.
- `Expense`: one expense. Links to the EMI or insurance policy that created it, if any. `paidAt` records when an EMI or premium was actually paid, and an unpaid one is "planned" and not counted as spending. Also holds an optional custom category name.

## `Income.swift`
`Income` and `IncomeSource`: money received, such as salary, with the bank it arrived in.

## `Account.swift`
- `AccountKind`: bank, cash or credit card.
- `Account`: a place money sits in, with an opening balance and date. Entries find their account by bank name and card digits.
- `Transfer`: money moving between two accounts, a card bill payment, or a one-sided adjustment made when matching a real balance. Not income or spending.

## `EMI.swift`
`EMI`: an instalment plan. Owns one expense per month. Tracks paid, pending, due-today and overdue instalments, and the principal still outstanding. Regenerating after an edit keeps instalments already paid.

## `InsurancePolicy.swift`
`InsurancePolicy`: a health or term plan. Works like an EMI: one expense per premium, paid or pending, with due and overdue tracking.

## `Loan.swift`
- `LoanMethod`: cash/transfer, used my card, or personal loan in my name.
- `Loan`: money lent to a friend. Supports part payments, an instalment count and amount (for a personal loan or a friend's EMI on your card), and a monthly reminder day.
- `LoanRepayment`: one payment received from the friend. Only repayments of cash loans count as income.

## `Goal.swift`
- `Goal`: something you are saving for, with a target, a monthly amount, an optional finish date, and when it was bought. Works out progress, the month it will be ready, and how far behind plan it is.
- `GoalContribution`: one amount set aside, automatically at month end or added by hand.
- `GoalAllocator`: at launch, goes through each finished month and sets aside every goal's monthly amount from that month's leftover, oldest goal first. A month with less left over sets aside less, and a month is never counted twice. The money is only marked for the goal. No balance or net worth changes.

## `Holding.swift`
`Holding` and `HoldingKind`: an investment, savings balance or debt entered by hand for net worth.

## `PaymentCard.swift`
`PaymentCard`: a saved card with optional full number, expiry and CVV, shown only after Face ID. The full details are stored in the Keychain (see `CardVault`), and the database holds only the last four digits and an id that points to them. Cards saved by earlier versions are moved to the Keychain on the next launch.

## `MonthlySavings.swift`
- `MonthlySavings`: one record per finished month, noting the leftover and how much was moved to savings.
- `SavingsSweep`: moves each finished month's leftover into the chosen savings account, as a transfer when accounts exist, or into a savings holding otherwise.
