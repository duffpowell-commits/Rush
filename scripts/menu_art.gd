extends RefCounted
## Menu dressing for Rush: painted backdrops, the drawn RUSH logo and the ticket-paper card.
## The logo is drawn in code (no AI lettering), so it stays crisp at any size and text setting.

const UI = preload("res://scripts/ui.gd")

const PAPER := Color("f3ead2")
const PAPER_INK := Color("1d1a17")
const FLAME := Color("f5a623")
const EMBER := Color("c8361f")


## Full-screen painted art, cover-fit, with dark fades top and bottom so text and buttons read.
## `fade` 0..1 darkens the whole picture too (intro cards sit on a dimmer kitchen).
static func backdrop(parent: Control, tex: Texture2D, fade: float = 0.0) -> TextureRect:
	var art := TextureRect.new()
	art.name = "Backdrop"
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	var shade := TextureRect.new()
	var g := Gradient.new()
	var a := 0.95 if UI.contrast() else 0.8
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 1.0])
	g.colors = PackedColorArray([Color(UI.BG, a), Color(UI.BG, fade), Color(UI.BG, maxf(fade, 0.35)), Color(UI.BG, a + 0.15)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	return art


## The RUSH logo: heavy slanted letters, ink outline, ember drop shadow, speed lines, and a
## ticket strip underneath with the tagline.
class Logo extends Control:
	var word := "RUSH"
	var tagline := "DINNER SERVICE, TURN BY TURN"

	func _init() -> void:
		name = "Logo"
		custom_minimum_size = Vector2(0, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _font() -> Font:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 1.4
		return f

	func _draw() -> void:
		var f := _font()
		var size_px := 136
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var cx := size.x * 0.5
		var base := Vector2(cx - w * 0.5 + 14, 160)
		var hc := UI.contrast()
		var fill := Color.WHITE if hc else FLAME
		var shadow := Color.BLACK if hc else EMBER
		# Speed lines streaking off the left of the word.
		for i in 3:
			var y := base.y - 96 + i * 30
			var ln := 64.0 - i * 14
			var x1 := base.x - 6 - i * 12
			draw_rect(Rect2(x1 - ln, y, ln, 12), PAPER_INK)
			draw_rect(Rect2(x1 - ln + 3, y + 3, ln - 6, 6), fill)
		draw_set_transform_matrix(Transform2D(0.0, Vector2.ONE, -0.22, Vector2(-base.y * 0.22, 0)))
		draw_string_outline(f, base + Vector2(7, 9), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 26, PAPER_INK)
		draw_string(f, base + Vector2(7, 9), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, shadow)
		draw_string_outline(f, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 18, PAPER_INK)
		draw_string(f, base, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, fill)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# Ticket strip: cream paper, ink border, notched ends, tagline.
		var ts := 19
		var tw := f.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 44
		var strip := Rect2(cx - tw * 0.5, base.y + 30, tw, 40)
		draw_set_transform(strip.get_center(), -0.035, Vector2.ONE)
		var r := Rect2(-strip.size * 0.5, strip.size)
		draw_rect(r.grow(3), PAPER_INK)
		draw_rect(r, Color.WHITE if hc else PAPER)
		for k in [r.position.x, r.end.x]:
			draw_circle(Vector2(k, 0), 9, PAPER_INK)
		draw_string(f, Vector2(r.position.x, 7), tagline, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, ts, PAPER_INK)
		draw_set_transform_matrix(Transform2D.IDENTITY)


## A ticket-paper panel style (cream, ink border, square corners like an order slip).
static func paper_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var hc := UI.contrast()
	sb.bg_color = Color.WHITE if hc else PAPER
	sb.set_border_width_all(4)
	sb.border_color = PAPER_INK
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(4, 6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 26
	return sb


## The main call to action: filled flame orange with ink text, so it is the first thing a thumb finds.
static func primary(b: Button) -> Button:
	var hc := UI.contrast()
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE if hc else (FLAME.darkened(0.2) if state == "pressed" else FLAME)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(4)
		sb.border_color = PAPER_INK
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, PAPER_INK)
	b.add_theme_font_size_override("font_size", UI.font_size(26))
	return b


## Diner ticket chrome for the progression sheets. Keep the gameplay colours,
## accessible text sizes and high-contrast theme owned by UI.
static func diner_sheet(box: VBoxContainer) -> void:
	if UI.contrast():
		return
	var root: Control = box.get_meta("sheet")
	var t := root.theme
	var panel := t.get_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	panel.bg_color = Color("392321")
	panel.border_color = PAPER
	panel.set_corner_radius_all(5)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var b := t.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		b.bg_color = PAPER if state != "disabled" else Color("806b60")
		if state == "pressed":
			b.bg_color = Color("e4bda0")
		b.border_color = Color("953b30") if state == "pressed" else Color("b86450")
		b.set_corner_radius_all(5)
		t.set_stylebox(state, "Button", b)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", PAPER_INK)
	t.set_color("font_disabled_color", "Button", Color("fff1dc"))


## Gameplay enamel buttons: preserve touch targets, labels, button nodes and accessibility.
## Cream action, red end-turn/control buttons; disabled states remain visibly muted.
static func diner_button(b: Button, paper: bool = false) -> void:
	if UI.contrast():
		return
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var disabled: bool = state == "disabled"
		var base := PAPER if paper else Color("792e2a")
		if state == "hover":
			base = base.lightened(0.10)
		elif state == "pressed":
			base = base.darkened(0.14)
		sb.bg_color = Color("514842") if disabled else base
		sb.border_color = Color("9a8a77") if disabled else (Color("762e29") if paper else PAPER)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color("1d1714")
		sb.shadow_size = 3 if state == "pressed" else 5
		sb.shadow_offset = Vector2(0, 3)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, PAPER_INK if paper else PAPER)
	b.add_theme_color_override("font_disabled_color", Color("d8cbbc"))
