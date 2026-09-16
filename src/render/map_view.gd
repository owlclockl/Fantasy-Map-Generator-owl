class_name MapView
extends Node2D
## Renders the generated world: ocean, landmasses with fractal coastlines,
## lakes, rivers, overlays (political/biomes/cultures/religions/heights),
## borders, burgs and labels. Static cell layers are uploaded as cached meshes;
## camera moves therefore reuse the GPU command list instead of rebuilding a
## draw call for every Voronoi cell.

const COL_OCEAN := Color("#466eab")
const COL_OCEAN_DEEP := Color("#3b5e94")
const COL_OCEAN_OUTLINE := Color("#5b83b8")
const COL_LAKE := Color("#5b83b8")
const COL_LAKE_SHORE := Color("#7da2cc")
const COL_RIVER := Color("#5d99c6")
const COL_COAST := Color("#33506d")
const COL_LAND := Color("#e6e2c8")
const COL_BORDER := Color(0.1, 0.2, 0.3, 0.65)
const COL_PROVINCE_BORDER := Color(0.1, 0.2, 0.3, 0.3)
const COL_TEXT := Color(0.12, 0.13, 0.15, 0.85)
const COL_TEXT_OUT := Color(1, 1, 1, 0.6)

# hypsometric ramp for the heightmap view (t in 0..1 over land)
const HYPSO: Array = [
	Color("#4f7ec3"), Color("#79a743"), Color("#a8c048"), Color("#cbcd5b"),
	Color("#d6c56a"), Color("#c9a668"), Color("#b98d5e"), Color("#a57855"),
	Color("#c5b3a6"), Color("#e8e2da")
]

var sim: FmgSim = null # Sim autoload

# layer toggles
var show_politics: bool = true
var show_biomes: bool = true
var show_heights: bool = false
var show_cultures: bool = false
var show_religions: bool = false
var show_provinces: bool = false
var show_rivers: bool = true
var show_borders: bool = true
var show_labels: bool = true
var show_burgs: bool = true
var show_relief: bool = true # hillshading-ish height tint over biomes
var show_ice: bool = true
var show_routes: bool = true
var show_feature_labels: bool = true # oceans, seas, lakes, islands
var show_province_labels: bool = false
var show_markers: bool = true
var show_armies: bool = false
var show_zones: bool = false
var show_goods: bool = false
var show_emblems: bool = false
var show_relief_icons: bool = true # mountain and forest glyphs
var show_cell_borders: bool = false # debug

# cached geometry
var _land_rings: Array = [] # {points, feature}
var _lake_rings: Array = []
var _ocean_rings: Array = [] # {t, rings}
var _river_polys: Array = [] # {points, river}
var _feature_labels: Array = [] # {name, pos, size, color}
var _mountain_points: PackedVector2Array = PackedVector2Array()
var _tree_points: PackedVector2Array = PackedVector2Array()
var _font: Font = null

# Geometry and meshes are built once per generated map. Drawing one mesh per
# cell used to make the 10k/20k presets needlessly expensive: every redraw
# recreated the Voronoi polygon and submitted thousands of draw calls. The
# cached polygons also keep every overlay clipped to the map rectangle, which
# prevents the boundary cells from bleeding into the UI margin.
var _cell_polygons: Array = []
var _biome_mesh: ArrayMesh = null
var _height_mesh: ArrayMesh = null
var _culture_mesh: ArrayMesh = null
var _religion_mesh: ArrayMesh = null
var _state_mesh: ArrayMesh = null
var _province_mesh: ArrayMesh = null
var _relief_mesh: ArrayMesh = null
var _zones_mesh: ArrayMesh = null
var _goods_mesh: ArrayMesh = null
var _tree_mesh: ArrayMesh = null
var _mountain_segments: PackedVector2Array = PackedVector2Array()
var _tree_stem_segments: PackedVector2Array = PackedVector2Array()
var _border_segments: PackedVector2Array = PackedVector2Array()
var _province_border_segments: PackedVector2Array = PackedVector2Array()
var _cell_border_segments: PackedVector2Array = PackedVector2Array()
var _sea_route_segments: PackedVector2Array = PackedVector2Array()
var _road_segments: PackedVector2Array = PackedVector2Array()
var _trail_segments: PackedVector2Array = PackedVector2Array()
var _journey_segments: PackedVector2Array = PackedVector2Array()

# brush preview (set by main.gd)
var brush_preview_visible: bool = false
var brush_preview_pos := Vector2.ZERO
var brush_preview_radius: float = 40.0


func _ready() -> void:
	_font = ThemeDB.fallback_font


func rebuild_cache() -> void:
	_land_rings = []
	_lake_rings = []
	_ocean_rings = []
	_river_polys = []
	_feature_labels = []
	_cell_polygons = []
	_biome_mesh = null
	_height_mesh = null
	_culture_mesh = null
	_religion_mesh = null
	_state_mesh = null
	_province_mesh = null
	_relief_mesh = null
	_zones_mesh = null
	_goods_mesh = null
	_tree_mesh = null
	_mountain_segments = PackedVector2Array()
	_tree_stem_segments = PackedVector2Array()
	_border_segments = PackedVector2Array()
	_province_border_segments = PackedVector2Array()
	_cell_border_segments = PackedVector2Array()
	_sea_route_segments = PackedVector2Array()
	_road_segments = PackedVector2Array()
	_trail_segments = PackedVector2Array()
	_journey_segments = PackedVector2Array()
	_mountain_points = PackedVector2Array()
	_tree_points = PackedVector2Array()
	if sim == null or sim.pack == null:
		queue_redraw_all()
		return
	_build_cell_polygons()
	_build_feature_labels()
	_build_relief_icons()

	# coastline rings per feature, fractalized deterministically per feature id
	for feature in sim.pack.features:
		if feature == null or feature.is_empty():
			continue
		var chain: PackedInt32Array = feature["vertices"]
		if chain.size() < 3:
			continue
		var points := PackedVector2Array()
		for vv: int in chain:
			points.append(sim.pack.voronoi.vertices.p[vv])
		points = FmgPaths.clip_poly(points, sim.map_width, sim.map_height, true)
		points = FmgPaths.simplify(points, 0.3)
		if points.size() < 3:
			continue
		var ring: PackedVector2Array
		if sim.coast_enabled:
			var coast_rng := FmgRng.new("%s_c%d" % [sim.seed_value, feature["i"]])
			var smooth_threshold: float = 0.25
			if feature["type"] == "lake":
				smooth_threshold = minf(1.0, smooth_threshold * 2.0)
			ring = FmgPaths.fractalize_coastline(points, coast_rng, sim.coast_max_depth, sim.coast_amplitude,
				1.0, smooth_threshold, 1.5, 4, 0.9, sim.map_width, sim.map_height)
		else:
			ring = FmgPaths.chaikin(points, true, 1)
			ring.append(ring[0])
		if ring.size() < 4:
			continue
		if feature["type"] == "lake":
			_lake_rings.append({"points": ring, "feature": feature})
		elif feature["land"]:
			_land_rings.append({"points": ring, "feature": feature})

	# ocean outline rings around coasts
	var limits: Array = []
	for t: int in range(-1, -6, -1):
		limits.append(t)
	if sim.grid != null:
		_ocean_rings = FmgFeatures.generate_ocean_outlines(sim.grid, limits)

	# river polygons
	if sim.hydrology != null:
		for river in sim.pack.rivers:
			if river == null:
				continue
			var poly := sim.hydrology.get_river_polygon(river)
			if poly.size() >= 3:
				_river_polys.append({"points": poly, "river": river})

	# The rest of the render data is immutable until the next generation. Build
	# it here rather than in _draw(), so toggling a layer only changes a single
	# mesh draw call and never walks the complete Voronoi graph again.
	_build_overlay_meshes()
	_build_border_segments()
	_build_route_segments()

	queue_redraw_all()


## Cache clipped Voronoi cells. Boundary cells in the packed graph can have
## vertices outside the map; using the clipped version for every layer fixes
## the thin triangles that otherwise appeared over the sidebar/margin.
func _build_cell_polygons() -> void:
	var pack: FmgGraph = sim.pack
	_cell_polygons.resize(pack.cell_count())
	for i: int in pack.cell_count():
		var polygon: PackedVector2Array = pack.get_polygon(i)
		_cell_polygons[i] = FmgPaths.clip_poly(polygon, sim.map_width, sim.map_height)


func _mesh_from_cells(color_fn: Callable, alpha: float = 1.0, include_water: bool = false) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if not include_water and pack.h[i] < 20:
			continue
		var polygon: PackedVector2Array = _cell_polygons[i]
		if polygon.size() < 3:
			continue
		var color: Color = color_fn.call(i)
		if color.a <= 0.0:
			continue
		color.a *= alpha
		for j: int in range(1, polygon.size() - 1):
			vertices.append(polygon[0])
			vertices.append(polygon[j])
			vertices.append(polygon[j + 1])
			colors.append(color)
			colors.append(color)
			colors.append(color)
	return _make_color_mesh(vertices, colors)


func _make_color_mesh(vertices: PackedVector2Array, colors: PackedColorArray) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_overlay_meshes() -> void:
	_biome_mesh = _mesh_from_cells(_cell_biome_color)
	_height_mesh = _mesh_from_cells(_cell_height_color, 1.0, true)
	_culture_mesh = _mesh_from_cells(_cell_culture_color, 0.65)
	_religion_mesh = _mesh_from_cells(_cell_religion_color, 0.6)
	_state_mesh = _mesh_from_cells(_cell_state_color, 0.55)
	_province_mesh = _mesh_from_cells(_cell_province_color, 0.25)

	var relief_vertices := PackedVector2Array()
	var relief_colors := PackedColorArray()
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if pack.h[i] < 45:
			continue
		var polygon: PackedVector2Array = _cell_polygons[i]
		if polygon.size() < 3:
			continue
		var strength: float = clampf((float(pack.h[i]) - 45.0) / 55.0, 0.0, 1.0) * 0.45
		var color := Color(0.25, 0.2, 0.12, strength)
		for j: int in range(1, polygon.size() - 1):
			relief_vertices.append(polygon[0])
			relief_vertices.append(polygon[j])
			relief_vertices.append(polygon[j + 1])
			relief_colors.append(color)
			relief_colors.append(color)
			relief_colors.append(color)
	_relief_mesh = _make_color_mesh(relief_vertices, relief_colors)

	var zone_vertices := PackedVector2Array()
	var zone_colors := PackedColorArray()
	for zone_value: Variant in pack.zones:
		var zone: Dictionary = zone_value
		var color := Color.html(str(zone.get("color", "#888888")))
		color.a = 0.16
		for cell_value: Variant in zone.get("cells", []):
			var cell_id: int = int(cell_value)
			if cell_id < 0 or cell_id >= _cell_polygons.size():
				continue
			var polygon: PackedVector2Array = _cell_polygons[cell_id]
			if polygon.size() < 3:
				continue
			for j: int in range(1, polygon.size() - 1):
				zone_vertices.append(polygon[0])
				zone_vertices.append(polygon[j])
				zone_vertices.append(polygon[j + 1])
				zone_colors.append(color)
				zone_colors.append(color)
				zone_colors.append(color)
	_zones_mesh = _make_color_mesh(zone_vertices, zone_colors)

	var good_vertices := PackedVector2Array()
	var good_colors := PackedColorArray()
	for i: int in pack.cell_count():
		var good_id: int = pack.good[i]
		if good_id <= 0 or good_id > FmgGoods.GOODS_DATA.size():
			continue
		var color: Color = Color.html(FmgGoods.GOODS_DATA[good_id - 1]["color"])
		var p: Vector2 = pack.points[i]
		var a := p + Vector2(-1.4, -1.4)
		var b := p + Vector2(1.4, -1.4)
		var c := p + Vector2(1.4, 1.4)
		var d := p + Vector2(-1.4, 1.4)
		var inner_a := p + Vector2(-0.7, -0.7)
		var inner_b := p + Vector2(0.7, -0.7)
		var inner_c := p + Vector2(0.7, 0.7)
		var inner_d := p + Vector2(-0.7, 0.7)
		var dark := color.darkened(0.35)
		for tri: Array in [[a, b, c], [a, c, d]]:
			for point: Vector2 in tri:
				good_vertices.append(point)
				good_colors.append(dark)
		for tri: Array in [[inner_a, inner_b, inner_c], [inner_a, inner_c, inner_d]]:
			for point: Vector2 in tri:
				good_vertices.append(point)
				good_colors.append(color)
	_goods_mesh = _make_color_mesh(good_vertices, good_colors)

	# Relief glyphs are also static. Batch the many small tree triangles and
	# mountain strokes so dense maps do not turn their icons into thousands of
	# individual CanvasItem commands.
	var tree_vertices := PackedVector2Array()
	var tree_colors := PackedColorArray()
	var tree_color := Color(0.15, 0.35, 0.15, 0.5)
	for p: Vector2 in _mountain_points:
		_mountain_segments.append(p + Vector2(-2.6, 1.6))
		_mountain_segments.append(p + Vector2(0, -2.6))
		_mountain_segments.append(p + Vector2(0, -2.6))
		_mountain_segments.append(p + Vector2(2.6, 1.6))
	for p: Vector2 in _tree_points:
		_tree_stem_segments.append(p + Vector2(0, 1.4))
		_tree_stem_segments.append(p + Vector2(0, 0.2))
		var pts := PackedVector2Array([
			p + Vector2(-1.3, 0.6), p + Vector2(0, -1.8), p + Vector2(1.3, 0.6)
		])
		tree_vertices.append_array(pts)
		tree_colors.append(tree_color)
		tree_colors.append(tree_color)
		tree_colors.append(tree_color)
	_tree_mesh = _make_color_mesh(tree_vertices, tree_colors)


func _draw_mesh(mesh: ArrayMesh) -> void:
	if mesh != null:
		draw_mesh(mesh, Transform2D.IDENTITY, Color.WHITE)


func queue_redraw_all() -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.pack == null:
		return
	# --- ocean ---
	draw_rect(Rect2(-sim.map_width, -sim.map_height, sim.map_width * 3.0, sim.map_height * 3.0), COL_OCEAN)
	for ring: Dictionary in _ocean_rings:
		var alpha: float = 0.5 + 0.1 * absf(int(ring["t"]))
		var col := COL_OCEAN_OUTLINE
		col.a = clampf(0.9 - alpha * 0.12, 0.15, 0.6)
		for points: PackedVector2Array in ring["rings"]:
			var closed := PackedVector2Array(points)
			if closed.size() > 1:
				closed.append(closed[0])
				draw_polyline(closed, col, 1.2, true)

	# --- landmasses ---
	var land_color := COL_LAND
	for ring: Dictionary in _land_rings:
		var fill_pts := PackedVector2Array(ring["points"])
		if fill_pts.size() > 1:
			fill_pts.remove_at(fill_pts.size() - 1)
		if fill_pts.size() >= 3:
			draw_colored_polygon(fill_pts, land_color)

	# --- lakes ---
	for ring: Dictionary in _lake_rings:
		var pts := PackedVector2Array(ring["points"])
		draw_colored_polygon(PackedVector2Array(pts.slice(0, pts.size() - 1)) if pts.size() > 3 else pts, COL_LAKE)
		draw_polyline(pts, COL_LAKE_SHORE, 0.8, true)

	# --- cell-based overlays (under rivers, over land) ---
	if show_heights:
		_draw_mesh(_height_mesh)
	elif show_cultures:
		_draw_mesh(_culture_mesh)
	elif show_religions:
		_draw_mesh(_religion_mesh)
	else:
		if show_biomes:
			_draw_mesh(_biome_mesh)
		if show_relief:
			_draw_mesh(_relief_mesh)
		if show_politics:
			_draw_mesh(_state_mesh)
		if show_provinces:
			_draw_mesh(_province_mesh)

	# --- ice (glaciers on land, icebergs on water) ---
	if show_ice:
		_draw_ice()

	# --- zones (translucent named areas) ---
	if show_zones:
		_draw_mesh(_zones_mesh)

	# --- goods (resource dots) ---
	if show_goods:
		_draw_mesh(_goods_mesh)

	if show_cell_borders:
		_draw_cell_borders()
	if show_provinces:
		_draw_province_borders()
	if show_borders:
		_draw_state_borders()

	# --- coastlines (strokes on top of fills) ---
	for ring: Dictionary in _land_rings:
		draw_polyline(ring["points"], COL_COAST, 1.0, true)
	for ring: Dictionary in _lake_rings:
		draw_polyline(ring["points"], COL_COAST, 0.7, true)

	# --- rivers ---
	if show_rivers:
		for entry: Dictionary in _river_polys:
			draw_colored_polygon(entry["points"], COL_RIVER)

	# --- relief icons (mountains and forests) ---
	if show_relief_icons:
		_draw_relief_icons()

	# --- routes (roads, trails, sea routes) ---
	if show_routes:
		_draw_routes()
		_draw_journeys()

	# --- burgs ---
	if show_burgs:
		_draw_burgs()

	# --- emblems (heraldry shields at state poles) ---
	if show_emblems:
		_draw_emblems()

	# --- armies ---
	if show_armies:
		_draw_armies()

	# --- markers (points of interest) ---
	if show_markers:
		_draw_markers()

	# --- labels ---
	if show_labels:
		_draw_labels()

	# --- feature labels (oceans, seas, lakes, islands) ---
	if show_feature_labels:
		_draw_feature_labels()

	# --- province labels ---
	if show_province_labels:
		_draw_province_labels()


func _cell_color_safe(_cell_id: int) -> Color:
	return Color.WHITE


func _draw_cell_overlay(color_fn: Callable, alpha: float) -> void:
	# Kept as a small fallback for tools that call this method directly. Normal
	# rendering uses the prebuilt meshes above.
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var color: Color = color_fn.call(i)
		if color.a <= 0.0:
			continue
		color.a *= alpha
		var poly: PackedVector2Array = _cell_polygons[i]
		if poly.size() >= 3:
			draw_colored_polygon(poly, color)


func _draw_relief_shading() -> void:
	# Compatibility wrapper for callers from older scenes. The actual render
	# path is the cached relief mesh.
	_draw_mesh(_relief_mesh)


func _cell_biome_color(i: int) -> Color:
	return Color.html(FmgBiomes.COLORS[sim.pack.biome[i]])


func _cell_state_color(i: int) -> Color:
	var s: int = sim.pack.state[i]
	if s == 0 or s >= sim.pack.states.size():
		return Color(0, 0, 0, 0)
	var color: String = sim.pack.states[s].get("color", "#cccccc")
	return Color.html(color)


func _cell_province_color(i: int) -> Color:
	var p: int = sim.pack.province[i]
	if p == 0 or p >= sim.pack.provinces.size():
		return Color(0, 0, 0, 0)
	return Color.html(sim.pack.provinces[p].get("color", "#cccccc"))


func _cell_culture_color(i: int) -> Color:
	var c: int = sim.pack.culture[i]
	if c == 0 or c >= sim.pack.cultures.size():
		return Color(0, 0, 0, 0)
	return Color.html(sim.pack.cultures[c].get("color", "#cccccc"))


func _cell_religion_color(i: int) -> Color:
	var r: int = sim.pack.religion[i]
	if r == 0 or r >= sim.pack.religions.size():
		return Color(0, 0, 0, 0)
	return Color.html(sim.pack.religions[r].get("color", "#cccccc"))


func _cell_height_color(i: int) -> Color:
	var h: float = float(sim.pack.h[i])
	if h < 20.0:
		var depth: float = clampf(h / 20.0, 0.0, 1.0)
		return COL_OCEAN_DEEP.lerp(COL_OCEAN, depth)
	var t: float = clampf((h - 20.0) / 80.0, 0.0, 1.0)
	var seg: float = t * float(HYPSO.size() - 1)
	var idx: int = mini(int(seg), HYPSO.size() - 2)
	return HYPSO[idx].lerp(HYPSO[idx + 1], seg - float(idx))


func _build_border_segments() -> void:
	var pack: FmgGraph = sim.pack
	var vertices := pack.voronoi.vertices
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		for n: int in pack.c[i]:
			if n < i or pack.h[n] < 20:
				continue
			var common := _common_edge_vertices(pack, i, n)
			if common.size() < 2:
				continue
			var a: Vector2 = vertices.p[common[0]]
			var b: Vector2 = vertices.p[common[1]]
			_cell_border_segments.append(a)
			_cell_border_segments.append(b)
			if pack.state[i] != pack.state[n]:
				_border_segments.append(a)
				_border_segments.append(b)
			if pack.province[i] != pack.province[n]:
				_province_border_segments.append(a)
				_province_border_segments.append(b)


func _common_edge_vertices(pack: FmgGraph, first: int, second: int) -> PackedInt32Array:
	var common := PackedInt32Array()
	for vertex_id: int in pack.v[first]:
		if pack.v[second].has(vertex_id):
			common.append(vertex_id)
	return common


func _draw_cell_borders() -> void:
	if not _cell_border_segments.is_empty():
		draw_multiline(_cell_border_segments, Color(0, 0, 0, 0.15), 0.5, true)


func _draw_state_borders() -> void:
	if not _border_segments.is_empty():
		draw_multiline(_border_segments, COL_BORDER, 1.4, true)


func _draw_province_borders() -> void:
	if not _province_border_segments.is_empty():
		draw_multiline(_province_border_segments, COL_PROVINCE_BORDER, 0.8, true)


func _draw_burgs() -> void:
	for b in sim.pack.burgs:
		if b == null:
			continue
		var pos := Vector2(b["x"], b["y"])
		var is_capital: bool = b.get("capital", 0) == 1
		var is_port: bool = int(b.get("port", 0)) != 0
		if is_capital:
			draw_circle(pos, 2.6, Color("#7a1f1f"))
			draw_arc(pos, 3.4, 0.0, TAU, 12, Color("#3d1010"), 0.9, true)
		else:
			draw_circle(pos, 1.7, Color("#3d2b1f"))
		if is_port:
			draw_arc(pos, 4.6, -0.6, 1.8, 10, Color("#23405e"), 1.0, true)


func _draw_labels() -> void:
	# state labels at poles of inaccessibility
	for state in sim.pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		if not sim.poles_cache.has(state["i"]):
			continue
		var pole: Vector2 = sim.poles_cache[state["i"]]
		var cells: int = state.get("cells", 10)
		var font_size: float = clampf(sqrt(float(cells)) * 2.2, 9.0, 34.0)
		var name_v: String = state.get("fullName", state["name"])
		var width: float = _font.get_string_size(name_v, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size)).x
		draw_string_outline(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), 3, COL_TEXT_OUT)
		draw_string(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), COL_TEXT)

	# burg labels
	for b in sim.pack.burgs:
		if b == null:
			continue
		var pop: float = float(b.get("population", 0.0))
		var is_capital: bool = b.get("capital", 0) == 1
		if pop < 2.0 and not is_capital:
			continue
		var font_size: float = 4.5 if is_capital else clampf(2.5 + pop / 12.0, 3.0, 5.0)
		var pos := Vector2(b["x"], b["y"]) + Vector2(0, 4.0 + font_size * 0.9)
		draw_string_outline(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size), 2, COL_TEXT_OUT)
		draw_string(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size), COL_TEXT)


# ---------------------------------------------------------------------------
# Second-contour layers (ice, goods, routes, markers, armies, zones,
# emblems, feature/province labels, relief icons)

func _build_feature_labels() -> void:
	var pack: FmgGraph = sim.pack
	for feature in pack.features:
		if feature == null or feature.is_empty():
			continue
		var name_v: String = feature.get("name", "")
		if name_v == "":
			continue
		var type: String = feature.get("type", "")
		if type != "ocean" and type != "lake" and type != "island":
			continue
		if type == "island" and int(feature.get("cells", 0)) < 8:
			continue
		var pos: Vector2
		if type == "ocean":
			# ocean features carry no vertex chain in this port — average the
			# feature's water cells, biased to the inner map rectangle
			pos = _ocean_label_position(int(feature["i"]))
			if pos == Vector2.ZERO:
				continue
		else:
			var chain: PackedInt32Array = feature.get("vertices", PackedInt32Array())
			if chain.size() < 3:
				continue
			var acc := Vector2.ZERO
			var count: int = 0
			for v: int in chain:
				var p: Vector2 = pack.voronoi.vertices.p[v]
				if p.x > 8.0 and p.x < sim.map_width - 8.0 and p.y > 8.0 and p.y < sim.map_height - 8.0:
					acc += p
					count += 1
			if count < 3:
				for v: int in chain:
					acc += pack.voronoi.vertices.p[v]
				count = chain.size()
			pos = acc / float(count)
		var cells: float = float(feature.get("cells", 0))
		var size: float
		var color: Color
		if type == "ocean":
			size = clampf(sqrt(cells) * 2.0, 16.0, 40.0)
			color = Color("#cfe0f2")
		elif type == "lake":
			size = clampf(sqrt(cells) * 1.6, 8.0, 18.0)
			color = Color("#dbe8f5")
		elif feature.get("subtype", "") == "continent":
			size = clampf(sqrt(cells) * 0.9, 9.0, 24.0)
			color = COL_TEXT
		else:
			size = clampf(sqrt(cells) * 1.1, 7.0, 15.0)
			color = COL_TEXT
		_feature_labels.append({"name": name_v, "pos": pos, "size": size, "color": color, "type": type})


## Average position of a feature's water cells inside the inner map area.
func _ocean_label_position(feature_id: int) -> Vector2:
	var pack: FmgGraph = sim.pack
	var margin: float = 30.0
	var acc := Vector2.ZERO
	var count: int = 0
	for i: int in pack.cell_count():
		if pack.h[i] >= 20 or pack.f[i] != feature_id:
			continue
		var p: Vector2 = pack.points[i]
		if p.x > margin and p.x < sim.map_width - margin and p.y > margin and p.y < sim.map_height - margin:
			acc += p
			count += 1
	if count == 0:
		return Vector2.ZERO
	return acc / float(count)


func _build_relief_icons() -> void:
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var jitter := Vector2(float((i * 7919) % 11) - 5.0, float((i * 104729) % 11) - 5.0) * 0.35
		if pack.h[i] >= 70:
			_mountain_points.append(pack.points[i] + jitter)
		elif [5, 6, 7, 8, 9].has(pack.biome[i]) and i % 3 == 0:
			_tree_points.append(pack.points[i] + jitter)


func _draw_ice() -> void:
	var pack: FmgGraph = sim.pack
	for ice: Variant in pack.ice:
		var e: Dictionary = ice
		var points: PackedVector2Array = e.get("points", PackedVector2Array())
		if points.size() < 3:
			continue
		draw_colored_polygon(points, Color(0.94, 0.97, 1.0, 0.92))
		var outline := PackedVector2Array(points)
		outline.append(points[0])
		draw_polyline(outline, Color(0.8, 0.88, 0.96, 0.9), 0.6, true)


func _draw_goods() -> void:
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		var good_id: int = pack.good[i]
		if good_id <= 0 or good_id > FmgGoods.GOODS_DATA.size():
			continue
		var color: Color = Color.html(FmgGoods.GOODS_DATA[good_id - 1]["color"])
		var p: Vector2 = pack.points[i]
		var rect := Rect2(p - Vector2(1.4, 1.4), Vector2(2.8, 2.8))
		draw_rect(rect, color.darkened(0.35), false, 0.4, true)
		draw_rect(rect.grow(-0.7), color, true)


func _draw_zones() -> void:
	var pack: FmgGraph = sim.pack
	for zone: Variant in pack.zones:
		var z: Dictionary = zone
		var color: Color = Color.html(z.get("color", "#888888"))
		color.a = 0.16
		for cell_id: Variant in z.get("cells", []):
			var cid: int = int(cell_id)
			if cid < 0 or cid >= pack.cell_count():
				continue
			var poly := pack.get_polygon(cid)
			if poly.size() >= 3:
				draw_colored_polygon(poly, color)


func _build_route_segments() -> void:
	var pack: FmgGraph = sim.pack
	for route_value: Variant in pack.routes:
		var route: Dictionary = route_value
		var points: PackedVector2Array = route.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		match route.get("group", ""):
			"searoutes":
				_sea_route_segments.append_array(_dashed_segments(points, 6.0, 3.0))
			"roads":
				_road_segments.append_array(_line_segments(points))
			_:
				_trail_segments.append_array(_dashed_segments(points, 3.0, 2.0))
	for journey_value: Variant in pack.journeys:
		var journey: Dictionary = journey_value
		var points: PackedVector2Array = journey.get("points", PackedVector2Array())
		if points.size() >= 2:
			_journey_segments.append_array(_dashed_segments(points, 5.0, 3.0))


func _line_segments(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i: int in points.size() - 1:
		result.append(points[i])
		result.append(points[i + 1])
	return result


func _dashed_segments(points: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var cycle: float = dash + gap
	var acc: float = 0.0
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var t: float = 0.0
		while t < seg_len:
			var pos_in_cycle: float = fmod(acc, cycle)
			var drawing: bool = pos_in_cycle < dash
			var remaining_in_phase: float = (dash - pos_in_cycle) if drawing else (cycle - pos_in_cycle)
			var step: float = minf(remaining_in_phase, seg_len - t)
			if drawing:
				result.append(a.lerp(b, t / seg_len))
				result.append(a.lerp(b, (t + step) / seg_len))
			t += step
			acc += step
	return result


func _draw_routes() -> void:
	# Every array contains line pairs, so a whole route layer is one draw call.
	if not _sea_route_segments.is_empty():
		draw_multiline(_sea_route_segments, Color("#4a7ab5"), 0.7, true)
	if not _road_segments.is_empty():
		draw_multiline(_road_segments, Color("#7a5c3e"), 1.1, true)
	if not _trail_segments.is_empty():
		draw_multiline(_trail_segments, Color("#8a7355"), 0.6, true)


func _draw_journeys() -> void:
	if not _journey_segments.is_empty():
		draw_multiline(_journey_segments, Color("#c0392b"), 1.2, true)


func _draw_dashed(points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var cycle: float = dash + gap
	var acc: float = 0.0
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var t: float = 0.0
		while t < seg_len:
			var pos_in_cycle: float = fmod(acc, cycle)
			var drawing: bool = pos_in_cycle < dash
			var remaining_in_phase: float = (dash - pos_in_cycle) if drawing else (cycle - pos_in_cycle)
			var step: float = minf(remaining_in_phase, seg_len - t)
			if drawing:
				draw_line(a.lerp(b, t / seg_len), a.lerp(b, (t + step) / seg_len), color, width, true)
			t += step
			acc += step


func _draw_markers() -> void:
	var pack: FmgGraph = sim.pack
	for marker: Variant in pack.markers:
		var m: Dictionary = marker
		var pos := Vector2(float(m.get("x", 0.0)), float(m.get("y", 0.0)))
		var mtype: String = m.get("type", "")
		var color := Color("#8b4513")
		if mtype.contains("monster") or mtype == "pirates":
			color = Color("#5e3b8a")
		elif mtype.contains("sacred") or mtype == "portals":
			color = Color("#b8860b")
		elif mtype == "volcanoes" or mtype == "battlefields":
			color = Color("#a02c2c")
		elif mtype.contains("water") or mtype == "waterfalls" or mtype == "lighthouses":
			color = Color("#2b6cb0")
		elif mtype == "mines" or mtype == "dungeons" or mtype == "caves":
			color = Color("#4a4a4a")
		var pts := PackedVector2Array([
			pos + Vector2(0, -2.4), pos + Vector2(2.4, 0),
			pos + Vector2(0, 2.4), pos + Vector2(-2.4, 0)
		])
		draw_colored_polygon(pts, color)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.5), 0.5, true)


func _draw_armies() -> void:
	var pack: FmgGraph = sim.pack
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		var color: Color = Color.html(state.get("color", "#888888"))
		for regiment: Variant in state.get("military", []):
			var reg: Dictionary = regiment
			var pos := Vector2(float(reg.get("x", 0.0)), float(reg.get("y", 0.0)))
			var troops: int = int(reg.get("a", 0))
			var size: float = clampf(1.5 + sqrt(float(troops)) / 30.0, 1.5, 4.0)
			if int(reg.get("n", 0)) == 1:
				draw_circle(pos, size, Color("#23405e"))
				draw_arc(pos, size, 0.0, TAU, 8, Color("#cfe0f2"), 0.5, true)
			else:
				draw_rect(Rect2(pos - Vector2(size, size * 0.8), Vector2(size * 2.0, size * 1.6)), color.darkened(0.2), true)
				draw_rect(Rect2(pos - Vector2(size, size * 0.8), Vector2(size * 2.0, size * 1.6)), Color(0, 0, 0, 0.6), false, 0.4, true)


func _draw_emblems() -> void:
	var pack: FmgGraph = sim.pack
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0 or not state.has("co"):
			continue
		if not sim.poles_cache.has(state["i"]):
			continue
		var pole: Vector2 = sim.poles_cache[state["i"]]
		var cells: int = state.get("cells", 10)
		var label_size: float = clampf(sqrt(float(cells)) * 2.2, 9.0, 34.0)
		var pos: Vector2 = pole + Vector2(0.0, label_size * 1.1)
		_draw_shield(state["co"], pos, clampf(label_size * 0.55, 6.0, 18.0))


func _draw_shield(coa: Dictionary, pos: Vector2, size: float) -> void:
	var t1: Color = Color.html(FmgEmblems.TINCTURE_COLORS.get(coa.get("t1", "argent"), "#fafafa"))
	var w: float = size * 0.8
	var h: float = size
	# heater shield outline
	var outline := PackedVector2Array([
		pos + Vector2(-w, -h * 0.55), pos + Vector2(w, -h * 0.55),
		pos + Vector2(w, h * 0.1), pos + Vector2(0.0, h * 0.6), pos + Vector2(-w, h * 0.1)
	])
	draw_colored_polygon(outline, t1)
	var division: Dictionary = coa.get("division", {})
	if not division.is_empty():
		var t2: Color = Color.html(FmgEmblems.TINCTURE_COLORS.get(division.get("t", "gules"), "#d7374a"))
		var div_type: String = division.get("division", "")
		var half := PackedVector2Array()
		match div_type:
			"perPale":
				half = PackedVector2Array([pos + Vector2(0, -h * 0.55), pos + Vector2(w, -h * 0.55), pos + Vector2(w, h * 0.1), pos + Vector2(0, h * 0.6)])
			"perFess":
				half = PackedVector2Array([pos + Vector2(-w, 0.0), pos + Vector2(w, 0.0), pos + Vector2(w, h * 0.1), pos + Vector2(0.0, h * 0.6), pos + Vector2(-w, h * 0.1)])
			"perBend":
				half = PackedVector2Array([pos + Vector2(w, -h * 0.55), pos + Vector2(w, h * 0.1), pos + Vector2(0.0, h * 0.6), pos + Vector2(-w, -h * 0.55)])
			"perChevron", "perChevronReversed":
				half = PackedVector2Array([pos + Vector2(-w, h * 0.1), pos + Vector2(0.0, -h * 0.1), pos + Vector2(w, h * 0.1), pos + Vector2(0.0, h * 0.6)])
			"perCross":
				draw_rect(Rect2(pos + Vector2(0.0, -h * 0.55), Vector2(w, h * 0.55)), t2, true)
				draw_rect(Rect2(pos + Vector2(-w, 0.0), Vector2(w, h * 0.6)), t2, true)
			_:
				half = PackedVector2Array([pos + Vector2(0, -h * 0.55), pos + Vector2(w, -h * 0.55), pos + Vector2(w, h * 0.1), pos + Vector2(0, h * 0.6)])
		if half.size() >= 3:
			draw_colored_polygon(half, t2)
	var ordinaries: Array = coa.get("ordinaries", [])
	if not ordinaries.is_empty():
		var ord: Dictionary = ordinaries[0]
		var t_ord: Color = Color.html(FmgEmblems.TINCTURE_COLORS.get(ord.get("t", "gules"), "#d7374a"))
		match ord.get("ordinary", ""):
			"fess":
				draw_rect(Rect2(pos + Vector2(-w, -h * 0.18), Vector2(w * 2.0, h * 0.36)), t_ord, true)
			"pale":
				draw_rect(Rect2(pos + Vector2(-w * 0.25, -h * 0.55), Vector2(w * 0.5, h * 1.1)), t_ord, true)
			"bend":
				draw_line(pos + Vector2(-w, -h * 0.55), pos + Vector2(w, h * 0.3), t_ord, size * 0.2, true)
			"cross":
				draw_rect(Rect2(pos + Vector2(-w * 0.15, -h * 0.55), Vector2(w * 0.3, h * 1.1)), t_ord, true)
				draw_rect(Rect2(pos + Vector2(-w, -h * 0.15), Vector2(w * 2.0, h * 0.3)), t_ord, true)
			"chief":
				draw_rect(Rect2(pos + Vector2(-w, -h * 0.55), Vector2(w * 2.0, h * 0.3)), t_ord, true)
	var charges: Array = coa.get("charges", [])
	if not charges.is_empty():
		var charge: Dictionary = charges[0]
		var tc: Color = Color.html(FmgEmblems.TINCTURE_COLORS.get(charge.get("t", "sable"), "#333333"))
		_draw_charge(charge.get("charge", ""), pos, size * 0.3, tc)
	var closed := PackedVector2Array(outline)
	closed.append(outline[0])
	draw_polyline(closed, Color(0.1, 0.1, 0.1, 0.8), size * 0.06, true)


func _draw_charge(charge: String, pos: Vector2, r: float, color: Color) -> void:
	match charge:
		"Star", "Sun":
			var pts := PackedVector2Array()
			for k: int in 10:
				var angle: float = float(k) * TAU / 10.0 - PI / 2.0
				var radius: float = r if k % 2 == 0 else r * 0.45
				pts.append(pos + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(pts, color)
		"Moon":
			draw_circle(pos, r * 0.8, color)
			draw_circle(pos + Vector2(r * 0.4, -r * 0.2), r * 0.7, Color(0, 0, 0, 0))
		"Cross":
			draw_rect(Rect2(pos + Vector2(-r * 0.25, -r), Vector2(r * 0.5, r * 2.0)), color, true)
			draw_rect(Rect2(pos + Vector2(-r, -r * 0.25), Vector2(r * 2.0, r * 0.5)), color, true)
		"Tower", "Castle":
			draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.4), Vector2(r * 1.2, r * 1.2)), color, true)
			draw_rect(Rect2(pos + Vector2(-r * 0.6, -r * 0.8), Vector2(r * 0.3, r * 0.4)), color, true)
			draw_rect(Rect2(pos + Vector2(r * 0.3, -r * 0.8), Vector2(r * 0.3, r * 0.4)), color, true)
		"Crown":
			var pts := PackedVector2Array([
				pos + Vector2(-r, r * 0.5), pos + Vector2(-r, -r * 0.2), pos + Vector2(-r * 0.4, r * 0.1),
				pos + Vector2(0.0, -r * 0.6), pos + Vector2(r * 0.4, r * 0.1), pos + Vector2(r, -r * 0.2),
				pos + Vector2(r, r * 0.5)
			])
			draw_colored_polygon(pts, color)
		"Sword", "Axe", "Key":
			draw_line(pos + Vector2(0, -r), pos + Vector2(0, r), color, r * 0.3, true)
			draw_line(pos + Vector2(-r * 0.5, -r * 0.4), pos + Vector2(r * 0.5, -r * 0.4), color, r * 0.3, true)
		_:
			draw_circle(pos, r * 0.55, color)


func _draw_relief_icons() -> void:
	if not _mountain_segments.is_empty():
		draw_multiline(_mountain_segments, Color(0.35, 0.3, 0.25, 0.55), 0.7, true)
	if not _tree_stem_segments.is_empty():
		draw_multiline(_tree_stem_segments, Color(0.15, 0.35, 0.15, 0.5), 0.6, true)
	_draw_mesh(_tree_mesh)


func _draw_feature_labels() -> void:
	for label: Dictionary in _feature_labels:
		var name_v: String = label["name"]
		var pos: Vector2 = label["pos"]
		var font_size: int = int(label["size"])
		var color: Color = label["color"]
		var width: float = _font.get_string_size(name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var start := pos + Vector2(-width / 2.0, font_size * 0.35)
		var out_col: Color = Color(0.1, 0.15, 0.2, 0.55) if label["type"] == "island" else Color(0.05, 0.1, 0.2, 0.4)
		draw_string_outline(_font, start, name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, out_col)
		draw_string(_font, start, name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_province_labels() -> void:
	var pack: FmgGraph = sim.pack
	for province in pack.provinces:
		if province == null:
			continue
		var burg_id: int = int(province.get("burg", 0))
		if burg_id <= 0 or burg_id >= pack.burgs.size() or pack.burgs[burg_id] == null:
			continue
		var burg: Dictionary = pack.burgs[burg_id]
		var pos := Vector2(burg["x"], burg["y"]) + Vector2(0.0, 8.0)
		var name_v: String = province.get("fullName", province.get("name", ""))
		draw_string_outline(_font, pos, name_v, HORIZONTAL_ALIGNMENT_CENTER, -1, 5, 2, COL_TEXT_OUT)
		draw_string(_font, pos, name_v, HORIZONTAL_ALIGNMENT_CENTER, -1, 5, Color(0.2, 0.2, 0.3, 0.8))
