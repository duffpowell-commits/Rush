extends RefCounted
## Rush rules: one dinner service on a line, turn by turn. No nodes, no drawing, so tests and the
## autoplay bot drive the exact rules the player does. game.gd draws this and turns taps into calls.
##
## The line, left to right: GRILL, FRY, SAUTE, PASS. Each cook station holds one pan.
## A turn is one minute of service. Each cook gets AP actions a turn:
##   move one station = 1 AP, FIRE a dish at your station = 1, PLATE a finished dish = 1,
##   RUN a plate at the pass = 1 (that dish is served).
## End of turn: pans cook one step, finished pans left sitting burn, ticket clocks tick down.
## A ticket at 0 is walked (a comp). Too many comps and the night is over.
## Stress: a working cook gains 1 at end of turn while any ticket is red (2 min or less), and 2 for a burn on
## their station. At STRESS_CAP they walk out for the rest of the service. A cook who does nothing
## all turn rests and drops 2.

const STATIONS := ["GRILL", "FRY", "SAUTE", "PASS"]
const PASS_IX := 3

## Dish: station it cooks at, minutes on the heat.
const DISHES := {
	"BURGER": {"st": 0, "cook": 2},
	"STEAK": {"st": 0, "cook": 3},
	"FRIES": {"st": 1, "cook": 1},
	"WINGS": {"st": 1, "cook": 2},
	"PASTA": {"st": 2, "cook": 2},
	"SCAMPI": {"st": 2, "cook": 1},
}

var turns := 20          # service length in minutes (7:00 to 7:20 PM)
var ticket_time := 9     # minutes a ticket has before it's walked
var ap := 3              # actions per cook per turn
var stress_cap := 6
var burn_after := 1      # a finished pan burns at the end of the turn its wait passes this (2 turns to plate at 1)
var first_tickets := 6   # tickets in service 1
var more_tickets := 1    # extra tickets each later service (greedy bot, 200 seeds: s2 ~40% game over, s3 ~65%)

var service := 1
var turn := 0
var crew: Array = []        # {name, at, ap, stress, out, hand: {} or {tid, dish}, acted}
var pans: Array = []        # per cook station: {} or {tid, dish, left, sat}
var tickets: Array = []     # active: {id, table, items: [{dish, state}], time, big}
var incoming: Array = []    # not yet on the rail: {arrive, ticket}
var served := 0             # tickets out complete
var walked := 0             # tickets comped this service
var tips := 0
var events: Array = []       # short lines for the HUD ("BURN on GRILL")
var done := false
var total := 0           # tickets this service, for the grade

var _next_id := 1
var rng := RandomNumberGenerator.new()


## A fresh service. Later services bring more tickets, faster, with a big table in the push.
func start(n: int, seed_value: int = 0) -> void:
	service = n
	turn = 0
	served = 0
	walked = 0
	tips = 0
	done = false
	events.clear()
	rng.seed = seed_value if seed_value != 0 else 1000 + n
	crew = [_cook("DEV"), _cook("MO")]
	crew[0].at = 0
	crew[1].at = 2
	pans = [{}, {}, {}]
	tickets.clear()
	incoming.clear()
	var count := maxi(1, first_tickets + more_tickets * (n - 1))
	total = count
	var last_arrival := maxi(turns - ticket_time - 2, 4)
	for i in count:
		var arrive := int(round(float(i) * last_arrival / maxf(count - 1, 1)))
		var big := i == count / 2 + 1
		incoming.append({"arrive": arrive, "ticket": _make_ticket(big)})
	if n == 1:   # the first ticket of the night teaches the grill: DEV starts there
		incoming[0].ticket.items = [{"dish": "BURGER", "state": "wait"}]
	_arrivals()


func _cook(nm: String) -> Dictionary:
	return {"name": nm, "at": 0, "ap": ap, "stress": 0, "out": false, "hand": {}, "acted": false}


func _make_ticket(big: bool) -> Dictionary:
	var names: Array = DISHES.keys()
	var items: Array = []
	var k := 4 if big else rng.randi_range(1, 2)
	for i in k:
		items.append({"dish": names[rng.randi_range(0, names.size() - 1)], "state": "wait"})
	var t := {"id": _next_id, "table": rng.randi_range(1, 30), "items": items,
		"time": ticket_time + (3 if big else 0), "big": big}
	_next_id += 1
	return t


func _arrivals() -> void:
	for inc in incoming.duplicate():
		if inc.arrive <= turn:
			incoming.erase(inc)
			tickets.append(inc.ticket)
			if inc.ticket.big:
				_say("%d-TOP ON THE RAIL" % (inc.ticket.items.size() * 3))


## The next few tickets coming, soonest first: what the rail shows as "next" (like enemy intents).
func preview(n: int = 3) -> Array:
	var out: Array = []
	for inc in incoming:
		if out.size() >= n:
			break
		out.append({"in": inc.arrive - turn, "ticket": inc.ticket})
	return out


func ticket(id: int) -> Dictionary:
	for t in tickets:
		if t.id == id:
			return t
	return {}


# ---------------------------------------------------------------- actions (each returns true if it happened)

func can_act(c: int) -> bool:
	return not done and c >= 0 and c < crew.size() and not crew[c].out and crew[c].ap > 0


## Move cook c to station s. Costs 1 AP per station crossed.
func move(c: int, s: int) -> bool:
	if not can_act(c) or s < 0 or s >= STATIONS.size() or s == crew[c].at:
		return false
	var cost: int = absi(s - crew[c].at)
	if cost > crew[c].ap:
		return false
	crew[c].ap -= cost
	crew[c].at = s
	crew[c].acted = true
	return true


## Fire the most urgent waiting dish for this cook's station. tid picks a ticket instead.
func fire(c: int, tid: int = 0) -> bool:
	if not can_act(c):
		return false
	var s: int = crew[c].at
	if s == PASS_IX or not pans[s].is_empty():
		return false
	var pick := _waiting_for(s, tid)
	if pick.is_empty():
		return false
	pick.item.state = "cooking"
	pans[s] = {"tid": pick.t.id, "dish": pick.item.dish, "left": DISHES[pick.item.dish].cook, "sat": 0}
	crew[c].ap -= 1
	crew[c].acted = true
	return true


func _waiting_for(s: int, tid: int) -> Dictionary:
	var order := tickets.duplicate()
	order.sort_custom(func(a, b): return a.time < b.time)
	for t in order:
		if tid != 0 and t.id != tid:
			continue
		for it in t.items:
			if it.state == "wait" and DISHES[it.dish].st == s:
				return {"t": t, "item": it}
	return {}


## Pick up the finished dish from this cook's station.
func plate(c: int) -> bool:
	if not can_act(c) or not crew[c].hand.is_empty():
		return false
	var s: int = crew[c].at
	if s == PASS_IX or pans[s].is_empty() or pans[s].left > 0:
		return false
	var p: Dictionary = pans[s]
	var t := ticket(p.tid)
	pans[s] = {}
	if t.is_empty():   # its ticket was walked while it cooked: the plate is wasted
		crew[c].ap -= 1
		crew[c].acted = true
		return true
	for it in t.items:
		if it.state == "cooking" and it.dish == p.dish:
			it.state = "carried"
			break
	crew[c].hand = {"tid": p.tid, "dish": p.dish}
	crew[c].ap -= 1
	crew[c].acted = true
	return true


## Run the plate in hand at the pass. A ticket with every dish run is out: tips by time left.
func run(c: int) -> bool:
	if not can_act(c) or crew[c].at != PASS_IX or crew[c].hand.is_empty():
		return false
	var h: Dictionary = crew[c].hand
	crew[c].hand = {}
	crew[c].ap -= 1
	crew[c].acted = true
	var t := ticket(h.tid)
	if t.is_empty():
		return true
	for it in t.items:
		if it.state == "carried" and it.dish == h.dish:
			it.state = "served"
			break
	if t.items.all(func(it): return it.state == "served"):
		tickets.erase(t)
		served += 1
		tips += 2 + t.time + (4 if t.big else 0)
		_say("TABLE %d OUT" % t.table)
	return true


## The one sensible action for cook c where they stand, or "" (game.gd's big button).
func action_here(c: int) -> String:
	if not can_act(c):
		return ""
	var s: int = crew[c].at
	if s == PASS_IX:
		return "RUN" if not crew[c].hand.is_empty() else ""
	if not pans[s].is_empty() and pans[s].left <= 0 and crew[c].hand.is_empty():
		return "PLATE"
	if pans[s].is_empty() and not _waiting_for(s, 0).is_empty():
		return "FIRE"
	return ""


func act_here(c: int) -> bool:
	match action_here(c):
		"RUN":
			return run(c)
		"PLATE":
			return plate(c)
		"FIRE":
			return fire(c)
	return false


# ---------------------------------------------------------------- end of turn

func end_turn() -> void:
	if done:
		return
	events.clear()
	# Pans cook; finished pans sit, and burn if left too long.
	for s in pans.size():
		var p: Dictionary = pans[s]
		if p.is_empty():
			continue
		if p.left > 0:
			p.left -= 1
		else:
			p.sat += 1
			if p.sat > burn_after:
				pans[s] = {}
				var t := ticket(p.tid)
				for it in t.get("items", []):
					if it.state == "cooking" and it.dish == p.dish:
						it.state = "wait"   # refire
						break
				_say("BURN ON %s, REFIRE" % STATIONS[s])
				for cr in crew:
					if cr.at == s and not cr.out:
						cr.stress += 2
	# Clocks tick; a ticket at zero is walked.
	var red := 0
	for t in tickets.duplicate():
		t.time -= 1
		if t.time <= 0:
			tickets.erase(t)
			walked += 1
			_say("TABLE %d WALKED" % t.table)
			for s in pans.size():
				if not pans[s].is_empty() and pans[s].tid == t.id:
					pans[s] = {}
			for cr in crew:   # a plate for a walked table is binned, so the cook's hands are free
				if not cr.hand.is_empty() and cr.hand.tid == t.id:
					cr.hand = {}
		elif t.time <= 2:
			red += 1
	# Stress: red tickets wear everyone working; a cook who did nothing rests.
	for cr in crew:
		if cr.out:
			continue
		if cr.acted:
			cr.stress += 1 if red > 0 else 0
		else:
			cr.stress = maxi(0, cr.stress - 2)
		if cr.stress >= stress_cap:
			cr.out = true
			_drop_hand(cr)
			_say("%s WALKED OUT" % cr.name)
		cr.ap = ap
		cr.acted = false
	turn += 1
	_arrivals()
	if (tickets.is_empty() and incoming.is_empty()) or crew.all(func(cr): return cr.out) or turn >= turns + ticket_time + 3:
		done = true


## A cook leaves holding a plate: that dish goes back on the ticket to refire, like a burn.
func _drop_hand(cr: Dictionary) -> void:
	if cr.hand.is_empty():
		return
	var t := ticket(cr.hand.tid)
	for it in t.get("items", []):
		if it.state == "carried" and it.dish == cr.hand.dish:
			it.state = "wait"
			break
	cr.hand = {}


## The letter for a finished service: share of tickets out, minus a step per table walked.
func grade() -> String:
	var share := float(served) / maxf(total, 1)
	var g := 4 if share >= 0.95 else (3 if share >= 0.8 else (2 if share >= 0.6 else (1 if share >= 0.4 else 0)))
	g = maxi(0, g - walked)
	return ["F", "D", "C", "B", "A"][g]


## Station name for a dish ("GRILL"), so the screen can show where each dish cooks.
static func station_of(dish: String) -> String:
	return STATIONS[DISHES[dish].st]


# ---------------------------------------------------------------- save mid-service

## Everything needed to pick the service back up exactly where it was (JSON-safe).
func to_dict() -> Dictionary:
	return {"service": service, "turn": turn, "crew": crew.duplicate(true), "pans": pans.duplicate(true),
		"tickets": tickets.duplicate(true), "incoming": incoming.duplicate(true), "served": served,
		"walked": walked, "tips": tips, "done": done, "total": total, "next_id": _next_id,
		"rng": str(rng.state), "turns": turns, "ticket_time": ticket_time, "ap": ap,
		"stress_cap": stress_cap, "burn_after": burn_after}


## Load a to_dict() back. JSON turns every number into a float, so ints are cast back here.
func from_dict(d: Dictionary) -> bool:
	if not d.has("crew") or not d.has("tickets") or not d.has("pans") or not d.has("incoming"):
		return false
	service = int(d.service)
	turn = int(d.turn)
	served = int(d.served)
	walked = int(d.walked)
	tips = int(d.tips)
	done = bool(d.done)
	total = int(d.get("total", 0))
	_next_id = int(d.next_id)
	rng.state = int(str(d.rng))
	turns = int(d.turns)
	ticket_time = int(d.ticket_time)
	ap = int(d.ap)
	stress_cap = int(d.stress_cap)
	burn_after = int(d.burn_after)
	crew = []
	for c in d.crew:
		var h: Dictionary = c.hand
		crew.append({"name": str(c.name), "at": int(c.at), "ap": int(c.ap), "stress": int(c.stress),
			"out": bool(c.out), "acted": bool(c.acted),
			"hand": {} if h.is_empty() else {"tid": int(h.tid), "dish": str(h.dish)}})
	pans = []
	for p in d.pans:
		pans.append({} if p.is_empty() else {"tid": int(p.tid), "dish": str(p.dish), "left": int(p.left), "sat": int(p.sat)})
	tickets = []
	for t in d.tickets:
		tickets.append(_ticket_from(t))
	incoming = []
	for inc in d.incoming:
		incoming.append({"arrive": int(inc.arrive), "ticket": _ticket_from(inc.ticket)})
	events.clear()
	return crew.size() > 0 and pans.size() == PASS_IX


func _ticket_from(t: Dictionary) -> Dictionary:
	var items: Array = []
	for it in t.items:
		items.append({"dish": str(it.dish), "state": str(it.state)})
	return {"id": int(t.id), "table": int(t.table), "items": items, "time": int(t.time), "big": bool(t.big)}


func _say(s: String) -> void:
	events.append(s)


## "7:04 PM": the service clock.
func clock() -> String:
	return "7:%02d PM" % turn if turn < 60 else "8:%02d PM" % (turn - 60)


## A plain greedy line cook: run, plate, fire, else walk toward work. Proves a service is
## playable and drives autoplay. Returns the number of actions it took this turn.
func bot_turn() -> int:
	var acts := 0
	for c in crew.size():
		var guard := 0
		if crew[c].stress >= stress_cap - 2 and crew[c].hand.is_empty():
			continue   # rest this turn or walk out
		while can_act(c) and guard < 8:
			guard += 1
			if act_here(c):
				acts += 1
				continue
			var goal := _bot_goal(c)
			if goal < 0 or goal == crew[c].at:
				break
			var step: int = crew[c].at + signi(goal - crew[c].at)
			if move(c, step):
				acts += 1
			else:
				break
	return acts


func _bot_goal(c: int) -> int:
	if not crew[c].hand.is_empty():
		return PASS_IX
	# A finished pan nobody else is standing at.
	for s in pans.size():
		if not pans[s].is_empty() and pans[s].left <= 0 and not _other_at(c, s):
			return s
	# An empty station with work waiting, nearest first.
	var best := -1
	for s in pans.size():
		if pans[s].is_empty() and not _waiting_for(s, 0).is_empty() and not _other_at(c, s):
			if best < 0 or absi(s - crew[c].at) < absi(best - crew[c].at):
				best = s
	return best


func _other_at(c: int, s: int) -> bool:
	for i in crew.size():
		if i != c and not crew[i].out and crew[i].at == s:
			return true
	return false
