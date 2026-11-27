extends Node
## Autoload "Save": the run in progress, one JSON file. Games call Save.write(state) at every
## checkpoint and the game scene calls it again on pause and when the phone sends the app to
## the background (a call, a notification, the home button). Title shows CONTINUE when
## Save.exists(). GAME OVER calls Save.clear().
##
## Writes go to a temp file first, then replace the real one, so a kill mid-write can't leave
## a half-written save.

const VERSION := 8   # 6: paid third-cook ownership no longer expires; migrate prior hires
# 2 (Rush, Nov 25): adds "kitchen", the service in progress; "lives" dropped
# 3 (Rush, Nov 25 playtest): the kitchen gains a pass "window"; plates in a cook's hand move onto it
# 5 (Rush, Nov 25): a COLD station before the pass (PASS 3 -> 4, a 4th pan); a service saved before it
#   keeps every station open (its tickets may need saute in service 1)
# 4 (Rush, Nov 25): "cash" (banked tips) and "perks" (upgrades bought tonight) carry between services
var path := "user://run.json"


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp")


func write(state: Dictionary) -> bool:
	var data := state.duplicate(true)
	data["_version"] = VERSION
	data["_saved_at"] = Time.get_unix_time_from_system()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	return DirAccess.rename_absolute(abs_tmp, abs_path) == OK


## The saved state, or {} if there's none (or it's unreadable).
func read() -> Dictionary:
	if not exists():
		return {}
	# Killed between "delete old" and "rename new" in write(): the temp file is the save.
	var p := path if FileAccess.file_exists(path) else path + ".tmp"
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	return _migrate(j.data)


func clear() -> void:
	for p in [path, path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Old saves keep loading: bump VERSION and upgrade here when the save format changes.
func _migrate(d: Dictionary) -> Dictionary:
	if int(d.get("_version", 1)) < 2:
		d.erase("lives")   # v1 had no mid-service state: CONTINUE starts the saved service fresh
		d["_version"] = 2
	if int(d.get("_version", 1)) < 3:
		var kd: Variant = d.get("kitchen", null)
		if kd is Dictionary and not kd.has("window"):
			var win: Array = []
			for c in kd.get("crew", []):   # a plate in hand goes up on the window (run() still takes hands too)
				if c is Dictionary and c.get("hand", {}) is Dictionary and not c.hand.is_empty():
					win.append(c.hand)
					c.hand = {}
			kd["window"] = win
		d["_version"] = 3
	if int(d.get("_version", 1)) < 4:
		d["cash"] = 0
		d["perks"] = []
		d["_version"] = 4
	if int(d.get("_version", 1)) < 5:
		var kd5: Variant = d.get("kitchen", null)
		if kd5 is Dictionary and kd5.get("pans", []) is Array and (kd5.pans as Array).size() == 3:
			kd5.pans.append({})   # the new COLD pan sits at index 3, before the pass
			for c in kd5.get("crew", []):
				if c is Dictionary and int(c.get("at", 0)) == 3:
					c.at = 4   # was at the pass
			kd5["all_open"] = int(kd5.get("service", 1)) == 1   # only service 1 had saute closed
		d["_version"] = 5
	if int(d.get("_version", 1)) < 6:
		# Honor any previously paid hire, even if its one-service perk was already consumed.
		var owned: Array = d.get("perks", [])
		if int(d.get("temp_buys", 0)) > 0 and not owned.has("temp"):
			owned.append("temp")
		d["perks"] = owned
		d.erase("temp_buys")
		d["_version"] = 6
	if int(d.get("_version", 1)) < 7:
		# Existing owners paid for all stations; honor their purchase, no second charge.
		var old_perks: Array = d.get("perks", [])
		if old_perks.has("burners"):
			old_perks.erase("burners")
			for s in range(4):
				var id := "burners_%d" % s
				if not old_perks.has(id):
					old_perks.append(id)
		d["perks"] = old_perks
		d["cook_xp"] = {}
		d["_version"] = 7
	if int(d.get("_version", 1)) < 8:
		d["chef_pressure"] = 0
		d["_version"] = 8
	return d
