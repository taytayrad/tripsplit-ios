# TripSplit

Native iPhone app (SwiftUI, iOS 17+) on Supabase, for close friends to split trip costs and settle up. USD, English, at most 20 members per trip.

## Sources of truth

- **Product behavior and copy:** `prd.md`. The "Decisions" and "Prototype decisions" sections at the end override earlier text. `product-plan.md` is history; the PRD wins any conflict.
- **Words:** `docs/glossary.md`. Use its terms in code and copy ("settled", never "square").
- **Visual design:** the Figma file in `docs/screen-map.md`. Use variables and components; their Dev Mode code syntax is the SwiftUI to write.

## Read before you touch

- **Planning or picking up work:** `docs/implementation-plan.md`. Phases with exit criteria; finish a phase's exit criteria before starting the next.
- **Money** (splits, shares, balances, payments, allocation, rounding): `docs/money-rules.md`. Turn its golden cases into tests before writing the code they cover. All money is integer cents.
- **Schema, migrations, or RPC functions:** `docs/data-model.md`
- **RLS or who-can-do-what:** `docs/permissions.md`
- **Activity rows or push notifications:** `docs/events.md`
- **Screens, navigation, or presentation (sheet, push, alert):** `docs/screen-map.md`
- **Cross-system flows** (invite links, realtime, payment logging): `docs/flows.md` and `docs/architecture.md`

## Working in the repo

- **iOS:** the Xcode project is generated. Edit `ios/project.yml`, then run `xcodegen` in `ios/`; `TripSplit.xcodeproj` is not committed. Tests use Swift Testing.
- **Database:** `supabase db start`, then `supabase db reset` (migrations + `seed.sql`), then `supabase test db` runs the pgTAP tests in `supabase/tests/database/`. Tests act as signed-in people through helpers in `seed.sql` (`tests.users`, `tests.trip`, `tests.equal`, `tests.authenticate_as`); seed files never reach the hosted project. New functions must be granted to `authenticated` explicitly (anon gets nothing).
- **Two people locally:** Debug builds sign in as a named test person (anonymous auth, local only). Run one simulator per person; open an invite with `xcrun simctl openurl <udid> tripsplit://join/<token>`.
- **CI:** `.github/workflows/ci.yml` runs both on every PR.

## Rules that bite

- Money writes go through Postgres functions in one transaction; the app never inserts expenses, shares, or payments directly. Balances are calculated, never stored.
- Never collect or display a phone number. No Contacts matching.
- A payment exists only once logged in TripSplit. Returning from Venmo, Zelle, or Apple Cash records nothing.
- Stamps contain no letters or words and are always fully inside their frame.
- When a design or product decision is made during the build, add it to `prd.md` under "Prototype decisions", so the PRD stays the single record.
