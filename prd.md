# TripSplit PRD

## The job

TripSplit is a native iPhone app (SwiftUI). Close friends share a trip, log what one of them paid, see who owes whom, and settle.

Each person has an account and logs from their own phone. A person can be on many trips. The system share sheet, contacts, and payment apps are the real iOS ones.

MVP: iPhone, US dollars, English, close friends. A trip holds at most 20 members. Splits, the people on a trip, and adding members have to work at that size.

The signed-in person is “you.” A negative amount means you owe. A positive amount means members owe you.

## The rules

### Stamps
Stamps are the playful graphic used for TripSplit. Stamps are similar to passport stamps - they are simple, single color, easy to identify.

Similar to passport stamps they are not perfectly centered in a container and often angled; as if a real person 'stamped' the screen. 

Stamps do not have letters or words.

Stamps are always fully visible, they do not go off screen or out of frame. 

Empty state screens will have a collection of 3 different stamps. When a trip is created, a stamp is automatically generated. The stamp is the trip's avatar (there are no trip photos; see Prototype decisions).

### Account

Sign in with Apple. One tap, no password. Do not ask for a phone number.

Profile shows the person’s name and sign out. Venmo, Zelle, and Apple Cash are recorded in onboarding or on Profile, only as methods that person has. Do not ask for a phone number to do that.

### What you see

App navigation has three places: Trips, Activity, and Profile.

An add action is reachable from any of them. It adds an expense. If you have no trips, the empty state action is Add Trip with the stamps graphic.

The header on the main screens is one signed dollar amount: your net across every trip that still counts. No “You owe” or “You’re owed” on that figure. `-$42` means you owe $42. `$42` means you are owed $42. `$0` means the net is even. Tap it to open the people behind it. The same list can open from any main screen. Swipe down dismisses it.

That list is one row per other person, combined across every trip you share with them. A row is a name and one signed amount. No trip name. No explanation of the math. The rows add up to the header. Two trips with the same person are one row and one amount.

Check: you owe Alex $90, Jordan $90, and Connor $12, and Tyler owes you $64. The header is `-$128`, because 90 + 90 + 12 − 64 = 128.

Tap a person for the breakdown. Each trip you share is its own group under the combined total, and each group states that trip’s net with them. Paying them, or recording that they paid you, happens from that person.

### Trip card and a trip at $0

A trip card states your net for that trip in words. Negative net: “You owe” and the amount. Positive net: “You’re owed” and the amount. The card amount has no leading minus.

A trip at $0 and in the past is hidden from the main list. “Show past settled trips” brings it back. That control is on the trips list. A trip does not hide if a balance remains. A shown $0 trip shows $0. Do not use “You owe” or “You’re owed” for a $0 net.

### Balances

Your net, on one trip or across trips, is what you paid, minus your share of expenses, minus payments logged to you, plus payments you logged to other people. Receiving a payment and making one both move you toward $0.

Deleted trips do not contribute. Their outstanding balances are nullified, those amounts are hidden, and they are not in the header or in what anyone owes.

On a trip, the trip states your net for that trip. Each expense shows only your part of it, with no leading minus. If someone else paid, the line is “You owe” and your share. If you paid, the line is “You lent” and what you paid minus your share. It does not show the full expense amount or anyone else’s share.

### Trips

Creating a trip asks for a name, an image used as the trip’s avatar wherever the trip appears, and dates. The default image is a generated, unique stamp. Image and dates are optional. If dates are included, both a start and an end are required. If the user does not provide an image, use the stamps graphic. The creator is a member from the start. A trip can be edited after it is created. There is a way back to all trips.

### Members

Add a member in either of two ways:

- Contacts, with permission. Show contacts who already have an account, and add them. Do not ask for a phone number.
- A shareable link, through the iOS share sheet. A text message is the share path to expect. Someone without the app follows the link to the App Store, then into the trip.

Swipe removes a member. Past expenses stay as they were, including shares for people no longer on the trip. Someone added later is not put on expenses already logged.

Adding and removing members is part of editing the trip.

### Expenses

An expense has a description, an icon, an amount in USD, and the one person who paid. The description picks the icon. Tapping the icon changes it.

The payer starts as you and can be any current member of the trip. The payer can be outside the split. On an equal split the payer starts included. What they paid still counts in the net even when their share is $0.

The split starts as equal. Choosing the split opens that kind of split.

An expense can be edited or deleted. Edit opens the same fields, filled in. An edit changes the expense and is an Activity event. A delete removes it from the nets.

The expense can be applied to any of your trips, and you can switch the trip before it is saved. It does not have to be the trip on screen. The trip starts as the last trip you added an expense to. If you have never added an expense, it starts as the last trip you created. If you have no trips, the action is Add Trip. There is no general expense outside a trip.

### Splits

Only people already on the trip can be in a split.

**Equal.** Only the people selected. Everyone starts selected. At least one person stays selected. Unchecking someone redivides the whole amount across whoever is still selected. The parts add up to the expense. Leftover cents go to the last selected person.

**Exact amounts.** Each member starts at $0. $0 leaves that person out. The expense cannot be saved until the amounts add up to the expense.

**Percentages.** Each member starts at 0%. You cannot leave until the percentages are 100%.

**Shares.** Each member starts at 1. The amount is divided in proportion to the share counts. Zero shares leaves that person out. The split locks only when the total is 0.

The shares saved on an expense are the ones used from then on. Later membership changes do not redivide it.

### Settling

You are always one side of a payment you record. A payment between two other people is out.

**You owe them.** The amount starts as the full amount you owe them and can be changed before it is logged.

Venmo, Zelle, and Apple Cash show only when both people have that method. A method only one of you has is absent, not a disabled control. A tap opens that app with the person and the amount filled in. Do not invent URL schemes. The outcome is that the other app opens with that person and that amount filled in.

Coming back from Venmo, Zelle, or Apple Cash does not log the payment. Logging records it. Leaving it unpaid records nothing.

Cash is always available, whether or not you share another method. Cash logs inside TripSplit. There is no other app to open. Whether Cash skips the confirm step is open.

**They owe you.** Record a Payment is available. It opens already filled: they paid you, for the amount they owe. Logging records that payment.

A logged payment is one record. The payer and the payee both see it. Every member’s transactions and totals update in close to real time. A second log of that same payment is not a second payment.

A logged payment updates your header and appears on Activity. Settling to $0 with a person is a celebration on that person’s screen. At $0 with them there is nothing left to pay and Record a Payment is not offered.

### Activity

Activity is every transaction on every trip you belong to, newest first: expenses you added, expenses friends added, edits, expense deletes, payments, payment deletes, members joining or being removed, and trips created, deleted, or undeleted.

Each item is a statement in the form person, action, transaction, trip. Expense titles and trip names sit in quotes. People do not. The patterns:

- You paid Connor $30 in "Coast Road"
- You created the trip "Coast Road"
- Tyler paid Connor in "Lake House"
- Connor added "Airbnb" in "Coast Road"
- Tyler updated "Costco" in "Lake House"
- You added "Lyft" in "Night Market"
- Sammy paid you in "Orlando 2027"
- Sammy deleted the trip "Orlando 2027"

On an expense, and when someone pays you, add how it changes your money: “You received $518.44”, “You get back $117.40”, “You paid $100”, or “You owe $36”. Creating or deleting a trip has no dollar line. A payment you made keeps its amount inside the statement.

The expense dollar line follows the change to your net: “You owe $X” when it went down, “You get back $X” when it went up. “You paid $X” appears only when you paid and your share is the whole amount (your own cost, so no one owes anyone). When an expense doesn't change your money and you didn't pay it, there's no dollar line.

Today shows the time. An earlier day shows a short date and time.

Search filters the feed by person, expense, or trip. Tapping an expense opens it. Tapping a trip opens it.

Deleting a trip is a soft delete. The delete stays in Activity. Tapping that row asks “Do you want to undelete this trip?” Cancel leaves it deleted. Confirming undeletes the trip and brings back the expenses that were nullified. Those amounts count again.

### Notifications

The iPhone permission is required before any push. Profile is where each kind is turned on or off. You are not notified about your own action.

Send a push when:

- Someone paid you.
- Someone added, edited, or deleted an expense on a trip you are on, and it changes what you owe.
- Someone joined a trip you are on.
- Someone deleted a trip you are on, or undeleted one.

Do not send a push when the trip’s name or dates change, when someone leaves, when a payment does not include you, or as a reminder to settle.

## Stored versus calculated

Store:

- The Apple identity and name. No phone number.
- Which of Venmo, Zelle, and Apple Cash each person has.
- The trip: name, image, optional start and end, members, creator, and whether it is deleted.
- The expense: trip, description, icon, USD amount, the one payer, split kind, who was in it, and each person’s saved share. Shares stay fixed after save.
- The payment: trip, the two people, amount, and that it was logged in TripSplit. Returning from another app is not a payment.
- Activity events for adds, edits, expense deletes, payments, payment deletes, members joining or being removed, and trip create, delete, and undelete. An edit is its own event. The delete event remains after a delete.

Calculate:

- Your share on an expense row, from the saved split. Equal, percent, and share amounts are fixed at save, including leftover cents on an equal split.
- Your net on a trip, and your net across trips, from the formula in Balances. Leave out every deleted trip.
- Each other person’s combined amount, from the trips you still share with them, excluding deleted trips. Those signed amounts sum to the header.
- The Activity dollar line, from that event’s effect on you.

A $0 trip is still stored. It is hidden on the main list until “Show settled trips.” Its zero does not move the header. A deleted trip is still stored. Its old balances are not calculated into any total.

## Out of scope

- Android, currencies other than USD, and languages other than English.
- Receipts, comments, and offline entry.
- A phone number at sign-in, in contacts, or on Profile.
- Recording a payment where you are neither person.
- More than one payer on an expense.
- URL schemes for Venmo, Zelle, or Apple Cash. Implement the outcome only.
- Layout, type, color, and which screen comp is approved.
- More than 20 members on a trip.

## Open

Do not decide these. Do not invent a default and build it.

1. **Cash confirm.** Cash logs inside TripSplit. Whether that path skips the confirm step is not decided.
2. **Journey defaults that were never confirmed.** The plan’s “Journey defaults to confirm” are not requirements. Where a rule above already decides the point, follow the rule. The undecided items are:
   - After create, the trip opens on Add members, and members are not required.
   - A trip shows its stamp, name, dates, members, and expenses newest first. Your net on the trip is already required.
   - Anything about the trip card or the header that is not already in the rules above.
   - The rest of the $0-trip note: an expense putting the trip back on the main list, a deleted trip staying out of both lists, no archive, and whether a person’s screen hides trips already settled with them or has its own “Show settled trips.” The trips-list control is already required.
   - Who can add, edit, or delete an expense, invite, leave, edit the trip’s name and dates, remove someone, or delete the trip. Leaving does not rewrite past expenses is only this unconfirmed note. Swipe-remove and “past expenses stay” are already required.
   - A link joins the trip immediately. Someone already on it just opens the trip.
   - An expense has a date, defaulting to today, and it can be changed.
   - The amount uses a large figure and the system number pad.
   - The exact Profile fields for a Venmo username, a Zelle phone or email, or an Apple Cash phone. Do not ask for a phone number while this is open. A missing handle does not get an explanatory control; a method you do not both have is absent.
   - Saves need a connection. A failed save stays on screen and can be retried.
   - Add sits in the upper right, opposite the header total. That it is reachable is already required.
   - A live dollar preview per person, a manual icon that stays put when the description changes, and save staying unavailable until the split is valid with the screen saying why. The equal, exact, percent, and share gates above are already required.

## Decisions (2026-10-03)

These resolve conflicts and Open items above. Where this section and an earlier rule disagree, this section wins. Where the PRD and `product-plan.md` disagree, the PRD wins.

- **Backend:** Supabase (Postgres, Sign in with Apple auth, realtime, edge functions for APNs).
- **Contacts:** no Contacts matching in the MVP. "On TripSplit" lists people you already share a trip with. Everyone else joins through the share link. No phone number is ever collected.
- **Pay apps:** store a Venmo username on Profile. Venmo opens with the person and amount filled in. Zelle and Apple Cash open their app (Apple Cash opens Messages) with the amount copied to the clipboard. Zelle and Apple Cash are stored only as "I have this."
- **Removing a member with a balance:** the person removing them chooses in an alert:
  - *Keep balance:* the removed member's balance still counts, and they can still be paid or recorded.
  - *Wipe balance:* the removed member's unpaid shares are re-split across the remaining members so the trip still balances. This is the only case where saved shares change after save.
- **Paying across trips:** a combined payment fills the oldest open trip balance with that person first, then the next. It creates one payment record per trip it touches.
- **Permissions:** any member can add, edit, and delete expenses, edit the trip, add and remove members, and delete or undelete the trip.
- **Payment undo:** either person on a payment can delete it. This is a soft delete, it is shown in Activity, and balances recalculate.
- **Cash:** a confirm step before logging ("Log $90 cash to Alex?").
- **Rounding:** leftover cents on percent and share splits go to the last included person, the same as equal splits.
- **Expense date:** defaults to today and can be changed.
- **Invite link:** joins the trip immediately. Someone already on the trip just opens it.
- **After create:** the trip opens on Add members, which can be skipped.
- **Links:** Apple Developer account, no domain yet. A static page on GitHub Pages (`site/join/`, token in the URL fragment) stands in for Universal Links: it opens the app, or shows a Get TripSplit button when it isn't installed. After installing from the App Store, a new user may need to tap the link a second time.
- **Saves:** online only. A failed save stays on screen with Retry. There is no offline queue.
- **Shares:** whole numbers only.
- **Hiding settled trips:** only a trip that has dates, whose end date is in the past, and that is at $0 is hidden. A trip without dates is never hidden. The control is labeled "Show settled trips."
- **Wiping a removed member who is owed money:** the same keep-or-wipe choice applies. Wiping cancels their credit, re-split across the remaining members.
- **Wipe algorithm:** accepted for the MVP as written in `docs/money-rules.md` › Wipe. It's a rare action and may change after user feedback.
- **Payment amount (supersedes the earlier "not capped" decision):** for this pass, a payment can be at most the combined amount owed with that person. The log sheet won't log more and says why. Overpaying may come back later.
- **Removed members:** lose access to the trip and its Activity. Their balance stays only if it was kept.
- **Expense icon:** keyword match from the description to the starter icons (groceries, restaurant, coffee, drinks, gas, rideshare, flight, lodging, tickets, shopping, general). Tapping the icon overrides it.
- **Platform:** iOS 17 minimum.
- **Your Balance sheet (supersedes "a row is a name and one signed amount"):** the sheet that opens from the header is titled "Your Balance". It opens with a balance block: the net label ("You owe", "You’re owed", or "Settled" at $0), the amount without a sign, and a trip-count line in the same style as the label ("Across 3 trips", counting only trips that aren't deleted). Rows are grouped under "You owe" and "Owes you", each a name and an unsigned amount. The header chip is the only place money is shown with a sign. No trip names on rows.
- **Copy:** say "settled", never "square", for $0 states.
- **Logging a payment:** every payment is recorded on one "Log payment" sheet, prefilled with the full balance and editable there (decimal pad). It opens on return from Venmo or Apple Cash ("Did you pay Alex?"), on Cash ("Paid Alex in cash?", which is the cash confirm step), and on Record a Payment ("Did Alex pay you?"). "Not yet" records nothing.
- **Payment lines on a person's screen:** shown in neutral secondary color. Red and green are only for charges.

## Prototype decisions (2026-10-03)

These came out of the Figma prototype (Flow page in the design system file) and apply to the build. The prototype is the reference for layout, and these notes are the reference for behavior.

### People and payments
- **Settled trips on a person's screen:** right after a payment, a trip that just reached $0 stays visible, with its payment line, so the money doesn't look like it vanished. The next time the screen opens, settled trips with that person are hidden behind "Show settled trips", the same control as on the trips list.
- **Trip order on a person's screen:** newest trip first, even though payments are applied oldest trip first.
- **Showing where a payment goes:** when a logged amount touches more than one trip, the log sheet says where it goes before logging, for example "Pays off Lake House ($30) first, then $20 toward Coast Road."
- **After a partial payment:** the balance block shows what's left, with a detail line like "You paid $50 today". The pay bar stays.
- **Settled with a person:** the balance block shows "Settled", "$0", and "You and Alex are settled". Confetti plays in the stamp inks (static under Reduce Motion). The pay bar is removed.

### Expenses
- **Edit:** tapping an expense opens the add form as a sheet, filled in, titled "Edit expense", with Cancel and Save. "Delete expense" sits at the bottom. A line under it says who added the expense and when ("Added by you · Today, 9:41 AM").
- **Delete:** from the edit form, or by swiping left on the expense row. Both ask: "Delete 'Costco'?" / "It comes off everyone's balance on Coast Road. This can't be undone." with Cancel and Delete.
- **Deletes are permanent.** Undeleting a trip brings back only the expenses that existed when the trip was deleted. An expense deleted on its own stays deleted.
- **Default trip after an invite:** Add expense started from the invite modal (or as your first expense after joining) preselects the trip you were just added to.

### Splits
- **Paid by:** a single-select list with a trailing checkmark. Equal splits use circle checks (multi-select).
- **Equal:** member rows have no amounts. A footer shows the rounded average ("$28.07 per person"), and the saved shares stay exact. There's no "All" row. A "Select all" button appears in the section header only when someone is unchecked; there is no "Deselect all", because at least one person must stay selected.
- **Keyboards:** a decimal pad for the expense amount, Exact, Percent, and the payment amount. A number pad for Shares (whole numbers).
- **Running total:** the footer ("$84.20 left", "100% left", "3 shares") is pinned directly above the keyboard, or above the home indicator on Equal, so it stays visible with long member lists. Save is unavailable until the split is valid.

### Joining from a link
- **Welcome modal:** after onboarding (sign in, notifications, pay methods), the invitee sees "Taylor added you to a trip!" with that trip's stamp, name, dates, and members. The buttons are View Trips (goes to the Trips list), Add expense, and ✕.
- **Sign-in context:** when someone arrives from a link, the sign-in screen shows "Taylor invited you to 'Coast Road'".

### Onboarding and Profile
- **Notifications:** a short screen explains what gets pushed before the iOS permission prompt, with "Not now" as an option.
- **Profile:** name and "Signed in with Apple"; pay methods with the Venmo username; one switch per push type (Someone pays you, Expenses that affect you, Someone joins your trip, A trip is deleted or restored), plus the note "You're never notified about your own changes"; Sign out.
- **Sign out confirmation:** Sign out asks "Sign out of TripSplit?" / "Your trips and balances stay saved. Sign back in with Apple anytime." with Cancel and Sign out.

### Build decisions
- **Stamp glyphs in code are SF Symbols** (road.lanes, house, cart, airplane, beach.umbrella, mountain.2, tent, sailboat, sun.max), so they get system weights, accessibility, and dark mode for free. The Figma Stamp Glyph components use the same SF Symbol vectors, so design and code match. Border shapes are drawn in SwiftUI, and their stroke widths scale with the stamp's size.
- **Color tokens** ship as an asset catalog with light and dark values from Figma. Backgrounds, separators, and primary text use iOS system colors directly. Secondary text uses `tsSecondary` (#6C6C70 light) rather than the system's translucent gray, to pass AA contrast.
- **Backends:** Debug builds talk to the local Supabase (`supabase start`); Release builds talk to the hosted project.
- **Invite links** open a static page (`site/join/`, hosted free on GitHub Pages) with the token in the URL fragment, which opens the app at `tripsplit://join/<token>`. An edge function can't serve it: Supabase's functions domain forces `text/plain`. A custom URL scheme until there's a domain for Universal Links.
- **Test people (Debug only):** the sign-in screen has a "Test person's name" field that signs in anonymously against the local backend, so two simulators can act as two people without two Apple IDs. Anonymous sign-in is enabled only in the local config, never on the hosted project.
- **Welcome modal after a link:** shown to newcomers. Someone already on the trip who taps its link just lands on Trips.
- **Profiles are visible to anyone you've shared a trip with, including removed members**, so a removed member's name stays on the trip and, with keep, both sides can still see who they settle up with.
- **Stamps only, no trip photos (for now):** every trip shows its generated stamp. Photo upload is removed to keep the build smaller; photos can come back later. The empty private `trip-photos` bucket remains until it's deleted in the Supabase dashboard (SQL can't delete storage rows; see `docs/data-model.md` › Notes).
- **Removed members can't rejoin with a link.** Their old invite link no longer works for them. An active member can add them back from Add members; after a wipe they come back with no share in the old expenses.
- **Live updates:** the app subscribes to its trips' rows (trips, members, payments, activity; every expense change writes an activity row) and re-queries on any change, so an expense saved on one phone shows on the others within a few seconds.
- **Expense row for your own cost:** when you paid and your share is the whole amount, the row reads "You paid $X" (the Activity wording), since "You lent $0" says nothing.
- **Trip is locked while editing an expense.** Moving an expense between trips would change two trips' balances; delete and re-add instead.
- **Split kinds are tabs** (Equally, Exact, Percent, Shares) on one screen; switching kinds resets that kind to its starting values.
- **Add trip shows its stamp before saving.** The stamp is generated when the form opens, so you see what the trip will look like.
- **Tap the stamp to regenerate it** while creating a trip. Once the trip exists the stamp is fixed.
- **The + button** adds an expense, or starts a trip when you have none (the Figma header). Another trip starts from an "Add trip" button under the trip cards on Trips.

### Assumed in the prototype, not yet confirmed
- The welcome modal also appears when someone who already has the app taps an invite link.
- Being shown as allowed is the only notification state that's designed. The case where iOS permission was denied isn't.
