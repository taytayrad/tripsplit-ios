---
target: "Expense details comps D1-D3 (Figma 271:1018)"
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-10T18-41-14Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: Figma Expense details comps D1 (271:1020), D2 deleted (271:1083), D3 restore alert (271:1151), section 271:1018.

Heuristics: H1 3, H2 3, H3 2, H4 2, H5 2, H6 3, H7 2, H8 3, H9 2, H10 3. Total 25/40 (Acceptable).

Design specificity: mostly generic (an iOS grouped list). The only TripSplit-specific parts are the wording and the trip-style header; no stamp appears. Suggestion: put the trip's stamp in the Trip row.

Detector: not applicable to Figma or SwiftUI (exit 0, []).

Measured:
- Contrast passes; the lowest is 4.69:1.
- Every tap target is at least 44 pt.
- Long titles get cut off (about 540 pt needed, 302 pt available).
- Body spacing is 16 pt against 12 pt on T1.
- The D3 alert buttons have no text style.

Priority issues:
- [P1] Restore contradicts the PRD ("deletes are permanent") and the shipped delete alert ("This can't be undone"). Fix: record the decision, reword the delete alert, plan the soft-delete schema and an expense_restored event.
- [P1] Restore edge cases are undesigned:
  - a member who has left (the departed-member trigger would refuse the restore)
  - an expense on a deleted trip
  - a failed save
  Fix: add frames D4 (blocked), D5 (the trip is deleted), and a Retry state.
- [P1] The split column means different things: Tyler shows $40 in D1 and $20 in D2. A payer outside the split and exact/percent splits are undesigned. Fix: D2 shows D1's numbers and labels in gray; add those variants.
- [P2] The $60 outranks the viewer's own amount, and red is used for other people's debts too. Fix: add a balance block, or emphasize the viewer's row.
- [P2] The deleted state relies on strikethrough and gray only (VoiceOver is silent), and long titles get cut off. Fix: a tinted banner with a glyph, accessibility labels, and wrap titles to 2 lines.

Personas:
- Jordan misreads "Owes" and may miss Restore.
- Sam: the strikethrough is silent, and "Restore" needs an object.
- Casey: Restore sits in the hardest corner to reach.

Minor:
- Dates don't show the year rule.
- "Added by" is missing.
- The Trip row has no chevron and duplicates the back label.
- Row order is undefined.
- A frame in D3 is still named "Remove".
