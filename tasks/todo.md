# Todo

## M1: vertical slice (Rush)
- [x] docs/PITCH.md filled, game renamed to Rush in project.godot.
- [x] PLAY section of scripts/game.gd replaced with the service loop (scripts/kitchen.gd).
- [x] scripts/autoplay.gd plays the real loop (TAP PASS, PLAY PASS, GAMEOVER by idling).
- [ ] Duff playtest on the APK.
- [ ] Real art + sound for one service.
- [ ] Service events: 12-top push, 86, refire call-out.
- [x] End-of-service grade screen (Nov 25).
- [x] Found by Eyes (Nov 24): the template intro line. Replaced with Rush's own three cards.
- [x] Found by Eyes (Nov 24): nothing told a new player to tap END TURN. Five coach hints now
      teach FIRE, END TURN, PLATE, RUN and switching cooks, one at a time.

## From the Nov 25 audit (two fresh-eyes reviewers)
- [x] Service 2 was a wall: 81% game over for the greedy bot over 200 seeds, 99% in service 3.
      Curve is now 6 tickets +1 a service; `test_kitchen_service_curve` keeps service 2 at or under 55%.
- [x] Resuming mid-service rerolled the tickets and refilled lives. The save now carries the
      service in progress (Save.VERSION 2).
- [x] A plate from a walked table jammed the cook's hands for the rest of the service.
- [x] GAME OVER showed a stale board and never said why.
- [x] The APK shipped the template's 3D test scene and its imported models (~2.2 MB).
- [x] Scene changes went through change_scene_to_file instead of Loader.go (intro, quit, try again).
- [x] Save could be lost if the app died between the delete and the rename in Save.write.
- [ ] Settings still offers INVERT LOOK, LOOK SENSITIVITY and a controls legend for a tap-only game.
- [ ] The Credits sheet is one line.
- [ ] Autoplay is still mostly the template's 3D checks; Rush's own PASS lines are the minority.
