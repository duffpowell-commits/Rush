# Decisions log (catch-up file for Claude, Grok and any agent)

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
