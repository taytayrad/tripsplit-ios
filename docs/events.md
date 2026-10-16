# Events

Every `activity_events.kind`: how it reads in Activity, its dollar line, and who gets a push. `push_recipients(event)` implements the "Push to" and "Preference" columns (TRIP-24, tested in `013_push_recipients`); the push edge function sends to those people's registered tokens (TRIP-25, [setup and device pass](push-setup.md)). Its TypeScript wording tests mirror `ActivityCopyTests`. Never notify the actor about their own action.

**What a push says** ([Figma › Push notifications](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=316-1638), N1–N9): it's written for the person getting it. The bold title is their Activity statement ("Sammy paid you in "Orlando 2027"", never "Sammy paid Connor"), and the body is their dollar line, left off when there is none.

**Delta** = the event's change to a person's trip net, snapshotted at write time (`activity_events.deltas`).

| Kind | Activity statement (pattern) | Dollar line for you | Push to | Preference (Profile switch) |
|---|---|---|---|---|
| `trip_created` | You created the trip "Coast Road" | none | nobody | — |
| `member_joined` | Alex joined "Coast Road" | none | every other active member | `notify_join` |
| `expense_added` | Connor added "Airbnb" in "Coast Road" | see *Expense dollar line* below | members whose delta ≠ 0 | `notify_expense` |
| `expense_updated` | Tyler updated "Costco" in "Lake House" | same rules as added, using the change | members whose delta ≠ 0 | `notify_expense` |
| `expense_deleted` | Tyler deleted "Costco" in "Lake House" | the reversal, same rules | members whose delta ≠ 0 | `notify_expense` |
| `expense_restored` | Tyler restored "Costco" in "Lake House" | same rules as added (the expense going back on) | members whose delta ≠ 0 | `notify_expense` |
| `payment_logged`, someone paid you | Sammy paid you in "Orlando 2027" | "You received $518.44" | the payee | `notify_paid` |
| `payment_logged`, you paid | You paid Connor $30 in "Coast Road" | none (amount is in the statement) | the payee | `notify_paid` |
| `payment_logged`, between others | Tyler paid Connor in "Lake House" | none | the payee only | `notify_paid` |
| `payment_deleted` | Sammy removed a payment in "Orlando 2027" | the reversal | the other person | `notify_paid` |
| `trip_deleted` | Sammy deleted the trip "Orlando 2027" | none | every other active member | `notify_trip_deleted` |
| `trip_undeleted` | Sammy restored the trip "Orlando 2027" | none | every other active member | `notify_trip_deleted` |
| `member_removed` | Taylor removed Jordan from "Coast Road"; when the actor is the person removed: Jordan left "Coast Road". A leave is a row whose `subject` equals the snapshotted `actor_name`, not the live name, so a deleted account's past leaves read "Deleted account left …" | none (only settled members leave) | nobody | — |
| `trip_edited` (name, dates, stamp) | — (not shown) | — | nobody | — |

## Rules

- **Expense dollar line** (added, updated, deleted), from your delta:
  - delta < 0 → "You owe $X"
  - delta > 0 → "You get back $X"
  - delta = 0 and you paid with your share equal to the whole amount → "You paid $X" (your own cost). $X is the amount stored on the event when it was written. A later edit of the expense does not change an earlier row. An event without that snapshot has no dollar line.
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
- **Taps:** an expense row (added, updated, deleted, restored) opens Expense details, in its deleted state when the expense is deleted; an expense deleted before TRIP-27 is gone, so its row does nothing. A trip or member row (`trip_created`, `trip_undeleted`, `member_joined`, `member_removed`) opens the trip when you can still see it. Payment rows open nothing. A `trip_deleted` row asks "Do you want to undelete this trip?" while the trip is still deleted, and opens the trip once it's back.
- **Search** filters by person, expense title, or trip name.

The `payment_deleted` and `member_removed` sentences above are the ones Activity uses (PRD › Prototype decisions › Activity wording).

Profile switch for each preference: `notify_paid` "Payments with you", `notify_expense` "Expenses that affect you", `notify_join` "Someone joins your trip", `notify_trip_deleted` "Someone deletes or restores a trip".

## Notification taps (N1–N9)

The APNs payload contains `activity_event_id`. On tap the app waits for sign-in/onboarding, refreshes, and reads that event with the signed-in account’s RLS. It opens the existing screen from the Activity tab, clearing old details, search, and sheets in both Trips and Activity. An unavailable event or destination falls back to Activity; a deleted expense uses its existing deleted detail state.

| Push | Kind | Destination |
|---|---|---|
| N1 Someone joined | `member_joined` | Trip Details for that trip |
| N2 Expense added | `expense_added` | Expense Details for that expense |
| N3 Expense updated | `expense_updated` | Expense Details for that expense |
| N4 Expense deleted | `expense_deleted` | Expense Details for that expense |
| N5 Expense restored | `expense_restored` | Expense Details for that expense |
| N6 Someone paid you | `payment_logged` | Trip Details for that trip |
| N7 Payment removed | `payment_deleted` | Trip Details for that trip |
| N8 Trip deleted | `trip_deleted` | Activity, even if subsequently restored |
| N9 Trip restored | `trip_undeleted` | Trip Details for that trip |

Activity row taps retain their own rules above. Notifications delivered before this payload change have no event ID and simply open the app.
