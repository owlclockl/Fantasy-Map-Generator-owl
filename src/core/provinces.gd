class_name FmgProvinces
extends RefCounted
## Provinces: created for the biggest burgs of each state, expanded by a
## cheap Dijkstra. Port of provinces-generator.ts.

const SEA_LEVEL: int = 20

const FORMS := {
	"Monarchy": {"County": 22, "Earldom": 6, "Shire": 2, "Landgrave": 2, "Margrave": 2, "Barony": 2, "Captaincy": 1, "Seneschalty": 1},
	"Republic": {"Province": 6, "Department": 2, "Governorate": 2, "District": 1, "Canton": 1, "Prefecture": 1},
	"Theocracy": {"Parish": 3, "Deanery": 1},
	"Union": {"Province": 1, "State": 1, "Canton": 1, "Republic": 1, "County": 1, "Council": 1},
	"Anarchy": {"Council": 1, "Commune": 1, "Community": 1, "Tribe": 1},
	"Wild": {"Territory": 10, "Land": 5, "Region": 2, "Tribe": 1, "Clan": 1, "Dependency": 1, "Area": 1}
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var provinces_ratio: float = 20.0
var burgs_ref: FmgBurgs


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph, burgs: FmgBurgs) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref
	burgs_ref = burgs


func generate() -> void:
	pack.provinces = [null]
	var province_ids := PackedInt32Array()
	province_ids.resize(pack.cell_count())

	var max_growth: float = rng.gauss(20.0, 5.0, 5.0, 100.0) * sqrt(provinces_ratio) if provinces_ratio < 100.0 else 1000.0

	for state in pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		state["provinces"] = []

		var state_burgs: Array = []
		for b in pack.burgs:
			if b == null:
				continue
			if b.get("state", 0) == int(state["i"]) and province_ids[b["cell"]] == 0:
				state_burgs.append(b)
		if state_burgs.size() < 2:
			continue
		state_burgs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.get("capital", 0) != b.get("capital", 0):
				return a.get("capital", 0) > b.get("capital", 0)
			return float(a.get("population", 0.0)) > float(b.get("population", 0.0)))

		var provinces_number: int = maxi(int(ceil(float(state_burgs.size()) * provinces_ratio / 100.0)), 2)
		var form: Dictionary = FORMS.get(state.get("form", "Monarchy"), FORMS["Monarchy"]).duplicate()

		for i: int in mini(provinces_number, state_burgs.size()):
			var province_id: int = pack.provinces.size()
			var burg: Dictionary = state_burgs[i]
			var center: int = burg["cell"]
			var c: int = int(burg["culture"])
			var name_by_burg: bool = rng.P(0.5)
			var name_v: String = burg["name"] if name_by_burg else Names.get_state(Names.get_culture_short(c), c)
			var form_name: String = rng.rw(form)
			form[form_name] = float(form.get(form_name, 1.0)) + 10.0
			var color: String = FmgColors.get_mixed_color(state["color"], rng)

			(state["provinces"] as Array).append(province_id)
			pack.provinces.append({
				"i": province_id,
				"state": int(state["i"]),
				"center": center,
				"burg": burg["i"],
				"name": name_v,
				"formName": form_name,
				"fullName": "%s %s" % [name_v, form_name],
				"color": color
			})
			province_ids[center] = province_id

	# expand provinces
	var queue := FlatQueue.new()
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())

	for p in pack.provinces:
		if p == null:
			continue
		province_ids[p["center"]] = p["i"]
		queue.push([int(p["center"]), int(p["i"]), int(p["state"]), 0.0], 0.0)
		cost[int(p["center"])] = 1.0

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Array = pair[0]
		var e: int = payload[0]
		var p_cost: float = payload[3]
		var province: int = payload[1]
		var state: int = payload[2]

		for neib: int in pack.c[e]:
			var land: bool = pack.h[neib] >= 20
			if not land and pack.t[neib] == 0:
				continue
			if land and pack.state[neib] != state:
				continue
			var elevation: float = 100.0
			if pack.h[neib] >= 70:
				elevation = 100.0
			elif pack.h[neib] >= 50:
				elevation = 30.0
			elif pack.h[neib] >= 20:
				elevation = 10.0
			var total_cost: float = p_cost + elevation
			if total_cost > max_growth:
				continue
			if cost[neib] == 0.0 or total_cost < cost[neib]:
				if land:
					province_ids[neib] = province
				cost[neib] = total_cost
				queue.push([neib, province, state, total_cost], total_cost)

	# justify province shapes a bit: lonely cells join the majority neighbor
	for i: int in pack.cell_count():
		if not land_or_shore(i) or province_ids[i] == 0:
			continue
		var counts := {}
		for c: int in pack.c[i]:
			var pid: int = province_ids[c]
			if pid != 0:
				counts[pid] = int(counts.get(pid, 0)) + 1
		if counts.is_empty():
			continue
		var best: int = province_ids[i]
		var best_count: int = 0
		for pid: int in counts:
			if int(counts[pid]) > best_count:
				best_count = int(counts[pid])
				best = pid
		if best != province_ids[i] and best_count > 4:
			province_ids[i] = best

	pack.province = province_ids

	# poles for labels
	var dist := PackedInt32Array()
	dist.resize(pack.cell_count())
	dist.fill(-1)
	var queue_cells: Array = []
	for i: int in pack.cell_count():
		if province_ids[i] == 0 or pack.h[i] < 20:
			continue
		var is_border: bool = false
		for c: int in pack.c[i]:
			if pack.h[c] < 20 or province_ids[c] != province_ids[i]:
				is_border = true
				break
		if is_border:
			dist[i] = 0
			queue_cells.append(i)
	var head: int = 0
	while head < queue_cells.size():
		var cell: int = queue_cells[head]
		head += 1
		for c: int in pack.c[cell]:
			if dist[c] != -1 or pack.h[c] < 20 or province_ids[c] != province_ids[cell]:
				continue
			dist[c] = dist[cell] + 1
			queue_cells.append(c)
	var best_depth := {}
	for p in pack.provinces:
		if p == null:
			continue
		p["pole"] = pack.points[p["center"]]
	for i: int in pack.cell_count():
		if province_ids[i] == 0 or dist[i] < 0:
			continue
		var pid: int = province_ids[i]
		if not best_depth.has(pid) or dist[i] > int(best_depth[pid]):
			best_depth[pid] = dist[i]
			pack.provinces[pid]["pole"] = pack.points[i]


func land_or_shore(i: int) -> bool:
	return pack.h[i] >= 20 or pack.t[i] != 0
