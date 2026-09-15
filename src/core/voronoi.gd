class_name FmgVoronoi
extends RefCounted
## Builds the Voronoi diagram from a Delaunator triangulation.
## Port of the original voronoi.ts: cells get their circumscribed vertices and
## adjacent cells, vertices get coordinates and adjacency. Boundary points passed
## after the real points get no cells of their own but clip the outer cells.

class Cells:
	var v: Array = [] # per cell: PackedInt32Array of adjacent vertices
	var c: Array = [] # per cell: PackedInt32Array of adjacent cells
	var b: PackedByteArray = PackedByteArray() # 1 = near-border cell
	var i: PackedInt32Array = PackedInt32Array() # cell indexes
	var count: int = 0

class Vertices:
	var p: PackedVector2Array = PackedVector2Array() # coordinates
	var v: Array = [] # per vertex: PackedInt32Array of adjacent vertices
	var c: Array = [] # per vertex: PackedInt32Array of adjacent cells

var cells := Cells.new()
var vertices := Vertices.new()


static func calculate(points: PackedVector2Array, boundary: PackedVector2Array) -> FmgVoronoi:
	var all_points := PackedVector2Array(points)
	all_points.append_array(boundary)
	var delaunay := Delaunator.from_points(all_points)
	var voronoi := FmgVoronoi.new()
	voronoi._build(delaunay, all_points.size(), points.size())
	return voronoi


func _build(delaunay: Delaunator, _points_n_total: int, points_n: int) -> void:
	var triangles: PackedInt32Array = delaunay.triangles
	var halfedges: PackedInt32Array = delaunay.halfedges
	var points := delaunay.coords

	cells.v.resize(points_n)
	cells.c.resize(points_n)
	cells.b.resize(points_n)

	var tri_count: int = triangles.size() / 3
	vertices.p.resize(tri_count)
	vertices.v.resize(tri_count)
	vertices.c.resize(tri_count)

	for e: int in triangles.size():
		var p: int = triangles[_next_halfedge(e)]
		if p < points_n and cells.c[p] == null:
			var edges := _edges_around_point(e, halfedges, triangles)
			var cell_v := PackedInt32Array()
			var cell_c := PackedInt32Array()
			for edge: int in edges:
				cell_v.append(_triangle_of_edge(edge))
			for edge: int in edges:
				var adj: int = triangles[edge]
				if adj < points_n:
					cell_c.append(adj)
			cells.v[p] = cell_v
			cells.c[p] = cell_c
			cells.b[p] = 1 if edges.size() > cell_c.size() else 0

		var t: int = _triangle_of_edge(e)
		if vertices.c[t] == null:
			var tri_pts := _points_of_triangle(t, triangles, points)
			var cc := Delaunator.circumcenter(tri_pts[0].x, tri_pts[0].y, tri_pts[1].x, tri_pts[1].y, tri_pts[2].x, tri_pts[2].y)
			vertices.p[t] = cc
			vertices.v[t] = _triangles_adjacent_to_triangle(t, halfedges)
			vertices.c[t] = _points_of_triangle_ids(t, triangles)

	for i: int in points_n:
		cells.i.append(i)
	cells.count = points_n


static func _points_of_triangle_ids(t: int, triangles: PackedInt32Array) -> PackedInt32Array:
	return PackedInt32Array([triangles[t * 3], triangles[t * 3 + 1], triangles[t * 3 + 2]])


static func _points_of_triangle(t: int, triangles: PackedInt32Array, points: PackedFloat64Array) -> Array:
	var out: Array = []
	for k: int in 3:
		var pid: int = triangles[t * 3 + k]
		out.append(Vector2(points[pid * 2], points[pid * 2 + 1]))
	return out


static func _triangles_adjacent_to_triangle(t: int, halfedges: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in 3:
		var e: int = t * 3 + k
		var opposite: int = halfedges[e]
		out.append(_triangle_of_edge(opposite))
	return out


static func _edges_around_point(start: int, halfedges: PackedInt32Array, _triangles: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	var incoming: int = start
	while true:
		result.append(incoming)
		var outgoing: int = _next_halfedge(incoming)
		incoming = halfedges[outgoing]
		if incoming == -1 or incoming == start or result.size() >= 20:
			break
	return result


static func _triangle_of_edge(e: int) -> int:
	return e / 3 if e >= 0 else -1


static func _next_halfedge(e: int) -> int:
	return e - 2 if e % 3 == 2 else e + 1
