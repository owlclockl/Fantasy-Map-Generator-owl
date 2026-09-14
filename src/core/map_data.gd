extends Node
## Sim — the world state singleton. Port of the original global `options`,
## `grid`, `pack` objects and the generation pipeline
## (generation-pipeline.ts). Autoloaded as `Sim`.

signal stage_started(stage_name: String)
signal map_generated()

const SEA_LEVEL: int = 20
const SAVE_FORMAT: int = 1

# --- options (options-model.ts defaults) ---
var seed_value: String = "1000"
var template_id: String = "continents" # or "random"
var cells_desired: int = 10000
var map_width: float = 1280.0
var map_height: float = 800.0

var climate_equator: float = 27.0
var climate_north_pole: float = -30.0
var climate_south_pole: float = -15.0
var climate_precipitation: float = 100.0
var climate_winds: Array = [225.0, 45.0, 225.0, 315.0, 135.0, 315.0]
var lat_n: float = 90.0
var lat_s: float = -90.0
var lat_t: float = 180.0

var cultures_limit: int = 12
var cultures_set: String = "world"
var states_limit: int = 18
var provinces_ratio: float = 20.0
var burgs_limit: int = 1000 # -1 = auto
var religions_limit: int = 6
var size_variety: float = 4.0
var growth_rate: float = 1.0
var lake_elevation_limit: int = 20

# coastline style (coastline-generator.ts defaults)
var coast_enabled: bool = true
var coast_max_depth: int = 4
var coast_amplitude: float = 1.5

var rng: FmgRng = null
var grid: FmgGraph = null
var pack: FmgGraph = null
var hydrology: FmgHydrology = null
var burgs: FmgBurgs = null
var generation_time_ms: int = 0


func climate() -> FmgClimate:
	var c := FmgClimate.new()
	c.temperature_equator = climate_equator
	c.temperature_north_pole = climate_north_pole
	c.temperature_south_pole = climate_south_pole
	c.precipitation_level = climate_precipitation
	c.winds = climate_winds.duplicate()
	c.height_exponent = 2.0
	c.lat_n = lat_n
	c.lat_s = lat_s
	c.lat_t = lat_t
	return c


## The canonical pipeline: id + callable pairs, executed in order by main.gd
func pipeline() -> Array:
	rng = FmgRng.new(seed_value)
	return [
		["Граф", func() -> void: _stage_grid()],
		["Рельеф", func() -> void: _stage_heightmap()],
		["Океаны и озёра", func() -> void: _stage_markup_grid()],
		["Температура", func() -> void: _stage_climate()],
		["Осадки", func() -> void: _stage_precipitation()],
		["Упаковка графа", func() -> void: _stage_pack()],
		["Реки", func() -> void: _stage_rivers()],
		["Биомы", func() -> void: _stage_biomes()],
		["Население", func() -> void: _stage_population()],
		["Культуры", func() -> void: _stage_cultures()],
		["Города", func() -> void: _stage_burgs()],
		["Государства", func() -> void: _stage_states()],
		["Религии", func() -> void: _stage_religions()],
		["Провинции", func() -> void: _stage_provinces()],
		["Имена", func() -> void: _stage_names()],
	]


func _stage_grid() -> void:
	grid = GridGenerator.generate(seed_value, map_width, map_height, cells_desired, rng)


func _stage_heightmap() -> void:
	var template: String = template_id
	if template == "random":
		template = HeightmapGenerator.get_random_template_id(rng)
	var generator := HeightmapGenerator.new()
	generator.from_template(grid, template, cells_desired, map_width, map_height, rng)
	grid.h = generator.heights


func _stage_markup_grid() -> void:
	FmgFeatures.markup_grid(grid)
	GridGenerator.add_deep_depression_lakes(grid, rng, lake_elevation_limit)
	GridGenerator.open_near_sea_lakes(grid, template_id == "atoll")


func _stage_climate() -> void:
	climate().generate_temperature(grid)


func _stage_precipitation() -> void:
	climate().generate_precipitation(grid, cells_desired, rng)


func _stage_pack() -> void:
	pack = PackBuilder.generate(grid, rng)
	FmgFeatures.markup_pack(pack, map_width, map_height)


func _stage_rivers() -> void:
	hydrology = FmgHydrology.new(rng, grid, pack)
	burgs = FmgBurgs.new(rng, pack, grid)
	burgs.set_hydrology(hydrology)
	burgs.states_limit = states_limit
	burgs.burgs_limit = burgs_limit
	hydrology.generate(true)


func _stage_biomes() -> void:
	pack.biomes = FmgBiomes.get_default_biomes()
	FmgBiomes.define(pack, grid)
	FmgFeatures.define_groups(pack, grid.cell_count())


func _stage_population() -> void:
	FmgBiomes.Population.rank_cells(pack, rng)


func _stage_cultures() -> void:
	var cultures := FmgCultures.new(rng, pack, grid)
	cultures.cultures_limit = cultures_limit
	cultures.cultures_set = cultures_set
	cultures.size_variety = size_variety
	cultures.growth_rate = growth_rate
	cultures.generate()
	cultures.expand()


func _stage_burgs() -> void:
	burgs.generate()


func _stage_states() -> void:
	var states := FmgStates.new(rng, pack, grid)
	states.states_limit = states_limit
	states.size_variety = size_variety
	states.growth_rate = growth_rate
	states.generate()
	poles_cache = states.poles


func _stage_religions() -> void:
	var religions := FmgReligions.new(rng, pack, grid)
	religions.religions_limit = religions_limit
	religions.generate()


func _stage_provinces() -> void:
	var provinces := FmgProvinces.new(rng, pack, grid, burgs)
	provinces.provinces_ratio = provinces_ratio
	provinces.generate()


func _stage_names() -> void:
	# river names and types + lake names, based on local cultures
	if pack.rivers.size() > 1:
		var lengths: Array = []
		for river: Dictionary in pack.rivers:
			if river != null:
				lengths.append(float(river.get("length", 0.0)))
		lengths.sort()
		var small_length: float = lengths[mini(int(ceil(float(lengths.size()) * 0.15)), lengths.size() - 1)] if lengths.size() > 0 else 0.0

		for river: Dictionary in pack.rivers:
			if river == null:
				continue
			var mouth: int = river["mouth"]
			var culture: int = pack.culture[mouth] if mouth >= 0 and mouth < pack.culture.size() else 0
			river["name"] = Names.get_culture(culture)
			var is_small: bool = float(river.get("length", 0.0)) < small_length
			var is_fork: bool = river["i"] % 3 == 0 and int(river.get("parent", 0)) != 0 and int(river.get("parent", 0)) != int(river["i"])
			if is_fork:
				river["type"] = "Ветвь" if is_small else "Приток"
			else:
				if is_small:
					river["type"] = rng.rw({"Ручей": 9, "Река": 3, "Ручеёк": 3, "Поток": 1})
				else:
					river["type"] = "Река"

	for feature: Dictionary in pack.features:
		if feature == null or feature.is_empty() or feature["type"] != "lake":
			continue
		var shoreline: PackedInt32Array = feature["shoreline"]
		if shoreline.is_empty():
			continue
		var land_cell: int = shoreline[0]
		feature["name"] = Names.get_culture(pack.culture[land_cell])


## regenerates everything downstream of the heightmap (after a height edit)
func pipeline_from_heightmap() -> Array:
	return pipeline().slice(2)


func get_stats_text() -> String:
	if pack == null:
		return "Карта не сгенерирована"
	var land_cells: int = 0
	for i: int in pack.cell_count():
		if pack.h[i] >= SEA_LEVEL:
			land_cells += 1
	var states_count: int = 0
	for s: Dictionary in pack.states:
		if s != null and int(s["i"]) > 0:
			states_count += 1
	var burgs_count: int = 0
	for b: Dictionary in pack.burgs:
		if b != null:
			burgs_count += 1
	var rivers_count: int = maxi(pack.rivers.size() - 1, 0)
	return "Ячеек: %d · Суши: %d%% · Государств: %d · Городов: %d · Рек: %d · Время: %d мс" % [
		pack.cell_count(), int(100.0 * land_cells / maxi(pack.cell_count(), 1)),
		states_count, burgs_count, rivers_count, generation_time_ms
	]


# ---------------------------------------------------------------------------
# Save / load (port of the .map format concept: points + derived graph)

func save_map(path: String) -> Error:
	if grid == null or pack == null:
		return ERR_DOES_NOT_EXIST
	var data := {
		"format": "fmg-godot",
		"version": SAVE_FORMAT,
		"seed": seed_value,
		"template": template_id,
		"cellsDesired": cells_desired,
		"mapWidth": map_width,
		"mapHeight": map_height,
		"climate": {
			"equator": climate_equator, "northPole": climate_north_pole,
			"southPole": climate_south_pole, "precipitation": climate_precipitation,
			"winds": climate_winds, "latN": lat_n, "latS": lat_s, "latT": lat_t
		},
		"limits": {
			"cultures": cultures_limit, "culturesSet": cultures_set,
			"states": states_limit, "provincesRatio": provinces_ratio,
			"burgs": burgs_limit, "religions": religions_limit
		},
		"grid": {
			"spacing": grid.spacing,
			"cellsX": grid.cells_x,
			"cellsY": grid.cells_y,
			"points": _pack_points(grid.points),
			"h": Array(grid.h)
		},
		"pack": {
			"points": _pack_points(pack.points),
			"g": Array(pack.g),
			"h": Array(pack.h),
			"area": Array(pack.area),
			"fl": Array(pack.fl),
			"r": Array(pack.r),
			"conf": Array(pack.conf),
			"biome": Array(pack.biome),
			"culture": Array(pack.culture),
			"state": Array(pack.state),
			"province": Array(pack.province),
			"religion": Array(pack.religion),
			"burg": Array(pack.burg),
			"s": Array(pack.s),
			"pop": Array(pack.pop)
		},
		"cultures": pack.cultures,
		"states": pack.states,
		"burgs": pack.burgs,
		"provinces": pack.provinces,
		"religions": pack.religions,
		"rivers": pack.rivers,
		"featureNames": _collect_feature_names()
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	return OK


func _pack_points(points: PackedVector2Array) -> Array:
	var out: Array = []
	out.resize(points.size())
	for i: int in points.size():
		out[i] = [points[i].x, points[i].y]
	return out


func _collect_feature_names() -> Dictionary:
	var out := {}
	if pack != null:
		for feature: Dictionary in pack.features:
			if feature == null or feature.is_empty():
				continue
			if feature.get("name", "") != "":
				out[feature["i"]] = feature["name"]
	return out


func load_map(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not parsed is Dictionary:
		return ERR_INVALID_DATA
	var data: Dictionary = parsed
	if data.get("format", "") != "fmg-godot":
		return ERR_INVALID_DATA

	seed_value = data.get("seed", "0")
	template_id = data.get("template", "continents")
	cells_desired = int(data.get("cellsDesired", 10000))
	map_width = float(data.get("mapWidth", 1280.0))
	map_height = float(data.get("mapHeight", 800.0))
	var climate_data: Dictionary = data.get("climate", {})
	climate_equator = float(climate_data.get("equator", 27.0))
	climate_north_pole = float(climate_data.get("northPole", -30.0))
	climate_south_pole = float(climate_data.get("southPole", -15.0))
	climate_precipitation = float(climate_data.get("precipitation", 100.0))
	climate_winds = climate_data.get("winds", [225.0, 45.0, 225.0, 315.0, 135.0, 315.0])
	lat_n = float(climate_data.get("latN", 90.0))
	lat_s = float(climate_data.get("latS", -90.0))
	lat_t = float(climate_data.get("latT", 180.0))
	var limits: Dictionary = data.get("limits", {})
	cultures_limit = int(limits.get("cultures", 12))
	cultures_set = str(limits.get("culturesSet", "world"))
	states_limit = int(limits.get("states", 18))
	provinces_ratio = float(limits.get("provincesRatio", 20.0))
	burgs_limit = int(limits.get("burgs", 1000))
	religions_limit = int(limits.get("religions", 6))

	rng = FmgRng.new(seed_value)

	# --- grid ---
	var grid_data: Dictionary = data["grid"]
	grid = FmgGraph.new()
	grid.spacing = float(grid_data["spacing"])
	grid.cells_x = int(grid_data["cellsX"])
	grid.cells_y = int(grid_data["cellsY"])
	grid.width = map_width
	grid.height = map_height
	grid.points = _unpack_points(grid_data["points"])
	grid.boundary = GridGenerator._boundary_points(map_width, map_height, grid.spacing)
	_rebuild_voronoi(grid)
	grid.h = PackedByteArray(Array(grid_data["h"]))

	# grid-level climate + feature data is recomputed deterministically
	climate().generate_temperature(grid)
	climate().generate_precipitation(grid, cells_desired, rng)
	FmgFeatures.markup_grid(grid)

	# --- pack ---
	var pack_data: Dictionary = data["pack"]
	pack = FmgGraph.new()
	pack.width = map_width
	pack.height = map_height
	pack.spacing = grid.spacing * 0.5
	pack.points = _unpack_points(pack_data["points"])
	pack.g = PackedInt32Array(Array(pack_data["g"]))
	pack.h = PackedByteArray(Array(pack_data["h"]))
	pack.cells_x = grid.cells_x
	pack.cells_y = grid.cells_y
	_rebuild_voronoi(pack)
	pack.area = PackedFloat32Array(Array(pack_data["area"]))
	pack.fl = PackedFloat32Array(Array(pack_data["fl"]))
	pack.r = PackedInt32Array(Array(pack_data["r"]))
	pack.conf = PackedInt32Array(Array(pack_data["conf"]))
	pack.biome = PackedByteArray(Array(pack_data["biome"]))
	pack.culture = PackedInt32Array(Array(pack_data["culture"]))
	pack.state = PackedInt32Array(Array(pack_data["state"]))
	pack.province = PackedInt32Array(Array(pack_data["province"]))
	pack.religion = PackedInt32Array(Array(pack_data["religion"]))
	pack.burg = PackedInt32Array(Array(pack_data["burg"]))
	pack.s = PackedInt32Array(Array(pack_data["s"]))
	pack.pop = PackedFloat32Array(Array(pack_data["pop"]))

	pack.biomes = FmgBiomes.get_default_biomes()
	FmgFeatures.markup_pack(pack, map_width, map_height)

	# reapply saved feature names (lakes mostly)
	var feature_names: Dictionary = data.get("featureNames", {})
	for fid: Variant in feature_names:
		var idx: int = int(fid)
		if idx > 0 and idx < pack.features.size():
			pack.features[idx]["name"] = feature_names[fid]

	pack.cultures = data.get("cultures", [null])
	pack.states = data.get("states", [null])
	pack.burgs = data.get("burgs", [null])
	pack.provinces = data.get("provinces", [null])
	pack.religions = data.get("religions", [null])
	pack.rivers = data.get("rivers", [null])

	hydrology = FmgHydrology.new(rng, grid, pack)
	burgs = FmgBurgs.new(rng, pack, grid)
	burgs.set_hydrology(hydrology)
	burgs.states_limit = states_limit
	burgs.burgs_limit = burgs_limit
	return OK


func _unpack_points(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(arr.size())
	for i: int in arr.size():
		out[i] = Vector2(arr[i][0], arr[i][1])
	return out


func _rebuild_voronoi(graph: FmgGraph) -> void:
	var del := Delaunator.from_points(graph.points)
	var voronoi := FmgVoronoi.new()
	voronoi._build(del, graph.points.size(), graph.points.size())
	graph.voronoi = voronoi
	graph.v = voronoi.cells.v
	graph.c = voronoi.cells.c
	graph.b = voronoi.cells.b


## after a height edit: rerun everything from the pack graph on
func rebuild_after_height_edit() -> void:
	# grid markup + climate stay; the pack is rebuilt and all layers regenerated
	climate().generate_temperature(grid)
	climate().generate_precipitation(grid, cells_desired, rng)
	FmgFeatures.markup_grid(grid)
	_stage_pack()
	_stage_rivers()
	_stage_biomes()
	_stage_population()
	_stage_cultures()
	_stage_burgs()
	_stage_states()
	_stage_religions()
	_stage_provinces()
	_stage_names()
