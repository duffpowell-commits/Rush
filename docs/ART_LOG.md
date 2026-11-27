# Art log

Every piece of real art in Rush: the Forge job, its seed, what was done to it, and Duff's verdict.
Forge jobs live in the public Foxboard repo (`forge/jobs/<id>.json`, prompts included).

## Style A "flat ink" (original art, Nov 25, 2026; style test: `rush-style-{a,b,c}-20261125`)

Historical provenance: where an asset is listed as replaced below, these jobs refer to its
pre-V4 version, not the current file.
Style line used in every prompt: "Bold flat vector illustration with thick dark ink outlines, chunky
simple shapes and big readable silhouettes, like a polished mobile strategy game. Warm palette of
brushed steel greys, hot orange flame, tomato red and mustard yellow, lit by even soft top light
with crisp edges." Props/icons keyed on magenta (#FF00FF).

| File | Forge job / take | Seed | Cleanup | Verdict |
| --- | --- | --- | --- | --- |
| `assets/art/bg_line.jpg` | rush-bg-kitchen-20261125 / 2 | 5150 | none; drawn under a 55% dark wash, text on dark plates. Replaced the plain tile wall (rush-bg-a, Duff: "more kitchen like") | waiting on Duff |
| `assets/art/title_key.jpg` | rush-title-20261125 / 0 | 7310 | none; title backdrop, empty smoky top for the drawn RUSH logo (code, not AI text). Take 2 had a mark in the corner; take 1 failed | waiting on Duff |
| `assets/art/station_grill.png` | rush-st-grill-20261125 / 0 | 24812 | `art_loop.py cut --height 256` | waiting on Duff |
| `assets/art/station_fryer.png` | rush-st-fryer-20261125 / 0 | 24812 | cut; fake brand text painted out; key shadow removed | waiting on Duff |
| `assets/art/station_saute.png` | rush-st-saute-20261125 / 0 | 24812 | cut | waiting on Duff |
| `assets/art/station_pass.png` | rush-st-pass-20261125 / 0 | 24812 | cut; key-tinted strip under the shelf recoloured steel | waiting on Duff |
| `assets/art/cook_dev.png` | rush-cook-dev-20261125 / 0 | 31337 | key to navy, round crop 144 px | waiting on Duff |
| `assets/art/cook_mo.png` | rush-cook-mo-20261125 / 0 | 31337 | key to navy, round crop 144 px | waiting on Duff |
| `assets/art/dish_*.png` (all but fries) | rush-dish-<dish>-20261125 / 0 | 31337 | cut --height 128; floor shadow removed | waiting on Duff |
| `assets/art/dish_fries.png` | rush-dish-fries2-20261125 / 1 | 4242 | first job came out broken, rerolled; cut --height 128; floor shadow removed | waiting on Duff |
| `assets/art/station_cold.png` | rush-st-cold-20261125 / 1 | 24813 | cut --height 256; magenta seen through the glass recoloured pale glass. Opens in service 3 | waiting on Duff |
| `assets/art/dish_salad.png` | rush-dish-salad-20261125 / 0 | 31338 | cut --height 128 | waiting on Duff |
| `assets/art/dish_cake.png` | rush-dish-cake-20261125 / 0 | 31339 | cut --height 128; key shadow under the plate removed | waiting on Duff |

## Studio fox cameo (Nov 26, 2026)
| File | Source | Cleanup | Verdict |
|---|---|---|---|
| `assets/art/fox_cameo.png` | 3 Eyed Fox Studios logo (Duff's upload, the app-icon version) | head cropped, purple background keyed out, 384 px | Duff: "Real logo head pops up" (after Forge jobs rush-fox-cameo-20261126, -cameo2, -cameo3, -cameo4 missed the face) |

## Painted V4 kitchen and title (PR #47 / build 112)

The supplied V4 handoff replaced `bg_line.jpg`, `title_key.jpg`, all eight `dish_*.png` files,
all five `station_*.png` files and the three crew atlases. Source: the V4 handoff ZIP applied in
PR #47; its Forge IDs/seeds were not recorded in the repository. The earlier Style A entries
remain historical provenance. The cook face portraits and studio fox cameo were not replaced.
The painted artwork and its imports are unchanged in the final diner menu consistency pass.

## Crew sprite sheets (PR #41 prototype; V4 replacement in PR #47)

The original flat-ink prototype used `tools/gen_crew_sprites.py`, with Dev/Mo portrait crops and
an original Jo silhouette. The shipped `assets/art/crew/{dev,mo,jo}.png` are the painted V4
handoff atlases committed in PR #47 (build 112 / `55bb072`), not output of that legacy generator.
The repository does not record a V4 Forge job ID or seed; do not infer one from the old art.
Transparent PNG atlases are 512 × 880: four columns of 128 × 176 cells; rows idle, walk, work,
serve, rest. Walk uses four frames; other rows use their first two. Import is lossless, normal
map off. Low graphics holds still frames. The legacy prototype generator now follows the same
atlas geometry and requires a scratch output directory outside shipped art. It is not a way to
recreate the approved painted artwork. Never overwrite the V4 sprites with it.

## Diner menus (final consistency pass)

Existing cream ticket, red enamel and warm charcoal styles extended to player-facing menus,
including secondary actions, scroll tracks and the bug report note field. No new raster assets.
