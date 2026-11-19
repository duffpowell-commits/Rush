# Lessons

- `godot --check-only --script` doesn't load autoloads, so any script using `Settings.` etc. fails
  it. Use `tools/check_scripts.gd` (loads every script inside a running tree) instead.
- Adding UI from `_notification` (focus out, back button) fails with "parent busy": call it deferred.
- An imported .wav's loop is set in its .import (`edit/loop_mode=2`), not at runtime (it's compressed).
- Rebuilding a screen's UI after a settings change: move open sheets back on top (`move_child(sheet, -1)`).
- DuffQuest went weeks without a GAME OVER because end screens weren't day-one plumbing. They are now.
