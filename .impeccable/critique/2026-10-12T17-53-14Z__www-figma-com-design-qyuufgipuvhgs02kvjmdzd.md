---
target: "Empty & failure comps X1–X10 + D6 (Figma 331:1812)"
total_score: 28
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-12T17-53-14Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: Figma Empty & failure section 331:1812 (X1–X10) plus D6 276:1429.

Heuristics: H1 3, H2 3, H3 3, H4 2, H5 3, H6 3, H7 2, H8 3, H9 3, H10 3. Total 28/40 (Good).

Design specificity:
- The stamps in X9 and X10 are TripSplit-specific.
- The banner is deliberately plain iOS.
- X8 is generic, which is correct (no stamps on errors).

Detector: exit 0, [] (no SwiftUI rules).

Measured:
- Banner text is Inter 12pt with no text style.
- Banner text contrast is 4.16:1 (fails AA). The fill against the page background is 1.13:1.
- Banner gaps are 0, 8, 12 or 16 pt. It sits flush under the nav bar in X3 and X4.
- Empty-state blocks sit 48–88 pt above center and 4.5 pt left of center.
- X6 "Not yet" is 56×22.
- Alert buttons are 135×44 and Retry is 200×50 (both pass).

Priority issues:
- [P1] Banner font and contrast. Fix: Footnote text style, primary text color.
- [P1] The shared alert has two bodies, and X5's Retry loops while offline. Fix: one body ("Check your connection and try again."). Retry re-checks the connection, and there's no second haptic.
- [P2] The banner doesn't say how stale the data is. Fix: "Updated 9:12 AM."
- [P2] Spacing drift in the banner and the empty states. Fix: 8 pt above and 12 pt below the banner; center the empty states.
- [P2] X10's tent stamp reads as one specific trip on All trips.

Personas:
- First-timer: Save looks active offline.
- VoiceOver: banner announcement, a hint on Save, stamps hidden.
- Flaky connection: the Retry loop, and no "back online" signal.

Minor:
- X5 still shows "YOU LENT" from P3.
- Alert button layers are still named "Try Again".
- D6's code still says "Try Again" (TRIP-33).

Questions: What does coming back online look like? Should Save be visibly blocked when the app knows it's offline?
