# Screen map

How screens connect. Every screen has a Figma frame on the **Flow** page of the [TripSplit Design System](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD) file. Frame names follow `Feature / State [ref]`. Search Figma for the `[ref]` shown in brackets below.

```mermaid
flowchart LR
    subgraph Onboarding
        signin["Sign in [01]"] --> notif["Notifications [02]"] --> paym["Pay methods [03]"]
    end
    subgraph Main["Tabs"]
        trips["Trips [04, 11]"]
        activity["Activity [12]"]
        profile["Profile [21]"]
    end
    paym -->|creator| trips
    paym -->|from invite| welcome["Added to trip [I04]"]
    welcome -->|View Trips| trips

    trips -- "+ / Add Trip" --> addtrip["Add trip [05]"] --> members["Add members [06, 07]"] --> trip["Trip detail [08, 10]"]
    trips -- card --> trip
    trip -- "Add expense" --> expense["Expense form [09, E1]"]
    trip -- "expense row" --> expense
    expense --> paidby["Paid by [09a]"]
    expense --> split["Split [09b–09e]"]
    expense -- delete --> delconfirm["Delete confirm [E2]"]
    welcome -->|Add expense| expense

    chip(("Balance chip")) --> balance["Your Balance [13]"] --> person["Person [14, 18, P1]"]
    person -- "Venmo / Apple Cash" --> payapp["Pay app<br/>(outside TripSplit)"] --> log["Log sheet [16, 19, P3]"]
    person -- "Cash / Record" --> log
    log --> settled["Person: $0 or remaining [17, 20, P5, P6]"]

    activity -- "deleted trip row" --> undelete["Undelete alert [12c]"]
    profile -- "Sign out" --> signout["Sign out confirm [21b]"]
```

## Figma sections

| Section | Contents |
|---|---|
| [Onboarding](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3485) | Sign in, notifications, pay methods (+ invitee variants) |
| [Invite](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3487) | Welcome modal |
| [Trips](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3489) | Trips list states |
| [Trip](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3491) | Add trip, members, trip detail states |
| [Expense](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3493) | Add/edit form, payer, splits, delete |
| [Activity](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3495) | Feed, undelete alert |
| [Balance](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3497) | Your Balance sheet |
| [Person & Payments](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3499) | Person screens, log sheets, settled |
| [Profile](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3501) | Profile, sign out |
| [Prototype only](https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD?node-id=42-3503) | Stand-ins. **Don't build.** |

## Presentation

| Screen | SwiftUI presentation |
|---|---|
| Trips, Activity, Profile | `TabView` tabs |
| Trip detail, Add members | pushed in `NavigationStack` |
| Add trip, Expense form | `.sheet` with its own `NavigationStack` (payer and split pickers push inside it) |
| Your Balance → Person | `.sheet` with `NavigationStack` (person pushes inside it) |
| Log sheet | `.sheet` with medium detent, over the person screen |
| Welcome modal | `.sheet` or centered overlay after onboarding |
| Delete, undelete, and sign-out confirms | `.alert` |

Sheets and alerts in Figma are drawn as full frames with a dimmed copy of the screen behind. The dim is context, not a layout to build.

## Design tokens and components

The **Color**, **Spacing**, **Radius**, and **Stamp** variable collections carry SwiftUI code syntax (Dev Mode shows `Color.tsOwe`, `Spacing.lg`, and so on). Text styles map to Dynamic Type styles in their descriptions. Native controls (tab bar, segmented control, switch, keyboard) come from the iOS 26 kit. Use the system versions, not custom ones.
