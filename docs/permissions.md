# Permissions

Who can do what, and the Supabase row-level security (RLS) that enforces it. The product rule is simple: **any active member can do anything on a trip** (PRD › Decisions › Permissions). Money writes go through RPC functions (see [`data-model.md`](data-model.md)), and each function checks membership itself.

**Active member** = a `trip_members` row for the caller with `removed_at is null`, on a trip that isn't deleted (unless the action is undelete).

## Actions

| Action | Who | Notes |
|---|---|---|
| Create a trip | any signed-in user | creator becomes a member |
| Edit trip name, dates | active member | |
| Add a member, share the invite link | active member | 20-member cap |
| Join with a link | anyone holding the token, except someone removed from the trip | already a member: no-op; removed: refused (an active member can add them back) |
| Remove a member (keep or wipe) | active member | the remover chooses keep or wipe |
| Delete a trip | active member | soft delete |
| Undelete a trip | member at deletion time | from the Activity row |
| Add, edit, or delete an expense | active member | |
| Log a payment | either of the two people | the caller must be the payer or payee; the other person may be a removed member with *keep* |
| Delete a payment | payer or payee | soft delete |
| Edit profile, pay methods, notifications | self | |

## Table access (RLS)

| Table | Select | Insert / update / delete from the client |
|---|---|---|
| `profiles` | self; anyone you've shared a trip with, including removed members (a removed member's name stays on the trip, and with keep they still settle up) | self, update only |
| `trips` | active members | none (use `create_trip`, `delete_trip`, `undelete_trip`). Name and dates can be updated by active members. |
| `trip_members` | active members of the trip | none (use `join_trip`, `remove_member`) |
| `expenses`, `expense_shares` | active members | none (use `save_expense`, `delete_expense`) |
| `payments` | active members, plus a removed-with-keep payer or payee for their own rows | none (use `log_payment`, `delete_payment`) |
| `activity_events` | active members. A trip's deleted state doesn't hide its events, so members still see the `trip_deleted` row and can undelete | none, ever (written by functions) |
| `device_tokens` | self | self |

## Gotchas

- **Removed members lose access** to the trip and its Activity. With *keep*, their balance still shows on their own Your Balance and person screens, built from their payment and pair rows only.
- **Deleted trips** disappear from every list and total, but the `trip_deleted` Activity row stays visible to members at deletion time, so they can undelete.
- Pay-app handles are only ever shown to people you share a trip with.
