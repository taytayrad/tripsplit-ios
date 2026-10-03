# Money rules

The math every balance, split, and payment must follow. Code that touches money is correct only if it passes every **golden case** below. Turn each one into a test before writing the code it covers.

Behavior and copy live in [`prd.md`](../prd.md). This file is the math. Terms are defined in [`glossary.md`](glossary.md).

## Units

- All money is **integer cents** (`amount_cents`, `share_cents`). Never floats. Format to dollars only at the UI edge.
- Amounts are USD and strictly positive (`> 0`).
- Percent inputs allow two decimals (`33.33`). Share counts are whole numbers ≥ 0.

## Splits → saved shares

A split turns an expense amount into one `share_cents` per included member. Shares are computed once at save and **stored**. Balance math reads only stored shares, never the split inputs.

Invariant: `sum(share_cents) == amount_cents` for every expense.

**Remainder rule (all kinds):** compute each included person's share with `floor`, then add every leftover cent to the **last included person**. "Last" means last in trip member order (the order members joined the trip).

| Kind | Raw share for person *i* | Included when | Valid when |
|---|---|---|---|
| `equal` | `floor(amount / n)` | checked; at least one checked | always |
| `exact` | the entered cents | entered > 0 | entries sum to `amount` exactly |
| `percent` | `floor(amount × pct_i / 100)` | pct > 0 | percents sum to `100.00` exactly |
| `shares` | `floor(amount × count_i / total_count)` | count > 0 | total count > 0 |

`exact` has no remainder. For the others the remainder is `amount − sum(raw shares)`, always ≥ 0.

Save is unavailable until the split is valid.

## Balances

For one trip, from your point of view:

```
net = paid − shares − payments_received + payments_made
```

- `paid`: sum of `amount_cents` of expenses where you are the payer
- `shares`: sum of your `share_cents` across the trip's expenses
- `payments_received`: payments where you are the payee
- `payments_made`: payments where you are the payer

Positive means you are owed. Negative means you owe. Receiving a payment and making one both move you toward $0 (golden case M9).

### Pairwise balance (the building block)

The balance between you and person X on one trip:

```
pair(you, X) =   Σ X's share  of expenses you paid
               − Σ your share of expenses X paid
               − Σ payments X made to you
               + Σ payments you made to X
```

Positive means X owes you.

- Your trip net equals the sum of `pair(you, X)` over every other person on the trip.
- **No debt simplification.** If you owe Alex and Alex owes Jordan, you still owe Alex. Balances are always between the two people who shared the expense or payment.

### Rolling up

- **Combined balance** with X = Σ `pair(you, X)` over every trip you share with X that is **not deleted**.
- **Header total** = Σ combined balances = Σ your trip nets over non-deleted trips.
- **Deleted trips** contribute nothing anywhere. Undeleting restores their contribution exactly, because the stored rows were never changed.
- **Removed members:** with *keep*, their pairwise balances still count and they can still be paid or recorded. With *wipe*, see below.

### Who appears where

- A trip card shows your trip net in words.
- Your Balance lists each person whose combined balance is non-zero, under "You owe" (negative) or "Owes you" (positive), unsigned.
- Settled trips: hidden from the trips list only when the trip has dates, the end date has passed, and your trip net is $0.

## Payments

### Allocation (paying or recording across trips)

When you log amount `A` with person X, `A` must be greater than 0 and no more than the combined balance in that direction (what you owe X when paying, what X owes you when recording). Overpaying isn't allowed in this pass: the log sheet disables Log and states the maximum.

1. Take every non-deleted trip shared with X where the pairwise balance is in the payment's direction. For you paying X, that means trips where you owe X.
2. Order them **oldest first**: by trip start date, and for trips without dates by created date.
3. Fill each trip's open balance in order until `A` runs out. Each trip touched gets one `payment` row.

The log sheet must describe the allocation before logging whenever more than one trip is touched (see PRD › Prototype decisions).

### Idempotency

"A second log of the same payment is not a second payment." Each log carries a client-generated `request_id`. Logging the same `request_id` again returns the existing payments and creates nothing new.

### Deletion

Either person on a payment can delete it (soft delete). Deleted payments are excluded from all math.

## Expense lifecycle

- **Edit** replaces the amount, payer, split, and shares, and recomputes shares with the rules above. Earlier shares are not kept.
- **Delete** is permanent (hard delete). The Activity event keeps a snapshot of the title.
- A member added after an expense was saved is not on that expense.
- Removing a member never rewrites expenses, except under *wipe*.

## Wipe (removing a member and wiping their balance)

**Accepted for the MVP** (PRD › Decisions › Wipe algorithm). It's a rare action and may change after user feedback.

For removed member R on one trip:

1. For each expense where R has `share_cents > 0` and R is not the payer, move R's share to the remaining included members of that expense in proportion to their current shares, using the remainder rule. If R was the only included person, move it to the payer.
2. For each expense R paid, set every other member's share to 0 and R's share to the full amount. R absorbs their own payments, which cancels their credit.
3. Payments involving R stay as recorded. If they leave R's pairwise balances non-zero, the remover is shown the leftover before confirming.

## Golden cases

Amounts in dollars for readability; implement in cents. Member order is as listed.

### Splits

| # | Input | Expected shares |
|---|---|---|
| S1 | equal, $84.20, You/Alex/Jordan | 28.06, 28.06, **28.08** |
| S2 | equal, $10.00, You/Alex/Jordan | 3.33, 3.33, **3.34** |
| S3 | equal, $84.20, You/Alex checked, Jordan unchecked | 42.10, 42.10, — |
| S4 | equal, $0.01, You/Alex | 0.00, **0.01** |
| S5 | percent, $100.00, 33.33/33.33/33.34 | 33.33, 33.33, 33.34 |
| S6 | percent, $10.00, 50/50/0 | 5.00, 5.00, — |
| S7 | percent, $100.00, 50/49 | invalid (99%) |
| S8 | shares, $84.20, 2/1/1 | 42.10, 21.05, 21.05 |
| S9 | shares, $100.00, 1/1/1 | 33.33, 33.33, **33.34** |
| S10 | shares, $50.00, 0/0/0 | invalid (total 0) |
| S11 | exact, $84.20, 40.00/40.00/4.20 | 40.00, 40.00, 4.20 |
| S12 | exact, $84.20, 40.00/40.00/0 | invalid ($4.20 left) |

### Balances

| # | Setup | Expected |
|---|---|---|
| M1 | You pay $84.20, equal You/Alex/Jordan (S1) | You +56.14 · Alex −28.06 · Jordan −28.08 · pair(you, Alex) = +28.06 · pair(you, Jordan) = +28.08 |
| M2 | You pay $30.00, equal Alex/Jordan only (payer outside split) | You +30.00 · Alex −15.00 · Jordan −15.00 |
| M3 | PRD example: you owe Alex 90, Jordan 90, Connor 12; Tyler owes you 64 | header **−128** = −90 −90 −12 +64 |
| M4 | Coast Road: you owe Alex 60. Lake House: you owe Alex 30 | combined with Alex −90, one row |
| M5 | Coast Road: you owe Alex 20. Lake House: Alex owes you 20 | combined with Alex 0; Alex not listed on Your Balance |
| M6 | M1, then Coast Road is deleted | header 0; Alex and Jordan not listed |
| M7 | M6, then undeleted | back to M1 exactly |
| M8 | M1, then Sam joins Coast Road | M1 unchanged; Sam's net 0 |
| M9 | M1, then Alex logs a $28.06 payment to you | You +28.08 · Alex 0 · pair(you, Alex) = 0 |
| M10 | Alex pays $60 dinner, equal You/Alex/Jordan; you pay $30 gas, equal You/Alex/Jordan | pair(you, Alex) = 10 − 20 = **−10** (you owe Alex 10) |

### Allocation

| # | Setup | Log | Expected payment rows | Result |
|---|---|---|---|---|
| A1 | You owe Jordan: Lake House (Sep 12) 30, Coast Road (Oct 3) 60 | you pay 90 | LH 30, CR 60 | settled with Jordan |
| A2 | same | you pay 50 | LH 30, CR 20 | you owe Jordan 40, all on CR |
| A3 | same | you pay 20 | LH 20 | LH 10, CR 60 left |
| A4 | same | you pay 100 | none: rejected | can't log more than the $90 owed |
| A5 | Alex owes you 28.06 on Coast Road | you record 28.06 from Alex | CR 28.06 | settled with Alex |
| A6 | A2, the same log repeated with the same `request_id` | — | no new rows | unchanged |
