@AGENTS.md

# Rush (made from godot-game-starter)

A dinner service played like XCOM: the tickets are the enemy. Owner: Duff. Read this first; it is
the handoff between sessions. Commands, standing rules, guards and layout: AGENTS.md (imported above).

## Where things stand
- Side test: one week, Nov 24 to Dec 1, 2026. Lethemoor is the active game. Pitch + kill criteria:
  docs/PITCH.md. Queue: QUEUE.md (NOW = M1 slice). Progress: tasks/todo.md.
- Rules: `scripts/kitchen.gd` (pure logic, no nodes). Screen: `scripts/game.gd` PLAY section.
  Tests: `test_kitchen_*` in tests/run_tests.gd. Autoplay: TAP PASS + PLAY PASS drive a real service.
- Tuning lives in game.gd TUNE (ticket_time, crew_ap, stress_cap, service_turns): DEV MENU -> TUNE.
  Defaults: 9-minute tickets, 3 actions, stress cap 6, 20-minute service. Greedy bot clears ~6 of 7
  tickets in service 1 and ~4 of 9 in service 2.
- Latest build: Releases -> `dev` -> `rush.apk`.
- Next: Duff plays the APK; then real art and sound for the one service (QUEUE.md NOW).

## Claude-only notes
- `.claude/settings.json` runs `.claude/hooks/guard.py` before every Bash/Write/Edit call. A blocked
  call comes back with the reason; fix the cause, don't work around it.
- In that hook `--force-with-lease` is allowed; the Git pre-push hook still blocks any push that
  rewrites the remote branch, so plan on merging, not rewriting.
- Commit and push in separate Bash calls: a commit and push in one line is checked before the commit exists.
