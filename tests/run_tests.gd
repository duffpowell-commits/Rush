extends SceneTree
## Rule tests, headless: godot --headless --path . --script tests/run_tests.gd
## Last line is "ALL PASS (N)" or "FAILED k of N". Add a test_* function for every rule.
## A new test only counts once you've seen it fail (break the code, watch it go red, restore).

const Config = preload("res://scripts/config.gd")
const UI = preload("res://scripts/ui.gd")
const Updater = preload("res://scripts/updater.gd")
const BugReport = preload("res://scripts/bug_report.gd")
const Kitchen = preload("res://scripts/kitchen.gd")
const Upgrades = preload("res://scripts/upgrades.gd")

var n := 0
var bad := 0


func _initialize() -> void:
	await process_frame   # autoloads are ready after the first frame
	for m in get_method_list():
		if m.name.begins_with("test_"):
			n += 1
			var before := bad
			await call(m.name)
			print(("ok   " if bad == before else "FAIL ") + m.name)
	print("ALL PASS (%d)" % n if bad == 0 else "FAILED %d of %d" % [bad, n])
	quit(1 if bad > 0 else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		bad += 1
		print("  failed: " + what)


func test_save_roundtrip() -> void:
	var save: Node = root.get_node("Save")
	save.path = "user://test_run.json"
	save.clear()
	check(not save.exists(), "no save at start")
	check(save.write({"level": 3, "score": 27, "lives": 1}), "write ok")
	var d: Dictionary = save.read()
	check(int(d.get("level")) == 3 and int(d.get("score")) == 27, "same values back")
	check(int(d.get("_version")) == save.VERSION, "version stamped")
	save.clear()
	check(not save.exists(), "cleared")
	save.path = "user://run.json"


func test_corrupt_save_is_ignored() -> void:
	var save: Node = root.get_node("Save")
	save.path = "user://test_bad.json"
	var f := FileAccess.open(save.path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(save.read().is_empty(), "garbage save reads as empty, no crash")
	save.clear()
	save.path = "user://run.json"


func test_settings_defaults_and_persist() -> void:
	var s: Node = root.get_node("Settings")
	s.reset_for_tests()
	for k in ["music", "sfx", "vibration", "gamma", "text_size", "invert_y", "sensitivity",
			"low_graphics", "left_handed", "subtitles", "high_contrast", "colorblind"]:
		check(s.DEFAULTS.has(k), "setting exists: " + k)
	s.set_value("music", 0.25)
	s.values["music"] = 0.9
	s.load_settings()
	check(absf(float(s.get_value("music")) - 0.25) < 0.001, "music volume saved to disk")
	var bus := AudioServer.get_bus_index("Music")
	check(bus > 0, "Music bus exists at boot")
	check(AudioServer.get_bus_index("SFX") > 0, "SFX bus exists at boot")
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.25)) < 0.1, "music slider moves the bus")
	s.reset_for_tests()
	s.save_settings()


func test_text_scale_steps() -> void:
	var s: Node = root.get_node("Settings")
	s.values["text_size"] = 3
	check(UI.font_size(20) > 20, "large text is larger")
	s.values["text_size"] = 1
	check(UI.font_size(20) == 20, "normal is unchanged")


func test_colorblind_swaps_key_colors() -> void:
	var s: Node = root.get_node("Settings")
	s.values["colorblind"] = false
	var a := UI.key("good")
	s.values["colorblind"] = true
	check(UI.key("good") != a, "colorblind palette differs")
	s.values["colorblind"] = false


func test_touch_targets() -> void:
	check(UI.MIN_TOUCH >= 62, "min touch >= 48dp (~62 base units)")
	var b := UI.button("X")
	check(b.custom_minimum_size.y >= UI.MIN_TOUCH, "buttons use the minimum")
	b.free()


func test_updater_compare() -> void:
	check(Updater.is_newer(5, 4), "newer build offered")
	check(not Updater.is_newer(4, 4), "same build not offered")
	check(not Updater.is_newer(9, 0), "editor build (0) never offered")
	check(Updater.should_offer(6, 4, 5), "build newer than the one put off is offered")
	check(not Updater.should_offer(5, 4, 5), "LATER holds for that build")
	check(Updater.should_offer(5, 4, 0), "nothing put off: newer build offered")


func test_config_paths() -> void:
	check(Config.apk_name().ends_with(".apk"), "apk name")
	check(Config.release_url().begins_with("https://github.com/") and Config.release_url().ends_with("/releases/download/dev/"), "release url")


func test_bug_report_text() -> void:
	var t := BugReport.report_text("it broke", self)
	check(t.begins_with("it broke"), "note first")
	check("build:" in t and "device:" in t, "build + device added")
	check(BugReport.issue_url(t).contains("/issues/new?"), "issue link")


# ---------------------------------------------------------------- house standards (GROK_STANDARDS.md)

## 11. Every game action works on keyboard AND gamepad, and remaps survive a restart.
func test_controls_keyboard_and_pad() -> void:
	var c: Node = root.get_node("Controls")
	for a in c.ACTIONS:
		var has_key := false
		var has_pad := false
		for e in InputMap.action_get_events(a):
			has_key = has_key or e is InputEventKey
			has_pad = has_pad or c.is_pad(e)
		check(has_key and has_pad, a + " has a key and a pad input")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_G
	c.rebind("attack", k)
	var fresh: Node = load("res://scripts/controls.gd").new()
	fresh._load()
	check(fresh._custom.has("attack") and (fresh._custom.attack.key as InputEventKey).physical_keycode == KEY_G, "remap saved and loaded")
	fresh.free()
	c.reset()
	check(not InputMap.action_has_event("attack", k), "reset restores defaults")


## 9 + 12. Stats stay on the phone unless the player opts in AND an endpoint is set; a run that
## didn't close cleanly is spotted next launch.
func test_telemetry_offline_and_crash_flag() -> void:
	var t: Node = root.get_node("Telemetry")
	check(not t.allowed(), "nothing is sent by default")
	var before: int = t.events().size()
	t.event("unit_test", {"x": 1})
	check(t.events().size() == before + 1, "event kept locally")
	var f := FileAccess.open(t.RUN_FLAG, FileAccess.WRITE)
	f.store_string("Game v0.1.0")
	f = null
	var fresh: Node = load("res://scripts/telemetry.gd").new()
	root.add_child(fresh)
	check(fresh.crashed_last_run, "unclean exit detected")
	fresh.clean_exit()
	check(not FileAccess.file_exists(t.RUN_FLAG), "clean exit clears the flag")
	fresh.queue_free()
	var http := 0
	for n in root.find_children("*", "HTTPRequest", true, false):
		if t.is_ancestor_of(n):
			http += 1
	check(http == 0, "no network request without consent")


## 8. Portable assets: every model is glTF on the standard humanoid skeleton and listed in SOURCES.
func test_models_portable() -> void:
	var sources := FileAccess.get_file_as_string("res://assets/models/SOURCES.md")
	var d := DirAccess.open("res://assets/models")
	var count := 0
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".md"):
			continue
		count += 1
		check(f.ends_with(".glb") or f.ends_with(".gltf"), f + " is glTF")
		check(f in sources, f + " listed in SOURCES.md")
		var scene: Node = (load("res://assets/models/" + f) as PackedScene).instantiate()
		var sk := scene.find_children("*", "Skeleton3D", true, false)
		check(sk.size() == 1, f + " has one skeleton")
		if sk.size() == 1:
			for b in ["pelvis", "spine_01", "Head", "thigh_l", "calf_l", "foot_l", "upperarm_r", "hand_r"]:
				check((sk[0] as Skeleton3D).find_bone(b) >= 0, f + " has bone " + b)
			_check_model_scale(f, scene as Node3D, sk[0] as Skeleton3D)
		scene.free()
	check(count > 0, "models found")


## Normalised import: 1 unit = 1 m, root scale 1, feet on y = 0, same facing as the mannequin
## (glTF +Z forward; Character3D turns it). Catches 100x centimetre roots and floating feet.
func _check_model_scale(f: String, root: Node3D, sk: Skeleton3D) -> void:
	check(root.scale.is_equal_approx(Vector3.ONE), f + " root scale is 1")
	var xf := Transform3D.IDENTITY
	var n: Node = sk
	while n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var head := (xf * sk.get_bone_global_rest(sk.find_bone("Head"))).origin
	var foot := (xf * sk.get_bone_global_rest(sk.find_bone("foot_l"))).origin
	var toe_i := sk.find_bone("ball_l")
	var toe := (xf * sk.get_bone_global_rest(toe_i)).origin if toe_i >= 0 else foot
	check(head.y > 1.2 and head.y < 2.2, f + " is human height in metres (head at %.2f)" % head.y)
	check(minf(toe.y, foot.y) > -0.05 and minf(toe.y, foot.y) < 0.12, f + " feet on y = 0 (%.2f)" % minf(toe.y, foot.y))
	check(toe_i < 0 or toe.z > foot.z, f + " faces +Z like the mannequin")


## Texture imports are explicit: colour maps are sRGB and never normal maps; only *_n / *_normal
## files may be normal maps. (Godot's "detect" setting can flip a colour map to a normal map.)
func test_texture_imports_explicit() -> void:
	for path: String in _files("res://assets", [".png.import", ".jpg.import", ".jpeg.import", ".webp.import"]):
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		var base: String = path.get_file().get_basename().get_basename()
		var is_normal: bool = base.ends_with("_n") or base.ends_with("_normal")
		var nm: int = cfg.get_value("params", "compress/normal_map", 0)
		check(nm == (1 if is_normal else 2), "%s normal_map is %s (set it, don't detect)" % [path, "on" if is_normal else "off"])


func _files(dir: String, ends: Array) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		for e in ends:
			if f.ends_with(e):
				out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files(dir + "/" + sub, ends))
	return out


## Phone textures: 3D textures import as ETC2/ASTC (the VRAM formats Android phones read directly).
func test_mobile_texture_compression() -> void:
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false),
		"ETC2/ASTC texture compression is on for phones")


## Atlases: a sheet + json made by tools/pack_atlas.py hands back the right piece.
func test_atlas_regions() -> void:
	var Atlas = preload("res://scripts/atlas.gd")
	var t: AtlasTexture = Atlas.tex("res://tests/fixtures/atlas_demo", "coin")
	check(t != null and t.region == Rect2(26, 0, 16, 16), "coin region read from the json")
	if t != null:
		var c := t.atlas.get_image().get_pixel(26 + 8, 8)
		check(c.r > 0.85 and c.g > 0.7 and c.b < 0.3, "coin pixel is gold (%s)" % c)
	check(Atlas.names("res://tests/fixtures/atlas_demo").size() == 3, "three images in the sheet")
	check(Atlas.tex("res://tests/fixtures/atlas_demo", "coin") == t, "atlas pieces are cached")


## Quality tiers: LOW sets low graphics + a smaller 3D render, HIGH undoes it, the pick is saved.
func test_quality_tiers() -> void:
	var Q = preload("res://scripts/quality.gd")
	var st: Node = root.get_node_or_null("Settings")
	check(st != null, "Settings autoload present")
	if st == null:
		return
	Q.apply(self, 0)
	check(st.get_value("low_graphics") == true and st.get_value("tier") == 0 and is_equal_approx(root.scaling_3d_scale, 0.7), "LOW applies")
	Q.apply(self, 2)
	check(st.get_value("low_graphics") == false and st.get_value("tier") == 2 and is_equal_approx(root.scaling_3d_scale, 1.0), "HIGH applies")
	check(Q.NAMES.size() == 3 and Q.SCALE.size() == 3, "three tiers")


## The rulebook stays split: every standards/ file is listed in the GROK_STANDARDS.md index,
## every link in the index exists, and no topic file grows past 60 lines (load only what you need).
func test_standards_index() -> void:
	var index := FileAccess.get_file_as_string("res://GROK_STANDARDS.md")
	check(index.length() > 0, "GROK_STANDARDS.md index exists")
	var d := DirAccess.open("res://standards")
	check(d != null, "standards/ folder exists")
	if d == null:
		return
	var count := 0
	for f in d.get_files():
		if not f.ends_with(".md"):
			continue
		count += 1
		check(("standards/" + f) in index, f + " is listed in the index")
		var lines := FileAccess.get_file_as_string("res://standards/" + f).split("\n").size()
		check(lines <= 60, "%s is short (%d lines)" % [f, lines])
	check(count >= 10, "topic files present")
	for m in RegEx.create_from_string("\\((standards/[^)]+)\\)").search_all(index):
		check(FileAccess.file_exists("res://" + m.get_string(1)), m.get_string(1) + " exists")


## Your own music: GAME MUSIC off mutes only the Music bus; sound effects keep playing. On iPhone
## the game mixes with other apps' audio. (Android: Godot never grabs audio focus, so Spotify etc.
## keep playing; never add a plugin that does.)
func test_play_your_own_music() -> void:
	var s: Node = root.get_node("Settings")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	s.set_value("game_music", false)
	check(AudioServer.is_bus_mute(music) and not AudioServer.is_bus_mute(sfx), "GAME MUSIC off mutes music only")
	s.set_value("game_music", true)
	check(not AudioServer.is_bus_mute(music), "GAME MUSIC on brings it back")
	check(ProjectSettings.get_setting("audio/general/ios/mix_with_others", false), "iPhone mixes with other apps' music")


## Battery saver: paused/menu/idle = 30 fps, background = 5 fps + low-processor, play = full speed.
func test_battery_saver_states() -> void:
	var b: Node = root.get_node("Battery")
	b.set_state("saver")
	check(Engine.max_fps == 30, "saver caps at 30 fps")
	b.set_state("background")
	check(Engine.max_fps == 5 and OS.low_processor_usage_mode, "background drops to 5 fps, low-processor mode")
	b.set_state("play")
	check(Engine.max_fps == 60 and not OS.low_processor_usage_mode, "play is full speed")


## 7. Coach hints are short (no text walls).
func test_coach_hints_short() -> void:
	var re := RegEx.create_from_string('Coach\\.teach\\([^,]+,\\s*"[^"]+",\\s*"([^"]+)"')
	for f in ["res://scripts/character_test.gd", "res://scripts/game.gd"]:
		if not FileAccess.file_exists(f):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			check(m.get_string(1).split(" ", false).size() <= 4, "hint '%s' is 4 words or fewer" % m.get_string(1))
	# Rush teaches from a table of steps, not literal teach() calls.
	var g = load("res://scripts/game.gd").new()
	var steps: Array = g._coach_steps()
	check(steps.size() >= 5, "Rush has its five hints")
	var ids: Array = steps.map(func(st): return st[0])
	check(ids.has("dots") and ids.find("dots") > ids.find("end_turn"), "the action dots are taught after the first END TURN")
	check(str(steps[ids.find("run")][1]).contains("SERVES"), "the RUN hint says RUN is what serves the table")
	for st in steps:
		check(str(st[1]).split(" ", false).size() <= 4, "hint '%s' is 4 words or fewer" % st[1])
	g.free()


func test_tune_saves_applies_and_reports() -> void:
	var Tune = preload("res://scripts/tune_panel.gd")
	var feel: Node = root.get_node("Feel")
	var dm: Node = root.get_node("DebugMenu")
	Tune.clear()
	check(feel.is_in_group("tunable") and "feel" in Tune.kinds(self), "Feel is tunable")
	check(dm.tune_defaults.get("feel.shake_scale") == 1.0, "code value remembered")
	Tune.save_value("feel", "shake_scale", 2.0)
	feel.shake_scale = 1.0
	Tune.apply(feel)
	check(is_equal_approx(feel.shake_scale, 2.0), "saved value applied")
	var lines: PackedStringArray = Tune.changed_lines(self, dm.tune_defaults)
	check("feel.shake_scale = 2.0 (code 1.0)" in lines, "changed value reported: %s" % [lines])
	check("labels=tuning" in Tune.share_url("x"), "share link files a tuning issue")
	Tune.clear()
	feel.shake_scale = 1.0
	check(Tune.saved("feel", "shake_scale") == null, "reset clears saved values")


# ---------------------------------------------------------------- Rush rules (scripts/kitchen.gd)

func _kitchen() -> Kitchen:
	var k := Kitchen.new()
	k.all_open = true   # rule tests use the whole line; test_kitchen_stations_open covers the unlocks
	k.start(1)
	return k


## A dish goes the whole way: fire, cook, plate, walk to the pass, run. Ticket out, tips paid.
func test_kitchen_fire_to_table() -> void:
	var k := _kitchen()
	check(k.tickets.size() == 1 and k.tickets[0].items[0].dish == "BURGER", "first ticket is a burger")
	check(k.action_here(0) == "FIRE" and k.fire(0), "DEV fires at the grill")
	check(k.crew[0].ap == k.ap - 1, "firing costs 1 action")
	check(not k.plate(0), "can't plate a raw burger")
	k.end_turn()
	k.end_turn()
	check(k.pans[0].left == 0 and k.action_here(0) == "PLATE", "burger is up after 2 minutes")
	check(k.plate(0) and k.window.size() == 1 and k.window[0].dish == "BURGER", "plated up onto the pass window")
	check(not k.move(0, Kitchen.PASS_IX), "can't cross 4 stations on 2 actions")
	check(k.move(0, 2) and k.crew[0].ap == 0, "2 stations = 2 actions")
	k.end_turn()
	check(k.move(0, Kitchen.PASS_IX) and k.action_here(0) == "RUN" and k.run(0), "walk to the pass and run it")
	check(k.served == 1 and k.tips > 0 and k.ticket(1).is_empty(), "ticket out, tips paid")


## A finished pan left sitting burns: the dish goes back to wait (refire) and the cook there stresses.
func test_kitchen_burn_refires() -> void:
	var k := _kitchen()
	k.fire(0)
	for i in 2 + k.burn_after + 1:
		k.crew[0].acted = true   # stays working, so no rest
		k.end_turn()
	check(k.pans[0].is_empty(), "burnt pan is cleared")
	check(k.tickets[0].items[0].state == "wait", "dish is back to wait for a refire")
	check(k.crew[0].stress >= 2, "the grill cook took the burn (stress %d)" % k.crew[0].stress)


## Nobody cooks: tickets run out of time and walk. Working through red tickets stresses; idling rests.
func test_kitchen_walks_and_stress() -> void:
	var k := _kitchen()
	k.ticket_time = 3
	k.start(1)
	k.breaks = 0   # no second wind here: test_second_wind_and_ramp covers it
	k.crew[0].acted = true
	k.end_turn()
	check(k.crew[0].stress == 1, "worked through a red ticket: +1 stress")
	check(k.crew[1].stress == 0, "idle cook stays calm")
	k.crew[0].stress = 4
	k.end_turn()
	check(k.crew[0].stress == 2, "a turn off rests 2")
	for i in 10:
		k.end_turn()
	check(k.walked >= 1, "untouched tickets walk (%d)" % k.walked)
	k.crew[1].stress = k.stress_cap - 1
	k.crew[1].acted = true
	k.tickets.append({"id": 999, "table": 9, "items": [{"dish": "FRIES", "state": "wait"}], "time": 2, "big": false})
	k.end_turn()
	check(k.crew[1].out and k.crew[1].hand.is_empty(), "at the stress cap a cook walks out")


## A cook who walks out mid-carry puts the dish back to refire, so the ticket can still go out.
func test_kitchen_walkout_drops_plate() -> void:
	var k := _kitchen()
	k.start(1)
	k.breaks = 0
	var t: Dictionary = k.tickets[0]
	t.items[0].state = "carried"
	k.crew[1].hand = {"tid": t.id, "dish": t.items[0].dish}
	k.crew[1].stress = k.stress_cap - 1
	k.crew[1].acted = true
	t.time = 2   # red, so working adds the last point of stress
	k.end_turn()
	check(k.crew[1].out and k.crew[1].hand.is_empty(), "cook walked out")
	check(t.items[0].state == "wait", "the dropped plate goes back to refire (%s)" % t.items[0].state)




## The greedy bot gets most of service 1 out: the slice is playable, not a wall.
func test_kitchen_service1_beatable() -> void:
	var k := _kitchen()
	var total := k.tickets.size() + k.incoming.size()
	var guard := 0
	while not k.done and guard < 100:
		k.bot_turn()
		k.end_turn()
		guard += 1
	check(k.done, "service ends")
	check(k.served * 10 >= total * 7, "bot served %d of %d (needs 70%%)" % [k.served, total])
	check(k.walked < 3, "bot walked %d, under the game over line" % k.walked)


## A table walks while a cook holds its plate: the plate is binned and the cook's hands are free.
func test_kitchen_walked_plate_binned() -> void:
	var k := _kitchen()
	var t: Dictionary = k.tickets[0]
	t.items[0].state = "carried"
	k.crew[0].hand = {"tid": t.id, "dish": t.items[0].dish}
	t.time = 1
	k.end_turn()
	check(k.ticket(t.id).is_empty() and k.walked == 1, "the table walked")
	check(k.crew[0].hand.is_empty(), "the dead plate left DEV's hand (%s)" % k.crew[0].hand)


## Mid-service save: to_dict -> JSON -> from_dict plays on exactly like the original.
func test_kitchen_save_resumes_same_service() -> void:
	var a := Kitchen.new()
	a.start(2, 4242)
	for i in 5:
		a.bot_turn()
		a.end_turn()
	var b := Kitchen.new()
	var j := JSON.new()
	j.parse(JSON.stringify(a.to_dict()))
	check(b.from_dict(j.data), "loads back")
	check(b.turn == a.turn and b.walked == a.walked and b.served == a.served and b.tickets.size() == a.tickets.size(),
		"same minute, tables and tickets (turn %d/%d)" % [b.turn, a.turn])
	var guard := 0
	while not a.done and guard < 60:
		a.bot_turn(); a.end_turn()
		b.bot_turn(); b.end_turn()
		guard += 1
	check(a.served == b.served and a.walked == b.walked and a.tips == b.tips and b.done,
		"plays out identically (served %d/%d, walked %d/%d)" % [a.served, b.served, a.walked, b.walked])


## END TURN's quit warning predicts exactly who Kitchen.end_turn walks out, on random states.
func test_quit_warning_matches_end_turn() -> void:
	var g = load("res://scripts/game.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad := 0
	for i in 300:
		var k := Kitchen.new()
		k.start(1 + i % 3, i)
		for t in k.tickets:
			t.time = rng.randi_range(1, 6)
		for c in k.crew:
			c.stress = rng.randi_range(0, k.stress_cap - 1)
			c.acted = rng.randf() < 0.6
			c.at = rng.randi_range(0, Kitchen.PASS_IX)
		if rng.randf() < 0.5:
			k.pans[0] = {"tid": k.tickets[0].id, "dish": k.tickets[0].items[0].dish, "left": 0,
				"sat": rng.randi_range(0, k.burn_after), "rushed": false, "by": 0}
			k.tickets[0].items[0].state = "cooking"
		k.breaks = i % 2   # half the states have tonight's second wind left
		g.k = k
		var said: Array = g.cooks_quitting()
		var resting: Array = g.cooks_breaking()
		var was_out: Array = k.crew.map(func(c): return c.out)
		var shown: Array = []
		for c in k.crew.size():
			shown.append(g.stress_after(c))
		k.end_turn()
		for c in k.crew.size():   # the meter's preview is the stress END TURN really leaves (bar a second wind)
			if not was_out[c] and not k.crew[c].brk and k.crew[c].stress != shown[c]:
				bad += 1
		var took: Array = []
		for c in k.crew.size():
			if k.crew[c].brk:
				took.append(k.crew[c].name)
		if resting != took:
			bad += 1
		var walked: Array = []
		for c in k.crew.size():
			if k.crew[c].out and not was_out[c]:
				walked.append(k.crew[c].name)
		if said != walked:
			bad += 1
	check(bad == 0, "quit warning and stress preview matched end_turn on 300 random states (%d mismatches)" % bad)
	g.free()


## 8.5 plan #3 (build-84 review: one walkout snowballed into GAME OVER): the first cook who'd quit
## in a service takes five instead, once.
func test_second_wind_and_ramp() -> void:
	var k := _kitchen()
	k.tickets = [{"id": 95, "table": 5, "items": [{"dish": "STEAK", "state": "wait"}], "time": 2, "big": false}]
	k.incoming.clear()
	k.breaks = 1
	for c in k.crew:
		c.stress = k.stress_cap - 1
		c.acted = true
	k.end_turn()
	check(k.crew[0].brk and not k.crew[0].out and k.crew[0].stress == k.stress_cap - 3 and k.crew[0].ap == 0,
		"first cook over the cap takes five: stress %d, no moves" % k.crew[0].stress)
	check(k.crew[1].out, "the second wind is spent: the next one quits")
	check(k.events.any(func(e): return e.ends_with("TAKES FIVE")), "the status line says so")
	check(not k.can_act(0), "on break: can't act")
	var back := Kitchen.new()
	check(back.from_dict(JSON.parse_string(JSON.stringify(k.to_dict()))) and back.crew[0].brk and back.breaks == 0, "a break survives a save")
	k.end_turn()
	check(not k.crew[0].brk and k.crew[0].ap == k.ap and k.crew[0].stress == k.stress_cap - 5, "back after one turn, rested")
	check(Kitchen.count_for(7, 1, 1) == 7 and Kitchen.count_for(7, 1, 2) == 8 and Kitchen.count_for(7, 1, 3) == 9
		and Kitchen.count_for(7, 1, 4) == 9 and Kitchen.count_for(7, 1, 5) == 10, "ramp: 7, 8, 9, 9, 10")


## 8.5 plan #4 (Duff: "make the perks earn able like a level up system"): perks ride on the cook,
## each pays off as written, and they survive a save.
func test_cook_perks() -> void:
	var k := Kitchen.new()
	k.all_open = true
	k.cook_perks = {"DEV": ["fast_0", "walk"], "MO": ["run", "plate"]}
	k.start(1)
	check(k.has_perk(0, "fast_0") and not k.has_perk(1, "fast_0") and k.crew[0].perks.size() == 2, "perks ride on the cook")
	check(k.cook_time_by(0, "STEAK") == 2 and k.cook_time_by(1, "STEAK") == 3 and k.cook_time_by(0, "FRIES") == 1, "GRILL HAND: a minute off grill dishes only")
	k.crew[0].at = 0
	check(k.move_cost(0, 2) == 1 and k.move(0, 2) and k.crew[0].ap == k.ap - 1, "LIGHT FEET: first step free (2 stops for 1)")
	check(k.move_cost(0, 0) == 2, "only the first step each turn")
	k.tickets = [{"id": 97, "table": 7, "items": [{"dish": "FRIES", "state": "carried"}, {"dish": "WINGS", "state": "carried"}], "time": 9, "big": false}]
	k.window = [{"tid": 97, "dish": "FRIES"}]
	k.crew[1].at = Kitchen.PASS_IX
	check(k.is_free(1, "RUN") and k.run(1) and k.crew[1].ap == k.ap, "RUNNER: first RUN free")
	k.window = [{"tid": 97, "dish": "WINGS"}]
	check(not k.is_free(1, "RUN") and k.run(1) and k.crew[1].ap == k.ap - 1, "the second RUN costs a move")
	var back := Kitchen.new()
	check(back.from_dict(JSON.parse_string(JSON.stringify(k.to_dict()))) and back.has_perk(1, "plate") and back.crew[1].used.has("run")
		and back.crew[0].acts == k.crew[0].acts, "perks, used freebies and work done survive a save")
	k.end_turn()
	check(k.is_free(1, "RUN") and k.move_cost(0, 0) == 1, "freebies come back each turn")
	var plain := Kitchen.new()
	plain.start(1)
	check(plain.crew.all(func(c): return c.perks.is_empty()), "cooks start a night with no perks")


## Duff, Nov 26 ("Gone for the whole night"): a house cook who walked out sits out the rest of the night.
func test_gone_for_the_night() -> void:
	var k := Kitchen.new()
	k.gone = ["MO"]
	k.start(2, 5)
	check(k.crew.size() == 1 and k.crew[0].name == "DEV" and k.crew[0].at == 0, "MO gone: DEV runs the line alone")
	var k2 := Kitchen.new()
	k2.gone = ["DEV"]
	k2.hires = 1
	k2.start(2, 5)
	check(k2.crew.size() == 2 and k2.crew[0].name == "MO" and k2.crew[0].at == 2 and k2.crew[1].name == Kitchen.TEMPS[0], "DEV gone: MO plus the temp")
	var guard := 0
	while not k2.done and guard < 60:
		k2.bot_turn()
		k2.end_turn()
		guard += 1
	check(guard < 60, "a short-handed service still plays out")
	var k3 := Kitchen.new()
	k3.gone = ["DEV", "MO"]
	k3.start(3, 5)
	check(k3.crew.size() == 1 and k3.crew[0].name == "DEV", "both gone, no temp: DEV comes back so the line is never empty")


## The game screen's save carries the service in progress, and score only counts finished services.
func test_rush_save_no_double_count() -> void:
	var g = load("res://scripts/game.gd").new()
	g.k = Kitchen.new()
	g.k.start(2, 7)
	g._night_before = 3
	g.score = 7
	var st: Dictionary = g.state()
	check(int(st.score) == 3, "mid-service save stores finished services only (%s)" % st.score)
	check(st.has("kitchen") and int(st.kitchen.service) == 2, "service in progress is saved")
	g.between = true
	check(not g.state().has("kitchen"), "between services the next service starts fresh")
	g.free()


## A v1 save (no mid-service state, had lives) still loads.
func test_save_migrates_v1() -> void:
	var sv = load("res://scripts/save_game.gd").new()
	var d: Dictionary = sv._migrate({"_version": 1, "level": 3, "score": 9, "lives": 2})
	check(int(d.level) == 3 and int(d.score) == 9 and not d.has("lives") and int(d._version) == 6, "v1 -> v6")
	sv.free()


## Difficulty curve (greedy bot, 100 seeds): service 2 is beatable, service 3 is harder still.
func test_kitchen_service_curve() -> void:
	var over := {2: 0, 3: 0}
	for n in [2, 3]:
		for sd in 100:
			var k := Kitchen.new()
			k.start(n, sd + 7)
			var guard := 0
			while not k.done and guard < 80:
				k.bot_turn()
				k.end_turn()
				guard += 1
				if k.walked >= 3 or k.crew.all(func(c): return c.out):
					over[n] += 1
					break
	check(over[2] <= 55, "service 2: bot game over in %d%% (want <= 55)" % over[2])
	check(over[3] > over[2], "service 3 is harder (%d%% vs %d%%)" % [over[3], over[2]])


## Nov 25 playtest: the player picks which ticket FIRE cooks; without a pick it's the most urgent.
func test_kitchen_pick_ticket() -> void:
	var k := _kitchen()
	k.tickets = [
		{"id": 50, "table": 5, "items": [{"dish": "STEAK", "state": "wait"}], "time": 3, "big": false},
		{"id": 60, "table": 6, "items": [{"dish": "BURGER", "state": "wait"}], "time": 9, "big": false}]
	check(k.fire_pick(0).t.id == 50, "no pick: the most urgent ticket")
	check(k.fire_pick(0, 60).t.id == 60, "picked: that ticket")
	check(k.fire_pick(0, 999).t.id == 50, "a pick with nothing at this station falls back to most urgent")
	check(k.act_here(0, 60) and k.pans[0].tid == 60 and k.pans[0].dish == "BURGER", "FIRE cooked the picked table")


## RUSH: a minute off a cooking pan, once a turn, for stress. The bot never rushes.
func test_kitchen_rush() -> void:
	var k := _kitchen()
	k.tickets = [{"id": 70, "table": 7, "items": [{"dish": "STEAK", "state": "wait"}], "time": 9, "big": false}]
	k.fire(0)
	check(k.action_here(0) == "RUSH" and k.action_here(0, false) == "", "a cooking pan offers RUSH (not to the bot)")
	var st: int = k.crew[0].stress
	check(k.rush(0) and k.pans[0].left == 2 and k.crew[0].stress == st + k.rush_stress, "rush: a minute off, stress up")
	check(not k.rush(0), "only once a turn")
	k.end_turn()
	check(k.pans[0].left == 1 and k.rush(0) and k.pans[0].left == 0, "next turn it can rush again")
	check(k.action_here(0) == "PLATE", "a 3-minute steak is up after one end of turn")


## The pass window: plates go up, any cook at the pass runs them; a walked table's plates are binned.
func test_kitchen_window() -> void:
	var k := _kitchen()
	k.tickets = [
		{"id": 80, "table": 8, "items": [{"dish": "FRIES", "state": "wait"}], "time": 9, "big": false},
		{"id": 81, "table": 9, "items": [{"dish": "SCAMPI", "state": "wait"}], "time": 1, "big": false}]
	k.move(0, 1)
	k.fire(0)
	k.crew[1].at = 2
	k.fire(1)
	k.end_turn()   # both are 1-minute dishes; table 9 walks at the end of this turn
	check(k.walked == 1, "table 9 walked")
	k.crew[1].at = 2
	check(k.pans[2].is_empty(), "its pan was cleared")
	check(k.plate(0) and k.window.size() == 1, "fries up on the window")
	check(k.crew[0].hand.is_empty(), "DEV's hands stay free")
	k.crew[1].at = Kitchen.PASS_IX
	check(k.action_here(1) == "RUN" and k.run(1) and k.served == 1, "MO runs it from the pass")
	k.window = [{"tid": 999, "dish": "PASTA"}]
	k.tickets = [{"id": 999, "table": 3, "items": [{"dish": "PASTA", "state": "carried"}], "time": 1, "big": false}]
	k.end_turn()
	check(k.window.is_empty(), "a walked table's plate leaves the window")


## A v2 save from before the window: a plate in a cook's hand moves onto the window.
func test_save_migrates_v2() -> void:
	var sv = load("res://scripts/save_game.gd").new()
	var a := Kitchen.new()
	a.start(1)
	var kd: Dictionary = a.to_dict()
	kd.erase("window")
	kd.crew[0].hand = {"tid": 1, "dish": "BURGER"}
	var d: Dictionary = sv._migrate({"_version": 2, "level": 1, "score": 0, "kitchen": kd})
	check(int(d._version) == 6 and d.kitchen.window.size() == 1 and d.kitchen.crew[0].hand.is_empty(), "hand -> window")
	var b := Kitchen.new()
	check(b.from_dict(d.kitchen) and b.window.size() == 1, "and it loads")
	sv.free()


## Grades (Nov 25): a score out of 100 (out 60, speed 25, clean pans 15, -10 a walk, critic +-8)
## lands every letter, not just A/C/F.
func test_kitchen_grade() -> void:
	var k := _kitchen()
	k.total = 6
	k.served = 6
	k.speed = 6 * 0.8
	check(k.grade() == "A+" and k.score_parts().total == 100, "6/6 fast and clean = A+ (%s)" % k.score_parts())
	k.speed = 6 * 0.55
	check(k.grade() == "B", "6/6 clean, middling speed = B now (8.5 plan #4: A needs 90; %d)" % k.score_parts().total)
	k.speed = 6 * 0.6
	check(k.grade() == "A", "6/6 clean, a bit quicker = A (%d)" % k.score_parts().total)
	check(Kitchen.GRADE_BONUS.A > Kitchen.GRADE_BONUS.B and Kitchen.GRADE_BONUS.F > 0, "every grade pays a bonus, better grades more")
	k.burns = 2
	check(k.grade() == "B", "two burns drop it to B (%d)" % k.score_parts().total)
	k.burns = 0
	k.served = 5
	k.walked = 1
	k.speed = 5 * 0.55
	check(k.grade() == "C", "one walked = C (%d)" % k.score_parts().total)
	k.total = 7
	k.served = 5
	k.walked = 2
	k.speed = 5 * 0.55
	check(k.grade() == "D", "two of seven walked = D (%d)" % k.score_parts().total)
	k.served = 0
	k.walked = 0
	k.speed = 0.0
	check(k.grade() == "F", "nothing out = F")
	var seen := {}
	for n in [1, 2, 3]:
		for sd in 60:
			var b := Kitchen.new()
			b.start(n, sd + 7)
			var guard := 0
			while not b.done and guard < 80 and b.walked < 3 and not b.crew.all(func(c): return c.out):
				b.bot_turn()
				b.end_turn()
				guard += 1
			if b.walked < 3:
				seen[b.grade()] = true
	check(seen.size() >= 5, "the bot's services land at least 5 different letters (%s)" % str(seen.keys()))


## Tips carry between services: upgrades cost cash, are bought once, and change the next service.
func test_upgrades_carry() -> void:
	var owned: Array = []
	check(Upgrades.buy("comps", 40, owned) == -1 and owned.is_empty(), "can't afford")
	check(Upgrades.buy("lamps", 70, owned) == 40 and owned == ["lamps"], "bought")
	check(Upgrades.buy("lamps", 70, owned) == -1, "only once")
	check(Upgrades.buy("nope", 999, owned) == -1, "unknown id")
	owned.append_array(["meal", "iron", "comps"])
	var u := Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, owned)
	check(u.ticket_time == 10 and u.stress_cap == 7 and u.rush_stress == 0 and u.lives == 4, "all four apply")
	for id in Upgrades.ALL:
		check(String(Upgrades.ALL[id].says).length() <= 26, id + " fits the button")
	var sv = load("res://scripts/save_game.gd").new()
	var d: Dictionary = sv._migrate({"_version": 3, "level": 2, "score": 8})
	check(int(d._version) == 6 and int(d.cash) == 0 and (d.perks as Array).is_empty(), "v3 -> v4")
	sv.free()


## Tap a dish (Duff, Nov 25): FIRE cooks that exact dish when it waits at this station; a dish
## from another station, or one already on, falls back to the table's first dish here.
func test_fire_picked_dish() -> void:
	var k := Kitchen.new()
	k.start(1, 3)
	k.tickets = [{"id": 70, "table": 7, "items": [{"dish": "BURGER", "state": "wait"},
		{"dish": "STEAK", "state": "wait"}, {"dish": "FRIES", "state": "wait"}], "time": 9, "big": false}]
	k.crew[0].at = 0
	check(k.fire_pick(0, 70, -1).item.dish == "BURGER", "no dish picked: the first grill dish")
	check(k.fire_pick(0, 70, 1).item.dish == "STEAK", "the tapped steak")
	check(k.fire_pick(0, 70, 2).item.dish == "BURGER", "fries cook at the fryer: back to the table's grill dish")
	check(k.act_here(0, 70, true, 1) and k.pans[0].dish == "STEAK" and k.tickets[0].items[1].state == "cooking", "FIRE cooked the steak")
	check(k.fire_pick(0, 70, 1).is_empty() or k.fire_pick(0, 70, 1).item.dish == "BURGER", "steak on: falls back")


## A pan remembers the cook who fired it, through a save (the screen picks that cook on a station tap).
func test_pan_owner() -> void:
	var k := Kitchen.new()
	k.start(1, 3)
	k.crew[1].at = 0
	check(k.act_here(1) and int(k.pans[0].by) == 1, "MO fired the grill pan")
	var k2 := Kitchen.new()
	k2.from_dict(JSON.parse_string(JSON.stringify(k.to_dict())))
	check(int(k2.pans[0].by) == 1, "who fired it survives a save")
	var old: Dictionary = k.to_dict()
	(old.pans[0] as Dictionary).erase("by")
	k2.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(int(k2.pans[0].by) == -1, "an old save's pan has no owner")


## Trays (Duff, Nov 25): one RUN carries one plate, the server tray 2, the entree tray 4 (after the
## server tray). The most urgent table goes first and its other plates ride with it.
func test_tray_runs() -> void:
	var owned: Array = []
	check(Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, owned).tray == 1, "one plate to start")
	check(Upgrades.buy("tray2", 999, owned) == -1, "entree tray needs the server tray")
	check(Upgrades.shown(owned).has("tray") and not Upgrades.shown(owned).has("tray2"), "shop lists the server tray first")
	check(Upgrades.buy("tray", 100, owned) == 70, "server tray bought")
	check(Upgrades.shown(owned).has("tray2") and not Upgrades.shown(owned).has("tray"), "then the entree tray")
	check(Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, owned).tray == 2, "server tray = 2")
	check(Upgrades.buy("tray2", 100, owned) == 10, "entree tray bought")
	check(Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, owned).tray == Upgrades.MAX_TRAY, "entree tray = 4")
	for tray in [1, 2, 4]:
		var k := Kitchen.new()
		k.start(1, 7)
		k.tray = tray
		var b := {"id": 91, "table": 9, "items": [{"dish": "BURGER", "state": "carried"}], "time": 8, "big": false}
		var a := {"id": 92, "table": 4, "items": [{"dish": "FRIES", "state": "carried"},
			{"dish": "BURGER", "state": "carried"}], "time": 2, "big": false}
		k.tickets = [b, a]
		k.window = [{"tid": 91, "dish": "BURGER"}, {"tid": 92, "dish": "FRIES"}, {"tid": 92, "dish": "BURGER"}]
		var before := k.window.size()
		k.crew[0].at = Kitchen.PASS_IX
		var ap: int = k.crew[0].ap
		check(k.run(0) and k.crew[0].ap == ap - 1, "tray %d: one action" % tray)
		check(before - k.window.size() == mini(tray, before), "tray %d: carried %d" % [tray, mini(tray, before)])
		if tray >= 2:
			check(k.ticket(92).is_empty() and (tray > 2) == k.ticket(91).is_empty(), "tray %d: the urgent table went out whole first" % tray)
		else:
			check(not k.ticket(92).is_empty() and k.window.filter(func(w): return w.tid == 92).size() == 1, "tray 1: one plate, the urgent table's")
		var k2 := Kitchen.new()
		k2.from_dict(JSON.parse_string(JSON.stringify(k.to_dict())))
		check(k2.tray == tray, "tray %d survives a save" % tray)


## Services 2+ roll a twist; each one does what its card says, and it survives a save.
func test_kitchen_events() -> void:
	var seen := {}
	for sd in 40:
		var k := Kitchen.new()
		k.start(4, sd + 1)
		seen[k.event] = true
	check(seen.size() == Kitchen.EVENT_IDS.size() and not seen.has(""), "every twist shows up in service 4 (%s)" % [seen.keys()])
	# 8.5 plan #4: service 2 rolls a gentle twist (VIP or critic), service 3 none (cold opens).
	var mild := {}
	for sd in 30:
		var two := Kitchen.new()
		two.start(2, sd + 1)
		mild[two.event] = true
		var three := Kitchen.new()
		three.start(3, sd + 1)
		mild["s3:" + three.event] = true
	check(mild.has("vip") and mild.has("critic") and mild.size() == 3 and mild.has("s3:"), "service 2: VIP or critic only; service 3: none (%s)" % [mild.keys()])
	var one := Kitchen.new()
	one.start(1, 5)
	check(one.event == "", "service 1 is plain")
	var k := _event_kitchen("tour")
	var mid: int = k.incoming.size() / 2 - 1
	check(k.incoming[mid].arrive == k.incoming[mid + 2].arrive, "bus tour: three tables on one minute")
	k = _event_kitchen("fritz")
	check(k.cook_time("STEAK") == 4 and k.cook_time("FRIES") == 1, "fritz: grill a minute slower, fryer not")
	k = _event_kitchen("vip")
	var vt: Array = k.incoming.filter(func(inc): return inc.ticket.get("vip", false))
	check(vt.size() == 1, "one VIP ticket")
	k.tickets = [{"id": 90, "table": 9, "items": [{"dish": "FRIES", "state": "carried"}], "time": 5, "big": false, "vip": true}]
	k.window = [{"tid": 90, "dish": "FRIES"}]
	k.crew[0].at = Kitchen.PASS_IX
	k.run(0)
	check(k.tips == (2 + 5) * 3, "VIP pays triple (%d)" % k.tips)
	k.tickets = [{"id": 91, "table": 8, "items": [{"dish": "FRIES", "state": "wait"}], "time": 1, "big": false, "vip": true}]
	k.incoming.clear()
	k.end_turn()
	check(k.walked == 2, "a walked VIP counts as two")
	k = _event_kitchen("critic")
	k.served = k.total
	k.speed = k.total * 0.55
	var plain: int = k.score_parts().total
	k.critic = "served"
	check(k.score_parts().total == mini(plain + 8, 100), "serving the critic is worth 8 points")
	k.critic = "walked"
	check(k.score_parts().total == plain - 8, "walking the critic costs 8")
	# 8.5 plan #2: HEAT WAVE adds a point to working cooks every fourth turn; PARTY OF 12 swaps in a big table.
	k = _event_kitchen("heat")
	k.tickets = [{"id": 92, "table": 7, "items": [{"dish": "FRIES", "state": "wait"}], "time": 9, "big": false}]
	k.incoming.clear()
	k.turn = 1
	k.crew[0].acted = true
	k.crew[0].stress = 0
	k.crew[1].stress = 3
	k.end_turn()
	check(k.crew[0].stress == 1 and k.crew[1].stress == 1, "heat: +1 on a worker, a rester still rests (%d, %d)" % [k.crew[0].stress, k.crew[1].stress])
	k.crew[0].acted = true
	k.end_turn()
	check(k.crew[0].stress == 1, "heat skips the even turns")
	var pk := _event_kitchen("party")
	var plain_k := Kitchen.new()
	plain_k.with_events = false
	plain_k.start(2, 11)
	check(pk.total == plain_k.total and pk.incoming.size() == plain_k.incoming.size()
		and pk.incoming.filter(func(inc): return inc.ticket.big).size() > plain_k.incoming.filter(func(inc): return inc.ticket.big).size(),
		"party: a big table takes a small one's place")
	var short: Kitchen = null   # a 2-ticket night that rolls the party: it still lands mid-service, in order
	for sd in 400:
		var sk := Kitchen.new()
		sk.first_tickets = 1
		sk.start(4, sd + 1)
		if sk.event == "party":
			short = sk
			break
	check(short != null, "a short night rolls PARTY OF 12 within 400 seeds")
	if short == null:
		return
	var arr: Array = short.incoming.map(func(inc): return int(inc.arrive))
	var sorted_arr := arr.duplicate()
	sorted_arr.sort()
	check(short.incoming.any(func(inc): return inc.ticket.big and int(inc.arrive) >= short.turns / 3) and arr == sorted_arr,
		"party: mid-service on a short night, arrivals in order (%s)" % [arr])
	var back := Kitchen.new()
	var vk := _event_kitchen("vip")
	check(back.from_dict(JSON.parse_string(JSON.stringify(vk.to_dict()))) and back.event == "vip"
		and back.incoming.any(func(inc): return inc.ticket.get("vip", false)), "twist and VIP flag survive a save")


func _event_kitchen(ev: String) -> Kitchen:
	var k := Kitchen.new()
	k.with_events = false
	k.start(2, 11)
	k.event = ev
	k._set_up_event()
	return k


## The line grows by service: grill + fry, then saute (service 2), then cold (service 3). Closed
## stations take no tickets, can't be stood at, and are walked past for free.
func test_kitchen_stations_open() -> void:
	for n in [1, 2, 3]:
		var k := Kitchen.new()
		k.with_events = false
		k.start(n, 77)
		var sts := {}
		for inc in k.incoming:
			for it in inc.ticket.items:
				sts[Kitchen.DISHES[it.dish].st] = true
		for t in k.tickets:
			for it in t.items:
				sts[Kitchen.DISHES[it.dish].st] = true
		var want: Array = [[0, 1], [0, 1, 2], [0, 1, 2, 3]][n - 1]
		check(sts.keys().all(func(x): return want.has(x)), "service %d only orders from open stations (%s)" % [n, sts.keys()])
		check(k.crew.all(func(c): return k.is_open(c.at)), "service %d cooks start at open stations" % n)
	var one := Kitchen.new()
	one.start(1, 5)
	check(not one.move(0, 2) and not one.move(0, 3), "can't stand at a closed station")
	check(one.walk_cost(1, Kitchen.PASS_IX) == 1, "fry to pass skips the closed saute and cold (1 action)")
	check(one.move(1, Kitchen.PASS_IX) and one.crew[1].ap == one.ap - 1, "and it really costs 1")
	var three := Kitchen.new()
	three.start(3, 5)
	check(three.walk_cost(0, Kitchen.PASS_IX) == 4, "service 3: grill to pass is 4 stops")
	var sv = load("res://scripts/save_game.gd").new()
	var old := Kitchen.new()
	old.all_open = true
	old.start(1, 3)
	var kd: Dictionary = old.to_dict()
	kd.pans = [{}, {}, {"tid": 1, "dish": "PASTA", "left": 1, "sat": 0, "rushed": false}]
	kd.crew[1].at = 3
	kd.erase("all_open")
	var d: Dictionary = sv._migrate({"_version": 4, "level": 1, "score": 0, "cash": 0, "perks": [], "kitchen": kd})
	var back := Kitchen.new()
	check(back.from_dict(d.kitchen) and back.crew[1].at == Kitchen.PASS_IX and back.pans[2].dish == "PASTA"
		and back.pans[3].is_empty() and back.is_open(2), "a v4 mid-service save loads onto the longer line")
	sv.free()


## IGN review (build 70): two tickets both read T22. Every ticket in a service gets its own table.
func test_table_numbers_unique() -> void:
	var dup := 0
	for seed in 200:
		var k := Kitchen.new()
		k.start(1 + seed % 5, seed)
		var tables: Array = k.tickets.map(func(t): return t.table) + k.incoming.map(func(i): return i.ticket.table)
		for t in tables:
			if tables.count(t) > 1:
				dup += 1
				break
	check(dup == 0, "no service deals two tickets the same table number (%d of 200 did)" % dup)


## 8.5 pass: the shop's THIRD COOK adds a third cook to the roster, starting at the pass; the
## second ticket lands with the first from service 2 on; service 4 is a ticket lighter.
func test_temp_cook_and_curve_tweaks() -> void:
	var owned: Array = []
	check(Upgrades.apply({}, owned).hires == 0, "no temp without the perk")
	owned.append("temp")
	check(Upgrades.apply({}, owned).hires == 1, "temp perk = one hire")
	var k := Kitchen.new()
	k.hires = 1
	k.start(2, 5)
	check(k.crew.size() == 3 and k.crew[2].at == Kitchen.PASS_IX and k.crew[2].name == Kitchen.TEMPS[0], "temp cook at the pass")
	var back := Kitchen.new()
	check(back.from_dict(JSON.parse_string(JSON.stringify(k.to_dict()))) and back.crew.size() == 3, "temp cook survives a save")
	var plain := Kitchen.new()
	plain.start(2, 5)
	check(plain.crew.size() == 2, "no hire, two cooks")
	check(plain.tickets.size() >= 2, "service 2's second ticket comes at once")
	var s1 := Kitchen.new()
	s1.start(1, 5)
	check(s1.tickets.size() == 1 and not s1.incoming.is_empty() and int(s1.incoming[0].arrive) == 1, "service 1 still eases in")
	var s3 := Kitchen.new()
	s3.start(3, 5)
	var s4 := Kitchen.new()
	s4.start(4, 5)
	check(s4.total == s3.total, "service 4 is a ticket lighter than the +1 curve (same as service 3)")


## Permanent third cook: one payment, and previous paid rentals migrate without another charge.
func test_shop_pushes_back() -> void:
	var owned: Array = []
	check(Upgrades.price("temp") == 45, "third cook costs $45")
	check(Upgrades.buy("temp", 44, owned) == -1 and owned.is_empty(), "cannot afford crew")
	check(Upgrades.buy("temp", 45, owned) == 0 and owned == ["temp"], "crew bought once")
	check(Upgrades.buy("temp", 100, owned) == -1 and owned == ["temp"], "no duplicate charge")
	check(Upgrades.load_tickets([]) == 0 and Upgrades.load_tickets(["meal"]) == 0 and Upgrades.load_tickets(["meal", "lamps"]) == 1
		and Upgrades.load_tickets(["meal", "lamps", "iron", "tray"]) == 2, "one table per two upgrades")
	var sv = load("res://scripts/save_game.gd").new()
	var old: Dictionary = sv._migrate({"_version": 5, "cash": 73, "perks": ["tray"], "temp_buys": 2})
	check(int(old._version) == 6 and old.perks == ["tray", "temp"] and old.cash == 73, "past hires unlock crew without charge")
	var active: Dictionary = sv._migrate({"_version": 5, "perks": ["temp"], "temp_buys": 1})
	check(active.perks == ["temp"], "active hire migrates without duplication")
	var legacy := Kitchen.new()
	legacy.hires = 1
	legacy.start(3, 9)
	legacy.turn = 4
	var legacy_state := {"_version": 5, "level": 3, "cash": 9, "perks": ["temp"], "temp_buys": 1, "kitchen": legacy.to_dict()}
	sv.path = "user://test_crew_v5.json"
	var f := FileAccess.open(sv.path, FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy_state))
	f.close()
	var restored: Dictionary = sv.read()
	var resumed := Kitchen.new()
	check(resumed.from_dict(restored.kitchen) and resumed.crew.size() == 3 and resumed.turn == 4 and restored.cash == 9,
		"legacy mid-service save restores Jo, cash and turn")
	check(sv.write(restored) and sv.read().perks == ["temp"] and not Upgrades.can_buy("temp", 100, sv.read().perks),
		"migrated ownership stays on disk and blocks another charge")
	sv.clear()
	var fresh: Dictionary = sv._migrate({"_version": 5, "perks": [], "temp_buys": 0})
	check(fresh.perks.is_empty(), "old unpaid save keeps two cooks")
	sv.free()


## CROSS PREP (Duff, Nov 26): a marked dish can't fire until a cook at its prep station pulls the
## ingredient (any station, e.g. steak strips from the grill for a salad). Saves and loads intact.
func test_cross_prep() -> void:
	var k := Kitchen.new()
	k.with_events = false
	k.start(4, 3)
	for i in k.pans.size():
		k.pans[i] = {}
	k.tickets = [{"id": 70, "table": 7, "items": [{"dish": "SALAD", "state": "wait", "needs": 0}], "time": 8, "big": false, "t0": 8}]
	k.crew[0].at = 3
	k.crew[0].ap = 3
	check(k.action_here(0) == "" and not k.fire(0), "a salad waiting on steak strips can't fire at COLD")
	check(Kitchen.prep_name(k.tickets[0].items[0]) == "STEAK STRIPS", "the salad needs steak strips")
	k.crew[0].at = 0
	check(k.action_here(0) == "PREP" and k.act_here(0), "the grill preps it")
	check(not k.tickets[0].items[0].has("needs") and k.crew[0].ap == 2, "prepped for one move")
	k.crew[0].at = 3
	check(k.action_here(0) == "FIRE" and k.fire(0), "then COLD fires it")
	var d := k.to_dict()
	var k2 := Kitchen.new()
	k.tickets[0].items.append({"dish": "PASTA", "state": "wait", "needs": 3})
	d = JSON.parse_string(JSON.stringify(k.to_dict()))
	check(k2.from_dict(d) and int(k2.tickets[0].items[1].needs) == 3, "the prep mark survives a save")
	var m := _event_kitchen("prep")
	var marked := 0
	var dishes := 0
	for inc in m.incoming:
		for it in inc.ticket.items:
			dishes += 1
			if it.has("needs"):
				marked += 1
				check(int(it.needs) != Kitchen.DISHES[it.dish].st, "prepped somewhere else")
	check(marked > 0 and marked <= (dishes + 2) / 3, "about one dish in three (%d of %d)" % [marked, dishes])


## DOUBLE BURNERS (shop): one FIRE cooks the same dish for two tables; PLATE sends both up; a
## burn refires both.
func test_double_burners() -> void:
	var k := Kitchen.new()
	k.with_events = false
	k.batch = 2
	k.start(2, 3)
	for i in k.pans.size():
		k.pans[i] = {}
	k.tickets = [{"id": 81, "table": 1, "items": [{"dish": "FRIES", "state": "wait"}], "time": 5, "big": false, "t0": 5},
		{"id": 82, "table": 2, "items": [{"dish": "FRIES", "state": "wait"}, {"dish": "WINGS", "state": "wait"}], "time": 7, "big": false, "t0": 7}]
	k.crew[0].at = 1
	k.crew[0].ap = 3
	check(k.fire(0) and k.pans[1].get("more", []) == [82], "one FIRE, fries for two tables")
	check(k.tickets[1].items[1].state == "wait", "the wings wait their turn")
	k.end_turn()
	k.crew[0].at = 1
	check(k.plate(0) and k.window.size() == 2, "PLATE puts both up")
	# The pan's first table walks: the rider's fries keep cooking for it, nothing is stuck.
	k.window.clear()
	k.tickets = [{"id": 83, "table": 3, "items": [{"dish": "FRIES", "state": "wait"}], "time": 1, "big": false, "t0": 1},
		{"id": 84, "table": 4, "items": [{"dish": "FRIES", "state": "wait"}], "time": 7, "big": false, "t0": 7}]
	k.crew[0].at = 1
	k.crew[0].ap = 3
	k.fire(0)
	k.end_turn()
	check(k.ticket(83).is_empty() and not k.pans[1].is_empty() and k.pans[1].tid == 84 and not k.pans[1].has("more"),
		"a walked first table hands the pan to the other one")
	var u := Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, ["burners"])
	check(u.batch == 2 and Upgrades.apply({"ticket_time": 9, "stress_cap": 6, "rush_stress": 1, "lives": 3}, []).batch == 1, "the shop sets it")


## The studio fox (docs/MASCOT.md): on service 3 (the quiet one) it runs through halfway, and the
## calmest cook loses that turn chasing it. Once a night, never on a twist night, survives a save.
func test_fox_cameo() -> void:
	for n in [1, 2, 4, 5]:
		var q := Kitchen.new()
		q.start(n, 9)
		check(q.fox_turn == -1, "no fox in service %d" % n)
	var k := Kitchen.new()
	k.start(3, 9)
	check(k.event == "" and k.fox_turn == k.turns / 2, "service 3: the fox comes halfway")
	var guard := 0
	while k.turn < k.fox_turn - 1 and guard < 40:
		k.end_turn()
		guard += 1
	k.crew[0].stress = 4   # resting drops 2 at END TURN: MO stays the calmer one
	k.crew[1].stress = 1
	k.end_turn()
	check(k.crew[1].get("fox", false) and k.crew[1].ap == k.ap - k.fox_cost and not k.crew[0].get("fox", false) and k.crew[0].ap == k.ap,
		"the calmer cook chases it and loses %d moves" % k.fox_cost)
	check(k.events.any(func(e): return String(e).begins_with("FOX IN THE KITCHEN")), "the news line says so")
	var k2 := Kitchen.new()
	check(k2.from_dict(JSON.parse_string(JSON.stringify(k.to_dict()))) and k2.crew[1].get("fox", false) and k2.fox_turn == k.fox_turn, "a save keeps it")
	k.end_turn()
	check(not k.crew[1].get("fox", false) and k.crew[1].ap == k.ap, "one turn only")
	var plain := Kitchen.new()
	plain.with_events = false
	plain.start(3, 9)
	check(plain.fox_turn == -1, "plain services (sweeps) have no fox")


func test_tap_command() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.k.start(1, 7)
	game.sel = 0
	game._after_move()
	var pos: Vector2 = game.cook_pos(1) + Vector2(80, 0)
	game._cook_draw[1] = pos
	var ap: int = game.k.crew[1].ap
	game.tap(pos)
	check(game.sel == 1 and game.k.crew[1].ap == ap, "visible moving cook selects without spending AP")
	game.sel = 1
	var cost: int = game.k.move_cost(1, 0)
	game.tap(game.station_rect(0).get_center())
	check(game.sel == 1 and game.k.crew[1].at == 0 and game.k.crew[1].ap == ap - cost, "occupied station moves selected cook")
	var before: Dictionary = game.k.to_dict()
	game.tap(game.station_rect(0).get_center())
	check(game.k.to_dict() == before, "same station never acts")
	game.tap(Vector2(1, game.station_rect(0).end.y + 150))
	check(game.sel == 1 and game.k.to_dict() == before, "blank tap does not select or mutate")
	game.queue_free()
	await process_frame


func test_drag_command() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.k.start(1, 7)
	game._cook_draw.clear()
	game.sel = 0
	var start: Vector2 = game.cook_visual_pos(1)
	var target: Vector2 = game.station_rect(0).get_center()
	var ap: int = game.k.crew[1].ap
	var cost: int = game.k.move_cost(1, 0)
	var down := InputEventScreenTouch.new()
	down.index = 2
	down.pressed = true
	down.position = start
	game._field_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = target
	game._field_input(drag)
	check(game._dragging and game.k.crew[1].ap == ap, "drag previews without committing")
	var other := InputEventScreenTouch.new()
	other.index = 3
	other.position = target
	game._field_input(other)
	check(game._dragging, "second finger cannot end active drag")
	var up := InputEventScreenTouch.new()
	up.index = 2
	up.position = target
	game._field_input(up)
	check(game.sel == 1 and game.k.crew[1].at == 0 and game.k.crew[1].ap == ap - cost, "valid touch release commits one move")
	var snapshot: Dictionary = game.k.to_dict()
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = game.station_rect(1).get_center()
	mouse.pressed = true
	game._field_input(mouse)
	mouse.pressed = false
	game._field_input(mouse)
	check(game.k.to_dict() == snapshot, "emulated mouse does not double commit")
	game._cook_draw.clear()
	down.position = game.cook_visual_pos(1)
	game._field_input(down)
	game._field_input(drag)
	game._cancel_gesture()
	game._field_input(up)
	check(game.k.to_dict() == snapshot, "cancelled drag has no effect")
	game.queue_free()
	await process_frame
