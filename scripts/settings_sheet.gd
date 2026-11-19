extends RefCounted
## The SETTINGS sheet (title and pause menu): SettingsSheet.open(parent).
## Changing text size or high contrast rebuilds the sheet so the new look shows at once.

const UI = preload("res://scripts/ui.gd")


static func open(parent: Node) -> VBoxContainer:
	var s: Node = parent.get_node("/root/Settings")
	var box := UI.sheet(parent, 500)
	box.add_child(UI.label("SETTINGS", 28, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UI.GAP)
	scroll.add_child(col)

	_slider(col, s, "MUSIC", "music", 0.0, 1.0)
	_slider(col, s, "SOUND EFFECTS", "sfx", 0.0, 1.0)
	_slider(col, s, "BRIGHTNESS", "gamma", 0.6, 1.6)
	_toggle(col, s, "VIBRATION", "vibration")
	var text_b := UI.button("TEXT SIZE: " + s.text_name())
	text_b.name = "text_size"
	text_b.pressed.connect(func():
		s.set_value("text_size", (int(s.get_value("text_size")) + 1) % s.TEXT_SCALES.size())
		_reopen(box, parent))
	col.add_child(text_b)
	_toggle(col, s, "SUBTITLES", "subtitles")
	_toggle(col, s, "HIGH CONTRAST", "high_contrast", func(): _reopen(box, parent))
	_toggle(col, s, "COLORBLIND COLORS", "colorblind")
	_toggle(col, s, "LEFT-HANDED CONTROLS", "left_handed")
	_toggle(col, s, "INVERT LOOK", "invert_y")
	_slider(col, s, "LOOK SENSITIVITY", "sensitivity", 0.3, 2.0)
	_toggle(col, s, "LOW GRAPHICS", "low_graphics")
	box.add_child(UI.button("DONE", func(): UI.close_sheet(box)))
	return box


static func _reopen(box: VBoxContainer, parent: Node) -> void:
	UI.close_sheet(box)
	open(parent)


static func _toggle(col: Control, s: Node, title: String, key: String, after: Callable = Callable()) -> void:
	var b := UI.button(title + ": " + ("ON" if s.get_value(key) else "OFF"))
	b.name = key
	b.pressed.connect(func():
		s.set_value(key, not s.get_value(key))
		b.text = title + ": " + ("ON" if s.get_value(key) else "OFF")
		if after.is_valid():
			after.call())
	col.add_child(b)


static func _slider(col: Control, s: Node, title: String, key: String, lo: float, hi: float) -> void:
	col.add_child(UI.label(title, 20))
	var sl := HSlider.new()
	sl.name = key
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = float(s.get_value(key))
	sl.custom_minimum_size = Vector2(0, UI.MIN_TOUCH - 16)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v: float): s.set_value(key, v))
	col.add_child(sl)
