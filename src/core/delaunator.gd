class_name Delaunator
extends RefCounted
## GDScript port of Delaunator (https://github.com/mapbox/delaunator, ISC license).
## Incremental sweep-hull Delaunay triangulation, O(n log n).
## Outputs: `triangles` (PackedInt32Array, 3 indices per triangle into `coords`)
## and `halfedges` (PackedInt32Array, -1 = open hull edge).

const EPSILON: float = 2.0 ** -52.0
const EDGE_STACK_SIZE: int = 512

var coords: PackedFloat64Array
var _triangles: PackedInt32Array
var _halfedges: PackedInt32Array
var triangles: PackedInt32Array
var halfedges: PackedInt32Array
var hull: PackedInt32Array

var _hash_size: int = 0
var _hull_prev: PackedInt32Array
var _hull_next: PackedInt32Array
var _hull_tri: PackedInt32Array
var _hull_hash: PackedInt32Array
var _hull_start: int = 0
var _ids: PackedInt32Array
var _dists: PackedFloat64Array
var _cx: float = 0.0
var _cy: float = 0.0
var triangles_len: int = 0
var _edge_stack: PackedInt32Array = PackedInt32Array()


static func from_points(points: PackedVector2Array) -> Delaunator:
	var n: int = points.size()
	var c := PackedFloat64Array()
	c.resize(n * 2)
	for i: int in n:
		c[i * 2] = points[i].x
		c[i * 2 + 1] = points[i].y
	return Delaunator.new(c)


func _init(coord_array: PackedFloat64Array) -> void:
	coords = coord_array
	var n: int = coords.size() >> 1
	var max_triangles: int = maxi(2 * n - 5, 0)
	_triangles = PackedInt32Array()
	_triangles.resize(maxi(max_triangles * 3, 3))
	_halfedges = PackedInt32Array()
	_halfedges.resize(maxi(max_triangles * 3, 3))
	_halfedges.fill(-1)
	_hash_size = int(ceil(sqrt(float(n))))
	_hull_prev = PackedInt32Array()
	_hull_prev.resize(n)
	_hull_next = PackedInt32Array()
	_hull_next.resize(n)
	_hull_tri = PackedInt32Array()
	_hull_tri.resize(n)
	_hull_hash = PackedInt32Array()
	_hull_hash.resize(_hash_size)
	_ids = PackedInt32Array()
	_ids.resize(n)
	_dists = PackedFloat64Array()
	_dists.resize(n)
	_edge_stack = PackedInt32Array()
	_edge_stack.resize(EDGE_STACK_SIZE)
	update()


func _hash_key(x: float, y: float) -> int:
	return int(floor(_pseudo_angle(x - _cx, y - _cy) * float(_hash_size))) % _hash_size


## monotonically increases with real angle, but doesn't need expensive trigonometry
static func _pseudo_angle(dx: float, dy: float) -> float:
	var p: float = dx / (absf(dx) + absf(dy))
	return ((3.0 - p if dy > 0.0 else 1.0 + p)) / 4.0


static func _dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx: float = ax - bx
	var dy: float = ay - by
	return dx * dx + dy * dy


static func _in_circle(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, px: float, py: float) -> bool:
	var dx: float = ax - px
	var dy: float = ay - py
	var ex: float = bx - px
	var ey: float = by - py
	var fx: float = cx - px
	var fy: float = cy - py
	var ap: float = dx * dx + dy * dy
	var bp: float = ex * ex + ey * ey
	var cp: float = fx * fx + fy * fy
	return (
		dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) < 0.0
	)


static func _circumradius2(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var dx: float = bx - ax
	var dy: float = by - ay
	var ex: float = cx - ax
	var ey: float = cy - ay
	var bl: float = dx * dx + dy * dy
	var cl: float = ex * ex + ey * ey
	var d: float = 0.5 / (dx * ey - dy * ex)
	var x: float = (ey * bl - dy * cl) * d
	var y: float = (dx * cl - ex * bl) * d
	return x * x + y * y


static func circumcenter(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> Vector2:
	var dx: float = bx - ax
	var dy: float = by - ay
	var ex: float = cx - ax
	var ey: float = cy - ay
	var bl: float = dx * dx + dy * dy
	var cl: float = ex * ex + ey * ey
	var d: float = 0.5 / (dx * ey - dy * ex)
	var x: float = ax + (ey * bl - dy * cl) * d
	var y: float = ay + (dx * cl - ex * bl) * d
	return Vector2(x, y)


## orient2d in the Delaunator / robust-predicates sign convention (NEGATED vs the
## textbook CCW formula) — Delaunator's hull-walk comparisons assume exactly this.
## Filtered error bound with Shewchuk's exact-expansion fallback, required for
## inputs with exactly-collinear points (e.g. lattice boundary rings).
const PRED_EPSILON: float = 1.1102230246251565e-16
const PRED_SPLITTER: float = 134217729.0
const PRED_RESULTERRBOUND: float = (3.0 + 8.0 * PRED_EPSILON) * PRED_EPSILON
const PRED_CCWERRBOUND_A: float = (3.0 + 16.0 * PRED_EPSILON) * PRED_EPSILON
const PRED_CCWERRBOUND_B: float = (2.0 + 12.0 * PRED_EPSILON) * PRED_EPSILON
const PRED_CCWERRBOUND_C: float = (9.0 + 64.0 * PRED_EPSILON) * PRED_EPSILON * PRED_EPSILON

static var _pred_b := PackedFloat64Array()
static var _pred_c1 := PackedFloat64Array()
static var _pred_c2 := PackedFloat64Array()
static var _pred_d := PackedFloat64Array()
static var _pred_u := PackedFloat64Array()


static func _pred_scratch() -> void:
	if _pred_b.size() == 0:
		_pred_b.resize(4)
		_pred_c1.resize(8)
		_pred_c2.resize(12)
		_pred_d.resize(16)
		_pred_u.resize(4)


## fast_expansion_sum_zeroelim — exact sum of two expansions, zeroes eliminated
static func _pred_sum(elen: int, e: PackedFloat64Array, flen: int, f: PackedFloat64Array, h: PackedFloat64Array) -> int:
	var Q: float
	var Qnew: float
	var hh: float
	var bvirt: float
	var enow: float = e[0]
	var fnow: float = f[0]
	var eindex: int = 0
	var findex: int = 0
	if (fnow > enow) == (fnow > -enow):
		Q = enow
		eindex += 1
		enow = e[eindex]
	else:
		Q = fnow
		findex += 1
		fnow = f[findex]
	var hindex: int = 0
	if eindex < elen and findex < flen:
		if (fnow > enow) == (fnow > -enow):
			Qnew = enow + Q
			hh = Q - (Qnew - enow)
			eindex += 1
			enow = e[eindex]
		else:
			Qnew = fnow + Q
			hh = Q - (Qnew - fnow)
			findex += 1
			fnow = f[findex]
		Q = Qnew
		if hh != 0.0:
			h[hindex] = hh
			hindex += 1
		while eindex < elen and findex < flen:
			if (fnow > enow) == (fnow > -enow):
				Qnew = Q + enow
				bvirt = Qnew - Q
				hh = Q - (Qnew - bvirt) + (enow - bvirt)
				eindex += 1
				enow = e[eindex]
			else:
				Qnew = Q + fnow
				bvirt = Qnew - Q
				hh = Q - (Qnew - bvirt) + (fnow - bvirt)
				findex += 1
				fnow = f[findex]
			Q = Qnew
			if hh != 0.0:
				h[hindex] = hh
				hindex += 1
	while eindex < elen:
		Qnew = Q + enow
		bvirt = Qnew - Q
		hh = Q - (Qnew - bvirt) + (enow - bvirt)
		eindex += 1
		enow = e[eindex]
		Q = Qnew
		if hh != 0.0:
			h[hindex] = hh
			hindex += 1
	while findex < flen:
		Qnew = Q + fnow
		bvirt = Qnew - Q
		hh = Q - (Qnew - bvirt) + (fnow - bvirt)
		findex += 1
		fnow = f[findex]
		Q = Qnew
		if hh != 0.0:
			h[hindex] = hh
			hindex += 1
	return hindex


static func _pred_estimate(elen: int, e: PackedFloat64Array) -> float:
	var Q: float = e[0]
	for eindex: int in range(1, elen):
		Q += e[eindex]
	return Q


## exact 2x2 determinant via expansion arithmetic (port of Shewchuk orient2dadapt)
static func _orient2d_adapt(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, detsum: float) -> float:
	_pred_scratch()
	var B := _pred_b
	var u := _pred_u
	var C1 := _pred_c1
	var C2 := _pred_c2
	var D := _pred_d
	var bvirt: float
	var c: float
	var ahi: float
	var alo: float
	var bhi: float
	var blo: float
	var _i: float
	var _j: float
	var _0: float
	var s1: float
	var s0: float
	var t1: float
	var t0: float
	var u3: float

	var acx: float = ax - cx
	var bcx: float = bx - cx
	var acy: float = ay - cy
	var bcy: float = by - cy

	# (acx * bcy - acy * bcx) as an exact expansion in B[0..3]
	s1 = acx * bcy
	c = PRED_SPLITTER * acx
	ahi = c - (c - acx)
	alo = acx - ahi
	c = PRED_SPLITTER * bcy
	bhi = c - (c - bcy)
	blo = bcy - bhi
	s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
	t1 = acy * bcx
	c = PRED_SPLITTER * acy
	ahi = c - (c - acy)
	alo = acy - ahi
	c = PRED_SPLITTER * bcx
	bhi = c - (c - bcx)
	blo = bcx - bhi
	t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
	_i = s0 - t0
	bvirt = s0 - _i
	B[0] = s0 - (_i + bvirt) + (bvirt - t0)
	_j = s1 + _i
	bvirt = _j - s1
	_0 = s1 - (_j - bvirt) + (_i - bvirt)
	_i = _0 - t1
	bvirt = _0 - _i
	B[1] = _0 - (_i + bvirt) + (bvirt - t1)
	u3 = _j + _i
	bvirt = u3 - _j
	B[2] = _j - (u3 - bvirt) + (_i - bvirt)
	B[3] = u3

	var det: float = _pred_estimate(4, B)
	var errbound: float = PRED_CCWERRBOUND_B * detsum
	if det >= errbound or -det >= errbound:
		return det

	bvirt = ax - acx
	var acxtail: float = ax - (acx + bvirt) + (bvirt - cx)
	bvirt = bx - bcx
	var bcxtail: float = bx - (bcx + bvirt) + (bvirt - cx)
	bvirt = ay - acy
	var acytail: float = ay - (acy + bvirt) + (bvirt - cy)
	bvirt = by - bcy
	var bcytail: float = by - (bcy + bvirt) + (bvirt - cy)

	if acxtail == 0.0 and acytail == 0.0 and bcxtail == 0.0 and bcytail == 0.0:
		return det

	errbound = PRED_CCWERRBOUND_C * detsum + PRED_RESULTERRBOUND * absf(det)
	det += (acx * bcytail + bcy * acxtail) - (acy * bcxtail + bcx * acytail)
	if det >= errbound or -det >= errbound:
		return det

	# tail * other
	s1 = acxtail * bcy
	c = PRED_SPLITTER * acxtail
	ahi = c - (c - acxtail)
	alo = acxtail - ahi
	c = PRED_SPLITTER * bcy
	bhi = c - (c - bcy)
	blo = bcy - bhi
	s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
	t1 = acytail * bcx
	c = PRED_SPLITTER * acytail
	ahi = c - (c - acytail)
	alo = acytail - ahi
	c = PRED_SPLITTER * bcx
	bhi = c - (c - bcx)
	blo = bcx - bhi
	t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
	_i = s0 - t0
	bvirt = s0 - _i
	u[0] = s0 - (_i + bvirt) + (bvirt - t0)
	_j = s1 + _i
	bvirt = _j - s1
	_0 = s1 - (_j - bvirt) + (_i - bvirt)
	_i = _0 - t1
	bvirt = _0 - _i
	u[1] = _0 - (_i + bvirt) + (bvirt - t1)
	u3 = _j + _i
	bvirt = u3 - _j
	u[2] = _j - (u3 - bvirt) + (_i - bvirt)
	u[3] = u3
	var c1len: int = _pred_sum(4, B, 4, u, C1)

	# main * tail
	s1 = acx * bcytail
	c = PRED_SPLITTER * acx
	ahi = c - (c - acx)
	alo = acx - ahi
	c = PRED_SPLITTER * bcytail
	bhi = c - (c - bcytail)
	blo = bcytail - bhi
	s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
	t1 = acy * bcxtail
	c = PRED_SPLITTER * acy
	ahi = c - (c - acy)
	alo = acy - ahi
	c = PRED_SPLITTER * bcxtail
	bhi = c - (c - bcxtail)
	blo = bcxtail - bhi
	t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
	_i = s0 - t0
	bvirt = s0 - _i
	u[0] = s0 - (_i + bvirt) + (bvirt - t0)
	_j = s1 + _i
	bvirt = _j - s1
	_0 = s1 - (_j - bvirt) + (_i - bvirt)
	_i = _0 - t1
	bvirt = _0 - _i
	u[1] = _0 - (_i + bvirt) + (bvirt - t1)
	u3 = _j + _i
	bvirt = u3 - _j
	u[2] = _j - (u3 - bvirt) + (_i - bvirt)
	u[3] = u3
	var c2len: int = _pred_sum(c1len, C1, 4, u, C2)

	# tail * tail
	s1 = acxtail * bcytail
	c = PRED_SPLITTER * acxtail
	ahi = c - (c - acxtail)
	alo = acxtail - ahi
	c = PRED_SPLITTER * bcytail
	bhi = c - (c - bcytail)
	blo = bcytail - bhi
	s0 = alo * blo - (s1 - ahi * bhi - alo * bhi - ahi * blo)
	t1 = acytail * bcxtail
	c = PRED_SPLITTER * acytail
	ahi = c - (c - acytail)
	alo = acytail - ahi
	c = PRED_SPLITTER * bcxtail
	bhi = c - (c - bcxtail)
	blo = bcxtail - bhi
	t0 = alo * blo - (t1 - ahi * bhi - alo * bhi - ahi * blo)
	_i = s0 - t0
	bvirt = s0 - _i
	u[0] = s0 - (_i + bvirt) + (bvirt - t0)
	_j = s1 + _i
	bvirt = _j - s1
	_0 = s1 - (_j - bvirt) + (_i - bvirt)
	_i = _0 - t1
	bvirt = _0 - _i
	u[1] = _0 - (_i + bvirt) + (bvirt - t1)
	u3 = _j + _i
	bvirt = u3 - _j
	u[2] = _j - (u3 - bvirt) + (_i - bvirt)
	u[3] = u3
	var dlen: int = _pred_sum(c2len, C2, 4, u, D)

	return D[dlen - 1]


## sign of the oriented area of triangle (a, b, c) — Delaunator convention + exact fallback
static func orient2d(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var detleft: float = (ay - cy) * (bx - cx)
	var detright: float = (ax - cx) * (by - cy)
	var det: float = detleft - detright
	var detsum: float = absf(detleft + detright)
	if absf(det) >= PRED_CCWERRBOUND_A * detsum:
		return det
	return -_orient2d_adapt(ax, ay, bx, by, cx, cy, detsum)


static func _swap_ids(ids: PackedInt32Array, i: int, j: int) -> void:
	var tmp: int = ids[i]
	ids[i] = ids[j]
	ids[j] = tmp


static func _quicksort(ids: PackedInt32Array, dists: PackedFloat64Array, left: int, right: int) -> void:
	if right - left <= 20:
		for i: int in range(left + 1, right + 1):
			var temp: int = ids[i]
			var temp_dist: float = dists[temp]
			var j: int = i - 1
			while j >= left and dists[ids[j]] > temp_dist:
				ids[j + 1] = ids[j]
				j -= 1
			ids[j + 1] = temp
	else:
		var median: int = (left + right) >> 1
		var i: int = left + 1
		var j: int = right
		_swap_ids(ids, median, i)
		if dists[ids[left]] > dists[ids[right]]:
			_swap_ids(ids, left, right)
		if dists[ids[i]] > dists[ids[right]]:
			_swap_ids(ids, i, right)
		if dists[ids[left]] > dists[ids[i]]:
			_swap_ids(ids, left, i)

		var temp: int = ids[i]
		var temp_dist: float = dists[temp]
		while true:
			i += 1
			while dists[ids[i]] < temp_dist:
				i += 1
			j -= 1
			while dists[ids[j]] > temp_dist:
				j -= 1
			if j < i:
				break
			_swap_ids(ids, i, j)
		ids[left + 1] = ids[j]
		ids[j] = temp

		if right - i + 1 >= j - left:
			_quicksort(ids, dists, i, right)
			_quicksort(ids, dists, left, j - 1)
		else:
			_quicksort(ids, dists, left, j - 1)
			_quicksort(ids, dists, i, right)


func update() -> void:
	var n: int = coords.size() >> 1
	if n == 0:
		triangles = PackedInt32Array()
		halfedges = PackedInt32Array()
		hull = PackedInt32Array()
		return

	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for i: int in n:
		var x: float = coords[i * 2]
		var y: float = coords[i * 2 + 1]
		if x < min_x: min_x = x
		if y < min_y: min_y = y
		if x > max_x: max_x = x
		if y > max_y: max_y = y
		_ids[i] = i
	var cx: float = (min_x + max_x) / 2.0
	var cy: float = (min_y + max_y) / 2.0

	var i0: int = 0
	var i1: int = 0
	var i2: int = 0

	# pick a seed point close to the center
	var min_d: float = INF
	for i: int in n:
		var d: float = _dist2(cx, cy, coords[i * 2], coords[i * 2 + 1])
		if d < min_d:
			i0 = i
			min_d = d
	var i0x: float = coords[i0 * 2]
	var i0y: float = coords[i0 * 2 + 1]

	# find the point closest to the seed
	min_d = INF
	for i: int in n:
		if i == i0:
			continue
		var d: float = _dist2(i0x, i0y, coords[i * 2], coords[i * 2 + 1])
		if d < min_d and d > 0.0:
			i1 = i
			min_d = d
	var i1x: float = coords[i1 * 2]
	var i1y: float = coords[i1 * 2 + 1]

	var min_radius: float = INF
	# find the third point which forms the smallest circumcircle with the first two
	for i: int in n:
		if i == i0 or i == i1:
			continue
		var r: float = _circumradius2(i0x, i0y, i1x, i1y, coords[i * 2], coords[i * 2 + 1])
		if r < min_radius:
			i2 = i
			min_radius = r
	var i2x: float = coords[i2 * 2]
	var i2y: float = coords[i2 * 2 + 1]

	if min_radius == INF:
		# order collinear points by dx (or dy if all x are identical) and return the list as a hull
		for i: int in n:
			_dists[i] = (coords[i * 2] - coords[0]) if coords[i * 2] - coords[0] != 0.0 else (coords[i * 2 + 1] - coords[1])
		_quicksort(_ids, _dists, 0, n - 1)
		var colinear_hull := PackedInt32Array()
		colinear_hull.resize(n)
		var j: int = 0
		var d0: float = -INF
		for i: int in n:
			var id: int = _ids[i]
			var d: float = _dists[id]
			if d > d0:
				colinear_hull[j] = id
				j += 1
				d0 = d
		hull = colinear_hull.slice(0, j)
		triangles = PackedInt32Array()
		halfedges = PackedInt32Array()
		return

	# swap the order of the seed points for counter-clockwise orientation
	if orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0.0:
		var ti: int = i1
		var tx: float = i1x
		var ty: float = i1y
		i1 = i2
		i1x = i2x
		i1y = i2y
		i2 = ti
		i2x = tx
		i2y = ty

	var center := circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
	_cx = center.x
	_cy = center.y

	for i: int in n:
		_dists[i] = _dist2(coords[i * 2], coords[i * 2 + 1], _cx, _cy)

	_quicksort(_ids, _dists, 0, n - 1)

	# set up the seed triangle as the starting hull
	_hull_start = i0
	var hull_size: int = 3

	_hull_next[i0] = i1
	_hull_prev[i2] = i1
	_hull_next[i1] = i2
	_hull_prev[i0] = i2
	_hull_next[i2] = i0
	_hull_prev[i1] = i0

	_hull_tri[i0] = 0
	_hull_tri[i1] = 1
	_hull_tri[i2] = 2

	_hull_hash.fill(-1)
	_hull_hash[_hash_key(i0x, i0y)] = i0
	_hull_hash[_hash_key(i1x, i1y)] = i1
	_hull_hash[_hash_key(i2x, i2y)] = i2

	triangles_len = 0
	_add_triangle(i0, i1, i2, -1, -1, -1)

	var xp: float = 0.0
	var yp: float = 0.0
	for k: int in _ids.size():
		var i: int = _ids[k]
		var x: float = coords[i * 2]
		var y: float = coords[i * 2 + 1]

		# skip near-duplicate points
		if k > 0 and absf(x - xp) <= EPSILON and absf(y - yp) <= EPSILON:
			continue
		xp = x
		yp = y

		# skip seed triangle points
		if i == i0 or i == i1 or i == i2:
			continue

		# find a visible edge on the convex hull using edge hash
		var start: int = 0
		var key: int = _hash_key(x, y)
		for jj: int in _hash_size:
			start = _hull_hash[(key + jj) % _hash_size]
			if start != -1 and start != _hull_next[start]:
				break

		start = _hull_prev[start]
		var e: int = start
		var q: int = 0
		while true:
			q = _hull_next[e]
			if orient2d(x, y, coords[e * 2], coords[e * 2 + 1], coords[q * 2], coords[q * 2 + 1]) >= 0.0:
				e = q
				if e == start:
					e = -1
					break
			else:
				break
		if e == -1:
			continue # likely a near-duplicate point; skip it

		# add the first triangle from the point
		var t: int = _add_triangle(e, i, _hull_next[e], -1, -1, _hull_tri[e])

		# recursively flip triangles from the point until they satisfy the Delaunay condition
		_hull_tri[i] = _legalize(t + 2)
		_hull_tri[e] = t
		hull_size += 1

		# walk forward through the hull, adding more triangles and flipping recursively
		var nn: int = _hull_next[e]
		while true:
			q = _hull_next[nn]
			if orient2d(x, y, coords[nn * 2], coords[nn * 2 + 1], coords[q * 2], coords[q * 2 + 1]) < 0.0:
				t = _add_triangle(nn, i, q, _hull_tri[i], -1, _hull_tri[nn])
				_hull_tri[i] = _legalize(t + 2)
				_hull_next[nn] = nn # mark as removed
				hull_size -= 1
				nn = q
			else:
				break

		# walk backward from the other side, adding more triangles and flipping
		if e == start:
			while true:
				q = _hull_prev[e]
				if orient2d(x, y, coords[q * 2], coords[q * 2 + 1], coords[e * 2], coords[e * 2 + 1]) < 0.0:
					t = _add_triangle(q, i, e, -1, _hull_tri[e], _hull_tri[q])
					_legalize(t + 2)
					_hull_tri[q] = t
					_hull_next[e] = e # mark as removed
					hull_size -= 1
					e = q
				else:
					break

		# update the hull indices
		_hull_start = e
		_hull_prev[i] = e
		_hull_next[e] = i
		_hull_prev[nn] = i
		_hull_next[i] = nn

		# save the two new edges in the hash table
		_hull_hash[_hash_key(x, y)] = i
		_hull_hash[_hash_key(coords[e * 2], coords[e * 2 + 1])] = e

	hull = PackedInt32Array()
	hull.resize(hull_size)
	var he: int = _hull_start
	for hi: int in hull_size:
		hull[hi] = he
		he = _hull_next[he]

	triangles = _triangles.slice(0, triangles_len)
	halfedges = _halfedges.slice(0, triangles_len)


func _legalize(a: int) -> int:
	var edge_stack: PackedInt32Array = _edge_stack
	var i: int = 0
	var ar: int = 0

	while true:
		var b: int = _halfedges[a]

		var a0: int = a - (a % 3)
		ar = a0 + ((a + 2) % 3)

		if b == -1: # convex hull edge
			if i == 0:
				break
			i -= 1
			a = edge_stack[i]
			continue

		var b0: int = b - (b % 3)
		var al: int = a0 + ((a + 1) % 3)
		var bl: int = b0 + ((b + 2) % 3)

		var p0: int = _triangles[ar]
		var pr: int = _triangles[a]
		var pl: int = _triangles[al]
		var p1: int = _triangles[bl]

		var illegal: bool = _in_circle(
			coords[p0 * 2], coords[p0 * 2 + 1],
			coords[pr * 2], coords[pr * 2 + 1],
			coords[pl * 2], coords[pl * 2 + 1],
			coords[p1 * 2], coords[p1 * 2 + 1]
		)

		if illegal:
			_triangles[a] = p1
			_triangles[b] = p0

			var hbl: int = _halfedges[bl]

			# edge swapped on the other side of the hull (rare); fix the halfedge reference
			if hbl == -1:
				var e: int = _hull_start
				while true:
					if _hull_tri[e] == bl:
						_hull_tri[e] = a
						break
					e = _hull_prev[e]
					if e == _hull_start:
						break
			_link(a, hbl)
			_link(b, _halfedges[ar])
			_link(ar, bl)

			var br: int = b0 + ((b + 1) % 3)

			if i < EDGE_STACK_SIZE:
				edge_stack[i] = br
				i += 1
		else:
			if i == 0:
				break
			i -= 1
			a = edge_stack[i]

	return ar


func _link(a: int, b: int) -> void:
	_halfedges[a] = b
	if b != -1:
		_halfedges[b] = a


func _add_triangle(i0: int, i1: int, i2: int, a: int, b: int, c: int) -> int:
	var t: int = triangles_len
	_triangles[t] = i0
	_triangles[t + 1] = i1
	_triangles[t + 2] = i2
	_link(t, a)
	_link(t + 1, b)
	_link(t + 2, c)
	triangles_len += 3
	return t
