---
target: "Trips V1b boarding pass card (Figma 353:2949)"
total_score: 17
max_score: 24
na_heuristics: 3,5,9,10
p0_count: 0
p1_count: 2
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-12T23-55-51Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: the V1b Boarding pass · watermark bleed trip card. Component 353:2949; screens 353:3113 (light) and 354:3075 (dark).

Heuristics (H3, H5, H9 and H10 n/a): H1 3, H2 4, H4 2, H6 2, H7 3, H8 3. Total 17/24, 71%, Good.

Specificity: high. It shares its construction with the Member Tickets.

Detector: exit 0, [] (it has no SwiftUI rules).

Measured:
- The stub has 86 pt of content width; "You’re owed" needs 89 pt (15 pt) and an estimated 136 pt at AX1.
- Dates over watermark strokes: 4.37:1 in light (fails AA).
- Amounts: 5.3–9.3:1, with no watermark under them.
- Surface vs background: 1.12:1 light, 1.23:1 dark.
- Shadow: 6% at blur 10 (Member Ticket Figma: 7% at blur 14).
- Watermark: about 79% / 72% visible. It overlaps the name and dates boxes.
- The trip name wraps rather than truncating; about 19 characters fit.

Priority issues:
- [P1] Stub overflow. Fix: the stub width follows its text; at AX sizes, switch to V2's stacked layout.
- [P1] Watermark under the text. Fix: move it toward the tear line, keep the glyph whole, raise opacity to about 15%.
- [P2] $0, no-dates and settled-row states are undesigned.
- [P2] Chevron mismatch with the Member Tickets.
- [P3] Trip ink vs money green/red. Fix: neutral tear line.

Personas:
- First-timer: the faint stamp may read as a smudge.
- VoiceOver / large text: stub overflow; Increase Contrast should drop the watermark.
- Glancing one-handed: recognizes trips by name only.

Minor:
- Fixed −14° rotation on every card; vary it per trip.
- Long names wrap.
- Shadow and opacity aren't bound to tokens.

Questions: Could a settled trip become a "used" ticket? Should the stamp live in the detail header instead?
