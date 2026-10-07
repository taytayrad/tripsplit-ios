# Glossary

One meaning per word. Use these terms in code, copy, and conversation. Code names are in `backticks`.

The net model (approved 2026-10-06, `prd.md` › Net model) adds the terms at the end of the table and retires the ones marked **Retiring**. Until each issue ships, retiring terms still describe the running app.

| Term | Meaning |
|---|---|
| **You** | The signed-in person. Every amount in the UI is from their point of view. |
| **Trip** (`trip`) | A group of people sharing costs. Has members, expenses, payments, and an optional date range. A trip can be soft-deleted and undeleted. |
| **Member** (`trip_member`) | A person on a trip. A member can be **removed**, or **leave**, only when their net on the trip is $0. |
| **Expense** (`expense`) | One cost paid by exactly one **payer**, divided among members by a **split**. |
| **Payer** | The one person who paid an expense. Can be outside the split. |
| **Split kind** (`split_kind`) | `equal`, `exact`, `percent`, or `shares`. How the expense amount was divided. |
| **Share** (`expense_share.share_cents`) | One person's saved part of an expense, in cents. Fixed at save, and the only number balance math reads. Not to be confused with a share *count* (the `shares` split input). |
| **Payment** (`payment`) | Money one person says they gave another, **logged** in TripSplit. Always between you and one other person, always on one trip. |
| **Log** | The act of recording a payment in TripSplit. Coming back from Venmo is not logging. |
| **Allocation** | **Retiring (TRIP-10).** How a single amount you log with a person is divided across the trips you share: oldest trip first. Produces one payment per trip touched. |
| **Net** | A signed amount: what you paid, minus your shares, minus payments you received, plus payments you made. Positive means you are owed; negative means you owe. Exists per trip, per person (pairwise), and overall. In the net model, every member has one net per trip. |
| **Pairwise balance** | **Retiring (TRIP-10).** Net between you and one other person on one trip. The building block of every other balance. |
| **Combined balance** | **Retiring (TRIP-13).** Pairwise balances with one person summed across every shared, non-deleted trip. One row on Your Balance. |
| **Header total** | **Retiring (TRIP-13).** Your overall net across non-deleted trips. Shown in the balance chip. Equals the sum of combined balances. |
| **Settled** | A net of exactly $0. Use "settled", never "square". |
| **Balance chip** | **Retiring (TRIP-13).** The header control showing the header total, signed (`-$42`, `$42`, `$0`). The only place money shows a sign. |
| **Your Balance** | **Retiring (TRIP-13).** The sheet the balance chip opens: balance block plus people grouped under "You owe" and "Owes you". |
| **Balance block** | The net-in-words component: label ("You owe", "You're owed", "Settled"), unsigned amount, optional detail line. |
| **Person screen** | **Retiring (TRIP-13).** One person's combined balance, a trip group per shared trip, and the pay bar. |
| **Pay bar** | **Retiring (TRIP-13).** Bottom bar on a person screen: shared pay apps plus Cash, or Record a Payment. |
| **Log sheet** | The single sheet where every payment is logged, prefilled and editable. |
| **Stamp** | A trip's generated, wordless, single-ink graphic (shape, glyph, ink, rotation, offset). The trip avatar. |
| **Ink** | A stamp color: blue, green, red, purple, orange, teal. |
| **Activity event** (`activity_event`) | An immutable record of something that happened on a trip, shown in Activity. |
| **Dollar line** | The line under an Activity statement saying how that event changed *your* money ("You owe $36"). |
| **Wipe** | **Retired (TRIP-14).** Removing a member and re-splitting their unpaid shares. Only members removed before TRIP-14 were wiped. |
| **Keep** | **Retired (TRIP-14).** Removing a member while their balance still counted. Only members removed before TRIP-14 were kept. |
| **Suggested payment** | One payment the app proposes so a trip settles in the fewest payments: largest debtor pays largest creditor. Calculated, never stored. May pair people who never shared an expense. |
| **Settle up** | The page that lists the people you have a suggested payment with, as Member Tickets. Starts on a trip when opened from one; "All trips" shows everyone. |
| **Member Ticket** | One person on Settle up: trip stamp(s) (up to two, then "+N"), name, caption, and "You owe" or "You lent" with the amount. |
| **Payment page** | Where a payment is set up: Route, amount, trip, date, method, and one button. Titled "Payment". |
| **Route** | The FROM → TO line at the top of the Payment page. "You" is always one end. |
| **You owe / You lent** | The only money labels. "You owe" (red) when you pay; "You lent" (green) when they pay you. Never "Your share". |
