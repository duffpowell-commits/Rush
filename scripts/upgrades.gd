extends RefCounted
## Kitchen upgrades bought with tips between services. They carry through the night (the run
## save), so a good service makes the next one easier. Pure data + rules, no nodes: tests and the
## grade sheet's SHOP both use this.
## Nov 25 (Duff: "all six" score fixes, #1 "something that carries between nights").

## id: name on the button, price, what it does (<= 26 chars so the button fits at text size 1.4).
const ALL := {
	"lamps": {"name": "HEAT LAMPS", "cost": 30, "says": "+1 MIN ON EVERY TICKET"},
	"meal": {"name": "FAMILY MEAL", "cost": 25, "says": "+1 STRESS BEFORE QUITTING"},
	"iron": {"name": "CAST IRON", "cost": 35, "says": "1 STRESS-FREE RUSH/TURN"},
	"comps": {"name": "SECOND CHANCE", "cost": 50, "says": "+1 WALK BEFORE GAME OVER"},
	# Trays (Duff, Nov 25: "start out with the one dish ran rule and then upgrade it in the shop for a
	# max of 4"). A RUN carries one plate; the server tray makes it 2, the entree tray (after the
	# server tray) makes it 4.
	"tray": {"name": "SERVER TRAY", "cost": 30, "says": "RUN 2 PLATES AT ONCE"},
	"tray2": {"name": "ENTREE TRAY", "cost": 65, "says": "RUN 4 PLATES AT ONCE", "needs": "tray", "opens": 4},
	# Third cook is a permanent upgrade for the saved night; keep the legacy id for saves.
	"temp": {"name": "THIRD COOK", "cost": 45, "says": "JO JOINS FOR THE NIGHT"},
	# Duff, Nov 26: "make the stations upgradable later on so that you can fire multiple dishes".
	# A kitchen upgrade, not a cook perk: it stays when a cook walks out.
	"burners_0": {"name": "GRILL BURNERS", "cost": 100, "says": "GRILL FIRES 2 OF A DISH", "opens": 4},
	"burners_1": {"name": "FRY BURNERS", "cost": 100, "says": "FRY FIRES 2 OF A DISH", "opens": 4},
	"burners_2": {"name": "SAUTE BURNERS", "cost": 100, "says": "SAUTE FIRES 2 OF A DISH", "opens": 4},
	"burners_3": {"name": "COLD BURNERS", "cost": 100, "says": "COLD FIRES 2 OF A DISH", "opens": 4},
}
const ORDER := ["meal", "lamps", "tray", "tray2", "temp", "burners_0", "burners_1", "burners_2", "burners_3", "iron", "comps"]
const MAX_TRAY := 4


## Each upgrade has a fixed one-time price.
static func price(id: String) -> int:
	return int(ALL[id].cost)


## Purchases never add tables; the service curve controls load.
static func load_tickets(_owned: Array) -> int:
	return 0


static func can_buy(id: String, cash: int, owned: Array, level: int = 999) -> bool:
	if not ALL.has(id) or owned.has(id) or cash < price(id) or level < int(ALL[id].get("opens", 1)):
		return false
	return not ALL[id].has("needs") or owned.has(ALL[id].needs)


## What the shop lists: a tray step shows only when it's the next one (one row for the trays).
static func shown(owned: Array, level: int = 999) -> Array:
	var tray_row := "tray2" if owned.has("tray") and (level >= int(ALL.tray2.opens) or owned.has("tray2")) else "tray"
	return ORDER.filter(func(id): return (not id.begins_with("tray") or id == tray_row) and (level >= int(ALL[id].get("opens", 1)) or owned.has(id)))


## Returns the cash left, or -1 if it can't be bought (owned array gains the id).
static func buy(id: String, cash: int, owned: Array, level: int = 999) -> int:
	if not can_buy(id, cash, owned, level):
		return -1
	owned.append(id)
	return cash - price(id)


## The service's numbers with the owned upgrades on top.
## base: {ticket_time, stress_cap, rush_stress, lives}
static func apply(base: Dictionary, owned: Array) -> Dictionary:
	var out := base.duplicate()
	if owned.has("lamps"):
		out.ticket_time += 1
	if owned.has("meal"):
		out.stress_cap += 1
	out["cast_iron"] = owned.has("iron")
	if owned.has("comps"):
		out.lives += 1
	out["tray"] = 4 if owned.has("tray2") else (2 if owned.has("tray") else 1)
	out["hires"] = 1 if owned.has("temp") else 0
	out["batch"] = 1
	out["batch_stations"] = range(4).filter(func(s): return owned.has("burners_%d" % s))
	return out
