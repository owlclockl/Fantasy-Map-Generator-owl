class_name MapView
extends Node2D
## Renders the generated world: ocean, landmasses with fractal coastlines,
## lakes, rivers, overlays (political/biomes/cultures/religions/heights),
## borders, burgs and labels. Each layer is a child Node2D whose draw commands
## are recorded once and re-rasterized by the GPU on camera moves.

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

var sim: Node = null # Sim autoload

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
var show_cell_borders: bool = false # debug

# cached geometry
var _land_rings: Array = [] # {points, feature}
var _lake_rings: Array = []
var _ocean_rings: Array = [] # {t, rings}
var _river_polys: Array = [] # {points, river}
var _font: Font = null

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
	if sim == null or sim.pack == null:
		queue_redraw_all()
		return

	# coastline rings per feature, fractalized deterministically per feature id
	for feature: Dictionary in sim.pack.features:
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
		for river: Dictionary in sim.pack.rivers:
			if river == null:
				continue
			var poly := sim.hydrology.get_river_polygon(river)
			if poly.size() >= 3:
				_river_polys.append({"points": poly, "river": river})

	queue_redraw_all()


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
		_draw_cell_overlay(_cell_height_color, 1.0)
	elif show_cultures:
		_draw_cell_overlay(_cell_culture_color, 0.65)
	elif show_religions:
		_draw_cell_overlay(_cell_religion_color, 0.6)
	else:
		if show_biomes:
			_draw_cell_overlay(_cell_biome_color, 1.0)
		if show_relief and not show_heights:
			_draw_relief_shading()
		if show_politics:
			_draw_cell_overlay(_cell_state_color, 0.55)
		if show_provinces:
			_draw_cell_overlay(_cell_province_color, 0.25)

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

	# --- burgs ---
	if show_burgs:
		_draw_burgs()

	# --- labels ---
	if show_labels:
		_draw_labels()


func _cell_color_safe(cell_id: int) -> Color:
	return Color.WHITE


func _draw_cell_overlay(color_fn: Callable, alpha: float) -> void:
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var color: Color = color_fn.call(i)
		if color.a <= 0.0:
			continue
		color.a *= alpha
		var poly := pack.get_polygon(i)
		if poly.size() >= 3:
			draw_colored_polygon(poly, color)


func _draw_relief_shading() -> void:
	# soft shadow on higher cells: multiply-ish tint
	var pack: FmgGraph = sim.pack
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		var h: float = float(pack.h[i])
		if h < 45.0:
			continue
		var strength: float = clampf((h - 45.0) / 55.0, 0.0, 1.0) * 0.45
		var poly := pack.get_polygon(i)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0.25, 0.2, 0.12, strength))


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


func _draw_cell_borders() -> void:
	var pack: FmgGraph = sim.pack
	var vertices := pack.voronoi.vertices
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		for n: int in pack.c[i]:
			if n < i or pack.h[n] < 20:
				continue
			var common := PackedInt32Array()
			for v1: int in pack.v[i]:
				for v2: int in pack.v[n]:
					if v1 == v2:
						common.append(v1)
			if common.size() >= 2:
				draw_line(vertices.p[common[0]], vertices.p[common[1]], Color(0, 0, 0, 0.15), 0.5, true)


func _draw_state_borders() -> void:
	var pack: FmgGraph = sim.pack
	var vertices := pack.voronoi.vertices
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		for n: int in pack.c[i]:
			if n < i or pack.h[n] < 20:
				continue
			if pack.state[i] == pack.state[n]:
				continue
			var common := PackedInt32Array()
			for v1: int in pack.v[i]:
				for v2: int in pack.v[n]:
					if v1 == v2:
						common.append(v1)
			if common.size() >= 2:
				draw_line(vertices.p[common[0]], vertices.p[common[1]], COL_BORDER, 1.4, true)


func _draw_province_borders() -> void:
	var pack: FmgGraph = sim.pack
	var vertices := pack.voronoi.vertices
	for i: int in pack.cell_count():
		if pack.h[i] < 20:
			continue
		for n: int in pack.c[i]:
			if n < i or pack.h[n] < 20:
				continue
			if pack.province[i] == pack.province[n]:
				continue
			var common := PackedInt32Array()
			for v1: int in pack.v[i]:
				for v2: int in pack.v[n]:
					if v1 == v2:
						common.append(v1)
			if common.size() >= 2:
				draw_line(vertices.p[common[0]], vertices.p[common[1]], COL_PROVINCE_BORDER, 0.8, true)


func _draw_burgs() -> void:
	for b: Dictionary in sim.pack.burgs:
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
	for state: Dictionary in sim.pack.states:
		if state == null or int(state["i"]) == 0:
			continue
		if not sim.poles_cache.has(state["i"]):
			continue
		var pole: Vector2 = sim.poles_cache[state["i"]]
		var cells: int = state.get("cells", 10)
		var font_size: float = clampf(sqrt(float(cells)) * 2.2, 9.0, 34.0)
		var name_v: String = state.get("fullName", state["name"])
		var width: float = _font.get_string_size(name_v, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		draw_string_outline(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, COL_TEXT_OUT)
		draw_string(_font, pole + Vector2(-width / 2.0, 0), name_v, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_TEXT)

	# burg labels
	for b: Dictionary in sim.pack.burgs:
		if b == null:
			continue
		var pop: float = float(b.get("population", 0.0))
		var is_capital: bool = b.get("capital", 0) == 1
		if pop < 2.0 and not is_capital:
			continue
		var font_size: float = 4.5 if is_capital else clampf(2.5 + pop / 12.0, 3.0, 5.0)
		var pos := Vector2(b["x"], b["y"]) + Vector2(0, 4.0 + font_size * 0.9)
		draw_string_outline(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, 2, COL_TEXT_OUT)
		draw_string(_font, pos, b["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COL_TEXT)
