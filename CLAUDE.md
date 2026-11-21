# Starter Game (godot-game-starter)

Template for every new Duff game: Godot 4.6.3, GDScript, portrait phone, Android APK. Milestone 0
(foundation) is done here, so a new game starts at Milestone 1. Owner: Duff. This is the handoff.

## Where things stand
- Rulebook for every game and every coding AI: **GROK_STANDARDS.md** -> `standards/*.md` (one topic
  each, <= 60 lines). Change rules here, then copy `GROK_STANDARDS.md` + `standards/` + `.claude/`
  into the game repos.
- What Milestone 0 built (items 1-19, Nov 19-21): `docs/MILESTONE0.md`. Queue: QUEUE.md. Progress: tasks/todo.md.
- Latest build: Releases -> `dev` -> `<repo>.apk`, rebuilt on every push to main.
- Waiting on Duff: tick Settings -> Template repository; make the keystone (docs/SIGNING.md). Until
  then CI signs with a throwaway key and warns.
- Nov 21: live tuning sliders (DEV MENU -> TUNE), push-guard hooks, fresh-eyes review gate.
- Next: start a game from this template (docs/NEW_GAME.md); Milestone 1 = the game's core loop.

## Rules (the full set is in standards/; these are the ones sessions trip on)
- Duff is phone-only (Godot Android editor, GitHub app). GDScript only. No desktop steps.
- UI through `ui.gd` helpers. Sounds a player must notice: `Subs.cue`. Gameplay colours: `UI.key()` + a shape cue.
- Gameplay scenes handle focus-out (pause + save) and the back button, deferred, like `game.gd`.
  Save at checkpoints; bump `Save.VERSION` + migrate when the format changes.
- 3D characters: `Character3D` on the shared skeleton, real clips only (docs/MOVEMENT_3D.md).
- Every gameplay number gets a TUNE slider (`standards/03`). Every new feature gets an autoplay PASS line.
- Renderer is Compatibility everywhere. Visual decisions need real engine renders, saved to files.
- Push after every chunk; merge to main at the end of every milestone; up to three per session.
- After an engine upgrade delete `.godot/imported/` (stale cache = T-pose).

## Guards (enforced, not just written down)
- `.claude/hooks/guard.py` blocks: force push, direct push to main, pushing code the tests didn't pass
  on, writing/generating signing keys, committing secrets. Settings: `.claude/hooks/guard.cfg`.
- Before a push: `tools/test.sh` (parse check + rule tests; records the passing tree), then `tools/autoplay.sh`.
- PRs: the `fresh-eyes` status stays pending until a fresh-context review posts
  `FRESH-EYES REVIEW: PASS` on the head commit (docs/FRESH_EYES.md). Pending is not green: sessions
  check the combined status and don't merge (GitHub itself doesn't block it).
- Signing: one keystone for every game except Lethemoor (docs/SIGNING.md). Never make another key.

## Layout
- `scenes/` boot, intro, title, game (Control + script; UI built in code). `game.gd` = placeholder
  "Orb Catch": replace its PLAY section, keep the rest.
- `scripts/` autoloads: Controls, Settings, Save, Audio, Subs, Feel, Telemetry, Loader, Battery,
  Updater, DebugMenu, Autoplay. Helpers: `ui.gd`, `config.gd`, `bug_report.gd`, `settings_sheet.gd`,
  `tune_panel.gd`, `camera_rig.gd`, `coach.gd`, `character3d.gd` (+ foot_ik, aim_twist, ragdoll).
- `tests/run_tests.gd` rule tests. `tools/` check_scripts.gd, test.sh, autoplay.sh, gen_audio.py.
- `assets/audio/` (list every clip in SOURCES.md), `assets/art/`, `assets/models/`. `grok_art/` never ships.
- `signing/` keystone (encrypted) + `unlock.sh`. `docs/renders/` autoplay screenshots.

## Commands
- Engine version lives in `GODOT_VERSION` (build.yml) + `config/features`.
- Godot in the cloud sandbox: 4.6.3-stable Linux zip from GitHub releases -> `/usr/local/bin/godot`.
  Fresh clone: `godot --headless --path . --import`.
- Tests: `tools/test.sh` -> `TESTS PASS`. Flow + screenshots: `tools/autoplay.sh` -> last line `AUTOPLAY PASS`.
- CI: `gh api repos/<owner>/<repo>/actions/runs?per_page=3` (gh GraphQL is blocked in sessions).
