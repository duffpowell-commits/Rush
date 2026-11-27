# Final diner menu consistency

Baseline: build 112 / `55bb072`. Godot 4.7.2 Compatibility renderer. These are captures of
actual UI nodes and game scenes, not mockups. The render sweep uses isolated local data and
sets up a service state to visit each sheet; full autoplay separately plays the game.

## Before and after (390 × 780, normal)

| Screen | Build 112 | Candidate |
|---|---|---|
| Title | [Before](before/normal_title.png) | [After](after/normal_title.png) |
| Title / Continue | [Before](before/normal_title_continue.png) | [After](after/normal_title_continue.png) |
| Crew Expanded | [Before](before/normal_crew_expanded.png) | [After](after/normal_crew_expanded.png) |
| Grade | [Before](before/normal_grade.png) | [After](after/normal_grade.png) |
| Tonight | [Before](before/normal_tonight.png) | [After](after/normal_tonight.png) |
| Pause | [Before](before/normal_pause.png) | [After](after/normal_pause.png) |
| Game Over | [Before](before/normal_game_over.png) | [After](after/normal_game_over.png) |
| Settings | [Before](before/normal_settings.png) | [After](after/normal_settings.png) |
| Controls | [Before](before/normal_controls.png) | [After](after/normal_controls.png) |
| Credits | [Before](before/normal_credits.png) | [After](after/normal_credits.png) |
| How to Play | [Before](before/normal_how_to_play.png) | [After](after/normal_how_to_play.png) |
| Report a Bug | [Before](before/normal_bug_report.png) | [After](after/normal_bug_report.png) |

## Render matrix (native Godot viewport, 14 captures per mode)

| Size | Normal | Huge | High contrast | Huge + high contrast |
|---|---|---|---|---|
| 360×640 | [Normal](360x640_normal.jpg) | [Huge](360x640_huge.jpg) | [HC](360x640_contrast.jpg) | [HC+Huge](360x640_contrast_huge.jpg) |
| 390×780 | [Normal](390x780_normal.jpg) | [Huge](390x780_huge.jpg) | [HC](390x780_contrast.jpg) | [HC+Huge](390x780_contrast_huge.jpg) |
| 907×510 | [Normal](907x510_normal.jpg) | [Huge](907x510_huge.jpg) | [HC](907x510_contrast.jpg) | [HC+Huge](907x510_contrast_huge.jpg) |
| 1216×684 | [Normal](1216x684_normal.jpg) | [Huge](1216x684_huge.jpg) | [HC](1216x684_contrast.jpg) | [HC+Huge](1216x684_contrast_huge.jpg) |

The pre-change sweep fails Settings at Huge and Huge+HC ([before](before/huge_settings.png) / [after](after/huge_settings.png)): the DONE button and scroll area
extend beyond the portrait viewport. Wrapping long option text resolves it without changing
any settings semantics. The candidate bounds check passes all four sizes and four modes.

Run `tests/menu_render.gd` under a graphical display with a temporary `XDG_DATA_HOME`,
`--resolution WIDTHxHEIGHT`, and `-- --shots=/absolute/output/directory` to repeat the captures.

## Actual desktop browser iframe

Godot's Web release export, served on localhost inside a full-size HTML iframe in Chromium
(WebGL 2 / SwiftShader). Both sizes reached the title through the unchanged studio splash and
intro, then opened Settings with browser pointer input. These are browser screenshots, not
native-window substitutes. No external bug-report link was opened and no release was submitted.

| Size | Title | Settings |
|---|---|---|
| 907×510 | [Title](web/rush-iframe-907x510-title.png) | [Settings](web/rush-iframe-907x510-settings.png) |
| 1216×684 | [Title](web/rush-iframe-1216x684-title.png) | [Settings](web/rush-iframe-1216x684-settings.png) |
