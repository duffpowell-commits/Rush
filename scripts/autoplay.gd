extends Node
const Upgrades = preload("res://scripts/upgrades.gd")
const KitchenRules = preload("res://scripts/kitchen.gd")
## Autoload "Autoplay": a bot that plays the whole flow with real taps and saves screenshots.
## Off unless the game is started with `-- --autoplay`. Run it (needs a screen, so xvfb):
##   tools/autoplay.sh            -> docs/renders/flow_*.png, prints one PASS line per check
## It ends with "AUTOPLAY PASS" or "AUTOPLAY FAIL <step>"; CI fails without the PASS or on any FAIL line.
## Uses its own settings/save folder (XDG_DATA_HOME in the script), never the player's.
##
## When the game grows, extend `_run()`: drive the real game the way a player would, and add a
## PASS line for each thing that must keep working.

var shots := ""
var clip := ""                          # --clip=DIR: save a gameplay clip's frames there
const UI = preload("res://scripts/ui.gd")
const Kitchen = preload("res://scripts/kitchen.gd")
const CLIP_SECS := 15.0                 # vertical 9:16 (the game is portrait), sized for Shorts/Reels/TikTok
var failed := false
var _start_ms := 0                      # when game code first runs (engine/driver start-up excluded)


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	if not "--autoplay" in OS.get_cmdline_user_args():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		if a.begins_with("--clip="):
			clip = a.trim_prefix("--clip=")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	get_tree().create_timer(240.0).timeout.connect(func(): _fail("timeout"))
	_run.call_deferred()


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _wait_scene("Boot")
	# Disable the timer in this run so only the tap can dismiss the card.
	get_tree().current_scene.get_node("StudioSplash/DisplayTimer").stop()
	await _shot("studio_splash")
	await _click("Skip splash")
	_check(_find("Skip splash") == null, "STUDIO SPLASH PASS (Skip splash dismisses the publisher card)")
	await _wait_scene("Intro")
	var intro_ms := Time.get_ticks_msec()
	await _frames(10)
	_shot("intro")
	var skip_ms := Time.get_ticks_msec()
	await _click("SKIP")
	await _wait_scene("Title")
	# Game start -> intro on screen, plus SKIP -> title. Driver start-up (10 s of ALSA/llvmpipe on a CI
	# box, not a phone) and the bot's own frames and screenshot don't count.
	var boot_ms := (intro_ms - _start_ms) + (Time.get_ticks_msec() - skip_ms)
	_check(boot_ms < 10000, "BOOT PASS (title ready %.1f s after game start)" % (boot_ms / 1000.0))
	# Quality tier: picked on first launch and saved; LOW really lowers; then HIGH for the checks below.
	var Q = preload("res://scripts/quality.gd")
	var st: Node = get_node("/root/Settings")
	var picked: int = st.get_value("tier")
	Q.apply(get_tree(), 0)
	var low_ok: bool = st.get_value("low_graphics") and is_equal_approx(get_tree().root.scaling_3d_scale, 0.7)
	Q.apply(get_tree(), 2)
	var high_ok: bool = not st.get_value("low_graphics") and is_equal_approx(get_tree().root.scaling_3d_scale, 1.0)
	_check(picked >= 0 and Q.last_ms > 0.0 and low_ok and high_ok,
		"TIER PASS (first launch picked %s, test frame %.1f ms; LOW and HIGH apply)" % [Q.NAMES[maxi(picked, 0)], Q.last_ms])
	await _frames(10)
	_shot("title")
	_check(_find("CONTINUE") == null, "TITLE PASS (no save yet)")
	# Menu polish (Nov 25): painted backdrop + drawn logo, HOW TO PLAY opens and closes, and a caption
	# moves to the top while a sheet is up so it never covers a button.
	var title := get_tree().current_scene
	var dressed: bool = title.get_node_or_null("Backdrop") != null and title.get_node_or_null("Logo") != null
	await _click("HOW TO PLAY")
	var how_open := _find("GOT IT") != null
	var subs: Node = get_node("/root/Subs")
	subs.cue("[test caption]")
	await _frames(3)
	var subs_top: bool = subs._bg.anchor_top < 0.2
	_shot("how_to_play")
	await _click("GOT IT")
	await _frames(3)
	subs.clear()
	_check(dressed and how_open and subs_top and _find("GOT IT") == null,
		"MENU PASS (title art + logo, HOW TO PLAY opens and closes, captions clear the sheet)")
	await _click("SETTINGS")
	await _click("CREDITS")
	_check(_has_label("Published by 3 Eyed Fox Studios"), "PUBLISHER CREDITS PASS")
	await _click("DONE")
	await _click("DONE")
	await _click("NEW GAME")
	# Why (Nov 24 review): Game loads in the background with the title still current; that counts as play.
	var upd: Node = get_node("/root/Updater")
	var mid_load: bool = not get_node("/root/Loader").busy() or upd._in_play()
	await _wait_scene("Game")
	var game := get_tree().current_scene
	# Why (Nov 23 review): the open-app update poll must never cover live play.
	var mine: int = upd.my_code
	upd.my_code = 4
	upd._on_version(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"code": 5}'.to_utf8_buffer())
	var quiet: bool = upd._in_play() and upd.box == null
	# Close the offer the way Android back does (free the sheet): the build must stay put off.
	upd.new_code = 5
	upd._offer()
	var opened: bool = upd.box != null
	upd.UI.close_sheet(upd.box)
	await get_tree().process_frame
	var held: bool = opened and upd.box == null and upd.dismissed == 5 \
		and not upd.should_offer(5, 4, upd.dismissed) and upd.should_offer(6, 4, upd.dismissed)
	# A sheet already up when Game enters is withdrawn, without counting as LATER.
	upd.dismissed = 0
	upd._offer()
	upd._on_scene_changed()
	await get_tree().process_frame
	var withdrawn: bool = upd.box == null and upd.dismissed == 0
	upd.my_code = mine
	upd.new_code = 0
	upd.dismissed = 0
	_check(quiet and held and mid_load and withdrawn, "UPDATER QUIET PASS (no sheet mid-load or mid-play; one already up leaves when Game enters; back on the offer holds that build)")
	var ld: Node = get_node("/root/Loader")
	_check(ld.loads >= 2 and not ld.busy(), "LOAD PASS (%d scenes loaded in the background, %d frames drawn meanwhile)" % [ld.loads, ld.frames_while_loading])

	# Play: a real service. First a player's taps (pick DEV, walk to GRILL, FIRE there), then the
	# greedy bot cooks turn by turn until a ticket goes out.
	var start_score: int = game.score
	var k: Object = game.k
	var fired_by_tap := false
	var coach_up: bool = game.has_node("Coach_fire")
	await _shot("first_minute")
	# Walk MO from FRY to the PASS with a tap: one action, because the closed saute and cold
	# stations in service 1 are walked past for free. A tap on a closed station goes nowhere.
	await _tap_at(game.field.get_global_transform() * game.cook_pos(1))
	await _tap_at(game.field.get_global_transform() * game.station_rect(2).get_center())
	var closed_ok: bool = k.crew[1].at == 1 and "OPENS IN SERVICE 2" in game.note.text
	await _tap_at(game.field.get_global_transform() * game.station_rect(Kitchen.PASS_IX).get_center())
	var moved: bool = closed_ok and k.crew[1].at == Kitchen.PASS_IX and k.crew[1].ap == k.ap - 1
	await _tap_at(game.field.get_global_transform() * game.cook_pos(0))
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	await _frames(2)
	fired_by_tap = k.pans[0].get("dish", "") == "BURGER"
	var fire_fx: bool = game.fx.any(func(e): return e.kind == "spark")
	_check(coach_up and moved and fired_by_tap, "TAP PASS (hint shown, closed SAUTE refused, MO walked FRY->PASS past closed stations for 1 action, DEV fired the burger)")
	# Tap a station, get its cook (Duff, Nov 25): with MO picked, a tap on the GRILL (DEV stands
	# there) picks DEV and sends nobody anywhere. With DEV stepped off, the GRILL still picks DEV,
	# because his burger is on it: the pan wears his initial.
	game.sel = 1   # MO picked earlier (not by a face tap just now)
	game._after_move()
	var mo_ap: int = k.crew[1].ap
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	var picked_here: bool = game.sel == 0 and k.crew[1].at == Kitchen.PASS_IX and k.crew[1].ap == mo_ap
	game.sel = 1
	k.crew[0].at = 1
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	var picked_pan: bool = game.sel == 0 and k.crew[0].at == 1 and k.crew[1].at == Kitchen.PASS_IX and k.crew[1].ap == mo_ap
	# A second tap on the same station hands off: MO (picked before) walks to DEV's pan after all.
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	var handoff: bool = game.sel == 1 and k.crew[1].at == 0 and k.crew[0].at == 1
	k.crew[1].at = Kitchen.PASS_IX
	k.crew[1].ap = mo_ap
	k.crew[0].at = 0
	game._after_move()
	await _shot("station_pick")
	_check(picked_here and picked_pan and handoff, "STATION PICK PASS (MO picked, GRILL tap picked DEV who stands there; with DEV away it picked him by his burger; a 2nd GRILL tap sent MO to it)")
	# Movement pass (build-73 reviews): a face tap always wins. Tap MO, then the GRILL where DEV
	# stands: MO walks over instead of the tap swapping to DEV. A walk too far says so.
	await _tap_at(game.field.get_global_transform() * game.cook_pos(1))
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	var face_went: bool = game.sel == 1 and k.crew[1].at == 0 and k.crew[1].ap == mo_ap - k.walk_cost(Kitchen.PASS_IX, 0)
	game.field.queue_redraw()
	await _frames(2)
	await _shot("walk_costs")
	k.crew[1].ap = 0
	game._after_move()
	await _tap_at(game.field.get_global_transform() * game.station_rect(Kitchen.PASS_IX).get_center())
	var far_said: bool = k.crew[1].at == 0 and game.note.text == "MO: NO MOVES LEFT" and game.fx.any(func(e): return e.kind == "text" and e.text == "NO MOVES")
	k.crew[1].ap = 1
	k.crew[1].at = 0
	game.sel = 1
	k.all_open = true   # every stop counts: GRILL to PASS is 4 moves
	game._after_move()
	await _tap_at(game.field.get_global_transform() * game.station_rect(Kitchen.PASS_IX).get_center())
	var far_note: String = game.note.text
	k.all_open = false
	far_said = far_said and k.crew[1].at == 0 and far_note == "TOO FAR: MO NEEDS 4 MOVES, HAS 1"
	k.crew[1].at = Kitchen.PASS_IX
	k.crew[1].ap = mo_ap
	game.sel = 1
	game._after_move()
	_check(face_went and far_said, "MOVE PASS (MO tapped by face walked to DEV's GRILL; a spent walk said NO MOVES; a long one said '%s')" % far_note)
	# The next hint follows by itself: after FIRE, END TURN is taught.
	var next_hint := false
	for i in 60:
		await _frames(1)
		if game.has_node("Coach_end_turn"):
			next_hint = true
			break
	await _shot("hint_end_turn")
	# The hint sits between the NEXT line and the stations, never over the station names (it did on a
	# tall phone's web browser, Nov 25).
	var hint_rect: Rect2 = (game.get_node("Coach_end_turn") as Control).get_global_rect() if next_hint else Rect2()
	var st_top: float = (game.field.get_global_transform() * game.station_rect(0).position).y
	_check(next_hint and not game.has_node("Coach_fire") and hint_rect.end.y <= st_top + 1.0,
		"COACH PASS (FIRE hint gone, END TURN hint up, %d px above the stations)" % int(st_top - hint_rect.end.y))
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until and game.score < start_score + 1 and not game.over:
		game.bot_play_turn()
		await _frames(3)
	await _shot("game")
	_check(game.score > start_score, "PLAY PASS (%d ticket out by %s)" % [game.score, game.k.clock()])
	# Nov 25 playtest features, by real taps on a set-up minute (then the service is put back):
	# tap a ticket to cook it first, RUSH a cooking pan, plates go up on the pass window and MO runs one.
	var real: Dictionary = game.k.to_dict()
	var kk: Object = game.k
	kk.tickets = [
		{"id": 901, "table": 21, "items": [{"dish": "STEAK", "state": "wait"}], "time": 4, "big": false},
		{"id": 902, "table": 22, "items": [{"dish": "BURGER", "state": "wait"}, {"dish": "FRIES", "state": "cooking"}], "time": 8, "big": false}]
	kk.pans = [{}, {"tid": 902, "dish": "FRIES", "left": 0, "sat": 0, "rushed": false}, {}, {}]
	kk.window = []
	kk.crew[0].at = 0
	kk.crew[1].at = 1
	for cr in kk.crew:
		cr.ap = kk.ap
		cr.out = false
		cr.stress = 0
		cr.hand = {}
	game.sel = 0
	game.pick_tid = 0
	game._after_move()
	var fire_default: String = game.act_btn.text
	await _tap_at(game.field.get_global_transform() * game.ticket_rect(1).get_center())   # table 22: less urgent
	var pick_ok: bool = game.pick_tid == 902 and game.act_btn.text.get_slice("\n", 0) == "DEV: FIRE T22"
	var pick_dbg := "default '%s', after tap pick %d '%s'" % [fire_default, game.pick_tid, game.act_btn.text]
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())   # DEV's own station: act
	pick_ok = pick_ok and kk.pans[0].get("tid", 0) == 902 and fire_default.get_slice("\n", 0) == "DEV: FIRE T21"
	_check(pick_ok, "PICK PASS (button said FIRE T21, tapped table 22's ticket, FIRE cooked its burger; %s, pan %s)" % [pick_dbg.replace("\n", " / "), str(kk.pans[0].get("tid", 0))])
	# Tap a dish (Duff, Nov 25): table 22 now wants a burger and a steak, both grill. A tap on the
	# STEAK row picks that dish: the button names it and FIRE cooks it, not the burger listed first.
	var keep_items: Array = kk.tickets[1].items.duplicate(true)
	var keep_pan: Dictionary = kk.pans[0].duplicate()
	var keep_ap: int = kk.crew[0].ap
	kk.tickets[1].items = [{"dish": "BURGER", "state": "wait"}, {"dish": "STEAK", "state": "wait"}]
	kk.pans[0] = {}
	kk.crew[0].ap = kk.ap
	game.pick_tid = 0
	game.pick_ix = -1
	game._after_move()
	var r22: Rect2 = game.ticket_rect(1)
	var steak_row := Vector2(r22.get_center().x, r22.position.y + game.DISH_ROW0 + game.DISH_ROW * 1.5)
	await _tap_at(game.field.get_global_transform() * steak_row)
	var dish_label: String = game.act_btn.text
	await _frames(2)
	await _shot("dish_pick")
	await _tap_at(game.field.get_global_transform() * game.station_rect(0).get_center())
	_check(game.pick_ix == -1 and dish_label == "DEV: FIRE STEAK" and kk.pans[0].get("dish", "") == "STEAK"
		and kk.tickets[1].items[0].state == "wait",
		"DISH PICK PASS (tapped T22's STEAK row: button said '%s', FIRE cooked the steak, the burger still waits)" % dish_label)
	kk.tickets[1].items = keep_items   # back to the minute the next checks expect
	kk.pans[0] = keep_pan
	kk.crew[0].ap = keep_ap
	game.pick_tid = 0
	game._after_move()
	var left0: int = kk.pans[0].left
	var rush_label: String = game.act_btn.text
	game.act()
	_check(rush_label == "DEV: RUSH +1 STRESS" and kk.pans[0].left == left0 - 1 and kk.crew[0].stress == kk.rush_stress,
		"RUSH PASS (burger %d -> %d minutes, DEV stress %d)" % [left0, kk.pans[0].left, kk.crew[0].stress])
	await _tap_at(game.field.get_global_transform() * game.cook_pos(1))
	await _tap_at(game.field.get_global_transform() * game.station_rect(1).get_center())   # MO plates the fries
	var up: bool = kk.window.size() == 1 and kk.crew[1].hand.is_empty()
	game.field.queue_redraw()
	await _shot("pick_rush_window")
	game.end_turn()   # MO spent an action plating: a fresh turn to walk to the pass and run
	await _tap_at(game.field.get_global_transform() * game.station_rect(Kitchen.PASS_IX).get_center())
	var on_pass: bool = kk.crew[1].at == Kitchen.PASS_IX and game.act_btn.text == "MO: RUN"
	game.act()
	var ran: bool = kk.window.is_empty() and kk.ticket(902).items[1].state == "served"
	_check(up and on_pass and ran, "WINDOW PASS (fries plated up on the window, MO walked to the pass and ran them)")
	# Juice: FIRE threw sparks, the run floated its tips, and a red ticket throbs (words ride along).
	var run_fx: bool = game.fx.any(func(e): return e.kind == "text")
	await _shot("juice")
	_check(fire_fx and run_fx, "JUICE PASS (sparks on FIRE, floating words on RUN, %d effects live)" % game.fx.size())
	# Real sound (Nov 25): each action plays its own kitchen recording, and the busy layer runs under the jazz.
	var au := get_node("/root/Audio")
	var heard: bool = ["fire", "rush", "plate", "bell"].all(func(n): return au.played.has(n))
	var real_clips: bool = ["fire", "rush", "plate", "bell", "burn", "walk", "door", "ticket", "gameover", "level", "click",
		"music_loop", "music_busy"].all(func(n): return au._stream(n) is AudioStreamOggVorbis)
	var on_first: bool = au._combat.playing
	au.music("music_loop")   # back to the title: the busy layer stops...
	var off_on_title: bool = not au._combat.playing
	au.music_layers("music_loop", "music_busy")   # ...and comes back on the next service
	_check(heard and real_clips and on_first and off_on_title and au._combat.playing, "SOUND PASS (FIRE sizzle, RUSH, plate, pass bell played; 13 real clips; busy layer on, off on the title, back on re-entry)")
	game.k = Kitchen.new()
	game.k.from_dict(real)
	game.pick_tid = 0
	game._after_move()
	# Both cooks at an end station stay fully on screen, a touch target apart.
	var at_before: Array = [game.k.crew[0].at, game.k.crew[1].at]
	var edge_ok := true
	var gap := 0.0
	for s in [0, Kitchen.PASS_IX]:
		game.k.crew[0].at = s
		game.k.crew[1].at = s
		var a: Vector2 = game.cook_pos(0)
		var b: Vector2 = game.cook_pos(1)
		gap = absf(a.x - b.x)
		for p in [a, b]:
			edge_ok = edge_ok and p.x - game.COOK_R >= 0.0 and p.x + game.COOK_R <= game.field.size.x
		edge_ok = edge_ok and gap >= game.COOK_R * 2.0 + UI.GAP - 0.5
	game.field.queue_redraw()
	await _shot("two_cooks_edge")
	game.k.crew[0].at = at_before[0]
	game.k.crew[1].at = at_before[1]
	game.field.queue_redraw()
	_check(edge_ok, "EDGE PASS (two cooks at GRILL and PASS on screen, %d apart)" % int(gap))
	var bat: Node = get_node("/root/Battery")
	var playing_full: bool = bat.state == "play" and Engine.max_fps == 60

	# Finish service 1: a grade sheet lands, NEXT SERVICE starts service 2 (the checkpoint).
	var guard := 0
	while not game.between and not game.over and guard < 80:
		game.bot_play_turn()
		await _frames(1)
		guard += 1
	await _frames(5)
	await _shot("grade")
	var grade_node: Node = game.find_child("Grade", true, false)
	var letter: String = grade_node.text if grade_node != null else "?"
	# Grades + pace (Nov 25): the sheet shows the points behind the letter; PACE and the house's read move the load.
	var pst: Node = get_node("/root/Settings")
	var points_ok: bool = game.find_child("Points", true, false) != null and str(game.find_child("Points", true, false).text).contains("POINTS")
	var ease_was = pst.get_value("house_ease")
	pst.set_value("house_ease", 0)
	pst.set_value("pace", 0)
	var relaxed: Dictionary = game.pace_adjust()
	var t_relaxed: int = game.tickets_for(1)
	pst.set_value("pace", 2)
	var t_slammed: int = game.tickets_for(1)
	pst.set_value("pace", 1)
	var t_normal: int = game.tickets_for(1)
	game._house_reads("F")
	var eased: bool = int(pst.get_value("house_ease")) == 1 and game.tickets_for(1) == t_normal - 1
	game._house_reads("A+")
	var back: bool = int(pst.get_value("house_ease")) == 0
	pst.set_value("house_ease", ease_was)
	_check(points_ok and relaxed.time == 2 and t_relaxed < t_normal and t_slammed > t_normal and eased and back,
		"PACE PASS (grade %s with its points; tickets relaxed %d / normal %d / slammed %d; an F eases a ticket, an A+ takes it back)" % [letter, t_relaxed, t_normal, t_slammed])
	# The grade sheet fits at HUGE text with its longest content (walks, critic, the house's read).
	var real_box: Node = game.sheet_box
	var ts_was = pst.get_value("text_size")
	pst.set_value("text_size", 3)
	await _frames(2)
	var critic_was: String = game.k.critic
	game.k.critic = "walked"   # worst case carries the critic's stamp too (8.5 pass)
	game._grade_sheet("D", {"total": 47, "out": 43, "speed": 9, "pans": 10, "walks": -20, "critic": -8},
		"The floor eases off a ticket.", {"service": 3, "served": 7, "total": 9, "walked": 2, "tips": 148})
	var tb: VBoxContainer = game.sheet_box
	tb.add_child(UI.button("SHOP ($148) NEW!", func(): pass))
	tb.add_child(preload("res://scripts/menu_art.gd").primary(UI.button("NEXT SERVICE", func(): pass, 96)))
	tb.add_child(UI.button("TITLE", func(): pass))
	await _frames(4)
	var pr: Rect2 = (tb.get_parent() as Control).get_global_rect()
	var critic_lbl: Node = tb.find_child("Critic", true, false)
	var critic_txt: String = critic_lbl.text if critic_lbl != null else ""
	game.k.critic = critic_was
	var vh: float = get_viewport().get_visible_rect().size.y
	await _shot("grade_huge")
	UI.close_sheet(tb)
	game.sheet_box = real_box
	pst.set_value("text_size", ts_was)
	await _frames(2)
	_check(pr.position.y >= 0.0 and pr.end.y <= vh and critic_txt == "CRITIC WALKED  -8",
		"GRADE FIT PASS (worst-case sheet at HUGE text with the critic's stamp '%s': %d px of %d)" % [critic_txt, int(pr.size.y), int(vh)])
	var graded: bool = game.between and grade_node != null and _find("NEXT SERVICE") != null
	# Tips carry over: they're banked, the SHOP spends them, the upgrade shapes service 2 and is saved.
	var tips1: int = game.k.tips
	var banked: bool = game.cash == tips1 and tips1 >= 25
	var shop_new: bool = _find("SHOP") != null and _find("SHOP").text.contains("NEW")   # NEW! before the first visit
	await _click("SHOP")
	await _frames(3)
	await _shot("shop")
	await _click("FAMILY MEAL")
	await _frames(3)
	var bought: bool = game.perks.has("meal") and game.cash == tips1 - 25 and _find("FAMILY MEAL") == null
	await _click("DONE")
	var shop_b: Button = _find("SHOP")
	var new_gone: bool = shop_new and shop_b != null and not shop_b.text.contains("NEW")   # looked once: no more NEW!
	_check(new_gone, "SHOP NEW PASS (NEW! before the visit, then '%s')" % (shop_b.text if shop_b != null else "-"))
	await _tray_checks(game, pst)
	await _polish_checks(game)
	await _click("NEXT SERVICE")
	await _frames(5)
	var sv: Dictionary = get_node("/root/Save").read()
	_check(banked and bought and game.k.stress_cap == int(game.stress_cap) + 1 and (sv.get("perks", []) as Array).has("meal")
		and int(get_node("/root/Settings").get_value("best_service")) >= 1,
		"SHOP PASS (banked $%d, bought FAMILY MEAL, stress cap %d in service 2, saved, best night kept)" % [tips1, game.k.stress_cap])
	_check(graded and game.level == 2 and not game.between,
		"GRADE PASS (service 1 graded %s, NEXT SERVICE -> service %d)" % [letter, game.level])
	# Service 2 opens on its twist card (bus tour, fritz, VIP or critic); HEARD! closes it.
	# The line grows by service: saute opens in service 2 and the card says so (cold opens in service 3).
	var ns: Node = game.find_child("NewStation", true, false)
	_check(ns != null and "SAUTE" in ns.text and game.k.is_open(2) and not game.k.is_open(3),
		"STATIONS PASS (service 2 opens %s; cold still closed)" % (ns.text if ns != null else "nothing"))
	var twist: Node = game.find_child("Twist", true, false)
	var twist_name: String = twist.text if twist != null else "?"
	await _shot("tonight")
	# A phone call / back gesture on the card pauses on top of it; after RESUME, HEARD! still works.
	game.pause()
	await _frames(3)
	await _click("RESUME")
	await _frames(3)
	# Focus-out pauses on top again; then the back gesture closes the pause (not stuck paused).
	game.pause()
	await _frames(3)
	var back_paused: bool = game.paused
	game._go_back()
	await _frames(3)
	var back_resumed: bool = not game.paused and _find("HEARD!") != null
	await _click("HEARD!")
	await _frames(3)
	var sheets_left: int = get_tree().get_nodes_in_group("sheet").filter(func(n): return not n.is_queued_for_deletion()).size()
	_check(game.k.event != "" and twist_name == game.k.EVENTS[game.k.event][0] and _find("HEARD!") == null and sheets_left == 0
		and back_paused and back_resumed and not game.paused,
		"TWIST PASS (service 2 twist %s shown; pause + back on top resume cleanly, HEARD! still closes it)" % twist_name)
	var saved: Dictionary = get_node("/root/Save").read()
	_check(int(saved.get("level", 0)) == 2, "AUTOSAVE PASS (level 2 saved)")
	# A few minutes into service 2, so CONTINUE has a service in progress to pick back up.
	for i in 3:
		game.bot_play_turn()
		await _frames(1)
	var mid_turn: int = game.k.turn
	var mid_walked: int = game.k.walked
	var mid_tickets: int = game.k.tickets.size()

	# Phone interruption: the app loses focus -> pause + save.
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(10)
	_check(game.paused and _find("RESUME") != null, "INTERRUPT PASS (paused on focus loss)")
	var bg_low: bool = bat.state == "background" and Engine.max_fps == 5
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(3)
	_check(playing_full and bg_low and bat.state == "saver" and Engine.max_fps == 30,
		"BATTERY PASS (play 60 fps, background 5 fps, paused 30 fps)")
	bat.idle_secs = INF                         # the bot plays without input events: don't treat it as idle
	_shot("pause")

	# Settings from the pause menu: bigger text, colorblind, left-handed.
	await _click("SETTINGS")
	await _frames(10)
	_shot("settings")
	await _click("TEXT SIZE")
	await _frames(5)
	await _click("COLORBLIND")
	await _click("LEFT-HANDED")
	await _frames(10)
	_shot("settings_changed")
	var s: Node = get_node("/root/Settings")
	_check(s.get_value("colorblind") and s.get_value("left_handed") and int(s.get_value("text_size")) == 2,
		"SETTINGS PASS (saved)")
	await _click("DONE")
	await _frames(5)

	# Quit to title, CONTINUE, back where we were.
	await _click("QUIT TO TITLE")
	await _wait_scene("Title")
	await _frames(10)
	_shot("title_continue")
	await _click("CONTINUE")
	await _wait_scene("Game")
	game = get_tree().current_scene
	_check(game.level == 2 and game.k.turn == mid_turn and game.k.walked == mid_walked and game.k.tickets.size() == mid_tickets
		and game.lives == 3 - mid_walked,
		"RESUME PASS (service %d picked up at %s, %d walked)" % [game.level, game.k.clock(), game.k.walked])
	await _frames(10)
	_shot("game_lefthanded")

	# Android back = pause, back again = resume.
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(5)
	_check(game.paused, "BACK PASS (back button pauses)")
	await _click("RESUME")
	await _frames(5)

	# Do nothing and keep ending turns: tables walk, GAME OVER.
	var waited := 0
	while not game.over and waited < 200:
		game.end_turn()
		await _frames(1)
		waited += 1
	await _frames(10)
	var guarded: bool = game.over and game.find_child("Reason", true, false) != null and _find("NEW NIGHT") == null   # a beat before it takes taps (stray board taps restarted the night)
	await get_tree().create_timer(1.2).timeout
	_shot("gameover")
	var reason: Node = game.find_child("Reason", true, false)
	var fresh: Node = game.find_child("Fresh", true, false)
	_check(fresh != null and "service 1" in fresh.text and guarded and game.over and _find("NEW NIGHT") != null and not get_node("/root/Save").exists() and reason != null and "WALKED" in reason.text,
		"GAMEOVER PASS (game over screen says why, NEW NIGHT waits a beat and says it starts at service 1, save cleared)")
	# 8.5 pass: RETRY replays the lost service with tonight's bank and upgrades.
	var lost_lvl: int = game.level
	game.cash = 77
	game.perks = ["tray"]
	var perks_lost: Array = game.perks.duplicate()
	var retry_ok: bool = _find("RETRY SERVICE %d" % lost_lvl) != null
	var old_game: Node = game
	await _click("RETRY SERVICE")
	for i in 600:
		if get_tree().current_scene != old_game and get_tree().current_scene != null and get_tree().current_scene.name == "Game":
			break
		await _frames(1)
	await _frames(5)
	game = get_tree().current_scene
	_check(retry_ok and game != old_game and game.level == lost_lvl and game.cash == 77 and game.perks == perks_lost and not game.over and game.k.served == 0,
		"RETRY PASS (RETRY SERVICE %d replays it with $%d and %s kept)" % [game.level, game.cash, str(game.perks)])
	# TEMP COOK: bought in the shop, a third cook at the pass for one service, tappable, drawn, then
	# gone; the next one costs double (8.5 plan #2), and two upgrades bring one more table.
	game.cash = 300
	var t_before: int = game.tickets_for(game.level)
	game.open_shop()
	await _frames(4)
	await _click("TEMP COOK")
	await _frames(4)
	var temp_bought: bool = game.perks.has("temp") and game.temp_buys == 1 and game.cash == 255
	var again_txt: String = ""
	await _click("DONE")
	game.perks.erase("temp")
	game.open_shop()
	await _frames(4)
	var again_b: Node = get_tree().root.find_child("Buy_temp", true, false)
	again_txt = again_b.text if again_b != null else "-"
	await _click("DONE")
	game.perks.append("temp")
	var t_after: int = game.tickets_for(game.level)
	_check(temp_bought and again_txt.contains("$90") and t_after == t_before + 1,
		"PUSHBACK PASS (TEMP COOK $45, then '%s'; two upgrades: %d -> %d tickets)" % [again_txt.get_slice("\n", 0), t_before, t_after])
	game._new_service()
	game._after_move()
	await _frames(20)
	await _shot("temp_cook")
	var three: bool = game.k.crew.size() == 3 and game.k.crew[2].at == Kitchen.PASS_IX
	game.sel = 0
	game._portrait_pick = false
	var pr3: Rect2 = game.station_rect(Kitchen.PASS_IX)
	game.tap(Vector2(pr3.get_center().x, pr3.end.y + 120.0))
	var jo_pick: bool = game.sel == 2
	game._service_done()
	await _frames(5)
	_check(three and jo_pick and not game.perks.has("temp"),
		"TEMP PASS (TEMP COOK adds %s at the pass, a tap under PASS picks them: %s, gone after the service)" % [game.k.crew[2].name if game.k.crew.size() > 2 else "-", jo_pick])
	get_node("/root/Save").clear()
	game.over = true   # leave without a checkpoint, so the title has no CONTINUE
	game.quit_to_title()
	await _wait_scene("Title")
	await _frames(5)
	_check(_find("CONTINUE") == null, "FLOW PASS (back at title, no stale CONTINUE)")

	# Bug report sheet carries the build line.
	await _click("REPORT A BUG")
	await _frames(10)
	_shot("bug_report")
	var txt: String = preload("res://scripts/bug_report.gd").report_text("test", get_tree())
	_check("build:" in txt and "device:" in txt, "BUGREPORT PASS")
	await _click("CLOSE")

	# Debug menu (dev builds): 5 taps on the version number.
	for i in 5:
		await _click_node(get_tree().current_scene.find_child("Version", true, false))
	await _frames(10)
	_check(_find("GOD MODE") != null, "DEBUG PASS (dev menu opens)")
	_shot("debug_menu")

	# 3D character standard (docs/MOVEMENT_3D.md): full range of movement, every system proven.
	await _click("3D CHARACTER TEST")
	await _wait_scene("CharacterTest")
	await _frames(20)
	var coach_was: bool = get_tree().current_scene.has_node("UI/Root/Coach_move")
	await _movement_checks(get_tree().current_scene)
	await _standards_checks(get_tree().current_scene, coach_was)
	await _tune_checks(get_tree().current_scene)
	if clip != "":
		await _record_kitchen_clip()

	if not failed:
		print("AUTOPLAY PASS")
	get_tree().quit(1 if failed else 0)


# ---------------------------------------------------------------- 3D movement checks

var _bones := {}


func _snap_bones(sk: Skeleton3D) -> void:
	var d := {}
	for b in ["foot_l", "foot_r", "pelvis", "Head"]:
		d[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin
	d["head_fwd"] = (sk.global_transform.basis * sk.get_bone_global_pose(sk.find_bone("Head")).basis.z).normalized()
	_bones[sk.get_instance_id()] = d


## Bone positions as drawn (after animation, IK and ragdoll), not before the modifiers ran.
func _bone(c: Node, b: String) -> Variant:
	var sk: Skeleton3D = c.skeleton
	if not sk.skeleton_updated.is_connected(_snap_bones.bind(sk)):
		sk.skeleton_updated.connect(_snap_bones.bind(sk))
		await _frames(2)
	await _frames(1)
	return _bones[sk.get_instance_id()][b]


func _place(c: Node, p: Vector3, h: float) -> void:
	c.global_position = p
	c.velocity = Vector3.ZERO
	c.heading = h
	c.model.rotation.y = h
	var sc := get_tree().current_scene
	if sc.has_method("snap_camera") and c == sc.get("hero"):
		sc.snap_camera()                       # cut, don't pan, after a teleport


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ground_gap(c: Node, foot: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(foot + Vector3.UP, foot + Vector3.DOWN * 2.0, 2)
	var r: Dictionary = c.get_world_3d().direct_space_state.intersect_ray(q)
	return foot.y - float(r.position.y) if not r.is_empty() else 99.0


func _movement_checks(ct: Node) -> void:
	var hero: Node = ct.hero
	var dummy: Node = ct.dummy
	# 360 degrees of movement with real limb animation.
	var top_speed := 0.0
	var foot_travel := 0.0
	var last_foot: Vector3 = await _bone(hero, "foot_l")
	var ang := 0.0
	while ang < TAU * 1.15:
		ct.bot_stick = Vector2(cos(ang), sin(ang))
		await _frames(1)
		ang += 0.06
		top_speed = maxf(top_speed, hero.speed())
		var f: Vector3 = _bones[hero.skeleton.get_instance_id()]["foot_l"] - hero.global_position
		foot_travel += f.distance_to(last_foot)
		last_foot = f
		if absf(ang - PI) < 0.03:
			_shot("char_run")
	ct.bot_stick = Vector2.ZERO
	_check(hero.turned > 5.6 and top_speed > 4.0,
		"MOVE360 PASS (turned %.1f rad, top speed %.1f m/s)" % [hero.turned, top_speed])
	_check(foot_travel > 2.0, "LIMBS PASS (left foot travelled %.1f m against the hips: real animation)" % foot_travel)
	# The drawn body follows the skeleton (a stale import can leave a T-pose mesh over a live rig).
	var bound := 0
	var skinned := 0
	for c in [ct.hero, ct.dummy]:
		for m in c.model.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).skin != null:
				skinned += 1
				if m.get_node_or_null(m.skeleton) == c.skeleton:
					bound += 1
	_check(skinned > 0 and bound == skinned, "SKIN PASS (%d of %d body meshes follow their skeleton)" % [bound, skinned])
	# Feet planted on a slope and on stairs (foot IK): both ankles at ankle height over the ground.
	for spot in [["SLOPE", Vector3(5, 1.5, -3), PI], ["STAIRS", Vector3(-3.5, 1.2, 3), -PI / 2]]:
		_place(hero, spot[1], spot[2])
		await _physics(50)
		var gl := _ground_gap(hero, await _bone(hero, "foot_l"))
		var gr := _ground_gap(hero, _bones[hero.skeleton.get_instance_id()]["foot_r"])
		_check(absf(gl - gr) < 0.04 and gl < 0.16 and gr < 0.16,
			"FOOTIK %s PASS (feet %.2f / %.2f m over the ground)" % [spot[0], gl, gr])
		if spot[0] == "STAIRS":
			_shot("char_stairs")
	# Jump: take-off, fall, land.
	_place(hero, Vector3(0, 0.05, 0), 0.0)
	await _physics(10)
	hero.jump()
	var peak := 0.0
	var phases := {}
	for i in 90:
		await _physics(1)
		peak = maxf(peak, hero.global_position.y)
		phases[hero.air_phase] = true
		if i == 20:
			_shot("char_jump")
	_check(peak > 0.6 and phases.has("start") and phases.has("fall") and phases.has("land") and hero.mode == "ground",
		"JUMP PASS (peak %.2f m, start/fall/land)" % peak)
	# Crouch walk.
	ct.toggle_crouch()
	ct.bot_stick = Vector2(1, 0)
	await _physics(30)
	_check(hero.mode == "crouch" and hero.speed() < 2.0 and hero._cap.height < 1.3, "CROUCH PASS (speed %.1f)" % hero.speed())
	_shot("char_crouch")
	ct.bot_stick = Vector2.ZERO
	ct.toggle_crouch()
	# Aim: turn in place, strafe (chest on target, legs sideways), backpedal, head looks at it.
	_place(hero, Vector3(0, 0.05, 2), 0.0)
	await _physics(5)
	var turned0: float = hero.turned
	await _click("AIM")
	await _physics(60)
	var start_pos: Vector3 = hero.global_position
	var to_d: Vector3 = (dummy.global_position - hero.global_position).normalized()
	_check(hero.turned - turned0 > 1.0 and start_pos.distance_to(Vector3(0, 0, 2)) < 0.2, "TURN PASS (turned on the spot)")
	var head_fwd: Vector3 = await _bone(hero, "head_fwd")
	_check(Vector2(head_fwd.x, head_fwd.z).normalized().dot(Vector2(to_d.x, to_d.z)) > 0.85, "LOOKAT PASS (head on target)")
	ct.bot_stick = Vector2(1, 0)
	await _physics(25)
	_check(absf(hero.twist.yaw) > 0.5 and hero.speed() > 3.0, "STRAFE PASS (chest twisted %.0f deg)" % rad_to_deg(hero.twist.yaw))
	_shot("char_strafe")
	_place(hero, Vector3(0, 0.05, 1), PI)
	ct.bot_stick = Vector2(0, 1)
	await _physics(25)
	_check(hero.backpedal and hero.speed() > 3.0, "BACKPEDAL PASS")
	ct.bot_stick = Vector2.ZERO
	await _click("AIM")
	# Punch combo: jab, cross, hook (a real tap, then the same function the button calls); the hook
	# knocks the dummy back (root motion).
	_place(hero, dummy.global_position + Vector3(0, 0.05, 1.0), PI)
	await _physics(5)
	await _click("PUNCH")
	await _physics(4)
	_check(hero.is_acting("punch") and dummy.is_acting("hit_chest"), "ACTION PASS (punch lands, dummy flinches)")
	_shot("char_punch")
	await _physics(20)
	ct.punch()
	await _physics(25)
	var d0: Vector3 = dummy.global_position
	_place(hero, dummy.global_position + Vector3(0, 0.05, 1.0), PI)
	ct.punch()
	await _physics(60)
	_check(ct.combo == 3 and dummy.global_position.distance_to(d0) > 0.6, "KNOCKBACK PASS (combo hook threw the dummy %.1f m)" % dummy.global_position.distance_to(d0))
	await _click("DODGE")
	await _physics(4)
	_check(hero.is_acting("dodge"), "DODGE PASS")
	await _physics(60)
	# Climb a 1 m ledge, vault a 0.8 m wall, swim, climb out of the water.
	_place(hero, Vector3(0, 0.05, -6.4), PI)
	await _physics(10)
	await _click("JUMP")
	await _physics(12)
	_shot("char_climb")
	await _physics(60)
	_check(hero.global_position.y > 0.9 and hero.mode == "ground", "CLIMB PASS (on the ledge at %.2f m)" % hero.global_position.y)
	_place(hero, Vector3(9.25, 0.05, 0.9), 0.0)
	await _physics(10)
	await _click("JUMP")
	await _physics(80)
	_check(hero.global_position.z > 2.0 and hero.global_position.y < 0.2, "VAULT PASS (over the wall)")
	_place(hero, Vector3(-6.5, 0.5, -7.5), 0.0)
	await _physics(90)
	_check(hero.mode == "swim", "SWIM PASS")
	_shot("char_swim")
	_place(hero, Vector3(-6.5, -1.6, -5.8), 0.0)
	await _physics(5)
	await _click("JUMP")
	await _physics(90)
	_check(hero.mode == "ground" and hero.global_position.y > -0.1, "SWIMOUT PASS (climbed out of the pool)")
	# Ragdoll death: the body falls under physics, the pelvis ends near the floor.
	ct.reset_dummy()
	_place(hero, Vector3(2, 0.05, 0), 0.0)
	await _physics(10)
	dummy.die(Vector3(0, 3, -8))
	await _physics(150)
	var pel: Vector3 = await _bone(dummy, "pelvis")
	_check(dummy.is_ragdoll() and pel.y < 0.4, "RAGDOLL PASS (pelvis down to %.2f m)" % pel.y)
	_shot("char_ragdoll")
	var inked := true
	for m in hero.model.find_children("*", "MeshInstance3D", true, false):
		for i in (m as MeshInstance3D).mesh.get_surface_count():
			var mat := (m as MeshInstance3D).get_surface_override_material(i) as ShaderMaterial
			inked = inked and mat != null and mat.next_pass != null
	_check(inked, "INK PASS (toon + outline on every surface)")


# ---------------------------------------------------------------- house standards (GROK_STANDARDS.md)

func _contrast(img: Image, cam: Camera3D, c: Node) -> float:
	var scale := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var lum := func(p: Vector2) -> float:
		var tot := 0.0
		for dx in range(-3, 4, 3):
			for dy in range(-3, 4, 3):
				var q := Vector2i((p * scale) + Vector2(dx, dy))
				q = q.clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
				tot += img.get_pixelv(q).get_luminance()
		return tot / 9.0
	var chest: Vector2 = cam.unproject_position(c.global_position + Vector3(0, 1.15, 0))
	var feet: Vector2 = cam.unproject_position(c.global_position + Vector3(0, 0.05, 0))
	var hips: Vector2 = cam.unproject_position(c.global_position + Vector3(0, 0.95, 0))
	var hero_l: float = (lum.call(chest) + lum.call(hips)) / 2.0
	var floor_l := 0.0
	for o in [Vector2(-90, 0), Vector2(90, 0), Vector2(-90, 40), Vector2(90, 40)]:
		floor_l += lum.call(feet + o) / 4.0
	return (maxf(hero_l, floor_l) + 0.05) / (minf(hero_l, floor_l) + 0.05)


func _standards_checks(ct: Node, coach_was: bool) -> void:
	var hero: Node = ct.hero
	var dummy: Node = ct.dummy
	var feel: Node = get_node("/root/Feel")
	var audio: Node = get_node("/root/Audio")
	var controls: Node = get_node("/root/Controls")
	# 7. First 60 seconds: the move hint showed, and went away once the player moved.
	_check(coach_was and not ct.has_node("UI/Root/Coach_move") and preload("res://scripts/coach.gd").seen("move"),
		"COACH PASS (DRAG TO MOVE shown, learned by doing)")
	# 1 + 10. Game feel: the punches earlier fired every part.
	_check(feel.shakes >= 3 and feel.bursts >= 3 and feel.buzzes >= 3 and feel.sounds >= 3,
		"FEEL PASS (hit-stop, shake x%d, sparks x%d, sound, buzz x%d)" % [feel.shakes, feel.bursts, feel.buzzes])
	# 2. Camera: smooth, never through a wall, frames the target.
	ct.reset_dummy()
	_place(hero, Vector3(0, 0.05, 0), 0.0)
	await _physics(10)
	var last: Vector3 = ct.rig.cam.global_position
	var fastest := 0.0
	ct.bot_stick = Vector2(1, 0)
	for i in 50:
		await _frames(1)
		# Smooth = the camera glides: never faster than twice the hero's top speed (no jump cuts).
		fastest = maxf(fastest, ct.rig.cam.global_position.distance_to(last) / maxf(get_process_delta_time(), 0.001))
		last = ct.rig.cam.global_position
	ct.bot_stick = Vector2.ZERO
	_check(fastest < hero.max_speed * 2.0, "CAMERA SMOOTH PASS (camera top speed %.1f m/s)" % fastest)
	_place(hero, Vector3(-12, 0.05, 2.2), 0.0)
	await _physics(30)
	var cam: Camera3D = ct.rig.cam
	var see: Dictionary = get_tree().current_scene.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(cam.global_position, hero.global_position + Vector3(0, 1.2, 0), 1, [hero.get_rid()]))
	_check(ct.rig.blocked and see.is_empty(), "CAMERA WALL PASS (camera came in front of the wall)")
	_shot("std_camera_wall")
	_place(hero, Vector3(0, 0.05, 4), PI)
	dummy.global_position = Vector3(0, 0, -5)
	ct.toggle_aim()
	await _physics(120)
	var vp := get_viewport().get_visible_rect()
	var both: bool = vp.has_point(cam.unproject_position(hero.global_position + Vector3(0, 1, 0))) \
		and vp.has_point(cam.unproject_position(dummy.global_position + Vector3(0, 1, 0))) \
		and not cam.is_position_behind(dummy.global_position)
	_check(both, "CAMERA FRAME PASS (hero and target both on screen)")
	_shot("std_camera_frame")
	# 6. Music shifts to the combat layer when fighting.
	_check(audio.intensity > 0.9, "MUSIC PASS (combat layer at %d%%)" % int(audio.intensity * 100))
	ct.toggle_aim()
	ct.reset_dummy()
	# 6. Footsteps per surface: stone floor, wooden ramp, grass.
	hero.steps.clear()
	for spot in [[Vector3(-2, 0.05, -1), Vector2(1, 0)], [Vector3(5, 0.05, 0.5), Vector2(0, -1)], [Vector3(-2, 0.1, 8), Vector2(1, 0)]]:
		_place(hero, spot[0], 0.0)
		ct.bot_stick = spot[1] * 0.5
		await _physics(70)
	ct.bot_stick = Vector2.ZERO
	_check(hero.steps.has("stone") and hero.steps.has("wood") and hero.steps.has("grass"),
		"STEPS PASS (%s)" % str(hero.steps))
	# 6. Ducking: a heavy hit dips the music.
	feel.impact(hero.global_position, 0.8, ct)
	await _frames(8)
	_check(audio.duck_db < -4.0, "DUCK PASS (music dipped %.0f dB)" % audio.duck_db)
	# 4. Responsive: input buffer, coyote time, dodge cancels anything.
	_place(hero, Vector3(0, 0.05, 2), 0.0)
	await _physics(10)
	hero.jump()
	var buffered := false
	var takeoffs := 0
	var prev_vy := 0.0
	for i in 120:
		await _physics(1)
		if hero.velocity.y > 3.0 and prev_vy <= 3.0:
			takeoffs += 1
		prev_vy = hero.velocity.y
		if not buffered and hero.velocity.y < -2.0 and hero.global_position.y < 0.35:
			hero.jump()                         # pressed before landing: must still jump
			buffered = true
	_check(takeoffs >= 2, "BUFFER PASS (jump pressed in the air fired on landing)")
	_place(hero, Vector3(0, 1.05, -8.0), 0.0)
	await _physics(10)
	ct.bot_stick = Vector2(0, 1)
	var coyote_ok := false
	for i in 90:
		await _physics(1)
		if not hero.is_on_floor() and hero.velocity.y <= 0.0 and hero.global_position.y < 0.98:
			await _physics(2)
			hero.jump()
			await _physics(1)
			coyote_ok = hero.velocity.y > 3.0
			break
	ct.bot_stick = Vector2.ZERO
	_check(coyote_ok, "COYOTE PASS (jumped just after leaving the edge)")
	await _physics(60)
	hero.act("punch")
	await _physics(3)
	hero.act("dodge")
	await _physics(3)
	_check(hero.is_acting("dodge") and not hero.is_acting("punch"), "CANCEL PASS (punch cancelled into a dodge)")
	await _physics(110)
	# 11. Gamepad + remapping, through the real input system.
	_place(hero, Vector3(0, 0.05, 2), 0.0)
	ct.bot_stick = Vector2.INF                # hand control back to the real inputs
	await _physics(5)
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_LEFT_X
	m.axis_value = 1.0
	Input.parse_input_event(m)
	await _physics(30)
	var pad_speed: float = hero.velocity.x
	m.axis_value = 0.0
	Input.parse_input_event(m)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_A
	b.pressed = true
	await _physics(20)
	Input.parse_input_event(b)
	await _frames(3)                           # parsed input is delivered on the next frame
	var pad_jump: bool = hero.mode == "air" or hero.velocity.y > 1.0
	b.pressed = false
	Input.parse_input_event(b)
	_check(pad_speed > 3.0 and pad_jump, "PAD PASS (stick moves %.1f m/s, A jumps)" % pad_speed)
	await _physics(80)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	controls.rebind("jump", k)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_T
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(3)
	var remap_ok: bool = (hero.mode == "air" or hero.velocity.y > 1.0) and FileAccess.file_exists("user://controls.cfg")
	press.pressed = false
	Input.parse_input_event(press)
	controls.reset()
	_check(remap_ok,
		"REMAP PASS (jump moved to T, saved, reset)")
	await _physics(80)
	# Controls legend: hidden for touch players, shows on the first key/pad press, follows remaps,
	# and the Settings toggle hides it.
	var lg: PanelContainer = preload("res://scripts/controls_legend.gd").make(["jump", "pause"])
	lg.top = 420                              # below the scene's own legend
	ct.ui.add_child(lg)
	await _frames(2)
	var hidden_touch := not lg.visible
	var kp := InputEventKey.new()
	kp.physical_keycode = KEY_Z
	kp.pressed = true
	Input.parse_input_event(kp)
	kp.pressed = false
	Input.parse_input_event(kp)
	await _frames(3)
	var shown := lg.visible
	await _frames(2)
	_shot("legend")
	var kt := InputEventKey.new()
	kt.physical_keycode = KEY_T
	controls.rebind("jump", kt)
	lg.refresh()
	var follows: bool = "T" in lg._label.text.split("\n")[0]
	controls.reset()
	var settings: Node = get_node("/root/Settings")
	settings.set_value("show_legend", false)
	var off := not lg.visible
	settings.set_value("show_legend", true)
	_check(hidden_touch and shown and follows and off and ct.legend != null,
		"LEGEND PASS (hidden on touch, shows on key, follows remap, toggle hides)")
	lg.queue_free()
	# 5. The hero reads against the floor, in normal light and in the dark.
	_place(hero, Vector3(-2, 0.05, 0.5), 0.0)
	await _physics(20)
	await RenderingServer.frame_post_draw
	var c1: float = _contrast(get_viewport().get_texture().get_image(), cam, hero)
	ct.sun.light_energy = 0.08
	await _frames(3)
	await RenderingServer.frame_post_draw
	var c2: float = _contrast(get_viewport().get_texture().get_image(), cam, hero)
	_shot("std_dark")
	ct.sun.light_energy = 1.2
	_check(c1 >= 2.0 and c2 >= 2.0, "READ PASS (hero vs floor contrast %.1f lit, %.1f dark)" % [c1, c2])
	# 3. Frame budget: draw calls, triangles, code time with 6 characters running.
	var r: Dictionary = await ct.perf_test(3.0, false)
	_check(r.budget_ok, "PERF PASS (%d draw calls, %dk tris, %.1f ms code; budget %s)" % [
		r.draw_calls, r.primitives / 1000.0, r.cpu_ms, str(ct.BUDGET)])
	# 9. Telemetry stays on the phone unless allowed.
	var tel: Node = get_node("/root/Telemetry")
	_check(not tel.allowed() and tel.events().size() > 0, "TELEMETRY PASS (%d events kept on the phone, nothing sent)" % tel.events().size())


# ---------------------------------------------------------------- 15 s gameplay clip (vertical)

## The build clip is Rush itself (Nov 25, ad kit): service 3, all four stations open, the bot cooking
## through the real screen so sparks, words and sounds all fire. 15 s of every drawn frame.
func _record_kitchen_clip() -> void:
	DirAccess.make_dir_recursive_absolute(clip)
	var ts_was = get_node("/root/Settings").get_value("text_size")
	get_node("/root/Settings").set_value("text_size", 1)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _wait_scene("Game")
	await _frames(10)
	var game: Node = get_tree().current_scene
	for st in game._coach_steps():   # the clip is an ad: no teaching bubbles over the play
		game._coached[st[0]] = true
	var subs_was = get_node("/root/Settings").get_value("subtitles")
	get_node("/root/Settings").set_value("subtitles", false)   # sound captions stay on for players, off for the clip
	for sh in get_tree().get_nodes_in_group("sheet"):
		sh.queue_free()
	game.paused = false
	game.level = 3
	game._new_service()
	game._after_move()
	for i in 3:   # a few minutes in, so the rail is busy from the first frame
		game.bot_play_turn()
	await _frames(5)
	var frames := 0
	var t0 := Time.get_ticks_msec()
	var next_step := 0.4
	var acted := 0
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t >= CLIP_SECS or game.over or game.between:
			break
		if t >= next_step:
			acted += 1 if game.bot_step() else 0
			next_step = t + 0.45
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2 * 2, img.get_height() / 2 * 2)   # even size for video
		img.save_jpg(clip.path_join("f%04d.jpg" % frames), 0.85)
		frames += 1
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	get_node("/root/Settings").set_value("subtitles", subs_was)
	get_node("/root/Settings").set_value("text_size", ts_was)
	var f := FileAccess.open(clip.path_join("fps.txt"), FileAccess.WRITE)
	f.store_string("%.3f" % (frames / secs))
	f.close()
	_check(frames >= 60 and secs >= CLIP_SECS and acted >= 10,
		"CLIP PASS (Rush service 3: %d frames over %.1f s, %d bot actions, saved for the build video)" % [frames, secs, acted])

## Trays (Duff, Nov 25): a RUN starts at one plate; the SHOP sells the server tray (2), then the
## entree tray (4) in the same row. The shop fits at HUGE text, and a tray RUN sends 2 plates on one
## tap of the real button. Cash, perks and the service are put back afterwards.
## The fresh-player polish pass: plain words on the NEXT bar and tickets, a badge for hidden
## tickets, END TURN warns before a pan burns, and the shop lists what's owned.
func _polish_checks(game: Node) -> void:
	var kk = game.k
	var keep: Dictionary = kk.to_dict()
	var perks_was: Array = game.perks.duplicate()
	var cash_was: int = game.cash
	game.between = false
	kk.done = false
	var covers: Array = get_tree().get_nodes_in_group("sheet").filter(func(n): return n.visible)
	for n in covers:
		n.visible = false
	kk.tickets.clear()
	for i in 6:   # six on the rail: two hide behind the badge, one of them red
		kk.tickets.append({"id": 970 + i, "table": 40 + i, "items": [{"dish": "STEAK", "state": "wait"},
			{"dish": "FRIES", "state": ["cooking", "carried", "served"][i % 3]}], "time": [6, 5, 4, 3, 7, 1][i], "big": false})
	kk.pans[0] = {"tid": 970, "dish": "STEAK", "left": 0, "sat": kk.burn_after, "rushed": false, "by": 0}
	kk.incoming = [{"arrive": kk.turn + 2, "ticket": {"items": [{"dish": "STEAK"}], "big": false}},
		{"arrive": kk.turn + 3, "ticket": {"items": [{"dish": "STEAK"}, {"dish": "FRIES"}], "big": false}},
		{"arrive": kk.turn + 5, "ticket": {"items": [], "big": true}}]
	game._refresh_hud()
	game.field.queue_redraw()
	await _frames(3)
	var warn: String = game.end_btn.text
	# The +N MORE badge pages the rail: a tap shows the 5th ticket first, BACK returns.
	var first_id: int = game.rail_tickets()[0].id
	var fifth_id: int = game.rail_tickets()[4].id
	await _tap_at(game.field.get_global_transform() * game._more_rect.get_center())
	var paged: bool = game.rail_off == 4 and game.rail_tickets()[0].id == fifth_id
	game.field.queue_redraw()
	await _frames(2)
	await _shot("polish_rail_page")
	await _tap_at(game.field.get_global_transform() * game._more_rect.get_center())
	var back: bool = game.rail_off == 0 and game.rail_tickets()[0].id == first_id
	_check(paged and back, "RAIL PAGE PASS (+2 MORE showed tickets 5-6, BACK returned to the most urgent)")
	# Stress pass: two away and working: END TURN warns a turn early, the meter shows the +1, and
	# the action button names the cook it moves.
	var sat_was: int = kk.pans[0].sat
	kk.pans[0].sat = 0   # no burn this turn, so the early warning isn't outranked
	kk.crew[1].stress = kk.stress_cap - 2
	kk.crew[1].acted = true
	game._refresh_hud()
	var near_warn: String = game.end_btn.text
	var near_after: int = game.stress_after(1)
	var named: String = game.act_btn.text
	game.field.queue_redraw()
	await _frames(2)
	await _shot("stress_preview")
	kk.pans[0].sat = sat_was
	_check(near_warn == "END TURN\nMO NEAR QUIT" and near_after == kk.stress_cap - 1
		and (named.begins_with(kk.crew[game.sel].name + ": ") or named == "TAP A STATION" or named.ends_with("NO MOVES")),
		"STRESS PASS (END TURN '%s', MO %d -> %d before it's pressed, button '%s')" % [near_warn.replace("\n", " / "), kk.stress_cap - 2, near_after, named.replace("\n", " ")])
	kk.crew[1].stress = kk.stress_cap - 1   # MO is one away and worked this turn: END TURN names her
	kk.crew[1].acted = true
	kk.crew[0].ap = 0
	game.sel = 0
	game._refresh_hud()
	var quit_warn: String = game.end_btn.text
	var spent: String = game.act_btn.text
	game.field.queue_redraw()
	await _frames(2)
	await _shot("polish_tired")
	var nx: String = game.next_line(ThemeDB.fallback_font, 2000.0)
	await _shot("polish_board")
	# Movement pass: the last table out says how to finish; Cast Iron's free RUSH says FREE; OUT counts this service.
	var rs_was: int = kk.rush_stress
	kk.rush_stress = 0
	kk.crew[0].stress = 0
	kk.crew[0].ap = kk.ap
	kk.crew[0].at = 0
	kk.pans[0] = {"tid": kk.tickets[0].id, "dish": "STEAK", "left": 2, "sat": 0, "rushed": false, "by": 0}
	game.sel = 0
	game._refresh_hud()
	var free_lbl: String = game.act_btn.text
	kk.rush_stress = rs_was
	kk.pans[0] = {}
	kk.tickets.clear()
	kk.incoming.clear()
	for c in kk.crew:
		c.stress = 0
	game._refresh_hud()
	var finish: String = game.end_btn.text
	_check(free_lbl == "DEV: RUSH (FREE)" and finish == "END TURN\nFINISH SERVICE",
		"FINISH PASS (Cast Iron rush reads '%s'; an empty rail says '%s')" % [free_lbl, finish.replace("\n", " / ")])
	# 8.5 pass: END TURN names every burn and every quit; FIRE says TOO LATE and what the first move costs;
	# a tap in the strip under a station picks the cook standing there.
	for c in kk.crew:
		c.stress = 0
		c.acted = false
		c.ap = kk.ap
	kk.crew[0].at = 0
	kk.crew[1].at = 1
	kk.tickets = [{"id": 990, "table": 50, "items": [{"dish": "STEAK", "state": "wait"}], "time": 1, "big": false},
		{"id": 991, "table": 51, "items": [{"dish": "FRIES", "state": "wait"}], "time": 3, "big": false}]
	kk.pans[0] = {"tid": 990, "dish": "STEAK", "left": 0, "sat": kk.burn_after, "rushed": false, "by": 0}
	kk.pans[1] = {"tid": 991, "dish": "FRIES", "left": 0, "sat": kk.burn_after, "rushed": false, "by": 1}
	game.sel = 0
	game._refresh_hud()
	var two_burns: String = game.end_btn.text
	var plate_lbl: String = game.act_btn.text   # plating empties the burning pan: only the red ticket's +1
	kk.pans[0] = {}
	kk.pans[1] = {}
	for c in 2:
		kk.crew[c].stress = kk.stress_cap - 1
		kk.crew[c].acted = true
	game._refresh_hud()
	var two_quits: String = game.end_btn.text
	for c in 2:
		kk.crew[c].stress = 0
		kk.crew[c].acted = false
	game.sel = 0
	game.pick_tid = 990
	game.pick_ix = -1
	game._refresh_hud()
	var late: String = game.act_btn.text
	# A tired cook who'd rest: the move costs nothing new, but the button says the rest is gone.
	var tickets_was: Array = kk.tickets.duplicate(true)
	kk.tickets = [{"id": 994, "table": 54, "items": [{"dish": "STEAK", "state": "wait"}], "time": 9, "big": false}]
	var stress_was: int = kk.crew[0].stress
	kk.crew[0].stress = kk.stress_cap - 3   # tired enough that the rest matters
	game.pick_tid = 0
	game._refresh_hud()
	var rest_lbl: String = game.act_btn.text
	kk.crew[0].stress = stress_was
	kk.tickets = tickets_was
	game.pick_tid = 0
	game.sel = 0
	game._portrait_pick = false
	var sr1: Rect2 = game.station_rect(1)
	game.tap(Vector2(sr1.position.x + 6.0, sr1.end.y + 140.0))
	var strip_pick: bool = game.sel == 1
	game._portrait_pick = false
	var want_q: String = "END TURN\n%s + %s QUIT" % [kk.crew[0].name, kk.crew[1].name]
	_check(two_burns == "END TURN\nGRILL + FRY BURN" and two_quits == want_q and "TOO LATE" in late and "+1 STRESS" in late and strip_pick
		and plate_lbl.begins_with("DEV: PLATE") and plate_lbl.ends_with("+1 STRESS") and rest_lbl.ends_with("SKIPS REST"),
		"WARN PASS ('%s', '%s', '%s', '%s', strip tap picks the cook: %s)" % [two_burns.replace("\n", " / "), two_quits.replace("\n", " / "), late.replace("\n", " / "), rest_lbl.replace("\n", " / "), strip_pick])
	# 8.5 plan #2: HEAT WAVE shows on the stress preview before END TURN; a spent cook goes grey, DONE.
	kk.event = "heat"
	kk.turn = 1
	kk.tickets = [{"id": 993, "table": 53, "items": [{"dish": "FRIES", "state": "wait"}], "time": 9, "big": false}]
	for i in kk.pans.size():
		kk.pans[i] = {}
	kk.crew[0].stress = 0
	kk.crew[0].acted = true
	kk.crew[0].ap = 0
	var heat_prev: int = game.stress_after(0)
	game._refresh_hud()
	game.field.queue_redraw()
	await _frames(3)
	await _shot("heat_spent")
	_check(heat_prev == 1, "HEAT PASS (a worked cook on a heat turn previews +%d stress; spent DEV drawn grey with DONE)" % heat_prev)
	kk.from_dict(JSON.parse_string(JSON.stringify(keep)))
	game._refresh_hud()
	var calm: String = game.end_btn.text
	for n in covers:
		n.visible = true
	game.perks = perks_was.filter(func(p): return not String(p).begins_with("tray")) + ["tray"]
	game.open_shop()
	await _frames(4)
	var owned: Label = get_tree().root.find_child("Owned", true, false)
	var owned_txt: String = owned.text if owned != null else "-"   # read now: DONE frees the sheet
	var owned_ok: bool = owned_txt.contains("SERVER TRAY")
	await _shot("polish_shop")
	await _click("DONE")
	game.perks = perks_was
	game.cash = cash_was
	game.between = true
	game._refresh_hud()
	await _frames(2)
	_check(warn == "END TURN\nGRILL BURNS" and calm == "END TURN" and quit_warn == "END TURN\nMO QUITS" and spent == "DEV: NO MOVES" and nx.begins_with("NEXT: ") and nx.contains("1 dish in 2 min") and nx.contains("2 dishes in 3 min")
		and owned_ok,
		"POLISH PASS (END TURN warns '%s' and '%s', spent cook '%s', NEXT bar '%s', shop says '%s')" % [warn.replace("\n", " / "), quit_warn.replace("\n", " / "), spent, nx, owned_txt])


func _tray_checks(game: Node, pst: Node) -> void:
	var cash_was: int = game.cash
	var perks_was: Array = game.perks.duplicate()
	var ts_was = pst.get_value("text_size")
	var one: bool = game.k.tray == 1
	pst.set_value("text_size", 3)
	game.cash = 999
	game.perks = perks_was.filter(func(p): return not String(p).begins_with("tray"))
	game.open_shop()
	await _frames(4)
	var row1: bool = _find("SERVER TRAY") != null and _find("ENTREE TRAY") == null
	await _click("SERVER TRAY")
	await _frames(4)
	var row2: bool = _find("ENTREE TRAY") != null and _find("SERVER TRAY") == null
	var sheet: Control = get_tree().get_nodes_in_group("sheet").back()
	var pr: Rect2 = (sheet.get_child(1).get_child(0) as Control).get_global_rect()
	var vh: float = get_viewport().get_visible_rect().size.y
	await _shot("shop_huge")
	await _click("ENTREE TRAY")
	await _frames(4)
	var four: bool = game.perks.has("tray2") and Upgrades.apply({"ticket_time": 9, "stress_cap": 6,
		"rush_stress": 1, "lives": 3}, game.perks).tray == 4
	await _click("DONE")
	pst.set_value("text_size", ts_was)
	await _frames(2)
	# A tray RUN through the real button: two plates of one table go out on one action.
	var kk = game.k
	var keep: Dictionary = kk.to_dict()
	game.between = false
	kk.done = false
	var covers: Array = get_tree().get_nodes_in_group("sheet").filter(func(n): return n.visible)
	for n in covers:   # the grade sheet sits over the line: step it aside for one real tap
		n.visible = false
	kk.tray = 2
	kk.tickets.append({"id": 990, "table": 30, "items": [{"dish": "BURGER", "state": "carried"},
		{"dish": "FRIES", "state": "carried"}], "time": 5, "big": false})
	kk.window = [{"tid": 990, "dish": "BURGER"}, {"tid": 990, "dish": "FRIES"}]
	game.sel = 0
	kk.crew[0].at = KitchenRules.PASS_IX
	kk.crew[0].ap = kk.ap
	kk.crew[0].out = false
	game._refresh_hud()
	await _frames(2)
	var label: String = game.act_btn.text
	var ap: int = kk.crew[0].ap
	await _click("RUN 2 PLATES")
	await _frames(3)
	var ran: bool = kk.ticket(990).is_empty() and kk.window.is_empty() and kk.crew[0].ap == ap - 1
	kk.from_dict(JSON.parse_string(JSON.stringify(keep)))
	for n in covers:
		n.visible = true
	game.between = true
	game.cash = cash_was
	game.perks = perks_was
	game._refresh_hud()
	_check(one and row1 and row2 and four and pr.position.y >= 0.0 and pr.end.y <= vh and label.get_slice("\n", 0).ends_with("RUN 2 PLATES") and ran,
		"TRAY PASS (one plate a RUN to start; shop row SERVER TRAY -> ENTREE TRAY = 4, fits at HUGE %d px of %d; '%s' sent 2 plates for one action)" % [int(pr.size.y), int(vh), label])


func _tune_checks(ct: Node) -> void:
	var dm: Node = get_node("/root/DebugMenu")
	var Tune = preload("res://scripts/tune_panel.gd")
	dm.open()
	await _frames(5)
	await _click("TUNE")
	await _frames(10)
	var panel: Node = dm.tune_panel
	var sl: HSlider = panel.find_child("character3d__max_speed", true, false) if panel != null else null
	var cam_sl: HSlider = panel.find_child("camera_rig__distance", true, false) if panel != null else null
	var feel_sl: HSlider = panel.find_child("feel__stop_scale", true, false) if panel != null else null
	var was: float = ct.hero.max_speed
	if sl != null:
		sl.value = was + 1.5
	await _frames(3)
	_shot("tune_panel")
	var moved: bool = sl != null and absf(ct.hero.max_speed - (was + 1.5)) < 0.02
	var kept: bool = Tune.saved("character3d", "max_speed") != null
	var all_kinds: bool = cam_sl != null and feel_sl != null
	var shared: bool = "character3d.max_speed" in "\n".join(Tune.changed_lines(get_tree(), dm.tune_defaults))
	await _click("RESET TO CODE VALUES")
	await _frames(3)
	_check(moved and kept and shared and all_kinds and dm.tune_panel == null
		and is_equal_approx(ct.hero.max_speed, was) and Tune.saved("character3d", "max_speed") == null,
		"TUNE PASS (live sliders for hero, camera, feel; saved, shared, reset)")


func _check(ok: bool, line: String) -> void:
	if ok:
		print(line)
	else:
		failed = true
		print("FAIL: " + line)


func _fail(step: String) -> void:
	print("AUTOPLAY FAIL " + step)
	get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_scene(node_name: String) -> void:
	for i in 600:
		var s := get_tree().current_scene
		if s != null and s.name == node_name:
			await _frames(2)
			return
		await _frames(1)
	_fail("scene " + node_name)


func _shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("flow_%s.png" % name))


## The visible, enabled button whose text starts with `prefix` (topmost sheet wins).
func _find(prefix: String) -> Button:
	var found: Button = null
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and (b.text.begins_with(prefix) or b.text.contains(": " + prefix)) and not b.is_queued_for_deletion():
			found = b
	return found


func _click(prefix: String) -> void:
	var b := _find(prefix)
	if b == null:
		_fail("no button " + prefix)
		return
	await _click_node(b)


func _click_node(c: Control) -> void:
	if c == null:
		_fail("no node")
		return
	var sc := c.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(c)
		await _frames(3)
	await _tap_at(c.get_global_rect().get_center())


## A real tap at a canvas point: converted to window pixels and sent through Input.
func _tap_at(p: Vector2) -> void:
	var w := get_viewport().get_final_transform() * p
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = w
		e.global_position = w
		Input.parse_input_event(e)
		await _frames(2)



func _has_label(text: String) -> bool:
	for label in get_tree().root.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == text:
			return true
	return false
