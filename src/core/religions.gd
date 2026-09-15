class_name FmgReligions
extends RefCounted
## Religions: one folk religion per culture plus several organized religions
## expanding from culture centers. Simplified port of religions-generator.ts.

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var religions_limit: int = 6


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	pack.religions = [{
		"i": 0, "name": "No religion", "color": "#000", "type": "Folk",
		"culture": 0, "center": 0, "area": PackedInt32Array()
	}]

	# folk religion of every culture
	var folk_by_culture := {}
	for culture in pack.cultures:
		if culture == null or int(culture["i"]) == 0:
			continue
		var rid: int = pack.religions.size()
		folk_by_culture[int(culture["i"])] = rid
		pack.religions.append({
			"i": rid,
			"name": "%s gods" % culture["name"],
			"color": FmgColors.get_mixed_color(culture.get("color", "#999999"), rng),
			"type": "Folk",
			"culture": int(culture["i"]),
			"center": int(culture["center"]),
			"form": "",
			"god": "",
			"area": PackedInt32Array()
		})

	# organized religions: claim the most populated culture centers
	var cultures_sorted: Array = []
	for culture in pack.cultures:
		if culture == null or int(culture["i"]) == 0:
			continue
		cultures_sorted.append(culture)
	cultures_sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var s_a: float = float(pack.s[int(a["center"])]) if int(a["center"]) < pack.s.size() else 0.0
		var s_b: float = float(pack.s[int(b["center"])]) if int(b["center"]) < pack.s.size() else 0.0
		return s_a > s_b)

	var organized := PackedInt32Array()
	var used_cultures := {}
	for culture: Dictionary in cultures_sorted:
		if organized.size() >= religions_limit:
			break
		if used_cultures.has(int(culture["i"])):
			continue
		used_cultures[int(culture["i"])] = true
		var rid: int = pack.religions.size()
		var name_v: String = Names.get_culture_short(int(culture["i"]))
		pack.religions.append({
			"i": rid,
			"name": name_v + "ism",
			"color": FmgColors.get_random_color(rng),
			"type": "Organized",
			"culture": int(culture["i"]),
			"center": int(culture["center"]),
			"form": rng.rw({"Dogma": 6, "Cult": 3, "Philosophy": 1}),
			"god": Names.get_base(int(culture["base"]), 2, 5, ""),
			"area": PackedInt32Array()
		})
		organized.append(rid)

	# expansion: organized religions first, then folk fill the rest
	var religion_ids := PackedInt32Array()
	religion_ids.resize(pack.cell_count())
	var queue := FlatQueue.new()
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())

	for rid: int in organized:
		var religion: Dictionary = pack.religions[rid]
		queue.push([int(religion["center"]), rid, 0.0], 0.0)
		cost[int(religion["center"])] = 1.0

	var max_growth: float = float(pack.cell_count()) * 1.2
	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Array = pair[0]
		var cell: int = payload[0]
		var rid: int = payload[1]
		var priority: float = payload[2]
		var religion: Dictionary = pack.religions[rid]

		for neib: int in pack.c[cell]:
			if pack.h[neib] < 20:
				continue
			var step: float = 10.0
			if pack.biome[neib] == 1 or pack.biome[neib] == 2:
				step = 200.0 # deserts hinder spread
			if pack.biome[neib] == 11 or pack.biome[neib] == 12:
				step = 300.0
			if pack.culture[neib] != int(religion["culture"]):
				step += 60.0
			var total: float = priority + step
			if total > max_growth:
				continue
			if cost[neib] == 0.0 or total < cost[neib]:
				religion_ids[neib] = rid
				cost[neib] = total
				queue.push([neib, rid, total], total)

	# folk religions fill everything else
	var folk_queue := FlatQueue.new()
	var folk_cost := PackedFloat64Array()
	folk_cost.resize(pack.cell_count())
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		if religion_ids[i] == 0 and folk_by_culture.has(pack.culture[i]):
			religion_ids[i] = folk_by_culture[pack.culture[i]]
		if religion_ids[i] != 0:
			folk_queue.push([i, religion_ids[i], 0.0], 0.0)
			folk_cost[i] = 1.0

	while folk_queue.size() > 0:
		var pair: Array = folk_queue.pop_pair()
		var payload: Array = pair[0]
		var cell: int = payload[0]
		var rid: int = payload[1]
		var priority: float = payload[2]
		for neib: int in pack.c[cell]:
			if pack.h[neib] < 20 or religion_ids[neib] != 0:
				continue
			var total: float = priority + 10.0
			if folk_cost[neib] == 0.0 or total < folk_cost[neib]:
				religion_ids[neib] = rid
				folk_cost[neib] = total
				folk_queue.push([neib, rid, total], total)

	pack.religion = religion_ids

	# stats
	for religion in pack.religions:
		if religion == null:
			continue
		religion["cellsCount"] = 0
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var rid: int = religion_ids[i]
		if rid > 0 and rid < pack.religions.size():
			pack.religions[rid]["cellsCount"] = int(pack.religions[rid]["cellsCount"]) + 1
