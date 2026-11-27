extends SceneTree
## Inspect the actual All Orders sheet without spending a turn.
const MenuArt = preload("res://scripts/menu_art.gd")
const UI = preload("res://scripts/ui.gd")
var failures := 0

func _initialize() -> void:
	await process_frame
	var game: Control = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.k.start(1, 7)
	for high in [false, true]:
		root.get_node("Settings").set_value("high_contrast", high)
		var before: Dictionary = game.k.to_dict()
		game.open_rail()
		await process_frame
		var sheet: Control = get_nodes_in_group("sheet").back()
		var order: Button = sheet.find_children("Order_*", "Button", true, false).front()
		var buttons := sheet.find_children("*", "Button", true, false)
		var done: Button = buttons.back()
		var ticket := order.get_theme_stylebox("normal") as StyleBoxFlat
		var finish := done.get_theme_stylebox("normal") as StyleBoxFlat
		check(ticket.bg_color == (Color.BLACK if high else MenuArt.PAPER), "order ticket paper and contrast %s" % high)
		check(finish.bg_color == (Color.BLACK if high else Color("792e2a")), "done enamel and contrast %s" % high)
		check(order.text.contains("MIN") and done.text == "DONE" and game.k.to_dict() == before, "live order copy and unchanged service")
		sheet.queue_free()
		await process_frame
	print("ORDER SHEET PASS" if failures == 0 else "ORDER SHEET FAIL")
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
