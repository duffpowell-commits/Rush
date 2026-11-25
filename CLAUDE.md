@AGENTS.md

# Rush (made from godot-game-starter)

A dinner service played like XCOM: the tickets are the enemy. Owner: Duff. Read this first; it is
the handoff between sessions. Commands, standing rules, guards and layout: AGENTS.md (imported above).

## Where things stand
- Side test: one week, Nov 24 to Dec 1, 2026. Lethemoor is the active game. Pitch + kill criteria:
  docs/PITCH.md. Queue: QUEUE.md (NOW = M1 slice). Progress: tasks/todo.md.
- Rules: `scripts/kitchen.gd` (pure logic, no nodes). Screen: `scripts/game.gd` PLAY section.
  Tests: `test_kitchen_*` in tests/run_tests.gd. Autoplay: TAP PASS + PLAY PASS drive a real service.
- Tuning lives in game.gd TUNE (ticket_time, crew_ap, stress_cap, service_turns, first_tickets,
  more_tickets): DEV MENU -> TUNE. Defaults: 9-minute tickets, 3 actions, stress cap 6, 20-minute
  service, 6 tickets in service 1 and +1 each service after.
- Nov 25 (audit, this is what changed): the curve was 5+2n, which the greedy bot lost 81% of the
  time in service 2 and 99% in service 3; it is now 6+1(n-1) (~40% / ~65%, `test_kitchen_service_curve`
  holds service 2 at or under 55%). A service now ends on a grade sheet (`Kitchen.grade()`, A-F:
  share of tickets out, minus a letter per walked table) with NEXT SERVICE. GAME OVER says why and
  redraws the board behind it. The save carries the service in progress (`Kitchen.to_dict` /
  `from_dict`, Save.VERSION 2), so PAUSE -> QUIT -> CONTINUE and a phone call pick up the same
  minute instead of rerolling with full lives. Five coach hints teach FIRE, END TURN, PLATE, RUN
  and switching cooks, one at a time. Ticket cards show each waiting dish's station; an empty
  station shows "N TO FIRE". The intro is Rush's own. The APK drops the template's 3D test scene
  and its 16 MB of models (export exclude_filter), so the dev menu hides those two buttons when
  the scene isn't in the build.
- Latest build: Releases -> `dev` -> `rush.apk`.
- Nov 24: Eyes (docs/EYES.md): a cloud session can run Rush, tap buttons, read the screen and
  screenshot it. `tools/eyes/smoke.json` plays a turn. Copied from the starter (Duff's OK).
- Next: Duff plays the APK; then real art and sound for the one service (QUEUE.md NOW).

## Claude-only notes
- `.claude/settings.json` runs `.claude/hooks/guard.py` before every Bash/Write/Edit call. A blocked
  call comes back with the reason; fix the cause, don't work around it.
- In that hook `--force-with-lease` is allowed; the Git pre-push hook still blocks any push that
  rewrites the remote branch, so plan on merging, not rewriting.
- Commit and push in separate Bash calls: a commit and push in one line is checked before the commit exists.
