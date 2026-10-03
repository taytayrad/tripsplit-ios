# TripSplit product plan

Last updated 2026-10-02. Planning only — no build until Taylor asks to start.

Native iOS app, built with SwiftUI when implementation starts, so the share sheet, contacts, and payment apps are the real iOS ones. Close-friend beta. US dollars only. Every person has an account and logs expenses from their own phone. A person can belong to many trips.

## Sign-in

Beta sign-in is Sign in with Apple. One tap, no password.

The share link is enough to get a friend onto a trip. A phone number is asked only the first time someone uses Add from Contacts, so the app can match people who already have an account.

## Navigation

Three main screens:

- Trips
- Activity — every transaction on every trip the user belongs to
- Profile — name and sign out

An add action is reachable from any screen. It adds an expense, unless the user has no trips. Then that action is Add Trip.

## Activity

Approved 2026-10-02. The comp is [Activity with the undelete alert](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/activity-v3.png).

The feed is every transaction on every trip the user belongs to, newest first. That includes expenses the user added, expenses friends added, edits, payments, and trips being created or deleted.

Each row has four parts:

- The trip’s stamp, on the left. Same stamp family as the trip cards.
- A statement in the form person, action, transaction, trip. Expense titles and trip names sit in quotes. People do not.
- A timestamp for when it happened, under the impact line, or under the statement when there is no impact line. The statement uses the full width of the row. Today shows the time. An earlier day shows a short date and time.
- On an expense, and when someone pays the user, one line for how it changes the user’s money: “You received $518.44”, “You get back $117.40”, “You paid $100”, or “You owe $36”. Creating or deleting a trip has no dollar line. A payment the user made keeps its amount inside the statement.

The statement grammar:

- You paid Connor $30 in "Coast Road"
- You created the trip "Coast Road"
- Tyler paid Connor in "Lake House"
- Connor added "Airbnb" in "Coast Road"
- Tyler updated "Costco" in "Lake House"
- You added "Lyft" in "Night Market"
- Sammy paid you in "Orlando 2027"
- Sammy deleted the trip "Orlando 2027"

Those lines are the pattern for the picture. The header on this screen stays the bare signed total, still -$128 across the sample trips. The owe and get-back words live on the row.

Search sits under the title and filters the feed by person, expense, or trip. Add sits at the upper right and opens the same add-expense form, which still does not assume a trip. Tapping an expense row opens that expense. Tapping a trip row opens that trip. Deleting a trip is a soft delete. Tapping that activity row opens an alert whose words are “Do you want to undelete this trip?” Cancel leaves it deleted. Undelete restores it.

## Header

Upper left of the header, on the main screens, is one signed dollar amount for the net across every trip. No “You owe” or “You’re owed” label. Working reading: `-$42` means the user owes $42, `$42` means the user is owed $42, `$0` when the net is even.

On a specific trip, the upper left is Back, to all trips. The all-trips total is not shown there. Edit is the way to change that trip. The trip screen is approved as of 2026-10-01. The comp is the [Coast Road screen](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/trip-detail-hf.png). Back is at the upper left. Edit is at the upper right. Dates and the member count are chips. The trip balance is the large figure. Expenses are a grouped list, with Add expense on that list. A faint stamp sits in the open space under the expenses and does not cross the type. Adding and removing members happens on the edit screen.

The number is their net. What they paid, minus their share of expenses, plus payments logged to them, minus payments they logged to other people.

Tap the header total to open the people behind it.

## Who you owe

Approved 2026-10-02. The comp is [the people sheet](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/people-sheet-v3.png).

Tapping the header total opens a sheet. The same sheet can open from any main screen. Swipe down dismisses it.

One row per person, combined across every trip you share with them. On the sheet, a row is a name and one amount. No trip name, and no explanation of how the amount was calculated. That breakdown is the screen you get by tapping the person. Two trips with the same person stay one row and one pay amount. On that person’s screen, each trip is its own group under the combined total. A trip can hold about 10 to 20 transactions. The pay buttons sit in a bar fixed to the bottom of the screen, so they stay visible and easy to tap while the charges scroll. Each trip shows its own net so the long list does not have to be added by hand. A trip that is settled with this person is hidden. “Show settled trips” reveals it. When the balance is $0, the pay bar is gone and confetti plays.

The rows add up to the header. In the sample that header is -$128.

- You owe: Alex $90, Jordan $90, Connor $12
- Owes you: Tyler $64

Those amounts come from the trips, and the sheet does not say so. Alex $90 and Jordan $90 are Coast Road. Connor $12 is Night Market. Tyler $64 is Lake House. 90 + 90 + 12 − 64 = 128.

Venmo, Zelle, and Apple Cash are not on this list. They appear after you tap a person. The sheet says “Tap someone to pay and for details.” People who owe you still have no pay button on that next screen.

Paying someone:

- The amount starts as the full total owed to that person, and can be changed before it is logged
- Both people add payment accounts in onboarding or on Profile. The pay screen shows only the methods they share. Venmo, Zelle, and Apple Cash are not assumed. A method they do not share is absent, not a disabled button. Tapping one opens that app with the recipient and the amount already filled in.
- Cash is always an option, shared or not. Tapping it logs the payment in TripSplit. There is no other app to open.
- The payment counts only when it is logged in TripSplit. Returning from Venmo does not change the balance by itself
- A logged payment updates the header total and appears on Activity
- Settling with a person is a celebration. Confetti plays on that person’s screen when the payment is logged in TripSplit.
- Approved 2026-10-02. The comp is [Alex](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/alex-pay-v3.png). Apple Cash and Zelle open those apps with Alex and $90 filled in. Cash logs in TripSplit. All three stay in a bar at the bottom. The $90 is Dinner $120 and Gas −$30 on Coast Road.

## Trips

Creating a trip asks for:

- Trip name
- An image, used as the trip’s avatar everywhere the trip appears
- Dates, optional. If included, both a start and an end date

A trip can be edited after it is created. The creator is a member from the start.

## Members

Two ways to add someone:

- Contacts: with permission, show contacts who already have an account, and add them
- Shareable link: opens the iOS share sheet. Text message is the share path we expect most often

Someone without the app follows the link to the App Store, then into the trip.

## Expenses

Adding an expense asks for a description, an icon, an amount in USD, and who paid.

The icon is chosen from the description. “Costco” becomes a grocery basket or something like it. Tapping the icon changes it.

The amount sits above the expense name. Under the name: “Paid by you and split equally.” On the add and edit forms, “you” and “equally” are the controls. On a trip, that sentence is a caption. Tapping the expense opens edit, the same form with the values filled in.

Add expense is one form, reachable from almost anywhere. It does not take the trip on screen. The person chooses the trip on the form. Tapping that row opens their trips. Accepted for now on 2026-10-02: the [add form](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/add-expense-v3.png) and the [edit form](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/edit-expense-hf.png).

- “you” is the payer. It can be any member of the trip. It starts as the signed-in user.
- “equally” opens the split. Each option shows the controls for that kind of split.

A new expense does not inherit a trip. The person chooses one on the form.

### Splits

1. **Equally.** A list of members. Select or unselect who is included. Everyone starts selected. The amount is divided evenly across the selected people. At least one person stays selected.
2. **Exact amounts.** A dollar amount for each member. The amounts must add up to the expense. Zero leaves that person out.
3. **Percentages.** A percentage for each member. The percentages must add up to 100.
4. **Shares.** A share count for each member, for time-based costs such as nights. Two nights means two shares. The amount is divided in proportion to shares. Zero shares leaves that person out.

The payer can be outside the split. On an equal split they start included.

## Assumed for the beta

- An expense can be edited or deleted. A member can be removed. Past expenses stay as they were.
- Equal splits give any leftover cent to the last selected person so the parts still add up.
- A trip is a handful of friends, under about ten. English only. iPhone only.
- Receipts, comments, currencies besides USD, Android, and offline entry stay out unless the trip has no service.

## Journey defaults to confirm

Recommended answers. Not locked until Taylor confirms or corrects them.

1. Trip photo can be skipped. A placeholder stands in until one is added.
2. After a trip is created, it opens with Add members visible. Members are not a required step.
3. A trip shows its photo, name, dates, members, your net for that trip, and expenses newest first.
4. Each trip card shows your net for that trip. The header stays the all-trips total.
5. A trip at $0 leaves the main list. “Show settled trips” brings it back. That control lives on the trips list, not on a person’s screen. Adding an expense puts the trip on the main list again. A deleted trip stays out of both lists. No archive in the beta. A draft at `media/alex-settled-hf.png` is not the celebration. It puts that control on Alex and drops the charges.
6. Any member can add, edit, or delete an expense, invite people, and leave. The creator edits the name, photo, and dates, removes someone, and can delete the trip. Leaving does not rewrite past expenses.
7. A link joins the trip immediately. Someone already on it just opens the trip.
8. Contacts shows only people who already have the app. Everyone else is reached with the share link.
9. An expense has a date, defaulting to today, and it can be changed.
10. The trip on the add-expense sheet is visible and can be changed before saving.
11. The amount uses a large figure and the system number pad.
12. Logging a payment updates the other person immediately. They do not confirm. Both people see the same payment, so it cannot be logged twice.
13. A payment can be logged on its own, for cash or a payment already sent, without opening Venmo, Zelle, or Apple Cash.
14. Profile can store a Venmo username and a Zelle phone or email. Apple Cash uses the phone number already on the account. If a handle is missing, that button explains it cannot target them yet.
15. Pay apps for the beta are Venmo, Zelle, and Apple Cash, unless this group uses another.
16. Someone you owe across two trips is one total. Tap the row to see each trip.
17. The beta asks for push notifications: a new expense on your trip, and a payment logged with you.
18. Saves need a connection. A failed save stays on screen and can be retried.
19. Add sits in the upper right, opposite the header total.
20. Every split shows a live dollar preview per person before saving. A manual icon choice stays put if the description keeps changing. Save stays unavailable until the split is valid, and the screen says why.

## Design direction

Proposed, not locked.

- Native iOS type, sheets, and lists. Light and dark follow the phone.
- Working trip card, accepted for now on 2026-10-01: the trip name and that trip’s signed balance sit on the card, over a passport-stamp graphic. Stamps are simple line drawings in one family. Each trip has its own color and shape. Each stamp is slightly rotated and off center, and fully visible. See the [tilted stamp card](/cursor/stores/bc-42260d9c-c439-46ce-b58f-df399fa36f24/media/trips-card-stamps-tilted.png).
- The header is only the signed amount: `-$42`, `$42`, or `$0`.
- Add expense is a sheet. Description and icon, large amount, keypad, then “Paid by you and split equally.”
- Copy sounds like a text to a friend.
- Starter icons: groceries, restaurant, coffee, drinks, gas, rideshare, flight, lodging, tickets, shopping, general.
