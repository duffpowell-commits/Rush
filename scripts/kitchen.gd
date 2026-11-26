extends RefCounted
## Rush rules: one dinner service on a line, turn by turn. No nodes, no drawing, so tests and the
## autoplay bot drive the exact rules the player does. game.gd draws this and turns taps into calls.
##
## The line, left to right: GRILL, FRY, SAUTE, PASS. Each cook station holds one pan.
## A turn is one minute of service. Each cook gets AP actions a turn:
##   move one station = 1 AP, FIRE a dish at your station = 1 (the player can pick the ticket),
##   RUSH a cooking pan = 1 (a minute off, once a turn, costs stress), PLATE a finished dish = 1
##   (it goes up on the pass window), RUN a plate from the window at the pass = 1 (served).
## Nov 25 playtest: picking the ticket, RUSH and the window were added so the turn is choices,
## not walking (a grill->pass->grill trip used to eat a whole turn).
## End of turn: pans cook one step, finished pans left sitting burn, ticket clocks tick down.
## A ticket at 0 is walked (a comp). Too many comps and the night is over.
## Stress: a working cook gains 1 at end of turn while any ticket is red (2 min or less), and 2 for a burn on
## their station. At STRESS_CAP they walk out for the rest of the service. A cook who does nothing
## all turn rests and drops 2.

## Twists by service: none in 1, a gentle one in 2 (MILD_EVENTS), none in 3 (cold opens), any from 4. (Nov 25, Duff's "all six" fixes, #2 variety): name, one line.
const EVENTS := {
	"tour": ["BUS TOUR", "Three tables land at once mid-service."],
	"fritz": ["GRILL ON THE FRITZ", "Grill dishes take a minute longer. Their tables wait one more."],
	"vip": ["VIP TABLE", "Gold ticket: triple tips. Walk it and it counts as two."],
	"critic": ["FOOD CRITIC", "Serve the critic: grade up. Walk them: grade down."],
	# 8.5 plan #2 (blind review: only two twists in four services, and stress never moved).
	"heat": ["HEAT WAVE", "The line is an oven: working cooks take +1 stress every fourth turn."],
	"party": ["PARTY OF 12", "A twelve-top books in mid-service and takes a small table's place."],
	# Duff, Nov 26: "you need ingredients from different stations to fire new dishes ... blue cheese
	# from salad bar for saute", then "you can do it from each station. Steak for a salad from grill".
	# From service 4 only (every station is open). Balance: only every PREP_EVERY-th dish needs it.
	"prep": ["CROSS PREP", "Some dishes need an ingredient from another station: PREP it there first."],
}
const EVENT_IDS := ["tour", "fritz", "vip", "critic", "heat", "party", "prep"]
## 8.5 plan #4 (IGN build 89: service 2 had no choice in it, service 3 stacked everything): service 2
## rolls a gentle twist (a table worth chasing), service 3 opens cold with none, the full set from 4.
const MILD_EVENTS := ["vip", "critic"]

## Cook perks, earned (Duff, Nov 26: "make the perks earn able like a level up system"; IGN build 89:
## "the cooks are functionally identical"). After each service the cook who did the most levels up
## and the player picks one of three (game.gd). A cook's perks ride on crew[c].perks. No downsides yet.
##   fast_N: station N's dishes cook a minute faster when this cook fires them (never under 1).
##   run / plate / walk: their first RUN / PLATE / step each turn is free.
const PERKS := {
	"fast_0": ["GRILL HAND", "Grill dishes cook 1 min faster"],
	"fast_1": ["FRY HAND", "Fry dishes cook 1 min faster"],
	"fast_2": ["SAUTE HAND", "Saute dishes cook 1 min faster"],
	"fast_3": ["COLD HAND", "Cold dishes take 1 min less"],
	"run": ["RUNNER", "First RUN each turn is free"],
	"plate": ["QUICK PLATE", "First PLATE each turn is free"],
	"walk": ["LIGHT FEET", "First step each turn is free"],
}
const PERK_IDS := ["fast_0", "fast_1", "fast_2", "fast_3", "run", "plate", "walk"]

const STATIONS := ["GRILL", "FRY", "SAUTE", "COLD", "PASS"]
const PASS_IX := 4
## The line grows as the night goes on (Duff, Nov 25: "add stations as they progress", by service):
## service 1 is grill + fry, saute opens in service 2, the cold station (salad, cake) in service 3.
## A closed station is walked past for free and takes no tickets.
const OPENS := [1, 1, 2, 3]
const TEMPS := ["JO", "KAI"]
## CROSS PREP: what a dish at each station needs, and where it's prepped ([from station, name]).
## Grill burger takes blue cheese (cold), fry wings take garlic butter (saute), saute takes blue
## cheese (cold), a cold salad takes steak strips (grill).
const PREP_FROM := {0: [3, "BLUE CHEESE"], 1: [2, "GARLIC BUTTER"], 2: [3, "BLUE CHEESE"], 3: [0, "STEAK STRIPS"]}

## Dish: station it cooks at, minutes on the heat.
const DISHES := {
	"BURGER": {"st": 0, "cook": 2},
	"STEAK": {"st": 0, "cook": 3},
	"FRIES": {"st": 1, "cook": 1},
	"WINGS": {"st": 1, "cook": 2},
	"PASTA": {"st": 2, "cook": 2},
	"SCAMPI": {"st": 2, "cook": 1},
	"SALAD": {"st": 3, "cook": 1},
	"CAKE": {"st": 3, "cook": 2},
}

var turns := 20          # service length in minutes (7:00 to 7:20 PM)
var ticket_time := 9     # minutes a ticket has before it's walked
var ap := 3              # actions per cook per turn
var stress_cap := 6
var burn_after := 1      # a finished pan burns at the end of the turn its wait passes this (2 turns to plate at 1)
var rush_stress := 1     # stress a RUSH costs the cook
var tray := 1            # plates one RUN carries (shop trays: 2, then 4)
var batch := 1           # dishes one FIRE cooks: 2 with the shop's DOUBLE BURNERS (same dish, any table)
var prep_every := 3      # CROSS PREP: every Nth dish needs an ingredient prepped at another station (TUNE)
var first_tickets := 7   # tickets in service 1 (8.5 plan #3 tried 8: the bot lost s1 26% vs 8%, so it stays 7) (Nov 25 stations: bot s1 ~8%, s2 ~32%, s3 ~48%, s4 ~71% game over, twists on)
var more_tickets := 1    # extra tickets each later service (greedy bot with the pass window, 200 seeds: s2 ~41% game over, s3 ~69%; was 6+1 before the window)

var service := 1
var turn := 0
var crew: Array = []        # {name, at, ap, stress, out, hand: {} or {tid, dish}, acted}
var pans: Array = []        # per cook station: {} or {tid, dish, left, sat, rushed}
var window: Array = []      # plated dishes up on the pass: {tid, dish}
var tickets: Array = []     # active: {id, table, items: [{dish, state}], time, big}
var incoming: Array = []    # not yet on the rail: {arrive, ticket}
var served := 0             # tickets out complete
var walked := 0             # tickets comped this service
var tips := 0
var all_open := false      # true: every station open from service 1 (old tests, sweeps)
var event := ""             # this service's twist (EVENTS), "" in service 1
var gone: Array = []         # house cooks who walked out earlier tonight: they sit the rest of the night out
var cook_perks := {}         # name -> perk ids, set by game.gd before start (earned over the night)
var breaks := 1             # second winds left this service: a cook who'd quit takes five instead (8.5 plan #3)
var hires := 0              # temp cooks for this service (shop TEMP COOK): a third pair of hands
var with_events := true     # false: plain services (balance sweeps)
var critic := ""            # "", "served" or "walked"
var events: Array = []       # short lines for the HUD ("BURN on GRILL")
var done := false
var total := 0           # tickets this service, for the grade
var burns := 0           # pans burned this service (grade)
var speed := 0.0         # sum over served tickets of the share of their clock left (grade)

var _next_id := 1
var rng := RandomNumberGenerator.new()


## A fresh service. Later services bring more tickets, faster, with a big table in the push.
func start(n: int, seed_value: int = 0) -> void:
	service = n
	turn = 0
	served = 0
	walked = 0
	tips = 0
	burns = 0
	speed = 0.0
	done = false
	events.clear()
	rng.seed = seed_value if seed_value != 0 else 1000 + n
	crew = []
	pans = [{}, {}, {}, {}]
	for nm in ["DEV", "MO"]:   # a cook who walked out earlier tonight stays gone (Duff, Nov 26)
		if gone.has(nm):
			continue
		var hc := _cook(nm)
		hc.at = 0 if nm == "DEV" else (2 if is_open(2) else 1)
		crew.append(hc)
	if crew.is_empty() and hires <= 0:   # never start a service with nobody on the line
		var back := _cook("DEV")
		back.at = 0
		crew.append(back)
	for h in hires:   # a temp starts at the pass, where plates pile up
		var tc := _cook(TEMPS[h % TEMPS.size()])
		tc.at = PASS_IX
		crew.append(tc)
	window.clear()
	tickets.clear()
	incoming.clear()
	# From service 4 (the full line is open) the rail grows one ticket
	# less (8.5 pass: service 4 was a wall for two cooks).
	var count := count_for(first_tickets, more_tickets, n)
	total = count
	var last_arrival := maxi(turns - ticket_time - 2, 4)
	for i in count:
		var arrive := int(round(float(i) * last_arrival / maxf(count - 1, 1)))
		var big := i == count / 2 + 1
		incoming.append({"arrive": arrive, "ticket": _make_ticket(big)})
	# No dead opening turns (build-76 review: "fire one dish, END TURN, END TURN"): the second ticket
	# lands at 7:00 from service 2, and a minute in on service 1 while the first one teaches.
	if count > 1:
		incoming[1].arrive = 0 if n >= 2 else 1
	if n == 1:   # the first ticket of the night teaches the grill: DEV starts there
		incoming[0].ticket.items = [{"dish": "BURGER", "state": "wait"}]
	event = ""
	critic = ""
	if with_events and (n == 2 or n >= 4):
		var pool: Array = MILD_EVENTS if n == 2 else EVENT_IDS
		event = pool[rng.randi_range(0, pool.size() - 1)]
		_set_up_event()
	_arrivals()


## Tickets service n deals: first, then +more a service, and from service 4 (the full line) one fewer.
## game.gd's tickets_for() uses the same sum (8.5 plan #3 put it in one place).
static func count_for(first: int, more: int, n: int) -> int:
	# Difficulty review (Nov 26, Duff: "ramps up at a bearable rate"): past service 5 the rail grows
	# every other service, not every one (the bot lost 91% of service 6).
	var steps := mini(n, 5) - 1 + maxi(n - 5, 0) / 2
	return maxi(1, first + more * steps - (1 if n >= 4 else 0))


func _set_up_event() -> void:
	var count := incoming.size()
	match event:
		"tour":   # three tickets from the middle of the service all arrive on the same minute
			var at := maxi(count / 2 - 1, 0)
			for i in range(at, mini(at + 3, count)):
				incoming[i].arrive = incoming[at].arrive
		"fritz":   # the floor knows: tickets with a grill dish get a minute's grace
			for inc in incoming:
				if inc.ticket.items.any(func(it): return DISHES[it.dish].st == 0):
					inc.ticket.time += 1
					inc.ticket.t0 = inc.ticket.time
		"vip":
			_mark(1 if count > 1 else 0, "vip")
		"critic":
			_mark(count / 3, "critic")
		"prep":   # every prep_every-th dish needs an ingredient from another station; its table gets a minute's grace
			var n := 0
			for inc in incoming:
				var marked := false
				for it in inc.ticket.items:
					n += 1
					if n % maxi(prep_every, 1) == 1 or prep_every <= 1:
						it["needs"] = int(PREP_FROM[DISHES[it.dish].st][0])
						marked = true
				if marked:
					inc.ticket.time += 1
					inc.ticket.t0 = inc.ticket.time
		"party":   # one more big table, landing mid-service (never at the opening, even on a short night)
			var mid := count / 2
			var at := maxi(incoming[mid].arrive if count > 0 else 0, turns / 3)
			var ix := incoming.size()
			for i in incoming.size():   # keep the list in arrival order (the NEXT bar reads it in order)
				if incoming[i].arrive > at:
					ix = i
					break
			var party := _make_ticket(true)
			party.time += 3   # a booked table: the floor seats them slow (difficulty review: it was 40 points over a plain service)
			party.t0 = party.time
			incoming.insert(ix, {"arrive": at, "ticket": party})
			# The twelve-top takes the room: the next small table after it doesn't come (difficulty
			# review, Nov 26: as an extra table it lost the bot 74% of service 4, vs 41% plain).
			for j in range(ix + 1, incoming.size()):
				if not incoming[j].ticket.big:
					incoming.remove_at(j)
					break
			total = incoming.size() + tickets.size()


func _mark(i: int, key: String) -> void:
	if incoming[i].ticket.big and i + 1 < incoming.size():
		i += 1
	incoming[i].ticket[key] = true


## Minutes a dish cooks for, with tonight's twist.
func cook_time(dish: String) -> int:
	return DISHES[dish].cook + (1 if event == "fritz" and DISHES[dish].st == 0 else 0)


func is_open(st: int) -> bool:
	return st == PASS_IX or all_open or (st >= 0 and st < OPENS.size() and service >= OPENS[st])


## Walking cost between two stations: one action per open stop, closed ones are passed for free.
func walk_cost(from: int, to: int) -> int:
	var cost := 0
	for st in range(mini(from, to) + 1, maxi(from, to) + 1):
		if is_open(st):
			cost += 1
	return cost


func _cook(nm: String) -> Dictionary:
	return {"name": nm, "at": 0, "ap": ap, "stress": 0, "out": false, "hand": {}, "acted": false, "brk": false,
		"perks": (cook_perks.get(nm, []) as Array).duplicate(), "used": [], "acts": 0}


func has_perk(c: int, id: String) -> bool:
	return c >= 0 and c < crew.size() and (crew[c].get("perks", []) as Array).has(id)


## Cook c's next RUN / PLATE / step costs nothing: they have the perk and haven't used it this turn.
func is_free(c: int, what: String) -> bool:
	var id: String = {"RUN": "run", "PLATE": "plate", "MOVE": "walk"}.get(what, "-")
	return has_perk(c, id) and not (crew[c].get("used", []) as Array).has(id)


func _pay(c: int, what: String) -> void:
	if is_free(c, what):
		crew[c].used.append({"RUN": "run", "PLATE": "plate"}[what])
	else:
		crew[c].ap -= 1
	_did(c)


func _did(c: int) -> void:
	crew[c].acted = true
	crew[c].acts = int(crew[c].get("acts", 0)) + 1   # who did the most: they level up after the service


## What walking cook c to station s costs, with LIGHT FEET's free first step.
func move_cost(c: int, s: int) -> int:
	var cost := walk_cost(crew[c].at, s)
	return maxi(0, cost - 1) if cost > 0 and is_free(c, "MOVE") else cost


## Minutes this cook's dish takes: the twist, then a station hand perk.
func cook_time_by(c: int, dish: String) -> int:
	var t := cook_time(dish)
	if has_perk(c, "fast_%d" % DISHES[dish].st):
		t = maxi(1, t - 1)
	return t


func _make_ticket(big: bool) -> Dictionary:
	var names: Array = DISHES.keys().filter(func(d): return is_open(DISHES[d].st))
	var items: Array = []
	var k := 4 if big else rng.randi_range(1, 2)
	for i in k:
		items.append({"dish": names[rng.randi_range(0, names.size() - 1)], "state": "wait"})
	# A table number nobody on the rail or still to come has (IGN review: two tickets both read T22).
	# One draw either way, so a seed still deals the same service.
	var used: Array = tickets.map(func(o): return o.table) + incoming.map(func(o): return o.ticket.table)
	var free: Array = range(1, 31).filter(func(n): return not used.has(n))
	if free.is_empty():
		free = range(1, 31)
	var t := {"id": _next_id, "table": free[rng.randi_range(0, free.size() - 1)], "items": items,
		"time": ticket_time + (3 if big else 0), "big": big}
	t.t0 = t.time   # the clock it started with: speed for the grade
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
	if not can_act(c) or s < 0 or s >= STATIONS.size() or s == crew[c].at or not is_open(s):
		return false
	var cost: int = move_cost(c, s)
	if cost > crew[c].ap or (cost == 0 and crew[c].ap <= 0):
		return false
	if cost < walk_cost(crew[c].at, s):
		crew[c].used.append("walk")
	crew[c].ap -= cost
	crew[c].at = s
	_did(c)
	return true


## Fire a waiting dish at this cook's station: the picked ticket (tid) if it has one here, else the
## most urgent ticket.
func fire(c: int, tid: int = 0, ix: int = -1) -> bool:
	if not can_act(c):
		return false
	var s: int = crew[c].at
	if s == PASS_IX or not pans[s].is_empty():
		return false
	var pick := fire_pick(c, tid, ix)
	if pick.is_empty():
		return false
	pick.item.state = "cooking"
	pans[s] = {"tid": pick.t.id, "dish": pick.item.dish, "left": cook_time_by(c, pick.item.dish), "sat": 0, "rushed": false,
		"by": c}   # who fired it: tapping the station picks that cook (Duff, Nov 25)
	if batch > 1:   # DOUBLE BURNERS: the same dish for the next most urgent table rides in this pan
		var more: Array = []
		while more.size() < batch - 1:
			var also := _same_dish(s, pick.item.dish)
			if also.is_empty():
				break
			also.item.state = "cooking"
			more.append(also.t.id)
		if not more.is_empty():
			pans[s]["more"] = more
	crew[c].ap -= 1
	_did(c)
	return true


## What FIRE would cook for cook c ({t, item}, or {} for nothing), so the screen can say which table.
## ix (Duff, Nov 25 "tap a dish"): that dish of ticket tid, when it's waiting and cooks here.
## Otherwise ticket tid's first dish for this station, otherwise the most urgent one.
func fire_pick(c: int, tid: int = 0, ix: int = -1) -> Dictionary:
	if c < 0 or c >= crew.size():
		return {}
	var s: int = crew[c].at
	if s == PASS_IX:
		return {}
	if tid != 0 and ix >= 0:
		var t := ticket(tid)
		if not t.is_empty() and ix < t.items.size():
			var it: Dictionary = t.items[ix]
			if it.state == "wait" and DISHES[it.dish].st == s and not it.has("needs"):
				return {"t": t, "item": it}
	var pick := _waiting_for(s, tid)
	if pick.is_empty() and tid != 0:
		pick = _waiting_for(s, 0)
	return pick


## A waiting copy of this dish at station s on the most urgent ticket (DOUBLE BURNERS).
func _same_dish(s: int, dish: String) -> Dictionary:
	var order := tickets.duplicate()
	order.sort_custom(func(a, b): return a.time < b.time)
	for t in order:
		for it in t.items:
			if it.state == "wait" and it.dish == dish and DISHES[it.dish].st == s and not it.has("needs"):
				return {"t": t, "item": it}
	return {}


## CROSS PREP: the most urgent waiting dish whose ingredient is prepped at station s ({t, item} or {}).
func prep_pick(s: int, tid: int = 0) -> Dictionary:
	var order := tickets.duplicate()
	order.sort_custom(func(a, b): return a.time < b.time)
	for t in order:
		if tid != 0 and t.id != tid:
			continue
		for it in t.items:
			if it.state == "wait" and int(it.get("needs", -1)) == s:
				return {"t": t, "item": it}
	return {} if tid == 0 else prep_pick(s, 0)


## What a dish needs prepped ("BLUE CHEESE"), "" when nothing.
static func prep_name(item: Dictionary) -> String:
	return str(PREP_FROM[DISHES[item.dish].st][1]) if item.has("needs") else ""


## PREP: pull the ingredient here for a dish at another station (1 move, no pan). Then it can fire.
func prep(c: int, tid: int = 0) -> bool:
	if not can_act(c) or crew[c].at == PASS_IX:
		return false
	var pick := prep_pick(crew[c].at, tid)
	if pick.is_empty():
		return false
	pick.item.erase("needs")
	pick.item["prepped"] = true
	crew[c].ap -= 1
	_did(c)
	return true


func _waiting_for(s: int, tid: int) -> Dictionary:
	var order := tickets.duplicate()
	order.sort_custom(func(a, b): return a.time < b.time)
	for t in order:
		if tid != 0 and t.id != tid:
			continue
		for it in t.items:
			if it.state == "wait" and DISHES[it.dish].st == s and not it.has("needs"):
				return {"t": t, "item": it}
	return {}


## Plate the finished dish at this cook's station: it goes up on the pass window.
func plate(c: int) -> bool:
	if not can_act(c):
		return false
	var s: int = crew[c].at
	if s == PASS_IX or pans[s].is_empty() or pans[s].left > 0:
		return false
	var p: Dictionary = pans[s]
	pans[s] = {}
	for tid in [p.tid] + p.get("more", []):   # DOUBLE BURNERS: every plate in the pan goes up
		var t := ticket(tid)
		if t.is_empty():   # its ticket was walked while it cooked: the plate is wasted
			continue
		for it in t.items:
			if it.state == "cooking" and it.dish == p.dish:
				it.state = "carried"
				break
		window.append({"tid": tid, "dish": p.dish})
	_pay(c, "PLATE")
	return true


## A minute off a cooking pan, once per pan per turn. The cook pays in stress.
func rush(c: int) -> bool:
	if not can_act(c) or crew[c].at == PASS_IX:
		return false
	var p: Dictionary = pans[crew[c].at]
	if p.is_empty() or p.left <= 0 or p.get("rushed", false):
		return false
	p.left -= 1
	p.rushed = true
	crew[c].stress += rush_stress
	crew[c].ap -= 1
	_did(c)
	return true


## Run plates at the pass for one action: the one in hand (saves from before the window), then
## window plates up to `tray` in all. The most urgent table goes first and its other plates ride
## along before the next table's. A ticket with every dish run is out: tips by time left.
func run(c: int) -> bool:
	if not can_act(c) or crew[c].at != PASS_IX:
		return false
	var plates: Array = []
	if not crew[c].hand.is_empty():
		plates.append(crew[c].hand)
		crew[c].hand = {}
	while plates.size() < maxi(tray, 1) and not window.is_empty():
		var best := 0
		var lead: int = plates[0].tid if not plates.is_empty() else -1
		for i in window.size():
			var w = window[i]
			var b = window[best]
			if (w.tid == lead) != (b.tid == lead):
				if w.tid == lead:
					best = i
			elif ticket(w.tid).get("time", 99) < ticket(b.tid).get("time", 99):
				best = i
		plates.append(window[best])
		window.remove_at(best)
	if plates.is_empty():
		return false
	_pay(c, "RUN")
	for h in plates:
		_serve(h)
	return true


func _serve(h: Dictionary) -> void:
	var t := ticket(h.tid)
	if t.is_empty():
		return
	for it in t.items:
		if it.state == "carried" and it.dish == h.dish:
			it.state = "served"
			break
	if t.items.all(func(it): return it.state == "served"):
		tickets.erase(t)
		served += 1
		speed += clampf(float(t.time) / maxf(float(t.get("t0", ticket_time)), 1.0), 0.0, 1.0)
		tips += (2 + t.time + (4 if t.big else 0)) * (3 if t.get("vip", false) else 1)
		if t.get("critic", false):
			critic = "served"
		_say("TABLE %d OUT" % t.table)


## The one sensible action for cook c where they stand, or "" (game.gd's big button).
## RUSH only when allow_rush: the bot leaves it alone, so the balance curve measures the base game.
func action_here(c: int, allow_rush: bool = true) -> String:
	if not can_act(c):
		return ""
	var s: int = crew[c].at
	if s == PASS_IX:
		return "RUN" if not crew[c].hand.is_empty() or not window.is_empty() else ""
	var p: Dictionary = pans[s]
	if not p.is_empty() and p.left <= 0:
		return "PLATE"
	if p.is_empty() and not _waiting_for(s, 0).is_empty():
		var cp := prep_pick(s)
		if cp.is_empty() or _waiting_for(s, 0).t.time <= cp.t.time:
			return "FIRE"
	if not prep_pick(s).is_empty():
		return "PREP"
	if p.is_empty() and not _waiting_for(s, 0).is_empty():
		return "FIRE"
	if allow_rush and not p.is_empty() and p.left > 0 and not p.get("rushed", false):
		return "RUSH"
	return ""


func act_here(c: int, tid: int = 0, allow_rush: bool = true, ix: int = -1) -> bool:
	match action_here(c, allow_rush):
		"RUN":
			return run(c)
		"PLATE":
			return plate(c)
		"FIRE":
			return fire(c, tid, ix)
		"RUSH":
			return rush(c)
		"PREP":
			return prep(c, tid)
	return false


# ---------------------------------------------------------------- end of turn

## HEAT WAVE: this turn's end adds a point to every cook who worked (turns 1, 5, 9...: every fourth).
func heat_turn() -> bool:
	return event == "heat" and turn % 4 == 1   # difficulty review (Nov 26): every fourth turn; every other was a 30-point spike


func end_turn() -> void:
	if done:
		return
	events.clear()
	# Pans cook; finished pans sit, and burn if left too long.
	for s in pans.size():
		var p: Dictionary = pans[s]
		if p.is_empty():
			continue
		p.rushed = false
		if p.left > 0:
			p.left -= 1
		else:
			p.sat += 1
			if p.sat > burn_after:
				pans[s] = {}
				for tid in [p.tid] + p.get("more", []):
					var t := ticket(tid)
					for it in t.get("items", []):
						if it.state == "cooking" and it.dish == p.dish:
							it.state = "wait"   # refire
							break
				burns += 1
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
			walked += 2 if t.get("vip", false) else 1
			if t.get("critic", false):
				critic = "walked"
			_say("TABLE %d WALKED" % t.table)
			for s in pans.size():
				if pans[s].is_empty():
					continue
				var more: Array = pans[s].get("more", [])
				more.erase(t.id)   # DOUBLE BURNERS: a walked rider just drops out of the pan
				if pans[s].tid == t.id:
					if more.is_empty():
						pans[s] = {}
					else:   # the other table's dish keeps cooking in this pan
						pans[s].tid = more.pop_front()
				if not pans[s].is_empty():
					if more.is_empty():
						pans[s].erase("more")
					else:
						pans[s]["more"] = more
			window = window.filter(func(w): return w.tid != t.id)   # its plates on the pass are binned
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
			cr.stress += (1 if red > 0 else 0) + (1 if heat_turn() else 0)
		else:
			cr.stress = maxi(0, cr.stress - 2)
		cr.brk = false   # a break lasts the one turn it was taken for
		if cr.stress >= stress_cap and breaks > 0:
			# Second wind (8.5 plan #3: one walkout snowballed into GAME OVER): the first cook who'd
			# quit this service takes five instead. Down to cap-3, sits out next turn (resting).
			breaks -= 1
			cr.stress = maxi(0, stress_cap - 3)
			cr.brk = true
			_say("%s TAKES FIVE" % cr.name)
		elif cr.stress >= stress_cap:
			cr.out = true
			_drop_hand(cr)
			_say("%s WALKED OUT" % cr.name)
		cr.ap = 0 if cr.brk else ap
		cr.used = []
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


## The service's score out of 100 and where it came from (Nov 25: the old letter only landed A/C/F).
## Tickets out 60, speed 25 (how much clock was left when each table went out; full at 75%, none
## under 30%: a clean service served with half the clock left is an A), clean pans 15,
## minus 10 per table walked (on top of the ticket it lost), critic +-8.
## 8.5 plan #4 (IGN: A came too easy): speed is full at 75% of the clock left (was 70%), A needs 90 (was 87).
func score_parts() -> Dictionary:
	var share := float(served) / maxf(total, 1)
	var avg := speed / maxf(served, 1)
	var parts := {
		"out": int(round(60.0 * share)),
		"speed": int(round(25.0 * clampf((avg - 0.3) / 0.45, 0.0, 1.0) * share)),
		"pans": maxi(0, 15 - 5 * burns),
		"walks": -10 * walked,
		"critic": {"served": 8, "walked": -8}.get(critic, 0),
	}
	parts.total = clampi(parts.out + parts.speed + parts.pans + parts.walks + parts.critic, 0, 100)
	return parts


const GRADES := [[95, "A+"], [90, "A"], [77, "B"], [65, "C"], [45, "D"], [0, "F"]]
## Tip bonus every finished service pays by grade, on top of tips (Duff, Nov 26: "a higher rate for all grades
## so that if you cant make one session it doesnt automatically ruin the next").
const GRADE_BONUS := {"A+": 30, "A": 25, "B": 20, "C": 15, "D": 10, "F": 10}


## The letter for a finished service, from score_parts().total.
func grade() -> String:
	var pts: int = score_parts().total
	for g in GRADES:
		if pts >= g[0]:
			return g[1]
	return "F"


## Station name for a dish ("GRILL"), so the screen can show where each dish cooks.
static func station_of(dish: String) -> String:
	return STATIONS[DISHES[dish].st]


# ---------------------------------------------------------------- save mid-service

## Everything needed to pick the service back up exactly where it was (JSON-safe). The service's own
## tuning rides along on purpose: a TUNE change applies from the next service, not mid-service.
func to_dict() -> Dictionary:
	return {"service": service, "turn": turn, "crew": crew.duplicate(true), "pans": pans.duplicate(true),
		"tickets": tickets.duplicate(true), "incoming": incoming.duplicate(true), "served": served,
		"walked": walked, "tips": tips, "done": done, "total": total, "next_id": _next_id,
		"rng": str(rng.state), "turns": turns, "ticket_time": ticket_time, "ap": ap,
		"stress_cap": stress_cap, "burn_after": burn_after,
		"window": window.duplicate(true), "rush_stress": rush_stress, "event": event, "critic": critic, "all_open": all_open,
		"burns": burns, "speed": speed, "tray": tray, "breaks": breaks, "batch": batch}


## Load a to_dict() back. JSON turns every number into a float, so ints are cast back here.
func from_dict(d: Dictionary) -> bool:
	for key in ["crew", "tickets", "pans", "incoming", "service", "turn", "served", "walked", "tips",
			"done", "next_id", "rng", "turns", "ticket_time", "ap", "stress_cap", "burn_after", "window"]:
		if not d.has(key):
			return false   # a mangled save: keep the fresh service instead
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
	rush_stress = int(d.get("rush_stress", 1))
	event = str(d.get("event", ""))
	all_open = bool(d.get("all_open", false))
	burns = int(d.get("burns", 0))
	speed = float(d.get("speed", 0.0))
	tray = clampi(int(d.get("tray", 1)), 1, 4)
	critic = str(d.get("critic", ""))
	breaks = int(d.get("breaks", 1))
	batch = clampi(int(d.get("batch", 1)), 1, 2)
	window = []
	for w in d.window:
		window.append({"tid": int(w.tid), "dish": str(w.dish)})
	crew = []
	for c in d.crew:
		var h: Dictionary = c.hand
		crew.append({"name": str(c.name), "at": int(c.at), "ap": int(c.ap), "stress": int(c.stress),
			"out": bool(c.out), "acted": bool(c.acted), "brk": bool(c.get("brk", false)),
			"perks": (c.get("perks", []) as Array).map(func(x): return str(x)), "used": (c.get("used", []) as Array).map(func(x): return str(x)),
			"acts": int(c.get("acts", 0)),
			"hand": {} if h.is_empty() else {"tid": int(h.tid), "dish": str(h.dish)}})
	pans = []
	for p in d.pans:
		pans.append({} if p.is_empty() else {"tid": int(p.tid), "dish": str(p.dish), "left": int(p.left), "sat": int(p.sat),
			"rushed": bool(p.get("rushed", false)), "by": int(p.get("by", -1))})
		if not pans[-1].is_empty() and p.has("more"):
			pans[-1]["more"] = (p.more as Array).map(func(x): return int(x))
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
		var item := {"dish": str(it.dish), "state": str(it.state)}
		if it.has("needs"):
			item["needs"] = int(it.needs)
		if it.get("prepped", false):
			item["prepped"] = true
		items.append(item)
	var out := {"id": int(t.id), "table": int(t.table), "items": items, "time": int(t.time), "big": bool(t.big)}
	for key in ["vip", "critic"]:
		if t.get(key, false):
			out[key] = true
	return out


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
			if act_here(c, 0, false):
				acts += 1
				continue
			var goal := _bot_goal(c)
			if goal < 0 or goal == crew[c].at:
				break
			var step: int = crew[c].at + signi(goal - crew[c].at)
			while not is_open(step):   # walk past closed stations to the next open stop
				step += signi(goal - crew[c].at)
			if move(c, step):
				acts += 1
			else:
				break
	return acts


func _bot_goal(c: int) -> int:
	if not crew[c].hand.is_empty():
		return PASS_IX
	# Plates waiting on the window and nobody at the pass.
	if not window.is_empty() and not _other_at(c, PASS_IX):
		return PASS_IX
	# A finished pan nobody else is standing at.
	for s in pans.size():
		if not pans[s].is_empty() and pans[s].left <= 0 and not _other_at(c, s):
			return s
	# An empty station with work waiting, nearest first.
	var best := -1
	for s in pans.size():
		var work: bool = pans[s].is_empty() and not _waiting_for(s, 0).is_empty()
		if not prep_pick(s).is_empty():
			work = true
		if work and not _other_at(c, s):
			if best < 0 or walk_cost(crew[c].at, s) < walk_cost(crew[c].at, best):
				best = s
	return best


func _other_at(c: int, s: int) -> bool:
	for i in crew.size():
		if i != c and not crew[i].out and crew[i].at == s:
			return true
	return false
