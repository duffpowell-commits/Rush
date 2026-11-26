extends Control
## Rush: a dinner service played turn by turn. Rules live in scripts/kitchen.gd; this draws them
## and turns taps into moves.
##   Tap a cook to pick them. Tap a station to walk there (1 action per station). Tap the station
##   they stand at, or the big button, to FIRE / PLATE / RUN. END TURN = one minute passes.
##   Every ticket out is a point. 3 tables walked in one service = GAME OVER. A service survived =
##   a grade sheet, then the next service (level) = checkpoint (autosave). Pause / focus-out saves
##   the service in progress too (kitchen.to_dict), so CONTINUE picks up the same minute.
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
## Real art (Forge, style A "flat ink", Nov 25; docs/ART_LOG.md). Code-drawn shapes stay on top
## for every state a player must read (pans, clocks, rings), so art never carries meaning alone.
const MenuArt = preload("res://scripts/menu_art.gd")
const Upgrades = preload("res://scripts/upgrades.gd")
const HowToPlay = preload("res://scripts/how_to_play.gd")
const ART_BG := preload("res://assets/art/bg_line.jpg")
const ART_STATIONS := [preload("res://assets/art/station_grill.png"), preload("res://assets/art/station_fryer.png"),
	preload("res://assets/art/station_saute.png"), preload("res://assets/art/station_cold.png"), preload("res://assets/art/station_pass.png")]
const ART_COOKS := {"DEV": preload("res://assets/art/cook_dev.png"), "MO": preload("res://assets/art/cook_mo.png")}
const ART_DISHES := {"BURGER": preload("res://assets/art/dish_burger.png"), "STEAK": preload("res://assets/art/dish_steak.png"),
	"FRIES": preload("res://assets/art/dish_fries.png"), "WINGS": preload("res://assets/art/dish_wings.png"),
	"PASTA": preload("res://assets/art/dish_pasta.png"), "SCAMPI": preload("res://assets/art/dish_scampi.png"),
	"SALAD": preload("res://assets/art/dish_salad.png"), "CAKE": preload("res://assets/art/dish_cake.png")}
const LIVES := 3             # tables you can walk in one service

## Live sliders (DEV MENU -> TUNE). Applied when a service starts.
const TUNE := {"ticket_time": [4.0, 16.0], "crew_ap": [1.0, 5.0], "stress_cap": [2.0, 12.0],
	"service_turns": [8.0, 40.0], "first_tickets": [2.0, 14.0], "more_tickets": [0.0, 4.0],
	"rush_stress": [0.0, 3.0]}
var ticket_time := 9.0
var crew_ap := 3.0
var stress_cap := 6.0
var service_turns := 20.0
var first_tickets := 7.0
var more_tickets := 1.0
var rush_stress := 1.0

var level := 1               # service number
var score := 0               # tickets out, whole night
var lives := LIVES
var lives_max := LIVES     # LIVES, +1 with COMP CARDS
var cash := 0                # tips banked tonight, spent in the SHOP between services
var twist_box: VBoxContainer   # the TONIGHT card while it's up
var perks: Array = []        # upgrades owned tonight (upgrades.gd)
var k: Kitchen
var sel := 0                 # selected cook
var _portrait_pick := false  # the last field tap picked a cook by face: the next station tap sends them
var _pick_from := {}         # last station tap that switched cooks: {st, prev}; a 2nd tap there sends prev
var pick_ix := -1            # dish on that ticket the player tapped: FIRE cooks exactly it (-1 = any)
var pick_tid := 0            # ticket the player tapped: FIRE cooks for it first (0 = most urgent)
var paused := false
var over := false
var between := false         # the grade sheet between two services is up
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
		_night_before = score
		cash = int(d.get("cash", 0))
		perks = (d.get("perks", []) as Array).filter(func(p): return Upgrades.ALL.has(p))
	add_to_group("tunable")
	get_node("/root/DebugMenu").apply_tune(self)
	_new_service()
	# Pick the service in progress back up: same minute, same tickets, same tables walked.
	var mid: Variant = d.get("kitchen", {})
	if mid is Dictionary and not mid.is_empty() and int(mid.get("service", 0)) == level:
		var back := Kitchen.new()
		if back.from_dict(mid):
			k = back
			lives = lives_max - k.walked
			score = _night_before + k.served
	_build()
	checkpoint()
	get_node("/root/Audio").music_layers("music_loop", "music_busy")   # the kitchen gets louder as tickets go red
	_music_heat()


# ---------------------------------------------------------------- state + saving

## score = finished services only; the service in progress rides along in "kitchen" (its own
## served count), so a reload can't count tickets twice.
func state() -> Dictionary:
	var d := {"level": level, "score": _night_before, "cash": cash, "perks": perks.duplicate()}
	if k != null and not between and not over and not k.done:
		d["kitchen"] = k.to_dict()
	return d


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
	end_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # the two-line burn warning at big text sizes
	end_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner(end_btn, not left, false, 230)
	act_btn = UI.button("FIRE", act, 96)
	act_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # big text sizes wrap onto two lines, not past the edge
	act_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN   # a taller wrapped button grows up, never off the bottom
	_corner(act_btn, left, false, 230)
	note = UI.label("", 20, UI.ACCENT)
	note.anchor_right = 1.0
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_top = -40 - 96 - 70
	note.offset_bottom = -40 - 96 - 8
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)
	get_node("/root/Subs").lift = 40 + 96 + 70 + 6   # sound captions sit above the status line, never on it
	for sh in get_tree().get_nodes_in_group("sheet"):   # open sheets stay on top of the rebuilt HUD
		if sh.get_parent() == self:
			move_child(sh, -1)
	# First minute: one hint, taught by doing.
	_coach_next()
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

	if pick_tid != 0 and k.ticket(pick_tid).is_empty():
		pick_tid = 0   # served or walked: back to most urgent
	if pick_tid == 0 or (pick_ix >= 0 and k.ticket(pick_tid).items[pick_ix].state != "wait"):
		pick_ix = -1   # the picked dish went on: the table stays picked
	var a := k.action_here(sel)
	end_btn.text = "END TURN"
	var quits := cooks_quitting()
	if not quits.is_empty():   # the worst news first: who walks out if the turn ends now
		end_btn.text = "END TURN\n%s QUITS" % quits[0]
	for i in (k.pans.size() if quits.is_empty() else 0):   # warn on the button that does it: ending the turn now burns this pan
		var p: Dictionary = k.pans[i]
		if not p.is_empty() and p.left <= 0 and p.sat >= k.burn_after:
			end_btn.text = "END TURN\n%s BURNS" % Kitchen.STATIONS[i]
			break
	if end_btn.text == "END TURN" and not k.done and not between and k.tickets.is_empty() and k.incoming.is_empty():
		end_btn.text = "END TURN\nFINISH SERVICE"   # every table is out: say what the button does now
	if end_btn.text == "END TURN":   # a turn earlier (stress pass): one more worked turn after this one and they quit
		for c in k.crew.size():
			if not k.crew[c].out and stress_after(c) == k.stress_cap - 1:
				end_btn.text = "END TURN\n%s NEAR QUIT" % k.crew[c].name
				break
	act_btn.text = a if a != "" else "TAP A STATION"   # nothing to do here: say how to move
	if a == "" and not k.crew[sel].out and k.crew[sel].ap <= 0:   # say why: this cook is spent till END TURN
		act_btn.text = "%s: NO MOVES" % k.crew[sel].name   # short: HUGE text wraps it over the status line
	if a == "FIRE":   # say which table it cooks for, picked or not
		var fp := k.fire_pick(sel, pick_tid, pick_ix)
		act_btn.text = "FIRE T%d" % fp.t.table
		if pick_ix >= 0 and fp.t.id == pick_tid and fp.item == k.ticket(pick_tid).items[pick_ix]:
			act_btn.text = "FIRE %s" % fp.item.dish   # the tapped dish, by name
	elif a == "RUSH":   # warn when this rush would send the cook over the edge
		var cr: Dictionary = k.crew[sel]
		# end of turn also adds 1 to a working cook while any ticket will be red (2 minutes or less)
		var red := 1 if k.tickets.any(func(t): return t.time - 1 > 0 and t.time - 1 <= 2) else 0
		act_btn.text = "RUSH (FREE)" if k.rush_stress <= 0 else ("RUSH (QUITS!)" if cr.stress + k.rush_stress + red >= k.stress_cap else "RUSH +%d STRESS" % k.rush_stress)
	elif a == "RUN" and k.tray > 1:   # a tray: say how many plates go out on this one action
		var n := mini(k.tray, k.window.size() + (0 if k.crew[sel].hand.is_empty() else 1))
		if n > 1:
			act_btn.text = "RUN %d PLATES" % n
	if a != "":   # whose move this is, on the button (stress pass: taps moved the wrong cook)
		var named := "%s: %s" % [k.crew[sel].name, act_btn.text]
		var bf := act_btn.get_theme_font("font")
		var room := act_btn.size.x - 20.0 if act_btn.size.x > 40.0 else 210.0
		if bf == null or bf.get_string_size(named, HORIZONTAL_ALIGNMENT_LEFT, -1, act_btn.get_theme_font_size("font_size")).x <= room * 2.0:
			act_btn.text = named   # up to two lines: the button wraps, and grows up, not off the screen
	act_btn.disabled = a == ""
	if note != null:
		note.text = " | ".join(k.events)   # a bar between events: they ran together as one sentence


# ---------------------------------------------------------------- PLAY

## Difficulty that fits the player (Nov 25): the PACE setting plus the house's read of you.
## RELAXED: a ticket fewer, two more minutes a ticket. SLAMMED: two more tickets, a minute less.
## house_ease (-2..2): each point is a ticket fewer (or more); at +-2 a ticket's clock moves a minute too.
const PACES := ["RELAXED", "NORMAL", "SLAMMED"]


func pace_adjust() -> Dictionary:
	var pace := clampi(int(_settings.get_value("pace")), 0, 2)
	var ease := clampi(int(_settings.get_value("house_ease")), -2, 2)
	var t: int = [-1, 0, 2][pace] - ease
	var m: int = [2, 0, -1][pace] + (1 if ease >= 2 else (-1 if ease <= -2 else 0))
	return {"tickets": t, "time": m}


## Tickets the given service brings, after pace and the house's read.
func tickets_for(n: int) -> int:
	var base := int(first_tickets)
	return maxi(1, maxi(mini(3, base), base + pace_adjust().tickets) + int(more_tickets) * (n - 1))


## After a service (or a lost night), the house reads you: a rough one eases the next, an aced one pushes it.
## Returns a line for the grade sheet ("" when nothing moved).
func _house_reads(g: String, lost: bool = false) -> String:
	var ease := clampi(int(_settings.get_value("house_ease")), -2, 2)
	var was := ease
	if lost or g in ["D", "F"]:
		ease = mini(ease + 1, 2)
	elif g in ["A+", "A"]:
		ease = maxi(ease - 1, -2)
	if ease == was:
		return ""
	_settings.set_value("house_ease", ease)
	return "The floor eases off a ticket." if ease > was else "The house noticed: one more ticket."


func _new_service() -> void:
	_pick_from = {}   # a station handoff only counts on the very next field tap
	rail_off = 0
	for ch in get_children():   # the new service's clock restarts at turn 0: so does a hint's wait
		if ch.name.begins_with("Coach_"):
			ch.set_meta("turn", 0)
	k = Kitchen.new()
	var u := Upgrades.apply({"ticket_time": int(ticket_time), "stress_cap": int(stress_cap),
		"rush_stress": int(rush_stress), "lives": LIVES}, perks)
	var adj := pace_adjust()
	k.ticket_time = maxi(mini(5, u.ticket_time), u.ticket_time + adj.time)   # pace never pushes below 5 (TUNE can)
	k.ap = int(crew_ap)
	k.stress_cap = u.stress_cap
	k.turns = int(service_turns)
	k.first_tickets = maxi(mini(3, int(first_tickets)), int(first_tickets) + adj.tickets)
	k.more_tickets = int(more_tickets)
	k.rush_stress = u.rush_stress
	k.tray = u.tray
	k.start(level, rng.randi() if level > 1 else 0)
	lives_max = u.lives
	lives = lives_max
	sel = 0
	pick_tid = 0
	pick_ix = -1


## Selected cook acts where they stand (the big button, or tapping their own station).
func act() -> void:
	_pick_from = {}   # a station handoff only counts on the very next field tap
	if paused or over or between:
		return
	var what := k.action_here(sel)
	var at: int = k.crew[sel].at
	var tips_before := k.tips
	var served_before := k.served
	if k.act_here(sel, pick_tid, true, pick_ix):
		var snd: String = {"FIRE": "fire", "RUSH": "rush", "PLATE": "plate", "RUN": "bell"}.get(what, "good")
		get_node("/root/Audio").sfx(snd, 1.12 if what == "RUN" and k.served > served_before else randf_range(0.95, 1.05))
		if what == "RUSH":
			get_node("/root/Subs").cue("[sizzle: rushed]")
		UI.buzz(15)
		var c := station_rect(at).get_center()
		var top := Vector2(c.x, station_rect(at).position.y - 6)   # words above the box, clear of its name
		match what:
			"FIRE":
				_fx_burst(c + Vector2(0, 10), MenuArt.FLAME, 14)
				_fx_text(top, "FIRED!", MenuArt.FLAME)
			"RUSH":
				_fx_burst(c + Vector2(0, 10), MenuArt.EMBER, 22)
				_fx_text(top, "RUSHED!", MenuArt.FLAME)
			"PLATE":
				_fx_ring(c, UI.key("good"))
				_fx_text(top, "UP!", UI.key("good"))
			"RUN":
				score = k.served + _night_before
				_fx_text(top, "+$%d" % (k.tips - tips_before) if k.tips > tips_before else "RAN", UI.key("good"))
				if k.served > served_before:   # a whole table out: the big moment
					_fx_ring(c, UI.ACCENT, 90.0)
					_fx_burst(c, UI.key("good"), 24)
					_fx_text(Vector2(field.size.x / 2, _rail_y() + 120), "TABLE OUT!", UI.ACCENT, 40)
					_shake(4.0)
	_after_move()


# ---------------------------------------------------------------- juice (Nov 25, step 3)
# Short-lived effects drawn on top of the field: sparks, rings, floating words, a screen shake.
# Words always ride along, so nothing is colour or motion alone. Low graphics keeps the words only.

var fx: Array = []           # {kind, pos, t, life, col, text, size, vel}
var shake_amt := 0.0


func _fx_text(pos: Vector2, text: String, col: Color, size: int = 28) -> void:
	fx.append({"kind": "text", "pos": pos, "t": 0.0, "life": 0.9, "col": col, "text": text, "size": size})


func _fx_ring(pos: Vector2, col: Color, r: float = 60.0) -> void:
	if not _settings.get_value("low_graphics"):
		fx.append({"kind": "ring", "pos": pos, "t": 0.0, "life": 0.45, "col": col, "r": r})


func _fx_burst(pos: Vector2, col: Color, n: int) -> void:
	if _settings.get_value("low_graphics"):
		return
	for i in int(n * get_node("/root/Feel").spark_scale):   # DEV MENU -> TUNE spark_scale
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a) - 0.8) * randf_range(80.0, 220.0)
		fx.append({"kind": "spark", "pos": pos, "t": 0.0, "life": randf_range(0.35, 0.7), "col": col, "vel": v})


func _shake(amt: float) -> void:
	if not _settings.get_value("low_graphics"):
		shake_amt = maxf(shake_amt, amt * get_node("/root/Feel").shake_scale)   # TUNE shake_scale


func _tick_fx(dt: float) -> void:
	if paused:
		if field != null:
			field.position = Vector2.ZERO   # no shake left offset under the sheet
		return   # effects hold still under the pause sheet
	if k != null and not (paused or over or between) and k.tickets.any(func(t): return t.time <= 2) and not _settings.get_value("low_graphics"):
		field.queue_redraw()   # red tickets pulse (drawn in _draw_field)
	if fx.is_empty() and shake_amt <= 0.0:
		return
	for e in fx:
		e.t += dt
		if e.kind == "spark":
			e.vel.y += 420.0 * dt
			e.pos += e.vel * dt
		elif e.kind == "text":
			e.pos.y -= 40.0 * dt
	fx = fx.filter(func(e): return e.t < e.life)
	if shake_amt > 0.0:
		shake_amt = maxf(0.0, shake_amt - 30.0 * dt)
		field.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	else:
		field.position = Vector2.ZERO
	field.queue_redraw()


func _draw_fx(f: Control) -> void:
	var font := ThemeDB.fallback_font
	for e in fx:
		var k01: float = e.t / e.life
		var a := 1.0 - k01
		match e.kind:
			"spark":
				f.draw_circle(e.pos, 3.0 + 3.0 * a, Color(e.col, a))
			"ring":
				f.draw_arc(e.pos, e.r * (0.4 + k01), 0.0, TAU, 32, Color(e.col, a), 6.0 * a + 1.0)
			"text":
				var sz := UI.font_size(e.size)
				var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - e.t * 8.0)   # a quick pop as it appears
				var fs := int(sz * pop)
				var w := font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				while w > f.size.x - 12.0 and fs > 12:   # big text sizes: shrink to fit the field
					fs -= 2
					w = font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var p: Vector2 = e.pos - Vector2(w / 2.0, 0)
				p.x = clampf(p.x, 6.0, f.size.x - w - 6.0)
				f.draw_string_outline(font, p, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(MenuArt.PAPER_INK, a))
				f.draw_string(font, p, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(e.col, a))


## One minute of service passes.
func end_turn() -> void:
	_pick_from = {}   # a station handoff only counts on the very next field tap
	_portrait_pick = false
	if paused or over or between:
		return
	rail_off = 0   # a new turn opens on the most urgent tickets
	var walked_before := k.walked
	var critic_before := k.critic
	var tickets_before: Array = k.tickets.map(func(t): return t.id)
	var stress_before: Array = k.crew.map(func(c): return c.stress)
	k.end_turn()
	for c in k.crew.size():   # say what the turn cost, on the cook who paid it
		var d: int = k.crew[c].stress - stress_before[c]
		if d > 0 and not k.crew[c].out:
			_fx_text(cook_pos(c) + Vector2(0, -COOK_R - 30), "+%d STRESS" % d, UI.key("bad"), 24)
	if k.tickets.any(func(t): return not tickets_before.has(t.id)):
		get_node("/root/Audio").sfx("ticket", randf_range(0.95, 1.05))
		get_node("/root/Subs").cue("[printer: new ticket]")
	if k.walked > walked_before and not get_node("/root/DebugMenu").god_mode:
		lives = lives_max - k.walked
		get_node("/root/Audio").sfx("walk")
		get_node("/root/Audio").duck()
		get_node("/root/Subs").cue("[chair scrapes: table walked]")
		UI.buzz(80)
		_shake(12.0)
		_fx_text(Vector2(field.size.x / 2, _rail_y() + 120), "TABLE WALKED!", UI.key("bad"), 40)
	elif k.walked > walked_before:
		k.walked = walked_before   # god mode: walked tables don't count
		k.critic = critic_before
	for e in k.events:
		if e.begins_with("BURN"):
			get_node("/root/Audio").sfx("burn")
			get_node("/root/Subs").cue("[sizzle: burn]")
			var bs: int = Kitchen.STATIONS.find(e.trim_prefix("BURN ON ").get_slice(",", 0))
			if bs >= 0:
				_fx_burst(station_rect(bs).get_center(), Color("6b6b6b"), 18)
				_fx_text(Vector2(station_rect(bs).get_center().x, station_rect(bs).position.y - 6), "BURNED!", UI.key("bad"))
		elif e.ends_with("WALKED OUT"):
			get_node("/root/Audio").sfx("door")
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


## Service survived: a grade sheet (the moment it lands), then NEXT SERVICE. The checkpoint is
## already the next service, so quitting here loses nothing.
func _service_done() -> void:
	_night_before += k.served
	score = _night_before
	cash += k.tips
	_record_best(level)
	get_node("/root/Audio").sfx("level")
	get_node("/root/Subs").cue("[chime: service %d done]" % level)
	UI.buzz(40)
	_after_move()
	between = true
	_music_heat()   # the busy layer settles behind the grade sheet
	level += 1
	checkpoint()
	var g := k.grade()
	var parts := k.score_parts()
	var read := _house_reads(g)
	_grade_sheet(g, parts, read, {"service": k.service, "served": k.served, "total": k.total, "walked": k.walked, "tips": k.tips})
	_shop_opened = false
	var shop := UI.button("", func(): open_shop())
	shop.name = "ShopButton"
	sheet_box.add_child(shop)
	_shop_label()
	sheet_box.add_child(MenuArt.primary(UI.button("NEXT SERVICE", next_service, 96)))
	sheet_box.add_child(UI.button("TITLE", quit_to_title))   # saved: CONTINUE starts the next service


## The grade sheet's top half: the letter, the night's numbers, the points behind the letter, what's next.
## Kept tight so it fits at HUGE text with walks, the critic and the house's read all showing.
func _grade_sheet(g: String, parts: Dictionary, read: String, st: Dictionary) -> void:
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("SERVICE %d DONE" % st.service, 34, UI.ACCENT))
	var big := 72 if float(_settings.text_scale()) > 1.2 else 96
	var grade := UI.label(g, big, UI.key("good" if g in ["A+", "A", "B"] else ("warn" if g == "C" else "bad")))
	grade.name = "Grade"
	sheet_box.add_child(grade)
	_stamp(grade)
	sheet_box.add_child(UI.label("%d of %d out, %d walk%s\nTips $%d" % [st.served, st.total, st.walked, "" if st.walked == 1 else "s", st.tips], 24))
	var why := UI.label("%d POINTS: out %d, speed %d, pans %d%s%s" % [parts.total, parts.out, parts.speed, parts.pans,
		", walks %d" % parts.walks if parts.walks != 0 else "", ", critic %+d" % parts.critic if parts.critic != 0 else ""] + 
		("\n%s Next: %d tickets." % [read, tickets_for(level)] if read != "" else "  Next: %d tickets." % tickets_for(level)), 18, UI.DIM)
	why.name = "Points"
	sheet_box.add_child(why)


## The grade lands like a stamp: big, then slammed down with a thud and a buzz.
func _stamp(l: Control) -> void:
	if _settings.get_value("low_graphics"):
		return
	l.modulate.a = 0.0   # hidden before the wait, so it never shows at rest first
	await get_tree().process_frame   # laid out first, so the pivot is the letter's centre
	if not is_instance_valid(l):
		return
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(2.6, 2.6)
	l.modulate.a = 0.0
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.12)
	tw.chain().tween_callback(func(): UI.buzz(40))


func _shop_label() -> void:
	var b: Button = sheet_box.get_node_or_null("ShopButton") if sheet_box != null else null
	if b != null:
		var can := Upgrades.ORDER.any(func(id): return Upgrades.can_buy(id, cash, perks))
		b.text = "SHOP ($%d)%s" % [cash, " NEW!" if can and not _shop_opened else ""]   # NEW until you've looked


var _shop_opened := false   # the SHOP button says NEW! until it's opened after a service


## Spend banked tips on upgrades for the rest of tonight. Each one is bought once.
func open_shop() -> void:
	_shop_opened = true
	var box := UI.sheet(self, 500)
	box.add_child(UI.label("KITCHEN SHOP", 30, UI.ACCENT))
	box.add_child(UI.label("Bank: $%d. Upgrades last all night." % cash, 20, UI.DIM))
	var owned: Array[String] = []
	var listed: Array = Upgrades.shown(perks)
	for id in Upgrades.ORDER:
		if perks.has(id) and not listed.has(id):   # owned rows already say OWNED: name only the ones that left the list
			owned.append(String(Upgrades.ALL[id].name))
	if not owned.is_empty():   # a tray upgrades in place, so the one it replaced leaves the list
		var ol := UI.label("ALSO OWNED: " + ", ".join(owned), 18, UI.key("good"))
		ol.name = "Owned"
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(ol)
	for id in Upgrades.shown(perks):
		var u: Dictionary = Upgrades.ALL[id]
		var b: Button
		if perks.has(id):
			b = UI.button("%s: OWNED\n%s" % [u.name, u.says], Callable(), 88)
			b.disabled = true
		else:
			var short := cash < int(u.cost)   # say it in words, not just the disabled colour
			b = UI.button("%s  %s\n%s" % [u.name, ("NEED $%d" if short else "$%d") % u.cost, u.says], func(): buy(id, box), 88)
			b.disabled = not Upgrades.can_buy(id, cash, perks)
		b.name = "Buy_" + id
		b.add_theme_font_size_override("font_size", UI.font_size(20))
		box.add_child(b)
	box.add_child(UI.button("DONE", func(): UI.close_sheet(box)))


func buy(id: String, box: VBoxContainer) -> void:
	var left := Upgrades.buy(id, cash, perks)
	if left < 0:
		return
	cash = left
	get_node("/root/Audio").sfx("level", 1.3)
	get_node("/root/Subs").cue("[register: %s bought]" % Upgrades.ALL[id].name.to_lower())
	UI.buzz(25)
	checkpoint()
	_shop_label()
	UI.close_sheet(box)
	open_shop()


## Best night on this phone (shown on the title): survives GAME OVER and NEW GAME.
func _record_best(services_cleared: int) -> void:
	if get_node("/root/DebugMenu").god_mode:
		return
	if services_cleared > int(_settings.get_value("best_service")) or (services_cleared == int(_settings.get_value("best_service")) and score > int(_settings.get_value("best_tickets"))):
		_settings.set_value("best_service", services_cleared)
		_settings.set_value("best_tickets", score)


func next_service() -> void:
	if not between:
		return
	UI.close_sheet(sheet_box)
	sheet_box = null
	between = false
	_new_service()
	checkpoint()
	_after_move()
	if k.event != "" or new_station() >= 0:
		tonight()


## The station that opens this service (-1 if none): the line grows by service.
func new_station() -> int:
	for i in Kitchen.OPENS.size():
		if Kitchen.OPENS[i] == k.service and Kitchen.OPENS[i] > 1 and not k.all_open:
			return i
	return -1


## The twist card at the top of a service: what's different tonight, one line.
func tonight() -> void:
	var ns := new_station()
	get_node("/root/Subs").clear()   # the twist's own cue, not the last turn's sizzle
	if k.event != "":
		get_node("/root/Subs").cue("[bell: %s]" % Kitchen.EVENTS[k.event][0].to_lower())
	# Its own box, not sheet_box: a pause (back, focus-out) on top swaps sheet_box, and HEARD! must
	# still close this card afterwards.
	var box := UI.sheet(self)
	twist_box = box
	if ns >= 0:   # the line grows: a station opens tonight, with its dishes
		var dishes: Array = Kitchen.DISHES.keys().filter(func(d): return Kitchen.DISHES[d].st == ns)
		var opened := UI.label("NEW STATION: " + Kitchen.STATIONS[ns], 30, UI.ACCENT)
		opened.name = "NewStation"
		box.add_child(opened)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		for tex in [ART_STATIONS[ns]] + dishes.map(func(d): return ART_DISHES[d]):
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(64, 64)
			row.add_child(pic)
		box.add_child(row)
		box.add_child(UI.label("Now on the menu: " + " and ".join(dishes.map(func(d): return d.to_lower())) + ".", 22))
	if k.event != "":
		var ev: Array = Kitchen.EVENTS[k.event]
		box.add_child(UI.label("TONIGHT", 22, UI.DIM))
		var head := UI.label(ev[0], 36, MenuArt.FLAME)
		head.name = "Twist"
		box.add_child(head)
		box.add_child(UI.label(ev[1], 24))
	box.add_child(MenuArt.primary(UI.button("HEARD!", func():
		UI.close_sheet(box)
		twist_box = null, 88)))


func debug_skip_level() -> void:
	if between:   # the grade sheet already banked this service: just move on
		next_service()
		return
	_night_before += k.served
	score = _night_before
	level += 1
	checkpoint()
	_new_service()
	_after_move()


## One bot action through the real screen code, so the juice and sounds fire (the build clip uses it).
## Returns false when it ended the turn instead.
func bot_step() -> bool:
	if paused or over or between:
		return false
	for c in k.crew.size():
		if not k.can_act(c) or (k.crew[c].stress >= k.stress_cap - 2 and k.crew[c].hand.is_empty()):
			continue
		sel = c
		pick_tid = 0
		pick_ix = -1
		var what := k.action_here(c, false)
		if what != "":
			var ap_was: int = k.crew[c].ap
			act()
			if k.crew[c].ap < ap_was:
				return true
			break   # the action didn't take: end the turn rather than retry it forever
		var goal: int = k._bot_goal(c)
		if goal < 0 or goal == k.crew[c].at:
			continue
		var step: int = k.crew[c].at + signi(goal - k.crew[c].at)
		while not k.is_open(step):
			step += signi(goal - k.crew[c].at)
		if k.move(c, step):
			get_node("/root/Audio").sfx("click", 0.9)
			_after_move()
			return true
	end_turn()
	return false


## The autoplay bot's turn: the greedy line cook from kitchen.gd, then END TURN.
func bot_play_turn() -> void:
	k.bot_turn()
	score = _night_before + k.served
	end_turn()


func _after_move() -> void:
	_refresh_hud()
	field.queue_redraw()
	_music_heat()


## The busy layer (sizzles, plates, the hood fan) rises under the jazz as tickets run low.
func _music_heat() -> void:
	var heat := 0.0
	if k != null and not (over or between):
		for t in k.tickets:
			heat = maxf(heat, clampf((5.0 - t.time) / 4.0, 0.0, 1.0))
		heat = maxf(heat, 0.35 * clampf(k.tickets.size() / 4.0, 0.0, 1.0))
	get_node("/root/Audio").set_intensity(heat)


var _coach_t := 0.0


func _process(dt: float) -> void:
	_tick_fx(dt)
	_coach_t += dt
	if _coach_t >= 0.25:
		_coach_t = 0.0
		_coach_next()


## Teach by doing, one hint at a time, in the order a first ticket needs them. Each shows only
## once its moment comes and goes for good once done.
var _coached := {}
const COACH_TURNS := 3   # turns a hint waits for the player before it retires


func _coach_steps() -> Array:
	return [
		["fire", "TAP FIRE TO COOK", func(): return true,
			func(): return k.turn > 0 or k.pans.any(func(p): return not p.is_empty())],
		["end_turn", "TAP END TURN: COOK", func(): return k.pans.any(func(p): return not p.is_empty()),
			func(): return k.turn > 0],
		# Fresh-player review: the action dots over each cook were never noticed. After the first END TURN.
		["dots", "DOTS ARE MOVES LEFT", func(): return k.turn >= 1,
			func(): return k.turn >= 2 or k.crew.any(func(c): return not c.out and c.ap <= 0)],
		["plate", "UP! TAP PLATE", func(): return k.pans.any(func(p): return not p.is_empty() and p.left <= 0),
			func(): return not k.window.is_empty() or k.served > 0],
		["run", "PASS: RUN SERVES IT", func(): return not k.window.is_empty(),
			func(): return k.served > 0],
		["switch", "TAP MO TO SWITCH", func(): return k.served > 0 and not k.crew[1].out,
			func(): return sel != 0 or k.crew[1].out],
		["pick", "TAP TICKET: COOK FIRST", func(): return k.tickets.size() >= 2,
			func(): return pick_tid != 0],
		["rest", "IDLE COOKS LOSE STRESS", func(): return k.crew.any(func(c): return not c.out and c.stress >= k.stress_cap - 3),
			func(): return false],   # nothing to do but read it: it retires after a few turns
		["rush", "RUSH IT: +STRESS", func(): return k.action_here(sel) == "RUSH",
			func(): return k.pans.any(func(p): return p.get("rushed", false))],
	]


func _coach_next() -> void:
	if k == null or paused or over or between or is_instance_valid(twist_box):
		return
	for ch in get_children():
		if ch.name.begins_with("Coach_"):
			# A hint the player hasn't acted on in COACH_TURNS turns retires, so it never parks over
			# the line all night (RUSH IT sat through two services in the blind review).
			if k.turn - int(ch.get_meta("turn", k.turn)) >= COACH_TURNS and ch.has_method("retire"):
				ch.retire()
			return
	for st in _coach_steps():
		if _coached.get(st[0], false):
			continue
		if Coach.seen(st[0]) or st[3].call():
			_coached[st[0]] = true
			continue
		if st[2].call():
			var c := Coach.teach(self, st[0], st[1], st[3])
			if c != null:
				c.set_meta("turn", k.turn)   # in the gap between the NEXT line and the stations, in pixels: a taller
				# phone (web, 9:19.5) stretches the canvas, and a fraction of its height landed on the station names
				c.anchor_top = 0.0
				c.anchor_bottom = 0.0
				c.offset_top = station_rect(0).position.y - 50.0   # the field sits at the origin; fits the gap under the NEXT bar
				c.offset_bottom = c.offset_top + 48.0
		return


# Layout, in field coordinates. Rail on top, the line in the middle, crew under their stations.
## The rail's tickets, most urgent first: the order the cards are drawn in.
func rail_tickets() -> Array:
	var shown: Array = k.tickets.duplicate()
	shown.sort_custom(func(a, b): return a.time < b.time)
	if rail_off >= shown.size():
		rail_off = 0   # the page emptied out: back to the most urgent
	return shown.slice(rail_off) if rail_off > 0 else shown


var rail_off := 0         # first rail card shown: tap the +N MORE badge to page past the first four
var _more_rect := Rect2()  # where that badge was drawn, for the tap


func ticket_rect(i: int) -> Rect2:
	var pad := 10.0
	var cw := (field.size.x - pad * 5.0) / 4.0
	return Rect2(pad + i * (cw + pad), _rail_y(), cw, 200.0)



## The row of ticket card i under point p (the dish list drawn in _draw_field), or -1.
func dish_at(i: int, p: Vector2) -> int:
	var rail := rail_tickets()
	if i >= rail.size():
		return -1
	var r := ticket_rect(i)
	for ix in rail[i].items.size():
		if Rect2(r.position.x, r.position.y + DISH_ROW0 + ix * DISH_ROW, r.size.x, DISH_ROW).has_point(p):
			return ix
	return -1


const DISH_ROW0 := 46.0   # first dish row's top inside a ticket card (its text baseline is 20 lower)
const DISH_ROW := 33.0


func _rail_y() -> float:
	return 30.0 + UI.MIN_TOUCH + 70.0


func station_rect(i: int) -> Rect2:
	var w := field.size.x
	var n := float(Kitchen.STATIONS.size())
	var pad := 8.0
	var bw := (w - pad * (n + 1.0)) / n
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
	if paused or over or between:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		tap(e.position)


## A tap at a point on the field (also used by the autoplay bot).
func tap(p: Vector2) -> void:
	var pf := _pick_from   # only the very next tap can use it
	_pick_from = {}
	if _more_rect.has_area() and _more_rect.has_point(p):   # page the rail
		rail_off = rail_off + 4 if rail_tickets().size() > 4 else 0
		get_node("/root/Audio").sfx("click")
		_after_move()
		return
	var rail := rail_tickets()
	for i in mini(rail.size(), 4):
		if ticket_rect(i).has_point(p):   # pick this table to cook first; tap again to unpick
			# A tap on a waiting dish's row picks that exact dish (Duff, Nov 25: "tap a dish").
			var ix := dish_at(i, p)
			if ix >= 0 and rail[i].items[ix].state == "wait":
				var same: bool = pick_tid == rail[i].id and pick_ix == ix
				pick_tid = 0 if same else rail[i].id
				pick_ix = -1 if same else ix
			else:
				pick_tid = 0 if pick_tid == rail[i].id else rail[i].id
				pick_ix = -1
			get_node("/root/Audio").sfx("click")
			_after_move()
			return
	for c in k.crew.size():
		if not k.crew[c].out and cook_pos(c).distance_to(p) <= COOK_R + 6.0:
			sel = c
			_portrait_pick = true   # the next station tap sends this cook, never swaps to another
			get_node("/root/Audio").sfx("click")
			_after_move()
			return
	var portrait := _portrait_pick
	_portrait_pick = false
	for i in Kitchen.STATIONS.size():
		if station_rect(i).grow(4.0).has_point(p):
			if not k.is_open(i):
				if note != null:
					note.text = "%s OPENS IN SERVICE %d" % [Kitchen.STATIONS[i], Kitchen.OPENS[i]]
				return
			if pf.get("st", -1) == i and int(pf.prev) != sel and not k.crew[int(pf.prev)].out:
				sel = int(pf.prev)   # tapped the same station again: the cook you had picked goes there after all
				var went := k.move(sel, i)
				if went:
					get_node("/root/Audio").sfx("click")
				_after_move()
				if not went:
					_too_far(i)   # after the redraw, so the status line keeps the reason
				return
			if k.crew[sel].at == i:
				act()
				return
			# Tap a station, get its cook (Duff, Nov 25: "tap the station and get the employee that
			# dropped it"): a cook standing there first, else the cook who fired its pan. Only an
			# empty station with nobody's pan on it sends the selected cook over. Tapping the same station
			# again sends the cook you had picked instead (a handoff: MO plates DEV's burger).
			var owner := -1 if portrait else station_cook(i)   # a cook you tapped by face goes where you send them
			if owner >= 0 and owner != sel:
				_pick_from = {"st": i, "prev": sel}
				sel = owner
				get_node("/root/Audio").sfx("click")
				_after_move()
			elif k.move(sel, i):
				get_node("/root/Audio").sfx("click")
				_after_move()
			else:
				_too_far(i)
			return


## A walk that can't happen says why, on the station and in the status line (it used to do nothing).
func _too_far(i: int) -> void:
	var cr: Dictionary = k.crew[sel]
	if cr.out:
		return
	var need: int = k.walk_cost(cr.at, i)
	var why := "%s: NO MOVES LEFT" % cr.name if cr.ap <= 0 else "TOO FAR: %s NEEDS %d MOVES, HAS %d" % [cr.name, need, cr.ap]
	if note != null:
		note.text = why
	var r := station_rect(i)
	_fx_text(Vector2(r.get_center().x, r.position.y - 6), "TOO FAR" if cr.ap > 0 else "NO MOVES", UI.key("bad"), 24)
	get_node("/root/Audio").sfx("click", 0.7)
	UI.buzz(30)
	if field != null:
		field.queue_redraw()


## The cook a tap on station i should pick: one standing there, else the one who fired its pan; -1 if none.
func station_cook(i: int) -> int:
	for c in k.crew.size():
		if not k.crew[c].out and k.crew[c].at == i:
			return c
	if i < k.pans.size() and not k.pans[i].is_empty():
		var by: int = k.pans[i].get("by", -1)
		if by >= 0 and by < k.crew.size() and not k.crew[by].out:
			return by
	return -1


## Draw a texture inside a box, whole, keeping its shape (letterboxed, centred).
func _draw_fit(f: Control, tex: Texture2D, box: Rect2) -> void:
	var sz := tex.get_size()
	var sc := minf(box.size.x / sz.x, box.size.y / sz.y)
	var d := sz * sc
	f.draw_texture_rect(tex, Rect2(box.position + (box.size - d) / 2.0, d), false)


## Draw a texture filling a box, cropped to keep its shape.
func _draw_cover(f: Control, tex: Texture2D, box: Rect2) -> void:
	var sz := tex.get_size()
	var sc := maxf(box.size.x / sz.x, box.size.y / sz.y)
	var src := Rect2((sz - box.size / sc) / 2.0, box.size / sc)
	f.draw_texture_rect_region(tex, box, src)


## Cooks whose stress hits the cap if the turn ends now: the same sums as Kitchen.end_turn (a burn at
## their station +2, a worked cook +1 while a ticket will be red, an idle one rests).
func cooks_quitting() -> Array:
	var out: Array = []
	for c in k.crew.size():
		if not k.crew[c].out and stress_after(c) >= k.stress_cap:
			out.append(k.crew[c].name)
	return out


## Cook c's stress once the turn ends now (the meter shows the change before END TURN is pressed).
func stress_after(c: int) -> int:
	var cr: Dictionary = k.crew[c]
	var red := k.tickets.any(func(t): return t.time - 1 > 0 and t.time - 1 <= 2)
	var s: int = cr.stress
	for i in k.pans.size():
		var p: Dictionary = k.pans[i]
		if not p.is_empty() and p.left <= 0 and p.sat >= k.burn_after and cr.at == i:
			s += 2
	return s + (1 if red else 0) if cr.acted else maxi(0, s - 2)


## The NEXT bar in plain words ("NEXT: 2 dishes in 3 min"), as many as fit the width.
func next_line(font: Font, width: float) -> String:
	var pv: Array = k.preview(3)
	if pv.is_empty():
		return "NEXT: no more tickets"
	var parts: Array[String] = []
	for v in pv:
		var n: int = v.ticket.items.size()
		var what := "BIG table" if v.ticket.big else ("1 dish" if n == 1 else "%d dishes" % n)
		parts.append("%s in %d min" % [what, v["in"]])
	for cnt in range(parts.size(), 0, -1):
		var line := "NEXT: " + ", ".join(parts.slice(0, cnt))
		if cnt == 1 or font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(18)).x <= width:
			return line
	return ""


## A dark plate behind text that sits on art.
## The long label if it fits the width at this text size, else the short one.
func _fit(font: Font, long: String, short: String, width: float, size: int) -> String:
	return long if font.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(size)).x <= width else short


func _plate(f: Control, box: Rect2) -> void:
	f.draw_rect(box, Color(0, 0, 0, 0.62))


func _draw_field(f: Control) -> void:
	f.draw_rect(Rect2(Vector2.ZERO, f.size), UI.BG)
	_draw_cover(f, ART_BG, Rect2(Vector2.ZERO, f.size))
	f.draw_rect(Rect2(Vector2.ZERO, f.size), Color(UI.BG, 0.55))   # keeps text and pieces on top readable
	var font := ThemeDB.fallback_font
	var low: bool = _settings.get_value("low_graphics")
	var ink := UI.ink()
	# --- the rail: tickets on now, then what's coming next
	var y0 := _rail_y()
	var shown: Array = rail_tickets()
	var pad := 10.0
	for i in mini(shown.size(), 4):
		var t: Dictionary = shown[i]
		var r := ticket_rect(i)
		var tone := "good" if t.time > 4 else ("warn" if t.time > 2 else "bad")
		f.draw_rect(r, UI.panel_color())
		f.draw_rect(r, UI.key(tone), false, 4.0 if tone == "bad" else 2.0)
		if tone == "bad" and not (paused or over or between) and not _settings.get_value("low_graphics"):   # about to walk: the frame throbs
			var throb := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
			f.draw_rect(r.grow(3.0 + 3.0 * throb), Color(UI.key("bad"), 0.5 * throb), false, 3.0)
		if t.id == pick_tid:   # picked: a thick accent frame plus a tab on the bottom (shape, not colour alone)
			f.draw_rect(r.grow(4.0), UI.ACCENT, false, 4.0)
			f.draw_rect(Rect2(r.position.x, r.end.y - 26, r.size.x, 26), UI.ACCENT)
			f.draw_string(font, Vector2(r.position.x, r.end.y - 7), "COOK FIRST", HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(13), UI.BG)
		f.draw_string(font, r.position + Vector2(8, 26), "T%d" % t.table,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56, UI.font_size(18), ink)
		if t.big:   # small, between the table number and the clock, so it never runs into either
			f.draw_string(font, r.position + Vector2(46, 25), "BIG", HORIZONTAL_ALIGNMENT_LEFT, 28, UI.font_size(11), UI.key("warn"))
		for tag in ["vip", "critic"]:   # tonight's twist: a word band on the bottom plus a doubled frame
			if t.get(tag, false):
				f.draw_rect(r.grow(-6.0), MenuArt.FLAME, false, 2.0)
			if t.get(tag, false) and t.id != pick_tid:   # picked: the COOK FIRST tab wins the band
				f.draw_rect(Rect2(r.position.x, r.end.y - 26, r.size.x, 26), MenuArt.FLAME)
				f.draw_string(font, Vector2(r.position.x, r.end.y - 7), tag.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
					UI.font_size(13), MenuArt.PAPER_INK)
		# Clock: number plus a shape cue (filled bars), not colour alone.
		f.draw_string(font, r.position + Vector2(r.size.x - 44, 28), "%d'" % t.time,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(24), UI.key(tone))
		for b in mini(t.time, 10):
			f.draw_rect(Rect2(r.position.x + 8 + b * ((r.size.x - 16) / 10.0), r.position.y + 36, (r.size.x - 16) / 10.0 - 2, 6), UI.key(tone))
		var iy := r.position.y + DISH_ROW0 + 20.0
		for n in t.items.size():
			var it: Dictionary = t.items[n]
			if t.id == pick_tid and n == pick_ix:   # the tapped dish: an accent bar and a pointer, not colour alone
				f.draw_rect(Rect2(r.position.x + 3, iy - 20, r.size.x - 6, DISH_ROW - 2), Color(UI.ACCENT, 0.25))
				f.draw_rect(Rect2(r.position.x + 3, iy - 20, 4, DISH_ROW - 2), UI.ACCENT)
			var col: Color = UI.DIM if it.state == "served" else ink
			f.draw_string(font, Vector2(r.position.x + 8, iy), it.dish, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, UI.font_size(16), col)
			if it.state == "served":   # struck through: done, in shape as well as colour
				var dw := minf(font.get_string_size(it.dish, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(16)).x, r.size.x - 12)
				f.draw_line(Vector2(r.position.x + 8, iy - 6), Vector2(r.position.x + 8 + dw, iy - 6), UI.DIM, 2.0)
			# Its state in words on a small line under it (no symbol to learn): where it cooks while it waits.
			var sub: String = {"wait": "at " + Kitchen.station_of(it.dish), "cooking": "cooking", "carried": "on the pass", "served": "served"}[it.state]
			var sc: Color = UI.key("warn") if it.state == "wait" else (UI.key("info") if it.state != "served" else UI.DIM)
			f.draw_string(font, Vector2(r.position.x + 8, iy + 14), sub,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, UI.font_size(14), sc)
			iy += DISH_ROW
	_plate(f, Rect2(pad - 6, y0 + 218, f.size.x - 2 * pad + 12, 30))
	var more_w := 0.0
	_more_rect = Rect2()
	if shown.size() > 4 or rail_off > 0:   # a tappable badge: page on to the hidden tickets, or back to the first ones
		var all_t: Array = k.tickets.duplicate()
		all_t.sort_custom(func(a, b): return a.time < b.time)
		var hid: Array = shown.slice(4) if shown.size() > 4 else all_t.slice(0, rail_off)
		var hot := hid.any(func(t): return t.time <= 2)   # red when a ticket off screen is about to walk
		var mt := ("+%d MORE" % hid.size()) if shown.size() > 4 else "BACK"
		if hot:
			mt += "!"   # hot: a "!" as well as red
		more_w = font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(16)).x + 16
		var mr := Rect2(f.size.x - pad - more_w, y0 + 220, more_w, 26)
		f.draw_rect(mr, UI.key("bad") if hot else UI.key("warn"))
		_more_rect = mr.grow(8.0)   # a bit of slack for a thumb
		f.draw_string(font, mr.position + Vector2(0, 19), mt, HORIZONTAL_ALIGNMENT_CENTER, more_w, UI.font_size(16), UI.BG)
	_plate(f, Rect2(pad - 6, y0 - 36, f.size.x - 2 * pad + 12, 30))   # busy kitchen wall behind: text sits on plates
	f.draw_string(font, Vector2(pad, y0 - 14), "OUT %d   WALKED %d/%d   TIPS $%d" % [k.served, k.walked, lives_max, k.tips],
		HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20, UI.font_size(18), UI.key("bad") if k.walked >= lives_max - 1 else ink)
	f.draw_string(font, Vector2(pad, y0 + 240), next_line(font, f.size.x - 20 - more_w), HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20 - more_w, UI.font_size(18), ink)
	# --- the line
	for i in Kitchen.STATIONS.size():
		var r := station_rect(i)
		var here: bool = k.crew[sel].at == i
		if not k.is_open(i):   # not open yet tonight: dimmed, with when it opens (word, not colour alone)
			f.draw_rect(r, Color(UI.panel_color(), 0.6))
			f.draw_rect(r, Color("4a5878"), false, 2.0)
			_draw_fit(f, ART_STATIONS[i], Rect2(r.position + Vector2(6, 40), r.size - Vector2(12, 46)))
			f.draw_rect(r.grow(-2.0), Color(UI.BG, 0.72))
			f.draw_string(font, r.position + Vector2(0, 30), Kitchen.STATIONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(16), UI.DIM)
			_plate(f, Rect2(r.position.x + 2, r.get_center().y - 24, r.size.x - 4, 52))
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, -4), "CLOSED", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(14), ink)
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 18), "SERVICE %d" % Kitchen.OPENS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(12), UI.DIM)
			continue
		f.draw_rect(r, UI.panel_color())
		f.draw_rect(r, UI.ACCENT if here else Color("4a5878"), false, 3.0 if here else 2.0)
		_draw_fit(f, ART_STATIONS[i], Rect2(r.position + Vector2(6, 40), r.size - Vector2(12, 46)))
		f.draw_string(font, r.position + Vector2(0, 30), Kitchen.STATIONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(16), ink)
		if i < k.pans.size() and not k.pans[i].is_empty():
			var p: Dictionary = k.pans[i]
			var up: bool = p.left <= 0
			var burning: bool = up and p.sat >= k.burn_after
			var tone := ("bad" if burning else "warn") if up else "info"
			if not low and up:
				f.draw_circle(r.get_center() + Vector2(0, 20), 46.0, Color(UI.key(tone), 0.2))
			var pc := r.get_center() + Vector2(0, 8)
			f.draw_circle(pc, 36.0, Color(0.08, 0.09, 0.12, 0.85))
			f.draw_arc(pc, 36.0, 0.0, TAU, 40, UI.key(tone), 9.0 if burning else 5.0)   # thick ring the turn before it burns
			_draw_fit(f, ART_DISHES[p.dish], Rect2(pc - Vector2(28, 28), Vector2(56, 56)))
			var by: int = p.get("by", -1)
			if by >= 0 and by < k.crew.size() and not k.crew[by].out:   # whose pan: the cook's initial, ringed when they're selected
				var bc := pc + Vector2(-30, -30)
				f.draw_circle(bc, 13.0, Color(0.08, 0.09, 0.12, 0.95))
				f.draw_arc(bc, 13.0, 0.0, TAU, 24, UI.ACCENT if by == sel else ink, 3.0 if by == sel else 1.5)
				f.draw_string(font, bc + Vector2(-13, 6), String(k.crew[by].name).left(1), HORIZONTAL_ALIGNMENT_CENTER, 26,
					UI.font_size(14), UI.ACCENT if by == sel else ink)
			# State in words, not colour alone: 2' cooking, UP! ready, PLATE NOW: burns at the next END TURN.
			_plate(f, Rect2(r.position.x + 4, r.end.y - 38, r.size.x - 8, 30))
			var st := ("PLATE NOW" if burning else "UP!") if up else "%d'" % p.left
			# Smaller text before cutting words (stress pass: "BURGER UP!" read just "UP!"); the state
			# always wins over the dish name, since the art says which dish.
			var lbl := "%s %s" % [p.dish, st]
			var fs := 15
			for cand in ([st, "PLATE!"] if burning else [lbl, st]):
				lbl = cand
				fs = 15
				while fs > 11 and font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(fs)).x > r.size.x - 8:
					fs -= 1
				if font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(fs)).x <= r.size.x - 8:
					break
			f.draw_string(font, r.position + Vector2(0, r.size.y - 16), lbl,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(fs), UI.key(tone))
		elif i < k.pans.size():
			var waiting := 0
			for t in k.tickets:
				for it in t.items:
					if it.state == "wait" and Kitchen.DISHES[it.dish].st == i:
						waiting += 1
			if waiting > 0:   # work waiting here: what to FIRE, and how much
				_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
				f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), _fit(font, "%d TO FIRE" % waiting, "FIRE %d" % waiting, r.size.x - 8, 17),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(17), UI.key("warn"))
		elif i == Kitchen.PASS_IX:
			for w in mini(k.window.size(), 3):   # plates up on the window, waiting for a runner
				_draw_fit(f, ART_DISHES[k.window[w].dish], Rect2(r.position.x + 4 + w * 28, r.position.y + 34, 34, 34))
			_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
			var up := _fit(font, "%d TO RUN" % k.window.size(), "RUN %d" % k.window.size(), r.size.x - 8, 15) if not k.window.is_empty() else _fit(font, "RUN HERE", "RUN", r.size.x - 8, 15)
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), up, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(15), UI.key("good") if not k.window.is_empty() else ink)
	# Walk costs (movement pass, build-73 reviews: walking ate turns unseen): with a cook picked,
	# every other open station says what getting there costs, or TOO FAR.
	if not k.crew[sel].out and not k.done and k.crew[sel].ap > 0:   # spent: the button already says NO MOVES
		var me: Dictionary = k.crew[sel]
		for i in Kitchen.STATIONS.size():
			if i == me.at or not k.is_open(i):
				continue
			var r := station_rect(i)
			var cost: int = k.walk_cost(me.at, i)
			var far: bool = cost > me.ap
			var wl := "TOO FAR" if far else "WALK %d" % cost
			wl = _fit(font, wl, "FAR" if far else "W%d" % cost, r.size.x - 12, 13)
			var chip := Rect2(r.position.x + 6, r.position.y + 36, r.size.x - 12, 18)
			f.draw_rect(chip, Color(0, 0, 0, 0.7))
			f.draw_string(font, chip.position + Vector2(0, 14), wl, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x,
				UI.font_size(13), UI.key("bad") if far else UI.key("info"))
	# --- crew
	for c in k.crew.size():
		var cr: Dictionary = k.crew[c]
		var pos := cook_pos(c)
		if cr.out:   # an empty spot where they stood: name + QUIT, right where you'd look for them
			if k.crew.any(func(o): return not o.out and cook_pos(k.crew.find(o)).distance_to(pos) < COOK_R * 2.0):
				continue   # a working cook stands here now: never cover them (blind review #3)
			f.draw_circle(pos, COOK_R, Color(0.08, 0.09, 0.12, 0.85))
			f.draw_arc(pos, COOK_R, 0.0, TAU, 32, UI.key("bad"), 2.0)
			f.draw_string(font, pos + Vector2(-COOK_R - 20, -2), cr.name, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2 + 40, UI.font_size(15), UI.DIM)
			f.draw_string(font, pos + Vector2(-COOK_R - 20, 16), "QUIT", HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2 + 40, UI.font_size(15), UI.key("bad"))
			continue
		if c == sel:
			f.draw_circle(pos, COOK_R + 7.0, UI.ACCENT)
		f.draw_circle(pos, COOK_R, Color("2b3448"))
		if ART_COOKS.has(cr.name):
			f.draw_texture_rect(ART_COOKS[cr.name], Rect2(pos - Vector2(COOK_R, COOK_R), Vector2(COOK_R, COOK_R) * 2.0), false)
			_plate(f, Rect2(pos.x - 26, pos.y + COOK_R - 22, 52, 22))
			f.draw_string(font, pos + Vector2(-COOK_R, COOK_R - 5), cr.name, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2, UI.font_size(15), ink)
		else:
			f.draw_string(font, pos + Vector2(-COOK_R, 7), cr.name, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2, UI.font_size(18), ink)
		for a in cr.ap:   # action pips
			f.draw_circle(pos + Vector2(-16 + a * 16, -COOK_R - 12), 6.0, UI.key("info"))
		# Stress: one box per point up to the cap (full = they quit), and the count in words under it.
		# Blind review #3: the thin bar went unseen, and stress is what loses most first nights.
		var cap: int = maxi(1, k.stress_cap)
		var sw := 76.0
		var seg := sw / cap
		var tired: bool = cr.stress >= k.stress_cap - 2
		var tone := "bad" if tired else ("warn" if cr.stress > 0 else "good")
		# Stress pass: what END TURN will do, before it's pressed. Boxes it adds are outlined red,
		# boxes a rest takes off are outlined green.
		var after := stress_after(c)
		for b in cap:
			var box := Rect2(pos.x - sw / 2 + b * seg, pos.y + COOK_R + 6, seg - 2, 10)
			f.draw_rect(box, UI.key(tone) if b < cr.stress else Color("2b3448"))   # real stress stays filled; a rest only outlines
			if b >= cr.stress and b < after:
				f.draw_rect(box, UI.key("bad"), false, 2.0)
			elif b >= after and b < cr.stress:
				f.draw_rect(box, UI.key("good"), false, 2.0)
		if cr.hand.is_empty() and (note == null or note.text == ""):   # (a carried plate's name, or the event line, sits here instead)
			# As wide as the gap to the next cook allows: two plates side by side ran together.
			var pw := 100.0
			for o in k.crew.size():
				if o != c and not k.crew[o].out:
					pw = minf(pw, absf(cook_pos(o).x - pos.x) - 6.0 if absf(cook_pos(o).y - pos.y) < 60.0 else pw)
			pw = maxf(pw, 44.0)
			var dl := "" if after == cr.stress else (" %+d" % (after - cr.stress))
			var sl := ("TIRED %d/%d" if tired else "STRESS %d/%d") % [cr.stress, cap] + dl
			sl = _fit(font, sl, "%d/%d%s" % [cr.stress, cap, dl], pw - 4, 14)
			_plate(f, Rect2(pos.x - pw / 2, pos.y + COOK_R + 18, pw, 22))
			f.draw_string(font, Vector2(pos.x - pw / 2, pos.y + COOK_R + 35), sl, HORIZONTAL_ALIGNMENT_CENTER, pw,
				UI.font_size(14), UI.key("bad") if after > cr.stress else (UI.key(tone) if cr.stress > 0 else ink))
		if not cr.hand.is_empty():   # the plate in hand, on the cook's shoulder, plus its name
			_draw_fit(f, ART_DISHES[cr.hand.dish], Rect2(pos + Vector2(COOK_R - 18, -COOK_R - 6), Vector2(40, 40)))
			_plate(f, Rect2(pos + Vector2(-50, COOK_R + 22), Vector2(100, 24)))
			f.draw_string(font, pos + Vector2(-60, COOK_R + 40), "> " + cr.hand.dish, HORIZONTAL_ALIGNMENT_CENTER, 120, UI.font_size(15), UI.key("good"))
	_draw_fx(f)


# ---------------------------------------------------------------- pause + game over

func pause() -> void:
	if between:
		checkpoint()   # the next service is already the checkpoint; the grade sheet stays up
		return
	if paused or over:
		return
	paused = true
	if field != null:
		field.queue_redraw()   # drop the red-ticket throb ring under the pause sheet
	checkpoint()
	get_node("/root/Subs").clear()
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("PAUSED", 30, UI.ACCENT))
	if k.event != "":
		sheet_box.add_child(UI.label("TONIGHT: " + Kitchen.EVENTS[k.event][0], 20, UI.DIM))
	sheet_box.add_child(MenuArt.primary(UI.button("RESUME", resume, 88)))
	sheet_box.add_child(UI.button("HOW TO PLAY", func(): HowToPlay.open(self)))
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
	get_node("/root/Loader").go("res://scenes/title.tscn")


func game_over() -> void:
	over = true
	_save.clear()
	_record_best(level - 1)
	_house_reads("F", true)   # a lost night eases the next one a little
	_after_move()   # the board behind the sheet shows the turn that lost it
	get_node("/root/Audio").sfx("gameover")
	get_node("/root/Subs").cue("[game over sting]")
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("GAME OVER", 40, UI.key("bad")))
	var why := "THE WHOLE LINE WALKED OUT" if k.crew.all(func(c): return c.out) else "TOO MANY TABLES WALKED"
	var reason := UI.label(why, 26, UI.key("bad"))
	reason.name = "Reason"
	sheet_box.add_child(reason)
	sheet_box.add_child(UI.label("Service %d, %d tickets out tonight" % [level, score], 22))
	var fresh := UI.label("A new night starts back at service 1.", 20, UI.DIM)   # say it: the lost night's progress is gone
	fresh.name = "Fresh"
	sheet_box.add_child(fresh)
	var again := MenuArt.primary(UI.button("NEW NIGHT", func(): get_node("/root/Loader").go("res://scenes/game.tscn"), 88))
	var title := UI.button("TITLE", quit_to_title)
	sheet_box.add_child(again)
	sheet_box.add_child(title)
	for b in [again, title]:   # a tap meant for the board doesn't restart the night: a beat before they work
		b.disabled = true
		get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(b): b.disabled = false)


func _notification(what: int) -> void:
	match what:
		# The phone took the app away (call, home button, notification shade): pause + save.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			pause.call_deferred()
		# Android back / back gesture: close the top sheet, else pause. Never quits.
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_go_back.call_deferred()


func _go_back() -> void:
	# Only this screen's sheets: autoload sheets (DEV MENU) come first in tree order and handle
	# their own back. A sheet on top of the pause / grade / game over sheet closes first.
	var sheets: Array = get_tree().get_nodes_in_group("sheet").filter(func(n): return n.get_parent() == self and not n.is_queued_for_deletion())
	var top: Node = sheets[-1] if sheets.size() > 0 else null
	if paused and top != null and is_instance_valid(sheet_box) and top == sheet_box.get_meta("sheet"):
		resume()   # back on the pause sheet = RESUME, even with the TONIGHT card under it
	elif not paused and top != null and is_instance_valid(twist_box) and top == twist_box.get_meta("sheet"):
		UI.close_sheet(twist_box)   # back on the TONIGHT card = HEARD!
		twist_box = null
	elif sheets.size() > 1:
		sheets[-1].queue_free()
	elif between:
		next_service()
	elif over:
		quit_to_title()
	elif paused:
		resume()
	else:
		pause()


func _exit_tree() -> void:
	var subs := get_node_or_null("/root/Subs")
	if subs != null:
		subs.lift = 0.0   # other screens keep the default caption spot
