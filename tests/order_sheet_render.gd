extends SceneTree
## Rendered phone smoke for All Orders. Optional -- --shots=/absolute/directory.
var game: Control
var failures := 0
var settings: Node

func _initialize() -> void:
	await process_frame
	settings = root.get_node("Settings")
	settings.set_value("low_graphics", false)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	game.k.start(4, 7)
	game.level = 4
	game.k.tickets.clear()
	for i in 8:
		game.k.tickets.append({"id": 970 + i, "table": 40 + i, "items": [{"dish": "STEAK", "state": "wait"}, {"dish": "FRIES", "state": "carried"}, {"dish": "SALAD", "state": "served"}], "time": i + 1, "big": i == 0})
	game.k.incoming = [{"arrive": game.k.turn + 2, "ticket": {"items": [{"dish": "STEAK"}], "big": false}}]
	for mode in ["normal", "contrast", "huge", "contrast_huge"]:
		settings.set_value("high_contrast", mode.begins_with("contrast"))
		settings.set_value("text_size", 3 if mode.ends_with("huge") else 1)
		game.rail_off = 0
		game._after_move()
		await frames(4)
		var before: Dictionary = game.k.to_dict()
		await touch_tap(game.field.get_global_transform() * game._more_rect.get_center())
		await frames(4)
		var sheets := get_nodes_in_group("sheet")
		check(sheets.size() == 1, mode + " opens one sheet from rail")
		if sheets.is_empty():
			continue
		var sheet: Control = sheets.back()
		var scroll: ScrollContainer = sheet.find_children("*", "ScrollContainer", true, false).front()
		var orders := sheet.find_children("Order_*", "Button", true, false)
		var done: Button = sheet.find_children("*", "Button", true, false).back()
		var urgent: Button = orders.front()
		var last: Button = orders.back()
		var view := sheet.get_global_rect()
		check(orders.size() == 8 and urgent.text.contains("1 MIN  URGENT") and urgent.text.contains("BIG"), mode + " urgent text and sorted orders")
		check(view.encloses(done.get_global_rect()) and view.encloses(scroll.get_global_rect()), mode + " DONE and scroll inside viewport")
		check(urgent.get_global_rect().size.y >= urgent.get_minimum_size().y, mode + " urgent row fits text")
		for child in game.get_children():
			if child.name.begins_with("Coach_"):
				check(child.get_index() < sheet.get_index(), mode + " modal above gameplay hints")
		check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, mode + " scrollable")
		await shot(mode + "_top")
		var sr := scroll.get_global_rect()
		# The X11 test display has no native touchscreen; a real GUI wheel event
		# exercises the same ScrollContainer. The rail opening above uses touch.
		for i in 20:
			if scroll.scroll_vertical >= scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page - 2:
				break
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_WHEEL_DOWN
			event.pressed = true
			event.position = root.get_final_transform() * sr.get_center()
			event.global_position = event.position
			Input.parse_input_event(event)
			await frames(1)
			event = event.duplicate()
			event.pressed = false
			Input.parse_input_event(event)
			await frames(2)
		await frames(6)
		check(scroll.scroll_vertical > 0 and sr.encloses(last.get_global_rect()), mode + " GUI scroll reaches final ticket")
		await shot(mode + "_bottom")
		await touch_tap(last.get_global_rect().get_center())
		check(get_nodes_in_group("sheet").is_empty() and game.pick_tid == 977 and game.rail_off == 4, mode + " touch selects hidden ticket")
		check(game.k.to_dict() == before, mode + " selection spends no turn or AP")
		game.open_rail()
		await frames(4)
		sheet = get_nodes_in_group("sheet").back()
		done = sheet.find_children("*", "Button", true, false).back()
		await touch_tap(done.get_global_rect().get_center())
		check(get_nodes_in_group("sheet").is_empty() and game.k.to_dict() == before, mode + " touch DONE closes without spending")
	# Pause must be able to stack above the open order sheet (focus-out path).
	game.open_rail()
	await frames(4)
	var all_orders: Control = get_nodes_in_group("sheet").back()
	game.pause()
	await frames(4)
	var pause_sheet: Control = game.sheet_box.get_meta("sheet")
	check(pause_sheet.get_index() > all_orders.get_index() and pause_sheet.z_index >= all_orders.z_index, "pause stacks above All Orders")
	game.resume()
	await frames(4)
	all_orders.queue_free()
	await frames(2)
	print("ORDER SHEET RENDER PASS %s" % str(root.size) if failures == 0 else "ORDER SHEET RENDER FAIL %d" % failures)
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func touch_tap(p: Vector2) -> void:
	var w := root.get_final_transform() * p
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.pressed = down
		e.position = w
		Input.parse_input_event(e)
		await frames(3)

func shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			var path := a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(path)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path.path_join(name + ".png"))
