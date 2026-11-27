extends Control
## Rush: a dinner service played turn by turn. Rules live in scripts/kitchen.gd; this draws them
## and turns taps into moves.
##   Tap a cook to pick them. Tap a station to walk there (1 action per station). Use the big button to FIRE / PLATE / RUN. END TURN = one minute passes.
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
const ART_FOX := preload("res://assets/art/fox_cameo.png")   # the studio logo's fox head (Duff picked it, Nov 26)
const ART_STATIONS := [preload("res://assets/art/station_grill.png"), preload("res://assets/art/station_fryer.png"),
	preload("res://assets/art/station_saute.png"), preload("res://assets/art/station_cold.png"), preload("res://assets/art/station_pass.png")]
const CREW_SHEETS := {"DEV": preload("res://assets/art/crew/dev.png"), "MO": preload("res://assets/art/crew/mo.png"), "JO": preload("res://assets/art/crew/jo.png")}
const ART_COOKS := {"DEV": preload("res://assets/art/cook_dev.png"), "MO": preload("res://assets/art/cook_mo.png")}
const ART_DISHES := {"BURGER": preload("res://assets/art/dish_burger.png"), "STEAK": preload("res://assets/art/dish_steak.png"),
	"FRIES": preload("res://assets/art/dish_fries.png"), "WINGS": preload("res://assets/art/dish_wings.png"),
	"PASTA": preload("res://assets/art/dish_pasta.png"), "SCAMPI": preload("res://assets/art/dish_scampi.png"),
	"SALAD": preload("res://assets/art/dish_salad.png"), "CAKE": preload("res://assets/art/dish_cake.png")}
const LIVES := 3             # tables you can walk in one service

## Live sliders (DEV MENU -> TUNE). Applied when a service starts.
const TUNE := {"ticket_time": [4.0, 16.0], "crew_ap": [1.0, 5.0], "stress_cap": [2.0, 12.0],
	"service_turns": [8.0, 40.0], "first_tickets": [2.0, 14.0], "more_tickets": [0.0, 4.0],
	"rush_stress": [0.0, 3.0], "breaks": [0.0, 3.0], "prep_every": [1.0, 8.0], "fox_cost": [0.0, 3.0], "late_ramp": [0.0, 3.0], "late_big_start": [6.0, 20.0]}
var ticket_time := 9.0
var crew_ap := 3.0
var stress_cap := 6.0
var service_turns := 20.0
var first_tickets := 7.0
var fox_cost := 2.0          # the studio fox cameo (service 3): moves the cook chasing it loses (docs/MASCOT.md)
var prep_every := 3.0        # CROSS PREP twist: every Nth dish needs an ingredient from another station
var breaks := 1.0            # second winds a service: the first cook who'd quit takes five instead
var more_tickets := 1.0
var late_ramp := 1.0
var late_big_start := 7.0
var rush_stress := 1.0

var level := 1               # service number
var score := 0               # tickets out, whole night
var lives := LIVES
var lives_max := LIVES     # LIVES, +1 with SECOND CHANCE
var cash := 0                # tips banked tonight, spent in the SHOP between services
var twist_box: VBoxContainer   # the TONIGHT card while it's up
var perks: Array = []        # upgrades owned tonight (upgrades.gd)
var cook_xp := {}            # productive work banked on completed services
var cook_perks := {}         # cook name -> perk ids earned tonight (8.5 plan #4: level-ups, Duff's pick)
var _undo := {}               # the state before the last move this turn (8.5 plan #4: one UNDO a turn)
var _undo_used := false
var undo_btn: Button
var _lvl_box: VBoxContainer   # the LEVEL UP sheet while it's up
var gone: Array = []         # cooks who walked out tonight: gone for the rest of the night (Duff's pick, Nov 26)
var levelup := ""            # a cook waiting to pick a perk before the next service ("" = none)
var k: Kitchen
var sel := 0                 # selected cook
var _fresh_turn := false     # END TURN's news is on the status line until the first move of the turn
var _steam_t := 0.0          # time since the last steam redraw
var _flinch := {}            # cook -> msec until their burn flinch ends
var _crew_action := {}       # cook -> [action, animation expiry]
var _cook_draw := {}         # cook -> where they're drawn: they walk there instead of jumping (8.5 pass)
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
		cook_xp = d.get("cook_xp", {}).duplicate()
		var cp: Variant = d.get("cook_perks", {})
		if cp is Dictionary:
			for nm in cp:
				cook_perks[str(nm)] = (cp[nm] as Array).map(func(x): return str(x)).filter(func(x): return Kitchen.PERKS.has(x))
		levelup = str(d.get("levelup", ""))
		gone = (d.get("gone", []) as Array).map(func(x): return str(x))
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
	if levelup != "":   # quit on the grade sheet with a pick owed: it comes first, then the service
		between = true
		next_service()
	checkpoint()
	get_node("/root/Audio").music_layers("music_loop", "music_busy")   # the kitchen gets louder as tickets go red
	_music_heat()


# ---------------------------------------------------------------- state + saving

## score = finished services only; the service in progress rides along in "kitchen" (its own
## served count), so a reload can't count tickets twice.
func state() -> Dictionary:
	var d := {"level": level, "score": _night_before, "cash": cash, "perks": perks.duplicate(),
		"cook_perks": cook_perks.duplicate(true), "cook_xp": cook_xp.duplicate(), "levelup": levelup, "gone": gone.duplicate()}
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
	_cancel_gesture()
	for c in get_children():
		if not c.is_in_group("sheet"):
			c.queue_free()
	theme = UI.theme()
	field = Control.new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	var f := field
	field.draw.connect(func(): _draw_field(f))
	field.gui_input.connect(_field_input)
	field.resized.connect(_cancel_gesture)
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
	undo_btn = UI.button("UNDO", undo)
	undo_btn.name = "UndoButton"
	_corner(undo_btn, not left, true, 150)
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
	if not quits.is_empty():   # the worst news first: everyone who walks out if the turn ends now
		end_btn.text = "END TURN\n%s QUIT%s" % [" + ".join(quits), "S" if quits.size() == 1 else ""]
	var brk := cooks_breaking()
	if quits.is_empty() and not brk.is_empty():   # second wind: they'd quit, but sit out a turn instead
		end_btn.text = "END TURN\n%s TAKES 5" % brk[0]
	var burns: Array[String] = []   # every pan that burns, not just the first (8.5 pass)
	for i in (k.pans.size() if quits.is_empty() and brk.is_empty() else 0):
		var p: Dictionary = k.pans[i]
		if not p.is_empty() and p.left <= 0 and p.sat >= k.burn_after:
			burns.append(Kitchen.STATIONS[i])
	if not burns.is_empty():
		end_btn.text = "END TURN\n%s BURN%s" % [" + ".join(burns), "S" if burns.size() == 1 else ""]
	if end_btn.text == "END TURN" and not k.done and not between and k.tickets.is_empty() and k.incoming.is_empty():
		end_btn.text = "END TURN\nFINISH SERVICE"   # every table is out: say what the button does now
	if end_btn.text == "END TURN":   # a turn earlier (stress pass): one more worked turn after this one and they quit
		for c in k.crew.size():
			if not k.crew[c].out and stress_after(c) == k.stress_cap - 1:
				end_btn.text = "END TURN\n%s NEAR QUIT" % k.crew[c].name
				break
	act_btn.text = a if a != "" else "TAP A STATION"   # nothing to do here: say how to move
	if a == "" and not k.crew[sel].out and k.crew[sel].ap <= 0:   # say why: this cook is spent till END TURN
		act_btn.text = "%s: %s" % [k.crew[sel].name, "CHASING FOX" if k.crew[sel].get("fox", false) else ("ON BREAK" if k.crew[sel].get("brk", false) else "NO MOVES")]   # short: HUGE text wraps it over the status line
	if a == "FIRE":   # say which table it cooks for, picked or not
		var fp := k.fire_pick(sel, pick_tid, pick_ix)
		act_btn.text = "FIRE T%d" % fp.t.table
		if pick_ix >= 0 and fp.t.id == pick_tid and fp.item == k.ticket(pick_tid).items[pick_ix]:
			act_btn.text = "FIRE %s" % fp.item.dish   # the tapped dish, by name
		if k.cook_time_by(sel, fp.item.dish) > fp.t.time:   # it can't be up before the table walks: say so first
			act_btn.text += ": TOO LATE"
	elif a == "PREP":   # what it pulls, and for which table
		var pp := k.prep_pick(k.crew[sel].at, pick_tid)
		act_btn.text = "PREP %s T%d" % [Kitchen.prep_name(pp.item), pp.t.table]
	elif a == "RUSH":   # warn when this rush would send the cook over the edge
		# end of turn also adds 1 to a working cook while any ticket will be red (2 minutes or less)
		var projected := stress_after(sel, true) + k.rush_cost()
		act_btn.text = ("RUSH (TAKES 5)" if _wind_for(sel) else "RUSH (QUITS!)") if projected >= k.stress_cap else ("RUSH (FREE)" if k.rush_cost() <= 0 else "RUSH +%d STRESS" % k.rush_cost())
	elif a == "RUN" and k.tray > 1:   # a tray: say how many plates go out on this one action
		var n := mini(k.tray, k.window.size() + (0 if k.crew[sel].hand.is_empty() else 1))
		if n > 1:
			act_btn.text = "RUN %d PLATES" % n
	if (a in ["RUN", "PLATE", "PREP"]) and k.is_free(sel, a):   # the cook's knack: this one costs no move (8.5 plan #4)
		act_btn.text += " (FREE)"
	if a != "":   # whose move this is, on the button (stress pass: taps moved the wrong cook)
		var named := "%s: %s" % [k.crew[sel].name, act_btn.text]
		var bf := act_btn.get_theme_font("font")
		var room := act_btn.size.x - 20.0 if act_btn.size.x > 40.0 else 210.0
		if bf == null or bf.get_string_size(named, HORIZONTAL_ALIGNMENT_LEFT, -1, act_btn.get_theme_font_size("font_size")).x <= room * 2.0:
			act_btn.text = named   # up to two lines: the button wraps, and grows up, not off the screen
	if a != "" and a != "RUSH" and not k.crew[sel].out and not k.crew[sel].acted:
		# The first move of a turn ends this cook's rest: say what it costs before the tap (8.5 pass).
		# PLATE empties the pan here, so its burn never lands on this cook (fresh-eyes PR #27)
		var then := stress_after(sel, true, k.crew[sel].at if a == "PLATE" else -1)
		if then >= k.stress_cap:
			act_btn.text += "\n(%s %s)" % [k.crew[sel].name, "TAKES 5" if _wind_for(sel) else "QUITS"]
		elif then > k.crew[sel].stress:
			act_btn.text += "\n+%d STRESS" % (then - k.crew[sel].stress)
		elif k.crew[sel].stress >= k.stress_cap - 3 and stress_after(sel) < k.crew[sel].stress:   # no cost, but a tired cook gives up their rest
			act_btn.text += "\nSKIPS REST"
	act_btn.disabled = a == ""
	if undo_btn != null:   # only while there's a move to take back this turn
		undo_btn.visible = not _undo.is_empty() and not _undo_used and not k.done and not between and not over
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
	return Kitchen.count_for(maxi(mini(3, base), base + pace_adjust().tickets),
		int(more_tickets), n, int(late_ramp))


## After a service (or a lost night), the house reads you: a rough one eases the next, an aced one pushes it.
## Returns a line for the grade sheet ("" when nothing moved).
func _house_reads(g: String, lost: bool = false) -> String:
	var ease := clampi(int(_settings.get_value("house_ease")), -2, 2)
	var was := ease
	if lost or g in ["D", "F"]:
		ease = mini(ease + 1, 2)
	elif g in ["A+", "A"] and (k == null or k.service >= 2):   # service 1 is the lesson: acing it doesn't stack service 2 (8.5 plan #3)
		ease = maxi(ease - 1, -2)
	if ease == was:
		return ""
	_settings.set_value("house_ease", ease)
	return "The floor eases off a ticket." if ease > was else "Word's out. Busier next service."


func _new_service() -> void:
	_cancel_gesture()
	_crew_action.clear()
	_cook_draw = {}   # a new service starts with everyone at their spot, not sliding from last service's
	rail_off = 0
	_stress_turn = -1   # hint timers count this service's turns
	_spent_turn = -1
	for ch in get_children():   # the new service's clock restarts at turn 0: so does a hint's wait
		if ch.name.begins_with("Coach_"):
			ch.set_meta("turn", 0)
	_undo = {}
	_undo_used = false
	k = Kitchen.new()
	var u := Upgrades.apply({"ticket_time": int(ticket_time), "stress_cap": int(stress_cap),
		"rush_stress": int(rush_stress), "lives": LIVES}, perks)
	var adj := pace_adjust()
	k.ticket_time = maxi(mini(5, u.ticket_time), u.ticket_time + adj.time)   # pace never pushes below 5 (TUNE can)
	k.ap = int(crew_ap)
	k.stress_cap = u.stress_cap
	k.turns = int(service_turns)
	# Later services ramp independently of purchases.
	k.first_tickets = maxi(mini(3, int(first_tickets)), int(first_tickets) + adj.tickets)
	k.more_tickets = int(more_tickets)
	k.late_ramp = int(late_ramp)
	k.late_big_start = int(late_big_start)
	k.rush_stress = u.rush_stress
	k.cast_iron = u.cast_iron
	k.tray = u.tray
	k.hires = u.hires
	k.breaks = int(breaks)
	k.prep_every = int(prep_every)
	k.fox_cost = int(fox_cost)
	k.batch_stations = u.batch_stations
	k.cook_perks = cook_perks.duplicate(true)
	k.gone = gone.duplicate()
	k.start(level, rng.randi() if level > 1 else 0)
	lives_max = u.lives
	lives = lives_max
	sel = 0
	pick_tid = 0
	pick_ix = -1


## Selected cook acts where they stand (the big button only).
func act() -> void:
	_cancel_gesture()
	if paused or over or between:
		return
	var what := k.action_here(sel)
	if _fresh_turn and what != "":   # the first move of a turn clears last turn's news off the status line
		k.events.clear()
		_fresh_turn = false
	var at: int = k.crew[sel].at
	var tips_before := k.tips
	var served_before := k.served
	var before := _snap()
	if k.act_here(sel, pick_tid, true, pick_ix):
		_undo = before
		_crew_action[sel] = [what, Time.get_ticks_msec() + 700]
		var snd: String = {"FIRE": "fire", "RUSH": "rush", "PLATE": "plate", "RUN": "bell", "PREP": "click"}.get(what, "good")
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
			"PREP":
				_fx_ring(c, UI.key("info"))
				_fx_text(top, "PREPPED!", UI.key("info"))
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
	if k != null and field != null:
		var walking := false
		for c in k.crew.size():
			var to := cook_pos(c)
			var at: Vector2 = _cook_draw.get(c, to)
			if _settings.get_value("low_graphics") or at.distance_to(to) < 2.0:
				_cook_draw[c] = to
			else:
				_cook_draw[c] = at.move_toward(to, maxf(900.0 * dt, at.distance_to(to) * 12.0 * dt))
				walking = true
		_steam_t += dt
		var moving := false
		if not _settings.get_value("low_graphics") and not (over or between):
			var now := Time.get_ticks_msec()
			for fc in k.crew.size():
				var cr: Dictionary = k.crew[fc]
				if not cr.out:
					moving = true
		if walking or (moving and _steam_t >= 1.0 / 15.0):
			if not walking:
				_steam_t = 0.0
			field.queue_redraw()   # a walk in progress: every frame, it's short; sprite animation: 15 a second
		elif _steam_t >= 1.0 / 15.0 and not _settings.get_value("low_graphics") and k.pans.any(func(p): return not p.is_empty()):
			_steam_t = 0.0
			field.queue_redraw()   # steam over a pan: 15 a second is plenty, and spares the battery
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
	_cancel_gesture()
	if not (paused or over or between):
		_undo = {}   # a new turn: the last one is final, and the undo comes back
		_undo_used = false
	if paused or over or between:
		return
	rail_off = 0   # a new turn opens on the most urgent tickets
	var walked_before := k.walked
	var critic_before := k.critic
	var tickets_before: Array = k.tickets.map(func(t): return t.id)
	var stress_before: Array = k.crew.map(func(c): return c.stress)
	var red_before: Array = k.tickets.filter(func(t): return t.time <= 2).map(func(t): return t.id)
	k.end_turn()
	_fresh_turn = true
	var went_red: Array = k.tickets.filter(func(t): return t.time <= 2 and not red_before.has(t.id)).map(func(t): return t.id)
	if not went_red.is_empty():   # a ticket just went red: the rail jolts, so it's felt as well as seen
		_shake(5.0)
		UI.buzz(30)
		for i in mini(rail_tickets().size(), 4):
			if went_red.has(rail_tickets()[i].id):
				_fx_ring(ticket_rect(i).get_center(), UI.key("bad"), 70.0)
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
				_fx_burst(station_rect(bs).get_center(), Color("6b6b6b"), 30)
				_fx_burst(station_rect(bs).get_center(), MenuArt.EMBER, 16)
				_fx_ring(station_rect(bs).get_center(), UI.key("bad"), 90.0)
				_fx_text(Vector2(station_rect(bs).get_center().x, station_rect(bs).position.y - 6), "BURNED! REFIRE", UI.key("bad"), 34)
				for fc in k.crew.size():
					if k.crew[fc].at == bs and not k.crew[fc].out:
						_flinch[fc] = Time.get_ticks_msec() + 450
				_shake(10.0)
				UI.buzz(60)
		elif e.begins_with("FOX IN THE KITCHEN"):
			_fox_t0 = Time.get_ticks_msec()
			get_node("/root/Audio").sfx("door")
			get_node("/root/Subs").cue("[yip and clatter: a fox is loose in the kitchen]")
			_shake(8.0)
			UI.buzz(40)
		elif e.ends_with("WALKED OUT"):
			get_node("/root/Audio").sfx("door")
			get_node("/root/Subs").cue("[door slams: cook walked out]")
			var qn: String = e.trim_suffix(" WALKED OUT")
			var house_left := 0
			for hn in ["DEV", "MO"]:
				if hn != qn and not gone.has(hn):
					house_left += 1
			if not Kitchen.TEMPS.has(qn) and not gone.has(qn) and house_left > 0 and not get_node("/root/DebugMenu").god_mode:
				gone.append(qn)   # the last house cook always comes back next service (no empty line)   # gone for the rest of the night, not just this service (RETRY brings them back)
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
	var bonus: int = Kitchen.GRADE_BONUS.get(k.grade(), 10)   # every grade pays something (Duff, Nov 26)
	for cr in k.crew:
		if cr.name in ["DEV", "MO", "JO"]:
			cook_xp[cr.name] = int(cook_xp.get(cr.name, 0)) + int(cr.get("work", 0))
	levelup = mvp()
	cash += k.tips + bonus
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
	_grade_sheet(g, parts, read, {"service": k.service, "served": k.served, "total": k.total, "walked": k.walked, "tips": k.tips, "bonus": bonus})
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
	var tl := UI.label("%d of %d out, %d walk%s\nTips $%d + $%d %s bonus" % [st.served, st.total, st.walked, "" if st.walked == 1 else "s",
		st.tips, st.get("bonus", 0), g], 24)
	tl.name = "TipsLine"
	sheet_box.add_child(tl)
	_points_head = "%d POINTS: out %d, speed %d, pans %d%s%s" % [parts.total, parts.out, parts.speed, parts.pans,
		", walks %d" % parts.walks if parts.walks != 0 else "", ", critic %+d" % parts.critic if parts.critic != 0 else ""]
	_points_read = read
	var why := UI.label("", 18, UI.DIM)
	why.name = "Points"
	sheet_box.add_child(why)
	_refresh_points()
	if not gone.is_empty():   # who walked out stays out tonight: say it where the night is summed up
		var gl := UI.label("%s WALKED OUT: GONE FOR TONIGHT" % " + ".join(gone), 20, UI.key("bad"))
		gl.name = "Gone"
		sheet_box.add_child(gl)
	if k.critic != "":   # the critic gets their own stamp, not a number in the small print (8.5 pass)
		var cl := UI.label("CRITIC LOVED IT  +8" if k.critic == "served" else "CRITIC WALKED  -8", 28,
			UI.key("good") if k.critic == "served" else UI.key("bad"))
		cl.name = "Critic"
		sheet_box.add_child(cl)
		_stamp(cl)


var _points_head := ""   # the grade sheet's points line, kept so "Next: N tickets" can be redone
var _points_read := ""


## The points line plus the next service's load. Redone after a shop buy: upgrades bring tables.
func _refresh_points() -> void:
	var why: Label = sheet_box.get_node_or_null("Points") if sheet_box != null else null
	if why == null:
		return
	var n := tickets_for(level)
	why.text = _points_head + ("\n%s Next: %d tickets." % [_points_read, n] if _points_read != "" else "  Next: %d tickets." % n)


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
		var can := Upgrades.ORDER.any(func(id): return Upgrades.can_buy(id, cash, perks, level))
		b.text = "SHOP ($%d)%s" % [cash, " NEW!" if can and not _shop_opened else ""]   # NEW until you've looked


var _shop_opened := false   # the SHOP button says NEW! until it's opened after a service


## Spend banked tips on upgrades for the rest of tonight. Each one is bought once.
func open_shop() -> void:
	_shop_opened = true
	var box := UI.sheet(self, 500)
	box.add_child(UI.label("KITCHEN SHOP", 30, UI.ACCENT))
	var bank := UI.label("Bank: $%d. Upgrades do not add tables." % cash, 20, UI.DIM)
	if level < 4:
		bank.text += "\nEntree tray + burners open S4."
	if not perks.has("temp"):   # build-84 review: nothing said a third cook was the answer to a busier night
		var left := 2 - gone.size()
		bank.text += "\nNext: %d tickets, %d cook%s. THIRD COOK helps." % [tickets_for(level), left, "" if left == 1 else "s"]
	bank.name = "Bank"
	bank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(bank)
	var owned: Array[String] = []
	var listed: Array = Upgrades.shown(perks, level)
	for id in Upgrades.ORDER:
		if perks.has(id) and not listed.has(id):   # owned rows already say OWNED: name only the ones that left the list
			owned.append(String(Upgrades.ALL[id].name))
	if not owned.is_empty():   # a tray upgrades in place, so the one it replaced leaves the list
		var ol := UI.label("ALSO OWNED: " + ", ".join(owned), 18, UI.key("good"))
		ol.name = "Owned"
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(ol)
	# The rows scroll once they'd push DONE off a phone at big text (the THIRD COOK row made six).
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UI.GAP)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	box.add_child(scroll)
	var big_text: bool = float(_settings.text_scale()) > 1.2
	if big_text:
		scroll.custom_minimum_size.y = 430
	elif Upgrades.shown(perks, level).size() > 6:   # DOUBLE BURNERS made seven rows: DONE fell off a phone at normal text
		scroll.custom_minimum_size.y = 560
	else:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # fits as is: no scroll
	for id in Upgrades.shown(perks, level):
		var u: Dictionary = Upgrades.ALL[id]
		var b: Button
		if perks.has(id):
			b = UI.button("%s: OWNED\n%s" % [u.name, u.says], Callable(), 88)
			b.disabled = true
		else:
			var cost := Upgrades.price(id)
			var short := cash < cost   # say it in words, not just the disabled colour
			b = UI.button("%s  %s\n%s" % [u.name, ("NEED $%d" if short else "$%d") % cost, u.says], func(): buy(id, box), 88)
			b.disabled = not Upgrades.can_buy(id, cash, perks, level)
		b.name = "Buy_" + id
		b.add_theme_font_size_override("font_size", UI.font_size(20))
		rows.add_child(b)
	box.add_child(UI.button("DONE", func(): UI.close_sheet(box)))


func buy(id: String, box: VBoxContainer) -> void:
	var left := Upgrades.buy(id, cash, perks, level)
	if left < 0:
		return
	var previous_cash := cash
	cash = left
	if not _save.write(state()):
		cash = previous_cash
		perks.erase(id)
		return
	get_node("/root/Audio").sfx("level", 1.3)
	get_node("/root/Subs").cue("[register: %s bought]" % Upgrades.ALL[id].name.to_lower())
	UI.buzz(25)
	_shop_label()
	_refresh_points()
	UI.close_sheet(box)
	if id == "temp":
		_crew_expanded()
	else:
		open_shop()


## One-time celebration: the existing flat-ink crew art, with Jo highlighted.
func _crew_expanded() -> void:
	var box := UI.sheet(self)
	var head := UI.label("CREW EXPANDED", 34, UI.ACCENT)
	head.name = "CrewExpanded"
	box.add_child(head)
	_stamp(head)
	box.add_child(UI.label("WELCOME TO THE LINE, JO!", 22, UI.key("good")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for nm in ["DEV", "MO", "JO"]:
		var column := VBoxContainer.new()
		row.add_child(column)
		var atlas := AtlasTexture.new()
		atlas.atlas = CREW_SHEETS[nm]
		atlas.region = Rect2(0, 0, 128, 176)
		var pic := TextureRect.new()
		pic.texture = atlas
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(116, 160)
		column.add_child(pic)
		column.add_child(UI.label(nm + ("  +" if nm == "JO" else ""), 20, UI.key("good") if nm == "JO" else UI.DIM))
	var info := UI.label("Jo joins every remaining service.\nOne payment. No more hire fees.", 22)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	box.add_child(MenuArt.primary(UI.button("LET'S COOK!", func():
		UI.close_sheet(box)
		open_shop(), 88)))


## Best night on this phone (shown on the title): survives GAME OVER and NEW GAME.
func _record_best(services_cleared: int) -> void:
	if get_node("/root/DebugMenu").god_mode:
		return
	if services_cleared > int(_settings.get_value("best_service")) or (services_cleared == int(_settings.get_value("best_service")) and score > int(_settings.get_value("best_tickets"))):
		_settings.set_value("best_service", services_cleared)
		_settings.set_value("best_tickets", score)


## The cook who contributed most productive work this service (all permanent crew).
## Ties go to the one with fewer perks, so both cooks grow.
func mvp() -> String:
	var best := ""
	var best_acts := -1
	for cr in k.crew:
		if cr.name not in ["DEV", "MO", "JO"] or gone.has(cr.name) or cr.out or (cook_perks.get(cr.name, []) as Array).size() >= Kitchen.PERK_IDS.size():
			continue
		var a: int = int(cr.get("work", 0))
		var fewer: bool = best != "" and (cook_perks.get(cr.name, []) as Array).size() < (cook_perks.get(best, []) as Array).size()
		if a > 0 and (a > best_acts or (a == best_acts and fewer)):
			best = cr.name
			best_acts = a
	return best


## Three perks to choose from for a cook, the same three after a reload (seeded by night + cook).
func perk_offer(nm: String) -> Array:
	var have: Array = cook_perks.get(nm, [])
	var pool: Array = []
	for id in Kitchen.PERK_IDS:   # not owned, and a station hand only for a station open by now
		if not have.has(id) and (id != "prep" or level >= 4) and (not id.begins_with("fast_") or Kitchen.OPENS[int(id.trim_prefix("fast_"))] <= level):
			pool.append(id)
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d:%d" % [nm, level, have.size()])
	for i in range(pool.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	# Give a role-consistent choice first when possible, with alternatives from other paths.
	var offer: Array = []
	if not have.is_empty():
		for id in pool:
			if Kitchen.perk_role(id) == Kitchen.cook_role(have):
				offer.append(id)
				break
	for id in pool:
		if not offer.has(id) and not offer.any(func(p): return Kitchen.perk_role(p) == Kitchen.perk_role(id)):
			offer.append(id)
		if offer.size() == 3:
			return offer
	for id in pool:
		if not offer.has(id):
			offer.append(id)
		if offer.size() == 3:
			break
	return offer


## LEVEL UP: pick one of three perks for the service's hardest worker, then the service starts.
func open_levelup() -> void:
	var nm := levelup
	var box := UI.sheet(self)
	_lvl_box = box   # its own handle: a pause on top swaps sheet_box (like the twist card)
	var head := UI.label("LEVEL UP: %s" % nm, 34, UI.ACCENT)
	head.name = "LevelUp"
	box.add_child(head)
	var have: Array = cook_perks.get(nm, [])
	var sub := UI.label("LV %d  |  %d XP  |  %s\nMost productive last service. Pick a perk%s" % [have.size() + 1, int(cook_xp.get(nm, 0)), Kitchen.cook_role(have),
		(". Has: " + ", ".join(have.map(func(id): return Kitchen.PERKS[id][0]))) if not have.is_empty() else "."], 20, UI.DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(UI.label("One free perk action per turn.", 18, UI.DIM))
	for id in perk_offer(nm):
		var b := UI.button("%s: %s\n%s" % [Kitchen.perk_role(id), Kitchen.PERKS[id][0], Kitchen.PERKS[id][1]], func(): pick_perk(id), 88)
		b.name = "Perk_" + id
		b.add_theme_font_size_override("font_size", UI.font_size(20))
		box.add_child(b)
	_stamp(head)


func pick_perk(id: String) -> void:
	if levelup == "":
		return
	var have: Array = cook_perks.get(levelup, [])
	if not have.has(id):
		have.append(id)
	cook_perks[levelup] = have
	get_node("/root/Subs").cue("[cheer: %s learns %s]" % [levelup.to_lower(), Kitchen.PERKS[id][0].to_lower()])
	get_node("/root/Audio").sfx("level", 1.2)
	UI.buzz(30)
	levelup = ""
	if is_instance_valid(_lvl_box):
		UI.close_sheet(_lvl_box)
	_lvl_box = null
	checkpoint()
	next_service()


func next_service() -> void:
	if not between:
		return
	if levelup != "" and k.crew.any(func(cr): return cr.name == levelup) and not perk_offer(levelup).is_empty():
		if not is_instance_valid(_lvl_box):
			if sheet_box != null:
				UI.close_sheet(sheet_box)   # the grade sheet makes way for the pick
				sheet_box = null
			open_levelup()
		return
	levelup = ""
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
	if between:   # the grade sheet already banked this service: just move on (a dev skip skips the pick too)
		levelup = ""
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
var _stress_turn := -1   # turn stress first showed (its hint stays two turns)
var _spent_turn := -1    # turn a cook first ran out of moves (its hint stays till END TURN)
const COACH_TURNS := 3   # turns a hint waits for the player before it retires


func _coach_steps() -> Array:
	return [
		["fire", "TAP FIRE TO COOK", func(): return true,
			func(): return k.turn > 0 or k.pans.any(func(p): return not p.is_empty())],
		["end_turn", "TAP END TURN: COOK", func(): return k.pans.any(func(p): return not p.is_empty()),
			func(): return k.turn > 0],
		# 8.5 plan #2: taught on turn 2, not after the first table is out ("face vs station" confused service 1).
		["switch", "TAP COOK, THEN STATION", func(): return k.turn >= 1 and k.crew.size() > 1 and not k.crew[1].out,
			func(): return sel != 0 or k.crew.size() < 2 or k.crew[1].out],
		# Fresh-player review: the action dots over each cook were never noticed. After the first END TURN.
		["dots", "NUMBER = MOVES LEFT", func(): return k.turn >= 1,
			func(): return k.turn >= 2 or k.crew.any(func(c): return not c.out and c.ap <= 0)],
		["plate", "UP! TAP PLATE", func(): return k.pans.any(func(p): return not p.is_empty() and p.left <= 0),
			func(): return not k.window.is_empty() or k.served > 0],
		["run", "PASS: RUN SERVES IT", func(): return not k.window.is_empty(),
			func(): return k.served > 0],
		# 8.5 plan #3 (build-84 review: stress went 2/6 to QUITS before it was explained).
		["stress", "FULL STRESS = QUITS", func(): return _stress_seen(),
			func(): return _stress_turn >= 0 and k.turn > _stress_turn + 1],
		["done", "DONE = NO MOVES", func(): return _spent_seen(),
			func(): return _spent_turn >= 0 and k.turn > _spent_turn],
		["pick", "TAP TICKET: COOK FIRST", func(): return k.tickets.size() >= 2,
			func(): return pick_tid != 0],
		["rest", "IDLE COOKS LOSE STRESS", func(): return k.crew.any(func(c): return not c.out and c.stress >= k.stress_cap - 3),
			func(): return false],   # nothing to do but read it: it retires after a few turns
		["rush", "RUSH IT: +STRESS", func(): return k.action_here(sel) == "RUSH",
			func(): return k.pans.any(func(p): return p.get("rushed", false))],
	]


func _stress_seen() -> bool:
	if _stress_turn < 0 and k.crew.any(func(c): return not c.out and c.stress > 0):
		_stress_turn = k.turn
	return _stress_turn >= 0


func _spent_seen() -> bool:
	if _spent_turn < 0 and k.crew.any(func(c): return not c.out and c.ap <= 0):
		_spent_turn = k.turn
	return _spent_turn >= 0


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


## Open stations share the width; a closed one is a narrow slot (8.5 plan #4, IGN build 89: 75 px
## stations were fiddly to hit, and in service 1 two closed stations took two fifths of the line).
const CLOSED_W := 0.42   # a closed station's share of an open one's width


func station_rect(i: int) -> Rect2:
	var w := field.size.x
	var n := Kitchen.STATIONS.size()
	var pad := 8.0
	var shares: Array = []
	var total := 0.0
	for j in n:
		var sh := 1.0 if k == null or k.is_open(j) else CLOSED_W
		shares.append(sh)
		total += sh
	var unit := (w - pad * (n + 1.0)) / total
	var x := pad
	for j in i:
		x += shares[j] * unit + pad
	var y := _rail_y() + 300.0
	return Rect2(x, y, shares[i] * unit, 170.0)


## Where a tap counts as this station: its whole column, gaps split with the neighbours, plus a
## little above (8.5 plan #4: bigger, gap-free tap zones).
func station_hit(i: int) -> Rect2:
	var r := station_rect(i)
	return Rect2(r.position.x - 4.0, r.position.y - 16.0, r.size.x + 8.0, r.size.y + 16.0)


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
	return Vector2(cx + off, r.end.y + 60.0)


const COOK_R := 36.0         # 72 wide: the touch rule


# One owner per gesture. Native touch is handled directly; Godot's emulated mouse
# events remain enabled for normal UI buttons but must not repeat field commands.
const DRAG_THRESHOLD := 18.0
var _pointer := -2  # -2 none, -1 mouse, >=0 touch index
var _press_pos := Vector2.ZERO
var _drag_pos := Vector2.ZERO
var _press_cook := -1
var _dragging := false


func _cancel_gesture() -> void:
	_pointer = -2
	_press_cook = -1
	_dragging = false
	if is_instance_valid(field):
		field.queue_redraw()


func _field_input(e: InputEvent) -> void:
	if paused or over or between:
		_cancel_gesture()
		return
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventScreenTouch:
		if e.canceled:
			if _pointer == e.index:
				_cancel_gesture()
		elif e.pressed:
			_begin_gesture(e.index, e.position)
		else:
			_end_gesture(e.index, e.position)
	elif e is InputEventScreenDrag:
		_move_gesture(e.index, e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_begin_gesture(-1, e.position)
		else:
			_end_gesture(-1, e.position)
	elif e is InputEventMouseMotion:
		_move_gesture(-1, e.position)


# Capture motion and release from the owning pointer even when it leaves the field
# or crosses a HUD button. Only a field press can initiate a command.
func _input(e: InputEvent) -> void:
	if _pointer == -2 or not is_instance_valid(field):
		return
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var owned := false
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		owned = e.index == _pointer and (e is InputEventScreenDrag or not e.pressed)
	elif e is InputEventMouseMotion or e is InputEventMouseButton:
		owned = _pointer == -1 and (e is InputEventMouseMotion or (e.button_index == MOUSE_BUTTON_LEFT and not e.pressed))
	if owned:
		var local: InputEvent = field.make_input_local(e)
		_field_input(local)
		get_viewport().set_input_as_handled()


func _begin_gesture(id: int, p: Vector2) -> void:
	if _pointer != -2:
		return
	_pointer = id
	_press_pos = p
	_drag_pos = p
	_press_cook = cook_at(p)


func _move_gesture(id: int, p: Vector2) -> void:
	if _pointer != id:
		return
	_drag_pos = p
	if _press_cook >= 0 and p.distance_to(_press_pos) >= DRAG_THRESHOLD:
		_dragging = true
	field.queue_redraw()


func _end_gesture(id: int, p: Vector2) -> void:
	if _pointer != id:
		return
	_move_gesture(id, p)
	var c := _press_cook
	var dragged := _dragging
	var short_tap := p.distance_to(_press_pos) < DRAG_THRESHOLD
	_cancel_gesture()
	if dragged:
		var i := station_at(p)
		if i >= 0 and _can_walk(c, i):
			var before := _snap()
			sel = c
			if k.move(c, i):
				_undo = before
				_after_move()
	elif short_tap:
		if c >= 0 and not k.crew[c].out:
			_select_cook(c)
		else:
			tap(p)


func station_at(p: Vector2) -> int:
	for i in Kitchen.STATIONS.size():
		if station_hit(i).has_point(p):
			return i
	return -1


func _can_walk(c: int, i: int) -> bool:
	return c >= 0 and c < k.crew.size() and not k.crew[c].out and k.crew[c].ap > 0 and k.is_open(i) and k.crew[c].at != i and k.move_cost(c, i) <= k.crew[c].ap


func cook_visual_pos(c: int) -> Vector2:
	var pos: Vector2 = _cook_draw.get(c, cook_pos(c))
	var cr: Dictionary = k.crew[c]
	if not _settings.get_value("low_graphics") and not cr.out:
		var tt := Time.get_ticks_msec() / 1000.0
		if cr.acted and cr.ap > 0:
			pos.y += sin(tt * 7.0 + c * 1.7) * 3.0
		if Time.get_ticks_msec() < int(_flinch.get(c, 0)):
			pos.x += sin(tt * 70.0) * 5.0
	return pos


# Rows of the 2-column crew atlas: idle, walk, work, serve, rest.
func crew_frame(c: int) -> int:
	var cr: Dictionary = k.crew[c]
	if _cook_draw.get(c, cook_pos(c)).distance_to(cook_pos(c)) > 2.0:
		return 1
	var recent: Array = _crew_action.get(c, [])
	if not recent.is_empty() and Time.get_ticks_msec() < int(recent[1]):
		return 3 if recent[0] in ["PLATE", "RUN"] else 2
	if cr.ap <= 0 or cr.stress >= k.stress_cap - 2:
		return 4
	return 2 if cr.acted else 0


func cook_at(p: Vector2) -> int:
	var best := -1
	var distance := INF
	for c in k.crew.size():
		if k.crew[c].out:
			continue
		var pos := cook_visual_pos(c)
		var d := pos.distance_squared_to(p)
		if Rect2(pos - Vector2(43, 55), Vector2(86, 108)).has_point(p) and d < distance:
			best = c
			distance = d
	return best


func _select_cook(c: int) -> void:
	sel = c
	get_node("/root/Audio").sfx("click")
	_after_move()


## A tap at a point on the field (also used by the autoplay bot).
func tap(p: Vector2) -> void:
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
	var cook := cook_at(p)
	if cook >= 0:
		_select_cook(cook)
		return
	var i := station_at(p)
	if i < 0:
		return
	if not k.is_open(i):
		if note != null:
			note.text = "%s OPENS IN SERVICE %d" % [Kitchen.STATIONS[i], Kitchen.OPENS[i]]
		return
	if k.crew[sel].at == i:
		return  # actions are committed only through the contextual button
	if _move_undoable(sel, i):
		get_node("/root/Audio").sfx("click")
		_after_move()
	else:
		_too_far(i)


func _move_undoable(c: int, i: int) -> bool:
	var before := _snap()
	if k.move(c, i):
		_undo = before
		return true
	return false


func _snap() -> Dictionary:
	return {"k": k.to_dict(), "sel": sel, "pick_tid": pick_tid, "pick_ix": pick_ix}


## Take back the last move of this turn, once a turn (8.5 plan #4, IGN build 89: a mis-tap cost a move
## with no way back). END TURN can't be taken back: that's the turn's real commitment.
func undo() -> void:
	_cancel_gesture()
	if _undo.is_empty() or _undo_used or paused or over or between:
		return
	var back := Kitchen.new()
	if not back.from_dict(_undo.k):
		return
	k = back
	sel = int(_undo.sel)
	pick_tid = int(_undo.pick_tid)
	pick_ix = int(_undo.pick_ix)
	score = _night_before + k.served
	_undo = {}
	_undo_used = true
	_cook_draw = {}
	_crew_action.clear()
	get_node("/root/Audio").sfx("click", 0.8)
	get_node("/root/Subs").cue("[undo]")
	UI.buzz(15)
	_after_move()


## A walk that can't happen says why, on the station and in the status line (it used to do nothing).
func _too_far(i: int) -> void:
	var cr: Dictionary = k.crew[sel]
	if cr.out:
		return
	var need: int = k.move_cost(sel, i)
	var why := "%s: NO MOVES LEFT" % cr.name if cr.ap <= 0 else "TOO FAR: %s NEEDS %d MOVES, HAS %d" % [cr.name, need, cr.ap]
	if note != null:
		note.text = why
	var r := station_rect(i)
	_fx_text(Vector2(r.get_center().x, r.position.y - 6), "TOO FAR" if cr.ap > 0 else "NO MOVES", UI.key("bad"), 24)
	get_node("/root/Audio").sfx("click", 0.7)
	UI.buzz(30)
	if field != null:
		field.queue_redraw()


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
	var wind: int = k.breaks
	for c in k.crew.size():
		if not k.crew[c].out and stress_after(c) >= k.stress_cap:
			if wind > 0:   # second wind: end_turn spends it on the first cook (crew order) who'd quit
				wind -= 1
				continue
			out.append(k.crew[c].name)
	return out


## The second wind would land on cook c if they hit the cap now: one is left and no cook before
## them in crew order (end_turn's order) hits the cap first (fresh-eyes PR #32).
func _wind_for(c: int) -> bool:
	if k.breaks <= 0:
		return false
	for i in c:
		if not k.crew[i].out and stress_after(i) >= k.stress_cap:
			return false
	return true


## Cooks who'd hit the cap but take five instead (second wind), in end_turn's order.
func cooks_breaking() -> Array:
	var out: Array = []
	for c in k.crew.size():
		if out.size() < k.breaks and not k.crew[c].out and stress_after(c) >= k.stress_cap:
			out.append(k.crew[c].name)
	return out


## Cook c's stress once the turn ends now (the meter shows the change before END TURN is pressed).
func stress_after(c: int, as_acted := false, emptied := -1) -> int:
	var cr: Dictionary = k.crew[c]
	var red := k.tickets.any(func(t): return t.time - 1 > 0 and t.time - 1 <= 2)
	var s: int = cr.stress
	for i in k.pans.size():
		var p: Dictionary = k.pans[i]
		if not p.is_empty() and p.left <= 0 and p.sat >= k.burn_after and cr.at == i and i != emptied:
			s += k.burn_stress(c)
	return s + (1 if red else 0) + (1 if k.heat_turn() else 0) if (cr.acted or as_acted) else maxi(0, s - k.rest_recovery(c))


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


## 8.5 plan #3: the one table that walks first wears URGENT (build-84 review: a busy rail was
## unreadable). Only with two or more tickets on: one ticket is urgent by default. -1 = none.
func urgent_tid() -> int:
	if k.tickets.size() < 2:
		return -1
	var lo: Dictionary = k.tickets[0]
	for t in k.tickets:
		if t.time < lo.time:
			lo = t
	return lo.id


## Dishes waiting to be fired at station i.
func waiting_at(i: int) -> int:
	var n := 0
	for t in k.tickets:
		for it in t.items:
			if it.state == "wait" and (int(it.get("needs", -1)) == i if it.has("needs") else Kitchen.DISHES[it.dish].st == i):
				n += 1   # a dish waiting on an ingredient counts where it's prepped, not where it cooks
	return n


## Somebody working stands at station i (a station with work and nobody there goes red: N WAITING).
func manned(i: int) -> bool:
	return k.crew.any(func(cr): return not cr.out and cr.at == i)


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
	var urgent := urgent_tid()
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
		if t.id == urgent and t.id != pick_tid and not t.get("vip", false) and not t.get("critic", false):
			if t.items.size() >= 4:   # a big table's 4th dish sits where the band would: a tab over the card's top edge instead
				f.draw_rect(Rect2(r.get_center().x - 34, r.position.y - 9, 68, 16), UI.key("bad"))
				f.draw_string(font, Vector2(r.get_center().x - 34, r.position.y + 4), "URGENT", HORIZONTAL_ALIGNMENT_CENTER, 68,
					UI.font_size(11), UI.BG)
			else:
				f.draw_rect(Rect2(r.position.x, r.end.y - 26, r.size.x, 26), UI.key("bad"))   # a band, in words: not colour alone
				f.draw_string(font, Vector2(r.position.x, r.end.y - 7), "URGENT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
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
			if it.state == "wait" and it.has("needs"):   # CROSS PREP: say what to prep and where, first
				sub = "PREP AT " + Kitchen.STATIONS[int(it.needs)]   # the button names the ingredient
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
		if not k.is_open(i) and r.size.x < 60.0:   # a narrow closed slot: dim, with the service it opens in
			f.draw_rect(r, Color(UI.panel_color(), 0.45))
			f.draw_rect(r, Color("4a5878"), false, 2.0)
			_plate(f, Rect2(r.position.x + 1, r.get_center().y - 24, r.size.x - 2, 48))
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, -4), "OPENS", HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(10), UI.DIM)
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 16), "S%d" % Kitchen.OPENS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(16), ink)
			continue
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
		f.draw_string(font, r.position + Vector2(0, 30), Kitchen.STATIONS[i] + (" x2" if i < Kitchen.PASS_IX and k.batch_at(i) == 2 else ""), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(14), ink)
		if i < k.pans.size() and not k.pans[i].is_empty():
			var p: Dictionary = k.pans[i]
			var up: bool = p.left <= 0
			var burning: bool = up and p.sat >= k.burn_after
			var tone := ("bad" if burning else "warn") if up else "info"
			if not low and up:
				f.draw_circle(r.get_center() + Vector2(0, 20), 46.0, Color(UI.key(tone), 0.2))
			var pc := r.get_center() + Vector2(0, 8)
			if not low:   # steam over a cooking pan, flame-flicker on one about to burn: the line is alive
				var tt := Time.get_ticks_msec() / 1000.0
				for w in 3:
					var ph := fposmod(tt * 0.7 + w / 3.0, 1.0)
					var sx := pc.x - 16.0 + w * 16.0 + sin(tt * 2.0 + w) * 4.0
					f.draw_circle(Vector2(sx, pc.y - 34.0 - ph * 34.0), 6.0 + ph * 6.0, Color(1, 1, 1, 0.22 * (1.0 - ph)))
				if burning:
					f.draw_arc(pc, 42.0 + sin(tt * 18.0) * 2.0, 0.0, TAU, 40, Color(MenuArt.EMBER, 0.6 + 0.4 * sin(tt * 11.0)), 3.0)
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
			var waiting := waiting_at(i)
			if waiting > 0 and not manned(i):   # 8.5 plan #3: dishes waiting and no cook here: red, and the frame throbs
				var th := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0) if not low and not (paused or over or between) else 1.0
				f.draw_rect(r.grow(2.0), Color(UI.key("bad"), 0.45 + 0.55 * th), false, 4.0)
				_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
				f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), _fit(font, "%d WAITING" % waiting, "%d WAIT" % waiting, r.size.x - 8, 17),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(17), UI.key("bad"))
			elif waiting > 0:   # work waiting here: what to FIRE (or PREP), and how much
				var verb := "PREP" if k.prep_pick(i).size() > 0 and k._waiting_for(i, 0).is_empty() else "FIRE"
				_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
				f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), _fit(font, "%d TO %s" % [waiting, verb], "%s %d" % [verb, waiting], r.size.x - 8, 17),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(17), UI.key("warn"))
		elif i == Kitchen.PASS_IX:
			for w in mini(k.window.size(), 3):   # plates up on the window, waiting for a runner, with their table
				var wx := r.position.x + 4 + w * ((r.size.x - 8) / 3.0)
				var wt := k.ticket(k.window[w].tid)
				_draw_fit(f, ART_DISHES[k.window[w].dish], Rect2(wx, r.position.y + 34, 28, 26))
				if not wt.is_empty():
					var hot: bool = wt.time <= 2
					f.draw_string_outline(font, Vector2(wx - 2, r.position.y + 70), "T%d" % wt.table, HORIZONTAL_ALIGNMENT_CENTER, 32, UI.font_size(12), 4, Color(0, 0, 0, 0.9))
					f.draw_string(font, Vector2(wx - 2, r.position.y + 70), "T%d" % wt.table, HORIZONTAL_ALIGNMENT_CENTER, 32, UI.font_size(12), UI.key("bad") if hot else ink)
			_plate(f, Rect2(r.position.x + 4, r.get_center().y - 14, r.size.x - 8, 32))
			var up := _fit(font, "%d TO RUN" % k.window.size(), "RUN %d" % k.window.size(), r.size.x - 8, 15) if not k.window.is_empty() else _fit(font, "RUN HERE", "RUN", r.size.x - 8, 15)
			f.draw_string(font, r.get_center() + Vector2(-r.size.x / 2, 10), up, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				UI.font_size(15), UI.key("good") if not k.window.is_empty() else ink)
	# Walk costs (movement pass, build-73 reviews: walking ate turns unseen): with a cook picked,
	# every other open station says what getting there costs, or TOO FAR.
	var command_cook := _press_cook if _dragging else sel
	if not k.crew[command_cook].out and not k.done and k.crew[command_cook].ap > 0:   # spent: the button already says NO MOVES
		var me: Dictionary = k.crew[command_cook]
		for i in Kitchen.STATIONS.size():
			if i == me.at or not k.is_open(i):
				continue
			var r := station_rect(i)
			var cost: int = k.move_cost(command_cook, i)
			var far: bool = cost > me.ap
			# The chip takes over the name row while a cook is picked (name + cost): above it a coach hint
			# hid it, at the foot it hid UP! / PLATE NOW (fresh-eyes PR #30).
			var nm: String = Kitchen.STATIONS[i] + (" x2" if i < Kitchen.PASS_IX and k.batch_at(i) == 2 else "")
			var wl := _fit(font, "TOO FAR" if far else ("FREE STEP" if cost == 0 else "WALK %d" % cost), "FAR" if far else ("FREE" if cost == 0 else "W%d" % cost), r.size.x - 8, 13)
			var chip := Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 36)   # two lines: the name, then the cost
			var tone_c: Color = UI.key("bad") if far else UI.key("info")
			f.draw_rect(chip, Color(0.03, 0.04, 0.06, 0.92))
			f.draw_rect(chip, tone_c, false, 2.0)
			f.draw_string(font, chip.position + Vector2(0, 15), nm, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, UI.font_size(13), ink)
			f.draw_string(font, chip.position + Vector2(0, 31), wl, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, UI.font_size(13), tone_c)
	# --- crew
	for c in k.crew.size():
		var cr: Dictionary = k.crew[c]
		var pos := cook_visual_pos(c)
		if cr.out:   # an empty spot where they stood: name + QUIT, right where you'd look for them
			if k.crew.any(func(o): return not o.out and cook_pos(k.crew.find(o)).distance_to(pos) < COOK_R * 2.0):
				continue   # a working cook stands here now: never cover them (blind review #3)
			f.draw_circle(pos, COOK_R, Color(0.08, 0.09, 0.12, 0.85))
			f.draw_arc(pos, COOK_R, 0.0, TAU, 32, UI.key("bad"), 2.0)
			f.draw_string(font, pos + Vector2(-COOK_R - 20, -2), cr.name, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2 + 40, UI.font_size(15), UI.DIM)
			f.draw_string(font, pos + Vector2(-COOK_R - 20, 16), "QUIT", HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2 + 40, UI.font_size(15), UI.key("bad"))
			continue
		if c == sel:
			f.draw_arc(pos, COOK_R + 7.0, 0.0, TAU, 48, UI.ACCENT, 4.0)
			f.draw_rect(Rect2(pos - Vector2(39, 54), Vector2(78, 104)), UI.ACCENT, false, 2.0)
		var near_cap: bool = cr.stress >= k.stress_cap - 2   # 8.5 plan #3: the face itself warns, not just the meter
		# 8.5 plan #2: who can still act, at a glance. A spent cook goes grey with DONE across the face;
		# the rest wear their moves left as a big number (the pips alone went unseen).
		var spent: bool = cr.ap <= 0
		var tex: Texture2D = CREW_SHEETS.get(cr.name)
		if tex != null:
			var row := crew_frame(c)
			var frame := 0 if low else int(Time.get_ticks_msec() / 180.0) % 2
			f.draw_texture_rect_region(tex, Rect2(pos - Vector2(37, 54), Vector2(74, 102)), Rect2(frame * 128, row * 176, 128, 176), Color(0.65, 0.65, 0.65) if spent else Color.WHITE)
		elif ART_COOKS.has(cr.name):
			_draw_fit(f, ART_COOKS[cr.name], Rect2(pos - Vector2(36, 36), Vector2(72, 72)))
		var np := Rect2(pos.x - 28, pos.y + COOK_R + 10, 56, 22)
		if near_cap:
			f.draw_rect(np, UI.key("bad"))
		else:
			_plate(f, np)
		f.draw_string(font, np.position + Vector2(0, 17), "%s L%d" % [cr.name, (cr.perks as Array).size() + 1], HORIZONTAL_ALIGNMENT_CENTER, np.size.x, UI.font_size(12), UI.BG if near_cap else ink)
		if near_cap:   # a red ring round the face, thick: shape as well as colour
			f.draw_arc(pos, COOK_R + 2.0, 0.0, TAU, 40, UI.key("bad"), 5.0)
		if spent:
			f.draw_circle(pos, COOK_R, Color(0, 0, 0, 0.2))
			var word := "FOX!" if cr.get("fox", false) else ("BREAK" if cr.get("brk", false) else "DONE")   # second wind / the fox: sitting out this turn
			f.draw_string_outline(font, pos + Vector2(-COOK_R, -2), word, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2, UI.font_size(17), 5, Color(0, 0, 0, 0.9))
			f.draw_string(font, pos + Vector2(-COOK_R, -2), word, HORIZONTAL_ALIGNMENT_CENTER, COOK_R * 2, UI.font_size(17),
				UI.key("warn") if word == "BREAK" else UI.DIM)
		else:
			var bc := pos + Vector2(COOK_R - 7, -COOK_R - 5)   # bigger (build-84 review: the badge was easy to miss)
			f.draw_circle(bc, 19.0, UI.key("info"))
			f.draw_arc(bc, 19.0, 0.0, TAU, 28, Color(0, 0, 0, 0.85), 2.5)
			f.draw_string(font, bc + Vector2(-19, 9), str(cr.ap), HORIZONTAL_ALIGNMENT_CENTER, 38, UI.font_size(25), Color(0.05, 0.06, 0.09))
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
			var box := Rect2(pos.x - sw / 2 + b * seg, pos.y + COOK_R + 34, seg - 2, 10)
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
			_plate(f, Rect2(pos.x - pw / 2, pos.y + COOK_R + 44, pw, 22))
			f.draw_string(font, Vector2(pos.x - pw / 2, pos.y + COOK_R + 61), sl, HORIZONTAL_ALIGNMENT_CENTER, pw,
				UI.font_size(14), UI.key("bad") if after > cr.stress else (UI.key(tone) if cr.stress > 0 else ink))
		if not cr.hand.is_empty():   # the plate in hand, on the cook's shoulder, plus its name
			_draw_fit(f, ART_DISHES[cr.hand.dish], Rect2(pos + Vector2(COOK_R - 18, -COOK_R - 6), Vector2(40, 40)))
			_plate(f, Rect2(pos + Vector2(-50, COOK_R + 22), Vector2(100, 24)))
			f.draw_string(font, pos + Vector2(-60, COOK_R + 40), "> " + cr.hand.dish, HORIZONTAL_ALIGNMENT_CENTER, 120, UI.font_size(15), UI.key("good"))
	if _dragging and _press_cook >= 0:
		var i := station_at(_drag_pos)
		if i >= 0:
			var r := station_rect(i)
			var valid := _can_walk(_press_cook, i)
			var col := UI.key("good") if valid else UI.key("bad")
			f.draw_rect(r, col, false, 5.0)
			var msg := "DROP: %d MOVES" % k.move_cost(_press_cook, i) if valid else "CANCEL"
			f.draw_string_outline(font, r.position + Vector2(0, r.size.y - 12), msg, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(14), 5, Color.BLACK)
			f.draw_string(font, r.position + Vector2(0, r.size.y - 12), msg, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI.font_size(14), col)
		f.draw_line(cook_visual_pos(_press_cook), _drag_pos, UI.ACCENT, 3.0)
	_draw_fox(f)
	_draw_fx(f)


var _fox_t0 := 0   # when the fox popped up (ms), for its pop-in


## The studio fox (docs/MASCOT.md): its head pops up over the cook chasing it, for that one turn.
func _draw_fox(f: Control) -> void:
	var font := ThemeDB.fallback_font
	for c in k.crew.size():
		if not k.crew[c].get("fox", false) or k.crew[c].out:
			continue
		var pos := cook_visual_pos(c)
		var age := float(Time.get_ticks_msec() - _fox_t0) / 1000.0 if _fox_t0 > 0 else 9.0
		var pop := clampf(age / 0.35, 0.0, 1.0)
		var sz := 104.0 * (0.4 + 0.6 * pop)
		var bob := 0.0 if _settings.get_value("low_graphics") else sin(age * 6.0) * 4.0
		# Beside the cook, on the side with more room, never over their face (the autoplay shot hid MO).
		var right := pos.x < f.size.x / 2.0
		var x := pos.x + COOK_R + 26.0 if right else pos.x - COOK_R - 26.0 - sz
		var at := Vector2(clampf(x, 0.0, f.size.x - sz), pos.y - sz * 0.75 + bob)
		f.draw_texture_rect(ART_FOX, Rect2(at, Vector2(sz, sz)), false)
		if pop >= 1.0:
			_plate(f, Rect2(at.x, at.y + sz - 4, sz, 24))
			f.draw_string(font, Vector2(at.x, at.y + sz + 14), "FOX!", HORIZONTAL_ALIGNMENT_CENTER, sz, UI.font_size(16), UI.key("warn"))


# ---------------------------------------------------------------- pause + game over

func pause() -> void:
	_cancel_gesture()
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
	sheet_box.add_child(UI.button("CREW", open_crew_card))
	sheet_box.add_child(UI.button("HOW TO PLAY", func(): HowToPlay.open(self)))
	sheet_box.add_child(UI.button("SETTINGS", func(): SettingsSheet.open(self)))
	sheet_box.add_child(UI.button("REPORT A BUG", func(): BugReport.open(self)))
	sheet_box.add_child(UI.button("QUIT TO TITLE", quit_to_title))


## Review every cook's role, level, productive experience and earned perks.
func open_crew_card() -> void:
	var box := UI.sheet(self, 500)
	box.add_child(UI.label("YOUR CREW", 30, UI.ACCENT))
	box.add_child(UI.label("One free perk action per cook per turn.", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 460
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for nm in ["DEV", "MO", "JO"]:
		if nm == "JO" and not perks.has("temp"):
			continue
		var have: Array = cook_perks.get(nm, [])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		rows.add_child(row)
		var atlas := AtlasTexture.new()
		atlas.atlas = CREW_SHEETS[nm]
		atlas.region = Rect2(0, 0, 128, 176)
		var pic := TextureRect.new()
		pic.texture = atlas
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(78, 108)
		row.add_child(pic)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := UI.label("%s  LV %d  |  %s" % [nm, have.size() + 1, Kitchen.cook_role(have)], 20, UI.ACCENT)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(title)
		var details := "%d XP" % int(cook_xp.get(nm, 0))
		if gone.has(nm):
			details += "  |  WALKED OUT"
		for id in have:
			details += "\n%s: %s" % [Kitchen.PERKS[id][0], Kitchen.PERKS[id][1]]
		if have.is_empty():
			details += "\nNo perks yet"
		var body := UI.label(details, 18, UI.DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(body)
	box.add_child(UI.button("DONE", func(): UI.close_sheet(box)))


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
	var fresh := UI.label("RETRY keeps your upgrades and bank.\nNEW NIGHT starts back at service 1.", 20, UI.DIM)
	fresh.name = "Fresh"
	sheet_box.add_child(fresh)
	# 8.5 pass: a loss keeps a foothold. RETRY replays the service you lost with tonight's upgrades.
	var retry := MenuArt.primary(UI.button("RETRY SERVICE %d" % level, retry_service, 88))
	retry.name = "Retry"
	var again := UI.button("NEW NIGHT", func(): get_node("/root/Loader").go("res://scenes/game.tscn"), 88)
	var title := UI.button("TITLE", quit_to_title)
	sheet_box.add_child(retry)
	sheet_box.add_child(again)
	sheet_box.add_child(title)
	for b in [retry, again, title]:   # a tap meant for the board doesn't restart the night: a beat before they work
		b.disabled = true
		get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(b): b.disabled = false)


## Replay the service that was lost: same night, same bank and upgrades, fresh tickets.
func retry_service() -> void:
	_save.write({"level": level, "score": _night_before, "cash": cash, "perks": perks.duplicate(),
		"cook_perks": cook_perks.duplicate(true), "cook_xp": cook_xp.duplicate()})   # earned perks stay; a pending pick was for the service you beat; a walked-out cook comes back
	get_node("/root/Loader").go("res://scenes/game.tscn")


func _notification(what: int) -> void:
	match what:
		# The phone took the app away (call, home button, notification shade): pause + save.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_cancel_gesture()
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
