extends Control
## Intro: a few caption cards. Tap to go to the next one, SKIP to jump to the title.
## Plays once; after that boot goes straight to the title, so a second play never forces it.
## Rush's opening: three cards, then the title.

const UI = preload("res://scripts/ui.gd")
const CARDS := [
	"Friday. 7 PM.\nThe rail is filling up.",
	"Every ticket has a clock.\nGet the food out before it hits zero.",
	"Walk three tables and the night is over.\n\nHeard?",
]

var i := 0
var text: Label


func _ready() -> void:
	theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			next())
	add_child(bg)
	text = UI.label("", 30)
	text.set_anchors_preset(Control.PRESET_CENTER)
	text.custom_minimum_size = Vector2(440, 0)
	text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	text.grow_vertical = Control.GROW_DIRECTION_BOTH
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text)
	var skip := UI.button("SKIP", done)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -170
	skip.offset_right = -24
	skip.offset_top = 28
	skip.offset_bottom = 28 + UI.MIN_TOUCH
	add_child(skip)
	_show()


func _show() -> void:
	text.text = CARDS[i]
	get_node("/root/Subs").clear()


func next() -> void:
	i += 1
	if i >= CARDS.size():
		done()
	else:
		_show()


func done() -> void:
	get_node("/root/Settings").set_value("intro_seen", true)
	get_node("/root/Loader").go("res://scenes/title.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		done()
