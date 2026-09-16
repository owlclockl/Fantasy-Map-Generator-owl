class_name FmgReligions
extends RefCounted
## Religions: one folk religion per culture plus several organized religions
## expanding from culture centers, and heresies splitting off at the borders
## of organized faiths. Port of religions-generator.ts.

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

	_generate_heresies(religion_ids)

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


## Heresies split off organized religions at their borders and spread within
## the parent's lands (port of generateHeresies + expandHeresies).
func _generate_heresies(religion_ids: PackedInt32Array) -> void:
	var organized: Array = []
	for religion in pack.religions:
		if religion != null and religion.get("type", "") == "Organized":
			organized.append(religion)
	if organized.is_empty():
		return

	# boundary cells: religion cell adjacent to a different religion
	var boundary_cells := {} # religion id -> Array of cells
	for i: int in pack.cell_count():
		var rid: int = religion_ids[i]
		if rid == 0:
			continue
		if rid >= pack.religions.size() or pack.religions[rid].get("type", "") != "Organized":
			continue
		for neib: int in pack.c[i]:
			if religion_ids[neib] != rid:
				if not boundary_cells.has(rid):
					boundary_cells[rid] = []
				boundary_cells[rid].append(i)
				break

	var occupied_centers := {}
	for religion in pack.religions:
		if religion != null:
			occupied_centers[int(religion.get("center", 0))] = true

	var heresies: Array = []
	for parent: Dictionary in organized:
		var candidates: Array = []
		for cell_id: Variant in boundary_cells.get(int(parent["i"]), []):
			if not occupied_centers.has(int(cell_id)):
				candidates.append(int(cell_id))
		var count: int = int(rng.gauss(0.0, 1.0, 0.0, 3.0))
		for _k: int in count:
			if candidates.is_empty():
				break
			var index: int = int(rng.random() * float(candidates.size()))
			var center: int = candidates[index]
			candidates.remove_at(index)
			occupied_centers[center] = true
			heresies.append(_create_heresy(parent, center))

	if heresies.is_empty():
		return

	# expansion: heresy spreads over its parent's cells
	var max_cost: float = float(pack.cell_count()) / 20.0
	var queue := FlatQueue.new()
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())
	for heresy: Dictionary in heresies:
		religion_ids[int(heresy["center"])] = int(heresy["i"])
		queue.push({"e": int(heresy["center"]), "p": 0.0, "r": int(heresy["i"]), "b": int(heresy["origins"][0])}, 0.0)
		cost[int(heresy["center"])] = 1.0

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Dictionary = pair[0]
		var cell_id: int = payload["e"]
		var p: float = payload["p"]
		var rid: int = payload["r"]
		var base_id: int = payload["b"]
		var heresy: Dictionary = pack.religions[rid]
		for neib: int in pack.c[cell_id]:
			var religion_cost: float = 0.0 if religion_ids[neib] == base_id else 2000.0
			var passage_cost: float = 0.0
			if pack.h[neib] < 20:
				passage_cost = 500.0
			var expansionism: float = maxf(float(heresy.get("expansionism", 1.0)), 0.1)
			var total_cost: float = p + 10.0 + (religion_cost + passage_cost) / expansionism
			if total_cost > max_cost:
				continue
			if cost[neib] == 0.0 or total_cost < cost[neib]:
				if pack.culture[neib] != 0:
					religion_ids[neib] = rid
				cost[neib] = total_cost
				queue.push({"e": neib, "p": total_cost, "r": rid, "b": base_id}, total_cost)


func _create_heresy(parent: Dictionary, center: int) -> Dictionary:
	var rid: int = pack.religions.size()
	var prefix: String = rng.rw({"Reformed": 4, "True": 2, "Old": 2, "Free": 1, "Renewed": 1})
	var heresy := {
		"i": rid,
		"name": "%s %s" % [prefix, parent.get("name", "")],
		"color": FmgColors.get_mixed_color(parent.get("color", "#999999"), rng),
		"culture": pack.culture[center],
		"type": "Heresy",
		"form": parent.get("form", ""),
		"god": parent.get("god", ""),
		"center": center,
		"expansionism": rng.gauss(1.0, 0.5, 0.0, 5.0, 1),
		"origins": [int(parent["i"])],
		"area": PackedInt32Array()
	}
	pack.religions.append(heresy)
	return heresy
