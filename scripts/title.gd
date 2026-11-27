extends Control
## Title: CONTINUE (when a run is saved), NEW GAME, SETTINGS, REPORT A BUG, version number.
## Tap the version number 5 times for the dev menu (dev builds only).

const UI = preload("res://scripts/ui.gd")
const Config = preload("res://scripts/config.gd")
const SettingsSheet = preload("res://scripts/settings_sheet.gd")
const BugReport = preload("res://scripts/bug_report.gd")
const HowToPlay = preload("res://scripts/how_to_play.gd")
const Art = preload("res://scripts/menu_art.gd")
const KEY_ART := "res://assets/art/title_key.jpg"

var _ver_taps := 0


func _ready() -> void:
	get_node("/root/Settings").changed.connect(_on_setting)
	get_node("/root/Audio").music("music_loop")
	_build()


func _on_setting(key: String) -> void:
	if key in ["text_size", "high_contrast"]:
		_build()


func _build() -> void:
	for c in get_children():
		if not c.is_in_group("sheet"):
			c.queue_free()
	theme = UI.theme()
	Art.diner_theme(theme)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	var tex: Texture2D = load(KEY_ART) if ResourceLoader.exists(KEY_ART) else load("res://assets/art/bg_line.jpg")
	Art.backdrop(self, tex)
	var logo := Art.Logo.new()
	logo.tagline = "DINNER SERVICE, TURN BY TURN"
	logo.anchor_right = 1.0
	logo.offset_top = 70
	logo.offset_bottom = 330
	add_child(logo)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = -200
	col.offset_right = 200
	col.offset_bottom = -70
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.add_theme_constant_override("separation", UI.GAP)
	add_child(col)
	var st: Node = get_node("/root/Settings")
	if int(st.get_value("best_service")) > 0:
		var best := UI.label("BEST NIGHT: %d SERVICE%s, %d TICKETS" % [int(st.get_value("best_service")),
			"" if int(st.get_value("best_service")) == 1 else "S", int(st.get_value("best_tickets"))], 20, Art.FLAME)
		best.name = "Best"
		best.add_theme_constant_override("outline_size", 8)
		best.add_theme_color_override("font_outline_color", Art.PAPER_INK)
		col.add_child(best)
	var save: Node = get_node("/root/Save")
	if save.exists():
		var d: Dictionary = save.read()
		col.add_child(Art.primary(UI.button("CONTINUE: SERVICE %d" % int(d.get("level", 1)), func(): _play(true), 96)))
		col.add_child(UI.button("NEW GAME", func(): _play(false)))
	else:
		col.add_child(Art.primary(UI.button("NEW GAME", func(): _play(false), 96)))
	col.add_child(UI.button("HOW TO PLAY", func(): HowToPlay.open(self)))
	col.add_child(UI.button("SETTINGS", func(): SettingsSheet.open(self)))
	col.add_child(UI.button("REPORT A BUG", func(): BugReport.open(self)))
	var ver := UI.label(Config.version_label(), 18, UI.DIM)
	ver.name = "Version"
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.anchor_right = 1.0
	ver.offset_top = -64
	ver.offset_bottom = -16
	ver.mouse_filter = Control.MOUSE_FILTER_STOP
	ver.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_ver_taps += 1
			if _ver_taps >= 5:
				_ver_taps = 0
				get_node("/root/DebugMenu").open())
	add_child(ver)
	for sh in get_tree().get_nodes_in_group("sheet"):
		if sh.get_parent() == self:
			move_child(sh, -1)


func _play(resume: bool) -> void:
	if not resume:
		get_node("/root/Save").clear()
	get_node("/root/Loader").go("res://scenes/game.tscn")


func _notification(what: int) -> void:
	# Android back on the title closes the top sheet; it never quits by accident.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var sheets := get_tree().get_nodes_in_group("sheet")
		if sheets.size() > 0:
			sheets[-1].queue_free()


func bug_state() -> String:
	return "title, save=%s" % get_node("/root/Save").exists()
