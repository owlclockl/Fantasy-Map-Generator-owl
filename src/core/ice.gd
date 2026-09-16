class_name FmgIce
extends RefCounted
## Glaciers and icebergs. Port of ice-generator.ts: glaciers are isoline
## polygons over cold land cells on the dense grid; icebergs are shrunk cell
## polygons on cold open water. Output goes to pack.ice as
## {"type": "glacier"|"iceberg", "points": PackedVector2Array, ...}.

const GLACIER_MAX_TEMP: int = -8
const ICEBERG_MAX_TEMP: int = 0

var rng: FmgRng
var grid: FmgGraph
var pack: FmgGraph


func _init(rng_ref: FmgRng, grid_ref: FmgGraph, pack_ref: FmgGraph) -> void:
	rng = rng_ref
	grid = grid_ref
	pack = pack_ref


func generate() -> void:
	pack.ice = []
	_generate_glaciers()
	_generate_icebergs()


## Cold land cells (h >= 20, temp <= -8) form ice shields traced as isolines.
func _generate_glaciers() -> void:
	var n: int = grid.cell_count()
	var checked := PackedByteArray()
	checked.resize(n)

	for cell_id: int in range(n):
		if checked[cell_id] == 1:
			continue
		if not _is_glacier_cell(cell_id):
			continue
		checked[cell_id] = 1

		# a border cell adjacent to a non-glacier cell starts the ring
		var border_cell: int = -1
		for neib: int in grid.c[cell_id]:
			if not _is_glacier_cell(neib):
				border_cell = neib
				break
		if border_cell == -1:
			continue

		var starting_vertex: int = -1
		for v: int in grid.v[cell_id]:
			var has_different: bool = false
			for vc: int in grid.voronoi.vertices.c[v]:
				if not _is_glacier_cell(vc):
					has_different = true
					break
			if has_different:
				starting_vertex = v
				break
		if starting_vertex == -1:
			continue

		var same_type := func(cid: int) -> bool: return _is_glacier_cell(cid)
		var chain: PackedInt32Array = FmgFeatures.connect_vertices(grid.voronoi.vertices, starting_vertex, same_type, checked)
		if chain.size() < 3:
			continue

		var points := PackedVector2Array()
		for v: int in chain:
			points.append(grid.voronoi.vertices.p[v])
		points = FmgPaths.clip_poly(points, grid.width, grid.height, false)
		if points.size() >= 3:
			pack.ice.append({"type": "glacier", "points": points})


func _is_glacier_cell(cell_id: int) -> bool:
	if cell_id < 0 or cell_id >= grid.cell_count():
		return false
	return grid.h[cell_id] >= 20 and grid.temp[cell_id] <= GLACIER_MAX_TEMP


## Icebergs: cold water cells of the sea (not lakes), each with a chance.
func _generate_icebergs() -> void:
	var min_temp: int = 100
	for cell_id: int in range(grid.cell_count()):
		if grid.temp[cell_id] < min_temp:
			min_temp = grid.temp[cell_id]

	for cell_id: int in range(grid.cell_count()):
		var temp: int = grid.temp[cell_id]
		if grid.h[cell_id] >= 20:
			continue # no icebergs on land
		if temp > ICEBERG_MAX_TEMP:
			continue # too warm
		var feature: Dictionary = grid.feature_of(cell_id)
		if feature.get("type", "") == "lake":
			continue # no icebergs on lakes
		if rng.P(0.8):
			continue # skip most eligible cells

		var random_factor: float = 0.8 + rng.random() * 0.4
		var base_size: float = (1.0 - FmgRng.normalize(float(temp), float(min_temp), 1.0)) * 0.8
		if grid.t[cell_id] == -1:
			base_size /= 1.3 # coastline: smaller icebergs
		var size: float = clampf(FmgRng.rn(base_size * random_factor, 2), 0.1, 1.0)

		var center: Vector2 = grid.points[cell_id]
		var polygon: PackedVector2Array = grid.get_polygon(cell_id)
		var points := PackedVector2Array()
		for p: Vector2 in polygon:
			points.append(Vector2(lerpf(center.x, p.x, size), lerpf(center.y, p.y, size)))
		pack.ice.append({"type": "iceberg", "points": points, "cellId": cell_id, "size": size})
