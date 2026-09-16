class_name FmgFeatures
extends RefCounted
## Feature marking: oceans, lakes, islands + distance-from-coast field.
## Port of features.ts (markupGrid, markupPack, ocean outlines) and the
## connectVertices util from pathUtils.ts.

const SEA_LEVEL: int = 20
const DEEPER_LAND: int = 3
const LANDLOCKED: int = 2
const LAND_COAST: int = 1
const UNMARKED: int = 0
const WATER_COAST: int = -1
const DEEP_WATER: int = -2


## wave expansion of the distance field: mark neighbors of `start` distance, stepping by increment
static func markup_distance(distance_field: PackedInt32Array, neighbors: Array, start: int, increment: int, limit: int) -> void:
	var distance: int = start
	var marked: int = 1 # any positive value to enter the loop; reset on first pass
	while marked > 0 and distance != limit:
		marked = 0
		var prev_distance: int = distance - increment
		for cell_id: int in neighbors.size():
			if distance_field[cell_id] != prev_distance:
				continue
			for neighbor_id: int in neighbors[cell_id]:
				if distance_field[neighbor_id] != UNMARKED:
					continue
				distance_field[neighbor_id] = distance
				marked += 1
		distance += increment


## Connects vertices around a feature border into a chain. `same_type` is a
## Callable(cell_id) -> bool. Port of connectVertices.
static func connect_vertices(vertices: FmgVoronoi.Vertices, starting_vertex: int, same_type: Callable, checked: PackedByteArray = PackedByteArray()) -> PackedInt32Array:
	var max_iterations: int = vertices.c.size()
	var chain := PackedInt32Array()
	var next: int = starting_vertex
	var i: int = 0
	while i == 0 or next != starting_vertex:
		var previous: int = chain[chain.size() - 1] if chain.size() > 0 else -1
		var current: int = next
		chain.append(current)

		var neib_cells: PackedInt32Array = vertices.c[current]
		if not checked.is_empty():
			for nc: int in neib_cells:
				if same_type.call(nc):
					checked[nc] = 1

		var c1: bool = same_type.call(neib_cells[0])
		var c2: bool = same_type.call(neib_cells[1])
		var c3: bool = same_type.call(neib_cells[2])
		var vertex_neibs: PackedInt32Array = vertices.v[current]
		var v1: int = vertex_neibs[0]
		var v2: int = vertex_neibs[1]
		var v3: int = vertex_neibs[2]

		if v1 != previous and c1 != c2: next = v1
		elif v2 != previous and c2 != c3: next = v2
		elif v3 != previous and c1 != c3: next = v3

		if next < 0 or next >= vertices.c.size():
			break
		if next == current:
			break
		if i == max_iterations:
			break
		i += 1
	return chain


## Mark grid features (ocean, lakes, islands) and calculate the distance field
static func markup_grid(grid: FmgGraph) -> void:
	var heights := grid.h
	var neighbors: Array = grid.c
	var border_cells := grid.b
	var cells_number: int = grid.cell_count()
	var distance_field := PackedInt32Array()
	distance_field.resize(cells_number)
	var feature_ids := PackedInt32Array()
	feature_ids.resize(cells_number)
	var features: Array = [null]

	var queue: Array = [0]
	var feature_id: int = 1
	while queue[0] != -1:
		var first_cell: int = queue[0]
		feature_ids[first_cell] = feature_id
		var land: bool = heights[first_cell] >= SEA_LEVEL
		var border: bool = false

		while not queue.is_empty():
			var cell_id: int = queue.pop_back()
			if not border and border_cells[cell_id]:
				border = true
			for neighbor_id: int in neighbors[cell_id]:
				var is_neib_land: bool = heights[neighbor_id] >= SEA_LEVEL
				if land == is_neib_land and feature_ids[neighbor_id] == UNMARKED:
					feature_ids[neighbor_id] = feature_id
					queue.append(neighbor_id)
				elif land and not is_neib_land:
					distance_field[cell_id] = LAND_COAST
					distance_field[neighbor_id] = WATER_COAST

		var type: String = "island" if land else ("ocean" if border else "lake")
		features.append({"i": feature_id, "land": land, "border": border, "type": type})

		var unmarked: int = -1
		for i: int in cells_number:
			if feature_ids[i] == UNMARKED:
				unmarked = i
				break
		queue = [unmarked] if unmarked >= 0 else [-1]
		if unmarked < 0:
			break
		feature_id += 1

	markup_distance(distance_field, neighbors, DEEP_WATER, -1, -10)
	grid.t = distance_field
	grid.f = feature_ids
	grid.features = features


## Mark pack features (oceans, lakes, islands), build feature outline vertex
## chains, havens and harbors, then run the distance fields.
static func markup_pack(pack: FmgGraph, map_width: float, map_height: float) -> void:
	var neighbors: Array = pack.c
	var border_cells := pack.b
	var pack_cells_number: int = pack.cell_count()
	if pack_cells_number == 0:
		return

	var distance_field := PackedInt32Array()
	distance_field.resize(pack_cells_number)
	var feature_ids := PackedInt32Array()
	feature_ids.resize(pack_cells_number)
	var haven := PackedInt32Array()
	haven.resize(pack_cells_number)
	var harbor := PackedByteArray()
	harbor.resize(pack_cells_number)
	var features: Array = [null]

	var queue: Array = [0]
	var feature_id: int = 1
	while queue[0] != -1:
		var first_cell: int = queue[0]
		feature_ids[first_cell] = feature_id
		var land: bool = pack.h[first_cell] >= SEA_LEVEL
		var border: bool = border_cells[first_cell] == 1
		var total_cells: int = 1

		while not queue.is_empty():
			var cell_id: int = queue.pop_back()
			if border_cells[cell_id]:
				border = true
			for neighbor_id: int in neighbors[cell_id]:
				var is_neib_land: bool = pack.h[neighbor_id] >= SEA_LEVEL
				if land and not is_neib_land:
					distance_field[cell_id] = LAND_COAST
					distance_field[neighbor_id] = WATER_COAST
					if haven[cell_id] == 0:
						_define_haven(pack, cell_id, haven, harbor)
				elif land and is_neib_land:
					if distance_field[neighbor_id] == UNMARKED and distance_field[cell_id] == LAND_COAST:
						distance_field[neighbor_id] = LANDLOCKED
					elif distance_field[cell_id] == UNMARKED and distance_field[neighbor_id] == LAND_COAST:
						distance_field[cell_id] = LANDLOCKED

				if feature_ids[neighbor_id] == 0 and land == is_neib_land:
					queue.append(neighbor_id)
					feature_ids[neighbor_id] = feature_id
					total_cells += 1

		var type: String = "island" if land else ("ocean" if border else "lake")
		var feature := _build_feature(pack, feature_id, type, land, border, first_cell, total_cells, feature_ids, map_width, map_height)
		features.append(feature)

		var unmarked: int = -1
		for i: int in pack_cells_number:
			if feature_ids[i] == 0:
				unmarked = i
				break
		if unmarked < 0:
			break
		queue = [unmarked]
		feature_id += 1

	markup_distance(distance_field, neighbors, DEEPER_LAND, 1, 127) # markup pack land
	markup_distance(distance_field, neighbors, DEEP_WATER, -1, -10) # markup pack water

	pack.t = distance_field
	pack.f = feature_ids
	pack.haven = haven
	pack.harbor = harbor
	pack.features = features


static func _define_haven(pack: FmgGraph, cell_id: int, haven: PackedInt32Array, harbor: PackedByteArray) -> void:
	var water_cells := PackedInt32Array()
	for n: int in pack.c[cell_id]:
		if pack.h[n] < SEA_LEVEL:
			water_cells.append(n)
	if water_cells.is_empty():
		haven[cell_id] = 0
		harbor[cell_id] = 0
		return
	var best: int = water_cells[0]
	var best_d2: float = INF
	var p := pack.points
	for wc: int in water_cells:
		var d2: float = (p[cell_id].x - p[wc].x) * (p[cell_id].x - p[wc].x) + (p[cell_id].y - p[wc].y) * (p[cell_id].y - p[wc].y)
		if d2 < best_d2:
			best_d2 = d2
			best = wc
	haven[cell_id] = best
	harbor[cell_id] = water_cells.size()


static func _build_feature(pack: FmgGraph, feature_id: int, type: String, land: bool, border: bool, first_cell: int, total_cells: int, feature_ids: PackedInt32Array, map_width: float, map_height: float) -> Dictionary:
	var vertices := pack.voronoi.vertices
	var start_cell: int = first_cell
	var feature_vertices := PackedInt32Array()

	if type != "ocean":
		var same_feature := func(cell_id: int) -> bool: return feature_ids[cell_id] == feature_ids[first_cell]
		# find a cell on the feature border
		var is_on_border := func(cell_id: int) -> bool:
			if pack.b[cell_id]:
				return true
			for n: int in pack.c[cell_id]:
				if not same_feature.call(n):
					return true
			return false
		if not is_on_border.call(first_cell):
			for i: int in pack.cell_count():
				if feature_ids[i] == feature_ids[first_cell] and is_on_border.call(i):
					start_cell = i
					break
		# find the starting vertex facing a different feature
		var starting_vertex: int = -1
		for vv: int in pack.v[start_cell]:
			var faces_other: bool = false
			for vc: int in vertices.c[vv]:
				if not same_feature.call(vc):
					faces_other = true
					break
			if faces_other:
				starting_vertex = vv
				break
		if starting_vertex >= 0:
			feature_vertices = connect_vertices(vertices, starting_vertex, same_feature)

	var points := PackedVector2Array()
	for vv: int in feature_vertices:
		points.append(vertices.p[vv])
	points = FmgPaths.clip_poly(points, map_width, map_height)
	var area: float = FmgPaths.polygon_area(points)

	var feature := {
		"i": feature_id,
		"type": type,
		"land": land,
		"border": border,
		"cells": total_cells,
		"firstCell": start_cell,
		"vertices": feature_vertices,
		"area": absf(area),
		"shoreline": PackedInt32Array(),
		"height": 0.0,
		"subtype": "",
		"group": "",
		"temp": 0.0,
		"flux": 0.0,
		"evaporation": 0.0,
		"name": "",
	}

	if type == "lake":
		if area > 0:
			feature_vertices.reverse()
			feature["vertices"] = feature_vertices
		feature["shoreline"] = define_shoreline(pack, feature)
		feature["height"] = lake_height(pack, feature)
	return feature


## trace the ocean outline rings at given distance-from-coast levels (ocean-generator.ts)
static func generate_ocean_outlines(grid: FmgGraph, limits: Array) -> Array:
	var cells := grid
	var vertices := grid.voronoi.vertices
	var points_n: int = grid.cell_count()
	if cells.t.size() < points_n:
		return [] # the distance field is not built yet: markup_grid has not run
	var used := PackedByteArray()
	used.resize(points_n)
	var outlines := {}
	for t: int in limits:
		outlines[t] = []

	for i: int in points_n:
		var t: int = cells.t[i]
		if t > 0 or used[i] == 1 or not outlines.has(t):
			continue
		var start: int = _find_outline_start(cells, vertices, i, t, points_n)
		if start < 0:
			continue
		used[i] = 1

		var chain := _connect_outline_vertices(cells, vertices, start, t, used, points_n)
		if chain.size() < 4:
			continue
		var relax: int = 1 + t * -2
		var relaxed := PackedInt32Array()
		for index: int in chain.size():
			var vv: int = chain[index]
			var is_border_vertex: bool = false
			for vc: int in vertices.c[vv]:
				if vc >= points_n:
					is_border_vertex = true
					break
			if index % relax == 0 or is_border_vertex:
				relaxed.append(vv)
		if relaxed.size() < 4:
			continue
		var ring := PackedVector2Array()
		for vv: int in relaxed:
			ring.append(vertices.p[vv])
		ring = FmgPaths.clip_poly(ring, grid.width, grid.height)
		outlines[t].append(ring)

	var result: Array = []
	for t: int in limits:
		result.append({"t": t, "rings": outlines[t]})
	return result


static func _find_outline_start(cells: FmgGraph, vertices: FmgVoronoi.Vertices, i: int, t: int, points_n: int) -> int:
	if cells.b[i] == 1:
		for vv: int in cells.v[i]:
			for vc: int in vertices.c[vv]:
				if vc >= points_n:
					return vv
		return -1
	var neibs: PackedInt32Array = cells.c[i]
	for idx: int in neibs.size():
		if cells.t[neibs[idx]] < t or cells.t[neibs[idx]] == 0:
			return cells.v[i][idx]
	return -1


## distance-from-coast value of a cell adjacent to a vertex. Boundary pseudo-points
## (id >= points_n) clip the outer cells but own no cell data, so they read as
## unmarked: in the original JS `cells.t[id]` is `undefined` there, which is falsy
## exactly like 0, while a GDScript PackedInt32Array raises "Out of bounds get index".
static func _cell_distance(cells: FmgGraph, cell: int, points_n: int) -> int:
	if cell < 0 or cell >= points_n:
		return 0
	return cells.t[cell]


static func _connect_outline_vertices(cells: FmgGraph, vertices: FmgVoronoi.Vertices, start: int, t: int, used: PackedByteArray, points_n: int) -> PackedInt32Array:
	var chain := PackedInt32Array()
	var current: int = start
	var i: int = 0
	while i == 0 or (current != start and i < 10000):
		var prev: int = chain[chain.size() - 1] if chain.size() > 0 else -1
		chain.append(current)

		# boundary pseudo-points own no cell: nothing to mark as used there
		for cell: int in vertices.c[current]:
			if cell >= 0 and cell < points_n and cells.t[cell] == t:
				used[cell] = 1

		var vv: PackedInt32Array = vertices.v[current]
		var c: PackedInt32Array = vertices.c[current]
		var t0: int = _cell_distance(cells, c[0], points_n)
		var t1: int = _cell_distance(cells, c[1], points_n)
		var t2: int = _cell_distance(cells, c[2], points_n)
		var c0: bool = t0 == 0 or t0 == t - 1
		var c1: bool = t1 == 0 or t1 == t - 1
		var c2: bool = t2 == 0 or t2 == t - 1
		if vv[0] != -1 and vv[0] != prev and c0 != c1: current = vv[0]
		elif vv[1] != -1 and vv[1] != prev and c1 != c2: current = vv[1]
		elif vv[2] != -1 and vv[2] != prev and c0 != c2: current = vv[2]

		if current == chain[chain.size() - 1]:
			break
		i += 1
	if chain.size() > 0:
		chain.append(chain[0])
	return chain


## land cells around a lake (lakes.ts defineShoreline)
static func define_shoreline(pack: FmgGraph, feature: Dictionary) -> PackedInt32Array:
	var shoreline := PackedInt32Array()
	var seen := {}
	for vertex_index: int in feature["vertices"]:
		for cell_index: int in pack.voronoi.vertices.c[vertex_index]:
			if pack.h[cell_index] >= SEA_LEVEL and not seen.has(cell_index):
				seen[cell_index] = true
				shoreline.append(cell_index)
	return shoreline


static func lake_height(pack: FmgGraph, feature: Dictionary) -> float:
	var heights := pack.h
	var min_shore_height: float = 20.0
	var shoreline: PackedInt32Array = feature["shoreline"]
	if shoreline.size() > 0:
		min_shore_height = float(heights[shoreline[0]])
		for cell_id: int in shoreline:
			min_shore_height = minf(min_shore_height, float(heights[cell_id]))
	return FmgRng.rn(min_shore_height - 0.1, 2)


## classify features: continents/islands, oceans/seas/gulfs, lake subtypes
static func define_groups(pack: FmgGraph, grid_cell_count: int) -> void:
	var CONTINENT_MIN_SIZE: float = grid_cell_count / 10.0
	var ISLAND_MIN_SIZE: float = grid_cell_count / 1000.0

	for feature in pack.features:
		if feature == null or feature.is_empty():
			continue
		var type: String = feature["type"]
		if type == "ocean":
			continue
		if type == "island":
			var subtype: String = "isle"
			if feature["cells"] > CONTINENT_MIN_SIZE:
				subtype = "continent"
			elif feature["cells"] > ISLAND_MIN_SIZE:
				subtype = "island"
			feature["subtype"] = subtype
		elif type == "lake":
			var subtype_l: String = "freshwater"
			if feature["temp"] < -3.0:
				subtype_l = "frozen"
			elif feature["height"] > 60.0 and feature["cells"] < 10 and int(feature["firstCell"]) % 10 == 0:
				subtype_l = "lava"
			elif not feature.has("inlets") and not feature.has("outlet"):
				if feature["evaporation"] > feature["flux"] * 4.0:
					subtype_l = "dry"
				elif feature["cells"] < 3 and int(feature["firstCell"]) % 10 == 0:
					subtype_l = "sinkhole"
			elif not feature.has("outlet") and feature["evaporation"] > feature["flux"]:
				subtype_l = "salt"
			feature["subtype"] = subtype_l
		feature["group"] = feature["subtype"] if type == "lake" else "sea_island"
