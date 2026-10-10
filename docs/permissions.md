# Permissions

Who can do what, and the Supabase row-level security (RLS) that enforces it. The product rule is simple: **any active member can do anything on a trip** (PRD › Decisions › Permissions). Money writes go through RPC functions (see [`data-model.md`](data-model.md)), and each function checks membership itself.

**Active member** = a `trip_members` row for the caller with `removed_at is null`, on a trip that isn't deleted (unless the action is undelete).

## Actions

| Action | Who | Notes |
|---|---|---|
| Create a trip | any signed-in user | creator becomes a member |
| Edit trip name, dates, stamp | active member | |
| Add a member, share the invite link | active member | 20-member cap |
| Join with a link | anyone holding the token, except someone removed from the trip | already a member: no-op; removed: refused (an active member can add them back) |
| Remove a member | active member | only when that member's net on the trip is $0 |
| Leave a trip | active member, yourself | only when your net on the trip is $0 |
| Delete a trip | active member | soft delete |
| Undelete a trip | member at deletion time | from the Activity row |
| Add, edit, or delete an expense | active member | |
| Log a payment | either of the two people | the caller must be the payer or payee, and both must be on the trip (the other may be a member removed with *keep* before the net model) |
| See every member's net and the suggested payments | active member | `my_trip_settlements()`; a removed member sees only suggestions involving them |
| Delete a payment | payer or payee | soft delete |
| Restore a deleted expense | any active member | not on a deleted trip, and not when someone on the expense has left the trip |
| Edit profile, pay methods, notifications | self | |

## Table access (RLS)

| Table | Select | Insert / update / delete from the client |
|---|---|---|
| `profiles` | self; anyone you've shared a trip with, including removed members (a removed member's name stays on the trip, and with keep they still settle up) | self, update only |
| `trips` | active members | none (use `create_trip`, `delete_trip`, `undelete_trip`). Name, dates, and stamp can be updated by active members. |
| `trip_members` | active members of the trip | none (use `join_trip`, `remove_member`) |
| `expenses`, `expense_shares` | active members, including deleted expenses (they open from Activity) | none (use `save_expense`, `delete_expense`, `restore_expense`) |
| `payments` | active members, plus a removed-with-keep payer or payee for their own rows | none (use `log_payment`, `delete_payment`) |
| `activity_events` | active members. A trip's deleted state doesn't hide its events, so members still see the `trip_deleted` row and can undelete | none, ever (written by functions) |
| `device_tokens` | self | self |

## Gotchas

- **Removed members lose access** to the trip and its Activity. They're always settled when they go (TRIP-14), so they never need a way back in to pay. Members removed with *keep* before that still see the suggestions that involve them.
- **Deleted trips** disappear from every list and total, but the `trip_deleted` Activity row stays visible to members at deletion time, so they can undelete.
- Pay-app handles are only ever shown to people you share a trip with.
