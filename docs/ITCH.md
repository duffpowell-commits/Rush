# Rush on itch.io

Page: https://3-eyedfox.itch.io/rush (made by Duff on his phone, kept as a **Draft** until he
publishes it). Money: free with tips, "$0 or donate" (studio rule, Nov 25 2026). Don't enter the
2026 Annual Jam before Rush's Dec 1 check.

## How builds get there
- Every push to main that changes the game (pushes touching only docs/ or *.md skip CI): build.yml zips the web build as `Rush_web.zip` and puts it on the `dev`
  release next to `Rush.apk`.
- If the repo has a `BUTLER_API_KEY` secret, the same run pushes both to itch with butler:
  web zip -> channel `html5`, APK -> channel `android`. No secret = the step skips.
- Target defaults to `3-eyedfox/rush`. If the itch URL ends up different, set the repo variable
  `ITCH_TARGET` (Settings -> Secrets and variables -> Actions -> Variables) to `3-eyedfox/<slug>`.
- butler never touches visibility. The page stays a Draft until Duff taps Public.
- First butler upload of the html5 channel: on the itch edit page, tick "This file will be played in
  the browser" once. Later pushes keep it.

## Page settings (paste these)
- Title: Rush
- Project URL: rush
- Short description: Dinner service, turn by turn. Fire, plate and run with two cooks before the tickets run out.
- Classification: Games. Kind of project: HTML.
- Release status: In development
- Pricing: $0 or donate. Suggested donation: $2.
- Embed: viewport 405 x 720, Mobile friendly ON, Orientation Portrait, Fullscreen button ON,
  "Click to launch in fullscreen" OFF, Automatically start on page load OFF.
- Genre: Strategy
- Tags: cooking, turn-based, tactical, strategy, restaurant, time-management, management, mobile, singleplayer, casual
- AI disclosure: Yes, graphics (title backdrop and art come from Foxboard/FLUX, docs/ART_LOG.md).
  Sound is CC0 recordings (assets/audio/SOURCES.md), not AI.
- Cover: `promo/rush-itch/cover_630x500.png` in project files. Screenshots: `promo/rush-itch/screens/`.
- Visibility: Draft

## Description (paste into the itch editor)
Friday night. The rail fills up faster than you can read it.

Rush is a turn-based kitchen game for your phone. Each turn your two cooks get three moves: fire a
dish, rush a pan, plate it on the pass, run it to the table. Every ticket is on a clock, and three
walked tables ends the night.

- A new twist every service after the first: a bus tour, the grill on the fritz, a VIP, a food critic, a heat wave, a party of 12.
- The line grows: grill and fry, then saute, then a cold station.
- Bank your tips for upgrades that last the night, or hire a temp cook when it gets ugly.
- Grades from A+ to F, scored on tables out, speed and clean pans.
- Too hot? Set the PACE. Rough night? The kitchen eases off.

Built by a line cook. Plays in your browser (tap Run game) or grab the Android APK below.

**Free. Tip if it's good.** No ads, no sign-up.

Watch this.
3 Eyed Fox Studios
