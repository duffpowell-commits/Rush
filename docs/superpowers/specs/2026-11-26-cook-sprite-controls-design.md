# Cook sprites and phone controls

Duff's approved design, Nov 26: full-body animated 2D cooks (Dev, Mo, Jo) in the existing flat-ink kitchen. Primary goal is fewer accidental taps and more tangible interaction, not more kitchen mechanics.

## Approaches
Tap-to-command (chosen): tap a cook, highlight reachable stations, tap destination, then a big contextual FIRE/PLATE/RUN button. Drag-and-drop is an optional shortcut with cost preview and cancellation. Station-first contextual picker would add taps; not chosen.

## Requirements
- Keep existing kitchen, turn-based rules, action costs, stress previews, undo, perks, shop, save and pacing.
- Full-body sprites recognizable from existing portraits: idle, walking, cooking/working, plating/running and tired/rest states; no changing identities. Match current flat-ink art. Names, move count and stress stay legible, no color-only indicators.
- Tap visible sprite selects cook and never spends AP. The clickable target tracks rendered position during movement; larger phone-friendly target with deterministic nearest-sprite handling. Selection ring plus name. Tap a reachable station moves the selected cook, even if occupied; tapping current station does not silently spend an action. Action buttons alone commit FIRE/PLATE/RUN/PREP/RUSH. Invalid station and outside taps do not move or change selected cook. Existing ticket/dish selection remains.
- Drag only begins on a cook after a deliberate motion threshold; preview destination/cost; release on valid reachable station commits once, release elsewhere or cancel commits nothing. Do not process synthetic click twice. Pause/focus loss cancels drag.
- Preserve undo and clear selection after quit when appropriate. No real-time mechanics or 3D. No new paid assets. Use Foxboard/current approved art direction.
- Test phone touch at small and tall resolutions, overlap, edge taps, animated clicks, spent cooks, occupied stations, AP preview/commit and invalid/cancelled drags. No publication or blind review until existing release rules are satisfied.
