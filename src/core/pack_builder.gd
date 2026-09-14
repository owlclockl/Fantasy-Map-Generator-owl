class_name PackBuilder
extends RefCounted
## The packed graph: a second Voronoi diagram built from the grid points that
## matter for the map. Deep ocean points are dropped and coastal cells are split
## for higher coastline resolution. Port of pack-generator.ts.

const SEA_LEVEL: int = 20


static func generate(grid: FmgGraph, rng: FmgRng) -> FmgGraph:
	var grid_cells := grid
	var new_points := PackedVector2Array()
	var new_g := PackedInt32Array()
	var new_h := PackedByteArray()
	var spacing2: float = grid.spacing * grid.spacing

	for i: int in grid_cells.cell_count():
		var height: int = grid_cells.h[i]
		var type: int = grid_cells.t[i]
		var is_lake: bool = false
		var fid: int = grid_cells.f[i]
		if fid > 0 and fid < grid_cells.features.size():
			is_lake = grid_cells.features[fid].get("type", "") == "lake"

		if height < SEA_LEVEL and type != -1 and type != -2:
			continue # exclude deep ocean points
		if type == -2 and (i % 4 == 0 or is_lake):
			continue # exclude non-coastal lake points

		var p := grid_cells.points[i]
		new_points.append(p)
		new_g.append(i)
		new_h.append(height)

		# add additional points for cells along the coast
		if type == 1 or type == -1:
			if grid_cells.b[i]:
				continue
			for e: int in grid_cells.c[i]:
				if i > e:
					continue
				if grid_cells.t[e] != type:
					continue
				var dist2: float = (p.y - grid_cells.points[e].y) * (p.y - grid_cells.points[e].y) + (p.x - grid_cells.points[e].x) * (p.x - grid_cells.points[e].x)
				if dist2 < spacing2:
					continue
				new_points.append(Vector2(FmgRng.rn((p.x + grid_cells.points[e].x) / 2.0, 1), FmgRng.rn((p.y + grid_cells.points[e].y) / 2.0, 1)))
				new_g.append(i)
				new_h.append(height)

	var pack := FmgGraph.new()
	pack.width = grid.width
	pack.height = grid.height
	var voronoi := FmgVoronoi.new()
	var del := Delaunator.from_points(new_points)
	voronoi._build(del, new_points.size(), new_points.size())
	pack.voronoi = voronoi
	pack.v = voronoi.cells.v
	pack.c = voronoi.cells.c
	pack.b = voronoi.cells.b
	pack.points = new_points
	pack.g = new_g
	pack.h = new_h
	pack.spacing = grid.spacing * 0.5
	pack.cells_x = grid.cells_x
	pack.cells_y = grid.cells_y
	pack.boundary = grid.boundary

	# cell areas (clamped like Uint16 in the original)
	pack.area.resize(pack.cell_count())
	for cell_id: int in pack.cell_count():
		var poly := pack.get_polygon(cell_id)
		pack.area[cell_id] = minf(absf(FmgPaths.polygon_area(poly)), 65535.0)

	# the grid keeps the climate data the pack reads through `g`
	return pack
