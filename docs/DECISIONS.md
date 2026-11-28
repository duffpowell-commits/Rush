# Decisions log (catch-up file for Claude, Grok and any agent)

## 2026-11-28 — Guided service, explicit rush and forecasts (owner landscape playtest)

Duff lost service 1 after serving three tables, with two tickets expiring on the same turn. This candidate is isolated from the unmerged visual polish branches and starts at the local #49 baseline (`4a25b47`); live v0.1.116 is owner-reported, remote main could not be verified.

- **Why — walkouts:** cap simultaneous expiration penalties at the current service limit (including VIP and purchased comps), finish cleanup and stop dealing tickets after the loss. Display is clamped as a second layer. No change to the value of a VIP walk when under the cap.
- **Why — stress:** hide all next-turn forecasts once a service ends; label visible deltas `next`, or omit the delta when space cannot fit the label. Clear transient feedback on loss.
- **Why — onboarding:** normal service 1 has two one-dish tickets at opening and one later, no large tables; 3/5/7/9 default early ticket ramp, later curve unchanged. Pace still adjusts count (the Slammed first service can add follow-up tickets). Checklist follows actual Fire/Plate/Walk to Pass/Run and highlights buttons or destination station; it retires after first served table. Legacy in-progress saves remain unguided; new deals carry an optional flag.
- **Why — walking:** cap long trips at two AP rather than automate RUN, preserving the tactical pass decision and adjacent moves. Existing free-walk perks still discount that cost; no shop changes. This intentionally changes balance and may make distant trips more attractive.
- **Why — rush:** dedicated center button with explicit stress/quit warning; context cannot invoke RUSH even after firing. Keep the three controls in fixed portrait locations so double taps do not spend stress by accident.
- **Why — forecasts:** ticket rows show remaining cook turns; big ticket total sums remaining cooking work, not parallel wall-clock time or walking/serving overhead. NEXT WALK labels the earliest clock without implying it is already expiring.

Regression tests explicitly cover simultaneous expiries, upgraded/VIP limits, legacy save fields, guided milestones and stress forecast clearing. Existing tests updated only where intentional behavior/copy changed. Rendered autoplay checks actual separate RUSH button and checklist, and portrait touch checks at 360×640 and 390×780. Final exact-code run: 61/61 tests, AUTOPLAY PASS, 360×640 and 390×780 touch and four-mode All Orders PASS. Manual portrait opening A, 3/3 served, zero walks, $48 bank; screenshot evidence in offline bundle. Concurrent software-rendered autoplay had unrelated 3D turn/camera timing failures, clean isolated retry passed. Existing Godot teardown warnings remain. GitHub returned 403, no PR or release.


## 2026-11-24 — Eyes copied in from the starter (tools/eyes)
Approved by Duff on Nov 24 ("go ahead and do them both", Rush and Lethemoor; Lethemoor waits for its
other session). Same tool as starter PRs #22/#23: godot-mcp-runtime 4.0.1 (pinned) under xvfb. Rush's
smoke plays NEW GAME -> FIRE -> END TURN. First run found two first-minute problems, logged in
tasks/todo.md. Outside QUEUE NOW (tooling, not the slice).
Synced Nov 24 with starter #23/#24: warnings no longer fail a run; printerr, crashes and a quit
right after the last step do; steps carrying allowErrors still run.

## 2026-11-24 — Rush made from the starter
Duff picked Rush (kitchen tactics) from the Nov 24 games scan and chose a one-week side test next to
Lethemoor. First playable: rules in scripts/kitchen.gd, screen in game.gd, 4 rule tests, autoplay
plays a real service. Open: Duff's playtest decides whether the slice gets real art.

## 2026-11-23 — Studio publisher

Startup shows the approved weathered 3 Eyed Fox Studios logo from the studio Drive folder
during the existing boot. The player can skip the card with the button, Enter, Escape, or
Android Back. Settings → Credits names the publisher.

Newest first. Dates are America/Chicago. Each entry: what changed, why, where the idea came from,
what review found, and what is still open. Add an entry whenever a session changes how agents
work in this repo. AGENTS.md lists this file in its reading order.

## 2026-11-21: Git pre-push hook for every agent; AGENTS.md is the one rulebook (PR #11)
Approved by Duff on Nov 21 ("Build the pre-push hook", "Build the shared rulebook and fix the docs").

**What changed**
- `.githooks/pre-push` runs `.claude/hooks/guard.py --pre-push`. It blocks force pushes (any push
  that rewrites a remote branch), pushes to or deleting main/master, secret or plain key files in
  the pushed commits, and code `tools/test.sh` didn't pass on. Setup per clone:
  `git config core.hooksPath .githooks` (first step in AGENTS.md). `tools/test_push_guard.sh`
  tests it against a local bare remote (14 checks, `PUSH GUARD PASS`).
- AGENTS.md now holds the commands, standing rules, guards and layout. CLAUDE.md starts with
  `@AGENTS.md` and keeps only where things stand plus Claude-only notes. GROK_STANDARDS.md,
  standards/12-testing.md and docs/FRESH_EYES.md point to AGENTS.md and the hook.
- Short "Why" notes were added in every changed file (Duff: "write why in all files for better memory").

**Why**
- Claude Code hooks (`.claude/settings.json`) only fire inside Claude Code. Grok and other agents
  could push to main or force-push without anything stopping them. A Git hook binds every agent.
- Claude Code skips AGENTS.md when a CLAUDE.md exists unless CLAUDE.md imports it with `@AGENTS.md`.
  Rules were split: some only Claude saw, some only other agents saw. Now there's one source.
- `--no-verify` still skips the hook, so CI and the fresh-eyes gate stay the backstop.

**Research behind it** (Grok, Nov 21: X, Reddit, dev blogs on AI coding setups)
- Common advice: rules that keep getting broken become hooks, not prose (r/ClaudeCode,
  "corrected twice = a hook"; already the idea behind guard.py).
- AGENTS.md as the shared file, CLAUDE.md importing it:
  https://codexguild.com/blog/claude-md-agents-md-best-practices and Claude Code memory docs
  https://code.claude.com/docs/en/memory (the `@path` import syntax).
- Keep always-loaded files short (under about 200 lines) and point to topic files instead of copying them.
- Skipped: live Godot-editor connectors for AIs. They need a desktop editor, and Duff is phone-only.
- Ideas ranked but not built yet: a GitHub ruleset that blocks merges until CI + fresh-eyes pass
  (with an exception for the art bots that push to main), skill files for repeated chores, and
  screenshot comparison in CI.

**Review findings** (fresh-eyes, PASS on 6449e33)
- No blockers. Non-blocking notes, not fixed yet:
  - A push that only deletes code files skips the hook's test gate (`--diff-filter=ACMRT`). CI catches it.
  - If `.claude/hooks/guard.py` is missing, the hook warns and lets the push through (on purpose).
  - Pushing a new branch to a bare URL instead of a named remote counts the whole history as new,
    so the test gate may ask for tests on a doc-only branch. Rare, and it errs on the safe side.
  - In Claude Code's mode `--force-with-lease` still gets through. AGENTS.md now says so; the Git hook blocks it.

**Still open (Duff decides)**
- Hunter's Godot version: its BUILD_SPEC says 4.5-stable, while this template and standards/ use 4.6.3.
- Is Hunter the active game? Hunter's docs/PITCH.md says Lethemoor is; its QUEUE.md says Hunter
  coding was greenlit Nov 20. Both logged in hunter's QUEUE.md; nothing changed until Duff says.

## 2026-11-24: Godot 4.7.2 for every game

- Duff: "Lets go 4.7 for all of our games." 4.7.2 is the latest stable; 4.7 adds a stable Godot Android Build Environment (GABE) for exporting from the phone, HDR output and AreaLight3D. CI `GODOT_VERSION`, `config/features` and the engine lines in AGENTS.md / standards moved from 4.6.3 to 4.7.2. Older entries below keep their original version numbers as history.

## 2026-11-27 — Cook sprites and tap commands (approved plan PR #41)
- Tap a visible cook to select, tap an open reachable station to walk (even if occupied), and use
  the large action button to FIRE/PLATE/RUN/PREP/RUSH. Repeated station taps never act or swap cooks.
- A deliberate drag from a cook previews the destination and cost and uses the same movement and
  undo rules. Invalid releases, cancellation, resize, pause and focus loss spend nothing. Native
  touch owns the gesture; emulated mouse events are ignored by the field, not by the rest of the UI.
- Full-body Dev, Mo and Jo sprites are drawn with existing flat-ink art direction; see ART_LOG.
  Hit tests share the visual position, including movement and bob. Kitchen and save code unchanged.
- The previous blind review score is not changed. Fresh-eyes, CI and release verification remain gates.
