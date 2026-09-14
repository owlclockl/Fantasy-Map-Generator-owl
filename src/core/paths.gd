class_name FmgPaths
extends RefCounted
## Geometry helpers ported from the original FMG utils:
## clipPoly (lineclip), simplify (RDP), meander, spline sampling,
## coastline fractalization and smooth path flattening.

## Sutherland–Hodgman polygon clip against the map rectangle. Port of clipPoly.
static func clip_poly(points: PackedVector2Array, graph_width: float, graph_height: float, secure: bool = false) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var rect := Rect2(0, 0, graph_width, graph_height)
	var clipped := _clip_polygon_rect(points, rect)
	if not secure:
		return clipped
	var secured := PackedVector2Array()
	for p: Vector2 in clipped:
		secured.append(p)
		if is_equal_approx(p.x, 0.0) or is_equal_approx(p.x, graph_width) or is_equal_approx(p.y, 0.0) or is_equal_approx(p.y, graph_height):
			secured.append(p)
			secured.append(p)
	return secured


static func _clip_polygon_rect(points: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var output := points
	for side: int in 4:
		var input := output
		output = PackedVector2Array()
		if input.is_empty():
			return output
		# side: 0=left 1=right 2=top 3=bottom
		for i: int in input.size():
			var cur: Vector2 = input[i]
			var prev: Vector2 = input[(i + input.size() - 1) % input.size()]
			var cur_in: bool = _inside(cur, side, rect)
			var prev_in: bool = _inside(prev, side, rect)
			if cur_in:
				if not prev_in:
					output.append(_intersect(prev, cur, side, rect))
				output.append(cur)
			elif prev_in:
				output.append(_intersect(prev, cur, side, rect))
	return output


static func _inside(p: Vector2, side: int, rect: Rect2) -> bool:
	match side:
		0: return p.x >= rect.position.x
		1: return p.x <= rect.end.x
		2: return p.y >= rect.position.y
		_: return p.y <= rect.end.y


static func _intersect(a: Vector2, b: Vector2, side: int, rect: Rect2) -> Vector2:
	var d := b - a
	match side:
		0:
			var t: float = (rect.position.x - a.x) / (d.x if d.x != 0.0 else 1e-12)
			return a + d * t
		1:
			var t: float = (rect.end.x - a.x) / (d.x if d.x != 0.0 else 1e-12)
			return a + d * t
		2:
			var t: float = (rect.position.y - a.y) / (d.y if d.y != 0.0 else 1e-12)
			return a + d * t
		_:
			var t: float = (rect.end.y - a.y) / (d.y if d.y != 0.0 else 1e-12)
			return a + d * t


static func project_to_nearest_edge(p: Vector2, width: float, height: float) -> Vector2:
	var dl: float = p.x
	var dr: float = width - p.x
	var dt: float = p.y
	var db: float = height - p.y
	var m: float = minf(minf(dl, dr), minf(dt, db))
	if m == dl: return Vector2(0, p.y)
	if m == dr: return Vector2(width, p.y)
	if m == dt: return Vector2(p.x, 0)
	return Vector2(p.x, height)


## Signed polygon area (positive = clockwise in screen coords)
static func polygon_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = points.size()
	for i: int in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func polygon_centroid(points: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Vector2 in points:
		c += p
	return c / float(maxi(points.size(), 1))


## Ramer–Douglas–Peucker simplification of a closed ring (port of simplify.js behavior)
static func simplify(points: PackedVector2Array, tolerance: float = 0.3) -> PackedVector2Array:
	var n: int = points.size()
	if n < 4 or tolerance <= 0.0:
		return points
	# split the closed ring at two extreme points to keep endpoints fixed
	var min_i: int = 0
	var max_i: int = 0
	for i: int in n:
		if points[i].x < points[min_i].x: min_i = i
		if points[i].x > points[max_i].x: max_i = i
	if min_i == max_i:
		return points
	var first: int = mini(min_i, max_i)
	var second: int = maxi(min_i, max_i)
	var part1 := _rdp(points.slice(first, second + 1), tolerance)
	var part2_arr := PackedVector2Array()
	for i: int in range(second, n):
		part2_arr.append(points[i])
	for i: int in range(0, first + 1):
		part2_arr.append(points[i])
	var part2 := _rdp(part2_arr, tolerance)
	var result := PackedVector2Array(part1)
	result.append_array(part2.slice(1))
	return result


static func _rdp(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array = [[0, n - 1]]
	var tol2: float = tolerance * tolerance
	while not stack.is_empty():
		var range_pair: Array = stack.pop_back()
		var first_i: int = range_pair[0]
		var last_i: int = range_pair[1]
		var max_dist: float = 0.0
		var index: int = first_i
		for i: int in range(first_i + 1, last_i):
			var d: float = _perp_dist2(points[i], points[first_i], points[last_i])
			if d > max_dist:
				max_dist = d
				index = i
		if max_dist > tol2:
			keep[index] = 1
			stack.append([first_i, index])
			stack.append([index, last_i])
	var result := PackedVector2Array()
	for i: int in n:
		if keep[i]:
			result.append(points[i])
	return result


static func _perp_dist2(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2: float = ab.length_squared()
	if l2 == 0.0:
		return (p - a).length_squared()
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (p - (a + ab * t)).length_squared()


## Chaikin corner-cutting smoothing of a (closed) polyline
static func chaikin(points: PackedVector2Array, closed: bool, iterations: int = 1) -> PackedVector2Array:
	var pts := points
	for _it: int in iterations:
		pts = _chaikin_once(pts, closed)
	return pts


static func _chaikin_once(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	var last_i: int = n if closed else n - 1
	for i: int in last_i:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		out.append(a * 0.75 + b * 0.25)
		out.append(a * 0.25 + b * 0.75)
	if not closed:
		out[0] = points[0]
		out[out.size() - 1] = points[n - 1]
	return out


## Catmull-Rom (centripetal-ish, tension via FMG's /8 tangents) spline sampled into points
static func catmull_rom(points: PackedVector2Array, closed: bool, samples_per_seg: int = 4) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	var last_i: int = n if closed else n - 1
	for i: int in last_i:
		var p0: Vector2 = points[(i - 1 + n) % n] if closed else points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var p3: Vector2 = points[(i + 2) % n] if closed else points[mini(i + 2, n - 1)]
		var end_i: int = samples_per_seg if i < last_i - 1 or closed else samples_per_seg + 1
		for s: int in end_i:
			var t: float = float(s) / float(samples_per_seg)
			var t2: float = t * t
			var t3: float = t2 * t
			var m1 := (p2 - p0) * 0.125
			var m2 := (p3 - p1) * 0.125
			var pos := 2.0 * t3 - 3.0 * t2 + 1.0
			out.append(pos * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2)
	if closed:
		out.append(out[0])
	return out


## Quadratic B-spline (curveBasisClosed equivalent) sampled into points
static func basis_closed(points: PackedVector2Array, samples_per_seg: int = 3) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	for i: int in n:
		var p0: Vector2 = points[(i - 1 + n) % n]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var m := (p0 + p1 * 2.0 + p2) / 4.0
		var prev_m: Vector2 = (points[(i - 2 + n) % n] + p0 * 2.0 + p1) / 4.0 if n > 2 else m
		for s: int in samples_per_seg:
			var t: float = float(s) / float(samples_per_seg)
			out.append(prev_m.lerp(m, t))
	out.append(out[0])
	return out


# ---------------------------------------------------------------------------
# Coastline fractalization (port of coastline-generator.ts)

const PROFILE_SIZE: int = 256


static func make_roughness_profile(rng: FmgRng, contrast: float, num_harmonics: int = 4) -> PackedFloat32Array:
	var profile := PackedFloat32Array()
	profile.resize(PROFILE_SIZE)
	for k: int in range(1, num_harmonics + 1):
		var amp: float = rng.random()
		var phase: float = rng.random() * PI * 2.0
		for i: int in PROFILE_SIZE:
			profile[i] += amp * cos((2.0 * PI * float(k) * float(i)) / float(PROFILE_SIZE) + phase)
	var min_v: float = INF
	var max_v: float = -INF
	for v: float in profile:
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	var range_v: float = (max_v - min_v) if max_v - min_v != 0.0 else 1.0
	for i: int in PROFILE_SIZE:
		profile[i] = pow((profile[i] - min_v) / range_v, contrast)
	return profile


static func _sample_profile(profile: PackedFloat32Array, t: float) -> float:
	var pos: float = fmod(fmod(t, 1.0) + 1.0, 1.0) * float(PROFILE_SIZE)
	var i: int = int(pos) % PROFILE_SIZE
	var f: float = pos - float(int(pos))
	return profile[i] * (1.0 - f) + profile[(i + 1) % PROFILE_SIZE] * f


static func _mid_t(t0: float, t1: float) -> float:
	var diff: float = t1 - t0
	if absf(diff) <= 0.5:
		return t0 + diff / 2.0
	var t: float = t0 + (diff - signf(diff)) / 2.0
	return fmod(fmod(t, 1.0) + 1.0, 1.0)


static func _subdivide_edge(
	x0: float, y0: float, x1: float, y1: float, t0: float, t1: float, depth: int,
	amplitude: float, profile: PackedFloat32Array, rng: FmgRng, result: PackedVector2Array,
	max_depth: int, base_amplitude: float, min_edge: float, smooth_threshold: float, amplitude_decay: float
) -> void:
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var len_v: float = sqrt(dx * dx + dy * dy)
	if depth == 0 or len_v < min_edge:
		return
	var tm: float = _mid_t(t0, t1)
	var roughness: float = _sample_profile(profile, tm)
	if roughness < smooth_threshold:
		return
	var px: float = -dy / len_v
	var py: float = dx / len_v
	var disp: float = (rng.random() - 0.5) * sqrt(len_v) * amplitude * roughness
	var mx: float = (x0 + x1) / 2.0 + px * disp
	var my: float = (y0 + y1) / 2.0 + py * disp
	_subdivide_edge(x0, y0, mx, my, t0, tm, depth - 1, amplitude * amplitude_decay, profile, rng, result, max_depth, base_amplitude, min_edge, smooth_threshold, amplitude_decay)
	result.append(Vector2(mx, my))
	_subdivide_edge(mx, my, x1, y1, tm, t1, depth - 1, amplitude * amplitude_decay, profile, rng, result, max_depth, base_amplitude, min_edge, smooth_threshold, amplitude_decay)


## Displace a closed ring into a naturalistic fractal coastline.
## Returns flattened smooth points ready to draw.
static func fractalize_coastline(
	points: PackedVector2Array, rng: FmgRng, max_depth: int, base_amplitude: float,
	min_edge: float, smooth_threshold: float, roughness_contrast: float, profile_harmonics: int,
	amplitude_decay: float, map_width: float, map_height: float
) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3:
		return points
	var profile := make_roughness_profile(rng, roughness_contrast, profile_harmonics)
	var total: float = 0.0
	var seg_lens: PackedFloat32Array = PackedFloat32Array()
	seg_lens.resize(n)
	for i: int in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		seg_lens[i] = a.distance_to(b)
		total += seg_lens[i]
	if total < 1e-9:
		return points
	var t_params: PackedFloat32Array = PackedFloat32Array()
	t_params.resize(n)
	var cum: float = 0.0
	for i: int in n:
		t_params[i] = cum / total
		cum += seg_lens[i]
	var result := PackedVector2Array()
	for i: int in n:
		var cur: Vector2 = points[i]
		var nxt: Vector2 = points[(i + 1) % n]
		result.append(cur)
		if _is_on_border(cur, map_width, map_height) and _is_on_border(nxt, map_width, map_height):
			continue
		_subdivide_edge(cur.x, cur.y, nxt.x, nxt.y, t_params[i], t_params[(i + 1) % n], max_depth, base_amplitude, profile, rng, result, max_depth, base_amplitude, min_edge, smooth_threshold, amplitude_decay)
	# smooth the displaced ring: basis-like smoothing keeps it seam-free
	var smoothed := chaikin(result, true, 1)
	smoothed.append(smoothed[0])
	return smoothed


static func _is_on_border(p: Vector2, w: float, h: float) -> bool:
	return p.x == 0.0 or p.x == w or p.y == 0.0 or p.y == h


# ---------------------------------------------------------------------------
# River meandering (port of pathUtils.meander)

static func meander(
	cells: PackedInt32Array, cell_positions: PackedVector2Array, meandering: float,
	start_step: int, bounds: Vector2, is_water_cell: Array, anchors_custom: Array = []
) -> Dictionary:
	var anchor_points: Array = []
	for i: int in cells.size():
		var cell: int = cells[i]
		if i < anchors_custom.size() and anchors_custom[i] != null:
			anchor_points.append(anchors_custom[i])
			continue
		if cell == -1:
			var prev_cell: int = cells[i - 1] if i > 0 else -1
			var prev := cell_positions[prev_cell] if prev_cell >= 0 else Vector2.ZERO
			anchor_points.append(project_to_nearest_edge(prev, bounds.x, bounds.y))
		else:
			anchor_points.append(cell_positions[cell])

	var points := PackedVector2Array()
	var anchor_indices := PackedInt32Array()
	var last_step: int = cells.size() - 1
	var step: int = start_step
	var cell_count: int = cells.size()
	const WATER_MEANDER_SCALE: float = 0.25

	for i: int in cells.size():
		if i > last_step:
			break
		if i >= anchor_points.size():
			continue
		var a: Vector2 = anchor_points[i]
		anchor_indices.append(points.size())
		points.append(a)
		if i == last_step:
			break
		var next_cell: int = cells[i + 1]
		if next_cell == -1:
			step += 1
			continue
		if i + 1 >= anchor_points.size():
			step += 1
			continue
		var b: Vector2 = anchor_points[i + 1]
		var x1: float = a.x
		var y1: float = a.y
		var x2: float = b.x
		var y2: float = b.y
		var dist2: float = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
		if dist2 <= 25.0 and cell_count >= 6:
			step += 1
			continue
		var meander_val: float = meandering + 1.0 / float(step) + maxf(meandering - float(step) / 100.0, 0.0)
		if is_water_cell.size() > i and (is_water_cell[i] or is_water_cell[i + 1]):
			meander_val *= WATER_MEANDER_SCALE
		var angle: float = atan2(y2 - y1, x2 - x1)
		var sin_m: float = sin(angle) * meander_val
		var cos_m: float = cos(angle) * meander_val
		if step < 20 and (dist2 > 64.0 or (dist2 > 36.0 and cell_count < 5)):
			points.append(Vector2((x1 * 2.0 + x2) / 3.0 - sin_m, (y1 * 2.0 + y2) / 3.0 + cos_m))
			points.append(Vector2((x1 + x2 * 2.0) / 3.0 + sin_m / 2.0, (y1 + y2 * 2.0) / 3.0 - cos_m / 2.0))
		elif dist2 > 25.0 or cell_count < 6:
			points.append(Vector2((x1 + x2) / 2.0 - sin_m, (y1 + y2) / 2.0 + cos_m))
		step += 1

	_relax_acute_angles(points, anchor_indices)
	return {"points": points, "anchorIndices": anchor_indices}


static func _corner_cos(a: Vector2, b: Vector2, c: Vector2) -> float:
	var av := a - b
	var cv := c - b
	var la: float = av.length()
	var lc: float = cv.length()
	if la == 0.0 or lc == 0.0:
		return -1.0
	return av.dot(cv) / (la * lc)


static func _reflect_across_line(m: Vector2, p: Vector2, q: Vector2) -> Vector2:
	var d := q - p
	var len2: float = d.length_squared()
	if len2 == 0.0:
		return m
	var t: float = (m - p).dot(d) / len2
	var foot: Vector2 = p + d * t
	return foot * 2.0 - m


static func _relax_acute_angles(points: PackedVector2Array, anchor_indices: PackedInt32Array) -> void:
	var n: int = points.size()
	if n < 3:
		return
	var is_anchor := PackedByteArray()
	is_anchor.resize(n)
	for idx: int in anchor_indices:
		if idx < n:
			is_anchor[idx] = 1
	var prev_anchor: PackedInt32Array = PackedInt32Array()
	prev_anchor.resize(n)
	prev_anchor.fill(-1)
	var next_anchor: PackedInt32Array = PackedInt32Array()
	next_anchor.resize(n)
	next_anchor.fill(-1)
	var last_a: int = -1
	for i: int in n:
		prev_anchor[i] = last_a
		if is_anchor[i]:
			last_a = i
	last_a = -1
	for i: int in range(n - 1, -1, -1):
		next_anchor[i] = last_a
		if is_anchor[i]:
			last_a = i

	const RELAX_ITERATIONS: int = 4
	for _iter: int in RELAX_ITERATIONS:
		var snapshot := PackedVector2Array(points)
		var flipped_any: bool = false
		for i: int in range(1, n - 1):
			if is_anchor[i]:
				continue
			var p: int = prev_anchor[i]
			var q: int = next_anchor[i]
			if p < 0 or q < 0:
				continue
			var flipped := _reflect_across_line(snapshot[i], snapshot[p], snapshot[q])
			var before: float = _acute_cost(snapshot, i - 1) + _acute_cost(snapshot, i) + _acute_cost(snapshot, i + 1)
			var with_flip := PackedVector2Array(snapshot)
			with_flip[i] = flipped
			var after: float = _acute_cost(with_flip, i - 1) + _acute_cost(with_flip, i) + _acute_cost(with_flip, i + 1)
			if after < before - 1e-6:
				points[i] = flipped
				flipped_any = true
		if not flipped_any:
			break


static func _acute_cost(pos: PackedVector2Array, i: int) -> float:
	if i <= 0 or i >= pos.size() - 1:
		return 0.0
	var c: float = _corner_cos(pos[i - 1], pos[i], pos[i + 1])
	return c if c > 0.0 else 0.0
