class_name HeightmapGenerator
extends RefCounted
## Heightmap templates and tools. Port of heightmap-generator.ts.
## Each template is a script of steps: `Tool count height rangeX rangeY`.

const SEA_LEVEL: int = 20

var grid: FmgGraph = null
var heights := PackedByteArray()
var blob_power: float = 0.98
var line_power: float = 0.81
var _width: float = 1280.0
var _height: float = 800.0
var _rng: FmgRng = null


static func get_blob_power(cells: int) -> float:
	if cells <= 1000: return 0.93
	if cells <= 2000: return 0.95
	if cells <= 5000: return 0.97
	if cells <= 10000: return 0.98
	if cells <= 20000: return 0.99
	if cells <= 30000: return 0.991
	if cells <= 40000: return 0.993
	if cells <= 50000: return 0.994
	if cells <= 60000: return 0.995
	if cells <= 70000: return 0.9955
	if cells <= 80000: return 0.996
	if cells <= 90000: return 0.9964
	return 0.9973


static func get_line_power(cells: int) -> float:
	if cells <= 1000: return 0.75
	if cells <= 2000: return 0.77
	if cells <= 5000: return 0.79
	if cells <= 10000: return 0.81
	if cells <= 20000: return 0.82
	if cells <= 30000: return 0.83
	if cells <= 40000: return 0.84
	if cells <= 50000: return 0.86
	if cells <= 60000: return 0.87
	if cells <= 70000: return 0.88
	if cells <= 80000: return 0.91
	if cells <= 90000: return 0.92
	return 0.93


func _set_graph(graph: FmgGraph, cells_desired: int, width: float, height: float, rng: FmgRng) -> void:
	_width = width
	_height = height
	heights = PackedByteArray(graph.h)
	blob_power = get_blob_power(cells_desired)
	line_power = get_line_power(cells_desired)
	grid = graph
	_rng = rng


func _point_in_range(range_s: String, length: float) -> float:
	var parts := range_s.split("-")
	var min_v: float = parts[0].to_float() / 100.0
	var max_v: float = parts[1].to_float() / 100.0 if parts.size() > 1 else min_v
	return _rng.range_f(min_v * length, max_v * length)


func add_hill(count: String, height: String, range_x: String, range_y: String) -> void:
	var desired: float = _rng.get_number_in_range(count)
	for _i: int in int(desired):
		_add_one_hill(height, range_x, range_y)


func _add_one_hill(height: String, range_x: String, range_y: String) -> void:
	var change := PackedByteArray()
	change.resize(heights.size())
	var limit: int = 0
	var start: int = 0
	var h: float = FmgRng.lim(_rng.get_number_in_range(height))
	while true:
		var x: float = _point_in_range(range_x, _width)
		var y: float = _point_in_range(range_y, _height)
		start = grid.find_cell(x, y)
		limit += 1
		if not (heights[start] + h > 90.0 and limit < 50):
			break
	change[start] = int(h)
	var queue: Array = [start]
	while not queue.is_empty():
		var q: int = queue.pop_front()
		for c: int in grid.c[q]:
			if change[c]:
				continue
			change[c] = int(clampf(pow(float(change[q]), blob_power) * (_rng.random() * 0.2 + 0.9), 0.0, 255.0))
			if change[c] > 1:
				queue.append(c)
	for i: int in heights.size():
		heights[i] = int(FmgRng.lim(float(heights[i]) + float(change[i])))


func add_pit(count: String, height: String, range_x: String, range_y: String) -> void:
	var desired: float = _rng.get_number_in_range(count)
	for _i: int in int(desired):
		_add_one_pit(height, range_x, range_y)


func _add_one_pit(height: String, range_x: String, range_y: String) -> void:
	var used := PackedByteArray()
	used.resize(heights.size())
	var limit: int = 0
	var start: int = 0
	var h: float = FmgRng.lim(_rng.get_number_in_range(height))
	while true:
		var x: float = _point_in_range(range_x, _width)
		var y: float = _point_in_range(range_y, _height)
		start = grid.find_cell(x, y)
		limit += 1
		if not (heights[start] < 20 and limit < 50):
			break
	var queue: Array = [start]
	while not queue.is_empty():
		var q: int = queue.pop_front()
		h = pow(h, blob_power) * (_rng.random() * 0.2 + 0.9)
		if h < 1.0:
			return
		for c: int in grid.c[q]:
			if used[c]:
				continue
			heights[c] = int(FmgRng.lim(float(heights[c]) - h * (_rng.random() * 0.2 + 0.9)))
			used[c] = 1
			queue.append(c)


func add_range(count: String, height: String, range_x: String, range_y: String, start_cell: int = -1, end_cell: int = -1, randomness: float = 0.15) -> void:
	var desired: float = _rng.get_number_in_range(count)
	for _i: int in int(desired):
		_add_one_range(height, range_x, range_y, start_cell, end_cell, randomness)


func _get_ridge(cur: int, end: int, used: PackedByteArray, randomness: float) -> PackedInt32Array:
	var ridge := PackedInt32Array([cur])
	var p := grid.points
	used[cur] = 1
	while cur != end:
		var min_d: float = INF
		var next: int = -1
		for e: int in grid.c[cur]:
			if used[e]:
				continue
			var diff: float = pow(p[end].x - p[e].x, 2.0) + pow(p[end].y - p[e].y, 2.0)
			if _rng.random() > 1.0 - randomness:
				diff = diff / 2.0
			if diff < min_d:
				min_d = diff
				next = e
		if next < 0 or min_d == INF:
			return ridge
		cur = next
		ridge.append(cur)
		used[cur] = 1
	return ridge


func _add_one_range(height: String, range_x: String, range_y: String, start_cell: int, end_cell: int, randomness: float) -> void:
	var used := PackedByteArray()
	used.resize(heights.size())
	var h: float = FmgRng.lim(_rng.get_number_in_range(height))
	if start_cell < 0 and not range_x.is_empty():
		var start_x: float = _point_in_range(range_x, _width)
		var start_y: float = _point_in_range(range_y, _height)
		var dist: float = 0.0
		var limit: int = 0
		var end_x: float = 0.0
		var end_y: float = 0.0
		while true:
			end_x = _rng.random() * _width * 0.8 + _width * 0.1
			end_y = _rng.random() * _height * 0.7 + _height * 0.15
			dist = absf(end_y - start_y) + absf(end_x - start_x)
			limit += 1
			if not ((dist < _width / 8.0 or dist > _width / 3.0) and limit < 50):
				break
		start_cell = grid.find_cell(start_x, start_y)
		end_cell = grid.find_cell(end_x, end_y)

	var ridge := _get_ridge(start_cell, end_cell, used, randomness)

	# add height to the ridge and cells around, wave by wave
	var queue := PackedInt32Array(ridge)
	var i: int = 0
	while not queue.is_empty():
		var frontier := PackedInt32Array(queue)
		queue = PackedInt32Array()
		i += 1
		for f_cell: int in frontier:
			heights[f_cell] = int(FmgRng.lim(float(heights[f_cell]) + h * (_rng.random() * 0.3 + 0.85)))
		h = pow(h, line_power) - 1.0
		if h < 2.0:
			break
		for f_cell: int in frontier:
			for nc: int in grid.c[f_cell]:
				if used[nc] == 0:
					queue.append(nc)
					used[nc] = 1

	# generate prominences
	for d: int in ridge.size():
		var cur: int = ridge[d]
		if d % 6 != 0:
			continue
		for _l: int in i:
			var min_h: float = INF
			var min_cell: int = cur
			for nc: int in grid.c[cur]:
				if float(heights[nc]) < min_h:
					min_h = float(heights[nc])
					min_cell = nc
			heights[min_cell] = int((float(heights[cur]) * 2.0 + float(heights[min_cell])) / 3.0)
			cur = min_cell


func add_trough(count: String, height: String, range_x: String, range_y: String, start_cell: int = -1, end_cell: int = -1, randomness: float = 0.2) -> void:
	var desired: float = _rng.get_number_in_range(count)
	for _i: int in int(desired):
		_add_one_trough(height, range_x, range_y, start_cell, end_cell, randomness)


func _add_one_trough(height: String, range_x: String, range_y: String, start_cell: int, end_cell: int, randomness: float) -> void:
	var used := PackedByteArray()
	used.resize(heights.size())
	var h: float = FmgRng.lim(_rng.get_number_in_range(height))
	if start_cell < 0 and not range_x.is_empty():
		var limit: int = 0
		var start_x: float = 0.0
		var start_y: float = 0.0
		while true:
			start_x = _point_in_range(range_x, _width)
			start_y = _point_in_range(range_y, _height)
			start_cell = grid.find_cell(start_x, start_y)
			limit += 1
			if not (heights[start_cell] < 20 and limit < 50):
				break
		limit = 0
		var end_x: float = 0.0
		var end_y: float = 0.0
		while true:
			end_x = _rng.random() * _width * 0.8 + _width * 0.1
			end_y = _rng.random() * _height * 0.7 + _height * 0.15
			limit += 1
			var dist: float = absf(end_y - start_y) + absf(end_x - start_x)
			if not ((dist < _width / 8.0 or dist > _width / 2.0) and limit < 50):
				break
		end_cell = grid.find_cell(end_x, end_y)

	var ridge := _get_ridge(start_cell, end_cell, used, randomness)

	var queue := PackedInt32Array(ridge)
	var i: int = 0
	while not queue.is_empty():
		var frontier := PackedInt32Array(queue)
		queue = PackedInt32Array()
		i += 1
		for f_cell: int in frontier:
			heights[f_cell] = int(FmgRng.lim(float(heights[f_cell]) - h * (_rng.random() * 0.3 + 0.85)))
		h = pow(h, line_power) - 1.0
		if h < 2.0:
			break
		for f_cell: int in frontier:
			for nc: int in grid.c[f_cell]:
				if used[nc] == 0:
					queue.append(nc)
					used[nc] = 1

	for d: int in ridge.size():
		var cur: int = ridge[d]
		if d % 6 != 0:
			continue
		for _l: int in i:
			var min_h: float = INF
			var min_cell: int = cur
			for nc: int in grid.c[cur]:
				if float(heights[nc]) < min_h:
					min_h = float(heights[nc])
					min_cell = nc
			heights[min_cell] = int((float(heights[cur]) * 2.0 + float(heights[min_cell])) / 3.0)
			cur = min_cell


func add_strait(width_s: String, direction: String = "vertical") -> void:
	var desired_width: float = minf(_rng.get_number_in_range(width_s), grid.cells_x / 3.0)
	if desired_width < 1.0 and _rng.P(desired_width):
		return
	var used := PackedByteArray()
	used.resize(heights.size())
	var vert: bool = direction == "vertical"
	var start_x: float = floorf(_rng.random() * _width * 0.4 + _width * 0.3) if vert else 5.0
	var start_y: float = 5.0 if vert else floorf(_rng.random() * _height * 0.4 + _height * 0.3)
	var end_x: float = (floorf(_width - start_x - _width * 0.1 + _rng.random() * _width * 0.2)) if vert else _width - 5.0
	var end_y: float = (_height - 5.0) if vert else floorf(_height - start_y - _height * 0.1 + _rng.random() * _height * 0.2)

	var start: int = grid.find_cell(start_x, start_y)
	var end: int = grid.find_cell(end_x, end_y)

	# get the strait course
	var range_cells := PackedInt32Array()
	var cur: int = start
	var p := grid.points
	while cur != end:
		var min_d: float = INF
		for e: int in grid.c[cur]:
			var diff: float = pow(p[end].x - p[e].x, 2.0) + pow(p[end].y - p[e].y, 2.0)
			if _rng.random() > 0.8:
				diff = diff / 2.0
			if diff < min_d:
				min_d = diff
				cur = e
		range_cells.append(cur)

	var query := PackedInt32Array()
	var step: float = 0.1 / desired_width
	for i: int in int(desired_width):
		var remaining_width: float = desired_width - float(i)
		var exp_v: float = 0.9 - step * remaining_width
		for r_cell: int in range_cells:
			for e: int in grid.c[r_cell]:
				if used[e]:
					continue
				used[e] = 1
				query.append(e)
				heights[e] = int(clampf(pow(float(heights[e]), exp_v), 0.0, 100.0))
				if float(heights[e]) > 100.0:
					heights[e] = 5
		range_cells = PackedInt32Array(query)
		query = PackedInt32Array()


func modify(range_s: String, add_v: float, mult: float, power: float = 0.0) -> void:
	var min_v: float = 20.0 if range_s == "land" else (0.0 if range_s == "all" else range_s.split("-")[0].to_float())
	var max_v: float = 100.0 if range_s == "land" or range_s == "all" else range_s.split("-")[1].to_float()
	var is_land: bool = min_v == 20.0
	for i: int in heights.size():
		var h: float = float(heights[i])
		if h < min_v or h > max_v:
			continue
		if add_v != 0.0:
			h = maxf(h + add_v, 20.0) if is_land else h + add_v
		if mult != 1.0:
			h = (h - 20.0) * mult + 20.0 if is_land else h * mult
		if power != 0.0:
			h = pow(h - 20.0, power) + 20.0 if is_land else pow(h, power)
		heights[i] = int(FmgRng.lim(h))


func smooth(fr: int = 2, add_v: float = 0.0) -> void:
	var old := PackedByteArray(heights)
	for i: int in heights.size():
		var sum_v: float = float(old[i])
		var count: float = 1.0
		for c: int in grid.c[i]:
			sum_v += float(old[c])
			count += 1.0
		var mean_v: float = sum_v / count
		if fr == 1:
			heights[i] = int(FmgRng.lim(mean_v + add_v))
		else:
			heights[i] = int(FmgRng.lim((float(old[i]) * float(fr - 1) + mean_v + add_v) / float(fr)))


func mask(power: float = 1.0) -> void:
	var fr: float = absf(power) if power != 0.0 else 1.0
	for i: int in heights.size():
		var x: float = grid.points[i].x
		var y: float = grid.points[i].y
		var nx: float = 2.0 * x / _width - 1.0
		var ny: float = 2.0 * y / _height - 1.0
		var distance: float = (1.0 - nx * nx) * (1.0 - ny * ny)
		if power < 0.0:
			distance = 1.0 - distance
		var masked: float = float(heights[i]) * distance
		heights[i] = int(FmgRng.lim((float(heights[i]) * (fr - 1.0) + masked) / fr))


func invert(count: float, axes: String) -> void:
	if not _rng.P(count):
		return
	var invert_x: bool = axes != "y"
	var invert_y: bool = axes != "x"
	var old := PackedByteArray(heights)
	for i: int in heights.size():
		var x: int = i % grid.cells_x
		var y: int = int(float(i) / float(grid.cells_x))
		var nx: int = grid.cells_x - x - 1 if invert_x else x
		var ny: int = grid.cells_y - y - 1 if invert_y else y
		heights[i] = old[nx + ny * grid.cells_x]


func add_step(tool: String, a2: String, a3: String, a4: String, a5: String) -> void:
	match tool:
		"Hill": add_hill(a2, a3, a4, a5)
		"Pit": add_pit(a2, a3, a4, a5)
		"Range": add_range(a2, a3, a4, a5)
		"Trough": add_trough(a2, a3, a4, a5)
		"Strait": add_strait(a2, a3)
		"Mask": mask(a2.to_float())
		"Invert": invert(a2.to_float(), a3)
		"Add": modify(a3, a2.to_float(), 1.0)
		"Multiply": modify(a3, 0.0, a2.to_float())
		"Smooth": smooth(a2.to_int())


## Build heights from a named template into the graph
func from_template(graph: FmgGraph, template_id: String, cells_desired: int, width: float, height: float, rng: FmgRng) -> PackedByteArray:
	var template_string: String = HeightmapTemplates.get_template(template_id)
	var steps := template_string.split("\n")
	_set_graph(graph, cells_desired, width, height, rng)
	for step_v: String in steps:
		var elements := step_v.strip_edges().split(" ", false)
		if elements.size() < 2:
			continue
		while elements.size() < 5:
			elements.append("0")
		add_step(elements[0], elements[1], elements[2], elements[3], elements[4])
	return heights


## Build the heights from one of the pre-created real-world heightmaps.
## Exactly like the original: the image is stretched to the grid (one pixel per
## cell) and every cell takes the lightness of its pixel — values below 0.2 pass
## through, everything above is flattened by the 0.8 power curve, and the result
## becomes a 0..100 height.
func from_precreated(
	graph: FmgGraph, template_id: String, cells_desired: int, width: float, height: float, rng: FmgRng
) -> PackedByteArray:
	_set_graph(graph, cells_desired, width, height, rng)
	var image: Image = load_precreated_image(template_id)
	if image == null:
		push_warning("Не удалось прочитать высотную карту «%s», беру процедурный шаблон" % template_id)
		return from_template(graph, "continents", cells_desired, width, height, rng)

	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(graph.cells_x, graph.cells_y, Image.INTERPOLATE_BILINEAR)

	var out: PackedByteArray = heights
	out.resize(graph.points.size())
	for row: int in graph.cells_y:
		var base: int = row * graph.cells_x
		for col: int in graph.cells_x:
			var index: int = base + col
			if index >= out.size():
				break
			var lightness: float = image.get_pixel(col, row).r
			var powered: float = lightness
			if lightness >= 0.2:
				powered = 0.2 + pow(lightness - 0.2, 0.8)
			out[index] = clampi(int(floor(powered * 100.0)), 0, 100)
	heights = out
	return out


## Read data/heightmaps/<id>.png without the texture importer: the folder carries
## a .gdignore, so the bytes are the exact grayscale data of the original.
static func load_precreated_image(template_id: String) -> Image:
	var path: String = HeightmapTemplates.precreated_file(template_id)
	if path.is_empty():
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK:
			return image
	# fallback for builds where the PNG was imported as a texture instead
	# (the .gdignore in data/heightmaps keeps the importer away by default, so an
	# exported build must add `data/heightmaps/*.png` to the non-resource export
	# filter, otherwise the raw files are not packed at all)
	if ResourceLoader.exists(path):
		var texture: Texture2D = ResourceLoader.load(path) as Texture2D
		if texture != null:
			return texture.get_image()
	return null


## Pick a random template id weighted by the template probabilities
static func get_random_template_id(rng: FmgRng) -> String:
	var weights := {}
	for id: String in HeightmapTemplates.TEMPLATES:
		weights[id] = HeightmapTemplates.TEMPLATES[id]["probability"]
	return rng.rw(weights)
