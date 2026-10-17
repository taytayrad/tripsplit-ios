---
target: "Trips list comps L1/L2 (Figma 240:4413)"
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-10T04-42-30Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: Figma Trips comps L1 (240:4415) and L2 (240:4515).

Heuristics: H1 3, H2 2, H3 3, H4 2, H5 2, H6 2, H7 3, H8 3, H9 3, H10 3. Total 26/40 (Acceptable).

Design specificity: partly specific to TripSplit. Stamps, ink-tinted cards and red/green amounts are TripSplit's own. Both "add" affordances are generic: the icon "+" and a kanban-style dashed card.

Detector: not applicable (it scans web markup; the target is a Figma design for SwiftUI). Exit 0 with [].

Mechanical checks:
- The dashed outline of the Add trip card is 1.53:1 (fails 3:1).
- The selected tab label is 3.29:1 (fails; shared Tab Bar component).
- "Settle up" is a 22 pt tall tap target.
- The 32 pt "+" circle sits inside a 44 pt frame.
- The 4th settled card would sit under the tab bar on an 874 pt screen.

Priority issues:
- [P1] "+" reads as "add trip" next to "+ Add trip". Fix: Label("Add expense", systemImage: "plus"); reads "Add trip" when you have no trips.
- [P1] The dashed outline is near invisible (1.53:1). Fix: a darker stroke (about 3:1) or a tinted outline.
- [P2] The rare action outweighs the frequent one, and the frequent one is out of thumb reach. Fix: label "+" now; later prototype a bottom "Add expense".
- [P2] Settled cards get full weight with a bare "$0". Fix: compact or desaturated cards with a "Settled" label; "Show 2 settled trips".
- [P2] Small tap targets ("Settle up" 22 pt; tab label contrast). Fix: a 44 pt hit area; a tab tint with ≥4.5:1 contrast.

Answer: label "+" as "+ Add expense".
