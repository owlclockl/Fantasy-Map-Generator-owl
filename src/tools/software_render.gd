class_name FmgSoftwareRender
extends RefCounted
## CPU rasterizer that mirrors MapView._draw for the major layers. Used by the
## headless smoke test and `--preview` to produce a PNG without a GPU: the
## same meshes, colors and draw order as the on-screen renderer (labels and
## relief glyphs aside — they need font/glyph rasterization).

const OPAQUE: float = 1.0


static func render_map(view: MapView, width: int, height: int) -> Image:
	var raster := Raster.new(width, height)
	var sim: FmgSim = view.sim
	if sim == null or sim.pack == null:
		return raster.image

	# --- ocean ---
	raster.fill_rect(0, 0, width, height, view.style_ocean)

	# --- landmasses and lakes (tinted white-baked geometry) ---
	for ring: Dictionary in view._land_rings:
		raster.fill_polygon(ring["points"], view.style_land)
	for ring: Dictionary in view._lake_rings:
		raster.fill_polygon(ring["points"], view.style_lake)

	# --- cell overlays (same order and alphas as _draw) ---
	if view.show_heights:
		raster.fill_cells(view, view._cell_height_color, 1.0, true)
	else:
		if view.show_biomes:
			raster.fill_cells(view, view._cell_biome_color, 1.0)
		if view.show_relief:
			raster.fill_cells(view, func(i: int) -> Color:
				var h: float = float(sim.pack.h[i])
				if h < 45.0:
					return Color(0, 0, 0, 0)
				var strength: float = clampf((h - 45.0) / 55.0, 0.0, 1.0) * 0.45
				return Color(0.25, 0.2, 0.12, strength), 1.0)
		if view.show_politics:
			raster.fill_cells(view, view._cell_state_color, 0.55)
		if view.show_provinces:
			raster.fill_cells(view, view._cell_province_color, 0.25)

	if view.show_temperature:
		raster.fill_cells(view, view._cell_temperature_color, 1.0, true)
	if view.show_precipitation:
		raster.fill_precipitation(view)
	if view.show_population:
		raster.fill_population(view)
	if view.show_markets:
		raster.fill_cells(view, view._cell_market_color, 0.28)

	# --- ice ---
	if view.show_ice:
		for ice_value: Variant in sim.pack.ice:
			var points: PackedVector2Array = (ice_value as Dictionary).get("points", PackedVector2Array())
			raster.fill_polygon(points, view.style_ice)

	# --- zones ---
	if view.show_zones:
		for zone_value: Variant in sim.pack.zones:
			var zone: Dictionary = zone_value
			var color: Color = Color.html(str(zone.get("color", "#888888")))
			color.a = 0.16
			for cell_value: Variant in zone.get("cells", []):
				var cid: int = int(cell_value)
				if cid >= 0 and cid < view._cell_polygons.size():
					raster.fill_polygon(view._cell_polygons[cid], color)

	# --- coastlines ---
	for ring: Dictionary in view._land_rings:
		raster.stroke_polyline(ring["points"], view.style_coast, maxi(int(view.style_coast_width), 1))
	if view.show_lakes:
		for ring: Dictionary in view._lake_rings:
			raster.stroke_polyline(ring["points"], view.style_coast, 1)

	# --- rivers ---
	if view.show_rivers:
		for entry: Dictionary in view._river_polys:
			raster.fill_polygon(entry["points"], view.style_river)
		for stroke: Dictionary in view._river_strokes:
			raster.draw_tapered_stroke(stroke["points"], stroke["widths"], view.style_river)

	# --- routes ---
	if view.show_routes:
		for route_value: Variant in sim.pack.routes:
			var route: Dictionary = route_value
			var points: PackedVector2Array = route.get("points", PackedVector2Array())
			if points.size() < 2:
				continue
			match route.get("group", ""):
				"searoutes":
					raster.stroke_dashed(points, view.style_searoute, 1, 6.0, 3.0)
				"roads":
					raster.stroke_polyline(points, view.style_road, maxi(int(view.style_road_width), 1))
				_:
					raster.stroke_dashed(points, view.style_trail, 1, 3.0, 2.0)

	# --- trade arcs ---
	if view.show_trade:
		for i: int in view._trade_segments.size() / 2:
			raster.draw_line(view._trade_segments[i * 2], view._trade_segments[i * 2 + 1], Color("#8a6d3b"), 1)

	# --- borders ---
	if view.show_borders and not view._border_segments.is_empty():
		for i: int in view._border_segments.size() / 2:
			raster.draw_line(view._border_segments[i * 2], view._border_segments[i * 2 + 1], view.style_border, maxi(int(ceilf(view.style_border_width)), 1))

	# --- burgs ---
	if view.show_burgs:
		for b in sim.pack.burgs:
			if b == null:
				continue
			var pos := Vector2(float(b["x"]), float(b["y"]))
			if int(b.get("capital", 0)) == 1:
				raster.fill_circle(pos, 2.6, Color("#7a1f1f"))
				raster.stroke_circle(pos, 3.4, Color("#3d1010"), 1)
			else:
				raster.fill_circle(pos, 1.7, Color("#3d2b1f"))

	# --- markers ---
	if view.show_markers:
		for marker_value: Variant in sim.pack.markers:
			var marker: Dictionary = marker_value
			var pos := Vector2(float(marker.get("x", 0.0)), float(marker.get("y", 0.0)))
			raster.fill_polygon(PackedVector2Array([
				pos + Vector2(0, -2.4), pos + Vector2(2.4, 0),
				pos + Vector2(0, 2.4), pos + Vector2(-2.4, 0)
			]), Color("#8b4513"))

	# --- ruler ---
	if view.show_rulers and view.ruler_points.size() >= 2:
		var total: float = 0.0
		for i: int in view.ruler_points.size() - 1:
			raster.draw_line(view.ruler_points[i], view.ruler_points[i + 1], Color(0.75, 0.1, 0.1, 0.9), 1)
			total += view.ruler_points[i].distance_to(view.ruler_points[i + 1])

	# --- compass rose (top-right) ---
	if view.show_compass:
		_draw_compass(raster, Vector2(sim.map_width - 76.0, 82.0), 56.0)

	# --- scale bar (bottom-left) ---
	if view.show_scale_bar:
		_draw_scale_bar(raster, view, width, height)

	# --- vignette ---
	if view.show_vignette:
		for y: int in height:
			for x: int in width:
				var dx: float = (float(x) / float(width) - 0.5) * 2.0
				var dy: float = (float(y) / float(height) - 0.5) * 2.0
				var d: float = sqrt(dx * dx + dy * dy) / 1.42
				var alpha: float = clampf((d - 0.55) / 0.45, 0.0, 1.0)
				alpha = alpha * alpha * 0.42
				if alpha > 0.003:
					raster.blend_pixel(x, y, Color(0.05, 0.08, 0.14, alpha))
	return raster.image


static func _draw_compass(raster: Raster, center: Vector2, radius: float) -> void:
	var dark := Color("#27374d")
	var light := Color("#f4f1e6")
	raster.stroke_circle(center, radius, Color("#3a4a5f"), 1)
	for k: int in 16:
		var major: bool = k % 2 == 0
		var angle: float = -PI / 2.0 + TAU * float(k) / 16.0
		var length: float = radius * (0.92 if major else 0.5)
		var half_width: float = TAU / 16.0 * 0.55
		var tip := center + Vector2(cos(angle), sin(angle)) * length
		var left := center + Vector2(cos(angle - half_width), sin(angle - half_width)) * radius * 0.1
		var right := center + Vector2(cos(angle + half_width), sin(angle + half_width)) * radius * 0.1
		var tone := dark if k % 4 == 0 else light
		raster.fill_polygon(PackedVector2Array([center, tip, left]), tone)
		raster.fill_polygon(PackedVector2Array([center, tip, right]), Color(tone, 0.65))
	raster.fill_circle(center, radius * 0.07, dark)
	raster.fill_circle(center, radius * 0.035, light)


static func _draw_scale_bar(raster: Raster, view: MapView, width: int, height: int) -> void:
	var km_per_px: float = maxf(view.distance_scale, 0.01)
	var raw_km: float = 140.0 * km_per_px
	var magnitude: float = pow(10.0, floorf(log(raw_km) / log(10.0)))
	var nice: float = magnitude
	for candidate: float in [1.0, 2.0, 5.0, 10.0]:
		if raw_km <= candidate * magnitude * 1.0001:
			nice = candidate * magnitude
			break
	var bar_px: int = int(round(nice / km_per_px))
	var pos := Vector2i(24, height - 40)
	var bar_height: int = 6
	for k: int in 4:
		var color := Color(0.08, 0.1, 0.12) if k % 2 == 0 else Color(0.96, 0.94, 0.88)
		raster.fill_rect(pos.x + bar_px * k / 4, pos.y, maxi(bar_px / 4, 1), bar_height, color)
	raster.stroke_rect(Rect2i(pos.x, pos.y, bar_px, bar_height), Color(0.08, 0.1, 0.12), 1)


# ---------------------------------------------------------------------------
# Tiny rasterizer

class Raster:
	var width: int
	var height: int
	var image: Image

	func _init(w: int, h: int) -> void:
		width = w
		height = h
		image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)

	func fill_rect(x: int, y: int, w: int, h: int, color: Color) -> void:
		var x0: int = maxi(x, 0)
		var y0: int = maxi(y, 0)
		var x1: int = mini(x + w, width)
		var y1: int = mini(y + h, height)
		for py: int in range(y0, y1):
			for px: int in range(x0, x1):
				image.set_pixel(px, py, color)

	func blend_pixel(x: int, y: int, color: Color) -> void:
		if x < 0 or y < 0 or x >= width or y >= height or color.a <= 0.001:
			return
		if color.a >= 0.999:
			image.set_pixel(x, y, color)
			return
		var base: Color = image.get_pixel(x, y)
		image.set_pixel(x, y, base.blend(color))

	## Fills a polygon by fan-walking convex runs; concave cells fall back to
	## Geometry2D triangulation, matching the GPU mesh fill.
	func fill_polygon(points: PackedVector2Array, color: Color) -> void:
		if points.size() < 3:
			return
		var clean := PackedVector2Array(points)
		if clean[0].distance_squared_to(clean[clean.size() - 1]) < 0.0001:
			clean.remove_at(clean.size() - 1)
		if clean.size() < 3:
			return
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(clean)
		# No delaunay fallback: it fills the convex hull, which is catastrophically
		# wrong for self-intersecting polygons (rivers). Callers render those as
		# tapered strokes instead.
		for t: int in indices.size() / 3:
			fill_triangle(clean[indices[t * 3]], clean[indices[t * 3 + 1]], clean[indices[t * 3 + 2]], color)

	## Polyline with per-point width: quad per segment + round joints.
	func draw_tapered_stroke(points: PackedVector2Array, widths: PackedFloat32Array, color: Color) -> void:
		var n: int = points.size()
		if n == 0:
			return
		if n == 1:
			fill_circle(points[0], maxf(widths[0] * 0.5, 0.5), color)
			return
		fill_circle(points[0], maxf(widths[0] * 0.5, 0.5), color)
		for i: int in n - 1:
			var p0: Vector2 = points[i]
			var p1: Vector2 = points[i + 1]
			var dir: Vector2 = p1 - p0
			if dir.length_squared() < 0.0001:
				continue
			dir = dir.normalized()
			var normal := Vector2(-dir.y, dir.x)
			var w0: float = maxf(widths[i] * 0.5, 0.5)
			var w1: float = maxf(widths[i + 1] * 0.5, 0.5)
			fill_polygon(PackedVector2Array([
				p0 + normal * w0,
				p1 + normal * w1,
				p1 - normal * w1,
				p0 - normal * w0
			]), color)
			fill_circle(p1, w1, color)

	func fill_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
		var min_x: int = maxi(int(floorf(minf(a.x, minf(b.x, c.x)))), 0)
		var max_x: int = mini(int(ceilf(maxf(a.x, maxf(b.x, c.x)))), width - 1)
		var min_y: int = maxi(int(floorf(minf(a.y, minf(b.y, c.y)))), 0)
		var max_y: int = mini(int(ceilf(maxf(a.y, maxf(b.y, c.y)))), height - 1)
		if min_x > max_x or min_y > max_y:
			return
		var area: float = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
		if absf(area) < 0.00001:
			return
		for py: int in range(min_y, max_y + 1):
			for px: int in range(min_x, max_x + 1):
				var p := Vector2(float(px) + 0.5, float(py) + 0.5)
				var w0: float = (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
				var w1: float = (c.x - b.x) * (p.y - b.y) - (p.x - b.x) * (c.y - b.y)
				var w2: float = (a.x - c.x) * (p.y - c.y) - (p.x - c.x) * (a.y - c.y)
				if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
					blend_pixel(px, py, color)

	func stroke_polyline(points: PackedVector2Array, color: Color, thickness: int) -> void:
		var half: float = float(thickness) * 0.5 - 0.25
		for i: int in points.size() - 1:
			var a: Vector2 = points[i] + Vector2(half, half)
			var b: Vector2 = points[i + 1] + Vector2(half, half)
			draw_line(a, b, color, thickness)

	func stroke_dashed(points: PackedVector2Array, color: Color, thickness: int, dash: float, gap: float) -> void:
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
				var remaining: float = (dash - pos_in_cycle) if drawing else (cycle - pos_in_cycle)
				var step: float = minf(remaining, seg_len - t)
				if drawing:
					draw_line(a.lerp(b, t / seg_len), a.lerp(b, (t + step) / seg_len), color, thickness)
				t += step
				acc += step

	func draw_line(a: Vector2, b: Vector2, color: Color, thickness: int) -> void:
		var steps: int = maxi(int(ceilf(a.distance_to(b))), 1)
		if thickness <= 1:
			for i: int in steps + 1:
				var p: Vector2 = a.lerp(b, float(i) / float(steps))
				blend_pixel(int(p.x), int(p.y), color)
		else:
			var r: float = float(thickness) * 0.5
			for i: int in steps + 1:
				var p: Vector2 = a.lerp(b, float(i) / float(steps))
				for oy: int in thickness:
					for ox: int in thickness:
						blend_pixel(int(p.x - r + float(ox) + 0.5), int(p.y - r + float(oy) + 0.5), color)

	func fill_circle(center: Vector2, radius: float, color: Color) -> void:
		var r2: float = radius * radius
		var min_x: int = maxi(int(floorf(center.x - radius)), 0)
		var max_x: int = mini(int(ceilf(center.x + radius)), width - 1)
		var min_y: int = maxi(int(floorf(center.y - radius)), 0)
		var max_y: int = mini(int(ceilf(center.y + radius)), height - 1)
		for py: int in range(min_y, max_y + 1):
			for px: int in range(min_x, max_x + 1):
				var d2: float = (float(px) + 0.5 - center.x) * (float(px) + 0.5 - center.x) + (float(py) + 0.5 - center.y) * (float(py) + 0.5 - center.y)
				if d2 <= r2:
					image.set_pixel(px, py, color)

	func stroke_circle(center: Vector2, radius: float, color: Color, thickness: int) -> void:
		var steps: int = maxi(int(radius * 6.0), 12)
		var prev: Vector2 = center + Vector2(radius, 0)
		for i: int in range(1, steps + 1):
			var angle: float = TAU * float(i) / float(steps)
			var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			draw_line(prev, point, color, thickness)
			prev = point

	func stroke_rect(rect: Rect2i, color: Color, thickness: int) -> void:
		var a := Vector2(float(rect.position.x), float(rect.position.y))
		var b := Vector2(float(rect.position.x + rect.size.x), float(rect.position.y))
		var c := Vector2(float(rect.position.x + rect.size.x), float(rect.position.y + rect.size.y))
		var d := Vector2(float(rect.position.x), float(rect.position.y + rect.size.y))
		draw_line(a, b, color, thickness)
		draw_line(b, c, color, thickness)
		draw_line(c, d, color, thickness)
		draw_line(d, a, color, thickness)

	## Fills packed land/water cells with a color from the view's own color
	## functions (identical logic to the GPU overlay meshes).
	func fill_cells(view: MapView, color_fn: Callable, alpha: float, include_water: bool = false) -> void:
		var pack: FmgGraph = view.sim.pack
		for i: int in pack.cell_count():
			if not include_water and pack.h[i] < 20:
				continue
			var color: Color = color_fn.call(i)
			if color.a <= 0.0:
				continue
			color.a *= alpha
			fill_polygon(view._cell_polygons[i], color)

	func fill_precipitation(view: MapView) -> void:
		var sim: FmgSim = view.sim
		var pack: FmgGraph = sim.pack
		var cells_modifier: float = pow(float(maxi(sim.cells_desired, 1)) / 10000.0, 0.25)
		var grid_prec := sim.grid.prec if sim.grid != null else PackedInt32Array()
		var color := Color(0.29, 0.45, 0.71, 0.5)
		for i: int in pack.cell_count():
			if pack.h[i] < 20 or grid_prec.is_empty():
				continue
			var parent: int = pack.g[i]
			if parent < 0 or parent >= grid_prec.size():
				continue
			var prec: int = grid_prec[parent]
			if prec <= 0:
				continue
			var radius: float = minf(sqrt(float(prec) / 4.0) / maxf(cells_modifier, 0.35), 14.0)
			if radius >= 0.35:
				fill_circle(pack.points[i], radius, color)

	func fill_population(view: MapView) -> void:
		var pack: FmgGraph = view.sim.pack
		var rural := Color(0.55, 0.62, 0.53, 0.85)
		var urban := Color(0.48, 0.12, 0.12, 0.9)
		for i: int in pack.cell_count():
			if pack.h[i] < 20 or pack.pop[i] <= 0.0:
				continue
			var height: float = minf(pack.pop[i] / 5.0, 40.0)
			if height < 0.8:
				continue
			fill_rect(int(pack.points[i].x - 0.32), int(pack.points[i].y - height), 1, int(height), rural)
		for burg_value: Variant in pack.burgs:
			if burg_value == null:
				continue
			var burg: Dictionary = burg_value
			var height: float = minf(float(burg.get("population", 0.0)) / 5.0, 60.0)
			if height < 0.8:
				continue
			var p: Vector2 = Vector2(float(burg.get("x", 0.0)), float(burg.get("y", 0.0)))
			fill_rect(int(p.x - 0.7), int(p.y - height), 2, int(height), urban)
