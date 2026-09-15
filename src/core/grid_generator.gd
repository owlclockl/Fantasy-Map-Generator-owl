class_name GridGenerator
extends RefCounted
## The initial graph: a jittered square lattice of points, triangulated and
## turned into a Voronoi diagram. Port of grid-generator.ts.
## Boundary pseudo-points (an extra lattice ring outside the map) clip the
## outer cells but get no cells of their own.

const SEA_LEVEL: int = 20


static func generate(_seed_value: String, width: float, height: float, cells_desired: int, rng: FmgRng) -> FmgGraph:
	var spacing: float = get_spacing(cells_desired, width, height)
	var graph := FmgGraph.new()
	graph.spacing = spacing
	graph.width = width
	graph.height = height
	graph.cells_x = _cells_count(spacing, width)
	graph.cells_y = _cells_count(spacing, height)
	graph.points = _jittered_points(width, height, spacing, rng)

	# the lattice plus one ring outside the map: boundary pseudo-points
	# participate in the triangulation but receive no cells
	graph.boundary = _boundary_points(width, height, spacing)
	var combined := PackedVector2Array(graph.points)
	combined.append_array(graph.boundary)
	var del := Delaunator.from_points(combined)
	var voronoi := FmgVoronoi.new()
	var all_n: int = combined.size()
	voronoi._build(del, all_n, graph.points.size())

	graph.voronoi = voronoi
	graph.v = voronoi.cells.v
	graph.c = voronoi.cells.c
	graph.b = voronoi.cells.b
	graph.h = PackedByteArray()
	graph.h.resize(graph.points.size())
	reset_heights(graph)
	return graph


static func reset_heights(graph: FmgGraph) -> void:
	graph.h = PackedByteArray()
	graph.h.resize(graph.points.size())


static func get_spacing(cells_desired: int, width: float, height: float) -> float:
	return FmgRng.rn(sqrt(width * height / float(cells_desired)), 2)


static func _cells_count(spacing: float, size: float) -> int:
	return int(floor((size + 0.5 * spacing - 1e-10) / spacing))


## points of a square grid, each one randomly shifted within its square
static func _jittered_points(width: float, height: float, spacing: float, rng: FmgRng) -> PackedVector2Array:
	var radius: float = spacing / 2.0
	var jittering: float = radius * 0.9
	var double_jittering: float = jittering * 2.0
	var points := PackedVector2Array()
	var y: float = radius
	while y < height:
		var x: float = radius
		while x < width:
			var jx: float = rng.random() * double_jittering - jittering
			var jy: float = rng.random() * double_jittering - jittering
			points.append(Vector2(minf(FmgRng.rn(x + jx, 2), width), minf(FmgRng.rn(y + jy, 2), height)))
			x += spacing
		y += spacing
	return points


## an extra lattice ring outside the map: clips the outer voronoi cells
static func _boundary_points(width: float, height: float, spacing: float) -> PackedVector2Array:
	var offset: float = -spacing
	var b_spacing: float = spacing * 2.0
	var w: float = width - offset * 2.0
	var h: float = height - offset * 2.0
	var number_x: int = int(ceil(w / b_spacing)) - 1
	var number_y: int = int(ceil(h / b_spacing)) - 1
	var points := PackedVector2Array()
	var i: float = 0.5
	while i < number_x:
		var x: float = ceil(w * i / number_x + offset)
		points.append(Vector2(x, offset))
		points.append(Vector2(x, h + offset))
		i += 1.0
	i = 0.5
	while i < number_y:
		var y: float = ceil(h * i / number_y + offset)
		points.append(Vector2(offset, y))
		points.append(Vector2(w + offset, y))
		i += 1.0
	return points


## cell index at the given coordinates for the packed graph: nearest point scan
## (the pack graph has no lattice). Grid graphs use the fast lattice lookup.
static func find_cell_in_pack(graph: FmgGraph, x: float, y: float, radius: float = INF) -> int:
	var best: int = -1
	var best_d2: float = radius * radius if radius != INF else INF
	var pts := graph.points
	for i: int in pts.size():
		var d2: float = (pts[i].x - x) * (pts[i].x - x) + (pts[i].y - y) * (pts[i].y - y)
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## turn depressions that cannot pour to water into lakes (grid level)
static func add_deep_depression_lakes(graph: FmgGraph, _rng: FmgRng, lake_elevation_limit: int) -> void:
	if lake_elevation_limit == 80:
		return
	var c: Array = graph.c
	var h := graph.h
	var b := graph.b

	for i: int in graph.cell_count():
		if b[i] != 0 or h[i] < SEA_LEVEL:
			continue
		var min_neib: int = 255
		for n: int in c[i]:
			min_neib = mini(min_neib, h[n])
		if h[i] > min_neib:
			continue

		var deep: bool = true
		var threshold: int = h[i] + lake_elevation_limit
		var queue: Array = [i]
		var checked := PackedByteArray()
		checked.resize(graph.cell_count())
		checked[i] = 1

		while deep and not queue.is_empty():
			var q: int = queue.pop_back()
			for n: int in c[q]:
				if checked[n]:
					continue
				if h[n] >= threshold:
					continue
				if h[n] < SEA_LEVEL:
					deep = false
					break
				checked[n] = 1
				queue.append(n)

		if deep:
			var lake_cells: Array = [i]
			for n: int in c[i]:
				if h[n] == h[i]:
					lake_cells.append(n)
			_add_lake(graph, lake_cells)


static func _add_lake(graph: FmgGraph, lake_cells: Array) -> void:
	var feature_id: int = graph.features.size()
	var h := graph.h
	var t := graph.t
	var f := graph.f
	for cell_id: int in lake_cells:
		h[cell_id] = 19
		t[cell_id] = -1
		f[cell_id] = feature_id
		for n: int in graph.c[cell_id]:
			if not lake_cells.has(n):
				t[n] = 1 # the lake shore is a coastline now
	graph.features.append({"i": feature_id, "land": false, "border": false, "type": "lake"})


## near-sea lakes get a lot of inflow; most breach the threshold and flow out to sea
static func open_near_sea_lakes(graph: FmgGraph, is_atoll: bool) -> void:
	if is_atoll:
		return
	var has_lakes: bool = false
	for feat in graph.features: # features[0] is a null placeholder
		if feat == null:
			continue
		if feat.get("type", "") == "lake":
			has_lakes = true
			break
	if not has_lakes:
		return
	var LIMIT: int = 22

	for i: int in graph.cell_count():
		var lake_feature_id: int = graph.f[i]
		if lake_feature_id <= 0 or lake_feature_id >= graph.features.size():
			continue
		if graph.features[lake_feature_id].get("type", "") != "lake":
			continue

		var removed: bool = false
		for coast_cell: int in graph.c[i]:
			if removed:
				break
			if graph.t[coast_cell] != 1 or graph.h[coast_cell] > LIMIT:
				continue
			for n: int in graph.c[coast_cell]:
				var ocean: int = graph.f[n]
				if ocean <= 0 or ocean >= graph.features.size():
					continue
				if graph.features[ocean].get("type", "") != "ocean":
					continue
				# remove lake: it becomes part of the ocean
				graph.h[coast_cell] = 19
				graph.t[coast_cell] = -1
				graph.f[coast_cell] = ocean
				for nc: int in graph.c[coast_cell]:
					if graph.h[nc] >= SEA_LEVEL:
						graph.t[nc] = 1
				for j: int in graph.cell_count():
					if graph.f[j] == lake_feature_id:
						graph.f[j] = ocean
				graph.features[lake_feature_id]["type"] = "ocean"
				graph.features[lake_feature_id]["land"] = false
				removed = true
				break
