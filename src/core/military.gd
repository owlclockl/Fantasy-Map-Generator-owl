class_name FmgMilitary
extends RefCounted
## Armies. Port of military-generator.ts: alert rate from expansionism and
## diplomacy, rural and urban platoons with state/culture/religion/landmass
## penalties, spatial merging of platoons into regiments and fleets.

const POP_SCALE: float = 1000.0 # options.map.units.population.scale default

const UNITS := [
	{"name": "infantry", "rural": 0.25, "urban": 0.2, "crew": 1, "power": 1, "type": "melee", "separate": 0},
	{"name": "archers", "rural": 0.12, "urban": 0.2, "crew": 1, "power": 1, "type": "ranged", "separate": 0},
	{"name": "cavalry", "rural": 0.12, "urban": 0.03, "crew": 2, "power": 2, "type": "mounted", "separate": 0},
	{"name": "artillery", "rural": 0.0, "urban": 0.03, "crew": 8, "power": 12, "type": "machinery", "separate": 0},
	{"name": "fleet", "rural": 0.0, "urban": 0.015, "crew": 100, "power": 50, "type": "naval", "separate": 1}
]

const STATE_MODIFIER := {
	"melee": {"Nomadic": 0.5, "Highland": 1.2, "Lake": 1.0, "Naval": 0.7, "Hunting": 1.2, "River": 1.1},
	"ranged": {"Nomadic": 0.9, "Highland": 1.3, "Lake": 1.0, "Naval": 0.8, "Hunting": 2.0, "River": 0.8},
	"mounted": {"Nomadic": 2.3, "Highland": 0.6, "Lake": 0.7, "Naval": 0.3, "Hunting": 0.7, "River": 0.8},
	"machinery": {"Nomadic": 0.8, "Highland": 1.4, "Lake": 1.1, "Naval": 1.4, "Hunting": 0.4, "River": 1.1},
	"naval": {"Nomadic": 0.5, "Highland": 0.5, "Lake": 1.2, "Naval": 1.8, "Hunting": 0.7, "River": 1.2}
}

const CELL_TYPE_MODIFIER := {
	"nomadic": {"melee": 0.2, "ranged": 0.5, "mounted": 3.0, "machinery": 0.4, "naval": 0.3},
	"wetland": {"melee": 0.8, "ranged": 2.0, "mounted": 0.3, "machinery": 1.2, "naval": 1.0},
	"highland": {"melee": 1.2, "ranged": 1.6, "mounted": 0.3, "machinery": 3.0, "naval": 1.0}
}

const BURG_TYPE_MODIFIER := {
	"nomadic": {"melee": 0.3, "ranged": 0.8, "mounted": 3.0, "machinery": 0.4, "naval": 1.0},
	"wetland": {"melee": 1.0, "ranged": 1.6, "mounted": 0.2, "machinery": 1.2, "naval": 1.0},
	"highland": {"melee": 1.2, "ranged": 2.0, "mounted": 0.3, "machinery": 3.0, "naval": 1.0}
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	var states: Array = pack.states
	var n_states: int = states.size()
	var valid: Array = []
	for s_idx: int in range(1, n_states):
		if states[s_idx] != null and int(states[s_idx].get("i", 0)) > 0:
			valid.append(s_idx)
	if valid.is_empty():
		return

	var expansion_sum: float = 0.0
	var area_sum: float = 0.0
	var state_areas := PackedFloat32Array()
	state_areas.resize(n_states)
	for i: int in pack.cell_count():
		if pack.h[i] >= 20 and pack.state[i] > 0 and pack.state[i] < n_states:
			state_areas[pack.state[i]] += pack.area[i] if pack.area.size() > i else 1.0
	for s_idx: int in valid:
		expansion_sum += float(states[s_idx].get("expansionism", 1.0))
		area_sum += state_areas[s_idx]

	# alert rate + state-level unit modifiers
	var temp_mods := {} # state id -> {unit name: modifier}
	for s_idx: int in valid:
		var s: Dictionary = states[s_idx]
		var expansion_rate: float
		if expansion_sum > 0.0 and area_sum > 0.0 and state_areas[s_idx] > 0.0:
			expansion_rate = float(s.get("expansionism", 1.0)) / expansion_sum / (state_areas[s_idx] / area_sum)
		else:
			expansion_rate = 1.0
		expansion_rate = FmgRng.minmax(expansion_rate, 0.25, 4.0)

		var diplomacy: Array = s.get("diplomacy", [])
		var diplomacy_rate: float = 0.1
		if diplomacy.has("Enemy"):
			diplomacy_rate = 1.0
		elif diplomacy.has("Rival"):
			diplomacy_rate = 0.8
		elif diplomacy.has("Suspicion"):
			diplomacy_rate = 0.5

		var neighbors_rate: float = 0.5
		for neib: Variant in s.get("neighbors", []):
			var neib_id: int = int(neib)
			if neib_id <= 0 or neib_id >= n_states or states[neib_id] == null:
				continue
			var neib_diplomacy: Array = states[neib_id].get("diplomacy", [])
			var rel: String = neib_diplomacy[int(s["i"])] if int(s["i"]) < neib_diplomacy.size() else "Suspicion"
			neighbors_rate += FmgDiplomacy.RELATION_RATE.get(rel, 0.0)
		neighbors_rate = FmgRng.minmax(neighbors_rate, 0.3, 3.0)

		s["alert"] = FmgRng.minmax(FmgRng.rn(expansion_rate * diplomacy_rate * neighbors_rate, 2), 0.1, 5.0)
		var alert: float = float(s["alert"])

		var mods := {}
		for unit: Dictionary in UNITS:
			var type_mods: Dictionary = STATE_MODIFIER.get(unit["type"], {})
			var modifier: float = float(type_mods.get(s.get("type", ""), 1.0))
			if unit["type"] == "mounted" and str(s.get("formName", s.get("form", ""))).contains("Horde"):
				modifier *= 2.0
			elif unit["type"] == "naval" and s.get("form", "") == "Republic":
				modifier *= 1.2
			mods[unit["name"]] = modifier * alert
		temp_mods[s_idx] = mods

	var platoons := {} # state id -> Array of platoon dicts
	for s_idx: int in valid:
		platoons[s_idx] = []

	# rural cells
	for i: int in pack.cell_count():
		if pack.pop[i] <= 0.0:
			continue
		var state: int = pack.state[i]
		if state <= 0 or state >= n_states or states[state] == null:
			continue
		if not platoons.has(state):
			continue
		var state_obj: Dictionary = states[state]

		var modifier: float = float(pack.pop[i]) / 100.0 # basic rural army in percentages
		if pack.culture[i] != int(state_obj.get("culture", 0)):
			modifier = modifier / 1.2 if state_obj.get("form", "") == "Union" else modifier / 2.0
		if int(state_obj.get("center", 0)) < pack.religion.size() \
				and pack.religion[i] != pack.religion[int(state_obj["center"])]:
			modifier = modifier / 2.2 if state_obj.get("form", "") == "Theocracy" else modifier / 1.4
		if pack.f[i] != pack.f[int(state_obj.get("center", i))]:
			modifier = modifier / 1.2 if state_obj.get("type", "") == "Naval" else modifier / 1.8
		var ctype: String = _cell_type(i)
		var mods: Dictionary = temp_mods[state]

		for unit: Dictionary in UNITS:
			var perc: float = float(unit["rural"])
			if perc <= 0.0 or float(mods.get(unit["name"], 0.0)) <= 0.0:
				continue
			if unit["type"] == "naval" and pack.haven[i] == 0:
				continue # only near-ocean cells create naval units
			var cell_mod: float = 1.0
			if ctype != "generic":
				cell_mod = float((CELL_TYPE_MODIFIER[ctype] as Dictionary).get(unit["type"], 1.0))
			var army: float = modifier * perc * cell_mod
			var total: int = int(FmgRng.rn(army * float(mods[unit["name"]]) * POP_SCALE))
			if total == 0:
				continue
			var pos: Vector2 = pack.points[i]
			var naval: int = 0
			if unit["type"] == "naval":
				pos = pack.points[pack.haven[i]]
				naval = 1
			platoons[state].append({
				"cell": i, "a": total, "t": total, "x": pos.x, "y": pos.y,
				"u": unit["name"], "n": naval, "s": int(unit["separate"]), "type": unit["type"]
			})

	# burgs
	for b in pack.burgs:
		if b == null or int(b.get("i", 0)) == 0:
			continue
		var state: int = int(b.get("state", 0))
		var population: float = float(b.get("population", 0.0))
		if state <= 0 or state >= n_states or states[state] == null or population <= 0.0:
			continue
		if not platoons.has(state):
			continue
		var state_obj: Dictionary = states[state]
		var cell: int = int(b["cell"])

		var m: float = population / 100.0 # basic urban army in percentages
		if int(b.get("capital", 0)) == 1:
			m *= 1.2 # capital has household troops
		if int(b.get("culture", 0)) != int(state_obj.get("culture", 0)):
			m = m / 1.2 if state_obj.get("form", "") == "Union" else m / 2.0
		if int(state_obj.get("center", 0)) < pack.religion.size() \
				and pack.religion[cell] != pack.religion[int(state_obj["center"])]:
			m = m / 2.2 if state_obj.get("form", "") == "Theocracy" else m / 1.4
		if pack.f[cell] != pack.f[int(state_obj.get("center", cell))]:
			m = m / 1.2 if state_obj.get("type", "") == "Naval" else m / 1.8
		var ctype: String = _cell_type(cell)
		var mods: Dictionary = temp_mods[state]

		for unit: Dictionary in UNITS:
			var perc: float = float(unit["urban"])
			if perc <= 0.0 or float(mods.get(unit["name"], 0.0)) <= 0.0:
				continue
			if unit["type"] == "naval" and (int(b.get("port", 0)) == 0 or pack.haven[cell] == 0):
				continue # only ports create naval units
			var burg_mod: float = 1.0
			if ctype != "generic":
				burg_mod = float((BURG_TYPE_MODIFIER[ctype] as Dictionary).get(unit["type"], 1.0))
			var army: float = m * perc * burg_mod
			var total: int = int(FmgRng.rn(army * float(mods[unit["name"]]) * POP_SCALE))
			if total == 0:
				continue
			var pos: Vector2 = pack.points[cell]
			var naval: int = 0
			if unit["type"] == "naval":
				pos = pack.points[pack.haven[cell]]
				naval = 1
			platoons[state].append({
				"cell": cell, "a": total, "t": total, "x": pos.x, "y": pos.y,
				"u": unit["name"], "n": naval, "s": int(unit["separate"]), "type": unit["type"]
			})

	# merge platoons into regiments
	for s_idx: int in valid:
		states[s_idx]["military"] = _create_regiments(platoons[s_idx], states[s_idx])


func _cell_type(cell_id: int) -> String:
	var biome: int = pack.biome[cell_id]
	if biome >= 1 and biome <= 4:
		return "nomadic"
	if biome == 7 or biome == 8 or biome == 9 or biome == 12:
		return "wetland"
	if pack.h[cell_id] >= 70:
		return "highland"
	return "generic"


## Merge nearby platoons (original quadtree merge: sorted by army size,
## overlap within 20 or search radius by missing troops).
func _create_regiments(nodes: Array, s: Dictionary) -> Array:
	if nodes.is_empty():
		return []
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["a"]) < int(b["a"]))
	var expected: float = 3.0 * POP_SCALE

	for node_idx: int in nodes.size():
		var node: Dictionary = nodes[node_idx]
		if int(node["t"]) == 0:
			continue
		# overlap within 20
		var merged: bool = false
		for other_idx: int in nodes.size():
			if other_idx == node_idx:
				continue
			var other: Dictionary = nodes[other_idx]
			if int(other["t"]) == 0:
				continue
			var dx: float = float(node["x"]) - float(other["x"])
			var dy: float = float(node["y"]) - float(other["y"])
			if dx * dx + dy * dy <= 400.0 and _mergeable(node, other):
				_merge(node, other)
				merged = true
				break
		if merged:
			continue
		if int(node["t"]) > int(expected):
			continue
		var radius: float = (expected - float(node["t"])) / (40.0 if int(node["s"]) == 1 else 20.0)
		for other_idx: int in nodes.size():
			if other_idx == node_idx:
				continue
			var other: Dictionary = nodes[other_idx]
			if int(other["t"]) == 0 or int(other["t"]) >= int(expected):
				continue
			var dx: float = float(node["x"]) - float(other["x"])
			var dy: float = float(node["y"]) - float(other["y"])
			if dx * dx + dy * dy <= radius * radius and _mergeable(node, other):
				_merge(node, other)
				break

	# parse regiments
	var alive: Array = []
	for node: Variant in nodes:
		if int((node as Dictionary)["t"]) > 0:
			alive.append(node)
	alive.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["t"]) > int(b["t"]))

	var regiments: Array = []
	for idx: int in alive.size():
		var r: Dictionary = alive[idx]
		var u := {}
		u[r["u"]] = int(r["a"])
		for child: Variant in r.get("children", []):
			var c: Dictionary = child
			u[c["u"]] = int(u.get(c["u"], 0)) + int(c["a"])
		regiments.append({
			"i": idx, "a": int(r["t"]), "cell": int(r["cell"]),
			"x": float(r["x"]), "y": float(r["y"]),
			"u": u, "n": int(r["n"]), "name": "", "state": int(s["i"])
		})

	for reg: Variant in regiments:
		_name_regiment(reg, regiments)
	return regiments


func _mergeable(n0: Dictionary, n1: Dictionary) -> bool:
	return (int(n0["s"]) == 0 and int(n1["s"]) == 0) or n0["u"] == n1["u"]


func _merge(n0: Dictionary, n1: Dictionary) -> void:
	var children: Array = n1.get("children", [])
	children.append(n0)
	for child: Variant in n0.get("children", []):
		children.append(child)
	n1["children"] = children
	n1["t"] = int(n1["t"]) + int(n0["t"])
	n0["t"] = 0


func _name_regiment(reg: Dictionary, regiments: Array) -> void:
	var cell: int = int(reg["cell"])
	var proper: String = ""
	if pack.province[cell] > 0 and pack.province[cell] < pack.provinces.size():
		proper = pack.provinces[pack.province[cell]].get("name", "")
	elif pack.burg[cell] > 0 and pack.burg[cell] < pack.burgs.size() and pack.burgs[pack.burg[cell]] != null:
		proper = pack.burgs[pack.burg[cell]].get("name", "")
	var same_kind: int = 0
	for other: Variant in regiments:
		if (other as Dictionary) == reg:
			break
		if int((other as Dictionary)["n"]) == int(reg["n"]):
			same_kind += 1
	var form: String = "Fleet" if int(reg["n"]) == 1 else "Regiment"
	var number: String = _nth(same_kind + 1)
	reg["name"] = "%s (%s) %s" % [number, proper, form] if proper != "" else "%s %s" % [number, form]


static func _nth(n: int) -> String:
	var mod100: int = n % 100
	if mod100 >= 11 and mod100 <= 13:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n
