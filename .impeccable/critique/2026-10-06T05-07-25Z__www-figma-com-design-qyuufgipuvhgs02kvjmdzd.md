---
target: "Net model comps (Figma 110:3805)"
total_score: 22
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 3
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-06T05-07-25Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: Figma section 110:3805, "Net model — proposal for review" (9 iOS comps).

Heuristics: H1 3, H2 2, H3 2, H4 1, H5 3, H6 2, H7 2, H8 2, H9 2, H10 3. Total 22/40 (Acceptable).

Design specificity: category-interchangeable except the N1 simplification footnote. The stamp is absent from money moments, and N5 (settled) reads as empty.

Detector: not applicable (it scans web markup; the target is Figma for SwiftUI). `detect` on ios/TripSplit/Trips returned [] with exit 0. Mechanical checks:
- No contrast failures (lowest 4.69:1).
- Pay pill is 32pt tall (fails 44pt); date and member chips are 28pt tall (fail).
- Add expense is below the fold on N1 (y922) and N5 (y944); Delete trip is below the fold on N6 (y849).
- More than 4 choices on N1, N5 and N6.

Priority issues:
- [P0] N3 person screen contradicts per-trip payments and adds a detour. Fix: Pay opens a method sheet directly; delete N3.
- [P1] Add expense is below the fold (user-reported, confirmed by measurement). Fix: pin it to the bottom, in the thumb zone.
- [P1] N5 settled state reads as disabled or empty. Fix: celebrate it with the stamp; collapse balances.
- [P1] N7 and N9 alerts are dead ends. Fix: add an action ("Pay Tyler $30"); use native alert styling.
- [P2] N1 repeats $30 three times; Balances competes with the primary action; the Pay pill is 32pt. Fix: put Pay next to the hero, open a Settle up sheet, and drop Balances from N1.
- [P2] N4 partial-amount edit is a hidden tap. Fix: make the amount a visible editable field.

Personas:
- Jordan: why pay Tyler is explained only on N1; N2 and N3 share a title; "You · Owes" reads wrong.
- Casey: the Pay pill is mid-screen and 32pt; Venmo and Zelle look identical.
- Sam: the hero needs one combined accessibility element; swipe-to-remove needs a custom action; Dynamic Type will break the right-aligned amounts.

Minor:
- Owed-state Settle up action is undesigned.
- Rounding to $0.01 can block removal.
- Delete trip has no unsettled guard.
- N2's "Tyler's expenses" includes dinner, which Tyler didn't pay for.
- Annotations are styled like UI copy.
- The glossary needs updating.
