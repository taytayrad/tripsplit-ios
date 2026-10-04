# Architecture

TripSplit is a native iPhone app (SwiftUI, iOS 17+) backed by Supabase. Product rules are in [`prd.md`](../prd.md).

A visual copy of these diagrams lives on the [Architecture & Reference FigJam board](https://www.figma.com/board/3ltxi7OzyIYQM1QjXN5Lhg). The Mermaid in these docs is the source of truth; update it first, then regenerate the board.

## C4 Level 1: System context

```mermaid
flowchart TB
    friend(["Friend<br/>iPhone user"])
    ts["TripSplit<br/>iOS app + Supabase backend"]
    apple["Sign in with Apple"]
    apns["Apple Push Notification service"]
    store["App Store"]
    msgs["Messages<br/>(via iOS share sheet)"]
    pay["Venmo · Zelle · Apple Cash"]

    friend -- "logs expenses, settles up" --> ts
    ts -- "authenticates" --> apple
    ts -- "sends pushes" --> apns
    apns -- "notifies" --> friend
    friend -- "shares invite link" --> msgs
    msgs -- "link opens app, or" --> store
    ts -- "opens prefilled (Venmo) or with amount copied" --> pay
```

Things TripSplit deliberately doesn't do: read contacts, collect phone numbers, move money, or confirm payments with pay apps. Payments count only once logged in TripSplit.

## C4 Level 2: Containers

```mermaid
flowchart TB
    subgraph device["iPhone"]
        app["TripSplit app<br/>SwiftUI, iOS 17+<br/>supabase-swift"]
    end

    subgraph supa["Supabase project"]
        auth["Auth<br/>Sign in with Apple (no phone)"]
        db[("Postgres<br/>tables, RLS, RPC functions,<br/>pair_balances view")]
        rt["Realtime<br/>row change streams"]
        fnPush["Edge function: push (Phase 5, not built yet)<br/>activity event → APNs"]
    end

    invitePage["Static invite page (GitHub Pages)<br/>site/join/: opens the app, or Get TripSplit button"]

    apns["APNs"]
    store["App Store"]

    app -- "sign in" --> auth
    app -- "RPC writes, balance reads" --> db
    app -- "subscribe to trip rows" --> rt
    db -- "changes" --> rt
    db -- "database webhook on activity_events insert" --> fnPush
    fnPush --> apns
    invitePage -- "app installed: open app with token" --> app
    invitePage -- "not installed" --> store
```

| Container | Responsibility |
|---|---|
| **iOS app** | All UI. Holds no money logic beyond formatting and live split previews; saved shares and balances come from the server. |
| **Postgres** | Source of truth. RPC functions own every money write (split → shares, payment allocation, wipe). The `pair_balances` view owns every balance read. RLS limits rows to the caller's trips. |
| **Realtime** | Pushes row changes so every member's screens update in close to real time. |
| **Edge function: push** (Phase 5, not built yet) | On each `activity_events` insert, finds affected members (event matrix in [`events.md`](events.md)), checks their preferences, skips the actor, sends APNs. |
| **Static invite page** | `site/join/index.html`, hosted free on GitHub Pages (Supabase's functions domain forces text/plain, so an edge function can't serve it). Kept in sync by hand with the `taytayrad/tripsplit-invite` Pages repo. Reads the token from the URL fragment and opens `tripsplit://join/:token`. Stands in for Universal Links until there's a domain. After an App Store install, the user may need to tap the link again. |

## Key choices

| Choice | Why |
|---|---|
| Money logic in Postgres functions, not the app | One implementation, atomic multi-row writes, and the same results on every client. |
| Balances calculated, never stored | They can't drift from the expenses and payments they come from. |
| Integer cents everywhere | No float rounding. The remainder rule is exact. |
| Online-only saves with Retry | The PRD keeps offline entry out of scope. Simpler than a sync queue. |
| Activity deltas snapshotted at write time | Old Activity rows keep the dollar line they had. |
| No contacts and no phone | The PRD forbids phone numbers. "On TripSplit" lists people you already share a trip with. |

## Related docs

- Schema and write paths: [`data-model.md`](data-model.md)
- Money math and golden cases: [`money-rules.md`](money-rules.md)
- Flows and state diagrams: [`flows.md`](flows.md)
- Access rules: [`permissions.md`](permissions.md)
- Activity and push matrix: [`events.md`](events.md)
- Screens and Figma: [`screen-map.md`](screen-map.md)
