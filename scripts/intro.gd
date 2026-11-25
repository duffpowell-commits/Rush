extends Control
## Intro: a few caption cards. Tap to go to the next one, SKIP to jump to the title.
## Plays once; after that boot goes straight to the title, so a second play never forces it.
## Rush's opening: three cards, then the title.

const UI = preload("res://scripts/ui.gd")
const Art = preload("res://scripts/menu_art.gd")
const CARDS := [
	"Friday. 7 PM.\nThe rail is filling up.",
	"Every ticket has a clock.\nGet the food out before it hits zero.",
	"Walk three tables and the night is over.\n\nHeard?",
]

var i := 0
var text: Label
var stamp: Label


func _ready() -> void:
	theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			next())
	add_child(bg)
	Art.backdrop(self, load("res://assets/art/bg_line.jpg"), 0.55)
	# The caption is an order slip pinned over the kitchen.
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", Art.paper_style())
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -220
	card.offset_right = 220
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.rotation = -0.025
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)
	stamp = UI.label("", 18, Art.EMBER)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stamp)
	text = UI.label("", 30, Art.PAPER_INK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	var hint := UI.label("TAP TO CONTINUE", 18, UI.ink())
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -150
	hint.offset_bottom = -110
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	var tw := create_tween().set_loops()
	tw.tween_property(hint, "modulate:a", 0.35, 0.8)
	tw.tween_property(hint, "modulate:a", 1.0, 0.8)
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
	stamp.text = "ORDER %d OF %d" % [i + 1, CARDS.size()]
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
