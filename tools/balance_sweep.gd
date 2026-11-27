extends SceneTree
## Deterministic comparative balance sweep (not a human playtest).
## Run with isolated XDG_DATA_HOME: godot --headless --path . --script tools/balance_sweep.gd
## CSV files are written to user://, printed on completion. Fixed inventories deliberately
## include hypothetical equipment at early stages; campaign purchases obey shop gates.
const K = preload("res://scripts/kitchen.gd")
const U = preload("res://scripts/upgrades.gd")
const N = 240
func setup(n:int, sd:int, owned:Array, cp:Dictionary, pace:int=1, ease:int=0, gone:Array=[], pressure:int=0):
	var k = K.new()
	var u = U.apply({"ticket_time":9,"stress_cap":6,"rush_stress":1,"lives":3}, owned)
	k.ticket_time = maxi(5, u.ticket_time + [2,0,-1][pace] + (1 if ease>=2 else (-1 if ease<=-2 else 0)))
	k.challenge = pressure if n >= 3 and pace != 0 else 0
	k.first_tickets = maxi(3,7+[-1,0,2][pace]-ease)+k.challenge
	k.stress_cap=u.stress_cap
	k.rush_stress=u.rush_stress
	k.tray=u.tray
	k.hires=u.hires
	k.batch_stations=u.batch_stations
	k.cast_iron=u.cast_iron
	k.cook_perks=cp
	k.gone=gone.duplicate()
	k.start(n,sd)
	return [k,u.lives]
func play(k, lives:int, rush:bool):
	while not k.done and k.walked<lives and not k.crew.all(func(c):return c.out):
		if not rush:
			k.bot_turn()
		else:
			for c in k.crew.size():
				if k.crew[c].stress>=k.stress_cap-2: continue
				for j in 10:
					if not k.can_act(c): break
					var a=k.action_here(c,false)
					if a!="" and k.act_here(c,0,false): continue
					var goal=k._bot_goal(c)
					if goal>=0 and goal!=k.crew[c].at:
						var step=k.crew[c].at+signi(goal-k.crew[c].at)
						while not k.is_open(step): step+=signi(goal-k.crew[c].at)
						if k.move(c,step): continue
					if k.crew[c].stress+k.rush_cost()<k.stress_cap-2 and k.action_here(c,true)=="RUSH" and k.rush(c): continue
					break
		k.end_turn()
	return k.walked<lives and not k.crew.all(func(c):return c.out)
func _initialize():
	await process_frame
	var f=FileAccess.open("user://balance_services.csv",FileAccess.WRITE)
	f.store_line("scenario,service,seed,win,served,total,walked,tips,grade,burns,turn,event,quit")
	var kit = ["temp","meal","lamps","tray","iron"]
	var full = kit + ["tray2","comps","burners_0","burners_1","burners_2","burners_3"]
	var advanced = {"DEV":["fast_0","plate","heat_master"],"MO":["walk","prep","long_stride"],"JO":["run","recovery","pass_captain"]}
	var scenarios={
		"base":[[],{},1,false,0],
		"jo":[["temp"],{},1,false,0],
		"jo_pressure":[["temp"],{},1,false,3],
		"jo_kit":[kit,{},1,false,0],
		"jo_kit_pressure":[kit,{},1,false,3],
		"jo_full":[full,{},1,false,0],
		"jo_full_pressure":[full,{},1,false,3],
		"jo_advanced":[kit,advanced,1,false,0],
		"jo_advanced_pressure":[kit,advanced,1,false,3],
		"jo_kit_rush":[kit,{},1,true,0],
		"jo_kit_rush_pressure":[kit,{},1,true,3],
		"relaxed":[[],{},0,false,3],
		"slammed":[[],{},2,false,0],
	}
	for name in scenarios:
		var s=scenarios[name]
		for n in range(1,9):
			if name.begins_with("jo") and n==1:continue
			if name.begins_with("perk_") and n==1:continue
			for sd in range(7,7+N):
				var a=setup(n,sd,s[0],s[1],s[2],0,[],s[4])
				var k=a[0]
				var win=play(k,a[1],s[3])
				f.store_line("%s,%d,%d,%d,%d,%d,%d,%d,%s,%d,%d,%s,%d"%[name,n,sd,int(win),k.served,k.total,k.walked,k.tips,k.grade(),k.burns,k.turn,k.event,k.crew.filter(func(c):return c.out).size()])
	f.close()
	var g=FileAccess.open("user://balance_campaigns.csv",FileAccess.WRITE)
	g.store_line("strategy,seed,service,win,cash_before,cash_after,bought,owned,grade,served,total,ease,jo_unlock,pressure")
	var strategies={"save_jo":["temp","lamps","burners_0","tray","comps","meal","iron","tray2","burners_1","burners_2","burners_3"],"cheap_first":["meal","lamps","tray","temp","comps","iron","burners_0","tray2","burners_1","burners_2","burners_3"],"tray_first":["tray","tray2","temp","burners_1","lamps","meal","comps","iron","burners_0","burners_2","burners_3"],"lamps_first":["lamps","temp","tray","burners_0","comps","meal","iron","tray2","burners_1","burners_2","burners_3"],"no_shop":[]}
	strategies["relaxed"] = strategies.save_jo
	strategies["slammed"] = strategies.save_jo
	for name in strategies:
		var pace = 0 if name == "relaxed" else (2 if name == "slammed" else 1)
		for sd in range(7,7+N):
			var owned:Array=[]
			var cash=0
			var ease=0
			var pressure=0
			var cp={}
			var gone=[]
			var unlocked=0
			for n in range(1,9):
				var a=setup(n,sd+n*1000,owned,cp,pace,ease,gone,pressure)
				var k=a[0]
				var win=play(k,a[1],false)
				var before=cash
				var bought:Array=[]
				if win:
					cash+=k.tips+K.GRADE_BONUS[k.grade()]
					var mvp=""
					var acts=-1
					for cr in k.crew:
						if cr.name not in ["DEV","MO","JO"] or cr.name in gone or cr.out:continue
						if cr.work>0 and (cr.work>acts or (cr.work==acts and cp.get(cr.name,[]).size()<cp.get(mvp,[]).size())):
							mvp=cr.name
							acts=cr.work
					if mvp!="":
						var have:Array=cp.get(mvp,[])
						var game=load("res://scripts/game.gd").new()
						game.level=n+1
						game.cook_perks=cp
						var offer=game.perk_offer(mvp)
						game.free()
						for id in ["heat_master","pass_captain","deep_rest","long_stride","walk","plate","fast_0","fast_1","fast_2","run","fast_3","recovery","steady","prep"]:
							if offer.has(id):
								have.append(id)
								cp[mvp]=have
								break
					for id in strategies[name]:
						if owned.has(id):continue
						if int(U.ALL[id].get("opens",1))>n+1:continue
						if U.can_buy(id,cash,owned,n+1):
							cash=U.buy(id,cash,owned,n+1)
							bought.append(id)
							if id=="temp":unlocked=n
						else:break
					if pace != 0 or k.grade() in ["D", "F"]:
						pressure = K.pressure_after(pressure, k.grade(), n)
					if k.grade() in ["D","F"]:ease=mini(2,ease+1)
					elif n>=2 and k.grade() in ["A","A+"]:ease=maxi(-2,ease-1)
					for cr in k.crew:
						if cr.out and cr.name in ["DEV","MO"] and not gone.has(cr.name) and gone.size()<1:gone.append(cr.name)
				g.store_line("%s,%d,%d,%d,%d,%d,%s,%s,%s,%d,%d,%d,%d,%d"%[name,sd,n,int(win),before,cash,"+".join(bought),"+".join(owned),k.grade(),k.served,k.total,ease,unlocked,pressure])
				if not win:break
	g.close()
	print("BALANCE COMPLETE: ", ProjectSettings.globalize_path("user://balance_services.csv"), " and balance_campaigns.csv")
	quit()
