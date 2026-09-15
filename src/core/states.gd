class_name FmgStates
extends RefCounted
## States: created from capital burgs, expanded with cost Dijkstra,
## normalized, colored, measured. Port of states-generator.ts
## (diplomacy/campaigns/military skipped in this edition).

const SEA_LEVEL: int = 20

const FORMS := {
	"Monarchy": {"Kingdom": 12, "Empire": 3, "Principality": 2, "Duchy": 2, "Tsardom": 1, "Khanate": 1, "Sultanate": 1, "Shogunate": 1},
	"Republic": {"Republic": 12, "Commonwealth": 2, "Union": 1, "Confederation": 1},
	"Theocracy": {"Theocracy": 5, "Caliphate": 2, "Papacy": 1, "Holy State": 1},
	"Union": {"Union": 5, "Federation": 2, "Alliance": 1, "League": 1},
	"Anarchy": {"Free Land": 1, "Anarchy": 1, "Commune": 1}
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var states_limit: int = 18
var size_variety: float = 4.0
var growth_rate: float = 1.0
var provinces_ratio: float = 20.0
var religions_limit: int = 6


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	create_states()
	expand_states()
	normalize_states()
	find_neighbors()
	assign_colors()
	poles = {}
	get_poles()
	collect_statistics()
	define_state_forms()


func create_states() -> void:
	pack.states = [{"i": 0, "name": "Neutrals", "color": "", "form": "Wild", "provinces": []}]

	for b in pack.burgs:
		if b == null or b.get("capital", 0) != 1:
			continue
		var expansionism: float = FmgRng.rn(rng.random() * size_variety + 1.0, 1)
		var basename: String = b["name"] if b["name"].length() < 9 and b["cell"] % 5 == 0 else Names.get_culture_short(b["culture"])
		var name_v: String = Names.get_state(basename, b["culture"])
		var type: String = pack.cultures[b["culture"]]["type"]
		pack.states.append({
			"i": b["i"],
			"name": name_v,
			"expansionism": expansionism,
			"capital": b["i"],
			"type": type,
			"center": b["cell"],
			"culture": b["culture"],
			"color": "",
			"provinces": []
		})

	pack.state = PackedInt32Array()
	pack.state.resize(pack.cell_count())


func _get_biome_cost(b: int, biome: int, type: String) -> float:
	if b == biome:
		return 10.0
	var cost: float = pack.biomes[biome]["cost"]
	if type == "Hunting":
		return cost * 2.0
	if type == "Nomadic" and biome > 4 and biome < 10:
		return cost * 3.0
	return cost


func _get_height_cost(fid: int, h: int, type: String) -> float:
	var is_lake: bool = false
	if fid > 0 and fid < pack.features.size():
		is_lake = pack.features[fid]["type"] == "lake"
	if type == "Lake" and is_lake:
		return 10.0
	if type == "Naval" and h < 20:
		return 300.0
	if type == "Nomadic" and h < 20:
		return 10000.0
	if h < 20:
		return 1000.0
	if type == "Highland" and h < 62:
		return 1100.0
	if type == "Highland":
		return 0.0
	if h >= 67:
		return 2200.0
	if h >= 44:
		return 300.0
	return 0.0


func _get_river_cost(river: int, i: int, type: String) -> float:
	if type == "River":
		return 0.0 if river != 0 else 100.0
	if river == 0:
		return 0.0
	return clampf(pack.fl[i] / 10.0, 20.0, 100.0)


func _get_type_cost(t: int, type: String) -> float:
	if t == 1:
		if type == "Naval" or type == "Lake":
			return 0.0
		return 60.0 if type == "Nomadic" else 20.0
	if t == 2:
		return 30.0 if type == "Naval" or type == "Nomadic" else 0.0
	if t != -1:
		return 100.0 if type == "Naval" or type == "Lake" else 0.0
	return 0.0


func expand_states() -> void:
	var queue := FlatQueue.new()
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())

	pack.state = PackedInt32Array()
	pack.state.resize(pack.cell_count())
	var growth_rate_v: float = (float(pack.cell_count()) / 2.0) * growth_rate

	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		var capital_cell: int = pack.burg[state["capital"]]
		pack.state[capital_cell] = state["i"]
		var native_biome: int = pack.biome[int(pack.cultures[state["culture"]]["center"])]
		queue.push([int(state["center"]), 0.0, int(state["i"]), native_biome], 0.0)
		cost[int(state["center"])] = 1.0

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Array = pair[0]
		var e: int = payload[0]
		var p: float = payload[1]
		var s: int = payload[2]
		var b: int = payload[3]
		var state: Dictionary = pack.states[s]
		var type: String = state["type"]
		var culture: int = int(state["culture"])

		for neib: int in pack.c[e]:
			if pack.state[neib] != 0 and neib == int(pack.states[pack.state[neib]]["center"]):
				continue # do not overwrite capital cells

			var culture_cost: float = -9.0 if culture == pack.culture[neib] else 100.0
			var population_cost: float = 0.0
			if pack.h[neib] >= 20:
				population_cost = maxf(20.0 - float(pack.s[neib]), 0.0) if pack.s[neib] != 0 else 5000.0
			var biome_cost: float = _get_biome_cost(b, pack.biome[neib], type)
			var height_cost: float = _get_height_cost(pack.f[neib], pack.h[neib], type)
			var river_cost: float = _get_river_cost(pack.r[neib], neib, type)
			var type_cost: float = _get_type_cost(pack.t[neib], type)
			var cell_cost: float = maxf(culture_cost + population_cost + biome_cost + height_cost + river_cost + type_cost, 0.0)
			var total_cost: float = p + 10.0 + cell_cost / float(state["expansionism"])

			if total_cost > growth_rate_v:
				continue
			if cost[neib] == 0.0 or total_cost < cost[neib]:
				if pack.h[neib] >= 20:
					pack.state[neib] = s
				cost[neib] = total_cost
				queue.push([neib, total_cost, s, b], total_cost)

	for burg in pack.burgs:
		if burg == null:
			continue
		burg["state"] = pack.state[burg["cell"]]


func normalize_states() -> void:
	for i: int in pack.cell_count():
		if pack.h[i] < 20 or pack.burg[i] != 0:
			continue
		var neibs_land := PackedInt32Array()
		for c: int in pack.c[i]:
			if pack.h[c] >= 20:
				neibs_land.append(c)
		var adversaries := PackedInt32Array()
		var buddies := PackedInt32Array()
		for c: int in neibs_land:
			if pack.state[c] != pack.state[i]:
				adversaries.append(c)
			else:
				buddies.append(c)
		if adversaries.size() < 2 or buddies.size() > 2 or adversaries.size() <= buddies.size():
			continue
		# do not overwrite cells near a capital
		var near_capital: bool = false
		for c: int in pack.c[i]:
			var bid: int = pack.burg[c]
			if bid != 0 and pack.burgs[bid].get("capital", 0):
				near_capital = true
				break
		if near_capital:
			continue
		pack.state[i] = pack.state[adversaries[0]]


var poles: Dictionary = {} # state id -> pole position


## pole of inaccessibility per state: interior cell farthest from the border
func get_poles() -> void:
	poles = {}
	# multi-source BFS from state-border cells; track depth per state
	var cells_count: int = pack.cell_count()
	var dist := PackedInt32Array()
	dist.resize(cells_count)
	dist.fill(-1)
	var queue: Array = []
	for i: int in cells_count:
		if pack.h[i] < 20:
			continue
		var is_border: bool = false
		for c: int in pack.c[i]:
			if pack.h[c] < 20 or pack.state[c] != pack.state[i]:
				is_border = true
				break
		if is_border:
			dist[i] = 0
			queue.append(i)
	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		for c: int in pack.c[cell]:
			if dist[c] != -1 or pack.h[c] < 20 or pack.state[c] != pack.state[cell]:
				continue
			dist[c] = dist[cell] + 1
			queue.append(c)

	var best_depth := {}
	for i: int in cells_count:
		if pack.h[i] < 20 or pack.state[i] == 0 or dist[i] < 0:
			continue
		var s: int = pack.state[i]
		if not best_depth.has(s) or dist[i] > int(best_depth[s]):
			best_depth[s] = dist[i]
			poles[s] = pack.points[i]


func find_neighbors() -> void:
	for state in pack.states:
		if state == null:
			continue
		state["neighbors"] = []
	var neighbor_sets := {}
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var s: int = pack.state[i]
		if not neighbor_sets.has(s):
			neighbor_sets[s] = {}
		for c: int in pack.c[i]:
			if pack.h[c] >= 20 and pack.state[c] != s:
				neighbor_sets[s][pack.state[c]] = true
	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		var set_dict: Dictionary = neighbor_sets.get(state["i"], {})
		state["neighbors"] = set_dict.keys()


## greedy coloring of the neighbor graph, then randomize used colors a bit
func assign_colors() -> void:
	var base_colors: Array = ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f"]
	var colors: Array = base_colors.duplicate()
	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		var assigned: String = ""
		for color: String in colors:
			var ok: bool = true
			for neib: int in state.get("neighbors", []):
				var neib_state: Dictionary = pack.states[neib] if neib < pack.states.size() else null
				if neib_state != null and neib_state.get("color", "") == color:
					ok = false
					break
			if ok:
				assigned = color
				break
		if assigned.is_empty():
			assigned = FmgColors.get_random_color(rng)
		state["color"] = assigned
		colors.append(colors.pop_front())

	# randomize each already-used color a bit
	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		state["color"] = FmgColors.get_mixed_color(state["color"], rng, 0.06, 0)


func collect_statistics() -> void:
	for state in pack.states:
		if state == null:
			continue
		state["cells"] = 0
		state["area"] = 0.0
		state["burgsCount"] = 0
		state["rural"] = 0.0
		state["urban"] = 0.0
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var s: int = pack.state[i]
		if s == 0 or s >= pack.states.size():
			continue
		var state: Dictionary = pack.states[s]
		state["cells"] = int(state["cells"]) + 1
		state["area"] = float(state["area"]) + pack.area[i]
		state["rural"] = float(state["rural"]) + pack.pop[i]
	for burg in pack.burgs:
		if burg == null:
			continue
		var s: int = burg.get("state", 0)
		if s > 0 and s < pack.states.size():
			var state: Dictionary = pack.states[s]
			state["burgsCount"] = int(state["burgsCount"]) + 1
			state["urban"] = float(state["urban"]) + float(burg.get("population", 0.0))


func define_state_forms() -> void:
	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		var cells: int = state.get("cells", 0)
		var burgs_count: int = state.get("burgsCount", 0)
		var type: String = state["type"]
		var form: String
		if cells > int(pack.cell_count() / 10.0) and rng.P(0.6):
			form = "Empire"
		elif cells > 20 and burgs_count > 4 and type != "Nomadic":
			var options := {"Monarchy": 26, "Republic": 7, "Union": 2}
			if type == "River":
				options["Republic"] = 12
			if type == "Hunting" or type == "Highland":
				options["Theocracy"] = 4
			if type == "Nomadic":
				options["Anarchy"] = 3
			form = rng.rw(options)
		else:
			form = "Monarchy" if rng.P(0.92) else "Union"
		state["form"] = form
		var forms: Dictionary = FORMS.get(form, FORMS["Monarchy"])
		state["formName"] = rng.rw(forms)
		state["fullName"] = "%s %s" % [state["name"], state["formName"]]
