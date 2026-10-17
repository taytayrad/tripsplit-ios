---
target: "Stamp builder B1–B3 (Figma 367:3652)"
total_score: 24
max_score: 32
na_heuristics: 9,10
p0_count: 0
p1_count: 2
target_identity: "url:https://www.figma.com/design/qyUUFgiPUvHGS02kVJMDZD"
timestamp: 2026-10-13T01-38-44Z
slug: www-figma-com-design-qyuufgipuvhgs02kvjmdzd
---
Method: dual-agent. Target: the Stamp builder, B1–B3, in section 367:3652.

Heuristics (n/a: 9, 10): H1 3, H2 2, H3 3, H4 3, H5 4, H6 4, H7 3, H8 2. Total 24/32, 75%, Good.

Specificity: partial. The preview is TripSplit; the three tile grids are a generic avatar builder.

Detector: exit 0, [].

Measured:
- Every ink is ≥3:1 on its tile (lowest: orange, light, 3.92).
- Selection ring vs blue swatch: 1.11 (light).
- Protan/deutan ΔE, blue vs purple: 2.1–6.7.
- Shuffle label: 4.08 (dark); capsule is 34 pt tall.
- Cancel/Done have no hit frames.
- The sheet fits with 0 pt to spare.
- Builder text is not on text styles.

Priority issues:
- [P1] Color-only selection, and blue/purple are confusable. Fix: checkmarks, VoiceOver labels, a preview value.
- [P1] Glyph names (market = cart, palm = umbrella). Fix: spoken names.
- [P2] Shape tiles are noisy. Fix: outlines only.
- [P2] Large text and reaching Done. Fix: pinned compact preview, live edits, confirm on swipe-dismiss.
- [P3] Shuffle is weak. Fix: 44 pt tinted button that also re-rolls tilt.

Personas: entry point (tap = shuffle vs builder); color-blind/VoiceOver; Done reach.

Minor:
- Add a stamp-down haptic and scale on change.
- The trip name isn't in the builder.
- B1's nav bar is out of date.
- Tile separation is 1.12.

Questions: Make Shuffle-first the default? Suggest the symbol from the trip name?
