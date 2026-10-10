# Events

Every `activity_events.kind`: how it reads in Activity, its dollar line, and who gets a push. The push edge function implements this table. Never notify the actor about their own action.

**Delta** = the event's change to a person's trip net, snapshotted at write time (`activity_events.deltas`).

| Kind | Activity statement (pattern) | Dollar line for you | Push to | Preference |
|---|---|---|---|---|
| `trip_created` | You created the trip "Coast Road" | none | nobody | — |
| `member_joined` | Alex joined "Coast Road" | none | every other active member | `notify_join` |
| `expense_added` | Connor added "Airbnb" in "Coast Road" | see *Expense dollar line* below | members whose delta ≠ 0 | `notify_expense` |
| `expense_updated` | Tyler updated "Costco" in "Lake House" | same rules as added, using the change | members whose delta ≠ 0 | `notify_expense` |
| `expense_deleted` | Tyler deleted "Costco" in "Lake House" | the reversal, same rules | members whose delta ≠ 0 | `notify_expense` |
| `payment_logged`, someone paid you | Sammy paid you in "Orlando 2027" | "You received $518.44" | the payee | `notify_paid` |
| `payment_logged`, you paid | You paid Connor $30 in "Coast Road" | none (amount is in the statement) | the payee | `notify_paid` |
| `payment_logged`, between others | Tyler paid Connor in "Lake House" | none | the payee only | `notify_paid` |
| `payment_deleted` | Sammy removed a payment in "Orlando 2027" | the reversal | the other person | `notify_paid` |
| `trip_deleted` | Sammy deleted the trip "Orlando 2027" | none | every other active member | `notify_trip_deleted` |
| `trip_undeleted` | Sammy restored the trip "Orlando 2027" | none | every other active member | `notify_trip_deleted` |
| `member_removed` | Taylor removed Jordan from "Coast Road"; when the actor is the person removed: Jordan left "Coast Road" | none (only settled members leave) | nobody | — |
| `trip_edited` (name, dates, stamp) | — (not shown) | — | nobody | — |

## Rules

- **Expense dollar line** (added, updated, deleted), from your delta:
  - delta < 0 → "You owe $X"
  - delta > 0 → "You get back $X"
  - delta = 0 and you paid with your share equal to the whole amount → "You paid $X" (your own cost)
  - delta = 0 otherwise → no dollar line

  | Lyft $100 | Delta | Line |
  |---|---|---|
  | You paid; you and Alex equally | +50 | You get back $50 |
  | You paid; only you in the split | 0 | You paid $100 |
  | You paid; Alex and Jordan only | +100 | You get back $100 |
  | Alex paid; you and Alex equally | −50 | You owe $50 |
  | Alex paid; you not in the split | 0 | none |
- **payment_deleted dollar line** is the reversal of that payment for you, from your delta on the event: delta > 0 → "You get back $X" (a payment you received was removed; your net went back up); delta < 0 → "You owe $X" (a payment you made was removed; your net went back down); otherwise no dollar line.
- **No push when:** the trip's name or dates change; someone leaves; a payment doesn't include you; or as a reminder to settle (PRD › Notifications).
- **Timestamps:** today shows the time only; earlier days show a short date and time.
- **Taps:** an expense row opens the expense (edit), a trip row opens the trip, and a `trip_deleted` row asks "Do you want to undelete this trip?"
- **Search** filters by person, expense title, or trip name.

The `payment_deleted` and `member_removed` sentences above are the ones Activity uses (PRD › Prototype decisions › Activity wording).
