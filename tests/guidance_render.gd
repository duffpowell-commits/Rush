extends SceneTree
## Actual portrait captures: guidance is explicit, scalable and disappears when the service ends.
var failures := 0
func _initialize() -> void:
	await process_frame
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.k.start(1)
	game.k.tickets.pop_front()
	game._after_move()
	var settings := root.get_node("Settings")
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
	var normal_fs := 0
	for mode in ["normal", "contrast", "huge", "contrast_huge"]:
		settings.set_value("high_contrast", mode.begins_with("contrast"))
		settings.set_value("text_size", 3 if mode.ends_with("huge") else 1)
		await process_frame
		game._after_move()
		var cue: String = game.guide_cue()
		var font := ThemeDB.fallback_font
		var fs: int = game.guide_font_size(font, game.field.size.x - 32)
		check(cue.contains("1/4 FIRE") and cue.contains("TAP FRY"), mode + " explicit station cue")
		if mode == "normal":
			normal_fs = fs
		if mode.ends_with("huge"):
			check(fs > normal_fs, mode + " cue grows with text setting")
		check(fs >= 18 and font.get_string_size(cue, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= game.field.size.x - 32, mode + " scalable cue fits")
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(mode + ".png"))
	game.over = true
	game._after_move()
	check(game.guide_cue().is_empty() and game.act_btn.disabled and game.rush_btn.disabled and game.end_btn.disabled and game.act_btn.text == "SERVICE ENDED", "ended controls neutral")
	print("GUIDANCE RENDER PASS" if failures == 0 else "GUIDANCE RENDER FAIL")
	quit(0 if failures == 0 else 1)
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	failures += 0 if ok else 1
