# Rush: December 10 showcase

Approved by Duff on Nov 26, 2026 (Omaha). Target: Omaha Game Developers Meetup, Dec 10 at 7 PM Central. The event is a chance for honest feedback, not a release deadline.

## Baseline and scope
Start with the current live build, 99 / 6e641a5 at planning time; verify the exact version before testing. Build 89 scored 7 in an internal IGN-style review; build 99 has no fresh score. Read docs/HANDOFF.md and QUEUE.md. Preserve the Dec 1 keep/park decision and M1 scope. No blind AI review while paused, public release or new systems just for this showcase.

The game already has coaching, warnings, undo, stress previews, perks, ticket curve changes, sound and a grade sheet. Refine these rather than implementing duplicates.

## Three outcomes
1. **Opening minute:** a new phone player serves the first dish through FIRE, END TURN, PLATE, RUN without being told which buttons to tap. Show only the next relevant hint, keep ticket and action labels visible, and provide visible/audible confirmation. If players hesitate, fix the precise confusing interaction first.
2. **Signature dinner rush:** one service feels like real kitchen decision-making, not busywork. Let the player see incoming tickets, choose which cook and station to prioritize, anticipate stress and recover a mistake. Use existing mechanics and escalating tickets; don't introduce another mandatory system. Test on a small/tall touch viewport with warnings and overlays visible.
3. **One more shift:** existing scorecard communicates why the grade was earned and one actionable improvement, recognizes a clutch save or clean service where applicable, and provides an obvious next-service/retry choice. Keep actual payouts and progression consistent.

## Evidence before coding
- Duff plays the current APK on his phone. Record exact build, time to first served dish, moments of hesitation, missed/tiny taps and whether he wants another service.
- Ask five willing testers to play without coaching. Use the first 60 seconds, whole service, then optional next service. Record observations and anonymous fun score. At least two of five must voluntarily start a second service; median fun at least 6/10 is a viability signal, not an 8.5 release score. Honor the existing kill criteria and Duff's Dec 1 decision.
- Prioritize the top three observed friction points; no fabricated results. Write one consolidated 8.5 improvement PR with the already-approved showcase direction; substantive new mechanics need agreement. Follow AGENTS.md for test/autoplay, actual phone/browser renders, fresh-eyes review and green CI.

## Showcase packet (if kept)
- Current verified web link and APK version; a short capture of the first-minute loop and one difficult-but-fair service.
- 30-second intro: a real dinner service played like a tactics game, built by a line cook. No claims of actual IGN rating.
- Feedback prompts: What was your first confusing moment? Which decision felt satisfying? Would you play another shift? Why?
- Save feedback anonymously and translate the biggest friction points into a single prioritized next pass.

Meeting: https://www.meetup.com/ngda-omaha/events/317521337/
