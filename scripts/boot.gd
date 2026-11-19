extends Control
## Boot: a short splash, then the intro (first launch only) or the title.

const UI = preload("res://scripts/ui.gd")
const Config = preload("res://scripts/config.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var l := UI.label(Config.game_title(), 36, UI.ACCENT)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(l)
	await get_tree().create_timer(0.6).timeout
	var seen: bool = get_node("/root/Settings").get_value("intro_seen")
	get_tree().change_scene_to_file("res://scenes/title.tscn" if seen else "res://scenes/intro.tscn")
