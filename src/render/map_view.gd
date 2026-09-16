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

# --- style (edited live from the Style tab; defaults follow the original) ---
var style_ocean := COL_OCEAN
var style_ocean_deep := COL_OCEAN_DEEP
var style_ocean_outline := COL_OCEAN_OUTLINE
var style_land := COL_LAND
var style_lake := COL_LAKE
var style_river := COL_RIVER
var style_coast := COL_COAST
var style_border := COL_BORDER
var style_road := Color("#7a5c3e")
var style_trail := Color("#8a7355")
var style_searoute := Color("#4a7ab5")
var style_text := COL_TEXT
var style_ice := Color(0.94, 0.97, 1.0, 0.92)
var style_coast_width := 1.0
var style_border_width := 1.4
var style_road_width := 1.1
var style_label_scale := 1.0
var distance_scale := 3.0 # kilometers per map pixel (Units ▸ distance scale)

# layer toggles — defaults follow the original's "political" layers preset
var show_politics: bool = true
var show_biomes: bool = false
var show_heights: bool = false
var show_cultures: bool = false
var show_religions: bool = false
var show_provinces: bool = false
var show_rivers: bool = true
var show_lakes: bool = true
var show_borders: bool = true
var show_labels: bool = true
var show_burgs: bool = true
var show_relief: bool = false # hillshading-ish height tint over biomes
var show_ice: bool = true
var show_routes: bool = true
var show_feature_labels: bool = true # oceans, seas, lakes, islands
var show_province_labels: bool = false
var show_markers: bool = false
var show_armies: bool = false
var show_zones: bool = false
var show_goods: bool = false
var show_emblems: bool = false
var show_relief_icons: bool = false # mountain and forest glyphs
var show_cell_borders: bool = false # debug
# second data-contour layers (FMG parity)
var show_temperature: bool = false
var show_precipitation: bool = false
var show_population: bool = false
var show_markets: bool = false
var show_trade: bool = false
var show_journeys: bool = true
# map furniture (FMG parity)
var show_grid: bool = false
var show_coordinates: bool = false
var show_compass: bool = false
var show_scale_bar: bool = true
var show_vignette: bool = true
var show_rulers: bool = false
var ruler_points := PackedVector2Array()

# cached geometry
var _land_rings: Array = [] # {points, feature}
var _lake_rings: Array = []
var _ocean_rings: Array = [] # {t, rings}
var _river_polys: Array = [] # {points, river} — ribbons that triangulate cleanly
var _river_strokes: Array = [] # {points, widths} — self-intersecting ribbons, drawn as tapered strokes
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

# second-contour data layers (temperature, precipitation, population, markets)
var _temperature_mesh: ArrayMesh = null
var _precipitation_mesh: ArrayMesh = null
var _population_mesh: ArrayMesh = null
var _market_mesh: ArrayMesh = null
var _market_centers: Array = [] # {pos, name, color, i}
var _trade_segments: PackedVector2Array = PackedVector2Array()
var _vignette_texture: Texture2D = null

# Static geometry that used to be submitted once per island, river or glacier.
# It is triangulated into a single mesh per visual layer without changing the
# source polygons or their colors.
var _land_mesh: ArrayMesh = null
var _lake_mesh: ArrayMesh = null
var _river_mesh: ArrayMesh = null
var _ice_mesh: ArrayMesh = null
var _coast_segments: PackedVector2Array = PackedVector2Array()
var _lake_shore_segments: PackedVector2Array = PackedVector2Array()
var _ice_outline_segments: PackedVector2Array = PackedVector2Array()
var _ocean_outline_segments: Dictionary = {}

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
	_river_strokes = []
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
	_temperature_mesh = null
	_precipitation_mesh = null
	_population_mesh = null
	_market_mesh = null
	_market_centers = []
	_trade_segments = PackedVector2Array()
	_land_mesh = null
	_lake_mesh = null
	_river_mesh = null
	_ice_mesh = null
	_coast_segments = PackedVector2Array()
	_lake_shore_segments = PackedVector2Array()
	_ice_outline_segments = PackedVector2Array()
	_ocean_outline_segments = {}
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
			if poly.size() < 3:
				continue
			# Self-intersecting meander loops cannot be triangulated; those
			# rivers are rendered as tapered centerline strokes instead, so no
			# river is ever silently dropped (upstream SVG fills tolerate the
			# self-intersections, Godot meshes do not).
			var probe := PackedVector2Array(poly)
			if probe.size() > 1 and probe[0].distance_squared_to(probe[probe.size() - 1]) < 0.0001:
				probe.remove_at(probe.size() - 1)
			if Geometry2D.triangulate_polygon(probe).size() >= 3:
				_river_polys.append({"points": poly, "river": river})
			else:
				var stroke: Dictionary = sim.hydrology.get_river_stroke(river)
				if not stroke.is_empty():
					_river_strokes.append(stroke)

	# The rest of the render data is immutable until the next generation. Build
	# it here rather than in _draw(), so toggling a layer only changes a single
	# mesh draw call and never walks the complete Voronoi graph again.
	_build_static_geometry()
	_build_overlay_meshes()
	_build_border_segments()
	_build_route_segments()
	_build_data_meshes()
	_build_vignette_texture()

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


## Triangulates a polygon with Geometry2D instead of a fan, so concave river
## and coastline polygons retain exactly the same fill as draw_colored_polygon.
func _append_polygon_mesh(data: Dictionary, polygon: PackedVector2Array, color: Color) -> void:
	var points := PackedVector2Array(polygon)
	if points.size() > 1 and points[0].distance_squared_to(points[points.size() - 1]) < 0.0001:
		points.remove_at(points.size() - 1)
	if points.size() < 3:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if indices.size() < 3:
		return
	var vertices: PackedVector2Array = data["vertices"]
	var colors: PackedColorArray = data["colors"]
	for i: int in indices.size():
		vertices.append(points[indices[i]])
		colors.append(color)
	data["vertices"] = vertices
	data["colors"] = colors


func _polygon_mesh(polygons: Array, color: Color) -> ArrayMesh:
	var data := {"vertices": PackedVector2Array(), "colors": PackedColorArray()}
	for polygon_value: Variant in polygons:
		var polygon: PackedVector2Array = polygon_value
		_append_polygon_mesh(data, polygon, color)
	var vertices: PackedVector2Array = data["vertices"]
	var colors: PackedColorArray = data["colors"]
	return _make_color_mesh(vertices, colors)


func _closed_line_segments(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array(points)
	if closed.size() > 1 and closed[0].distance_squared_to(closed[closed.size() - 1]) >= 0.0001:
		closed.append(closed[0])
	return _line_segments(closed)


func _build_static_geometry() -> void:
	var land_polygons: Array = []
	for ring: Dictionary in _land_rings:
		land_polygons.append(ring["points"])
		_coast_segments.append_array(_closed_line_segments(ring["points"]))
	# Baked white and tinted at draw time so the Style tab can recolor the
	# basemap without a geometry rebuild.
	_land_mesh = _polygon_mesh(land_polygons, Color.WHITE)

	var lake_polygons: Array = []
	for ring: Dictionary in _lake_rings:
		lake_polygons.append(ring["points"])
		_lake_shore_segments.append_array(_closed_line_segments(ring["points"]))
	_lake_mesh = _polygon_mesh(lake_polygons, Color.WHITE)

	var river_polygons: Array = []
	for entry: Dictionary in _river_polys:
		river_polygons.append(entry["points"])
	_river_mesh = _polygon_mesh(river_polygons, Color.WHITE)

	# Ocean outline colors depend on the distance level, so keep one batched
	# line list per level (five calls instead of one call per outline ring).
	for ring: Dictionary in _ocean_rings:
		var level: int = int(ring["t"])
		var segments: PackedVector2Array = _ocean_outline_segments.get(level, PackedVector2Array())
		for points: PackedVector2Array in ring["rings"]:
			segments.append_array(_closed_line_segments(points))
		_ocean_outline_segments[level] = segments

	var ice_polygons: Array = []
	for ice_value: Variant in sim.pack.ice:
		var ice: Dictionary = ice_value
		var points: PackedVector2Array = ice.get("points", PackedVector2Array())
		if points.size() < 3:
			continue
		ice_polygons.append(points)
		_ice_outline_segments.append_array(_closed_line_segments(points))
	_ice_mesh = _polygon_mesh(ice_polygons, Color.WHITE)


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
		# Godot 4.7 signature: draw_mesh(mesh, texture, transform, modulate).
		# Vertex colors are baked into the mesh, so no texture and identity/white defaults apply.
		draw_mesh(mesh, null)


## Draws a mesh whose polygons were baked white, tinting it with a live style
## color. This is what lets the Style tab recolor ocean/land/lakes/rivers
## without rebuilding any geometry.
## Draws a polyline whose width varies per point (quad per segment + round
## joints) — used for rivers whose ribbon polygon self-intersects.
func _draw_tapered_stroke(points: PackedVector2Array, widths: PackedFloat32Array, color: Color) -> void:
	var n: int = points.size()
	if n == 0:
		return
	if n == 1:
		draw_circle(points[0], maxf(widths[0] * 0.5, 0.5), color)
		return
	var half_widths := PackedFloat32Array()
	half_widths.resize(n)
	for i: int in n:
		half_widths[i] = maxf(widths[i] * 0.5, 0.5)
	draw_circle(points[0], half_widths[0], color)
	for i: int in n - 1:
		var p0: Vector2 = points[i]
		var p1: Vector2 = points[i + 1]
		var dir: Vector2 = p1 - p0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var normal := Vector2(-dir.y, dir.x)
		var w0: float = half_widths[i]
		var w1: float = half_widths[i + 1]
		var quad := PackedVector2Array([
			p0 + normal * w0,
			p1 + normal * w1,
			p1 - normal * w1,
			p0 - normal * w0
		])
		draw_colored_polygon(quad, color)
		draw_circle(p1, w1, color)


func _draw_tinted(mesh: ArrayMesh, color: Color) -> void:
	if mesh != null:
		draw_mesh(mesh, null, Transform2D(), color)


func queue_redraw_all() -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.pack == null:
		return
	# --- ocean ---
	draw_rect(Rect2(-sim.map_width, -sim.map_height, sim.map_width * 3.0, sim.map_height * 3.0), style_ocean)
	for level_value: Variant in _ocean_outline_segments:
		var level: int = int(level_value)
		var alpha: float = 0.5 + 0.1 * absf(level)
		var col := style_ocean_outline
		col.a = clampf(0.9 - alpha * 0.12, 0.15, 0.6)
		var segments: PackedVector2Array = _ocean_outline_segments[level]
		if not segments.is_empty():
			draw_multiline(segments, col, 1.2, true)

	# --- landmasses ---
	_draw_tinted(_land_mesh, style_land)

	# --- lakes ---
	if show_lakes:
		_draw_tinted(_lake_mesh, style_lake)
		if not _lake_shore_segments.is_empty():
			draw_multiline(_lake_shore_segments, style_lake.lightened(0.12), 0.8, true)

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

	# --- data layers (temperature, precipitation, population, markets) ---
	if show_temperature:
		_draw_mesh(_temperature_mesh)
	if show_precipitation:
		_draw_mesh(_precipitation_mesh)
		_draw_wind_arrows()
	if show_population:
		_draw_mesh(_population_mesh)
	if show_markets:
		_draw_mesh(_market_mesh)
		_draw_market_centers()
	if show_trade:
		if not _trade_segments.is_empty():
			draw_multiline(_trade_segments, Color("#8a6d3b"), 0.5, true)

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
	if not _coast_segments.is_empty():
		draw_multiline(_coast_segments, style_coast, style_coast_width, true)
	if show_lakes and not _lake_shore_segments.is_empty():
		draw_multiline(_lake_shore_segments, style_coast, style_coast_width * 0.7, true)

	# --- rivers ---
	if show_rivers:
		_draw_tinted(_river_mesh, style_river)
		for stroke: Dictionary in _river_strokes:
			_draw_tapered_stroke(stroke["points"], stroke["widths"], style_river)

	# --- relief icons (mountains and forests) ---
	if show_relief_icons:
		_draw_relief_icons()

	# --- routes (roads, trails, sea routes) ---
	if show_routes:
		_draw_routes()
	if show_journeys:
		_draw_journeys()

	# --- coordinates graticule ---
	if show_coordinates:
		_draw_coordinates()

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

	# --- grid overlay ---
	if show_grid:
		_draw_grid()

	# --- labels ---
	if show_labels:
		_draw_labels()

	# --- feature labels (oceans, seas, lakes, islands) ---
	if show_feature_labels:
		_draw_feature_labels()

	# --- province labels ---
	if show_province_labels:
		_draw_province_labels()

	# --- rulers (measure tool) ---
	if show_rulers:
		_draw_rulers()

	# --- brush preview circle ---
	if brush_preview_visible:
		draw_arc(brush_preview_pos, brush_preview_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.75), 1.2, true)
		draw_arc(brush_preview_pos, brush_preview_radius, 0.0, TAU, 48, Color(0.1, 0.1, 0.1, 0.55), 0.6, true)

	# --- compass rose (map furniture, world space) ---
	if show_compass:
		_draw_compass(Vector2(sim.map_width - 76.0, 82.0), 56.0)

	# --- screen-space furniture: scale bar + vignette ---
	var screen_size: Vector2 = get_viewport_rect().size
	draw_set_transform_matrix(Transform2D())
	if show_scale_bar:
		_draw_scale_bar(screen_size)
	if show_vignette and _vignette_texture != null:
		draw_texture_rect(_vignette_texture, Rect2(Vector2.ZERO, screen_size), false)
	draw_set_transform_matrix(get_viewport_transform())


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
		draw_multiline(_border_segments, style_border, style_border_width, true)


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
		var font_size: float = clampf(sqrt(float(cells)) * 2.2, 9.0, 34.0) * style_label_scale
		var name_v: String = state.get("fullName", state["name"])
		var width: float = _font.get_string_size(name_v, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size)).x
		draw_string_outline(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), 3, COL_TEXT_OUT)
		draw_string(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size), style_text)

	# burg labels
	for b in sim.pack.burgs:
		if b == null:
			continue
		var pop: float = float(b.get("population", 0.0))
		var is_capital: bool = b.get("capital", 0) == 1
		if pop < 2.0 and not is_capital:
			continue
		var font_size: float = 4.5 if is_capital else clampf(2.5 + pop / 12.0, 3.0, 5.0)
		font_size *= style_label_scale
		var pos := Vector2(b["x"], b["y"]) + Vector2(0, 4.0 + font_size * 0.9)
		draw_string_outline(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size), 2, COL_TEXT_OUT)
		draw_string(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size), style_text)


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
	_draw_tinted(_ice_mesh, style_ice)
	if not _ice_outline_segments.is_empty():
		draw_multiline(_ice_outline_segments, Color(0.8, 0.88, 0.96, 0.9), 0.6, true)


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
		draw_multiline(_sea_route_segments, style_searoute, style_road_width * 0.65, true)
	if not _road_segments.is_empty():
		draw_multiline(_road_segments, style_road, style_road_width, true)
	if not _trail_segments.is_empty():
		draw_multiline(_trail_segments, style_trail, style_road_width * 0.55, true)


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


# ---------------------------------------------------------------------------
# FMG-parity data layers: temperature, precipitation, population, markets, trade

# d3 interpolateSpectral anchors (ColorBrewer Spectral), hot -> cold order.
const SPECTRAL: Array = [
	Color("#9e0142"), Color("#d53e4f"), Color("#f46d43"), Color("#fdae61"),
	Color("#fee08b"), Color("#ffffbf"), Color("#e6f598"), Color("#abdda4"),
	Color("#66c2a5"), Color("#3288bd"), Color("#5e4fa2")
]


## Temperature of a packed cell, sampled from its parent grid cell.
func _cell_temperature(i: int) -> int:
	if sim.grid == null or sim.pack.g.is_empty():
		return 0
	var parent: int = sim.pack.g[i]
	if parent < 0 or parent >= sim.grid.temp.size():
		return 0
	return sim.grid.temp[parent]


## Original domain for the temperature scheme: supported extremes -50..50 °C.
func _cell_temperature_color(i: int) -> Color:
	var t: float = clampf((float(_cell_temperature(i)) + 50.0) / 100.0, 0.0, 1.0)
	# scheme(1 - (t - tMin) / delta): hot maps to spectral(0) = dark red.
	var pos: float = (1.0 - t) * float(SPECTRAL.size() - 1)
	var idx: int = mini(int(pos), SPECTRAL.size() - 2)
	var color: Color = (SPECTRAL[idx] as Color).lerp(SPECTRAL[idx + 1], pos - float(idx))
	color.a = 0.72
	return color


func _cell_market_color(i: int) -> Color:
	var market_id: int = sim.pack.market[i]
	if market_id <= 0 or market_id >= sim.pack.markets.size():
		return Color(0, 0, 0, 0)
	var market: Dictionary = sim.pack.markets[market_id]
	return Color.html(str(market.get("color", "#cccccc")))


func _append_quad(data: Dictionary, a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	var vertices: PackedVector2Array = data["vertices"]
	var colors: PackedColorArray = data["colors"]
	for point: Vector2 in [a, b, c, a, c, d]:
		vertices.append(point)
		colors.append(color)
	data["vertices"] = vertices
	data["colors"] = colors


func _build_data_meshes() -> void:
	var pack: FmgGraph = sim.pack
	_temperature_mesh = _mesh_from_cells(_cell_temperature_color, 1.0, true)

	# Precipitation: filled discs per land cell, radius = sqrt(prec / 4) scaled
	# by the point count like the original (draw-precipitation.ts).
	var prec_data := {"vertices": PackedVector2Array(), "colors": PackedColorArray()}
	var cells_modifier: float = pow(float(maxi(sim.cells_desired, 1)) / 10000.0, 0.25)
	var grid_prec := sim.grid.prec if sim.grid != null else PackedInt32Array()
	var prec_color := Color(0.29, 0.45, 0.71, 0.5)
	for i: int in pack.cell_count():
		if pack.h[i] < 20 or grid_prec.is_empty():
			continue
		var parent: int = pack.g[i]
		if parent < 0 or parent >= grid_prec.size():
			continue
		var prec: int = grid_prec[parent]
		if prec <= 0:
			continue
		var radius: float = sqrt(float(prec) / 4.0) / maxf(cells_modifier, 0.35)
		if radius < 0.35:
			continue
		radius = minf(radius, 14.0)
		var center: Vector2 = pack.points[i]
		for k: int in 6:
			var a0: float = TAU * float(k) / 6.0
			var a1: float = TAU * float(k + 1) / 6.0
			_append_quad(prec_data,
				center,
				center + Vector2(cos(a0), sin(a0)) * radius,
				center + Vector2(cos(a0), sin(a0)) * radius,
				center + Vector2(cos(a1), sin(a1)) * radius,
				prec_color)
	_precipitation_mesh = _make_color_mesh(prec_data["vertices"], prec_data["colors"])

	# Population: rural bars per cell and urban bars per burg (height pop / 5).
	var pop_data := {"vertices": PackedVector2Array(), "colors": PackedColorArray()}
	var rural_color := Color(0.55, 0.62, 0.53, 0.85)
	var urban_color := Color(0.48, 0.12, 0.12, 0.9)
	for i: int in pack.cell_count():
		if pack.h[i] < 20 or pack.pop[i] <= 0.0:
			continue
		var p: Vector2 = pack.points[i]
		var height: float = minf(pack.pop[i] / 5.0, 40.0)
		if height < 0.8:
			continue
		_append_quad(pop_data, p + Vector2(-0.32, 0), p + Vector2(0.32, 0), p + Vector2(0.32, -height), p + Vector2(-0.32, -height), rural_color)
	for burg_value: Variant in pack.burgs:
		if burg_value == null:
			continue
		var burg: Dictionary = burg_value
		var p: Vector2 = Vector2(float(burg.get("x", 0.0)), float(burg.get("y", 0.0)))
		var height: float = minf(float(burg.get("population", 0.0)) / 5.0, 60.0)
		if height < 0.8:
			continue
		_append_quad(pop_data, p + Vector2(-0.7, 0), p + Vector2(0.7, 0), p + Vector2(0.7, -height), p + Vector2(-0.7, -height), urban_color)
	_population_mesh = _make_color_mesh(pop_data["vertices"], pop_data["colors"])

	# Market territories + centers; trade deals connect market centers.
	_market_mesh = _mesh_from_cells(_cell_market_color, 0.28)
	var centers := {}
	for market_value: Variant in pack.markets:
		var market: Dictionary = market_value
		var burg_id: int = int(market.get("centerBurgId", 0))
		if burg_id <= 0 or burg_id >= pack.burgs.size() or pack.burgs[burg_id] == null:
			continue
		var burg: Dictionary = pack.burgs[burg_id]
		var pos := Vector2(float(burg["x"]), float(burg["y"]))
		var color: Color = Color.html(str(market.get("color", "#cccccc")))
		_market_centers.append({"pos": pos, "name": str(burg.get("name", "?")), "color": color})
		centers[int(market["i"])] = pos
	for deal_value: Variant in pack.deals:
		var deal: Dictionary = deal_value
		var a: Vector2 = centers.get(int(deal.get("seller", 0)), Vector2.ZERO)
		var b: Vector2 = centers.get(int(deal.get("buyer", 0)), Vector2.ZERO)
		if a == Vector2.ZERO or b == Vector2.ZERO or a == b:
			continue
		# curved arc so overlapping deals remain readable
		var mid: Vector2 = (a + b) * 0.5
		var lift: Vector2 = (b - a).orthogonal().normalized() * clampf(a.distance_to(b) * 0.12, 2.0, 26.0)
		var steps: int = 12
		var prev: Vector2 = a
		for k: int in range(1, steps + 1):
			var t: float = float(k) / float(steps)
			var point: Vector2 = _quad_point(a, mid + lift, b, t)
			_trade_segments.append(prev)
			_trade_segments.append(point)
			prev = point


func _quad_point(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var ab: Vector2 = a.lerp(control, t)
	var cb: Vector2 = control.lerp(b, t)
	return ab.lerp(cb, t)


func _draw_market_centers() -> void:
	for entry_value: Variant in _market_centers:
		var entry: Dictionary = entry_value
		var pos: Vector2 = entry["pos"]
		var color: Color = entry["color"]
		draw_circle(pos, 2.2, color.darkened(0.2))
		draw_arc(pos, 3.4, 0.0, TAU, 16, Color(0.1, 0.1, 0.1, 0.6), 0.5, true)


## Prevailing wind arrows along the top and bottom edges (precipitation layer).
func _draw_wind_arrows() -> void:
	if sim.climate_winds.is_empty():
		return
	var col := Color(0.24, 0.36, 0.55, 0.85)
	for i: int in mini(6, sim.climate_winds.size()):
		var angle: float = deg_to_rad(float(sim.climate_winds[i]))
		var direction := Vector2(sin(angle), -cos(angle))
		for edge_y: float in [16.0, sim.map_height - 16.0]:
			var center := Vector2((float(i) + 0.5) * sim.map_width / 6.0, edge_y)
			var tip := center + direction * 9.0
			var tail := center - direction * 9.0
			draw_line(tail, tip, col, 1.1, true)
			var side := Vector2(-direction.y, direction.x)
			draw_colored_polygon(PackedVector2Array([
				tip, tip - direction * 3.4 + side * 2.0, tip - direction * 3.4 - side * 2.0
			]), col)


# ---------------------------------------------------------------------------
# Map furniture: grid, coordinates, rulers, compass rose, scale bar, vignette

func _draw_grid() -> void:
	var col := Color(0.1, 0.15, 0.2, 0.25)
	var segments := PackedVector2Array()
	var step := 100.0
	var x := step
	while x < sim.map_width:
		segments.append(Vector2(x, 0))
		segments.append(Vector2(x, sim.map_height))
		x += step
	var y := step
	while y < sim.map_height:
		segments.append(Vector2(0, y))
		segments.append(Vector2(sim.map_width, y))
		y += step
	if not segments.is_empty():
		draw_multiline(segments, col, 0.6, true)


## Equirectangular graticule from the map's latitude span (lat_n/lat_s/lat_t).
func _draw_coordinates() -> void:
	if sim.lat_t <= 0.0:
		return
	var lat_n: float = sim.lat_n
	var lat_s: float = sim.lat_s
	var lat_t: float = sim.lat_t
	var lon_t: float = minf(sim.map_width / sim.map_height * lat_t, 360.0)
	var lon_w: float = -lon_t / 2.0
	var steps: Array = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0]
	var goal: float = lat_t / 12.0
	var step: float = 30.0
	for candidate: float in steps:
		if absf(candidate - goal) < absf(step - goal):
			step = candidate
	var col := Color(0.12, 0.2, 0.33, 0.55)
	var segments := PackedVector2Array()
	var labels: Array = []
	var lat: float = ceilf(lat_s / step) * step
	while lat <= lat_n + 0.001:
		var y: float = (lat_n - lat) / lat_t * sim.map_height
		segments.append(Vector2(0, y))
		segments.append(Vector2(sim.map_width, y))
		labels.append({"text": "%d°" % int(lat), "pos": Vector2(4.0, y - 2.0)})
		lat += step
	var lon: float = ceilf(lon_w / step) * step
	while lon <= lon_w + lon_t + 0.001:
		var x: float = (lon - lon_w) / lon_t * sim.map_width
		segments.append(Vector2(x, 0))
		segments.append(Vector2(x, sim.map_height))
		labels.append({"text": "%d°" % int(round(lon)), "pos": Vector2(x + 2.0, 9.0)})
		lon += step
	if not segments.is_empty():
		draw_multiline(segments, col, 0.5, true)
	for label_value: Variant in labels:
		var label: Dictionary = label_value
		draw_string_outline(_font, label["pos"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 2, Color(1, 1, 1, 0.65))
		draw_string(_font, label["pos"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)


## Measure tool: polyline through ruler_points with a running distance label.
func _draw_rulers() -> void:
	if ruler_points.size() < 1:
		return
	var col := Color(0.75, 0.1, 0.1, 0.9)
	var segments := PackedVector2Array()
	var total: float = 0.0
	for i: int in ruler_points.size() - 1:
		segments.append(ruler_points[i])
		segments.append(ruler_points[i + 1])
		total += ruler_points[i].distance_to(ruler_points[i + 1])
	if not segments.is_empty():
		draw_multiline(segments, col, 1.2, true)
	for point: Vector2 in ruler_points:
		draw_circle(point, 2.6, Color(0.95, 0.9, 0.8, 0.95))
		draw_arc(point, 2.6, 0.0, TAU, 12, col, 0.8, true)
	if ruler_points.size() >= 2:
		var last: Vector2 = ruler_points[ruler_points.size() - 1]
		var label: String = _format_distance(total)
		var size: int = 11
		draw_string_outline(_font, last + Vector2(6.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(1, 1, 1, 0.8))
		draw_string(_font, last + Vector2(6.0, -6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _format_distance(pixels: float) -> String:
	var km: float = pixels * distance_scale
	if km < 10.0:
		return "%.1f км" % km
	return "%d км" % int(round(km))


## 16-point compass rose, two-tone points like the original wind rose.
func _draw_compass(center: Vector2, radius: float) -> void:
	var dark := Color("#27374d")
	var light := Color("#f4f1e6")
	var ring := Color("#3a4a5f")
	draw_arc(center, radius, 0.0, TAU, 56, ring, 1.2, true)
	draw_arc(center, radius * 0.82, 0.0, TAU, 48, Color(ring, 0.6), 0.6, true)
	# star points: 8 major (alternate two-tone) + 8 minor (dark, half length)
	for k: int in 16:
		var major: bool = k % 2 == 0
		var angle: float = -PI / 2.0 + TAU * float(k) / 16.0
		var length: float = radius * (0.92 if major else 0.5)
		var half_width: float = TAU / 16.0 * 0.55
		var tip := center + Vector2(cos(angle), sin(angle)) * length
		var left := center + Vector2(cos(angle - half_width), sin(angle - half_width)) * radius * 0.1
		var right := center + Vector2(cos(angle + half_width), sin(angle + half_width)) * radius * 0.1
		if major and k % 4 == 0:
			# cardinal points: split into dark and light halves
			draw_colored_polygon(PackedVector2Array([center, tip, left]), dark)
			draw_colored_polygon(PackedVector2Array([center, tip, right]), light)
		elif major:
			draw_colored_polygon(PackedVector2Array([center, tip, left]), Color(dark, 0.85))
			draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(light, 0.85))
		else:
			draw_colored_polygon(PackedVector2Array([center, tip, left]), Color(dark, 0.7))
			draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(light, 0.7))
	draw_circle(center, radius * 0.07, dark)
	draw_circle(center, radius * 0.035, light)
	# N E S W letters
	var letters := [["N", 0.0], ["E", PI / 2.0], ["S", PI], ["W", -PI / 2.0]]
	for entry: Array in letters:
		var angle: float = float(entry[1])
		var pos := center + Vector2(cos(angle), sin(angle)) * radius * 1.12
		var letter: String = str(entry[0])
		var width: float = _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(_font, pos + Vector2(-width / 2.0, 5.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(1, 1, 1, 0.75))
		draw_string(_font, pos + Vector2(-width / 2.0, 5.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#33465e"))


## Screen-fixed scale bar in the bottom-left corner, like the original's.
func _draw_scale_bar(screen_size: Vector2) -> void:
	var km_per_px: float = maxf(distance_scale, 0.01)
	var target_px: float = 140.0
	var raw_km: float = target_px * km_per_px
	var magnitude: float = pow(10.0, floorf(log(raw_km) / log(10.0)))
	var nice: float = magnitude
	for candidate: float in [1.0, 2.0, 5.0, 10.0]:
		if raw_km <= candidate * magnitude * 1.0001:
			nice = candidate * magnitude
			break
	var bar_px: float = nice / km_per_px
	var pos := Vector2(24.0, screen_size.y - 40.0)
	var bar_height: float = 6.0
	var cells_count: int = 4
	for k: int in cells_count:
		var rect := Rect2(pos + Vector2(bar_px * float(k) / float(cells_count), 0), Vector2(bar_px / float(cells_count), bar_height))
		draw_rect(rect, Color(0.08, 0.1, 0.12) if k % 2 == 0 else Color(0.96, 0.94, 0.88), true)
	draw_rect(Rect2(pos, Vector2(bar_px, bar_height)), Color(0.08, 0.1, 0.12), false, 1.0)
	var label: String = "%s км" % _format_number(nice)
	var label_size: int = 12
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	draw_string_outline(_font, pos + Vector2((bar_px - width) / 2.0, -5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, 3, Color(1, 1, 1, 0.8))
	draw_string(_font, pos + Vector2((bar_px - width) / 2.0, -5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(0.08, 0.1, 0.12))


func _format_number(value: float) -> String:
	var rounded := int(round(value))
	if rounded >= 1000:
		return "%d %03d" % [floori(rounded / 1000.0), rounded % 1000]
	return str(rounded)


## Soft dark border around the viewport (the original's vignette layer).
func _build_vignette_texture() -> void:
	if _vignette_texture != null:
		return
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for y: int in size:
		for x: int in size:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) / (size * 0.72)
			var alpha: float = clampf((d - 0.55) / 0.45, 0.0, 1.0)
			alpha = alpha * alpha * 0.42
			image.set_pixel(x, y, Color(0.05, 0.08, 0.14, alpha))
	_vignette_texture = ImageTexture.create_from_image(image)
