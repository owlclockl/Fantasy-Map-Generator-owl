class_name FmgZones
extends RefCounted
## Named zones. Port of zones-generator.ts: invasions (from ongoing wars),
## rebels, proselytism, crusades, diseases, disasters, eruptions, avalanches,
## faults, floods and tsunamis. Zone: {i, name, type, cells, color}.

const ZONE_COLORS := {
	"Invasion": "#8b0000", "Rebels": "#8b4513", "Proselytism": "#4b0082",
	"Crusade": "#6a0dad", "Disease": "#556b2f", "Disaster": "#a0522d",
	"Eruption": "#b22222", "Avalanche": "#708090", "Fault": "#2f4f4f",
	"Flood": "#1e6091", "Tsunami": "#005f73"
}

# expected zone counts per type (upstream zones-generator config)
const ZONE_TYPES := {
	"invasion": 2.0, "rebels": 1.5, "proselytism": 1.6, "crusade": 1.6,
	"disease": 1.4, "disaster": 1.0, "eruption": 1.0, "avalanche": 0.8,
	"fault": 1.0, "flood": 1.0, "tsunami": 1.0
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var routes: FmgRoutes
var used := PackedByteArray()


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph, routes_ref: FmgRoutes) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref
	routes = routes_ref


func generate() -> void:
	pack.zones = []
	used = PackedByteArray()
	used.resize(pack.cell_count())

	for zone_type: Variant in ZONE_TYPES:
		var expected: float = ZONE_TYPES[zone_type]
		var count: int = int(rng.gauss(expected, expected / 2.0, 0.0, 100.0))
		for _k: int in count:
			match str(zone_type):
				"invasion": _add_invasion()
				"rebels": _add_rebels()
				"proselytism": _add_proselytism()
				"crusade": _add_crusade()
				"disease": _add_disease()
				"disaster": _add_disaster()
				"eruption": _add_eruption()
				"avalanche": _add_avalanche()
				"fault": _add_fault()
				"flood": _add_flood()
				"tsunami": _add_tsunami()


func _push_zone(name_v: String, type: String, cells_arr: Array) -> void:
	if cells_arr.is_empty():
		return
	pack.zones.append({
		"i": pack.zones.size(), "name": name_v, "type": type,
		"cells": cells_arr, "color": ZONE_COLORS.get(type, "#888888")
	})


## ongoing wars invade the defender's border lands
func _add_invasion() -> void:
	var ongoing: Array = []
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		for campaign: Variant in state.get("campaigns", []):
			if (campaign as Dictionary).get("end") == null:
				ongoing.append(campaign)
	if ongoing.is_empty():
		return
	var conflict: Dictionary = rng.ra(ongoing)
	var defender: int = int(conflict["defender"])
	var attacker: int = int(conflict["attacker"])
	if defender <= 0 or attacker <= 0 or attacker >= pack.states.size():
		return

	var border_cells: Array = []
	for i: int in pack.cell_count():
		if used[i] == 1 or pack.state[i] != defender:
			continue
		for neib: int in pack.c[i]:
			if pack.state[neib] == attacker:
				border_cells.append(i)
				break
	if border_cells.is_empty():
		return
	var start_cell: int = rng.ra(border_cells)

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(5, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front() if rng.P(0.4) else queue.pop_back()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.state[neib] != defender:
				continue
			used[neib] = 1
			queue.append(neib)

	var subtype: String = rng.rw({
		"Invasion": 5, "Occupation": 4, "Conquest": 3, "Incursion": 2, "Intervention": 2,
		"Assault": 1, "Foray": 1, "Intrusion": 1, "Irruption": 1, "Offensive": 1,
		"Pillaging": 1, "Plunder": 1, "Raid": 1, "Skirmishes": 1
	})
	_push_zone("%s %s" % [FmgDiplomacy.get_adjective(pack.states[attacker].get("name", "")), subtype], "Invasion", cells_arr)


func _add_rebels() -> void:
	var candidates: Array = []
	for s_idx: int in range(1, pack.states.size()):
		var s: Dictionary = pack.states[s_idx]
		if s != null and int(s.get("i", 0)) > 0 and not (s.get("neighbors", []) as Array).is_empty():
			candidates.append(s)
	if candidates.is_empty():
		return
	var state: Dictionary = rng.ra(candidates)
	var neib_ids: Array = []
	for n: Variant in state.get("neighbors", []):
		var n_id: int = int(n)
		if n_id > 0 and n_id < pack.states.size() and pack.states[n_id] != null:
			neib_ids.append(n_id)
	if neib_ids.is_empty():
		return
	var neib_state_id: int = rng.ra(neib_ids)

	var start_cell: int = -1
	for i: int in pack.cell_count():
		if pack.state[i] == int(state["i"]):
			for neib: int in pack.c[i]:
				if pack.state[neib] == neib_state_id:
					start_cell = i
					break
		if start_cell != -1:
			break
	if start_cell == -1:
		return

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(10, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.state[neib] != int(state["i"]):
				continue
			used[neib] = 1
			var near_border: bool = false
			for c2: int in pack.c[neib]:
				if pack.state[c2] == neib_state_id:
					near_border = true
					break
			if neib % 4 == 0 or near_border:
				queue.append(neib)

	var rebels: String = rng.rw({
		"Rebels": 5, "Insurrection": 2, "Mutineers": 1, "Insurgents": 1, "Rebellion": 1,
		"Renegades": 1, "Revolters": 1, "Revolutionaries": 1, "Rioters": 1,
		"Separatists": 1, "Secessionists": 1, "Conspiracy": 1
	})
	_push_zone("%s %s" % [FmgDiplomacy.get_adjective(pack.states[neib_state_id].get("name", "")), rebels], "Rebels", cells_arr)


func _add_proselytism() -> void:
	var organized: Array = []
	for religion in pack.religions:
		if religion != null and int(religion.get("i", 0)) > 0 and religion.get("type", "") == "Organized":
			organized.append(religion)
	if organized.is_empty():
		return
	var religion: Dictionary = rng.ra(organized)

	var border_cells: Array = []
	for i: int in pack.cell_count():
		if pack.h[i] < 20 or pack.pop[i] <= 0.0 or pack.religion[i] == int(religion["i"]):
			continue
		for neib: int in pack.c[i]:
			if pack.religion[neib] == int(religion["i"]):
				border_cells.append(i)
				break
	if border_cells.is_empty():
		return
	var start_cell: int = rng.ra(border_cells)
	var target_religion: int = pack.religion[start_cell]

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(10, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.religion[neib] != target_religion:
				continue
			if pack.h[neib] < 20 or pack.pop[neib] <= 0.0:
				continue
			used[neib] = 1
			queue.append(neib)

	var first_word: String = str(religion["name"]).split(" ")[0]
	_push_zone("%s Proselytism" % FmgDiplomacy.get_adjective(first_word), "Proselytism", cells_arr)


func _add_crusade() -> void:
	var heresies: Array = []
	for religion in pack.religions:
		if religion != null and religion.get("type", "") == "Heresy":
			heresies.append(religion)
	if heresies.is_empty():
		return
	var heresy: Dictionary = rng.ra(heresies)
	var cells_arr: Array = []
	for i: int in pack.cell_count():
		if used[i] == 0 and pack.religion[i] == int(heresy["i"]):
			cells_arr.append(i)
	if cells_arr.is_empty():
		return
	for cell_id: Variant in cells_arr:
		used[int(cell_id)] = 1
	var first_word: String = str(heresy["name"]).split(" ")[0]
	_push_zone("%s Crusade" % FmgDiplomacy.get_adjective(first_word), "Crusade", cells_arr)


func _add_disease() -> void:
	var burg_candidates: Array = []
	for burg in pack.burgs:
		if burg != null and int(burg.get("i", 0)) > 0 and used[int(burg["cell"])] == 0:
			burg_candidates.append(burg)
	if burg_candidates.is_empty():
		return
	var burg: Dictionary = rng.ra(burg_candidates)

	var cells_arr: Array = []
	var cost := {}
	var max_cells: int = rng.rand(20, 40)
	var queue := FlatQueue.new()
	queue.push({"e": int(burg["cell"]), "p": 0.0}, 0.0)

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Dictionary = pair[0]
		var e: int = payload["e"]
		var p: float = payload["p"]
		if pack.burg[e] != 0 or pack.pop[e] > 0.0:
			cells_arr.append(e)
		used[e] = 1
		for neib: int in pack.c[e]:
			var step: float = routes.route_step_cost(e, neib)
			var total: float = p + step
			if total > float(max_cells):
				continue
			if not cost.has(neib) or total < float(cost[neib]):
				cost[neib] = total
				queue.push({"e": neib, "p": total}, total)

	var prefix: String = rng.rw({"color": 2, "animal": 1, "adjective": 1})
	var prefix_name: String
	if prefix == "color":
		prefix_name = rng.ra(["Black", "Red", "White", "Yellow", "Crimson", "Golden", "Purple"])
	elif prefix == "animal":
		prefix_name = rng.ra(["Wolf", "Raven", "Rat", "Snake", "Spider", "Ox"])
	else:
		prefix_name = rng.ra(["Rotten", "Silent", "Evil", "Ancient", "Hungry", "Secret"])
	var disease: String = rng.rw({
		"Fever": 5, "Plague": 3, "Cough": 3, "Flu": 2, "Pox": 2, "Cholera": 2,
		"Typhoid": 2, "Leprosy": 1, "Smallpox": 1, "Pestilence": 1, "Consumption": 1, "Malaria": 1
	})
	_push_zone("%s %s" % [prefix_name, disease], "Disease", cells_arr)


func _add_disaster() -> void:
	var burg_candidates: Array = []
	for burg in pack.burgs:
		if burg != null and int(burg.get("i", 0)) > 0 and used[int(burg["cell"])] == 0:
			burg_candidates.append(burg)
	if burg_candidates.is_empty():
		return
	var burg: Dictionary = rng.ra(burg_candidates)
	used[int(burg["cell"])] = 1

	var cells_arr: Array = []
	var cost := {}
	var max_cells: int = rng.rand(5, 25)
	var queue := FlatQueue.new()
	queue.push({"e": int(burg["cell"]), "p": 0.0}, 0.0)
	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Dictionary = pair[0]
		var e: int = payload["e"]
		var p: float = payload["p"]
		if pack.burg[e] != 0 or pack.pop[e] > 0.0:
			cells_arr.append(e)
		used[e] = 1
		for neib: int in pack.c[e]:
			var total: float = p + float(rng.rand(1, 10))
			if total > float(max_cells):
				continue
			if not cost.has(neib) or total < float(cost[neib]):
				cost[neib] = total
				queue.push({"e": neib, "p": total}, total)

	var disaster_type: String = rng.rw({
		"Famine": 5, "Drought": 3, "Earthquake": 3, "Dearth": 1,
		"Tornadoes": 1, "Wildfires": 1, "Storms": 1, "Blight": 1
	})
	_push_zone("%s %s" % [FmgDiplomacy.get_adjective(burg.get("name", "")), disaster_type], "Disaster", cells_arr)


func _add_eruption() -> void:
	var volcano: Dictionary = {}
	for marker: Variant in pack.markers:
		var m: Dictionary = marker
		if m.get("type", "") == "volcanoes" and used[int(m["cell"])] == 0:
			volcano = m
			break
	if volcano.is_empty():
		return
	var volcano_cell: int = int(volcano["cell"])
	used[volcano_cell] = 1
	var name_v: String = "%s Eruption" % FmgDiplomacy.get_adjective(Names.get_culture_short(pack.culture[volcano_cell]))

	var cells_arr: Array = []
	var queue: Array = [int(volcano["cell"])]
	var max_cells: int = rng.rand(10, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front() if rng.P(0.5) else queue.pop_back()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.h[neib] < 20:
				continue
			used[neib] = 1
			queue.append(neib)
	_push_zone(name_v, "Eruption", cells_arr)


func _add_avalanche() -> void:
	var route_cells: Array = []
	for i: int in pack.cell_count():
		if used[i] == 0 and routes.is_connected(i) and pack.h[i] >= 70:
			route_cells.append(i)
	if route_cells.is_empty():
		return
	var start_cell: int = rng.ra(route_cells)
	used[start_cell] = 1

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(3, 15)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front() if rng.P(0.3) else queue.pop_back()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.h[neib] < 65:
				continue
			used[neib] = 1
			queue.append(neib)
	_push_zone("%s Avalanche" % FmgDiplomacy.get_adjective(Names.get_culture_short(pack.culture[start_cell])), "Avalanche", cells_arr)


func _add_fault() -> void:
	var elevated: Array = []
	for i: int in pack.cell_count():
		if used[i] == 0 and pack.h[i] > 50 and pack.h[i] < 70:
			elevated.append(i)
	if elevated.is_empty():
		return
	var start_cell: int = rng.ra(elevated)
	used[start_cell] = 1

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(3, 15)
	while not queue.is_empty():
		var cell_id: int = queue.pop_back()
		if pack.h[cell_id] >= 20:
			cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.r[neib] != 0:
				continue
			used[neib] = 1
			queue.append(neib)
	_push_zone("%s Fault" % FmgDiplomacy.get_adjective(Names.get_culture_short(pack.culture[start_cell])), "Fault", cells_arr)


func _add_flood() -> void:
	var flux_sum: float = 0.0
	var flux_count: int = 0
	var max_flux: float = 0.0
	for i: int in pack.cell_count():
		if pack.fl[i] > 0.0:
			flux_sum += pack.fl[i]
			flux_count += 1
			max_flux = maxf(max_flux, pack.fl[i])
	if flux_count == 0:
		return
	var mean_flux: float = flux_sum / float(flux_count)
	var threshold: float = (max_flux - mean_flux) / 2.0 + mean_flux

	var big_river_cells: Array = []
	for i: int in pack.cell_count():
		if used[i] == 0 and pack.h[i] < 50 and pack.r[i] != 0 and pack.fl[i] > threshold and pack.burg[i] != 0:
			big_river_cells.append(i)
	if big_river_cells.is_empty():
		return
	var start_cell: int = rng.ra(big_river_cells)
	used[start_cell] = 1
	var river_id: int = pack.r[start_cell]

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(5, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_back()
		cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.h[neib] < 20 or pack.r[neib] != river_id:
				continue
			if pack.h[neib] > 50 or pack.fl[neib] < mean_flux:
				continue
			used[neib] = 1
			queue.append(neib)
	_push_zone("%s Flood" % FmgDiplomacy.get_adjective(Names.get_culture_short(pack.culture[start_cell])), "Flood", cells_arr)


func _add_tsunami() -> void:
	var coastal: Array = []
	for i: int in pack.cell_count():
		if used[i] == 1 or pack.t[i] != -1:
			continue
		if pack.feature_of(i).get("type", "") != "lake":
			coastal.append(i)
	if coastal.is_empty():
		return
	var start_cell: int = rng.ra(coastal)
	used[start_cell] = 1

	var cells_arr: Array = []
	var queue: Array = [start_cell]
	var max_cells: int = rng.rand(10, 30)
	while not queue.is_empty():
		var cell_id: int = queue.pop_front()
		if pack.t[cell_id] == 1:
			cells_arr.append(cell_id)
		if cells_arr.size() >= max_cells:
			break
		for neib: int in pack.c[cell_id]:
			if used[neib] == 1 or pack.t[neib] > 2:
				continue
			if pack.feature_of(neib).get("type", "") == "lake":
				continue
			used[neib] = 1
			queue.append(neib)
	_push_zone("%s Tsunami" % FmgDiplomacy.get_adjective(Names.get_culture_short(pack.culture[start_cell])), "Tsunami", cells_arr)
