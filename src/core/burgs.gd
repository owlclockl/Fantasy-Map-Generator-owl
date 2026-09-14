class_name FmgBurgs
extends RefCounted
## Burgs: capitals and towns, ports, population. Port of burgs-generator.ts
## (routes-dependent parts simplified).

const SEA_LEVEL: int = 20


var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var states_limit: int = 18
var burgs_limit: int = 1000 # -1 = auto


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	pack.burgs = [null]
	pack.burg = PackedInt32Array()
	pack.burg.resize(pack.cell_count())

	var populated_cells := PackedInt32Array()
	for i: int in pack.cell_count():
		if pack.s[i] > 0 and pack.culture[i] != 0:
			populated_cells.append(i)
	if populated_cells.is_empty():
		push_warning("There is no populated cells with culture assigned. Cannot generate burgs")
		return

	_generate_capitals(populated_cells)
	_generate_towns(populated_cells)
	assign_ports()


func _burgs_number() -> int:
	if burgs_limit < 0:
		return FmgRng.rn(populated_size_cache / 5.0 / pow(float(grid.points.size()) / 10000.0, 0.8))
	return mini(burgs_limit, populated_size_cache)

var populated_size_cache: int = 0


func _generate_capitals(populated_cells: PackedInt32Array) -> void:
	populated_size_cache = populated_cells.size()
	var score := PackedFloat32Array()
	score.resize(pack.cell_count())
	for i: int in populated_cells.size():
		var cell: int = populated_cells[i]
		score[cell] = float(pack.s[cell]) * (0.5 + rng.random() * 0.5)
	var sorted := Array(populated_cells)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return score[a] > score[b])

	var capitals_number: int = states_limit
	if populated_cells.size() < capitals_number * 10:
		capitals_number = int(floor(float(populated_cells.size()) / 10.0))

	var spacing: float = (pack.width + pack.height) / 2.0 / float(capitals_number)
	var placed: Array = [] # PackedVector2Array of existing burg positions

	while pack.burgs.size() <= capitals_number:
		var placed_any: bool = false
		for i: int in sorted.size():
			if pack.burgs.size() > capitals_number:
				break
			var cell: int = sorted[i]
			var p := pack.points[cell]
			var too_close: bool = false
			for other: Vector2 in placed:
				if other.distance_to(p) < spacing:
					too_close = true
					break
			if too_close:
				continue
			placed.append(p)
			pack.burgs.append({
				"cell": cell, "x": p.x, "y": p.y, "i": pack.burgs.size(),
				"state": 0, "culture": pack.culture[cell], "feature": pack.f[cell], "capital": 1
			})
			placed_any = true
		if not placed_any:
			spacing /= 1.2
			if spacing < 1.0:
				break

	for b: Dictionary in pack.burgs:
		if b == null:
			continue
		var cell: int = b["cell"]
		b["state"] = b["i"]
		b["name"] = Names.get_culture_short(b["culture"])
		pack.burg[cell] = b["i"]


func _generate_towns(populated_cells: PackedInt32Array) -> void:
	var score := PackedFloat32Array()
	score.resize(pack.cell_count())
	for i: int in populated_cells.size():
		var cell: int = populated_cells[i]
		score[cell] = float(pack.s[cell]) * rng.gauss(1.0, 3.0, 0.0, 20.0, 3)
	var sorted := Array(populated_cells)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return score[a] > score[b])

	var burgs_number: int = _burgs_number()
	var spacing: float = (pack.width + pack.height) / 150.0 / (pow(float(burgs_number), 0.7) / 66.0)
	var added: int = 0
	while added < burgs_number and spacing > 1.0:
		for i: int in sorted.size():
			if added >= burgs_number:
				break
			var cell: int = sorted[i]
			if pack.burg[cell] != 0:
				continue
			var p := pack.points[cell]
			var min_spacing: float = spacing * rng.gauss(1.0, 0.3, 0.2, 2.0, 2)
			var too_close: bool = false
			for b: Dictionary in pack.burgs:
				if b == null:
					continue
				if Vector2(b["x"], b["y"]).distance_to(p) < min_spacing:
					too_close = true
					break
			if too_close:
				continue
			var burg_id: int = pack.burgs.size()
			var culture: int = pack.culture[cell]
			pack.burgs.append({
				"cell": cell, "x": p.x, "y": p.y, "i": burg_id, "state": 0,
				"culture": culture, "name": Names.get_culture(culture),
				"feature": pack.f[cell], "capital": 0
			})
			pack.burg[cell] = burg_id
			added += 1
		spacing *= 0.5


func get_type(cell_id: int, port: int = 0) -> String:
	if port != 0:
		return "Naval"
	var haven_cell: int = pack.haven[cell_id]
	if haven_cell != 0:
		var fid: int = pack.f[haven_cell]
		if fid > 0 and fid < pack.features.size():
			if pack.features[fid]["type"] == "lake":
				return "Lake"
	if pack.h[cell_id] > 60:
		return "Highland"
	if pack.r[cell_id] != 0 and pack.fl[cell_id] >= 100.0:
		return "River"

	var biome: int = pack.biome[cell_id]
	var population: float = pack.pop[cell_id]
	if pack.burg[cell_id] == 0 or population <= 5.0:
		if population < 5.0 and [1, 2, 3, 4].has(biome):
			return "Nomadic"
		if biome > 4 and biome < 10:
			return "Hunting"
	return "Generic"


## assign port feature ids and shift burgs to the harbor / river bank
func assign_ports() -> void:
	var hydrology: FmgHydrology = _hydrology
	for b: Dictionary in pack.burgs:
		if b == null:
			continue
		b.erase("port")

	var grid_temp := grid.temp
	# collect sea/lake port candidates
	var candidates: Array = []
	for b: Dictionary in pack.burgs:
		if b == null:
			continue
		var cell: int = b["cell"]
		var haven_cell: int = pack.haven[cell]
		if haven_cell == 0:
			continue
		var harbor: int = pack.harbor[cell]
		if harbor == 0:
			continue
		if grid_temp[pack.g[cell]] <= 0:
			continue
		var fid: int = pack.f[haven_cell]
		if fid <= 0 or fid >= pack.features.size():
			continue
		var feature: Dictionary = pack.features[fid]
		if feature.is_empty() or feature["cells"] <= 1:
			continue
		var subtype: String = feature.get("subtype", "freshwater")
		if subtype == "dry" or subtype == "frozen" or subtype == "lava":
			continue
		candidates.append({"burg": b, "cell": cell, "fid": fid, "harbor": harbor,
			"land": pack.f[cell], "preferred": harbor == 1 or b.get("capital", 0) == 1})

	# select ports: preferred candidates + best per landmass
	var promoted := {}
	for c: Dictionary in candidates:
		if c["preferred"]:
			promoted[c["burg"]["i"]] = c
	var by_land := {}
	for c: Dictionary in candidates:
		if not by_land.has(c["land"]):
			by_land[c["land"]] = []
		(by_land[c["land"]] as Array).append(c)
	for land_fid: int in by_land:
		var group: Array = by_land[land_fid]
		var has_promoted: bool = false
		for c: Dictionary in group:
			if promoted.has(c["burg"]["i"]):
				has_promoted = true
				break
		if has_promoted:
			continue
		var best: Dictionary = group[0]
		for c: Dictionary in group:
			var rank_c: float = -1000.0 if c["burg"].get("capital", 0) else 0.0
			rank_c += float(c["harbor"])
			var rank_b: float = -1000.0 if best["burg"].get("capital", 0) else 0.0
			rank_b += float(best["harbor"])
			if rank_c < rank_b:
				best = c
		promoted[best["burg"]["i"]] = best

	for burg_id: int in promoted:
		var c: Dictionary = promoted[burg_id]
		c["burg"]["port"] = c["fid"]
		var pos: Array = _close_to_edge_point(c["cell"], pack.haven[c["cell"]])
		c["burg"]["x"] = pos[0]
		c["burg"]["y"] = pos[1]

	# river ports
	for b: Dictionary in pack.burgs:
		if b == null or b.has("port"):
			continue
		var cell: int = b["cell"]
		if not hydrology.is_navigable(cell):
			continue
		var drain: int = hydrology.resolve_drain_feature(cell)
		if drain == 0:
			continue
		b["port"] = drain
		var shifted := _shift_to_river_bank(cell)
		b["x"] = shifted.x
		b["y"] = shifted.y


var _hydrology: FmgHydrology = null


func set_hydrology(h: FmgHydrology) -> void:
	_hydrology = h


func _close_to_edge_point(cell1: int, cell2: int) -> Array:
	var p0 := pack.points[cell1]
	var common: Array = []
	var vertices := pack.voronoi.vertices
	for vv: int in pack.v[cell1]:
		for vc: int in vertices.c[vv]:
			if vc == cell2:
				common.append(vv)
				break
	if common.size() < 2:
		return [p0.x, p0.y]
	var v1 := vertices.p[common[0]]
	var v2 := vertices.p[common[1]]
	var x_edge: float = (v1.x + v2.x) / 2.0
	var y_edge: float = (v1.y + v2.y) / 2.0
	return [FmgRng.rn(p0.x + 0.95 * (x_edge - p0.x), 2), FmgRng.rn(p0.y + 0.95 * (y_edge - p0.y), 2)]


func _shift_to_river_bank(cell_id: int) -> Vector2:
	var p := pack.points[cell_id]
	var shift: float = minf(pack.fl[cell_id] / 200.0, 0.6)
	var side: float = 1.0 if cell_id % 2 == 1 else -1.0
	# nudge perpendicular to the local river course
	var river_id: int = pack.r[cell_id]
	var tangent := Vector2.ZERO
	if river_id != 0:
		for river: Dictionary in pack.rivers:
			if river != null and river["i"] == river_id:
				var cells_path: PackedInt32Array = river["cells"]
				var idx: int = cells_path.find(cell_id)
				if idx >= 0:
					var from_p := pack.points[cells_path[maxi(idx - 1, 0)]] if idx > 0 else p
					var to_p := pack.points[cells_path[mini(idx + 1, cells_path.size() - 1)]] if idx < cells_path.size() - 1 else p
					tangent = to_p - from_p
				break
	if tangent.length_squared() < 1e-9:
		return Vector2(p.x + (shift if cell_id % 2 == 1 else -shift), p.y + (shift if river_id % 2 == 1 else -shift))
	var perp := Vector2(-tangent.y, tangent.x).normalized()
	return p + perp * shift * side


func define_population(b: Dictionary) -> void:
	var cell: int = b["cell"]
	var population: float = float(pack.s[cell]) / 5.0
	if b.get("capital", 0):
		population *= 1.5
	population *= rng.gauss(1.0, 1.0, 0.25, 4.0, 5)
	population += (float(b["i"] % 100) - float(cell % 100)) / 1000.0
	b["population"] = FmgRng.rn(maxf(population, 0.01), 3)


func define_features(b: Dictionary) -> void:
	var pop: float = b.get("population", 0.0)
	b["citadel"] = 1 if (b.get("capital", 0) or (pop > 50.0 and rng.P(0.75)) or (pop > 15.0 and rng.P(0.5)) or rng.P(0.1)) else 0
	b["walls"] = 1 if (b.get("capital", 0) or pop > 30.0 or (pop > 20.0 and rng.P(0.75)) or (pop > 10.0 and rng.P(0.5)) or rng.P(0.1)) else 0
	b["shanty"] = 1 if (pop > 60.0 or (pop > 40.0 and rng.P(0.75)) or (pop > 20.0 and b.get("walls", 0) and rng.P(0.4))) else 0
	b["temple"] = 1 if (pop > 50.0 or (pop > 35.0 and rng.P(0.75)) or (pop > 20.0 and rng.P(0.5))) else 0


func specify() -> void:
	for b: Dictionary in pack.burgs:
		if b == null or b.get("removed", false):
			continue
		define_population(b)
		b["type"] = get_type(b["cell"], int(b.get("port", 0)))
		define_features(b)
