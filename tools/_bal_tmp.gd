extends SceneTree
func _init() -> void:
	var K = load("res://scripts/kitchen.gd")
	var line := ""
	var grades := {}
	for n in [1, 2, 3, 4, 5]:
		var over := 0
		for sd in 200:
			var k = K.new()
			k.start(n, sd + 7)
			var guard := 0
			var lost := false
			while not k.done and guard < 80:
				k.bot_turn()
				k.end_turn()
				guard += 1
				if k.walked >= 3 or k.crew.all(func(c): return c.out):
					over += 1
					lost = true
					break
			if not lost and n <= 2:
				grades[k.grade()] = grades.get(k.grade(), 0) + 1
		line += " s%d %d%%" % [n, over / 2]
	print("BAL", line, " s1-2 grades ", grades)
	quit()
