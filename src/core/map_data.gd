class_name FmgSim
extends Node
## Sim — the world state singleton. Port of the original global `options`,
## `grid`, `pack` objects and the generation pipeline
## (generation-pipeline.ts). Autoloaded as `Sim`.
##
## The class name is intentionally different from the autoload name: `class_name Sim`
## would clash with the singleton and the parser rejects it. UI scripts reference this
## type so that `sim.grid` / `sim.pack` / `sim.hydrology` stay statically typed (an
## untyped `Node` reference turns every member access into a Variant and breaks `:=`
## type inference).

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
var routes_gen: FmgRoutes = null # kept for markers/zones helpers and journeys
var generation_time_ms: int = 0
var poles_cache: Dictionary = {} # state id -> pole cell position, cached for label rendering
var province_poles_cache: Dictionary = {} # province id -> pole position, for province labels


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


## Options are copied before a worker starts. Keeping this as a plain
## dictionary makes the worker independent from the SceneTree and avoids
## reading controls while another thread is generating.
func get_generation_options() -> Dictionary:
	return {
		"seed": seed_value,
		"template": template_id,
		"cellsDesired": cells_desired,
		"mapWidth": map_width,
		"mapHeight": map_height,
		"climateEquator": climate_equator,
		"climateNorthPole": climate_north_pole,
		"climateSouthPole": climate_south_pole,
		"climatePrecipitation": climate_precipitation,
		"climateWinds": climate_winds.duplicate(),
		"latN": lat_n,
		"latS": lat_s,
		"latT": lat_t,
		"cultures": cultures_limit,
		"culturesSet": cultures_set,
		"states": states_limit,
		"provincesRatio": provinces_ratio,
		"burgs": burgs_limit,
		"religions": religions_limit,
		"sizeVariety": size_variety,
		"growthRate": growth_rate,
		"lakeElevationLimit": lake_elevation_limit,
		"coastEnabled": coast_enabled,
		"coastMaxDepth": coast_max_depth,
		"coastAmplitude": coast_amplitude
	}


func apply_generation_options(options: Dictionary) -> void:
	seed_value = str(options.get("seed", seed_value))
	template_id = str(options.get("template", template_id))
	cells_desired = int(options.get("cellsDesired", cells_desired))
	map_width = float(options.get("mapWidth", map_width))
	map_height = float(options.get("mapHeight", map_height))
	climate_equator = float(options.get("climateEquator", climate_equator))
	climate_north_pole = float(options.get("climateNorthPole", climate_north_pole))
	climate_south_pole = float(options.get("climateSouthPole", climate_south_pole))
	climate_precipitation = float(options.get("climatePrecipitation", climate_precipitation))
	climate_winds = (options.get("climateWinds", climate_winds) as Array).duplicate()
	lat_n = float(options.get("latN", lat_n))
	lat_s = float(options.get("latS", lat_s))
	lat_t = float(options.get("latT", lat_t))
	cultures_limit = int(options.get("cultures", cultures_limit))
	cultures_set = str(options.get("culturesSet", cultures_set))
	states_limit = int(options.get("states", states_limit))
	provinces_ratio = float(options.get("provincesRatio", provinces_ratio))
	burgs_limit = int(options.get("burgs", burgs_limit))
	religions_limit = int(options.get("religions", religions_limit))
	size_variety = float(options.get("sizeVariety", size_variety))
	growth_rate = float(options.get("growthRate", growth_rate))
	lake_elevation_limit = int(options.get("lakeElevationLimit", lake_elevation_limit))
	coast_enabled = bool(options.get("coastEnabled", coast_enabled))
	coast_max_depth = int(options.get("coastMaxDepth", coast_max_depth))
	coast_amplitude = float(options.get("coastAmplitude", coast_amplitude))


## Move a completed worker result onto the main-thread singleton. The worker
## creates all generated graphs independently, so this is only reference
## assignment and does not duplicate the large cell arrays.
func adopt_generation(other: FmgSim) -> void:
	apply_generation_options(other.get_generation_options())
	rng = other.rng
	grid = other.grid
	pack = other.pack
	hydrology = other.hydrology
	burgs = other.burgs
	routes_gen = other.routes_gen
	generation_time_ms = other.generation_time_ms
	poles_cache = other.poles_cache
	province_poles_cache = other.province_poles_cache


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
		["Лёд", func() -> void: _stage_ice()],
		["Ресурсы", func() -> void: _stage_goods()],
		["Население", func() -> void: _stage_population()],
		["Культуры", func() -> void: _stage_cultures()],
		["Города", func() -> void: _stage_burgs()],
		["Государства", func() -> void: _stage_states()],
		["Дипломатия", func() -> void: _stage_diplomacy()],
		["Дороги", func() -> void: _stage_routes()],
		["Религии", func() -> void: _stage_religions()],
		["Провинции", func() -> void: _stage_provinces()],
		["Имена", func() -> void: _stage_names()],
		["Рынки", func() -> void: _stage_markets()],
		["Производство", func() -> void: _stage_production()],
		["Налоги", func() -> void: _stage_taxes()],
		["Армии", func() -> void: _stage_military()],
		["Маркеры", func() -> void: _stage_markers()],
		["Зоны", func() -> void: _stage_zones()],
		["Геральдика", func() -> void: _stage_emblems()],
		["Путешествия", func() -> void: _stage_journeys()],
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
	# riversSpecify: re-check parent/basin chains after all rivers settled
	if hydrology != null:
		hydrology.specify()
	# river names and types + lake names, based on local cultures
	if pack.rivers.size() > 1:
		var lengths: Array = []
		for river in pack.rivers:
			if river != null:
				lengths.append(float(river.get("length", 0.0)))
		lengths.sort()
		var small_length: float = lengths[mini(int(ceil(float(lengths.size()) * 0.15)), lengths.size() - 1)] if lengths.size() > 0 else 0.0

		for river in pack.rivers:
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

	# ocean, sea, lake and landmass names (features-generator defineNames)
	var feature_names := FmgFeatureNames.new(rng, pack)
	feature_names.define_names()


func _stage_ice() -> void:
	var ice := FmgIce.new(rng, grid, pack)
	ice.generate()


func _stage_goods() -> void:
	var goods := FmgGoods.new(rng, pack, grid)
	goods.generate()


func _stage_diplomacy() -> void:
	var diplomacy := FmgDiplomacy.new(rng, pack, grid)
	diplomacy.generate()


func _stage_routes() -> void:
	routes_gen = FmgRoutes.new(rng, pack, grid)
	routes_gen.generate()


func _stage_markets() -> void:
	var markets := FmgMarkets.new(rng, pack, grid)
	markets.generate()


func _stage_production() -> void:
	var production := FmgProduction.new(rng, pack, grid)
	production.produce()


func _stage_taxes() -> void:
	var production := FmgProduction.new(rng, pack, grid)
	production.collect_taxes()


func _stage_military() -> void:
	var military := FmgMilitary.new(rng, pack, grid)
	military.generate()


func _stage_markers() -> void:
	var markers := FmgMarkers.new(rng, pack, grid, routes_gen)
	markers.generate()


func _stage_zones() -> void:
	var zones := FmgZones.new(rng, pack, grid, routes_gen)
	zones.generate()


func _stage_emblems() -> void:
	var emblems := FmgEmblems.new(rng, pack)
	emblems.generate()


func _stage_journeys() -> void:
	if routes_gen == null:
		return
	var journeys := FmgJourneys.new(rng, pack, routes_gen)
	journeys.generate(3)


## regenerates everything downstream of the heightmap (after a height edit)
func pipeline_from_heightmap() -> Array:
	return pipeline().slice(2)


## regenerates everything downstream of the climate (after a climate edit):
## temperature, precipitation, pack graph and all layers above it
func pipeline_from_climate() -> Array:
	return pipeline().slice(3)


## run a single pipeline stage; main.gd drives the loop (one stage per couple
## of frames to keep the UI responsive). Broadcasts stage_started.
func run_stage(stage: Array) -> void:
	stage_started.emit(stage[0])
	var stage_fn: Callable = stage[1]
	stage_fn.call()


## called by main.gd when the pipeline is complete: records the generation
## time and broadcasts map_generated
func finish_generation(start_ms: int) -> void:
	generation_time_ms = Time.get_ticks_msec() - start_ms
	map_generated.emit()


func get_stats_text() -> String:
	if pack == null:
		return "Карта не сгенерирована"
	var land_cells: int = 0
	for i: int in pack.cell_count():
		if pack.h[i] >= SEA_LEVEL:
			land_cells += 1
	var states_count: int = 0
	for s in pack.states:
		if s != null and int(s["i"]) > 0:
			states_count += 1
	var burgs_count: int = 0
	for b in pack.burgs:
		if b != null:
			burgs_count += 1
	var rivers_count: int = maxi(pack.rivers.size() - 1, 0)
	var regiments: int = 0
	for s in pack.states:
		if s != null and s.has("military"):
			regiments += (s["military"] as Array).size()
	return "Ячеек: %d · Суши: %d%% · Государств: %d · Городов: %d · Рек: %d · Дорог: %d · Маркеров: %d · Полков: %d · Зон: %d · Время: %d мс" % [
		pack.cell_count(), int(100.0 * land_cells / maxi(pack.cell_count(), 1)),
		states_count, burgs_count, rivers_count, pack.routes.size(),
		pack.markers.size(), regiments, pack.zones.size(), generation_time_ms
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
			"pop": Array(pack.pop),
			"good": Array(pack.good),
			"market": Array(pack.market)
		},
		"cultures": pack.cultures,
		"states": pack.states,
		"burgs": pack.burgs,
		"provinces": pack.provinces,
		"religions": pack.religions,
		"rivers": pack.rivers,
		"routes": _pack_routes(),
		"markers": _pack_markers(),
		"zones": pack.zones,
		"markets": pack.markets,
		"deals": pack.deals,
		"ice": _pack_ice(),
		"journeys": _pack_journeys(),
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


## routes hold PackedVector2Array points which JSON.stringify would mangle
func _pack_routes() -> Array:
	var out: Array = []
	for route: Variant in pack.routes:
		var r: Dictionary = (route as Dictionary).duplicate()
		r["points"] = _pack_points(r.get("points", PackedVector2Array()))
		out.append(r)
	return out


func _pack_ice() -> Array:
	var out: Array = []
	for ice: Variant in pack.ice:
		var e: Dictionary = (ice as Dictionary).duplicate()
		e["points"] = _pack_points(e.get("points", PackedVector2Array()))
		out.append(e)
	return out


func _pack_markers() -> Array:
	var out: Array = []
	for marker: Variant in pack.markers:
		out.append((marker as Dictionary).duplicate())
	return out


func _pack_journeys() -> Array:
	var out: Array = []
	for journey: Variant in pack.journeys:
		var j: Dictionary = (journey as Dictionary).duplicate()
		j["points"] = _pack_points(j.get("points", PackedVector2Array()))
		out.append(j)
	return out


func _unpack_journeys(arr: Array) -> Array:
	var out: Array = []
	for entry: Variant in arr:
		var j: Dictionary = (entry as Dictionary).duplicate()
		j["points"] = _unpack_points(Array(j.get("points", [])))
		out.append(j)
	return out


func _collect_feature_names() -> Dictionary:
	var out := {}
	if pack != null:
		for feature in pack.features:
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
	# The initial grid is triangulated with its outer pseudo-points. Reuse
	# exactly that boundary on load; omitting it changes the outer Voronoi
	# cells and was the source of clipped/corrupted map edges after reload.
	_rebuild_voronoi(grid, true)
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
	pack.good = PackedInt32Array(Array(pack_data.get("good", [])))
	if pack.good.is_empty():
		pack.good.resize(pack.cell_count())
	pack.market = PackedInt32Array(Array(pack_data.get("market", [])))
	if pack.market.is_empty():
		pack.market.resize(pack.cell_count())

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
	pack.routes = _unpack_routes(data.get("routes", []))
	pack.markers = data.get("markers", [])
	pack.zones = data.get("zones", [])
	pack.markets = data.get("markets", [])
	_normalize_loaded_market_goods()
	pack.deals = data.get("deals", [])
	pack.ice = _unpack_ice(data.get("ice", []))
	pack.journeys = _unpack_journeys(data.get("journeys", []))
	_rebuild_cell_routes()
	_rebuild_route_links()

	hydrology = FmgHydrology.new(rng, grid, pack)
	burgs = FmgBurgs.new(rng, pack, grid)
	burgs.set_hydrology(hydrology)
	burgs.states_limit = states_limit
	burgs.burgs_limit = burgs_limit
	return OK


## JSON object keys are strings. Keep the in-memory market schema identical
## to a freshly generated map so recipe production and trade code can be run
## after loading as well.
func _normalize_loaded_market_goods() -> void:
	for market_value: Variant in pack.markets:
		var market: Dictionary = market_value
		var goods_value: Variant = market.get("goods", {})
		if not goods_value is Dictionary:
			market["goods"] = {}
			continue
		var normalized := {}
		for key: Variant in (goods_value as Dictionary):
			normalized[int(key)] = (goods_value as Dictionary)[key]
		market["goods"] = normalized


func _unpack_points(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(arr.size())
	for i: int in arr.size():
		out[i] = Vector2(arr[i][0], arr[i][1])
	return out


func _unpack_routes(arr: Array) -> Array:
	var out: Array = []
	for entry: Variant in arr:
		var r: Dictionary = (entry as Dictionary).duplicate()
		r["points"] = _unpack_points(Array(r.get("points", [])))
		out.append(r)
	return out


func _unpack_ice(arr: Array) -> Array:
	var out: Array = []
	for entry: Variant in arr:
		var e: Dictionary = (entry as Dictionary).duplicate()
		e["points"] = _unpack_points(Array(e.get("points", [])))
		out.append(e)
	return out


## rebuild pack.cell_routes / route_links from loaded routes
func _rebuild_cell_routes() -> void:
	pack.cell_routes = {}
	for route: Variant in pack.routes:
		var rid: int = int((route as Dictionary).get("i", 0))
		for i: int in (route as Dictionary).get("cells", []).size() - 1:
			var a: int = int((route as Dictionary)["cells"][i])
			var b: int = int((route as Dictionary)["cells"][i + 1])
			if not pack.cell_routes.has(a):
				pack.cell_routes[a] = {}
			if not pack.cell_routes.has(b):
				pack.cell_routes[b] = {}
			pack.cell_routes[a][b] = rid
			pack.cell_routes[b][a] = rid


func _rebuild_route_links() -> void:
	pack.route_links = {}
	for route: Variant in pack.routes:
		var cells_arr: Array = (route as Dictionary).get("cells", [])
		for i: int in cells_arr.size() - 1:
			pack.route_links["%d-%d" % [cells_arr[i], cells_arr[i + 1]]] = true
			pack.route_links["%d-%d" % [cells_arr[i + 1], cells_arr[i]]] = true
	if routes_gen != null:
		routes_gen.route_links = pack.route_links


func _rebuild_voronoi(graph: FmgGraph, include_boundary: bool = false) -> void:
	var points := PackedVector2Array(graph.points)
	if include_boundary:
		points.append_array(graph.boundary)
	var del := Delaunator.from_points(points)
	var voronoi := FmgVoronoi.new()
	voronoi._build(del, points.size(), graph.points.size())
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
	_stage_ice()
	_stage_goods()
	_stage_population()
	_stage_cultures()
	_stage_burgs()
	_stage_states()
	_stage_diplomacy()
	_stage_routes()
	_stage_religions()
	_stage_provinces()
	_stage_names()
	_stage_markets()
	_stage_production()
	_stage_taxes()
	_stage_military()
	_stage_markers()
	_stage_zones()
	_stage_emblems()
	_stage_journeys()
