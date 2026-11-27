extends SceneTree
## Real render sweep. Use isolated XDG data and -- --shots=/absolute/path.
const SettingsSheet = preload("res://scripts/settings_sheet.gd")
const HowToPlay = preload("res://scripts/how_to_play.gd")
const BugReport = preload("res://scripts/bug_report.gd")
var failures := 0
var out := ""
var mode := "normal"

func _initialize() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
	var settings := root.get_node("Settings")
	for variant in ["normal", "huge", "contrast", "contrast_huge"]:
		mode = variant
		settings.set_value("text_size", 3 if mode.ends_with("huge") else 1)
		settings.set_value("high_contrast", mode.begins_with("contrast"))
		root.get_node("Save").clear()
		root.get_node("Subs").clear()
		var title = load("res://scenes/title.tscn").instantiate()
		root.add_child(title)
		current_scene = title
		await capture("title", title)
		root.get_node("Save").write({"level": 2})
		title._build()
		await capture("title_continue", title)
		root.get_node("Save").clear()
		await sheet("settings", SettingsSheet.open(title))
		await sheet("controls", SettingsSheet.open_controls(title))
		SettingsSheet._open_credits(title)
		await capture("credits", get_nodes_in_group("sheet").back())
		get_nodes_in_group("sheet").back().queue_free()
		await frames(3)
		await sheet("how_to_play", HowToPlay.open(title))
		await sheet("bug_report", BugReport.open(title))
		title.queue_free()
		await frames(3)
		var game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await frames(5)
		game._crew_expanded()
		await capture("crew_expanded", get_nodes_in_group("sheet").back())
		get_nodes_in_group("sheet").back().queue_free()
		await frames(3)
		game.pause()
		await capture("pause", game.sheet_box.get_meta("sheet"))
		game.resume()
		await frames(3)
		game.k.start(2, 7)
		game.level = 2
		game.tonight()
		await sheet("tonight", game.twist_box)
		game.twist_box = null
		# A consistent end-of-service fixture, through the real grade builder and buttons.
		game.k.served = 7
		game.k.total = 7
		game.k.tips = 35
		game.k.speed = 7.0
		game.k.walked = 0
		game.k.done = true
		game._service_done()
		await sheet("grade", game.sheet_box)
		game.between = false
		game.game_over()
		await create_timer(1.2).timeout
		await capture("game_over", game.sheet_box.get_meta("sheet"))
		game.queue_free()
		await frames(3)
	print("MENU RENDER %s %s" % ["PASS" if failures == 0 else "FAIL", root.size])
	quit(0 if failures == 0 else 1)

func sheet(label: String, box: VBoxContainer) -> void:
	var node: Control = box.get_meta("sheet")
	await capture(label, node)
	node.queue_free()
	await frames(3)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func capture(label: String, node: Control) -> void:
	await frames(10)
	var view := node.get_global_rect()
	for sc in node.find_children("*", "ScrollContainer", true, false):
		if not view.encloses(sc.get_global_rect()):
			print("FAIL ", mode, " ", label, " scroll outside viewport")
			failures += 1
	for b in node.find_children("*", "Button", true, false):
		if b.get_parent() is VBoxContainer and b.get_parent().get_parent() is ScrollContainer:
			continue
		if not view.encloses(b.get_global_rect()):
			print("FAIL ", mode, " ", label, " ", b.text, " outside ", view, " ", b.get_global_rect())
			failures += 1
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(mode + "_" + label + ".png"))
		for scroll in node.find_children("*", "ScrollContainer", true, false):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(mode + "_" + label + "_bottom.png"))
