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
  service, 7 tickets in service 1 (since the stations change) and +1 each service after.
- Nov 25 (audit, this is what changed): the curve was 5+2n, which the greedy bot lost 81% of the
  time in service 2 and 99% in service 3; it is now 6+1(n-1) (~40% / ~65%, `test_kitchen_service_curve`
  holds service 2 at or under 55%). A service now ends on a grade sheet (`Kitchen.grade()`, A-F:
  share of tickets out, minus a letter per walked table) with NEXT SERVICE. GAME OVER says why and
  redraws the board behind it. The save carries the service in progress (`Kitchen.to_dict` /
  `from_dict`, Save.VERSION 2), so PAUSE -> QUIT -> CONTINUE and a phone call pick up the same
  minute instead of rerolling with full lives. Five coach hints teach FIRE, END TURN, PLATE, RUN
  and switching cooks, one at a time. Ticket cards show each waiting dish's station; an empty
  station shows "N TO FIRE". The intro is Rush's own. The APK drops the template's 3D test scene
  and its imported models (export exclude_filter; ~2.2 MB: the 16 MB .glb sources never shipped), so the dev menu hides those two buttons when
  the scene isn't in the build.
- Nov 25 (Claude playtest, Duff picked "top 3"): tap a ticket card to make FIRE cook that table
  first (the button names the table); RUSH takes a minute off a cooking pan once a turn for
  `rush_stress` stress (TUNE); plating puts the dish on the pass window (`Kitchen.window`) and any cook
  at the pass runs it, so nobody carries plates. The window made the bot much stronger, so the curve
  is now 8 tickets + 1 per service (bot: s2 ~41%, s3 ~69% game over). Save.VERSION 3 moves a carried
  plate onto the window. Autoplay: PICK, RUSH, WINDOW PASS. Open from the playtest: grades only land
  A/C/F, and the sounds are the template's.
- Nov 25 (Duff: "all six" score fixes, "step by step", one PR each): PR #10 menu polish (painted
  title + drawn RUSH logo in `menu_art.gd`, order-slip intro, HOW TO PLAY `how_to_play.gd`, captions
  jump to the top under a sheet) and tips that carry between services (grade sheet SHOP,
  `upgrades.gd`, Save v4, best night in Settings). Next PR: a twist per service from 2 on
  (`Kitchen.EVENTS`: bus tour, grill on the fritz, VIP, critic; bot s2 ~43-52% per twist).
  Then stations by service (Duff's pick, Nov 25): service 1 is grill + fry, saute opens in 2, a new
  COLD station (salad, cake) in 3 (`Kitchen.OPENS`, PASS is now index 4, closed stations are walked
  past free, Save v5). Curve is now 7 + 1 per service (bot s1 ~8%, s2 ~32%, s3 ~48%, s4 ~71%).
  Still to come in order: juice, real sound, grades/difficulty that fit the player, then the ad kit.
- Nov 25 juice (PR #13): sparks, rings, floating words, shake and a stamped grade in game.gd (`fx`,
  `_fx_*`, `_stamp`). The shake and sparks follow Feel's shake_scale/spark_scale TUNE sliders; low graphics keeps the words.
- Nov 25 real sound: CC0 kitchen recordings from OpenGameArt (stove click + sizzle on FIRE, rush burst,
  plate clink, pass bell, burn, chair scrape for a walked table, door for a cook, dish crash game
  over, ticket printer) and cafe jazz (CC0) as `music_loop` with a synced `music_busy` layer
  (kitchen noise under the jazz) that rises as tickets go red (`_music_heat`). Built by
  `tools/make_sounds.py`; credits in assets/audio/SOURCES.md. Audio plays `.ogg` before `.wav`.
- Nov 25 grades + pace: `Kitchen.score_parts()` scores a service out of 100 (out 60, speed 25 from
  clock left at serve, clean pans 15, -10 a walk, critic +-8) and `grade()` maps it A+/A/B/C/D/F (bot
  s1 lands all six). Settings PACE (RELAXED/NORMAL/SLAMMED) and `house_ease` (-2..2: D/F or a lost
  night eases a ticket, A/A+ adds one) move ticket count and clock (`pace_adjust`, `tickets_for`).
- Nov 25 ad kit: CI exports a Web build (preset "Web", threads off, audio unlock in head_include) and
  pushes it to gh-pages on main: https://duffpowell-commits.github.io/Rush/. The build clip is Rush
  itself now (`_record_kitchen_clip`: service 3 via `game.bot_step()`, no coach, no captions), not the
  template's 3D scene. Copy + links: docs/AD_KIT.md. Nothing posts without Duff's yes.
- Nov 25 trays (Duff: "start out with the one dish ran rule and then upgrade it in the shop for a max
  of 4"): a RUN carries `Kitchen.tray` plates for one action (1 to start). SHOP row SERVER TRAY ($30,
  2 plates) then ENTREE TRAY ($90, 4; needs the server tray), `Upgrades.shown()`. The most urgent table
  goes first and its other plates ride along. The bot's curve is unchanged (tray 1). TRAY PASS.
- Nov 25 station pick (Duff: "tap the station and get the employee that dropped it"): a station tap
  picks the cook standing there, else the cook who fired its pan (`pans[s].by`, wears their initial),
  and only an empty station sends the selected cook over (`station_cook`). A 2nd tap on the same
  station sends the cook you had picked (`_pick_from`: MO plates DEV's burger). STATION PICK PASS.
- Nov 25 balance pass (Duff's pick after Claude played): ENTREE TRAY $60 -> $90 (lands ~service 3);
  speed points full at 70% of the clock left, none under 30% (was 75%/35%), so a clean service served
  with half the clock left grades A; coach hints placed in pixels just above the stations (COACH PASS
  checks it), since a fraction of the height hit the station names on a tall phone's browser.
- Nov 25 tap a dish (Duff's pick): a tap on a waiting dish's row of a ticket card picks that dish
  (`pick_ix`, `dish_at`, rows DISH_ROW0/DISH_ROW); FIRE cooks it when the cook is at its station and the
  button names it ("FIRE STEAK"), else falls back to the table's first dish there (`fire_pick(c, tid, ix)`).
  DISH PICK PASS.
- Nov 25 first-time-player review (7/10; reviews are played blind now, Duff's rule): polish pass. Ticket
  rows say "at GRILL" / "cooking" / "on the pass" / "served" (struck) instead of ~ > V; the NEXT bar is
  words ("1 dish in 2 min", `next_line`); hidden tickets get a "+N MORE" badge (red if one is red);
  a pan about to burn says PLATE NOW and END TURN reads "END TURN / GRILL BURNS"; the idle button says
  TAP A STATION; coach hints sit on a dark band; sound captions sit above the status line
  (`Subs.lift`) in a softer style; the shop lists OWNED. POLISH PASS.
- Nov 25 hints from that review (Duff: "Yes"): TAP FIRE TO COOK (was "tap grill"), DOTS ARE MOVES LEFT
  after the first END TURN, PASS: RUN SERVES IT. test_coach_hints_short checks the last two.
- Nov 25 blind review #2 (7/10) fixes: a coach hint the player ignores retires after `COACH_TURNS` (3)
  turns (`Coach.retire`); END TURN names a cook who would quit ("END TURN / MO QUITS", `cooks_quitting`
  mirrors Kitchen.end_turn's stress sums); TIRED under a cook 2 from the cap; new hint IDLE COOKS LOSE
  STRESS; a spent cook's button says "DEV: NO MOVES LEFT"; events joined with " | "; a quit cook shows
  QUIT at their spot (the WALKED OUT line is gone); GAME OVER buttons wait 1 s; HOW TO PLAY says
  SCROLL FOR MORE until the end. POLISH + GAMEOVER PASS check them.
- Latest build: Releases -> `dev` -> `Rush.apk`.
- Nov 24: Eyes (docs/EYES.md): a cloud session can run Rush, tap buttons, read the screen and
  screenshot it. `tools/eyes/smoke.json` plays a turn. Copied from the starter (Duff's OK).
- Next: Duff plays the APK; then real art and sound for the one service (QUEUE.md NOW).

## Claude-only notes
- `.claude/settings.json` runs `.claude/hooks/guard.py` before every Bash/Write/Edit call. A blocked
  call comes back with the reason; fix the cause, don't work around it.
- In that hook `--force-with-lease` is allowed; the Git pre-push hook still blocks any push that
  rewrites the remote branch, so plan on merging, not rewriting.
- Commit and push in separate Bash calls: a commit and push in one line is checked before the commit exists.
