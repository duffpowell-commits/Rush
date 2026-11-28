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
	var normal_rush := 0
	var normal_sizes: Array = []
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
	# A four-dish ticket occupies the entire rail; test the real font measurements used to draw it.
	game.k.start(3)
	game.level = 3
	game.sel = 0
	game.k.crew[0].at = 0
	game.k.tickets = [{"id": 909, "table": 30, "time": 2, "big": true, "items": [{"dish": "BURGER", "state": "cooking"}, {"dish": "STEAK", "state": "wait"}, {"dish": "SCAMPI", "state": "wait"}, {"dish": "SALAD", "state": "wait"}]}]
	game.k.pans[0] = {"tid": 909, "dish": "BURGER", "left": 2, "sat": 0, "rushed": false, "by": 0}
	game.pick_tid = 909
	for mode in ["normal", "contrast", "huge", "contrast_huge"]:
		settings.set_value("high_contrast", mode.begins_with("contrast"))
		settings.set_value("text_size", 3 if mode.ends_with("huge") else 1)
		await process_frame
		game._after_move()
		await process_frame
		check(not game.rush_btn.disabled, mode + " active RUSH")
		var rush_fs: int = game.rush_btn.get_theme_font_size("font_size")
		var rush_rect: Rect2 = game.rush_btn.get_global_rect()
		var rush_room: Vector2 = rush_rect.size - game.rush_btn.get_theme_stylebox("normal").get_minimum_size() - Vector2(4, 4)
		check(game.button_text_fits(game.rush_btn.get_theme_font("font"), game.rush_btn.text, rush_room, rush_fs), mode + " RUSH fits actual button")
		check(game.field.get_global_rect().encloses(rush_rect) and not rush_rect.intersects(game.act_btn.get_global_rect()) and not rush_rect.intersects(game.end_btn.get_global_rect()), mode + " RUSH does not overlap neighboring controls")
		if mode == "normal":
			normal_rush = rush_fs
		if mode.ends_with("huge"):
			check(rush_fs > normal_rush, mode + " RUSH text grows")
		check(game.has_method("ticket_accessibility_layout"), mode + " measured rail layout exists")
		if game.has_method("ticket_accessibility_layout"):
			var layout: Array = game.ticket_accessibility_layout(game.ticket_rect(0), game.k.tickets[0])
			var sizes: Array = []
			var overlap := false
			for i in layout.size():
				for j in range(i + 1, layout.size()):
					overlap = overlap or layout[i].box.intersects(layout[j].box)
			check(not overlap, mode + " rail text regions do not overlap")
			for line in layout:
				var font := ThemeDB.fallback_font
				check(font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.size).x <= line.box.size.x and font.get_height(line.size) <= line.box.size.y, mode + " " + line.text + " fits")
				if line.kind == "dish":
					check(game.dish_at(0, line.box.get_center()) == line.item, mode + " resized dish hit row")
				if line.kind in ["dish", "next", "total"]:
					sizes.append(line.size)
			if mode == "normal":
				normal_sizes = sizes
			if mode.ends_with("huge"):
				for i in sizes.size():
					check(sizes[i] > normal_sizes[i], mode + " timing/label scales")
		if not out.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("rail_" + mode + ".png"))
	game.over = true
	game._after_move()
	check(game.guide_cue().is_empty() and game.act_btn.disabled and game.rush_btn.disabled and game.end_btn.disabled and game.act_btn.text == "SERVICE ENDED", "ended controls neutral")
	print("GUIDANCE RENDER PASS" if failures == 0 else "GUIDANCE RENDER FAIL")
	quit(0 if failures == 0 else 1)
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	failures += 0 if ok else 1
