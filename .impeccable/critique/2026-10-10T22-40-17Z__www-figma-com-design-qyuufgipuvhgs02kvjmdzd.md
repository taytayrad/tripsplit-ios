---
target: "Profile comps 21/21b (Figma 42:3501)"
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-10T22-40-17Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: Figma Profile [21] 34:2071 and Sign out confirm [21b] 40:3416, section 42:3501.

Heuristics: H1 1, H2 3, H3 3, H4 2, H5 1, H6 3, H7 2, H8 3, H9 1, H10 4. Total 23/40 (Acceptable).

Design specificity: a generic iOS Settings page. It has no stamp, no save model, and no permission state.

Detector: not applicable to Figma or SwiftUI (exit 0, []).

Measured:
- The footnote and Sign out sit under the tab bar, and Sign out is clipped by 11 pt.
- Section gaps are 28/20 pt, against 8/12 on the newer screens.
- The unchecked check ring is 1.71:1.
- The text minimum is 4.69:1.
- The alert is custom, not native.
- The pay-method rows reuse Split Row.

Priority issues:
- [P1] The Venmo check and the username field are one value. A mistyped username sends money to a stranger, and an empty field saves silently. Fix: one Venmo row, autosave, validation, and "Check in Venmo".
- [P1] The switches ignore the iOS notification permission. Fix: a not-determined row and a denied row with Open Settings; the switches are disabled when notifications are denied.
- [P1] The layout has drifted: things are hidden under the tab bar, the spacing differs, the alert is custom, the name shows "Taylor" not "Taylor R.", and the Main Header may not belong. Fix: Edit trip's layout, the native alert, and a decision on the header.
- [P2] Delete account is missing (App Store 5.1.1(v)). Fix: a row and a confirmation, plus a decision on how a deleted person appears on shared trips.
- [P2] The switch labels are narrower than the behavior, and undelete vs restore is inconsistent. Fix: "Payments with you" and "Someone deletes or restores a trip"; add the term to the glossary.

Personas:
- Jordan: no context for the pay methods.
- Sam: the checks need the selected state, and the section labels need to be headers.
- Casey: Sign out sits behind the tab bar.

Minor:
- "Get paid with" and onboarding's "How do you get paid?" use different wording.
- No off or empty states are shown.
- The name isn't editable.
- No app version.
- No stamp.
