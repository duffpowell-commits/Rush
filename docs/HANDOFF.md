# HANDOFF: pick up Rush from here (any coding AI)

Plain log for whoever builds next: Claude, Grok, Codex or anyone else. Also read docs/DECISIONS.md
(dated decisions) and tasks/todo.md (progress) as AGENTS.md says. Update it at the end of
every chunk of work, not only at the end of a session. Rules for every agent: AGENTS.md (read it
first). Dated history of every change: CLAUDE.md "Where things stand". This file is the short
version: where we are, what's next, how to check it.

Last updated: 2026-11-26 13:10 UTC (Claude).

## Where it is right now
- main = `d3b2210` (PR #28). Live builds:
  - Web: https://duffpowell-commits.github.io/Rush/ (gh-pages, pushed by CI on every main push;
    the gh-pages commit message reads "web build <sha7>").
  - APK: Releases -> `dev` -> `Rush.apk`; `version.json` on the same release shows `{"code", "sha"}`.
    Build 81 = d3b2210.
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
| 81 | not run yet | - | - | - |
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

## Next, step by step
1. Run the blind first-timer review on build 81 (it was cut off on Nov 26 by a usage limit).
   Save it as `docs/reviews/firsttimer_rush_build81.md` and add the score to the table above.
2. If it is under 8.5: write 8.5 plan #3 from that review, put it to Duff as one tappable choice,
   build it in one PR after his OK, then one more blind review.
3. Known small leftovers (not yet asked for): the grade sheet's "Next: N tickets" doesn't refresh
   after buying in the shop; the PARTY table lands at the opening when a service has only 2-3
   tickets; the bot loss rates in CLAUDE.md predate the two new twists (re-measure with a
   throwaway script that loops `Kitchen.start` + the game's bot, delete it after).
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
