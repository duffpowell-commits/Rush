extends RefCounted
## Kitchen upgrades bought with tips between services. They carry through the night (the run
## save), so a good service makes the next one easier. Pure data + rules, no nodes: tests and the
## grade sheet's SHOP both use this.
## Nov 25 (Duff: "all six" score fixes, #1 "something that carries between nights").

## id: name on the button, price, what it does (<= 26 chars so the button fits at text size 1.4).
const ALL := {
	"lamps": {"name": "HEAT LAMPS", "cost": 30, "says": "+1 MIN ON EVERY TICKET"},
	"meal": {"name": "FAMILY MEAL", "cost": 25, "says": "+1 STRESS BEFORE QUITTING"},
	"iron": {"name": "CAST IRON", "cost": 35, "says": "RUSH COSTS NO STRESS"},
	"comps": {"name": "COMP CARDS", "cost": 50, "says": "+1 TABLE CAN WALK"},
}
const ORDER := ["meal", "lamps", "iron", "comps"]


static func can_buy(id: String, cash: int, owned: Array) -> bool:
	return ALL.has(id) and not owned.has(id) and cash >= int(ALL[id].cost)


## Returns the cash left, or -1 if it can't be bought (owned array gains the id).
static func buy(id: String, cash: int, owned: Array) -> int:
	if not can_buy(id, cash, owned):
		return -1
	owned.append(id)
	return cash - int(ALL[id].cost)


## The service's numbers with the owned upgrades on top.
## base: {ticket_time, stress_cap, rush_stress, lives}
static func apply(base: Dictionary, owned: Array) -> Dictionary:
	var out := base.duplicate()
	if owned.has("lamps"):
		out.ticket_time += 1
	if owned.has("meal"):
		out.stress_cap += 1
	if owned.has("iron"):
		out.rush_stress = 0
	if owned.has("comps"):
		out.lives += 1
	return out
