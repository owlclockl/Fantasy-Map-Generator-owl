class_name FmgRoutes
extends RefCounted
## Roads, trails and sea routes. Port of routes-generator.ts: Urquhart graphs
## over burgs per landmass (Delaunay minus each triangle's longest edge),
## Dijkstra path-finding with land/water costs, route naming. River-run
## meandering is skipped — routes follow cell anchors.

const MIN_NAVIGABLE_FLUX: float = 100.0
const MIN_PASSABLE_SEA_TEMP: int = -4
const RIVER_TYPE_MODIFIER: float = 1.5
const ROUTES_SHARP_ANGLE: float = 135.0
const ROUTES_VERY_SHARP_ANGLE: float = 115.0

const ROUTE_TYPE_MODIFIERS := {"-1": 1.0, "-2": 1.8, "-3": 4.0, "-4": 6.0, "default": 8.0}

const NAME_MODELS := {
	"roads": {"burg_suffix": 3, "prefix_suffix": 6, "the_descriptor_prefix_suffix": 2, "the_descriptor_burg_suffix": 1},
	"trails": {"burg_suffix": 8, "prefix_suffix": 1, "the_descriptor_burg_suffix": 1},
	"searoutes": {"burg_suffix": 4, "prefix_suffix": 2, "the_descriptor_prefix_suffix": 1}
}

const NAME_SUFFIXES := {
	"roads": {"Road": 7, "Route": 3, "Way": 2, "Highway": 1},
	"trails": {"Trail": 4, "Path": 1, "Track": 1, "Pass": 1},
	"searoutes": {"Route": 5, "Lane": 2, "Passage": 1, "Water Way": 1}
}

const NAME_PREFIXES := [
	"King", "Queen", "Military", "Old", "New", "Ancient", "Royal", "Imperial", "Great", "Grand",
	"High", "Silver", "Dragon", "Shadow", "Star", "Mystic", "Whisper", "Eagle", "Golden", "Crystal",
	"Enchanted", "Frost", "Moon", "Sun", "Thunder", "Phoenix", "Sapphire", "Celestial", "Wandering", "Echo",
	"Twilight", "Crimson", "Serpent", "Iron", "Forest", "Flower", "Whispering", "Eternal", "Frozen", "Rain",
	"Luminous", "Stardust", "Arcane", "Glimmering", "Jade", "Ember", "Azure", "Gilded", "Divine", "Shadowed",
	"Cursed", "Moonlit", "Sable", "Everlasting", "Amber", "Nightshade", "Wraith", "Scarlet", "Platinum", "Whirlwind",
	"Obsidian", "Ethereal", "Ghost", "Spike", "Dusk", "Raven", "Spectral", "Burning", "Verdant", "Copper",
	"Velvet", "Falcon", "Enigma", "Glowing", "Silvered", "Molten", "Radiant", "Astral", "Wild", "Flame",
	"Amethyst", "Aurora", "Shadowy", "Solar", "Lunar", "Whisperwind", "Fading", "Titan", "Dawn", "Crystalline",
	"Jeweled", "Sylvan", "Twisted", "Ebon", "Thorn", "Cerulean", "Halcyon", "Infernal", "Storm", "Eldritch",
	"Tranquil", "Paved"
]

const NAME_DESCRIPTORS := [
	"Great", "Shrouded", "Sacred", "Fabled", "Frosty", "Winding", "Echoing", "Serpentine",
	"Breezy", "Misty", "Rustic", "Silent", "Cobbled", "Cracked", "Shaky", "Obscure"
]

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph

var connections := {} # "a-b" -> true for already-routed cell pairs
var river_edges := {} # cell -> {neib: true} along navigable rivers
var route_links := {} # same as connections, final (for zones/markets)


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	connections = {}
	route_links = {}
	_build_river_edges()
	pack.routes = []

	var grouped: Dictionary = _sort_burgs_by_feature()
	var main_roads: Array = _generate_group(grouped["capitals"], false, "roads")
	var trails: Array = _generate_group(grouped["burgs"], false, "trails")
	var sea_routes: Array = _generate_group(grouped["ports"], true, "searoutes")

	var route_id: int = 0
	for list: Array in [main_roads, trails, sea_routes]:
		for route: Variant in _merge_routes(list):
			var r: Dictionary = route
			if r.get("merged", false):
				continue
			r["i"] = route_id
			route_id += 1
			r["points"] = _get_points(r["cells"])
			r["name"] = _generate_name(r)
			pack.routes.append(r)

	# per-cell adjacency (mirrors pack.cells.routes) for markers/zones
	pack.cell_routes = {}
	for route: Variant in pack.routes:
		var rid: int = int((route as Dictionary)["i"])
		var cells_arr: Array = (route as Dictionary)["cells"]
		for i: int in cells_arr.size() - 1:
			var a: int = int(cells_arr[i])
			var b: int = int(cells_arr[i + 1])
			if not pack.cell_routes.has(a):
				pack.cell_routes[a] = {}
			if not pack.cell_routes.has(b):
				pack.cell_routes[b] = {}
			pack.cell_routes[a][b] = rid
			pack.cell_routes[b][a] = rid

	# cell -> cell adjacency lookup for other generators (disease spread etc.)
	for route: Variant in pack.routes:
		var cells_arr: Array = (route as Dictionary)["cells"]
		for i: int in cells_arr.size() - 1:
			route_links["%d-%d" % [cells_arr[i], cells_arr[i + 1]]] = true
			route_links["%d-%d" % [cells_arr[i + 1], cells_arr[i]]] = true
	pack.route_links = route_links


## is the cell touched by any route (markers isConnected)
func is_connected(cell_id: int) -> bool:
	return pack.cell_routes.has(cell_id) and not (pack.cell_routes[cell_id] as Dictionary).is_empty()


## is the cell on a "roads" group route (markers hasRoad)
func has_road(cell_id: int) -> bool:
	if not pack.cell_routes.has(cell_id):
		return false
	for rid: Variant in (pack.cell_routes[cell_id] as Dictionary).values():
		var route: Dictionary = _route_by_id(int(rid))
		if not route.is_empty() and route.get("group", "") == "roads":
			return true
	return false


## 4+ route neighbours, or 3+ of them on roads (markers isCrossroad)
func is_crossroad(cell_id: int) -> bool:
	if not pack.cell_routes.has(cell_id):
		return false
	var conns: Dictionary = pack.cell_routes[cell_id]
	if conns.size() > 3:
		return true
	var road_connections: int = 0
	for rid: Variant in conns.values():
		var route: Dictionary = _route_by_id(int(rid))
		if not route.is_empty() and route.get("group", "") == "roads":
			road_connections += 1
	return road_connections > 2


func _route_by_id(rid: int) -> Dictionary:
	for route: Variant in pack.routes:
		if int((route as Dictionary).get("i", -1)) == rid:
			return route
	return {}


## cost of stepping cell->neib along an existing route, else 100 (zones)
func route_step_cost(from: int, to: int) -> float:
	if pack.cell_routes.has(from) and (pack.cell_routes[from] as Dictionary).has(to):
		return 5.0
	return 100.0


func has_route_link(a: int, b: int) -> bool:
	return route_links.has("%d-%d" % [a, b])


func _build_river_edges() -> void:
	river_edges = {}
	for river in pack.rivers:
		if river == null:
			continue
		var cells_arr: Array = river.get("cells", [])
		if cells_arr.size() < 2:
			continue
		for i: int in cells_arr.size() - 1:
			var a: int = int(cells_arr[i])
			var b: int = int(cells_arr[i + 1])
			if a < 0 or b < 0 or a >= pack.cell_count() or b >= pack.cell_count():
				continue
			if pack.fl[a] < MIN_NAVIGABLE_FLUX and pack.fl[b] < MIN_NAVIGABLE_FLUX:
				continue
			if not river_edges.has(a):
				river_edges[a] = {}
			if not river_edges.has(b):
				river_edges[b] = {}
			river_edges[a][b] = true
			river_edges[b][a] = true


## group burgs by feature (all burgs / capitals / ports by water feature)
func _sort_burgs_by_feature() -> Dictionary:
	var burgs_by_feature := {}
	var capitals_by_feature := {}
	var ports_by_feature := {}
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		var feature: int = pack.f[int(burg["cell"])]
		if feature <= 0:
			continue
		if not burgs_by_feature.has(feature):
			burgs_by_feature[feature] = []
		burgs_by_feature[feature].append(burg)
		if int(burg.get("capital", 0)) == 1:
			if not capitals_by_feature.has(feature):
				capitals_by_feature[feature] = []
			capitals_by_feature[feature].append(burg)
		if int(burg.get("port", 0)) != 0:
			var port_feature: int = int(burg["port"])
			if not ports_by_feature.has(port_feature):
				ports_by_feature[port_feature] = []
			ports_by_feature[port_feature].append(burg)
	return {"burgs": burgs_by_feature, "capitals": capitals_by_feature, "ports": ports_by_feature}


func _generate_group(by_feature: Dictionary, is_water: bool, group: String) -> Array:
	var out: Array = []
	for feature: Variant in by_feature:
		var feature_burgs: Array = by_feature[feature]
		var points := PackedVector2Array()
		for burg: Variant in feature_burgs:
			points.append(Vector2((burg as Dictionary)["x"], (burg as Dictionary)["y"]))
		var edges: Array = _urquhart_edges(points)
		for edge: Variant in edges:
			var from_burg: Dictionary = feature_burgs[edge[0]]
			var to_burg: Dictionary = feature_burgs[edge[1]]
			var start: int = int(from_burg["cell"])
			var exit: int = int(to_burg["cell"])
			if start == exit:
				continue
			var path_cells: Array = _find_path(start, exit, is_water)
			if path_cells.is_empty():
				continue
			for segment: Variant in _get_route_segments(path_cells):
				var seg: Array = segment
				if seg.size() < 2:
					continue
				_add_connections(seg)
				out.append({"feature": int(feature), "cells": seg, "group": group})
	return out


## Urquhart graph: Delaunay triangulation with each triangle's longest edge
## removed (upstream calculateUrquhartEdges).
func _urquhart_edges(points: PackedVector2Array) -> Array:
	if points.size() < 2:
		return []
	if points.size() == 2:
		return [[0, 1]]
	var del := Delaunator.from_points(points)
	if del == null:
		return []
	var triangles: PackedInt32Array = del.triangles
	var halfedges: PackedInt32Array = del.halfedges
	var n: int = triangles.size()
	var removed := PackedByteArray()
	removed.resize(n)

	for e: int in range(0, n, 3):
		var p0: int = triangles[e]
		var p1: int = triangles[e + 1]
		var p2: int = triangles[e + 2]
		var p01: float = points[p0].distance_squared_to(points[p1])
		var p12: float = points[p1].distance_squared_to(points[p2])
		var p20: float = points[p2].distance_squared_to(points[p0])
		var idx: int
		if p20 > p01 and p20 > p12:
			idx = maxi(e + 2, halfedges[e + 2])
		elif p12 > p01 and p12 > p20:
			idx = maxi(e + 1, halfedges[e + 1])
		else:
			idx = maxi(e, halfedges[e])
		if idx >= 0 and idx < n:
			removed[idx] = 1

	var edges: Array = []
	for e: int in n:
		if e > halfedges[e] and removed[e] == 0:
			var t0: int = triangles[e]
			var t1: int = triangles[e - 2] if e % 3 == 2 else triangles[e + 1]
			edges.append([t0, t1])
	return edges


func _add_connections(segment: Array) -> void:
	for i: int in segment.size() - 1:
		connections["%d-%d" % [segment[i], segment[i + 1]]] = true
		connections["%d-%d" % [segment[i + 1], segment[i]]] = true


## Dijkstra over pack cells with land or water costs; returns the cell chain.
func _find_path(start: int, exit: int, is_water: bool) -> Array:
	if start == exit:
		return []
	var from := PackedInt32Array()
	from.resize(pack.cell_count())
	from.fill(-1)
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())
	for i: int in pack.cell_count():
		cost[i] = INF
	var queue := FlatQueue.new()
	queue.push(start, 0.0)
	cost[start] = 0.0

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var current: int = pair[0]
		var current_cost: float = pair[1]
		if current_cost > cost[current]:
			continue
		for next: int in pack.c[current]:
			if next == exit:
				if _exit_allowed(current, exit, is_water):
					from[next] = current
					return _restore_path(next, start, from)
				continue
			var next_cost: float = _get_cost(current, next, is_water)
			if is_inf(next_cost):
				continue
			var total_cost: float = current_cost + next_cost
			if total_cost >= cost[next]:
				continue
			from[next] = current
			cost[next] = total_cost
			queue.push(next, total_cost)
	return []


func _restore_path(end: int, start: int, from: PackedInt32Array) -> Array:
	var path: Array = [end]
	var current: int = end
	var guard: int = 0
	while current != start and guard < pack.cell_count() + 1:
		current = from[current]
		if current < 0:
			return []
		path.append(current)
		guard += 1
	path.reverse()
	return path


## Water routes may only reach the destination through a legal approach
func _exit_allowed(current: int, exit: int, is_water: bool) -> bool:
	if not is_water:
		return true
	if river_edges.has(current) and (river_edges[current] as Dictionary).has(exit):
		return true # river port: approach along the river course
	if pack.h[current] >= 20:
		return false # coastal port must be approached over water
	var haven: int = pack.haven[exit]
	return haven == 0 or current == haven


func _get_cost(current: int, next: int, is_water: bool) -> float:
	if is_water:
		return _water_cost(current, next)
	return _land_cost(current, next)


func _land_cost(_current: int, next: int) -> float:
	if pack.h[next] < 20:
		return INF # ignore water cells
	var habitability: float = float(pack.biomes[pack.biome[next]].get("habitability", 0))
	if habitability == 0.0:
		return INF # inhabitable cells are not passable (e.g. glacier)
	var distance_cost: float = pack.points[_current].distance_squared_to(pack.points[next])
	var habitability_modifier: float = 1.0 + maxf(100.0 - habitability, 0.0) / 1000.0
	var height_modifier: float = 1.0 + maxf(float(pack.h[next]) - 25.0, 25.0) / 25.0
	var connection_modifier: float = 0.5 if connections.has("%d-%d" % [_current, next]) else 1.0
	var burg_modifier: float = 1.0 if pack.burg[next] != 0 else 3.0
	return distance_cost * habitability_modifier * height_modifier * connection_modifier * burg_modifier


func _water_cost(current: int, next: int) -> float:
	var connection_modifier: float = 0.5 if connections.has("%d-%d" % [current, next]) else 1.0
	if pack.h[next] >= 20:
		# land cell: only navigable via a river along its recorded course
		if pack.r[next] == 0 or pack.fl[next] < MIN_NAVIGABLE_FLUX:
			return INF
		if not river_edges.has(current) or not (river_edges[current] as Dictionary).has(next):
			return INF
		return pack.points[current].distance_squared_to(pack.points[next]) * RIVER_TYPE_MODIFIER * connection_modifier

	if pack.h[current] >= 20:
		# leaving a land cell into water
		if pack.r[current] != 0:
			if not river_edges.has(current) or not (river_edges[current] as Dictionary).has(next):
				return INF
		else:
			var haven: int = pack.haven[current]
			if haven != 0 and haven != next:
				return INF
	if grid.temp[pack.g[next]] < MIN_PASSABLE_SEA_TEMP:
		return INF

	var distance_cost: float = pack.points[current].distance_squared_to(pack.points[next])
	var type_modifier: float = float(ROUTE_TYPE_MODIFIERS.get(str(pack.t[next]), ROUTE_TYPE_MODIFIERS["default"]))
	return distance_cost * type_modifier * connection_modifier


## Split a found path into new segments where it crosses existing routes
func _get_route_segments(path_cells: Array) -> Array:
	var segments: Array = []
	var segment: Array = []
	for i: int in path_cells.size():
		var cell_id: int = path_cells[i]
		var next_cell: int = path_cells[i + 1] if i + 1 < path_cells.size() else -1
		var is_connected: bool = false
		if next_cell >= 0:
			is_connected = connections.has("%d-%d" % [cell_id, next_cell]) \
				or connections.has("%d-%d" % [next_cell, cell_id])
		if is_connected:
			if not segment.is_empty():
				segment.append(cell_id)
				segments.append(segment)
				segment = []
			continue
		segment.append(cell_id)
	if segment.size() > 1:
		segments.append(segment)
	return segments


## Merge routes end-to-start so connected chains become single routes
func _merge_routes(routes: Array) -> Array:
	var merged_count: int = 0
	for i: int in routes.size():
		var this_route: Dictionary = routes[i]
		if this_route.get("merged", false):
			continue
		var this_cells: Array = this_route["cells"]
		for j: int in range(i + 1, routes.size()):
			var next_route: Dictionary = routes[j]
			if next_route.get("merged", false):
				continue
			var next_cells: Array = next_route["cells"]
			if next_cells[0] == this_cells[this_cells.size() - 1]:
				merged_count += 1
				this_route["cells"] = this_cells + next_cells.slice(1)
				next_route["merged"] = true
	if merged_count > 1:
		return _merge_routes(routes)
	return routes


## Route points: cell anchors with sharp-angle resolution (roads/trails),
## burg position at burg cells.
func _get_points(cells_arr: Array) -> PackedVector2Array:
	var data: Array = []
	for cell_id: Variant in cells_arr:
		data.append(_cell_anchor(int(cell_id)))
	for i: int in range(1, data.size() - 1):
		var cell_id: int = cells_arr[i]
		if pack.burg[cell_id] != 0:
			continue
		var prev_pt: Vector2 = data[i - 1]
		var curr_pt: Vector2 = data[i]
		var next_pt: Vector2 = data[i + 1]
		var da: Vector2 = prev_pt - curr_pt
		var db: Vector2 = next_pt - curr_pt
		var angle: float = absf(rad_to_deg(atan2(da.x * db.y - da.y * db.x, da.x * db.x + da.y * db.y)))
		if angle < ROUTES_SHARP_ANGLE:
			var middle: Vector2 = (prev_pt + next_pt) / 2.0
			var new_pt: Vector2
			if angle < ROUTES_VERY_SHARP_ANGLE:
				new_pt = (curr_pt + middle * 2.0) / 3.0
			else:
				new_pt = (curr_pt + middle) / 2.0
			data[i] = new_pt
	var out := PackedVector2Array()
	for pt: Variant in data:
		out.append(pt)
	return out


func _cell_anchor(cell_id: int) -> Vector2:
	var burg_id: int = pack.burg[cell_id]
	if burg_id > 0 and burg_id < pack.burgs.size() and pack.burgs[burg_id] != null:
		return Vector2(pack.burgs[burg_id]["x"], pack.burgs[burg_id]["y"])
	return pack.points[cell_id]


func _generate_name(route: Dictionary) -> String:
	var group: String = route["group"]
	var model: String = rng.rw(NAME_MODELS[group])
	var suffix: String = rng.rw(NAME_SUFFIXES[group])
	var cells_arr: Array = route["cells"]
	if model.contains("burg_suffix"):
		var burg_name: String = ""
		for cell_id: Variant in cells_arr:
			var burg_id: int = pack.burg[int(cell_id)]
			if burg_id > 0 and burg_id < pack.burgs.size() and pack.burgs[burg_id] != null:
				burg_name = pack.burgs[burg_id]["name"]
				break
		if burg_name == "" and not cells_arr.is_empty():
			var culture: int = pack.culture[int(cells_arr[0])]
			burg_name = Names.get_culture_short(culture)
		if model == "the_descriptor_burg_suffix":
			return "The %s %s %s" % [rng.ra(NAME_DESCRIPTORS), burg_name, suffix]
		return "%s %s" % [burg_name, suffix]
	if model == "the_descriptor_prefix_suffix":
		return "The %s %s %s" % [rng.ra(NAME_DESCRIPTORS), rng.ra(NAME_PREFIXES), suffix]
	return "%s %s" % [rng.ra(NAME_PREFIXES), suffix]
