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

Every member has **one net per trip**:

```
net = paid − shares − payments_received + payments_made
```

- `paid`: sum of `amount_cents` of expenses the member paid
- `shares`: sum of the member's `share_cents` across the trip's expenses
- `payments_received`: payments where the member is the payee
- `payments_made`: payments where the member is the payer

Positive means the member is owed (copy: "You lent" for you, "Gets back" for others). Negative means they owe ("You owe", "Owes"). The nets on a trip always add up to $0. Receiving a payment and making one both move a member toward $0 (golden case M9).

- **Deleted trips** contribute nothing anywhere. Undeleting restores every net exactly, because the stored rows were never changed.
- **Settled** means a net of exactly $0. A trip is settled when every member is.

### Suggested payments

The fewest payments that bring every member of a trip to $0. Calculated on read, never stored.

1. Take every member whose net isn't $0.
2. The largest debtor (most negative net) pays the largest creditor (most positive net) the smaller of the two amounts.
3. Repeat with the updated nets until everyone is $0.

Ties go to the lower user id, so every phone shows the same list. A trip with *n* members needs at most *n − 1* payments. **Suggestions can pair people who never shared an expense** (golden case G1): that's the point of simplifying.

### Who appears where

- A trip card and Trip detail show your net on the trip in words.
- **Settle up** lists one ticket per person you have a suggested payment with. From a trip, only that trip's; on All trips, summed per person across trips (one ticket per person and direction).
- **Edit trip** lists every member's net.
- Settled trips: hidden from the trips list only when the trip has dates, the end date has passed, and your net is $0.

## Payments

A payment is one payer, one payee, one trip, an amount, a date (`paid_on`, today by default) and a method. Logging one moves both nets on that trip and nothing else.

### Limits

On each trip, a payment can be at most what both sides allow: no more than the payer owes (−net) and no more than the payee is owed (+net). So paying someone who isn't owed is refused (golden case P3), and nobody's net can flip sign through a payment (P2). It doesn't have to match a suggestion.

### Across trips

Paying the total on an All-trips ticket ("2 Trips") logs **one payment per trip**, each for that trip's suggested amount, in one transaction. Paying less than the total fills the trips oldest first (by start date, then created date).

### Idempotency

"A second log of the same payment is not a second payment." Each log carries a client-generated `request_id`. Logging the same `request_id` again returns the existing payments and creates nothing new; someone else reusing it is refused.

### Deletion

Either person on a payment can delete it (soft delete). Deleted payments are excluded from all math.

## Expense lifecycle

- **Edit** replaces the amount, payer, split, and shares, and recomputes shares with the rules above. Earlier shares are not kept.
- **Delete** is permanent (hard delete). The Activity event keeps a snapshot of the title.
- A member added after an expense was saved is not on that expense.
- Removing a member never rewrites expenses, except under *wipe*.

## Removing and leaving

A member can be removed, or leave, only when their net on the trip is exactly $0. Nothing is re-split or rewritten: a settled member's past expenses and payments stay as they were, and their net stays $0. It has to stay $0: editing or deleting an expense they're on, or deleting their payment, is refused while they're off the trip (add them back first). (Keep and wipe are gone. Members removed with *keep* before the net model still count in the math until their net is $0.)

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

Nets per member on one trip.

| # | Setup | Expected |
|---|---|---|
| M1 | You pay $84.20, equal You/Alex/Jordan (S1) | You +56.14 · Alex −28.06 · Jordan −28.08 |
| M2 | You pay $30.00, equal Alex/Jordan only (payer outside split) | You +30.00 · Alex −15.00 · Jordan −15.00 |
| M6 | M1, then the trip is deleted | no nets anywhere |
| M7 | M6, then undeleted | back to M1 exactly |
| M8 | M1, then Sam joins | M1 unchanged; Sam 0 |
| M9 | M1, then Alex pays you $28.06 | You +28.08 · Alex 0 · Jordan −28.08 |

### Suggested payments

| # | Setup | Expected suggestions |
|---|---|---|
| G1 | Coast Road: Tyler pays $60 stay, Atish pays $30 dinner, both equal You/Atish/Tyler | nets You −30 · Atish 0 · Tyler +30 → **You → Tyler 30** (Atish paid for your dinner but is settled) |
| G2 | M1 | Jordan → You 28.08 · Alex → You 28.06 (largest debtor first) |
| G3 | Ann pays $60 equal Ann/Cy; Bo pays $40 equal Bo/Di | Cy → Ann 30 · Di → Bo 20 (two payments, not three) |
| G4 | G1, then you pay Tyler $10 | You → Tyler 20 |
| G5 | G1, then you pay Tyler $30 | none: everyone settled |

### Payments

| # | Setup | Log | Expected |
|---|---|---|---|
| P1 | G1 | you pay Tyler 30 on Coast Road, Venmo, paid on Oct 4 | one row; every net 0; the row keeps the date |
| P2 | G1 | you pay Tyler 40 | rejected: more than what is owed |
| P3 | G1 | you pay Atish 10 | rejected: Atish isn't owed anything |
| P4 | You owe Tyler 30 on Coast Road and 15 on Lake House | you pay 45 as Coast Road 30 + Lake House 15 | two rows; you're settled with Tyler on both trips |
| P5 | P4, the same log repeated with the same `request_id` | — | no new rows |
| P6 | Jo owes you 8 on Coast Road | you record 8 from Jo, cash | Jo is the payer; Jo and you settled |

### Removing and leaving

| # | Setup | Action | Expected |
|---|---|---|---|
| R1 | G1 | remove Tyler (+30) | refused: only members with a $0 balance can be removed |
| R2 | G1 | remove Atish ($0) | removed; every other net unchanged |
| R3 | G1 | you leave (−30) | refused; after you pay Tyler 30, leaving works |
