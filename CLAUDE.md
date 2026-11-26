@AGENTS.md

# Rush (made from godot-game-starter)

A dinner service played like XCOM: the tickets are the enemy. Owner: Duff. Read this first; it is
the handoff between sessions. Commands, standing rules, guards and layout: AGENTS.md (imported above).

## Where things stand
- Short handoff for any coding AI (state, next steps, how to check): docs/HANDOFF.md. Update it
  after every chunk of work.
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
  STRESS; a spent cook's button says "DEV: NO MOVES"; events joined with " | "; a quit cook shows
  QUIT at their spot (the WALKED OUT line is gone); GAME OVER buttons wait 1 s; HOW TO PLAY says
  SCROLL FOR MORE until the end. POLISH PASS checks the quit warning and spent button, GAMEOVER PASS
  the tap guard, test_quit_warning_matches_end_turn the prediction against end_turn on random states.
- Nov 26 blind review #3 (6.5/10: stress was how they lost and they barely saw it): a stress meter per
  cook (one box per point to the cap + "STRESS 2/6" / "TIRED 5/6"), intro card 3 says cooks quit;
  a QUIT marker never draws over a working cook; GAME OVER says a new night starts at service 1
  (button NEW NIGHT); tap +N MORE to page the rail (`rail_off`, `_more_rect`; BACK returns);
  bigger ticket/station text; Settings CONTROLS lists only `Controls.SHOWN` (pause); SHOP NEW! only
  until opened. RAIL PAGE, SHOP NEW, GAMEOVER PASS.
- Nov 26 build-70 reviews (first-timer 7, IGN-style 7, Claude 7; all three: stress reads too late).
  Duff: "Yes" to the stress pass. The meter previews END TURN (`stress_after(c)`, same sums as
  Kitchen.end_turn: boxes it adds outlined red, rest outlined green, "+1"/"-2" on the plate) and floats
  "+N STRESS" after; END TURN warns a turn early ("MO NEAR QUIT", after QUITS and BURNS); the rest hint
  shows at cap-3; the action button names the cook ("DEV: PLATE"); no two tickets share a table
  number (`_make_ticket`); pan labels shrink before cutting words; stress plates narrow to the gap
  between cooks. STRESS PASS, test_table_numbers_unique, test_quit_warning_matches_end_turn.
- Nov 26 build-73 reviews (first-timer 7, IGN-style 7.5, Claude 7.5; all three tripped on moving
  cooks). Duff: "Yes" to the movement pass. With a cook picked, every other open station shows
  "WALK n" or "TOO FAR" (hidden when they're spent); a walk that can't happen says why
  (`_too_far`: "TOO FAR: MO NEEDS 4 MOVES, HAS 1" / "MO: NO MOVES LEFT", plus a floating word); a
  tap on a cook's face always wins (`_portrait_pick`: the next station tap sends that cook instead
  of picking the station's cook); an empty rail reads "END TURN / FINISH SERVICE"; RUSH says
  "+1 STRESS" or "(FREE)" after Cast Iron; the top bar's OUT counts this service. MOVE, FINISH PASS.
- Nov 26 8.5 pass (Duff's new bar: plan to an 8.5 blind first-timer review, OK'd once, built in one
  pass; he picked "Build all of it"). Fairness: SHOP TEMP COOK ($45, a third cook JO at the pass for
  one service, `Kitchen.hires`, erased in `_service_done`); service 4+ is a ticket lighter; the
  second ticket lands at once from service 2 (a minute in on service 1). Clarity: END TURN names
  every burn and quit ("GRILL + FRY BURN"), FIRE says ": TOO LATE" when the dish can't beat the
  table, a cook's first move shows its stress ("+1 STRESS" / "(MO QUITS)"), the status line clears on
  the first move, a tap in the strip under a station picks its cook, window plates wear "T12", walk
  chips sit above station names. Feel: cooks walk (`_cook_draw`), steam over pans, red-ticket jolt,
  bigger burns, a CRITIC stamp on the grade sheet. Loss: RETRY SERVICE n keeps bank + upgrades
  (`retry_service`). Bot: s1 ~7%, s2 ~33%, s3 ~41%, s4 ~41% lost. WARN, RETRY PASS; GRADE FIT has the critic.
- Nov 26 build-79 blind first-timer: 7/10, too easy now (Temp Cook twice + Cast Iron, A+ with stress
  at 0). 8.5 plan #2 (Duff: "Build all of it"): TEMP COOK doubles each hire tonight
  (`Upgrades.price`, `temp_buys` in the save, kept by RETRY); every two upgrades bring +1 table
  (`Upgrades.load_tickets`, in `k.first_tickets` and `tickets_for`; the shop says so); new twists
  HEAT WAVE (working cooks +1 stress on odd turns, `Kitchen.heat_turn()`, mirrored in `stress_after`)
  and PARTY OF 12 (one more big table mid-service); a spent cook is grey with DONE, the rest wear a
  moves-left number; the face-then-station hint ("TAP FACE, THEN STATION") shows after the first
  END TURN, and the dots hint reads "NUMBER = MOVES LEFT". PUSHBACK, HEAT PASS; test_shop_pushes_back.
- Nov 26 (Duff: build the fixes, skip reviews to save usage): the grade sheet's "Next: N tickets"
  redoes itself after a shop buy (`_refresh_points`); PARTY OF 12 lands at turn >= turns/3 and keeps
  `incoming` in arrival order; a move that costs a tired cook (stress >= cap-3) their rest says "SKIPS REST"; with a cook
  picked, each station's name row becomes a two-line chip (FRY / WALK 1, SAUTE / TOO FAR) (above the
  station a coach hint hid it; at the foot it hid UP! / PLATE NOW). Bot loss with all six twists:
  s1 7%, s2 36%, s3 50%, s4 50%, s5 73%.
- Nov 26 build-84 blind first-timer: 7/10 (service 1 easy, service 2 a wall, busy rail unreadable, stress
  late, losses snowball; docs/reviews/firsttimer_rush_build84.md). 8.5 plan #3 (Duff: "Build all of it"):
  no twist in service 2 (twists from 3), acing service 1 doesn't stack service 2, shop nudges TEMP COOK;
  URGENT band on the first-to-walk ticket and red "N WAITING" on an unmanned station with work; hint
  FULL STRESS = QUITS and a red face ring 2 from the cap; second wind (`Kitchen.breaks`, TUNE): the first
  cook who'd quit in a service takes five instead (BREAK, "DEV TAKES 5"); bigger moves badge, DONE hint,
  COMP CARDS -> SECOND CHANCE. `Kitchen.count_for` holds the ticket curve. Bot: s1 7%, s2 22%, s3 50%,
  s4 50%, s5 73%. WIND, URGENT, NUDGE PASS. Details: docs/HANDOFF.md.
- Nov 26 build-89 IGN-style review: 7.0 (fiddly taps, early services easy then a service-3 spike,
  identical cooks). 8.5 plan #4 (Duff: "Build all of it", plus: pay every grade more, perks earned by
  level-up): narrow closed stations + whole-column tap zones; UNDO once a turn; service 2 gentle twist
  (VIP/critic), 3 none, all from 4; A at 90, speed full at 75%; `GRADE_BONUS` $10-$30 every service;
  LEVEL UP after each service (hardest worker picks 1 of 3 perks: station hands, RUNNER, QUICK PLATE,
  LIGHT FEET); a cook who walks out is gone for the rest of the night (`gone`, RETRY brings them back);
  cooks bob and flinch. LEVELUP, UNDO PASS; test_cook_perks. Details: docs/HANDOFF.md.
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
