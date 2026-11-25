extends CanvasLayer
## Autoload "Subs": captions at the bottom of the screen.
##   Subs.say("Mara: Get down!")   spoken lines (only when the Subtitles setting is on)
##   Subs.cue("[door slams]")      important sounds; also only with Subtitles on
## Lines queue up; each shows for about a second plus a bit per word.

const UI = preload("res://scripts/ui.gd")

var _queue: Array[String] = []
var _label: Label
var _bg: PanelContainer
var _left := 0.0
## A gameplay screen can lift captions off its own bottom HUD: pixels from the bottom edge to the
## caption's bottom (0 = the default spot). Sheets still move them to the top.
var lift := 0.0


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = PanelContainer.new()
	_bg.anchor_left = 0.05
	_bg.anchor_right = 0.95
	_bg.anchor_top = 0.78
	_bg.anchor_bottom = 0.78
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_bg.add_theme_stylebox_override("panel", sb)
	add_child(_bg)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_label)
	_bg.visible = false
	get_tree().scene_changed.connect(clear)


func say(line: String) -> void:
	var s := get_node_or_null("/root/Settings")
	if s != null and not s.get_value("subtitles"):
		return
	_queue.append(line)


func cue(sound: String) -> void:
	say(sound)


func clear() -> void:
	_queue.clear()
	_left = 0.0
	_bg.visible = false


func showing() -> String:
	return _label.text if _bg.visible else ""


func _process(dt: float) -> void:
	# A modal sheet (pause, grade, game over) has its buttons where captions sit: move them to the top.
	var sheet := get_tree().get_first_node_in_group("sheet") != null
	if lift > 0.0 and not sheet:   # sits with its bottom edge lift px above the screen's bottom
		_bg.anchor_top = 1.0
		_bg.anchor_bottom = 1.0
		_bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_bg.offset_top = -lift
		_bg.offset_bottom = -lift
	else:
		var y := 0.015 if sheet else 0.78
		_bg.anchor_top = y
		_bg.anchor_bottom = y
		_bg.grow_vertical = Control.GROW_DIRECTION_END
		_bg.offset_top = 0.0
		_bg.offset_bottom = 0.0
	if _left > 0.0:
		_left -= dt
		if _left <= 0.0:
			_bg.visible = false
	if _left <= 0.0 and _queue.size() > 0:
		var line: String = _queue.pop_front()
		_label.text = line
		var sound := line.begins_with("[")   # a sound, not speech: smaller and softer, so it reads as a caption
		_label.add_theme_font_size_override("font_size", UI.font_size(18 if sound else 22))
		_label.add_theme_color_override("font_color", Color(UI.ink(), 0.75) if sound else UI.ink())
		_bg.visible = true
		_left = 1.2 + 0.3 * line.split(" ").size()
