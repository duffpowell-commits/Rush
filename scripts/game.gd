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
	get_node("/root/Audio").music("music_loop")


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
	var a := k.action_here(sel)
	act_btn.text = a if a != "" else "NOTHING HERE"
	if a == "FIRE":   # say which table it cooks for, picked or not
		var fp := k.fire_pick(sel, pick_tid)
		act_btn.text = "FIRE T%d" % fp.t.table
	elif a == "RUSH":   # warn when this rush would send the cook over the edge
		var cr: Dictionary = k.crew[sel]
		# end of turn also adds 1 to a working cook while any ticket will be red (2 minutes or less)
		var red := 1 if k.tickets.any(func(t): return t.time - 1 > 0 and t.time - 1 <= 2) else 0
		act_btn.text = "RUSH: QUITS!" if cr.stress + k.rush_stress + red >= k.stress_cap else "RUSH +STRESS"
	act_btn.disabled = a == ""
	if note != null:
		note.text = "  ".join(k.events)


# ---------------------------------------------------------------- PLAY

func _new_service() -> void:
	k = Kitchen.new()
	var u := Upgrades.apply({"ticket_time": int(ticket_time), "stress_cap": int(stress_cap),
		"rush_stress": int(rush_stress), "lives": LIVES}, perks)
	k.ticket_time = u.ticket_time
	k.ap = int(crew_ap)
	k.stress_cap = u.stress_cap
	k.turns = int(service_turns)
	k.first_tickets = int(first_tickets)
	k.more_tickets = int(more_tickets)
	k.rush_stress = u.rush_stress
	k.start(level, rng.randi() if level > 1 else 0)
	lives_max = u.lives
	lives = lives_max
	sel = 0
	pick_tid = 0


## Selected cook acts where they stand (the big button, or tapping their own station).
func act() -> void:
	if paused or over or between:
		return
	var what := k.action_here(sel)
	if k.act_here(sel, pick_tid):
		get_node("/root/Audio").sfx("good", {"FIRE": 0.9, "PLATE": 1.0, "RUN": 1.15}.get(what, 1.0))
		if what == "RUSH":
			get_node("/root/Subs").cue("[sizzle: rushed]")
		UI.buzz(15)
		if what == "RUN":
			score = k.served + _night_before
	_after_move()


## One minute of service passes.
func end_turn() -> void:
	if paused or over or between:
		return
	var walked_before := k.walked
	var critic_before := k.critic
	k.end_turn()
	if k.walked > walked_before and not get_node("/root/DebugMenu").god_mode:
		lives = lives_max - k.walked
		get_node("/root/Audio").sfx("bad")
		get_node("/root/Subs").cue("[buzz: table walked]")
		UI.buzz(80)
	elif k.walked > walked_before:
		k.walked = walked_before   # god mode: walked tables don't count
		k.critic = critic_before
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
	level += 1
	checkpoint()
	var g := k.grade()
	sheet_box = UI.sheet(self)
	sheet_box.add_child(UI.label("SERVICE %d DONE" % k.service, 34, UI.ACCENT))
	var grade := UI.label(g, 96, UI.key("good" if g in ["A", "B"] else ("warn" if g == "C" else "bad")))
	grade.name = "Grade"
	sheet_box.add_child(grade)
	sheet_box.add_child(UI.label("%d of %d tickets out\n%d walk%s against you\nTips $%d" % [k.served, k.total, k.walked, "" if k.walked == 1 else "s", k.tips], 24))
	sheet_box.add_child(UI.label("Next: %d tickets." % maxi(1, int(first_tickets) + int(more_tickets) * (level - 1)), 20, UI.DIM))
	var shop := UI.button("", func(): open_shop())
	shop.name = "ShopButton"
	sheet_box.add_child(shop)
	_shop_label()
	sheet_box.add_child(MenuArt.primary(UI.button("NEXT SERVICE", next_service, 96)))
	sheet_box.add_child(UI.button("TITLE", quit_to_title))   # saved: CONTINUE starts the next service


func _shop_label() -> void:
	var b: Button = sheet_box.get_node_or_null("ShopButton") if sheet_box != null else null
	if b != null:
		var can := Upgrades.ORDER.any(func(id): return Upgrades.can_buy(id, cash, perks))
		b.text = "SHOP ($%d)%s" % [cash, " NEW!" if can else ""]


## Spend banked tips on upgrades for the rest of tonight. Each one is bought once.
func open_shop() -> void:
	var box := UI.sheet(self, 500)
	box.add_child(UI.label("KITCHEN SHOP", 30, UI.ACCENT))
	box.add_child(UI.label("Bank: $%d. Upgrades last all night." % cash, 20, UI.DIM))
	for id in Upgrades.ORDER:
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
			pic.custom_minimum_size = Vector2(80, 80)
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


## The autoplay bot's turn: the greedy line cook from kitchen.gd, then END TURN.
func bot_play_turn() -> void:
	k.bot_turn()
	score = _night_before + k.served
	end_turn()


func _after_move() -> void:
	_refresh_hud()
	field.queue_redraw()


var _coach_t := 0.0


func _process(dt: float) -> void:
	_coach_t += dt
	if _coach_t >= 0.25:
		_coach_t = 0.0
		_coach_next()


## Teach by doing, one hint at a time, in the order a first ticket needs them. Each shows only
## once its moment comes and goes for good once done.
var _coached := {}


func _coach_steps() -> Array:
	return [
		["fire", "TAP GRILL TO FIRE", func(): return true,
			func(): return k.turn > 0 or k.pans.any(func(p): return not p.is_empty())],
		["end_turn", "TAP END TURN: COOK", func(): return k.pans.any(func(p): return not p.is_empty()),
			func(): return k.turn > 0],
		["plate", "UP! TAP PLATE", func(): return k.pans.any(func(p): return not p.is_empty() and p.left <= 0),
			func(): return not k.window.is_empty() or k.served > 0],
		["run", "TAP PASS, THEN RUN", func(): return not k.window.is_empty(),
			func(): return k.served > 0],
		["switch", "TAP MO TO SWITCH", func(): return k.served > 0 and not k.crew[1].out,
			func(): return sel != 0 or k.crew[1].out],
		["pick", "TAP TICKET: COOK FIRST", func(): return k.tickets.size() >= 2,
			func(): return pick_tid != 0],
		["rush", "RUSH IT: +STRESS", func(): return k.action_here(sel) == "RUSH",
			func(): return k.pans.any(func(p): return p.get("rushed", false))],
	]


func _coach_next() -> void:
	if k == null or paused or over or between or is_instance_valid(twist_box):
		return
	for ch in get_children():
		if ch.name.begins_with("Coach_"):
			return
	for st in _coach_steps():
		if _coached.get(st[0], false):
			continue
		if Coach.seen(st[0]) or st[3].call():
			_coached[st[0]] = true
			continue
		if st[2].call():
			var c := Coach.teach(self, st[0], st[1], st[3])
			if c != null:   # just under the rail, clear of the NEXT line and the line itself
				c.anchor_top = 0.455
				c.anchor_bottom = 0.455
		return


# Layout, in field coordinates. Rail on top, the line in the middle, crew under their stations.
## The rail's tickets, most urgent first: the order the cards are drawn in.
func rail_tickets() -> Array:
	var shown: Array = k.tickets.duplicate()
	shown.sort_custom(func(a, b): return a.time < b.time)
	return shown


func ticket_rect(i: int) -> Rect2:
	var pad := 10.0
	var cw := (field.size.x - pad * 5.0) / 4.0
	return Rect2(pad + i * (cw + pad), _rail_y(), cw, 200.0)



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
	var rail := rail_tickets()
	for i in mini(rail.size(), 4):
		if ticket_rect(i).has_point(p):   # pick this table to cook first; tap again to unpick
			pick_tid = 0 if pick_tid == rail[i].id else rail[i].id
			get_node("/root/Audio").sfx("click")
			_after_move()
			return
	for c in k.crew.size():
		if not k.crew[c].out and cook_pos(c).distance_to(p) <= COOK_R + 6.0:
			sel = c
			get_node("/root/Audio").sfx("click")
			_after_move()
			return
	for i in Kitchen.STATIONS.size():
		if station_rect(i).grow(4.0).has_point(p):
			if not k.is_open(i):
				if note != null:
					note.text = "%s OPENS IN SERVICE %d" % [Kitchen.STATIONS[i], Kitchen.OPENS[i]]
				return
			if k.crew[sel].at == i:
				act()
			elif k.move(sel, i):
				get_node("/root/Audio").sfx("click")
				_after_move()
			return


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
		var iy := r.position.y + 66
		for it in t.items:
			var mark: String = {"wait": "  ", "cooking": "~ ", "carried": "> ", "served": "V "}[it.state]
			var col: Color = UI.DIM if it.state == "served" else ink
			f.draw_string(font, Vector2(r.position.x + 8, iy), mark + it.dish, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, UI.font_size(16), col)
			if it.state == "wait":   # where it cooks, on its own small line: routing is on the ticket
				f.draw_string(font, Vector2(r.position.x + 8, iy + 14), "  at " + Kitchen.station_of(it.dish),
					HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, UI.font_size(11), UI.DIM)
			iy += 33
	_plate(f, Rect2(pad - 6, y0 + 218, f.size.x - 2 * pad + 12, 30))
	if shown.size() > 4:
		f.draw_string(font, Vector2(f.size.x - 70, y0 + 222), "+%d" % (shown.size() - 4), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(20), UI.key("warn"))
	_plate(f, Rect2(pad - 6, y0 - 36, f.size.x - 2 * pad + 12, 30))   # busy kitchen wall behind: text sits on plates
	f.draw_string(font, Vector2(pad, y0 - 14), "OUT %d   WALKED %d/%d   TIPS $%d" % [score, k.walked, lives_max, k.tips],
		HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20, UI.font_size(18), UI.key("bad") if k.walked >= lives_max - 1 else ink)
	var nx := "NEXT: "
	for pv in k.preview(3):
		nx += "%d' %s   " % [pv["in"], ("BIG" if pv.ticket.big else "%d dish" % pv.ticket.items.size())]
	if k.preview(1).is_empty():
		nx += "last tickets"
	f.draw_string(font, Vector2(pad, y0 + 240), nx, HORIZONTAL_ALIGNMENT_LEFT, f.size.x - 20, UI.font_size(18), ink)
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
			# State in words, not colour alone: 2' cooking, UP! ready, BURN! about to burn.
			_plate(f, Rect2(r.position.x + 4, r.end.y - 38, r.size.x - 8, 30))
			var st := ("BURN!" if burning else "UP!") if up else "%d'" % p.left
			var lbl := "%s %s" % [p.dish, st]
			if font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.font_size(15)).x > r.size.x - 14:
				lbl = st   # big text sizes: the state wins, the dish art still says which dish
			f.draw_string(font, r.position + Vector2(0, r.size.y - 16), lbl,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(15), UI.key(tone))
		elif i < k.pans.size():
			var waiting := 0
			for t in k.tickets:
				for it in t.items:
					if it.state == "wait" and Kitchen.DISHES[it.dish].st == i:
						waiting += 1
			if waiting > 0:   # work waiting here: what to FIRE, and how much
				_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
				f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), _fit(font, "%d TO FIRE" % waiting, "FIRE %d" % waiting, r.size.x - 8, 15),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(15), UI.key("warn"))
		elif i == Kitchen.PASS_IX:
			for w in mini(k.window.size(), 3):   # plates up on the window, waiting for a runner
				_draw_fit(f, ART_DISHES[k.window[w].dish], Rect2(r.position.x + 4 + w * 28, r.position.y + 34, 34, 34))
			_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
			var up := _fit(font, "%d TO RUN" % k.window.size(), "RUN %d" % k.window.size(), r.size.x - 8, 15) if not k.window.is_empty() else _fit(font, "RUN HERE", "RUN", r.size.x - 8, 15)
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), up, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(15), UI.key("good") if not k.window.is_empty() else ink)
	# --- crew
	for c in k.crew.size():
		var cr: Dictionary = k.crew[c]
		if cr.out:
			continue
		var pos := cook_pos(c)
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
		var sw := 64.0
		var frac := float(cr.stress) / k.stress_cap
		f.draw_rect(Rect2(pos.x - sw / 2, pos.y + COOK_R + 8, sw, 8), Color("2b3448"))
		f.draw_rect(Rect2(pos.x - sw / 2, pos.y + COOK_R + 8, sw * frac, 8), UI.key("bad" if frac >= 0.6 else "warn"))
		if not cr.hand.is_empty():   # the plate in hand, on the cook's shoulder, plus its name
			_draw_fit(f, ART_DISHES[cr.hand.dish], Rect2(pos + Vector2(COOK_R - 18, -COOK_R - 6), Vector2(40, 40)))
			_plate(f, Rect2(pos + Vector2(-50, COOK_R + 22), Vector2(100, 24)))
			f.draw_string(font, pos + Vector2(-60, COOK_R + 40), "> " + cr.hand.dish, HORIZONTAL_ALIGNMENT_CENTER, 120, UI.font_size(15), UI.key("good"))
	var gone: Array = k.crew.filter(func(cr): return cr.out).map(func(cr): return cr.name)
	if not gone.is_empty():
		_plate(f, Rect2(20, station_rect(0).end.y + 138, f.size.x - 40, 30))
		f.draw_string(font, Vector2(0, station_rect(0).end.y + 160), "WALKED OUT: " + ", ".join(gone), HORIZONTAL_ALIGNMENT_CENTER, f.size.x, UI.font_size(18), UI.key("bad"))


# ---------------------------------------------------------------- pause + game over

func pause() -> void:
	if between:
		checkpoint()   # the next service is already the checkpoint; the grade sheet stays up
		return
	if paused or over:
		return
	paused = true
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
	sheet_box.add_child(MenuArt.primary(UI.button("TRY AGAIN", func(): get_node("/root/Loader").go("res://scenes/game.tscn"), 88)))
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
