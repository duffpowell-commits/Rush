# HANDOFF: pick up Rush from here (any coding AI)

Plain log for whoever builds next: Claude, Grok, Codex or anyone else. Also read docs/DECISIONS.md
(dated decisions) and tasks/todo.md (progress) as AGENTS.md says. Update it at the end of
every chunk of work, not only at the end of a session. Rules for every agent: AGENTS.md (read it
first). Dated history of every change: CLAUDE.md "Where things stand". This file is the short
version: where we are, what's next, how to check it.

Last updated: 2026-11-26 17:00 UTC (Claude).

## Studio mascot (Duff, Nov 26)
- **The three-eyed fox is in every game as a rare cameo, not a pal**: a small event
  that matters but never ruins a run. Duff OKs the fox art on a card before it's built. Rule + this game's idea: `docs/MASCOT.md`.

## Where it is right now
- main = `c56d586` (PR #32, plan #3), build 89. 8.5 plan #4 is on the working branch (see below). Live builds:
  - Web: https://duffpowell-commits.github.io/Rush/ (gh-pages, pushed by CI on every main push;
    the gh-pages commit message reads "web build <sha7>").
  - APK: Releases -> `dev` -> `Rush.apk`; `version.json` on the same release shows `{"code", "sha"}`.
    Build 89 = c56d586.
- Open PRs: none. Working branch for Claude sessions: `claude/project-thread-qt0oe2` (reset from
  main at the start of each PR; nothing unmerged on it).
- Side test window: Nov 24 to Dec 1, 2026. Duff decides keep or park on Dec 1 (kill criteria in
  docs/PITCH.md). Lethemoor is the active game; Rush must not pull effort from it without Duff.

## The bar: 8.5 from a blind first-time player (Duff's rule, Nov 26)
Before building a round, write an "8.5 plan" (the short list a first-timer needs to score it 8.5),
get Duff's OK on it once, build it in ONE PR, then run ONE blind first-timer review and report the
score. No one-fix-per-PR loops. A "blind" reviewer plays only the live web build, reads nothing in
the repo, and plays like a new player (see "How to run a blind review").

Score history (first-timer / IGN-style / Claude):
| Build | First-timer | IGN | Claude | Main complaint |
|---|---|---|---|---|
| 70 | 7 | 7 | 7 | stress shows too late |
| 73 | 7 | 7.5 | 7.5 | moving cooks confusing |
| 76 | 7.5 | 7.5 | - | warnings, pacing, feel |
| 79 | 7 | - | - | too easy once upgraded (Temp Cook x2 + Cast Iron, stress 0) |
| 81 | not run | - | - | - |
| 84 | 7 | - | - | s1 too easy, s2 a wall (new station + twist + more tickets), busy rail hard to read, stress spikes late, losing snowballs |
| 89 | - | 7.0 | - | fiddly taps, s1-2 easy then s3 spike, cooks identical, thin animation |
Reviews: `docs/reviews/` (copies of the ones saved so far; earlier first-timer reviews 1-3 and
builds 70-76 were reported in chat only, and their findings are in CLAUDE.md).

## What builds 79 and 81 added (the last two 8.5 rounds)
- Build 79 (PR #27): TEMP COOK shop item (3rd cook, one service), service 4+ one ticket lighter,
  second ticket arrives at once from service 2, END TURN names every burn and quit, FIRE says
  TOO LATE, first move shows its stress cost, tap under a station picks its cook, window plates
  show table numbers, cooks walk, steam, red-ticket shake, critic stamp, RETRY SERVICE on game over.
- Build 81 (PR #28): TEMP COOK price doubles per hire tonight ($45, $90, $180; `temp_buys` in the
  save); every 2 upgrades add +1 table a service (`Upgrades.load_tickets`); twists HEAT WAVE
  (working cooks +1 stress on odd turns) and PARTY OF 12 (one extra big table); spent cooks grey
  with DONE, others show a blue moves-left number; hint "TAP FACE, THEN STATION" after turn 1.

## 8.5 plan #3 (Duff: "Build all of it", Nov 26, after the build-84 review)
- Ramp: service 2 has no twist (twists from service 3, `n >= 3` in `Kitchen.start`); acing service 1
  doesn't add a ticket to service 2 (`_house_reads`); the shop says "Next: N tickets, 2 cooks. TEMP COOK
  helps." until a temp is hired. Ticket counts live in one place: `Kitchen.count_for` (game.gd's
  `tickets_for` calls it). Tried 8 tickets in service 1: bot loss went 8% -> 26%, so it stays 7.
- Rail: the table that walks first wears a red URGENT band (`urgent_tid`); a station with waiting dishes
  and nobody there throbs red with "N WAITING" (`waiting_at`, `manned`).
- Stress: hint "FULL STRESS = QUITS" the first time stress rises; a cook 2 from the cap gets a red face
  ring and a red name plate.
- Second wind: `Kitchen.breaks` (1 a service, TUNE "breaks"): the first cook who'd quit takes five
  instead (stress to cap-3, no moves next turn, `crew.brk`, drawn BREAK). END TURN says "DEV TAKES 5";
  `cooks_quitting()` skips them and `cooks_breaking()` names them.
- Polish: bigger moves-left badge, hint "DONE = NO MOVES", COMP CARDS renamed SECOND CHANCE.
- Bot (greedy, 200 seeds, twists on): s1 7%, s2 22%, s3 50%, s4 50%, s5 73% lost (s2 was 36%).
  The bot never reaches the cap (it rests at cap-2), so the second wind doesn't move its numbers.
- Checks: WIND, URGENT, NUDGE PASS; TWIST PASS now expects no twist in service 2; test_second_wind_and_ramp.

## 8.5 plan #4 (Duff: "Build all of it" + three adds in chat, Nov 26, after the build-89 IGN review)
- Taps: open stations share the width and a closed one is a narrow "OPENS S2" slot (`station_rect`,
  `CLOSED_W`); a station's tap zone is its whole column plus a strip above (`station_hit`).
- UNDO (top corner opposite PAUSE): takes back the last move or action, once a turn (`_snap`, `undo`).
- Curve: service 2 rolls a gentle twist (`Kitchen.MILD_EVENTS`: VIP or critic), service 3 none (cold
  opens), the full set from 4. A needs 90 (was 87); speed points full at 75% of the clock left.
- Payout (Duff: "a higher rate for all grades so that if you cant make one session it doesnt
  automatically ruin the next"): `Kitchen.GRADE_BONUS` A+ $30, A $25, B $20, C $15, D/F $10 on top of tips.
- Cook perks, earned (Duff: "make the perks earn able like a level up system"): cooks start bare; after
  each service the cook with the most actions (`crew.acts`, `game.mvp()`) levels up and the player
  picks 1 of 3 (`perk_offer`, seeded so a reload offers the same three) on a LEVEL UP sheet before the
  next service. Perks: GRILL/FRY/SAUTE/COLD HAND (that station's dishes 1 min faster), RUNNER (first
  RUN each turn free), QUICK PLATE (first PLATE free), LIGHT FEET (first step free). `Kitchen.PERKS`,
  `crew.perks/used`, `game.cook_perks` + `levelup` in the save, kept by RETRY. No downsides yet.
- Quitting hurts (Duff's pick, Nov 26: "Gone for the whole night"): a house cook who walks out sits out
  every later service tonight (`game.gone`, saved; `Kitchen.gone` skips them in `start`). RETRY brings
  them back. The grade sheet says "MO WALKED OUT: GONE FOR TONIGHT"; the shop counts the cooks left.
- Feel: a working cook bobs, a cook at a burned station flinches.
- Bot (no perks, greedy, 200 seeds): s1 7%, s2 22%, s3 37%, s4 50%, s5 73% lost. Perks make a real
  night easier as it goes; the bot never earns any.
- Checks: LEVELUP, UNDO PASS; TWIST PASS expects a VIP/critic twist in service 2; test_cook_perks.

## Next, step by step
1. Duff's call on Nov 26: blind reviews are paused to save usage; build fixes and merge on green
   CI plus a fresh-eyes check. Other games are paused; Rush continues.
2. Done Nov 26 after build 81: grade sheet "Next: N tickets" refreshes after a shop buy; PARTY OF 12
   lands mid-service on short nights; "SKIPS REST" on a move that costs a tired cook their rest;
   walk chips now take over the station's name row (FRY / WALK 1). Bot loss rates (greedy bot, 200 seeds, all twists):
   s1 7%, s2 36%, s3 50%, s4 50%, s5 73%.
3. When reviews resume: run the blind first-timer review on the newest build, save it in
   `docs/reviews/`, add the score to the table above. Under 8.5: write the next 8.5 plan, get
   Duff's OK once, build it in one PR.
4. After Dec 1: Duff's keep/park call. If kept, QUEUE.md NEXT (M2 week of services, M3 content).

## How to build and check (cloud sandbox, Linux)
- Godot 4.7.2-stable Linux binary at `/usr/local/bin/godot`; fresh clone: `godot --headless --path . --import`.
- `git config core.hooksPath .githooks` once per clone (pre-push guard).
- Fast checks: `tools/test.sh` -> must print `TESTS PASS` (parse check + `tests/run_tests.gd`, 46 tests as of build 81).
- Full flow: `tools/autoplay.sh` -> last line `AUTOPLAY PASS` (~8 minutes; run it in the background).
  It rewrites `docs/renders/`; restore them before committing:
  `git checkout -- docs/renders && git clean -fq docs/renders`.
- Both must pass before every push (the guard blocks pushing code the tests didn't pass on).
- PR flow: draft PR -> fresh-context review of `git diff origin/main...HEAD` -> fix -> post a PR
  review whose body starts `FRESH-EYES REVIEW: PASS <full head sha>` (docs/FRESH_EYES.md) -> mark
  ready -> CI green (android, test, gate, fresh-eyes) -> squash-merge. Then wait until `version.json`
  and the gh-pages commit both show the merge sha before calling it live.
- Every gameplay number gets a TUNE slider; every new feature gets an autoplay PASS line and,
  for rules, a unit test.

## Where the code is
- Rules (pure, no nodes, unit-tested): `scripts/kitchen.gd` (tickets, pans, crew, stress, twists
  `EVENTS`, `end_turn`, grading), `scripts/upgrades.gd` (shop items, prices, `apply`).
- Screen: `scripts/game.gd` (drawing, taps, HUD labels, coach hints `_coach_steps`, shop, grade
  sheet, game over, save state). `stress_after()` must mirror `Kitchen.end_turn`'s stress math
  exactly; `test_quit_warning_matches_end_turn` checks it.
- Autoplay checks: `scripts/autoplay.gd` (each `_check(..., "NAME PASS (...)")`).
- Save: `scripts/save_game.gd` (bump VERSION + migrate on format changes).

## How to run a blind review
Use a fresh agent with no repo access in its instructions. It opens the web build in headless
Chromium (Playwright; args `--use-gl=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist`),
phone viewport 390x780 with touch, screenshots to look and taps by coordinates. It plays 3-4
services, shops as it likes, then writes: score /10, what hooked/confused/felt unfair, top 3
changes, how far it got. Never give it the target score or the change list.

## Gotchas
- Godot 4.7 `--headless` for tests; autoplay needs xvfb (the script handles it).
- Commit and push in separate commands (the Claude hook checks a push before the commit exists).
- Never force-push; the pre-push hook blocks rewriting the remote branch.
- Never add the `duff-ok` label (rule-lock); rule-file changes need Duff's tap.
- Nothing posts publicly (ads, socials) without Duff's yes. No AI disclosure in marketing copy.
- Signing uses the shared keystone (secret KEYSTONE_PASS). Never make a new key.
- Shop rows sit in a ScrollContainer at big text sizes; autoplay's `_click_node` scrolls to them.
