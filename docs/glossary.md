# Glossary

One meaning per word. Use these terms in code, copy, and conversation. Code names are in `backticks`.

| Term | Meaning |
|---|---|
| **You** | The signed-in person. Every amount in the UI is from their point of view. |
| **Trip** (`trip`) | A group of people sharing costs. Has members, expenses, payments, and an optional date range. A trip can be soft-deleted and undeleted. |
| **Member** (`trip_member`) | A person on a trip. A member can be **removed**, and removal either **keeps** or **wipes** their balance. |
| **Expense** (`expense`) | One cost paid by exactly one **payer**, divided among members by a **split**. |
| **Payer** | The one person who paid an expense. Can be outside the split. |
| **Split kind** (`split_kind`) | `equal`, `exact`, `percent`, or `shares`. How the expense amount was divided. |
| **Share** (`expense_share.share_cents`) | One person's saved part of an expense, in cents. Fixed at save, and the only number balance math reads. Not to be confused with a share *count* (the `shares` split input). |
| **Payment** (`payment`) | Money one person says they gave another, **logged** in TripSplit. Always between you and one other person, always on one trip. |
| **Log** | The act of recording a payment in TripSplit. Coming back from Venmo is not logging. |
| **Allocation** | How a single amount you log with a person is divided across the trips you share: oldest trip first. Produces one payment per trip touched. |
| **Net** | A signed amount: what you paid, minus your shares, minus payments you received, plus payments you made. Positive means you are owed; negative means you owe. Exists per trip, per person (pairwise), and overall. |
| **Pairwise balance** | Net between you and one other person on one trip. The building block of every other balance. |
| **Combined balance** | Pairwise balances with one person summed across every shared, non-deleted trip. One row on Your Balance. |
| **Header total** | Your overall net across non-deleted trips. Shown in the balance chip. Equals the sum of combined balances. |
| **Settled** | A net of exactly $0. Use "settled", never "square". |
| **Balance chip** | The header control showing the header total, signed (`-$42`, `$42`, `$0`). The only place money shows a sign. |
| **Your Balance** | The sheet the balance chip opens: balance block plus people grouped under "You owe" and "Owes you". |
| **Balance block** | The net-in-words component: label ("You owe", "You're owed", "Settled"), unsigned amount, optional detail line. |
| **Person screen** | One person's combined balance, a trip group per shared trip, and the pay bar. |
| **Pay bar** | Bottom bar on a person screen: shared pay apps plus Cash, or Record a Payment. |
| **Log sheet** | The single sheet where every payment is logged, prefilled and editable. |
| **Stamp** | A trip's generated, wordless, single-ink graphic (shape, glyph, ink, rotation, offset). The trip avatar when there's no photo. |
| **Ink** | A stamp color: blue, green, red, purple, orange, teal. |
| **Activity event** (`activity_event`) | An immutable record of something that happened on a trip, shown in Activity. |
| **Dollar line** | The line under an Activity statement saying how that event changed *your* money ("You owe $36"). |
| **Wipe** | Removing a member and re-splitting their unpaid shares among remaining members. The only time saved shares change. |
| **Keep** | Removing a member while their balances still count and they can still be paid or recorded. |
