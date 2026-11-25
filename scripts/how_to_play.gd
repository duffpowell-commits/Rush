extends RefCounted
## HOW TO PLAY sheet (title and pause menu): HowToPlay.open(parent).
## Six short steps, each with the art the player will see on the line, then two tips.

const UI = preload("res://scripts/ui.gd")

const STEPS := [
	["dish_burger", "Tickets are the enemy. Each one has a clock. Get its food out before it hits zero."],
	["cook_dev", "Tap a cook, then a station, to walk there. Every move and job costs an action."],
	["station_grill", "At a station, FIRE starts the next dish. When the pan is done, PLATE it."],
	["station_pass", "Plates wait on the pass. Any cook at the PASS can RUN one to its table. Trays in the SHOP carry more."],
	["cook_mo", "END TURN and every clock ticks a minute. Hot work adds stress. Max stress and that cook walks out."],
	["dish_steak", "Walk 3 tables in one service and the night is over. Clear the service to get a grade: tables out, speed and clean pans all count."],
]
const TIPS := "Tap a ticket to make FIRE cook it first.\nRUSH takes a minute off a pan, for stress.\nThe line grows: saute opens in service 2, cold in service 3.\nToo hot or too easy? Settings -> PACE. The kitchen also eases off after a rough night."


static func open(parent: Node) -> VBoxContainer:
	var box := UI.sheet(parent, 500)
	box.add_child(UI.label("HOW TO PLAY", 30, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	for i in STEPS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var pic := TextureRect.new()
		pic.texture = load("res://assets/art/%s.png" % STEPS[i][0])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(72, 72)
		row.add_child(pic)
		var t := UI.label("%d. %s" % [i + 1, STEPS[i][1]], 20)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size = Vector2(300, 0)
		row.add_child(t)
		col.add_child(row)
	col.add_child(UI.label("TIPS", 22, UI.ACCENT))
	col.add_child(UI.label(TIPS, 20, UI.DIM))
	box.add_child(UI.button("GOT IT", func(): UI.close_sheet(box)))
	return box
