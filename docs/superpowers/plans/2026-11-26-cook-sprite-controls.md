# Cook Sprite Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task. Steps use checkbox syntax.

**Goal:** Make Rush's cooks actual animated sprites and eliminate ambiguous touch actions.

**Architecture:** Retain Kitchen's pure rules. Separate visual hit testing and input gesture state from rule mutations in scripts/game.gd; rendering and hit tests share the same actual screen position.

**Tech Stack:** Godot 4.7.2, GDScript, current flat-ink assets, existing autoplay and Eyes harness.

**Spec:** docs/superpowers/specs/2026-11-26-cook-sprite-controls-design.md

## Constraints
Follow AGENTS.md, current QUEUE/HANDOFF, no rule changes, existing one-PR 8.5 pass, no blind AI review while paused. No paid assets or public posting. Preserve save compatibility and Kitchen.move/act semantics.

## Review focus
Moving targets, overlapping cooks, occupied station selection, no-move invalid taps, duplicated synthetic touch/mouse input, cancellation during focus loss.

### Task 1: Unambiguous tap controls
Files: scripts/game.gd (tap, station_hit, cook_pos, _cook_draw, _field_input), scripts/autoplay.gd, tests/run_tests.gd.
- [ ] Add failing regression checks: tap visible moving cook selects it but leaves AP; tap overlap chooses nearest visible cook; selected cook remains selected when tapping occupied reachable destination and spends only actual move cost; tap same/closed/unreachable station or blank space has no gameplay mutation; explicit action commits once. Preserve ticket selection and undo.
- [ ] Run tests and autoplay; confirm failure under old behavior.
- [ ] Implement shared visual position and nearest target selection helper; retire implicit station ownership switches and second tap handoff logic. Preserve station cost preview and existing explicit action handlers; highlight reachable destinations and display selected cook name.
- [ ] Add TAP COMMAND PASS autoplay evidence on touch viewport; update prior station-pick tests for intentional approved behavior. Run tools/test.sh and tools/autoplay.sh, expected TESTS PASS and AUTOPLAY PASS.
- [ ] Commit.

### Task 2: Full-body animated cooks
Files: assets/art/crew/ (new validated sprites), assets/art/SOURCES.md or existing art provenance ledger, scripts/game.gd crew drawing.
- [ ] Capture reference portrait and kitchen art for each cook, reuse palette and recognizable silhouettes; create consistent transparent sprites and sensible frame sheet, no unrelated style change. Verify licensing and identity. Record source and actual dimensions/frame layout.
- [ ] Add checks for all three character/state render paths, fallback for missing texture, large-text/readable labels, sprites staying within line and no obscured station/ticket. Use actual screen capture of 2 and 3 cooks sharing station and edge positions.
- [ ] Implement sprite idle/walk/work/plate/run/rest using existing animation/feedback and game state. Place badge/stress/name so it remains clear. Hit target follows actual rendered/animated position including bob offsets, not destination.
- [ ] Run tests/autoplay, capture gameplay evidence mobile narrow and tall with large text. Commit.

### Task 2b: Personality and stress-driven mood cues
- [ ] Extend sprite art references with fictional Dev/Mo/Jo identities listed in the spec; preserve existing portrait resemblance.
- [ ] Add tests for mood threshold transitions (calm, busy, frustrated, near quitting, then recovery) from the current stress value/cap; assert no change to AP, stress, costs or perk math. Critical warnings override flavor text; cap-change/undo/load should not replay stale chatter.
- [ ] Implement mood presentation and distinct occasional character callouts using existing caption/feedback infrastructure. Keep stress meter and selected cook readable at all sizes. Provide examples of all moods in real screenshots, with reduced effects enabled and disabled.
- [ ] Run TESTS PASS/AUTOPLAY PASS and record the mood evidence.

### Task 3: Optional drag shortcut
Files: scripts/game.gd input and focus handling, scripts/autoplay.gd.
- [ ] Tests: press-release under threshold selects only; deliberate drag from cook shows reachable target and preview; release valid commits one Kitchen.move; release invalid, pause, resize/focus loss cancel without AP; touch plus emulated mouse cannot double commit. Multiple fingers cannot commandeer active drag.
- [ ] Run test to observe failure; implement one gesture owner, threshold, preview and cancellation in existing GUI input. Use existing tap path for short taps; same move+undo path for valid drop. Drag toggle in Settings if necessary; default tap remains fully functional.
- [ ] Add DRAG COMMAND PASS and run TESTS PASS/AUTOPLAY PASS. Commit.

### Task 4: Release evidence
- [ ] Run full Tests, Autoplay and Eyes smoke using approved baseline (verify latest build, compare current mis-tap behavior). Save actual screenshots and short clip; on-device playtest still required.
- [ ] Update docs/HANDOFF.md, decisions log and task progress. One PR for implementation, separate independent fresh-eyes review of exact head and all CI gates green before merging. Verify exact dev APK and web build; never claim new 8.5 without evidence.
