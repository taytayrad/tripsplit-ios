# Flows

Sequence diagrams for the three hardest flows, then the state machines. Function names refer to [`data-model.md`](data-model.md) › Write paths.

## Joining from an invite link

```mermaid
sequenceDiagram
    actor T as Taylor
    actor A as Alex
    participant Msg as Messages
    participant Inv as Static invite page
    participant Store as App Store
    participant App as TripSplit (Alex)
    participant DB as Postgres

    T->>Msg: Share sheet → text with the invite page link (site/join/#:token)
    A->>Msg: Taps link
    Msg->>Inv: GET site/join/ (token in the #fragment)
    alt App installed
        Inv-->>App: Open tripsplit://join/:token
    else Not installed
        Inv-->>Store: "Get TripSplit" button
        A->>Store: Installs, opens app
        Note over A,App: May need to tap the link again<br/>(no Universal Links yet)
    end
    App->>App: Sign in with Apple (if needed) → notifications → name and pay methods
    App->>DB: join_trip(token)
    DB->>DB: Insert trip_member (no-op if already a member)<br/>Insert activity_event member_joined
    DB-->>App: Trip
    App->>App: Newcomers: "Taylor added you to a trip!" → View Trips / Add expense<br/>Already on the trip: no modal
```

## Adding an expense

```mermaid
sequenceDiagram
    actor T as Taylor
    participant App as TripSplit (Taylor)
    participant DB as Postgres
    participant RT as Realtime
    participant Push as Edge fn: push (Phase 5)
    participant APNs
    participant Other as Alex's app

    T->>App: Amount, description, payer, split, trip
    App->>App: Live preview (display only)
    T->>App: Save
    App->>DB: save_expense(expense, split_inputs)
    DB->>DB: Compute shares (remainder rule)<br/>Insert expense, shares, activity_event with deltas
    alt Save fails
        DB-->>App: Error
        App->>App: Stay on screen with Retry
    else Saved
        DB-->>App: OK
        DB->>RT: Row changes
        RT-->>Other: Change event → re-query balances
        DB->>Push: Webhook: activity_events insert
        Push->>Push: Recipients = members whose delta ≠ 0,<br/>minus actor, minus notify_expense = false
        Push->>APNs: Send
    end
```

## Logging a payment

```mermaid
sequenceDiagram
    actor Y as You
    participant App as TripSplit
    participant Pay as Venmo
    participant DB as Postgres

    Y->>App: Trip detail → Pay → Settle up
    App->>DB: my_trip_settlements() (already loaded)
    Y->>App: Tyler's ticket (You owe $45, 2 trips)
    App->>App: Payment: You → Tyler, $45, 2 Trips, today, Venmo
    Y->>App: Pay $45 with Venmo
    App->>Pay: Open with Tyler + $45
    Y->>Pay: Pays $45
    Y->>App: Returns (nothing logged yet)
    App->>App: Log Payment Sheet "Did you pay Tyler?" $45
    Y->>App: Log $45 payment
    App->>DB: log_payment(Tyler, pay, venmo, request_id, paid_on,<br/>[Lake House 1500, Coast Road 3000])
    DB->>DB: Lock both trips, check each part ≤ what both sides allow<br/>Insert one payment per trip + activity_events
    DB-->>App: Payments
    App->>App: Back on Settle up: the stamp slams onto Tyler's ticket
    Note over App,DB: Retrying with the same request_id<br/>creates nothing new
    Note over Y,App: Apple Cash: a guide sheet first (steps, amount copied),<br/>then Messages; coming back opens the same sheet.<br/>Zelle: amount copied, the sheet opens right away.<br/>Cash and Record log straight from the Payment page.
```

## State machines

### Trip

```mermaid
stateDiagram-v2
    [*] --> Active: create_trip
    Active --> Active: expenses, payments, members
    Active --> SettledHidden: dates set, end date passed, your net = 0
    SettledHidden --> Active: net ≠ 0 (new expense)
    Active --> Deleted: delete_trip
    SettledHidden --> Deleted: delete_trip
    Deleted --> Active: undelete_trip (expenses as of deletion return)
```

"SettledHidden" is per viewer. It's calculated, not stored.

### Member

```mermaid
stateDiagram-v2
    [*] --> Active: create_trip (creator) / join_trip / added
    Active --> Removed: remove_member / leave_trip (net is $0)
    Removed --> Active: add_member
    note right of Removed: No trip access.<br/>Net stays $0.<br/>(Members removed with keep or wipe before TRIP-14 stay as they were.)
```

### Payment

```mermaid
stateDiagram-v2
    [*] --> Logged: log_payment (one row per trip touched)
    Logged --> Deleted: delete_payment (payer or payee)
    Deleted --> [*]
```
