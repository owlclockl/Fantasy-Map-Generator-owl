extends Node2D
## Main orchestrator: builds the UI, runs the generation pipeline stage by
## stage (keeping the UI responsive), handles the heightmap brush,
## save/load and PNG export.

var sim: FmgSim = null # Sim autoload
var view: MapView = null
var camera: MapCamera = null

# UI references
var status_label: Label = null
var progress_bar: ProgressBar = null
var seed_edit: LineEdit = null
var template_option: OptionButton = null
var density_option: OptionButton = null
var cultures_spin: SpinBox = null
var cultures_set_option: OptionButton = null
var states_spin: SpinBox = null
var burgs_check: CheckButton = null
var climate_equator_spin: SpinBox = null
var climate_north_spin: SpinBox = null
var climate_south_spin: SpinBox = null
var climate_precip_spin: SpinBox = null
var wind_spins: Array = []
var generate_button: Button = null
var brush_option: OptionButton = null
var brush_size: HSlider = null
var layer_checks: Dictionary = {}

# brush state
var brush_active: bool = false
var brush_world_pos := Vector2.ZERO
var _brush_down: bool = false
var _space_held: bool = false
var _generating: bool = false

const DENSITIES := [[1, "1 000"], [2, "2 000"], [3, "5 000"], [4, "10 000"], [5, "20 000"]]
const POINTS_BY_DENSITY := {1: 1000, 2: 2000, 3: 5000, 4: 10000, 5: 20000}


func _ready() -> void:
	sim = get_node("/root/Sim") as FmgSim
	view = MapView.new()
	view.sim = sim
	view.name = "MapView"
	add_child(view)

	camera = MapCamera.new()
	camera.name = "Camera"
	add_child(camera)

	_build_ui()

	if DisplayServer.get_name() == "headless":
		_run_headless_smoke()
	else:
		_on_generate_pressed.call_deferred()


func _run_headless_smoke() -> void:
	print("[smoke] headless generation test started")
	await run_generation(true)
	print("[smoke] stats: ", sim.get_stats_text())
	print("[smoke] states: ", _collect_state_names())
	print("[smoke] manufactured records: ", _count_manufacturing())
	# export paths
	_export_heightmap("/tmp/fmg_smoke_height.png")
	print("[smoke] heightmap -> ", status_label.text)
	_export_geojson("/tmp/fmg_smoke.geojson")
	print("[smoke] geojson -> ", status_label.text)
	# save + load roundtrip
	var err: Error = sim.save_map("/tmp/fmg_smoke_test.map")
	print("[smoke] save_map -> ", error_string(err))
	err = sim.load_map("/tmp/fmg_smoke_test.map")
	print("[smoke] load_map -> ", error_string(err))
	print("[smoke] manufactured after load: ", _count_manufacturing())
	view.rebuild_cache()
	print("[smoke] OK")
	get_tree().quit(0)


func _count_manufacturing() -> int:
	var total: int = 0
	for m in sim.pack.markets:
		total += ((m as Dictionary).get("manufacturing", []) as Array).size()
	return total


func _collect_state_names() -> String:
	var names: Array = []
	for s in sim.pack.states:
		if s != null and int(s["i"]) > 0:
			names.append("%s(%d)" % [s["name"], s.get("cells", 0)])
	return ", ".join(names)


# ---------------------------------------------------------------------------
# Generation

func _on_generate_pressed() -> void:
	if _generating:
		return
	sim.seed_value = seed_edit.text.strip_edges()
	if sim.seed_value.is_empty():
		sim.seed_value = str(randi() % 1000000000)
		seed_edit.text = sim.seed_value
	sim.template_id = _current_template_id()
	sim.cells_desired = POINTS_BY_DENSITY[density_option.get_selected_id()]
	sim.cultures_limit = int(cultures_spin.value)
	sim.cultures_set = str(cultures_set_option.get_selected_metadata()) if cultures_set_option != null else sim.cultures_set
	sim.states_limit = int(states_spin.value)
	sim.burgs_limit = -1 if burgs_check.button_pressed else 1000
	sim.poles_cache = {}
	run_generation(false)


func _current_template_id() -> String:
	var id: String = template_option.get_item_metadata(template_option.selected)
	return id if id != null else "random"


func run_generation(silent: bool = false) -> void:
	_generating = true
	if not silent:
		generate_button.disabled = true
	progress_bar.show()
	var t_start: int = Time.get_ticks_msec()

	var stages: Array = sim.pipeline()
	var total: int = stages.size()
	for i: int in stages.size():
		var stage: Array = stages[i]
		status_label.text = "Генерация: %s…" % stage[0]
		progress_bar.value = float(i) / float(total)
		await get_tree().process_frame
		await get_tree().process_frame
		sim.run_stage(stage)

	sim.finish_generation(t_start)
	progress_bar.value = 1.0
	progress_bar.hide()
	view.rebuild_cache()
	camera.map_rect = Rect2(0, 0, sim.map_width, sim.map_height)
	status_label.text = sim.get_stats_text()
	_generating = false
	if not silent:
		generate_button.disabled = false
	await get_tree().process_frame


func _regenerate_after_edit() -> void:
	if _generating:
		return
	_rerun_pipeline(sim.pipeline_from_heightmap(), "Пересчёт")


func _on_climate_apply_pressed() -> void:
	if _generating or sim.grid == null:
		return
	_rerun_pipeline(sim.pipeline_from_climate(), "Климат")


func _on_wind_changed(value: float, index: int) -> void:
	if index >= 0 and index < sim.climate_winds.size():
		sim.climate_winds[index] = value


## reruns a pipeline tail (after a brush or climate edit), keeping the UI alive
func _rerun_pipeline(stages: Array, verb: String) -> void:
	if _generating:
		return
	_generating = true
	generate_button.disabled = true
	progress_bar.show()
	var total: int = stages.size()
	for i: int in stages.size():
		var stage: Array = stages[i]
		status_label.text = "%s: %s…" % [verb, stage[0]]
		progress_bar.value = float(i) / float(total)
		await get_tree().process_frame
		sim.run_stage(stage)
	progress_bar.hide()
	view.rebuild_cache()
	status_label.text = sim.get_stats_text()
	_generating = false
	generate_button.disabled = false


## refreshes the climate controls from Sim (after a map load)
func _refresh_climate_ui() -> void:
	if climate_equator_spin == null:
		return
	climate_equator_spin.set_value_no_signal(sim.climate_equator)
	climate_north_spin.set_value_no_signal(sim.climate_north_pole)
	climate_south_spin.set_value_no_signal(sim.climate_south_pole)
	climate_precip_spin.set_value_no_signal(sim.climate_precipitation)
	for i: int in mini(wind_spins.size(), sim.climate_winds.size()):
		(wind_spins[i] as SpinBox).set_value_no_signal(float(sim.climate_winds[i]))


# ---------------------------------------------------------------------------
# Brush editing

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			_space_held = event.pressed

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and brush_active and not _space_held:
			_brush_down = mb.pressed
			if _brush_down:
				_apply_brush(mb.position)
			else:
				_regenerate_after_edit()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _brush_down:
		var motion := event as InputEventMouseMotion
		_apply_brush(motion.position)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if brush_active:
			brush_world_pos = get_global_mouse_position()
			view.queue_redraw()


func _apply_brush(_screen_pos: Vector2) -> void:
	var world := get_global_mouse_position()
	brush_world_pos = world
	if sim.grid == null:
		return
	var radius: float = brush_size.value
	var cells := sim.grid.find_all(world.x, world.y, radius)
	var mode: int = brush_option.get_selected_id() # 0 raise, 1 lower, 2 smooth
	for cell: int in cells:
		var p: Vector2 = sim.grid.points[cell]
		var falloff: float = 1.0 - clampf(p.distance_to(world) / maxf(radius, 0.001), 0.0, 1.0)
		match mode:
			0:
				var add: float = 4.0 * falloff
				sim.grid.h[cell] = int(clampf(float(sim.grid.h[cell]) + add, 0.0, 100.0))
			1:
				var sub: float = 4.0 * falloff
				sim.grid.h[cell] = int(clampf(float(sim.grid.h[cell]) - sub, 0.0, 100.0))
			2:
				var mean_v: float = float(sim.grid.h[cell])
				var count: float = 1.0
				for n: int in sim.grid.c[cell]:
					mean_v += float(sim.grid.h[n])
					count += 1.0
				mean_v /= count
				var w: float = falloff * 0.6
				sim.grid.h[cell] = int(clampf(float(sim.grid.h[cell]) * (1.0 - w) + mean_v * w, 0.0, 100.0))
	view.queue_redraw()


# ---------------------------------------------------------------------------
# Save / load / export

func _on_save_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "map_%s.map" % sim.seed_value
	dialog.filters = PackedStringArray(["*.map ; Карты FMG"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var err: Error = sim.save_map(path)
		status_label.text = "Сохранено: %s (%s)" % [path, error_string(err)]
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


func _on_load_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.map ; Карты FMG"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var err: Error = sim.load_map(path)
		if err == OK:
			seed_edit.text = sim.seed_value
			_refresh_climate_ui()
			view.rebuild_cache()
			camera.map_rect = Rect2(0, 0, sim.map_width, sim.map_height)
			status_label.text = "Загружено: %s" % path
			camera.fit_to_map()
		else:
			status_label.text = "Ошибка загрузки: %s" % error_string(err)
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


func _on_export_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "map_%s.png" % sim.seed_value
	dialog.filters = PackedStringArray(["*.png ; PNG изображение"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		_export_png(path)
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


func _export_png(path: String) -> void:
	var scale_factor: int = 2
	var sv := SubViewport.new()
	sv.size = Vector2i(int(sim.map_width) * scale_factor, int(sim.map_height) * scale_factor)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(sv)
	var clone := MapView.new()
	clone.sim = sim
	clone.show_labels = view.show_labels
	clone.show_politics = view.show_politics
	clone.show_biomes = view.show_biomes
	clone.show_heights = view.show_heights
	clone.show_cultures = view.show_cultures
	clone.show_religions = view.show_religions
	clone.show_provinces = view.show_provinces
	clone.show_rivers = view.show_rivers
	clone.show_borders = view.show_borders
	clone.show_burgs = view.show_burgs
	clone.show_relief = view.show_relief
	clone.show_ice = view.show_ice
	clone.show_routes = view.show_routes
	clone.show_feature_labels = view.show_feature_labels
	clone.show_province_labels = view.show_province_labels
	clone.show_markers = view.show_markers
	clone.show_armies = view.show_armies
	clone.show_zones = view.show_zones
	clone.show_goods = view.show_goods
	clone.show_emblems = view.show_emblems
	clone.show_relief_icons = view.show_relief_icons
	clone.rebuild_cache()
	clone.scale = Vector2(scale_factor, scale_factor)
	sv.add_child(clone)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = sv.get_texture().get_image()
	img.save_png(path)
	status_label.text = "Экспортировано: %s" % path
	sv.queue_free()


func _export_dialog(kind: String, description: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "map_%s.%s" % [sim.seed_value, kind]
	dialog.filters = PackedStringArray(["*.%s ; %s" % [kind, description]])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		if kind == "svg":
			_export_svg(path)
		elif kind == "geojson":
			_export_geojson(path)
		else:
			_export_csv(path)
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


## SVG export: ocean background, land and lake polygons, rivers, borders,
## routes, burgs and labels — the same geometry the map view draws.
func _export_svg(path: String) -> void:
	var pack: FmgGraph = sim.pack
	if pack == null:
		status_label.text = "Нет данных для экспорта"
		return
	var svg: Array = []
	svg.append('<?xml version="1.0" encoding="UTF-8"?>')
	svg.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [
		int(sim.map_width), int(sim.map_height), int(sim.map_width), int(sim.map_height)
	])
	svg.append('<rect width="100%%" height="100%%" fill="%s"/>' % "#466eab")

	# landmasses and lakes from the cached rings
	view.rebuild_cache()
	for ring: Dictionary in view._land_rings:
		svg.append('<path d="%s" fill="%s" stroke="#33506d" stroke-width="1"/>' % [_path_d(ring["points"]), "#e6e2c8"])
	for ring: Dictionary in view._lake_rings:
		svg.append('<path d="%s" fill="%s" stroke="#33506d" stroke-width="0.7"/>' % [_path_d(ring["points"]), "#5b83b8"])

	# rivers
	for entry: Dictionary in view._river_polys:
		svg.append('<path d="%s Z" fill="%s"/>' % [_path_d(entry["points"]), "#5d99c6"])

	# borders
	svg.append(_svg_borders(pack))

	# routes
	for route: Variant in pack.routes:
		var r: Dictionary = route
		var points: PackedVector2Array = r.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var stroke: String = "#7a5c3e" if r.get("group", "") == "roads" else "#4a7ab5"
		var dash: String = ' stroke-dasharray="3 2"' if r.get("group", "") != "roads" else ""
		svg.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="0.8"%s/>' % [_poly_pts(points), stroke, dash])

	# burgs
	for b in pack.burgs:
		if b == null:
			continue
		var radius: float = 2.2 if int(b.get("capital", 0)) == 1 else 1.4
		var fill: String = "#7a1f1f" if int(b.get("capital", 0)) == 1 else "#3d2b1f"
		svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % [float(b["x"]), float(b["y"]), radius, fill])

	# state labels
	for state in pack.states:
		if state == null or int(state["i"]) == 0 or not sim.poles_cache.has(state["i"]):
			continue
		var pole: Vector2 = sim.poles_cache[state["i"]]
		svg.append('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="14" fill="#1e2124" opacity="0.85">%s</text>' % [
			pole.x, pole.y, _xml_escape(state.get("fullName", state["name"]))
		])
	svg.append('</svg>')

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status_label.text = "Ошибка записи: %s" % error_string(FileAccess.get_open_error())
		return
	f.store_string("\n".join(svg))
	f.close()
	status_label.text = "Экспортировано: %s" % path


func _path_d(points: PackedVector2Array) -> String:
	if points.is_empty():
		return ""
	var parts: Array = ["M%.1f %.1f" % [points[0].x, points[0].y]]
	for i: int in range(1, points.size()):
		parts.append("L%.1f %.1f" % [points[i].x, points[i].y])
	parts.append("Z")
	return " ".join(parts)


func _poly_pts(points: PackedVector2Array) -> String:
	var parts: Array = []
	for p: Vector2 in points:
		parts.append("%.1f,%.1f" % [p.x, p.y])
	return " ".join(parts)


func _svg_borders(pack: FmgGraph) -> String:
	var segments: Array = []
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
				segments.append("M%.1f %.1f L%.1f %.1f" % [
					vertices.p[common[0]].x, vertices.p[common[0]].y,
					vertices.p[common[1]].x, vertices.p[common[1]].y
				])
	if segments.is_empty():
		return ""
	return '<path d="%s" stroke="#1a334d" stroke-width="1" stroke-opacity="0.65" fill="none"/>' % " ".join(segments)


func _xml_escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


func _on_heightmap_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "heightmap_%s.png" % sim.seed_value
	dialog.filters = PackedStringArray(["*.png ; PNG высотная карта"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		_export_heightmap(path)
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


## Heightmap export: grayscale PNG at map resolution, sampled from the grid
## heights (0 = black … 100 = white, sea level 20 ≈ gray 51).
func _export_heightmap(path: String) -> void:
	var grid: FmgGraph = sim.grid
	if grid == null:
		status_label.text = "Нет данных для экспорта"
		return
	var width: int = int(sim.map_width)
	var height: int = int(sim.map_height)
	if width <= 0 or height <= 0 or grid.h.is_empty():
		status_label.text = "Нет данных для экспорта"
		return
	var data := PackedByteArray()
	data.resize(width * height)
	var spacing: float = grid.spacing
	var cells_x: int = grid.cells_x
	var cells_y: int = grid.cells_y
	var last_idx: int = grid.h.size() - 1
	for y: int in height:
		var row: int = mini(int(float(y) / spacing), cells_y - 1)
		for x: int in width:
			var col: int = mini(int(float(x) / spacing), cells_x - 1)
			var idx: int = mini(row * cells_x + col, last_idx)
			data[y * width + x] = clampi(int(round(float(grid.h[idx]) * 2.55)), 0, 255)
	var img := Image.create_from_data(width, height, false, Image.FORMAT_R8, data)
	if img == null:
		status_label.text = "Ошибка создания изображения"
		return
	var err: Error = img.save_png(path)
	status_label.text = ("Экспортировано: %s" % path) if err == OK else ("Ошибка записи: %s" % error_string(err))


## GeoJSON export: pack cells as polygons with attributes, burgs as points,
## rivers as linestrings. Coordinates are map pixels (y grows downward);
## see the "metadata" member of the collection.
func _export_geojson(path: String) -> void:
	var pack: FmgGraph = sim.pack
	if pack == null:
		status_label.text = "Нет данных для экспорта"
		return
	var features: Array = []
	for i: int in pack.cell_count():
		var poly := pack.get_polygon(i)
		if poly.size() < 3:
			continue
		var ring: Array = []
		for p: Vector2 in poly:
			ring.append("[%.1f,%.1f]" % [p.x, p.y])
		ring.append("[%.1f,%.1f]" % [poly[0].x, poly[0].y])
		features.append('{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[%s]]},"properties":%s}' % [",".join(ring), _geojson_cell_props(i)])
	for b in pack.burgs:
		if b == null:
			continue
		features.append('{"type":"Feature","geometry":{"type":"Point","coordinates":[%.1f,%.1f]},"properties":%s}' % [float(b["x"]), float(b["y"]), _geojson_burg_props(b)])
	for river in pack.rivers:
		if river == null:
			continue
		var line: Array = []
		for cell_id: Variant in (river as Dictionary).get("cells", []):
			var cid: int = int(cell_id)
			if cid >= 0 and cid < pack.cell_count():
				line.append("[%.1f,%.1f]" % [pack.points[cid].x, pack.points[cid].y])
		if line.size() < 2:
			continue
		features.append('{"type":"Feature","geometry":{"type":"LineString","coordinates":[%s]},"properties":%s}' % [",".join(line), _geojson_river_props(river)])
	var header: String = '{"type":"FeatureCollection","metadata":{"seed":"%s","template":"%s","width":%d,"height":%d,"seaLevel":20,"cells":%d,"note":"coordinates are map pixels; y grows downward"},' % [
		_json_escape(sim.seed_value), _json_escape(sim.template_id), int(sim.map_width), int(sim.map_height), pack.cell_count()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status_label.text = "Ошибка записи: %s" % error_string(FileAccess.get_open_error())
		return
	f.store_string(header + '"features":[' + ",".join(features) + "]}")
	f.close()
	status_label.text = "Экспортировано: %s" % path


func _geojson_cell_props(i: int) -> String:
	var pack: FmgGraph = sim.pack
	return '{"kind":"cell","id":%d,"x":%.1f,"y":%.1f,"height":%d,"biome":%d,"biomeName":"%s","culture":%d,"cultureName":"%s","state":%d,"stateName":"%s","province":%d,"provinceName":"%s","religion":%d,"religionName":"%s","population":%.2f,"river":%d,"flux":%.1f,"good":%d,"market":%d}' % [
		i, pack.points[i].x, pack.points[i].y, pack.h[i],
		pack.biome[i], _json_escape(_biome_name(pack.biome[i])),
		pack.culture[i], _json_escape(_table_name(pack.cultures, pack.culture[i])),
		pack.state[i], _json_escape(_table_name(pack.states, pack.state[i])),
		pack.province[i], _json_escape(_table_name(pack.provinces, pack.province[i])),
		pack.religion[i], _json_escape(_table_name(pack.religions, pack.religion[i])),
		pack.pop[i], pack.r[i], pack.fl[i], pack.good[i], pack.market[i]
	]


func _geojson_burg_props(b: Dictionary) -> String:
	return '{"kind":"burg","id":%d,"name":"%s","population":%.3f,"capital":%d,"port":%d,"state":%d,"stateName":"%s","culture":%d,"cultureName":"%s"}' % [
		int(b.get("i", 0)), _json_escape(str(b.get("name", ""))), float(b.get("population", 0.0)),
		1 if int(b.get("capital", 0)) == 1 else 0, int(b.get("port", 0)),
		int(b.get("state", 0)), _json_escape(_table_name(sim.pack.states, int(b.get("state", 0)))),
		int(b.get("culture", 0)), _json_escape(_table_name(sim.pack.cultures, int(b.get("culture", 0))))
	]


func _geojson_river_props(river: Dictionary) -> String:
	return '{"kind":"river","id":%d,"name":"%s","type":"%s","length":%.1f,"width":%.2f}' % [
		int(river.get("i", 0)), _json_escape(str(river.get("name", ""))), _json_escape(str(river.get("type", ""))),
		float(river.get("length", 0.0)), float(river.get("width", 0.0))
	]


func _biome_name(biome_id: int) -> String:
	if sim.pack == null or biome_id < 0 or biome_id >= sim.pack.biomes.size():
		return ""
	return str((sim.pack.biomes[biome_id] as Dictionary).get("name", ""))


func _table_name(table: Array, entry_id: int) -> String:
	if entry_id <= 0 or entry_id >= table.size() or table[entry_id] == null:
		return ""
	return str((table[entry_id] as Dictionary).get("name", ""))


func _json_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


## CSV export: one row per cell with the main attributes.
func _export_csv(path: String) -> void:
	var pack: FmgGraph = sim.pack
	if pack == null:
		status_label.text = "Нет данных для экспорта"
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status_label.text = "Ошибка записи: %s" % error_string(FileAccess.get_open_error())
		return
	f.store_line("id;x;y;height;biome;culture;state;province;religion;population;good;market;river;flux")
	for i: int in pack.cell_count():
		f.store_line("%d;%.1f;%.1f;%d;%d;%d;%d;%d;%.2f;%d;%d;%d;%.1f" % [
			i, pack.points[i].x, pack.points[i].y, pack.h[i], pack.biome[i],
			pack.culture[i], pack.state[i], pack.province[i], pack.religion[i],
			pack.pop[i], pack.good[i], pack.market[i], pack.r[i], pack.fl[i]
		])
	f.close()
	status_label.text = "Экспортировано: %s" % path


# ---------------------------------------------------------------------------
# UI construction

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	# --- right sidebar ---
	var panel := PanelContainer.new()
	panel.name = "Sidebar"
	panel.custom_minimum_size = Vector2(270, 0)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# --- map section ---
	vbox.add_child(_make_header("Карта"))
	seed_edit = LineEdit.new()
	seed_edit.text = sim.seed_value
	seed_edit.placeholder_text = "Сид карты"
	vbox.add_child(_make_row("Сид", seed_edit))

	var dice := Button.new()
	dice.text = "Случайный сид"
	dice.pressed.connect(func() -> void:
		seed_edit.text = str(randi() % 1000000000)
	)
	vbox.add_child(dice)

	template_option = OptionButton.new()
	var templates: Array = HeightmapTemplates.TEMPLATES.keys()
	template_option.add_item("Случайный", 0)
	template_option.set_item_metadata(0, "random")
	var t_index: int = 1
	for tid: String in templates:
		template_option.add_item(HeightmapTemplates.template_name(tid), t_index)
		template_option.set_item_metadata(t_index, tid)
		t_index += 1
	template_option.select(1 + 3) # continents by default
	vbox.add_child(_make_row("Шаблон", template_option))

	density_option = OptionButton.new()
	for d: Array in DENSITIES:
		density_option.add_item("%s ячеек" % d[1], d[0])
	density_option.select(3)
	vbox.add_child(_make_row("Детализация", density_option))

	cultures_spin = SpinBox.new()
	cultures_spin.min_value = 1
	cultures_spin.max_value = 32
	cultures_spin.value = sim.cultures_limit
	vbox.add_child(_make_row("Культур", cultures_spin))

	cultures_set_option = OptionButton.new()
	var set_index: int = 0
	for set_id: String in FmgCultures.CULTURE_SETS:
		var set_meta: Dictionary = FmgCultures.CULTURE_SETS[set_id]
		cultures_set_option.add_item(str(set_meta["nameRu"]), set_index)
		cultures_set_option.set_item_metadata(set_index, set_id)
		if set_id == sim.cultures_set:
			cultures_set_option.select(set_index)
		set_index += 1
	vbox.add_child(_make_row("Набор культур", cultures_set_option))

	states_spin = SpinBox.new()
	states_spin.min_value = 1
	states_spin.max_value = 60
	states_spin.value = sim.states_limit
	vbox.add_child(_make_row("Государств", states_spin))

	burgs_check = CheckButton.new()
	burgs_check.text = "Города: авто"
	burgs_check.button_pressed = true
	vbox.add_child(burgs_check)

	# --- climate section (world configurator; values live in Sim) ---
	vbox.add_child(_make_header("Климат"))
	climate_equator_spin = _make_climate_spin(vbox, "Экватор °C", -10.0, 40.0, 0.5, sim.climate_equator, func(v: float) -> void: sim.climate_equator = v)
	climate_north_spin = _make_climate_spin(vbox, "Сев. полюс °C", -60.0, 15.0, 0.5, sim.climate_north_pole, func(v: float) -> void: sim.climate_north_pole = v)
	climate_south_spin = _make_climate_spin(vbox, "Юж. полюс °C", -60.0, 15.0, 0.5, sim.climate_south_pole, func(v: float) -> void: sim.climate_south_pole = v)
	climate_precip_spin = _make_climate_spin(vbox, "Осадки %", 0.0, 400.0, 5.0, sim.climate_precipitation, func(v: float) -> void: sim.climate_precipitation = v)
	wind_spins = []
	var wind_names: Array = ["Ветер N пол.", "Ветер N умер.", "Ветер троп. N", "Ветер троп. S", "Ветер S умер.", "Ветер S пол."]
	for i: int in 6:
		var wind_spin := SpinBox.new()
		wind_spin.min_value = 0.0
		wind_spin.max_value = 360.0
		wind_spin.step = 5.0
		wind_spin.value = float(sim.climate_winds[i]) if i < sim.climate_winds.size() else 0.0
		wind_spin.tooltip_text = "Направление преобладающего ветра пояса в градусах"
		vbox.add_child(_make_row(wind_names[i], wind_spin))
		wind_spin.value_changed.connect(_on_wind_changed.bind(i))
		wind_spins.append(wind_spin)

	var climate_btn := Button.new()
	climate_btn.text = "Применить климат"
	climate_btn.tooltip_text = "Пересчитать температуру, осадки и всё ниже по конвейеру"
	climate_btn.pressed.connect(_on_climate_apply_pressed)
	vbox.add_child(climate_btn)

	var climate_hint := Label.new()
	climate_hint.text = "Климат применяется кнопкой выше или при следующей генерации."
	climate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	climate_hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(climate_hint)

	generate_button = Button.new()
	generate_button.text = "Сгенерировать карту"
	generate_button.custom_minimum_size = Vector2(0, 40)
	generate_button.pressed.connect(_on_generate_pressed)
	vbox.add_child(generate_button)

	# --- layers section ---
	vbox.add_child(_make_header("Слои"))
	_add_layer_check(vbox, "Политика", "politics", view.show_politics)
	_add_layer_check(vbox, "Биомы", "biomes", view.show_biomes)
	_add_layer_check(vbox, "Высоты", "heights", view.show_heights)
	_add_layer_check(vbox, "Рельеф (затенение)", "relief", view.show_relief)
	_add_layer_check(vbox, "Культуры", "cultures", view.show_cultures)
	_add_layer_check(vbox, "Религии", "religions", view.show_religions)
	_add_layer_check(vbox, "Провинции", "provinces", view.show_provinces)
	_add_layer_check(vbox, "Реки", "rivers", view.show_rivers)
	_add_layer_check(vbox, "Границы", "borders", view.show_borders)
	_add_layer_check(vbox, "Города", "burgs", view.show_burgs)
	_add_layer_check(vbox, "Подписи", "labels", view.show_labels)
	_add_layer_check(vbox, "Лёд", "ice", view.show_ice)
	_add_layer_check(vbox, "Дороги", "routes", view.show_routes)
	_add_layer_check(vbox, "Подписи рельефа", "feature_labels", view.show_feature_labels)
	_add_layer_check(vbox, "Подписи провинций", "province_labels", view.show_province_labels)
	_add_layer_check(vbox, "Маркеры", "markers", view.show_markers)
	_add_layer_check(vbox, "Армии", "armies", view.show_armies)
	_add_layer_check(vbox, "Зоны", "zones", view.show_zones)
	_add_layer_check(vbox, "Ресурсы", "goods", view.show_goods)
	_add_layer_check(vbox, "Гербы", "emblems", view.show_emblems)
	_add_layer_check(vbox, "Иконки рельефа", "relief_icons", view.show_relief_icons)

	# --- tools section ---
	vbox.add_child(_make_header("Инструменты"))
	brush_option = OptionButton.new()
	brush_option.add_item("Кисть: выключена", -1)
	brush_option.add_item("Поднять рельеф", 0)
	brush_option.add_item("Опустить рельеф", 1)
	brush_option.add_item("Сгладить", 2)
	brush_option.select(0)
	vbox.add_child(_make_row("Кисть", brush_option))
	brush_option.item_selected.connect(func(_i: int) -> void:
		brush_active = brush_option.get_selected_id() >= 0
		view.queue_redraw()
	)

	brush_size = HSlider.new()
	brush_size.min_value = 10.0
	brush_size.max_value = 150.0
	brush_size.value = 45.0
	vbox.add_child(_make_row("Размер кисти", brush_size))

	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 4)
	var save_btn := Button.new()
	save_btn.text = "Сохранить"
	save_btn.pressed.connect(_on_save_pressed)
	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.pressed.connect(_on_load_pressed)
	var png_btn := Button.new()
	png_btn.text = "PNG"
	png_btn.pressed.connect(_on_export_pressed)
	var svg_btn := Button.new()
	svg_btn.text = "SVG"
	svg_btn.pressed.connect(func() -> void: _export_dialog("svg", "SVG векторная карта"))
	var csv_btn := Button.new()
	csv_btn.text = "CSV"
	csv_btn.pressed.connect(func() -> void: _export_dialog("csv", "CSV данные клеток"))
	io_row.add_child(save_btn)
	io_row.add_child(load_btn)
	io_row.add_child(png_btn)
	vbox.add_child(io_row)
	var io_row2 := HBoxContainer.new()
	io_row2.add_theme_constant_override("separation", 4)
	io_row2.add_child(svg_btn)
	io_row2.add_child(csv_btn)
	var height_btn := Button.new()
	height_btn.text = "Высота"
	height_btn.tooltip_text = "Экспорт высотной карты (grayscale PNG)"
	height_btn.pressed.connect(_on_heightmap_pressed)
	var geo_btn := Button.new()
	geo_btn.text = "GeoJSON"
	geo_btn.tooltip_text = "Экспорт клеток, городов и рек в GeoJSON"
	geo_btn.pressed.connect(func() -> void: _export_dialog("geojson", "GeoJSON геоданные"))
	io_row2.add_child(height_btn)
	io_row2.add_child(geo_btn)
	vbox.add_child(io_row2)

	var hint := Label.new()
	hint.text = "Колесо — зум, ПКМ/пробел+ЛКМ — панорама."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	# --- status bar ---
	var status_panel := PanelContainer.new()
	status_panel.name = "StatusBar"
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	layer.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_panel.add_child(status_box)
	status_label = Label.new()
	status_label.text = "Готов к генерации"
	status_box.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.visible = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	status_box.add_child(progress_bar)

	camera.fit_to_map()


func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#c8a24a"))
	return label


func _make_climate_spin(parent: Control, label_text: String, min_value: float, max_value: float, step: float, initial: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = initial
	parent.add_child(_make_row(label_text, spin))
	spin.value_changed.connect(func(v: float) -> void: on_change.call(v))
	return spin


func _make_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(105, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _add_layer_check(parent: Control, text: String, key: String, initial: bool) -> void:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = initial
	parent.add_child(check)
	layer_checks[key] = check
	check.toggled.connect(func(pressed: bool) -> void:
		match key:
			"politics": view.show_politics = pressed
			"biomes": view.show_biomes = pressed
			"heights": view.show_heights = pressed
			"relief": view.show_relief = pressed
			"cultures": view.show_cultures = pressed
			"religions": view.show_religions = pressed
			"provinces": view.show_provinces = pressed
			"rivers": view.show_rivers = pressed
			"borders": view.show_borders = pressed
			"burgs": view.show_burgs = pressed
			"labels": view.show_labels = pressed
			"ice": view.show_ice = pressed
			"routes": view.show_routes = pressed
			"feature_labels": view.show_feature_labels = pressed
			"province_labels": view.show_province_labels = pressed
			"markers": view.show_markers = pressed
			"armies": view.show_armies = pressed
			"zones": view.show_zones = pressed
			"goods": view.show_goods = pressed
			"emblems": view.show_emblems = pressed
			"relief_icons": view.show_relief_icons = pressed
		view.queue_redraw()
	)
