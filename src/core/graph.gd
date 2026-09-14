class_name FmgGraph
extends RefCounted
## A Voronoi graph — used both for the dense grid graph and the packed graph.
## Cell data arrays live here alongside the feature/river/culture/etc. tables
## that belong to this graph, mirroring the original `grid` and `pack` globals.

var spacing: float = 10.0
var cells_x: int = 0
var cells_y: int = 0
var points := PackedVector2Array()
var boundary := PackedVector2Array()
var voronoi: FmgVoronoi = null

# --- cell data (shared names with the original JS code) ---
var v: Array = [] # per cell: PackedInt32Array of vertices
var c: Array = [] # per cell: PackedInt32Array of neighbor cells
var b: PackedByteArray = PackedByteArray() # near-border flag
var h := PackedByteArray() # heights 0..100 (grid + pack)
var t := PackedInt32Array() # distance field: land 1+, water -1.., 0 unmarked
var f := PackedInt32Array() # feature id per cell
var g := PackedInt32Array() # parent grid cell (pack only)
var area := PackedFloat32Array() # cell area (pack only)
var temp := PackedInt32Array() # temperature (grid only)
var prec := PackedInt32Array() # precipitation (grid only)
var fl := PackedFloat32Array() # water flux (pack only)
var r := PackedInt32Array() # river id (pack only)
var conf := PackedInt32Array() # confluence flux (pack only)
var haven := PackedInt32Array() # opposite water cell (pack only)
var harbor := PackedByteArray() # adjacent water count (pack only)
var biome := PackedByteArray() # biome id (pack only)
var culture := PackedInt32Array() # culture id (pack only)
var state := PackedInt32Array() # state id (pack only)
var province := PackedInt32Array() # province id (pack only)
var religion := PackedInt32Array() # religion id (pack only)
var s := PackedInt32Array() # population suitability score (pack only)
var pop := PackedFloat32Array() # rural population (pack only)
var burg := PackedInt32Array() # burg id (pack only)

# --- object tables ---
var features: Array = [] # Dictionary per feature; index == feature id; [0] is null
var rivers: Array = [] # Dictionary per river; index 0 unused
var biomes: Array = [] # Dictionary per biome
var cultures: Array = [] # Dictionary per culture
var burgs: Array = [] # Dictionary per burg
var states: Array = [] # Dictionary per state
var provinces: Array = [] # Dictionary per province
var religions: Array = [] # Dictionary per religion

var width: float = 1280.0
var height: float = 800.0


func cell_count() -> int:
	return points.size()


func get_polygon(cell_id: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for vertex_id: int in v[cell_id]:
		out.append(voronoi.vertices.p[vertex_id])
	return out


func find_cell(x: float, y: float) -> int:
	# resolves by the regular square lattice the grid points sit on
	var col: int = mini(int(floor(x / spacing)), cells_x - 1)
	var row: int = mini(int(floor(y / spacing)), cells_y - 1)
	return maxi(row, 0) * cells_x + maxi(col, 0)


func is_water(cell_id: int) -> bool:
	return h[cell_id] < 20


func is_land(cell_id: int) -> bool:
	return h[cell_id] >= 20


func feature_of(cell_id: int) -> Dictionary:
	var fid: int = f[cell_id]
	if fid < features.size() and fid > 0:
		return features[fid]
	return {}


## BFS all cells within `radius` distance rings from the cell at (x, y)
func find_all(x: float, y: float, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array([find_cell(x, y)])
	var rings: int = int(radius / spacing)
	if rings == 0 or radius == 1.0:
		return found
	for nid: int in c[found[0]]:
		found.append(nid)
	var frontier := PackedInt32Array(c[found[0]])
	while rings > 1:
		var next := PackedInt32Array()
		for cell_id: int in frontier:
			for neighbor_id: int in c[cell_id]:
				if not found.has(neighbor_id):
					found.append(neighbor_id)
					next.append(neighbor_id)
		frontier = next
		rings -= 1
	return found


## the highest cell id used by cultures/states/... tables (0 is reserved)
func max_feature_id() -> int:
	return features.size() - 1
