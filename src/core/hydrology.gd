class_name FmgHydrology
extends RefCounted
## Rivers and lakes. Port of river-generator.ts and lakes.ts.
## Water drains from high to low ground, flux accumulates, tributaries merge;
## depressions become lakes with outlets, evaporation and river feeding.

const SEA_LEVEL: int = 20
const MIN_FLUX_TO_FORM_RIVER: float = 30.0
const MIN_NAVIGABLE_FLUX: float = 100.0
const FLUX_FACTOR: float = 500.0
const MAX_FLUX_WIDTH: float = 1.0
const LENGTH_FACTOR: float = 200.0

var rng: FmgRng
var grid: FmgGraph
var pack: FmgGraph
var lake_elevation_limit: int = 20
var resolve_depressions_steps: int = 250


func _init(rng_ref: FmgRng, grid_ref: FmgGraph, pack_ref: FmgGraph) -> void:
	rng = rng_ref
	grid = grid_ref
	pack = pack_ref


static func get_offset(flux: float, point_index: int, width_factor: float, starting_width: float) -> float:
	if point_index == 0:
		return starting_width
	var flux_width: float = minf(pow(flux, 0.7) / FLUX_FACTOR, MAX_FLUX_WIDTH)
	# upstream: LENGTH_PROGRESSION = [1,1,2,3,5,8,13,21,34].map(n => n / LENGTH_FACTOR)
	var progression: Array = [1.0, 1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0, 34.0]
	var progression_value: float = (progression[point_index] if point_index < progression.size() else 34.0) / LENGTH_FACTOR
	var length_width: float = point_index / LENGTH_FACTOR + progression_value
	return width_factor * (length_width + flux_width) + starting_width


static func get_source_width(flux: float) -> float:
	return FmgRng.rn(minf(pow(flux, 0.9) / FLUX_FACTOR, MAX_FLUX_WIDTH), 2)


static func get_width(offset: float) -> float:
	return FmgRng.rn(pow(offset / 1.5, 1.8), 2)


## smoothed heights adjusted by the distance field (rivers flow over this)
func alter_heights() -> PackedFloat32Array:
	var h := pack.h
	var t := pack.t
	var out := PackedFloat32Array()
	out.resize(h.size())
	for i: int in h.size():
		var hv: float = float(h[i])
		if hv < 20.0 or t[i] < 1:
			out[i] = hv
			continue
		var neib_sum: float = 0.0
		for n: int in pack.c[i]:
			neib_sum += float(t[n])
		out[i] = hv + float(t[i]) / 100.0 + (neib_sum / float(pack.c[i].size())) / 10000.0
	return out


## depression filling algorithm (for correct water flux modeling)
func resolve_depressions(h: PackedFloat32Array) -> void:
	var max_iterations: int = resolve_depressions_steps
	var check_lake_max_iteration: float = max_iterations * 0.85
	var elevate_lake_max_iteration: float = max_iterations * 0.75

	var lakes: Array = []
	for feature in pack.features:
		if feature != null and not feature.is_empty() and feature["type"] == "lake":
			lakes.append(feature)

	var land := PackedInt32Array()
	for i: int in pack.cell_count():
		if pack.h[i] >= SEA_LEVEL and pack.b[i] == 0:
			land.append(i)
	land.sort() # stable enough; then custom sort by height
	var land_arr := Array(land)
	land_arr.sort_custom(func(a: int, b: int) -> bool:
		if h[a] != h[b]:
			return h[a] < h[b]
		return a < b)

	var cell_height := func(i: int) -> float:
		var fid: int = pack.f[i]
		if fid > 0 and fid < pack.features.size():
			var fh: float = pack.features[fid].get("height", 0.0)
			if fh != 0.0:
				return fh
		return h[i]

	var progress: Array = []
	var depressions: int = 9999999
	var prev_depressions: int = -1
	var iteration: int = 0
	while depressions > 0 and iteration < max_iterations:
		if progress.size() > 5:
			var sum_p: float = 0.0
			for p: float in progress:
				sum_p += p
			if sum_p > 0.0:
				h = alter_heights()
				depressions = progress[0]
				break

		depressions = 0

		if iteration < check_lake_max_iteration:
			for lake: Dictionary in lakes:
				if lake.get("closed", false):
					continue
				var shoreline: PackedInt32Array = lake["shoreline"]
				if shoreline.is_empty():
					continue
				var min_height: float = INF
				for s_cell: int in shoreline:
					min_height = minf(min_height, h[s_cell])
				if min_height >= 100.0 or lake["height"] > min_height:
					continue

				if iteration > elevate_lake_max_iteration:
					for s_cell: int in shoreline:
						h[s_cell] = float(pack.h[s_cell])
					var min_h2: float = INF
					for s_cell: int in shoreline:
						min_h2 = minf(min_h2, h[s_cell])
					lake["height"] = min_h2 - 1.0
					lake["closed"] = true
					continue

				depressions += 1
				lake["height"] = min_height + 0.2

		for i: int in land_arr:
			var min_height: float = INF
			for n: int in pack.c[i]:
				min_height = minf(min_height, cell_height.call(n))
			if min_height >= 100.0 or h[i] > min_height:
				continue
			depressions += 1
			h[i] = min_height + 0.1

		if prev_depressions >= 0:
			progress.append(depressions - prev_depressions)
		prev_depressions = depressions
		iteration += 1

	if depressions > 0:
		push_warning("Unresolved depressions: %d. Edit heightmap to fix" % depressions)


## check if a lake can potentially pour out (not in a deep depression)
func detect_close_lakes(h: PackedFloat32Array) -> void:
	for feature in pack.features:
		if feature == null or feature.is_empty() or feature["type"] != "lake":
			continue
		feature.erase("closed")

		var max_elevation: float = feature["height"] + float(lake_elevation_limit)
		if max_elevation > 99.0:
			feature["closed"] = false
			continue

		var is_deep: bool = true
		var shoreline: PackedInt32Array = feature["shoreline"]
		if shoreline.is_empty():
			feature["closed"] = false
			continue
		var lowest_cell: int = shoreline[0]
		for s_cell: int in shoreline:
			if h[s_cell] < h[lowest_cell]:
				lowest_cell = s_cell
		var queue: Array = [lowest_cell]
		var checked := PackedByteArray()
		checked.resize(pack.cell_count())
		checked[lowest_cell] = 1

		while not queue.is_empty() and is_deep:
			var cell_id: int = queue.pop_back()
			for neib_cell: int in pack.c[cell_id]:
				if checked[neib_cell]:
					continue
				if h[neib_cell] >= max_elevation:
					continue
				if h[neib_cell] < SEA_LEVEL:
					var n_fid: int = pack.f[neib_cell]
					if n_fid > 0 and n_fid < pack.features.size():
						var n_feature: Dictionary = pack.features[n_fid]
						if n_feature["type"] == "ocean" or feature["height"] > n_feature.get("height", 0.0):
							is_deep = false
				checked[neib_cell] = 1
				queue.append(neib_cell)

		feature["closed"] = is_deep


## lake flux/temp/evaporation and the cell each open lake drains through
func define_lake_climate_data(h: PackedFloat32Array) -> PackedInt32Array:
	var lake_out_cells := PackedInt32Array()
	lake_out_cells.resize(pack.cell_count())

	for feature in pack.features:
		if feature == null or feature.is_empty() or feature["type"] != "lake":
			continue
		var shoreline: PackedInt32Array = feature["shoreline"]

		var flux: float = 0.0
		for s_cell: int in shoreline:
			flux += float(grid.prec[pack.g[s_cell]])
		feature["flux"] = flux

		var lake_temp: float
		if feature["cells"] < 6:
			lake_temp = float(grid.temp[pack.g[feature["firstCell"]]])
		else:
			var sum_t: float = 0.0
			for s_cell: int in shoreline:
				sum_t += float(grid.temp[pack.g[s_cell]])
			lake_temp = FmgRng.rn(sum_t / float(maxi(shoreline.size(), 1)), 1)
		feature["temp"] = lake_temp

		var height_m: float = pow(feature["height"] - 18.0, 2.0)
		var evaporation: float = ((700.0 * (lake_temp + 0.006 * height_m)) / 50.0 + 75.0) / (80.0 - lake_temp)
		feature["evaporation"] = FmgRng.rn(evaporation * float(feature["cells"]), 0)

		if feature.get("closed", false):
			continue

		var out_cell: int = -1
		var min_h: float = INF
		for s_cell: int in shoreline:
			if h[s_cell] < min_h:
				min_h = h[s_cell]
				out_cell = s_cell
		feature["outCell"] = out_cell
		if out_cell >= 0:
			lake_out_cells[out_cell] = feature["i"]

	return lake_out_cells


func cleanup_lake_data() -> void:
	for feature in pack.features:
		if feature == null or feature.is_empty() or feature["type"] != "lake":
			continue
		feature.erase("river")
		feature.erase("enteringFlux")
		feature.erase("outCell")
		feature.erase("closed")
		feature["height"] = FmgRng.rn(feature["height"], 3)
		if feature.has("inlets"):
			var kept: Array = []
			for inlet: int in feature["inlets"]:
				for river in pack.rivers:
					if river == null:
						continue
					if river["i"] == inlet:
						kept.append(inlet)
						break
			if kept.is_empty():
				feature.erase("inlets")
			else:
				feature["inlets"] = kept
		if feature.has("outlet"):
			var has_outlet: bool = false
			for river in pack.rivers:
				if river == null:
					continue
				if river["i"] == feature["outlet"]:
					has_outlet = true
					break
			if not has_outlet:
				feature.erase("outlet")


## main river generation: drain water, form rivers, resolve confluences
func generate(allow_erosion: bool = true) -> void:
	var cells := pack
	cells.fl = PackedFloat32Array()
	cells.fl.resize(cells.cell_count())
	cells.r = PackedInt32Array()
	cells.r.resize(cells.cell_count())
	cells.conf = PackedInt32Array()
	cells.conf.resize(cells.cell_count())
	var rivers_data := {} # riverId -> PackedInt32Array of cells
	var river_parents := {} # riverId -> parent river id
	var river_next: int = 1

	var h := alter_heights()
	detect_close_lakes(h)
	resolve_depressions(h)

	var cells_number_modifier: float = pow(float(grid.points.size()) / 10000.0, 0.25)
	var default_width_factor: float = FmgRng.rn(1.0 / pow(float(grid.points.size()) / 10000.0, 0.25), 2)
	var main_stem_width_factor: float = default_width_factor * 1.2

	# --- drain water ---
	var prec := grid.prec
	var land: Array = []
	for i: int in cells.cell_count():
		if h[i] >= 20.0:
			land.append(i)
	land.sort_custom(func(a: int, b: int) -> bool:
		if h[a] != h[b]:
			return h[a] > h[b]
		return a < b)

	var lake_out_cells := define_lake_climate_data(h)

	var add_cell_to_river := func(cell_id: int, river_id: int) -> void:
		if not rivers_data.has(river_id):
			rivers_data[river_id] = PackedInt32Array()
		# Packed arrays copied through an inline `as` cast: append to a local
		# and write the value back, otherwise the append is silently lost.
		var river_cells: PackedInt32Array = rivers_data[river_id]
		river_cells.append(cell_id)
		rivers_data[river_id] = river_cells

	var flow_down := func(to_cell: int, from_flux: float, river_id: int) -> void:
		var to_flux: float = cells.fl[to_cell] - float(cells.conf[to_cell])
		var to_river: int = cells.r[to_cell]

		if to_river != 0:
			if from_flux > to_flux:
				cells.conf[to_cell] += int(cells.fl[to_cell])
				if h[to_cell] >= 20.0:
					river_parents[to_river] = river_id
				cells.r[to_cell] = river_id
			else:
				cells.conf[to_cell] += int(from_flux)
				if h[to_cell] >= 20.0:
					river_parents[river_id] = to_river
		else:
			cells.r[to_cell] = river_id

		if h[to_cell] < 20.0:
			var water_fid: int = cells.f[to_cell]
			if water_fid > 0 and water_fid < pack.features.size():
				var water_body: Dictionary = pack.features[water_fid]
				if water_body["type"] == "lake":
					if not water_body.has("river") or from_flux > float(water_body.get("enteringFlux", 0.0)):
						water_body["river"] = river_id
						water_body["enteringFlux"] = from_flux
					water_body["flux"] = float(water_body.get("flux", 0.0)) + from_flux
					if not water_body.has("inlets"):
						water_body["inlets"] = [river_id]
					else:
						var inlets: Array = water_body["inlets"]
						inlets.append(river_id)
						water_body["inlets"] = inlets
		else:
			cells.fl[to_cell] += from_flux

		add_cell_to_river.call(to_cell, river_id)

	for i: int in land:
		cells.fl[i] += float(prec[cells.g[i]]) / cells_number_modifier

		# create lake outlet if the lake is not in a deep depression and flux > evaporation
		var lakes_for_cell: Array = []
		if lake_out_cells[i] != 0:
			var lake_fid: int = lake_out_cells[i]
			var lake: Dictionary = pack.features[lake_fid]
			if float(lake.get("flux", 0.0)) > float(lake.get("evaporation", 0.0)):
				lakes_for_cell.append(lake)

		for lake: Dictionary in lakes_for_cell:
			var lake_cell: int = -1
			for c: int in cells.c[i]:
				if h[c] < 20.0 and cells.f[c] == lake["i"]:
					lake_cell = c
					break
			if lake_cell < 0:
				continue
			cells.fl[lake_cell] += maxf(float(lake["flux"]) - float(lake["evaporation"]), 0.0)

			# allow chain lakes to retain identity
			if cells.r[lake_cell] != int(lake.get("river", 0)):
				var same_river: bool = false
				var lake_river: int = int(lake.get("river", 0))
				if lake_river != 0:
					for c: int in cells.c[lake_cell]:
						if cells.r[c] == lake_river:
							same_river = true
							break
				if same_river:
					cells.r[lake_cell] = lake_river
					add_cell_to_river.call(lake_cell, lake_river)
				else:
					cells.r[lake_cell] = river_next
					add_cell_to_river.call(lake_cell, river_next)
					river_next += 1

			lake["outlet"] = cells.r[lake_cell]
			flow_down.call(i, cells.fl[lake_cell], lake["outlet"])

		# assign all tributary rivers of lakes to the outlet basin
		if not lakes_for_cell.is_empty():
			var outlet: int = lakes_for_cell[0].get("outlet", 0)
			for lake: Dictionary in lakes_for_cell:
				if not lake.has("inlets"):
					continue
				for inlet: int in lake["inlets"]:
					river_parents[inlet] = outlet

		# near-border cell: pour water out of the map
		if cells.b[i] == 1 and cells.r[i] != 0:
			add_cell_to_river.call(-1, cells.r[i])
			continue

		# downhill cell
		var min_cell: int = -1
		if lake_out_cells[i] != 0:
			var lake_ids := {}
			for lake: Dictionary in lakes_for_cell:
				lake_ids[lake["i"]] = true
			for c: int in cells.c[i]:
				if not lake_ids.has(cells.f[c]):
					if min_cell < 0 or h[c] < h[min_cell]:
						min_cell = c
		elif cells.haven[i] != 0:
			min_cell = cells.haven[i]
		else:
			for c: int in cells.c[i]:
				if min_cell < 0 or h[c] < h[min_cell]:
					min_cell = c

		if min_cell < 0:
			continue
		if h[i] <= h[min_cell]:
			continue

		if cells.fl[i] < MIN_FLUX_TO_FORM_RIVER:
			if h[min_cell] >= 20.0:
				cells.fl[min_cell] += cells.fl[i]
			continue

		if cells.r[i] == 0:
			cells.r[i] = river_next
			add_cell_to_river.call(i, river_next)
			river_next += 1

		flow_down.call(min_cell, cells.fl[i], cells.r[i])

	# --- define rivers ---
	cells.r = PackedInt32Array()
	cells.r.resize(cells.cell_count())
	cells.conf = PackedInt32Array()
	cells.conf.resize(cells.cell_count())
	pack.rivers = [null]

	for river_id_v: Variant in rivers_data:
		var river_id: int = river_id_v
		var river_cells: PackedInt32Array = rivers_data[river_id]
		if river_cells.size() < 3:
			continue

		for cell_id: int in river_cells:
			if cell_id < 0 or h[cell_id] < 20.0:
				continue
			if cells.r[cell_id] != 0:
				cells.conf[cell_id] = 1
			else:
				cells.r[cell_id] = river_id

		var source: int = river_cells[0]
		var mouth: int = river_cells[river_cells.size() - 2]
		var parent: int = river_parents.get(river_id, 0)

		var width_factor: float = main_stem_width_factor if parent == 0 or parent == river_id else default_width_factor
		var meandered := _meander_river(river_cells)
		var discharge: float = cells.fl[mouth]
		var length_v: float = _approximate_length(meandered)
		var source_width: float = get_source_width(cells.fl[source])
		var width_v: float = get_width(get_offset(discharge, meandered.size(), width_factor, source_width))

		pack.rivers.append({
			"i": river_id,
			"source": source,
			"mouth": mouth,
			"discharge": discharge,
			"length": length_v,
			"width": width_v,
			"widthFactor": width_factor,
			"sourceWidth": source_width,
			"parent": parent,
			"cells": river_cells,
			"name": "",
			"type": ""
		})

	_calculate_confluence_flux(h)
	cleanup_lake_data()

	if allow_erosion:
		for i: int in pack.cell_count():
			pack.h[i] = int(clampf(h[i], 0.0, 100.0))
		_downcut_rivers()


## meander the river path between cell centers (deterministic)
func _meander_river(river_cells: PackedInt32Array) -> PackedVector2Array:
	var start_step: int = 1 if pack.h[river_cells[0]] < SEA_LEVEL else 10
	var is_water_cell: Array = []
	for c: int in river_cells:
		is_water_cell.append(c != -1 and pack.h[c] < SEA_LEVEL)
	var result := FmgPaths.meander(river_cells, pack.points, 0.5, start_step, Vector2(pack.width, pack.height), is_water_cell)
	return result["points"]


func _approximate_length(points: PackedVector2Array) -> float:
	var length_v: float = 0.0
	for i: int in range(1, points.size()):
		length_v += points[i].distance_to(points[i - 1])
	return FmgRng.rn(length_v, 2)


func _downcut_rivers() -> void:
	const MAX_DOWNCUT: int = 5
	for i: int in pack.cell_count():
		if pack.h[i] < 35:
			continue
		if pack.fl[i] == 0.0:
			continue
		var higher_sum: float = 0.0
		var higher_count: float = 0.0
		for c: int in pack.c[i]:
			if pack.h[c] > pack.h[i]:
				higher_sum += pack.fl[c]
				higher_count += 1.0
		if higher_count == 0.0:
			continue
		var higher_flux: float = higher_sum / higher_count
		if higher_flux == 0.0:
			continue
		var downcut: int = int(pack.fl[i] / higher_flux)
		if downcut > 0:
			pack.h[i] = maxi(pack.h[i] - mini(downcut, MAX_DOWNCUT), 0)


func _calculate_confluence_flux(h: PackedFloat32Array) -> void:
	for i: int in pack.cell_count():
		if pack.conf[i] == 0:
			continue
		var influxes: Array = []
		for c: int in pack.c[i]:
			if pack.r[c] != 0 and h[c] > h[i]:
				influxes.append(pack.fl[c])
		influxes.sort()
		influxes.reverse()
		var acc: float = 0.0
		for idx: int in influxes.size():
			if idx == 0:
				continue
			acc += influxes[idx]
		pack.conf[i] = int(acc)


# --- river polygon building for rendering ---

## Meandered centerline of a river with a per-point half-width (offset).
## Shared by the ribbon builder and the tapered-stroke renderer: ribbons whose
## meander loops self-intersect cannot be triangulated, so the renderer falls
## back to stroking the centerline with these widths.
func _river_offset_path(river: Dictionary) -> Dictionary:
	var river_cells: PackedInt32Array = river["cells"]
	if river_cells.size() < 2:
		return {}
	var start_step: int = 1 if pack.h[river_cells[0]] < SEA_LEVEL else 10
	var is_water_cell: Array = []
	for c: int in river_cells:
		is_water_cell.append(c != -1 and pack.h[c] < SEA_LEVEL)
	var result := FmgPaths.meander(river_cells, pack.points, 0.5, start_step, Vector2(pack.width, pack.height), is_water_cell)
	var points: PackedVector2Array = result["points"]
	var anchor_indices: PackedInt32Array = result["anchorIndices"]

	# flux per meandered point
	var flux := PackedFloat32Array()
	flux.resize(points.size())
	for ai: int in anchor_indices.size():
		var point_index: int = anchor_indices[ai]
		var cell_id: int = river_cells[ai]
		var flux_cell: int = river_cells[ai - 1] if cell_id == -1 and ai > 0 else cell_id
		flux[point_index] = pack.fl[flux_cell] if flux_cell >= 0 else 0.0

	var width_factor: float = river["widthFactor"]
	var starting_width: float = river["sourceWidth"]
	var offsets := PackedFloat32Array()
	offsets.resize(points.size())
	var flux_acc: float = 0.0
	var n: int = points.size()
	for point_index: int in n:
		flux_acc = maxf(flux_acc, flux[point_index])
		offsets[point_index] = get_offset(flux_acc, point_index, width_factor, starting_width)
	return {"points": points, "offsets": offsets}


## Centerline + full widths (diameters) for tapered stroke rendering.
func get_river_stroke(river: Dictionary) -> Dictionary:
	var path: Dictionary = _river_offset_path(river)
	if path.is_empty():
		return {}
	var offsets: PackedFloat32Array = path["offsets"]
	var widths := PackedFloat32Array()
	widths.resize(offsets.size())
	for i: int in offsets.size():
		widths[i] = offsets[i] * 2.0
	return {"points": path["points"], "widths": widths}


## getRiverPath port: build the tapered polygon of a river from its cells
func get_river_polygon(river: Dictionary) -> PackedVector2Array:
	var path: Dictionary = _river_offset_path(river)
	if path.is_empty():
		return PackedVector2Array()
	var points: PackedVector2Array = path["points"]
	var offsets: PackedFloat32Array = path["offsets"]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n: int = points.size()

	for point_index: int in n:
		var p_prev: Vector2 = points[point_index - 1] if point_index > 0 else points[point_index]
		var p_cur: Vector2 = points[point_index]
		var p_next: Vector2 = points[point_index + 1] if point_index < n - 1 else points[point_index]

		var offset: float = offsets[point_index]
		var angle: float = atan2(p_prev.y - p_next.y, p_prev.x - p_next.x)
		var sin_offset: float = sin(angle) * offset
		var cos_offset: float = cos(angle) * offset

		left.append(Vector2(p_cur.x - sin_offset, p_cur.y + cos_offset))
		right.append(Vector2(p_cur.x + sin_offset, p_cur.y - cos_offset))

	right.reverse()
	var polygon := PackedVector2Array(left)
	polygon.append_array(right)
	var smooth_polygon := FmgPaths.chaikin(polygon, true, 1)
	return smooth_polygon


func is_navigable(cell_id: int) -> bool:
	return pack.r[cell_id] != 0 and pack.fl[cell_id] >= MIN_NAVIGABLE_FLUX


## walk an outlet chain starting from a lake feature
func resolve_lake_drain_feature(lake_feature_id: int) -> int:
	var lake: Dictionary = pack.features[lake_feature_id]
	if lake.is_empty() or lake["type"] != "lake":
		return 0
	if not lake.has("outlet"):
		return lake_feature_id

	var river_by_id := {}
	for river in pack.rivers:
		if river != null:
			river_by_id[river["i"]] = river

	var visited := {}
	var river: Dictionary = river_by_id.get(lake["outlet"], null)
	while river != null and not visited.has(river["i"]):
		visited[river["i"]] = true
		var cells_path: PackedInt32Array = river["cells"]
		var last_cell: int = cells_path[cells_path.size() - 1]
		if last_cell < 0:
			return 0
		var feature: Dictionary = pack.features[pack.f[last_cell]]
		if feature.is_empty():
			return 0
		if feature["type"] == "ocean":
			return feature["i"]
		if feature["type"] != "lake":
			return 0
		if not feature.has("outlet"):
			return feature["i"]
		river = river_by_id.get(feature["outlet"], null)
	return 0


## walk a river chain downstream through lakes until the final receiving body
func resolve_drain_feature(cell_id: int) -> int:
	var start_river: int = pack.r[cell_id]
	if start_river == 0:
		return 0

	var river_by_id := {}
	for river in pack.rivers:
		if river != null:
			river_by_id[river["i"]] = river

	var visited := {}
	var river: Dictionary = river_by_id.get(start_river, null)
	while river != null and not visited.has(river["i"]):
		visited[river["i"]] = true
		var cells_path: PackedInt32Array = river["cells"]
		var last_cell: int = cells_path[cells_path.size() - 1]
		if last_cell < 0:
			return 0
		var feature: Dictionary = pack.features[pack.f[last_cell]]
		if feature.is_empty():
			return 0
		if feature["type"] == "ocean":
			return feature["i"]
		if feature["type"] != "lake":
			return 0
		if not feature.has("outlet"):
			return feature["i"]
		river = river_by_id.get(feature["outlet"], null)
	return 0


## recalculate river parents/basins after edits
func specify() -> void:
	if pack.rivers.size() <= 1:
		return
	for river in pack.rivers:
		if river == null:
			continue
		river["parent"] = _get_parent(river["i"])
		river["basin"] = _get_basin(river["i"])


func _get_parent(r: int) -> int:
	for river in pack.rivers:
		if river != null and river["i"] == r:
			var parent: int = river["parent"]
			if parent == 0 or parent == r:
				return r
			if not _river_exists(parent):
				return r
			return parent
	return r


func _river_exists(r: int) -> bool:
	for river in pack.rivers:
		if river != null and river["i"] == r:
			return true
	return false


func _get_basin(r: int) -> int:
	var parent: int = _get_parent(r)
	if parent == r:
		return r
	return _get_basin(parent)
