# Data model

The proposed Supabase Postgres schema. **Stored** facts live in tables. **Calculated** values (every balance) are derived by query, never stored, so they can't drift. The math is in [`money-rules.md`](money-rules.md).

```mermaid
erDiagram
    profiles ||--o{ trip_members : "is on"
    profiles ||--o{ device_tokens : has
    trips ||--o{ trip_members : has
    trips ||--o{ expenses : has
    trips ||--o{ payments : has
    trips ||--o{ activity_events : has
    expenses ||--|{ expense_shares : "divided into"
    profiles ||--o{ expense_shares : owes
    profiles ||--o{ expenses : paid
    profiles ||--o{ payments : "pays / is paid"

    profiles {
        uuid id PK "= auth.users.id"
        text display_name
        text venmo_username "nullable"
        bool has_zelle
        bool has_apple_cash
        bool notify_paid
        bool notify_expense
        bool notify_join
        bool notify_trip_deleted
    }
    trips {
        uuid id PK
        text name
        text image_path "nullable, Supabase Storage"
        jsonb stamp "shape, glyph, ink, rotation, offsetX, offsetY"
        date start_date "nullable"
        date end_date "nullable"
        text invite_token UK
        uuid created_by FK
        timestamptz created_at
        timestamptz deleted_at "nullable = soft delete"
        uuid deleted_by "nullable"
    }
    trip_members {
        uuid trip_id PK
        uuid user_id PK
        timestamptz joined_at "member order"
        timestamptz removed_at "nullable"
        uuid removed_by "nullable"
        text removal "keep | wipe, nullable"
    }
    expenses {
        uuid id PK
        uuid trip_id FK
        text description
        text icon
        int amount_cents "> 0"
        uuid payer_id FK
        text split_kind "equal | exact | percent | shares"
        date spent_on
        uuid created_by FK
        timestamptz created_at
        timestamptz updated_at
    }
    expense_shares {
        uuid expense_id PK
        uuid user_id PK
        int share_cents ">= 0"
        numeric split_input "percent or share count, for re-editing"
    }
    payments {
        uuid id PK
        uuid trip_id FK
        uuid payer_id FK
        uuid payee_id FK
        int amount_cents "> 0"
        text method "venmo | zelle | apple_cash | cash | recorded"
        uuid logged_by FK
        uuid request_id "idempotency, groups an allocation"
        timestamptz created_at
        timestamptz deleted_at "nullable"
        uuid deleted_by "nullable"
    }
    activity_events {
        uuid id PK
        uuid trip_id FK
        uuid actor_id FK
        text kind
        uuid expense_id "nullable, no FK (expense may be deleted)"
        uuid payment_id "nullable"
        text subject "title snapshot, e.g. Costco"
        jsonb deltas "user_id -> cents, effect on each person"
        timestamptz created_at
    }
    device_tokens {
        uuid user_id PK
        text token PK
        timestamptz updated_at
    }
```

## Constraints and invariants

| Rule | Where it's enforced |
|---|---|
| `start_date` and `end_date` are both set or both null, and `end ≥ start` | check constraint |
| A trip has at most 20 active members | trigger on `trip_members` insert |
| `sum(share_cents) = amount_cents` per expense | deferred constraint trigger |
| The payer is a member of the trip; a share's user was a member when the expense was saved | `save_expense` function |
| `payer_id ≠ payee_id`, and `logged_by ∈ {payer_id, payee_id}` | check constraint |
| One allocation per `request_id` | unique `(request_id, trip_id)` |
| Expenses, shares, and payments change only through the functions below | RLS: no direct client insert or update on money tables |
| Activity events are append-only and written only by functions or triggers | RLS |

## Write paths (Postgres functions called over RPC)

Every multi-row money write is one function in one transaction, so invariants hold even on flaky connections.

| Function | Does |
|---|---|
| `create_trip(name, dates, image?)` | inserts trip with generated stamp and invite token, adds creator as member, logs `trip_created` |
| `join_trip(invite_token)` | adds caller as member, or no-op if already a member; logs `member_joined` |
| `save_expense(expense, split_inputs)` | computes shares (remainder rule), inserts or updates expense and shares, logs `expense_added` or `expense_updated` with deltas |
| `delete_expense(id)` | hard-deletes expense and shares, logs `expense_deleted` with deltas |
| `log_payment(other_user, amount_cents, direction, method, request_id)` | `direction` is `pay` (you pay them) or `record` (they paid you). Rejects amounts above what's owed, allocates oldest trip first, inserts one payment per trip, logs `payment_logged` per row, and returns the rows. Retrying a `request_id` returns the existing rows |
| `delete_payment(id)` | soft-deletes, logs `payment_deleted` |
| `remove_member(trip, user, keep \| wipe)` | marks removal; for wipe, rewrites shares (see money-rules › Wipe) |
| `delete_trip(id)` / `undelete_trip(id)` | sets or clears `deleted_at`, logs the event |

## Reads (calculated)

| Need | Source |
|---|---|
| Pairwise balances | `my_pair_balances()` → `(trip_id, other_user_id, cents)`, positive = they owe you. Built on the private view `private.pair_balances` (non-deleted trips, expenses, shares, non-deleted payments), which clients can't query directly |
| Trip net | `my_trip_nets()` → `(trip_id, cents)` |
| Combined balance (Your Balance rows) | `my_combined_balances()` → `(other_user_id, cents)`, $0 people omitted |
| Header total (balance chip) | `my_header_total()` → `cents`, the sum of the combined rows |
| Activity dollar line | `activity_events.deltas[you]`, snapshotted when the event was written so history doesn't shift after later edits |

## Notes

- **Why deltas are snapshotted:** the PRD calculates the dollar line "from that event's effect on you". Recomputing that effect later, after edits and deletes, would change old Activity rows. A snapshot freezes it.
- **Realtime:** clients subscribe to `expenses`, `expense_shares`, `payments`, `trip_members`, and `activity_events` for their trips, and re-query balances on change.
- **Stamp** is stored, not regenerated, so a trip looks the same on every device. Its JSON matches the app's `StampSpec` (`ios/TripSplit/DesignSystem/Stamp.swift`):
  ```json
  {"shape": "ticket", "glyph": "road", "ink": "blue", "rotation": -6.0, "offsetX": 0.02, "offsetY": -0.015}
  ```
  `shape`: ticket, circle, octagon, rounded, hexagon, or postage. `glyph`: road, house, market, plane, palm, mountain, tent, boat, or sun. `ink`: blue, green, red, purple, orange, or teal. `rotation`: degrees, within ±8. `offsetX` and `offsetY`: fractions of the frame, within ±0.025. The app generates it at trip creation, and the server stores it as given.
