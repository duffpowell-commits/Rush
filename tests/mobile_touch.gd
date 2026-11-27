extends SceneTree
## Live viewport touch smoke; run with --resolution 360x640 or 390x780 on a display.
## Optional -- --shots=/absolute/directory to save engine evidence.
var game: Control
var failures := 0


func _initialize() -> void:
	await process_frame
	root.get_node("Settings").set_value("low_graphics", false)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(3)
	game.k.start(1, 7)
	game._cook_draw.clear()
	game._after_move()
	await frames(3)
	var mo: Vector2 = game.cook_visual_pos(1)
	var grill: Vector2 = game.station_rect(0).get_center()
	var before: int = game.k.crew[1].ap
	await touch(mo, mo)
	check(game.sel == 1 and game.k.crew[1].ap == before, "short touch selects only")
	await touch(grill, grill)
	check(game.sel == 1 and game.k.crew[1].at == 0 and game.k.crew[1].ap == before - 1, "occupied destination spends one AP")
	await touch(grill, grill)
	check(game.k.crew[1].ap == before - 1 and game.k.pans[0].is_empty(), "same station does nothing")
	await frames(15)
	await shot("two_cooks")
	game.k.hires = 1
	game.k.start(3, 7)
	game.level = 3
	game.sel = 0
	game._cook_draw.clear()
	game._after_move()
	await frames(3)
	var jo: Vector2 = game.cook_visual_pos(2)
	var cold: Vector2 = game.station_rect(3).get_center()
	var ap: int = game.k.crew[2].ap
	await touch(jo, cold)
	check(game.sel == 2 and game.k.crew[2].at == 3 and game.k.crew[2].ap == ap - 1, "drag commits once with emulated mouse enabled")
	game.k.crew[0].at = 0
	game.k.crew[1].at = 0
	game.k.crew[2].at = 0
	game._cook_draw.clear()
	root.get_node("Settings").set_value("text_size", 3)
	game._after_move()
	await frames(4)
	for c in game.k.crew.size():
		var p: Vector2 = game.cook_visual_pos(c)
		check(p.x >= game.COOK_R and p.x <= game.field.size.x - game.COOK_R, "edge cook stays on screen")
		await touch(p, p)
		check(game.sel == c, "edge sprite selects exact cook")
	await shot("three_cooks_huge")
	print("MOBILE TOUCH PASS %s" % str(root.size) if failures == 0 else "MOBILE TOUCH FAIL %d" % failures)
	quit(0 if failures == 0 else 1)


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func touch(from: Vector2, to: Vector2) -> void:
	var tr: Transform2D = root.get_final_transform() * game.field.get_global_transform()
	var e := InputEventScreenTouch.new()
	e.pressed = true
	e.position = tr * from
	Input.parse_input_event(e)
	await frames(2)
	if from != to:
		var drag := InputEventScreenDrag.new()
		drag.position = tr * to
		drag.relative = tr.basis_xform(to - from)
		Input.parse_input_event(drag)
		await frames(2)
	var up := InputEventScreenTouch.new()
	up.position = tr * to
	Input.parse_input_event(up)
	await frames(2)


func shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			var path := a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(path)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path.path_join(name + ".png"))
