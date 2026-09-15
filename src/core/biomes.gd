class_name FmgBiomes
extends RefCounted
## Biomes: hot↔cold × dry↕wet matrix. Port of biomes-generator.ts.

const MIN_LAND_HEIGHT: int = 20
const SEA_LEVEL: int = 20

# hot ↔ cold [>19°C; <-4°C]; dry ↕ wet
const BIOMES_MATRIX := [
	[1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 10],
	[3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 9, 9, 9, 9, 10, 10, 10],
	[5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 9, 9, 9, 9, 9, 10, 10, 10],
	[5, 6, 6, 6, 6, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 10, 10, 10],
	[7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 10, 10]
]

const NAMES: Array = [
	"Marine", "Hot desert", "Cold desert", "Savanna", "Grassland",
	"Tropical seasonal forest", "Temperate deciduous forest", "Tropical rainforest",
	"Temperate rainforest", "Taiga", "Tundra", "Glacier", "Wetland"
]

const COLORS: Array = [
	"#466eab", "#fbe79f", "#b5b887", "#d2d082", "#c8d68f",
	"#b6d95d", "#29bc56", "#7dcb35", "#409c43", "#4b6b32",
	"#96784b", "#d5e7eb", "#0b9131"
]

const HABITABILITY: Array = [0, 4, 10, 22, 30, 50, 100, 80, 90, 12, 4, 0, 12]

const COST: Array = [10, 200, 150, 60, 50, 70, 70, 80, 90, 200, 1000, 5000, 150]

## Russian names for the UI
const NAMES_RU: Array = [
	"Море", "Горячая пустыня", "Холодная пустыня", "Саванна", "Луга",
	"Тропический сезонный лес", "Умеренный лиственный лес", "Тропический дождевой лес",
	"Умеренный дождевой лес", "Тайга", "Тундра", "Ледник", "Болото"
]


static func get_default_biomes() -> Array:
	var out: Array = [null]
	for i: int in NAMES.size():
		out.append({
			"i": i,
			"name": NAMES[i],
			"nameRu": NAMES_RU[i],
			"color": COLORS[i],
			"habitability": HABITABILITY[i],
			"cost": COST[i]
		})
	return out


static func define(pack: FmgGraph, grid: FmgGraph) -> void:
	if pack.biomes.is_empty():
		pack.biomes = get_default_biomes()
	pack.biome = PackedByteArray()
	pack.biome.resize(pack.cell_count())

	var flux := pack.fl
	var river_ids := pack.r
	var heights := pack.h
	var neighbors: Array = pack.c
	var grid_ref := grid.prec
	var grid_temp := grid.temp

	for cell_id: int in pack.cell_count():
		var height: int = heights[cell_id]
		var moisture: int = 0
		if height >= MIN_LAND_HEIGHT:
			moisture = _calculate_moisture(cell_id, neighbors, heights, river_ids, flux, grid_ref, grid.g)
		var temperature: int = grid_temp[grid.g[cell_id]]
		pack.biome[cell_id] = get_biome_id(moisture, temperature, height, river_ids[cell_id] != 0)


static func _calculate_moisture(cell_id: int, neighbors: Array, heights: PackedByteArray, river_ids: PackedInt32Array, flux: PackedFloat32Array, grid_prec: PackedInt32Array, grid_mapping: PackedInt32Array) -> int:
	var moisture: int = grid_prec[grid_mapping[cell_id]]
	if river_ids[cell_id] != 0:
		moisture += int(maxf(flux[cell_id] / 10.0, 2.0))
	var sum_v: float = float(moisture)
	var count: float = 1.0
	for neib: int in neighbors[cell_id]:
		if heights[neib] >= MIN_LAND_HEIGHT:
			sum_v += float(grid_prec[grid_mapping[neib]])
			count += 1.0
	return roundi(4.0 + sum_v / count)


static func get_biome_id(moisture: int, temperature: int, height: int, has_river: bool) -> int:
	if height < 20:
		return 0 # all water cells: marine biome
	if temperature < -5:
		return 11 # too cold: permafrost
	if temperature >= 25 and not has_river and moisture < 8:
		return 1 # too hot and dry: hot desert
	if _is_wetland(moisture, temperature, height):
		return 12 # too wet: wetland

	var moisture_band: int = mini(moisture / 5, 4)
	var temperature_band: int = clampi(20 - temperature, 0, 25)
	return BIOMES_MATRIX[moisture_band][temperature_band]


static func _is_wetland(moisture: int, temperature: int, height: int) -> bool:
	if temperature <= -2:
		return false
	if moisture > 40 and height < 25:
		return true
	if moisture > 24 and height > 24 and height < 60:
		return true
	return false


class Population:
	extends RefCounted
	## Assess cell suitability, calculate population. Port of population-generator.ts.

	const COAST_SCORES := {
		"estuary": 15.0,
		"ocean_coast": 5.0,
		"safe_harbor": 20.0,
		"freshwater": 30.0,
		"salt": 10.0,
		"frozen": 1.0,
		"dry": -5.0,
		"sinkhole": -5.0,
		"lava": -30.0
	}

	static func rank_cells(pack: FmgGraph, _rng: FmgRng) -> void:
		var cells_count: int = pack.cell_count()
		pack.s = PackedInt32Array()
		pack.s.resize(cells_count)
		pack.pop = PackedFloat32Array()
		pack.pop.resize(cells_count)

		var fluxes: Array = []
		for f: float in pack.fl:
			if f > 0:
				fluxes.append(f)
		fluxes.sort()
		var mean_flux: float = fluxes[fluxes.size() / 2] if fluxes.size() > 0 else 0.0
		var max_fl: float = 0.0
		var max_conf: float = 0.0
		for f: float in pack.fl:
			max_fl = maxf(max_fl, f)
		for c: int in pack.conf:
			max_conf = maxf(max_conf, float(c))
		var mean_area: float = 0.0
		for a: float in pack.area:
			mean_area += a
		mean_area /= float(maxi(cells_count, 1))

		for i: int in cells_count:
			if pack.h[i] < 20:
				continue
			var score: float = pack.biomes[pack.biome[i]]["habitability"]
			if score == 0:
				continue
			if mean_flux > 0.0:
				score += FmgRng.normalize(pack.fl[i] + float(pack.conf[i]), mean_flux, max_fl + max_conf) * 250.0
			score -= (float(pack.h[i]) - 50.0) / 5.0

			if pack.t[i] == 1:
				if pack.r[i] != 0:
					score += COAST_SCORES["estuary"]
				var haven_cell: int = pack.haven[i]
				var fid: int = pack.f[haven_cell]
				if fid > 0 and fid < pack.features.size():
					var feature: Dictionary = pack.features[fid]
					if feature["type"] == "lake":
						score += COAST_SCORES.get(feature.get("subtype", ""), 0.0)
					else:
						score += COAST_SCORES["ocean_coast"]
						if pack.harbor[i] == 1:
							score += COAST_SCORES["safe_harbor"]

			pack.s[i] = int(score / 5.0)
			pack.pop[i] = (float(pack.s[i]) * pack.area[i]) / mean_area if pack.s[i] > 0 else 0.0
