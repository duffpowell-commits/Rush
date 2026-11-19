# Style guide (template defaults; each game replaces these)

## Colours
- Background `#12161f`, panels `#1d2433`, ink `#e9e4d8`, dim `#9aa3b5`, accent `#e8a33d` (scripts/ui.gd).
- Gameplay meaning always goes through `UI.key("good"|"bad"|"info"|"warn")`; colorblind mode swaps
  to Okabe-Ito. Never let colour be the only cue: add a shape, icon or position difference.

## Type and touch
- Body 22, buttons 24, headings 28-44 (base units at 540x960), all scaled by the Text Size setting.
- Buttons at least 72 tall (`UI.MIN_TOUCH`), 18 apart (`UI.GAP`). Main action goes on the thumb side;
  left-handed mirrors it.

## Screens
- Menus are sheets (`UI.sheet`): dimmed game behind, one column of buttons, primary first and tallest.
- Labels say what happens: RESUME, QUIT TO TITLE, TRY AGAIN. All caps on buttons.

## Art
- Placeholder art is drawn in code. Real art comes through Foxboard (docs/ART.md).
