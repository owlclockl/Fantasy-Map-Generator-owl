class_name FmgClimate
extends RefCounted
## Temperature and precipitation models. Port of temperature-generator.ts
## and precipitation-generator.ts.

const SEA_LEVEL: int = 20
const LATITUDE_MODIFIER: Array = [4.0, 2.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0, 2.0, 2.0, 3.0, 3.0, 2.0, 2.0, 1.0, 1.0, 1.0, 0.5]
const MAX_PASSABLE_ELEVATION: int = 85

var temperature_equator: float = 27.0
var temperature_north_pole: float = -30.0
var temperature_south_pole: float = -15.0
var winds: Array = [225.0, 45.0, 225.0, 315.0, 135.0, 315.0]
var precipitation_level: float = 100.0
var height_exponent: float = 2.0
var lat_n: float = 90.0
var lat_s: float = -90.0
var lat_t: float = 180.0


## calculate the temperature of every grid cell from its latitude and altitude
func generate_temperature(grid: FmgGraph) -> void:
	var cells_count: int = grid.cell_count()
	grid.temp = PackedInt32Array()
	grid.temp.resize(cells_count)

	var tropics: Array = [16.0, -20.0]
	var tropical_gradient: float = 0.15
	var temp_north_tropic: float = temperature_equator - tropics[0] * tropical_gradient
	var northern_gradient: float = (temp_north_tropic - temperature_north_pole) / (90.0 - tropics[0])
	var temp_south_tropic: float = temperature_equator + tropics[1] * tropical_gradient
	var southern_gradient: float = (temp_south_tropic - temperature_south_pole) / (90.0 + tropics[1])

	var row: int = 0
	while row < cells_count:
		var y: float = grid.points[row].y
		var row_latitude: float = lat_n - (y / grid.height) * lat_t
		var sea_level_temp: float = _sea_level_temperature(row_latitude, temp_north_tropic, temp_south_tropic, tropical_gradient, northern_gradient, southern_gradient, tropics)
		for cell_id: int in range(row, mini(row + grid.cells_x, cells_count)):
			var drop: float = 0.0
			if grid.h[cell_id] >= SEA_LEVEL:
				drop = FmgRng.rn((pow(float(grid.h[cell_id] - 18), height_exponent) / 1000.0) * 6.5)
			grid.temp[cell_id] = int(clampf(sea_level_temp - drop, -128.0, 127.0))
		row += grid.cells_x


func _sea_level_temperature(latitude: float, tnt: float, tst: float, tg: float, ng: float, sg: float, tropics: Array) -> float:
	var is_tropical: bool = latitude <= 16.0 and latitude >= -20.0
	if is_tropical:
		return temperature_equator - absf(latitude) * tg
	if latitude > 0.0:
		return tnt - (latitude - tropics[0]) * ng
	return tst + (latitude - tropics[1]) * sg


## winds enter the map from each side and drop humidity as they pass the cells
func generate_precipitation(grid: FmgGraph, cells_desired: int, rng: FmgRng) -> void:
	var cells_count: int = grid.cell_count()
	grid.prec = PackedInt32Array()
	grid.prec.resize(cells_count)
	var cells_x: int = grid.cells_x
	var cells_y: int = grid.cells_y

	var cells_number_modifier: float = pow(float(cells_desired) / 10000.0, 0.25)
	var modifier: float = cells_number_modifier * (precipitation_level / 100.0)

	var winds_data := get_winds(grid)

	# westerly and easterly winds
	_pass_wind(grid, winds_data["westerly"], 120.0 * modifier, 1, cells_x, modifier, rng)
	_pass_wind(grid, winds_data["easterly"], 120.0 * modifier, -1, cells_x, modifier, rng)

	var vert_t: int = winds_data["southerly"] + winds_data["northerly"]
	# A user may configure all six belts as horizontal winds. In that case
	# there is no north/south share to distribute; avoid the 0/0 division and
	# let the horizontal passes provide precipitation normally.
	if vert_t > 0 and winds_data["northerly"] > 0:
		var band_n: int = int((absf(lat_n) - 1.0) / 5.0)
		var lat_mod_n: float = _mean(LATITUDE_MODIFIER) if lat_t > 60.0 else LATITUDE_MODIFIER[clampi(band_n, 0, 17)]
		var max_prec_n: float = (float(winds_data["northerly"]) / float(vert_t)) * 60.0 * modifier * lat_mod_n
		var north_sources := PackedInt32Array()
		for i: int in cells_x:
			north_sources.append(i)
		_pass_wind(grid, north_sources, max_prec_n, cells_x, cells_y, modifier, rng)

	if vert_t > 0 and winds_data["southerly"] > 0:
		var band_s: int = int((absf(lat_s) - 1.0) / 5.0)
		var lat_mod_s: float = _mean(LATITUDE_MODIFIER) if lat_t > 60.0 else LATITUDE_MODIFIER[clampi(band_s, 0, 17)]
		var max_prec_s: float = (float(winds_data["southerly"]) / float(vert_t)) * 60.0 * modifier * lat_mod_s
		var south_sources := PackedInt32Array()
		for i: int in range(cells_count - cells_x, cells_count):
			south_sources.append(i)
		_pass_wind(grid, south_sources, max_prec_s, -cells_x, cells_y, modifier, rng)


static func _mean(arr: Array) -> float:
	var sum_v: float = 0.0
	for v: float in arr:
		sum_v += v
	return sum_v / float(arr.size())


## rows and columns the prevailing winds enter the map through
func get_winds(grid: FmgGraph) -> Dictionary:
	var cells_count: int = grid.cell_count()
	var cells_x: int = grid.cells_x
	var cells_y: int = grid.cells_y
	var westerly: Array = []
	var easterly: Array = []
	var northerly: int = 0
	var southerly: int = 0

	var row_id: int = 0
	var cell_id: int = 0
	while cell_id < cells_count:
		var lat: float = lat_n - (float(row_id) / float(cells_y)) * lat_t
		var lat_mod: float = LATITUDE_MODIFIER[clampi(int((absf(lat) - 1.0) / 5.0), 0, 17)]
		var tier: int = int(absf(lat - 89.0) / 30.0)
		var angle: float = winds[clampi(tier, 0, 5)]

		if angle > 40.0 and angle < 140.0:
			westerly.append([cell_id, lat_mod, tier])
		if angle > 220.0 and angle < 320.0:
			easterly.append(cell_id + cells_x - 1)
		if angle > 100.0 and angle < 260.0:
			northerly += 1
		if angle > 280.0 or angle < 80.0:
			southerly += 1

		row_id += 1
		cell_id += cells_x

	return {"westerly": westerly, "easterly": easterly, "northerly": northerly, "southerly": southerly}


func _pass_wind(grid: FmgGraph, sources: Array, initial_max_prec: float, next: int, steps: int, modifier: float, rng: FmgRng) -> void:
	var h := grid.h
	var temp := grid.temp
	var prec := grid.prec
	var cells_count: int = grid.cell_count()

	var max_prec: float = initial_max_prec
	for source: Variant in sources:
		var first: int = 0
		if source is Array:
			if source[0] == 0:
				continue # legacy quirk of the original
			max_prec = minf(initial_max_prec * float(source[1]), 255.0)
			first = source[0]
		else:
			first = source

		var humidity: float = max_prec - float(h[first])
		if humidity <= 0.0:
			continue

		var current: int = first
		for s: int in steps:
			var idx: int = current + next * s
			if idx < 0 or idx >= cells_count:
				break
			if temp[idx] < -5:
				continue

			if h[idx] < SEA_LEVEL:
				var ahead: int = idx + next
				if ahead >= 0 and ahead < cells_count and h[ahead] >= SEA_LEVEL:
					prec[ahead] += int(maxf(humidity / rng.range_f(10.0, 20.0), 1.0))
				else:
					humidity = minf(humidity + 5.0 * modifier, max_prec)
					prec[idx] += int(5.0 * modifier)
				continue

			var ahead_cell: int = idx + next
			var is_passable: bool = ahead_cell < 0 or ahead_cell >= cells_count or h[ahead_cell] <= MAX_PASSABLE_ELEVATION
			var precipitation: float = 0.0
			if is_passable:
				var normal_loss: float = maxf(humidity / (10.0 * modifier), 1.0)
				var diff: float = 0.0
				if ahead_cell >= 0 and ahead_cell < cells_count:
					diff = maxf(float(h[ahead_cell]) - float(h[idx]), 0.0)
				var mod: float = pow(float(h[ahead_cell]) / 70.0, 2.0) if ahead_cell >= 0 and ahead_cell < cells_count else 0.0
				precipitation = clampf(normal_loss + diff * mod, 1.0, humidity)
			else:
				precipitation = humidity
			prec[idx] += int(precipitation)
			var evaporation: float = 1.0 if precipitation > 1.5 else 0.0
			humidity = clampf(humidity - precipitation + evaporation, 0.0, max_prec) if is_passable else 0.0
