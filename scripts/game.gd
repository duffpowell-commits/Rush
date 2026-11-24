extends Control
## Rush: a dinner service played turn by turn. Rules live in scripts/kitchen.gd; this draws them
## and turns taps into moves.
##   Tap a cook to pick them. Tap a station to walk there (1 action per station). Tap the station
##   they stand at, or the big button, to FIRE / PLATE / RUN. END TURN = one minute passes.
##   Every ticket out is a point. 3 tables walked in one service = GAME OVER. A service survived =
##   next service (level) = checkpoint (autosave).
## Foundation pieces here: PAUSE button, Android back = pause, auto-pause + save when the app
## goes to the background (call, home button), pause menu (resume / settings / bug / quit),
## GAME OVER -> try again / title, checkpoint autosave + CONTINUE, left-handed layout, low
## graphics, colorblind-safe colours with shape cues, subtitles for sound cues, vibration.

const UI = preload("res://scripts/ui.gd")
const SettingsSheet = preload("res://scripts/settings_sheet.gd")
const BugReport = preload("res://scripts/bug_report.gd")
const ControlsLegend = preload("res://scripts/controls_legend.gd")
const Coach = preload("res://scripts/coach.gd")

const Kitchen = preload("res://scripts/kitchen.gd")
const LIVES := 3             # tables you can walk in one service

## Live sliders (DEV MENU -> TUNE). Applied when a service starts.
const TUNE := {"ticket_time": [4.0, 16.0], "crew_ap": [1.0, 5.0], "stress_cap": [2.0, 12.0],
	"service_turns": [8.0, 40.0]}
var ticket_time := 9.0
var crew_ap := 3.0
var stress_cap := 6.0
var service_turns := 20.0

var level := 1               # service number
var score := 0               # tickets out, whole night
var lives := LIVES
var k: Kitchen
var sel := 0                 # selected cook
var paused := false
var over := false
var rng := RandomNumberGenerator.new()

var hud: Label
var pause_btn: Button
var act_btn: Button
var end_btn: Button
var note: Label
var field: Control
var sheet_box: VBoxContainer
var _settings: Node
var _save: Node


func _ready() -> void:
	_settings = get_node("/root/Settings")
	_save = get_node("/root/Save")
	_settings.changed.connect(_on_setting)
	rng.randomize()
	var d: Dictionary = _save.read()
	if not d.is_empty():
		level = int(d.get("level", 1))
		score = int(d.get("score", 0))
		lives = int(d.get("lives", LIVES))
		_night_before = score
	add_to_group("tunable")
	get_node("/root/DebugMenu").apply_tune(self)
	_new_service()
	_build()
	checkpoint()
	get_node("/root/Audio").music("music_loop")


# ---------------------------------------------------------------- state + saving

func state() -> Dictionary:
	return {"level": level, "score": _night_before, "lives": lives}   # finished services only: a reload restarts the service


func checkpoint() -> void:
	_save.write(state())


func bug_state() -> String:
	return "service %d turn %d out %d walked %d tickets %d paused %s over %s" % [level, k.turn, score, k.walked, k.tickets.size(), paused, over]


# ---------------------------------------------------------------- layout

func _on_setting(key: String) -> void:
	if key in ["text_size", "high_contrast", "left_handed"]:
		_build()


func _build() -> void:
	for c in get_children():
		if not c.is_in_group("sheet"):
			c.queue_free()
	theme = UI.theme()
	field = Control.new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	var f := field
	field.draw.connect(func(): _draw_field(f))
	field.gui_input.connect(_field_input)
	add_child(field)
	move_child(field, 0)
	hud = UI.label("", 22)
	hud.anchor_right = 1.0
	hud.offset_left = 190      # clear of the PAUSE button on either side
	hud.offset_right = -190
	hud.offset_top = 30
	hud.offset_bottom = 30 + UI.MIN_TOUCH
	hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var legend := ControlsLegend.make(["pause"])
	legend.name = "Legend"
	legend.top = 30 + UI.MIN_TOUCH + 12
	add_child(legend)
	# Thumb buttons: PAUSE top corner; the action and END TURN along the bottom, END TURN on the
	# thumb's side.
	var left: bool = _settings.get_value("left_handed")
	pause_btn = UI.button("PAUSE", pause)
	_corner(pause_btn, left, true, 150)
	end_btn = UI.button("END TURN", end_turn, 96)
	_corner(end_btn, not left, false, 230)
	act_btn = UI.button("FIRE", act, 96)
	_corner(act_btn, left, false, 230)
	note = UI.label("", 20, UI.ACCENT)
	note.anchor_right = 1.0
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_top = -40 - 96 - 70
	note.offset_bottom = -40 - 96 - 8
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)
	for sh in get_tree().get_nodes_in_group("sheet"):   # open sheets stay on top of the rebuilt HUD
		if sh.get_parent() == self:
			move_child(sh, -1)
	# First minute: one hint, taught by doing.
	if k != null and not Coach.seen("fire"):
		Coach.teach(self, "fire", "TAP GRILL TO FIRE", func(): return k.pans.any(func(p): return not p.is_empty()))
	_refresh_hud()


## Put a button in a corner. right=true -> right side. top=true -> top.
func _corner(b: Button, right: bool, top: bool, w: int) -> void:
	var h := int(b.custom_minimum_size.y)
	b.anchor_left = 1.0 if right else 0.0
	b.anchor_right = b.anchor_left
	b.anchor_top = 0.0 if top else 1.0
	b.anchor_bottom = b.anchor_top
	var x := -24 - w if right else 24
	var y := 30 if top else -40 - h
	b.offset_left = x
	b.offset_right = x + w
	b.offset_top = y
	b.offset_bottom = y + h
	add_child(b)


func _refresh_hud() -> void:
	if hud == null:
		return
	var god := " GOD" if get_node("/root/DebugMenu").god_mode else ""
	hud.text = "%s%s\nSERVICE %d" % [k.clock(), god, level]
	var a := k.action_here(sel)
	act_btn.text = a if a != "" else "NOTHING HERE"
	act_btn.disabled = a == ""
	if note != null:
		note.text = "  ".join(k.events)


# ---------------------------------------------------------------- PLAY

func _new_service() -> void:
	k = Kitchen.new()
	k.ticket_time = int(ticket_time)
	k.ap = int(crew_ap)
	k.stress_cap = int(stress_cap)
	k.turns = int(service_turns)
	k.start(level, rng.randi() if level > 1 else 0)
	lives = LIVES
	sel = 0


## Selected cook acts where they stand (the big button, or tapping their own station).
func act() -> void:
	if paused or over:
		return
	var what := k.action_here(sel)
	if k.act_here(sel):
		get_node("/root/Audio").sfx("good", {"FIRE": 0.9, "PLATE": 1.0, "RUN": 1.15}.get(what, 1.0))
		UI.buzz(15)
		if what == "RUN":
			score = k.served + _night_before
	_after_move()


## One minute of service passes.
func end_turn() -> void:
	if paused or over:
		return
	var walked_before := k.walked
	k.end_turn()
	if k.walked > walked_before and not get_node("/root/DebugMenu").god_mode:
		lives = LIVES - k.walked
		get_node("/root/Audio").sfx("bad")
		get_node("/root/Subs").cue("[buzz: table walked]")
		UI.buzz(80)
	elif k.walked > walked_before:
		k.walked = walked_before   # god mode: walked tables don't count
	for e in k.events:
		if e.begins_with("BURN"):
			get_node("/root/Audio").sfx("bad", 0.8)
			get_node("/root/Subs").cue("[sizzle: burn]")
		elif e.ends_with("WALKED OUT"):
			get_node("/root/Audio").sfx("bad", 0.6)
			get_node("/root/Subs").cue("[door slams: cook walked out]")
	if lives <= 0 or k.crew.all(func(c): return c.out):
		game_over()
		return
	if k.done:
		_service_done()
		return
	if k.crew[sel].out:
		for i in k.crew.size():
			if not k.crew[i].out:
				sel = i
	_after_move()


var _night_before := 0       # tickets out in earlier services tonight


func _service_done() -> void:
	_night_before += k.served
	score = _night_before
	get_node("/root/Audio").sfx("level")
	get_node("/root/Subs").cue("[chime: service %d done]" % level)
	level += 1
	checkpoint()
	_new_service()
	_after_move()


func debug_skip_level() -> void:
	_night_before += k.served
	score = _night_before
	level += 1
	checkpoint()
	_new_service()
	_after_move()


## The autoplay bot's turn: the greedy line cook from kitchen.gd, then END TURN.
func bot_play_turn() -> void:
	k.bot_turn()
	score = _night_before + k.served
	end_turn()


func _after_move() -> void:
	_refresh_hud()
	field.queue_redraw()


func _process(_dt: float) -> void:
	pass


# Layout, in field coordinates. Rail on top, the line in the middle, crew under their stations.
func _rail_y() -> float:
	return 30.0 + UI.MIN_TOUCH + 70.0


func station_rect(i: int) -> Rect2:
	var w := field.size.x
	var pad := 14.0
	var bw := (w - pad * 5.0) / 4.0
	var y := _rail_y() + 300.0
	return Rect2(pad + i * (bw + pad), y, bw, 170.0)


func cook_pos(c: int) -> Vector2:
	var r := station_rect(k.crew[c].at)
	var same := 0
	var idx := 0
	for i in k.crew.size():
		if k.crew[i].at == k.crew[c].at and not k.crew[i].out:
			if i == c:
				idx = same
			same += 1
	var step := COOK_R * 2.0 + UI.GAP          # a full touch target apart
	var half := (same - 1) / 2.0 * step
	var off := 0.0 if same <= 1 else idx * step - half
	# Keep the pair on screen at the end stations: clamp the pair's centre, not each cook.
	var edge := COOK_R + 8.0 + half
	var cx := clampf(r.get_center().x, edge, field.size.x - edge)
	return Vector2(cx + off, r.end.y + 70.0)


const COOK_R := 36.0         # 72 wide: the touch rule


func _field_input(e: InputEvent) -> void:
	if paused or over:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tap(e.position)


## A tap at a point on the field (also used by the autoplay bot).
func tap(p: Vector2) -> void:
	for c in k.crew.size():
		if not k.crew[c].out and cook_pos(c).distance_to(p) <= COOK_R + 6.0:
			sel = c
			get_node("/root/Audio").sfx("click")
			_after_move()
			return
	for i in Kitchen.STATIONS.size():
		if station_rect(i).grow(6.0).has_point(p):
			if k.crew[sel].at == i:
				act()
			elif k.move(sel, i):
				get_node("/root/Audio").sfx("click")
				_after_move()
			return


func _draw_field(f: Control) -> void:
	f.draw_rect(Rect2(Vector2.ZERO, f.size), UI.BG)
	var font := ThemeDB.fallback_font
	var low: bool = _settings.get_value("low_graphics")
	var ink := UI.ink()
	# --- the rail: tickets on now, then what's coming next
	var y0 := _rail_y()
	var shown: Array = k.tickets.duplicate()
	shown.sort_custom(func(a, b): return a.time < b.time)
	var pad := 10.0
	var cw := (f.size.x - pad * 5.0) / 4.0
	for i in mini(shown.size(), 4):
		var t: Dictionary = shown[i]
		var r := Rect2(pad + i * (cw + pad), y0, cw, 200.0)
		var tone := "good" if t.time > 4 else ("warn" if t.time > 2 else "bad")
		f.draw_rect(r, UI.panel_color())
		f.draw_rect(r, UI.key(tone), false, 4.0 if tone == "bad" else 2.0)
		f.draw_string(font, r.position + Vector2(8, 26), ("BIG T%d" if t.big else "T%d") % t.table,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(18), ink)
		# Clock: number plus a shape cue (filled bars), not colour alone.
		f.draw_string(font, r.position + Vector2(r.size.x - 44, 28), "%d'" % t.time,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(24), UI.key(tone))
		for b in mini(t.time, 10):
			f.draw_rect(Rect2(r.position.x + 8 + b * ((r.size.x - 16) / 10.0), r.position.y + 36, (r.size.x - 16) / 10.0 - 2, 6), UI.key(tone))
		var iy := r.position.y + 66
		for it in t.items:
			var mark: String = {"wait": "  ", "cooking": "~ ", "carried": "> ", "served": "V "}[it.state]
			var col: Color = UI.DIM if it.state == "served" else ink
			f.draw_string(font, Vector2(r.position.x + 8, iy), mark + it.dish, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, UI.font_size(16), col)
			iy += 30
	if shown.size() > 4:
		f.draw_string(font, Vector2(f.size.x - 70, y0 + 222), "+%d" % (shown.size() - 4), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(20), UI.key("warn"))
	f.draw_string(font, Vector2(pad, y0 - 14), "OUT %d   WALKED %d/%d   TIPS $%d" % [score, k.walked, LIVES, k.tips],
		HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20, UI.font_size(18), UI.key("bad") if k.walked >= LIVES - 1 else ink)
	var nx := "NEXT: "
	for pv in k.preview(3):
		nx += "%d' %s   " % [pv["in"], ("BIG" if pv.ticket.big else "%d dish" % pv.ticket.items.size())]
	if k.preview(1).is_empty():
		nx += "last tickets"
	f.draw_string(font, Vector2(pad, y0 + 240), nx, HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20, UI.font_size(18), UI.DIM)
	# --- the line
	for i in Kitchen.STATIONS.size():
		var r := station_rect(i)
		var here: bool = k.crew[sel].at == i
		f.draw_rect(r, UI.panel_color())
		f.draw_rect(r, UI.ACCENT if here else Color("4a5878"), false, 3.0 if here else 2.0)
		f.draw_string(font, r.position + Vector2(0, 30), Kitchen.STATIONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(18), ink)
		if i < k.pans.size() and not k.pans[i].is_empty():
			var p: Dictionary = k.pans[i]
			var up: bool = p.left <= 0
			var burning: bool = up and p.sat >= k.burn_after
			var tone := ("bad" if burning else "warn") if up else "info"
			if not low and up:
				f.draw_circle(r.get_center() + Vector2(0, 20), 46.0, Color(UI.key(tone), 0.2))
			f.draw_circle(r.get_center() + Vector2(0, 20), 34.0, UI.key(tone))
			if burning:   # shape cue, not colour alone: a thick ring the turn before it burns
				f.draw_arc(r.get_center() + Vector2(0, 20), 40.0, 0.0, TAU, 32, UI.key("bad"), 5.0)
			f.draw_string(font, r.position + Vector2(0, r.size.y - 18), p.dish, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(16), ink)
			f.draw_string(font, r.get_center() + Vector2(-30, 30), ("BURN!" if burning else "UP!") if up else "%d'" % p.left,
				HORIZONTAL_ALIGNMENT_CENTER, 60, UI.font_size(22), Color.BLACK)
		elif i == Kitchen.PASS_IX:
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), "RUN HERE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(16), UI.DIM)
	# --- crew
	for c in k.crew.size():
		var cr: Dictionary = k.crew[c]
		if cr.out:
			continue
		var pos := cook_pos(c)
		if c == sel:
			f.draw_circle(pos, COOK_R + 7.0, UI.ACCENT)
		f.draw_circle(pos, COOK_R, Color("2b3448"))
		f.draw_string(font, pos + Vector2(-COOK_R, 7), cr.name, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2, UI.font_size(18), ink)
		for a in cr.ap:   # action pips
			f.draw_circle(pos + Vector2(-16 + a * 16, -COOK_R - 12), 6.0, UI.key("info"))
		var sw := 64.0
		var frac := float(cr.stress) / k.stress_cap
		f.draw_rect(Rect2(pos.x - sw / 2, pos.y + COOK_R + 8, sw, 8), Color("2b3448"))
		f.draw_rect(Rect2(pos.x - sw / 2, pos.y + COOK_R + 8, sw * frac, 8), UI.key("bad" if frac >= 0.6 else "warn"))
		if not cr.hand.is_empty():
			f.draw_string(font, pos + Vector2(-60, COOK_R + 40), "> " + cr.hand.dish, HORIZONTAL_ALIGNMENT_CENTER, 120, UI.font_size(15), UI.key("good"))
	var gone: Array = k.crew.filter(func(cr): return cr.out).map(func(cr): return cr.name)
	if not gone.is_empty():
		f.draw_string(font, Vector2(0, station_rect(0).end.y + 160), "WALKED OUT: " + ", ".join(gone), HORIZONTAL_ALIGNMENT_CENTER, f.size.x, UI.font_size(18), UI.key("bad"))


# ---------------------------------------------------------------- pause + game over

func pause() -> void:
	if paused or over:
		return
	paused = true
	checkpoint()
	get_node("/root/Subs").clear()
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("PAUSED", 30, UI.ACCENT))
	sheet_box.add_child(UI.button("RESUME", resume, 88))
	sheet_box.add_child(UI.button("SETTINGS", func(): SettingsSheet.open(self)))
	sheet_box.add_child(UI.button("REPORT A BUG", func(): BugReport.open(self)))
	sheet_box.add_child(UI.button("QUIT TO TITLE", quit_to_title))


func resume() -> void:
	UI.close_sheet(sheet_box)
	sheet_box = null
	paused = false


func quit_to_title() -> void:
	if not over:
		checkpoint()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func game_over() -> void:
	over = true
	_save.clear()
	get_node("/root/Audio").sfx("gameover")
	get_node("/root/Subs").cue("[game over sting]")
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("GAME OVER", 40, UI.key("bad")))
	sheet_box.add_child(UI.label("Service %d, %d tickets out" % [level, score], 24))
	sheet_box.add_child(UI.button("TRY AGAIN", func(): get_tree().reload_current_scene(), 88))
	sheet_box.add_child(UI.button("TITLE", quit_to_title))


func _notification(what: int) -> void:
	match what:
		# The phone took the app away (call, home button, notification shade): pause + save.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			pause.call_deferred()
		# Android back / back gesture: close the top sheet, else pause. Never quits.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_go_back.call_deferred()


func _go_back() -> void:
	var sheets := get_tree().get_nodes_in_group("sheet")
	if sheets.size() > 1:
		sheets[-1].queue_free()
	elif paused and not over:
		resume()
	else:
		pause()
