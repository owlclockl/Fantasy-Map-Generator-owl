extends Node2D
## Main orchestrator: builds the FMG-style UI (menu, overviews, loading
## overlay), runs the generation pipeline in a worker thread (keeping the UI
## responsive), handles the heightmap brush, the ruler tool, save/load and
## export.

var sim: FmgSim = null # Sim autoload
var view: MapView = null
var camera: MapCamera = null
var ui_theme: FmgUiTheme = null
var menu: FmgMainMenu = null
var overviews: FmgOverviewDialogs = null

var _generation_thread: Thread = null
var _generation_worker: FmgGenerationWorker = null
var _preview_output: String = "" # --preview <path>: software-render a PNG after generation

# The project is designed on a 1680×960 canvas; the window scales the interface
# from there (stretch mode "canvas_items"), and this extra factor lets the user
# make the UI even bigger on dense screens.
enum UiScaleMode { AUTO = 0, MANUAL = 1 }
var ui_scale_mode: int = UiScaleMode.AUTO
var ui_scale_value: float = 1.0
var _settings_loaded: bool = false

# brush state
var brush_active: bool = false
var brush_world_pos := Vector2.ZERO
var _brush_down: bool = false
var _space_held: bool = false
var _generating: bool = false


func _ready() -> void:
	# Rasterize fonts at the real output resolution: without this the interface
	# and the map lettering are magnified blurs on HiDPI screens and at zoom.
	var viewport := get_viewport()
	if viewport != null:
		viewport.oversampling = true
	var window := get_window()
	if window != null:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if not window.size_changed.is_connected(_on_window_resized):
			window.size_changed.connect(_on_window_resized)

	sim = get_node("/root/Sim") as FmgSim
	view = MapView.new()
	view.sim = sim
	view.name = "MapView"
	add_child(view)

	camera = MapCamera.new()
	camera.name = "Camera"
	add_child(camera)

	_build_ui()
	_load_settings()

	var user_args := OS.get_cmdline_user_args()
	var preview_index: int = user_args.find("--preview")
	if preview_index >= 0 and preview_index + 1 < user_args.size():
		_preview_output = user_args[preview_index + 1]

	if DisplayServer.get_name() == "headless":
		if not _preview_output.is_empty():
			_run_headless_preview()
		else:
			_run_headless_smoke()
	else:
		_on_generate_requested.call_deferred()


## `godot --headless . -- --preview out.png` — generate and software-render
## the map to a PNG without any GPU (CI / server usage).
func _run_headless_preview() -> void:
	print("[preview] generating for ", _preview_output)
	# _finish_generation_result saves the PNG once the map is ready
	await run_generation(true)
	print("[preview] OK")
	get_tree().quit(0)


func _run_headless_smoke() -> void:
	print("[smoke] headless generation test started")
	await run_generation(true)
	print("[smoke] stats: ", sim.get_stats_text())
	print("[smoke] states: ", _collect_state_names())
	print("[smoke] manufactured records: ", _count_manufacturing())
	# UI smoke: menu built, every tab selectable, overview tables populated
	_ui_smoke()
	# render smoke: enable every layer and force the draw path
	for property: Dictionary in view.get_property_list():
		var prop_name: String = str(property.get("name", ""))
		if prop_name.begins_with("show_") and view.get(prop_name) is bool:
			view.set(prop_name, true)
	view.ruler_points = PackedVector2Array([Vector2(100, 100), Vector2(400, 300), Vector2(600, 500)])
	# a manual NOTIFICATION_DRAW runs the whole _draw path even headlessly
	view.notification(CanvasItem.NOTIFICATION_DRAW)
	print("[smoke] draw path exercised")
	# lettering diagnostics: the on-screen size of a 14 pt name must follow the
	# device scale in WITH_MAP and stay constant in FIXED_SCREEN
	print("[labels] mode=", view.label_scale_mode, " canvas_scale=", view.canvas_scale(),
		" camera_zoom=", view.camera_zoom(), " interface_scale=", view.interface_scale(),
		" oversampling=", view.label_oversampling(14.0))
	var restore_zoom: Vector2 = camera.zoom
	camera.zoom = Vector2(8.0, 8.0)
	view.notification(CanvasItem.NOTIFICATION_DRAW)
	print("[labels] at 800%: canvas_scale=", view.canvas_scale(),
		" fixed_px=", view.label_screen_size(14.0, MapView.LabelScale.FIXED_SCREEN),
		" map_px=", view.label_screen_size(14.0, MapView.LabelScale.WITH_MAP),
		" oversampling=", view.label_oversampling(14.0))
	camera.zoom = restore_zoom
	view.queue_redraw()
	# software-rendered previews of the default (political) and biome views
	menu.apply_preset("political")
	await _save_preview("/tmp/fmg_smoke_preview_political.png", true)
	menu.apply_preset("biomes")
	view.show_relief = true
	view.show_relief_icons = true
	await _save_preview("/tmp/fmg_smoke_preview_biomes.png", true)
	# export paths
	_export_heightmap("/tmp/fmg_smoke_height.png")
	print("[smoke] heightmap -> ", menu.status_label.text)
	_export_geojson("/tmp/fmg_smoke.geojson")
	print("[smoke] geojson -> ", menu.status_label.text)
	# save + load roundtrip
	var err: Error = sim.save_map("/tmp/fmg_smoke_test.map")
	print("[smoke] save_map -> ", error_string(err))
	err = sim.load_map("/tmp/fmg_smoke_test.map")
	print("[smoke] load_map -> ", error_string(err))
	print("[smoke] manufactured after load: ", _count_manufacturing())
	view.rebuild_cache()
	view.notification(CanvasItem.NOTIFICATION_DRAW)
	print("[smoke] OK")
	get_tree().quit(0)


## Verifies the menu tree: tabs switch, layer buttons match the view state,
## presets apply and overview windows build their tables.
func _ui_smoke() -> void:
	var issues: int = 0
	for tab_id: String in FmgMainMenu.TAB_IDS:
		menu.select_tab(tab_id)
	for preset_id: String in FmgMainMenu.PRESETS.keys():
		menu.apply_preset(preset_id)
	menu.apply_preset("political")
	for kind: String in ["burgs", "states", "rivers", "markers", "markets", "diplomacy"]:
		overviews.open(kind)
		if not overviews.is_open():
			issues += 1
			print("[smoke] overview failed: ", kind)
		overviews.close_window()
	menu.handle_layer_key(KEY_B) # toggle biomes via hotkey path
	if not view.show_biomes:
		issues += 1
		print("[smoke] layer hotkey failed")
	menu.apply_generation_options()
	var requested_flag := [false]
	var test_sub := func(): requested_flag[0] = true
	menu.generate_requested.connect(test_sub)
	menu.request_new_map()
	menu.generate_requested.disconnect(test_sub)
	if not requested_flag[0]:
		issues += 1
		print("[smoke] request_new_map failed")
	if issues == 0:
		print("[smoke] UI tree OK (tabs, presets, overviews, hotkeys, options)")


func _count_manufacturing() -> int:
	var total: int = 0
	for m in sim.pack.markets:
		total += ((m as Dictionary).get("manufacturing", []) as Array).size()
	return total


## Software-renders the current map state to a PNG (no GPU required).
func _save_preview(path: String, restore_layers: bool = false) -> void:
	if sim.pack == null:
		return
	var snapshot: Dictionary = {}
	if restore_layers:
		for property: Dictionary in view.get_property_list():
			var prop_name: String = str(property.get("name", ""))
			if prop_name.begins_with("show_") and view.get(prop_name) is bool:
				snapshot[prop_name] = view.get(prop_name)
	var preview: Image = FmgSoftwareRender.render_map(view, int(sim.map_width), int(sim.map_height))
	var err: Error = preview.save_png(path)
	print("[preview] ", path, " -> ", error_string(err))
	if restore_layers:
		for prop_name: String in snapshot:
			view.set(prop_name, snapshot[prop_name])
		view.queue_redraw()


func _collect_state_names() -> String:
	var names: Array = []
	for s in sim.pack.states:
		if s != null and int(s["i"]) > 0:
			names.append("%s(%d)" % [s["name"], s.get("cells", 0)])
	return ", ".join(names)


# ---------------------------------------------------------------------------
# Generation

func _on_generate_requested() -> void:
	if _generating:
		return
	if menu != null:
		menu.apply_generation_options()
	run_generation(false)


func run_generation(silent: bool = false) -> void:
	if _generating:
		return
	_generating = true
	if menu != null:
		menu.set_busy(true)
		menu.close_popups()
		menu.show_loading(true)
	view.visible = false
	menu.show_progress(true)
	menu.set_status("Генерация запускается в фоновом потоке…")

	# Use the live Sim instance so the existing Names autoload and all
	# generators continue to share the same context. The map view is hidden
	# while its graph is being replaced by the worker.
	_generation_worker = FmgGenerationWorker.new({}, sim)
	_generation_thread = Thread.new()
	var start_error: Error = _generation_thread.start(_generation_worker.run, Thread.PRIORITY_NORMAL)
	if start_error != OK:
		# Thread creation can fail on a restricted export target. Keep a safe
		# synchronous fallback instead of leaving the UI locked.
		var result: FmgSim = _generation_worker.run()
		_generation_thread = null
		_generation_worker = null
		_finish_generation_result(result, silent, "Генерация")
		return
	await _wait_for_generation_result(silent, "Генерация")


func _regenerate_after_edit() -> void:
	if _generating:
		return
	_start_pipeline_tail("heightmap", "Пересчёт")


func _on_climate_apply_requested() -> void:
	if _generating or sim.grid == null:
		return
	_start_pipeline_tail("climate", "Климат")


func _start_pipeline_tail(tail: String, verb: String) -> void:
	_generating = true
	if menu != null:
		menu.set_busy(true)
		menu.close_popups()
	view.visible = false
	menu.show_progress(true)
	menu.set_status("%s запускается в фоновом потоке…" % verb)
	_generation_worker = FmgGenerationWorker.new({}, sim, tail)
	_generation_thread = Thread.new()
	var start_error: Error = _generation_thread.start(_generation_worker.run, Thread.PRIORITY_NORMAL)
	if start_error != OK:
		var result: FmgSim = _generation_worker.run()
		_generation_thread = null
		_generation_worker = null
		_finish_generation_result(result, false, verb)
		return
	await _wait_for_generation_result(false, verb)


## Poll only the worker's mutex-protected progress on the main thread. All
## graph generation and recipe production stay off the UI thread.
func _wait_for_generation_result(silent: bool, verb: String) -> void:
	while _generation_thread != null and _generation_thread.is_alive():
		var progress: Dictionary = _generation_worker.get_progress()
		var total: int = maxi(int(progress.get("total", 1)), 1)
		var index: int = int(progress.get("index", 0))
		var stage: String = "%s: %s…" % [verb, progress.get("name", "Подготовка")]
		menu.set_status(stage)
		menu.set_loading_stage(stage, float(index) / float(total))
		menu.set_progress(clampf(float(index) / float(total), 0.0, 0.99))
		await get_tree().process_frame

	if _generation_thread == null:
		return
	var result: Variant = _generation_thread.wait_to_finish()
	_generation_thread = null
	_generation_worker = null
	if result is FmgSim:
		_finish_generation_result(result as FmgSim, silent, verb)
	else:
		menu.set_status("%s: поток завершился без результата" % verb)
		view.visible = true
		_generating = false
		menu.set_busy(false)
		menu.show_loading(false)
		menu.show_progress(false)


func _finish_generation_result(result: FmgSim, silent: bool, verb: String) -> void:
	if result == null:
		menu.set_status("%s: не удалось получить результат" % verb)
		view.visible = true
		_generating = false
		menu.set_busy(false)
		menu.show_loading(false)
		menu.show_progress(false)
		return
	if result != sim:
		sim.adopt_generation(result)
	# The signal is emitted here, on the main thread, after the worker has
	# stopped touching the generated data.
	sim.generation_time_ms = result.generation_time_ms
	sim.map_generated.emit()
	menu.set_progress(1.0)
	menu.show_progress(false)
	menu.show_loading(false)
	view.rebuild_cache()
	view.visible = true
	camera.set_map_rect(Rect2(0, 0, sim.map_width, sim.map_height))
	menu.set_status(sim.get_stats_text())
	menu.refresh_from_sim()
	_generating = false
	menu.set_busy(false)
	_save_settings()
	if not _preview_output.is_empty():
		_save_preview(_preview_output)


# ---------------------------------------------------------------------------
# Input: hotkeys, brush, ruler

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed:
		var handled: bool = _handle_hotkey((event as InputEventKey).keycode)
		if handled:
			get_viewport().set_input_as_handled()
			return

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
		elif mb.button_index == MOUSE_BUTTON_LEFT and _ruler_active():
			if mb.pressed:
				view.ruler_points.append(get_global_mouse_position())
				view.queue_redraw()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and _ruler_active():
			view.ruler_points = PackedVector2Array()
			view.queue_redraw()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _brush_down:
		var motion := event as InputEventMouseMotion
		_apply_brush(motion.position)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if brush_active or _ruler_active():
			brush_world_pos = get_global_mouse_position()
			view.queue_redraw()


func _ruler_active() -> bool:
	return view.show_rulers and menu != null and menu.ruler_check != null and menu.ruler_check.button_pressed


func _handle_hotkey(keycode: int) -> bool:
	match keycode:
		KEY_TAB:
			menu.toggle_menu()
			return true
		KEY_F2:
			if menu != null:
				menu.request_new_map()
			else:
				_on_generate_requested()
			return true
		KEY_0:
			camera.fit_to_map()
			return true
		KEY_ESCAPE:
			if overviews.is_open():
				overviews.close_window()
				return true
			if menu.export_popup.visible or menu.omnibar.visible:
				menu.close_popups()
				return true
			if menu.is_menu_visible():
				menu.hide_menu()
				return true
			return false
		KEY_SPACE:
			# omnibar search, like the original
			menu.open_omnibar()
			return true
	if menu.handle_layer_key(keycode):
		return true
	return false


func _apply_brush(_screen_pos: Vector2) -> void:
	if _generating:
		return
	var world := get_global_mouse_position()
	brush_world_pos = world
	if sim.grid == null:
		return
	var radius: float = menu.brush_size.value
	var cells := sim.grid.find_all(world.x, world.y, radius)
	var mode: int = menu.brush_option.get_selected_id() # 0 raise, 1 lower, 2 smooth
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

func _on_save_requested() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "map_%s.map" % sim.seed_value
	dialog.filters = PackedStringArray(["*.map ; Карты FMG"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var err: Error = sim.save_map(path)
		menu.set_status("Сохранено: %s (%s)" % [path, error_string(err)])
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


func _on_load_requested() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.map ; Карты FMG"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var err: Error = sim.load_map(path)
		if err == OK:
			menu.refresh_from_sim()
			view.rebuild_cache()
			camera.set_map_rect(Rect2(0, 0, sim.map_width, sim.map_height))
			menu.set_status("Загружено: %s" % path)
			camera.fit_to_map()
			view.queue_redraw()
		else:
			menu.set_status("Ошибка загрузки: %s" % error_string(err))
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2i(700, 500))


func _on_export_requested(kind: String) -> void:
	match kind:
		"png":
			_on_export_pressed()
		"svg":
			_export_dialog("svg", "SVG векторная карта")
		"csv":
			_export_dialog("csv", "CSV данные клеток")
		"geojson":
			_export_dialog("geojson", "GeoJSON геоданные")
		"height":
			_on_heightmap_pressed()


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
	# Copy every layer toggle and style value, including future ones.
	for property: Dictionary in view.get_property_list():
		var name_v: String = str(property.get("name", ""))
		if name_v.begins_with("show_") and view.get(name_v) is bool:
			clone.set(name_v, view.get(name_v))
	clone.style_ocean = view.style_ocean
	clone.style_land = view.style_land
	clone.style_lake = view.style_lake
	clone.style_river = view.style_river
	clone.style_coast = view.style_coast
	clone.style_border = view.style_border
	clone.style_road = view.style_road
	clone.style_trail = view.style_trail
	clone.style_searoute = view.style_searoute
	clone.style_text = view.style_text
	clone.style_ice = view.style_ice
	clone.style_coast_width = view.style_coast_width
	clone.style_border_width = view.style_border_width
	clone.style_road_width = view.style_road_width
	clone.style_label_scale = view.style_label_scale
	clone.distance_scale = view.distance_scale
	clone.label_scale_mode = view.label_scale_mode
	clone.label_declutter = view.label_declutter
	clone.label_avoid_overlap = view.label_avoid_overlap
	clone.label_min_px = view.label_min_px
	clone.scale_bar_on_map = view.scale_bar_on_map
	clone.vignette_on_map = view.vignette_on_map
	clone.rebuild_cache()
	clone.scale = Vector2(scale_factor, scale_factor)
	sv.add_child(clone)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = sv.get_texture().get_image()
	img.save_png(path)
	menu.set_status("Экспортировано: %s" % path)
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
		menu.set_status("Нет данных для экспорта")
		return
	var svg: Array = []
	svg.append('<?xml version="1.0" encoding="UTF-8"?>')
	svg.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [
		int(sim.map_width), int(sim.map_height), int(sim.map_width), int(sim.map_height)
	])
	svg.append('<rect width="100%%" height="100%%" fill="%s"/>' % view.style_ocean.to_html(false))

	# landmasses and lakes from the cached rings
	view.rebuild_cache()
	for ring: Dictionary in view._land_rings:
		svg.append('<path d="%s" fill="%s" stroke="%s" stroke-width="1"/>' % [_path_d(ring["points"]), view.style_land.to_html(false), view.style_coast.to_html(false)])
	for ring: Dictionary in view._lake_rings:
		svg.append('<path d="%s" fill="%s" stroke="%s" stroke-width="0.7"/>' % [_path_d(ring["points"]), view.style_lake.to_html(false), view.style_coast.to_html(false)])

	# rivers
	for entry: Dictionary in view._river_polys:
		svg.append('<path d="%s Z" fill="%s"/>' % [_path_d(entry["points"]), view.style_river.to_html(false)])

	# borders
	svg.append(_svg_borders(pack))

	# routes
	for route: Variant in pack.routes:
		var r: Dictionary = route
		var points: PackedVector2Array = r.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var stroke: String = view.style_searoute.to_html(false) if r.get("group", "") != "roads" else view.style_road.to_html(false)
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
		menu.set_status("Ошибка записи: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string("\n".join(svg))
	f.close()
	menu.set_status("Экспортировано: %s" % path)


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
	return '<path d="%s" stroke="%s" stroke-width="1" stroke-opacity="0.65" fill="none"/>' % [" ".join(segments), view.style_border.to_html(false)]


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
		menu.set_status("Нет данных для экспорта")
		return
	var width: int = int(sim.map_width)
	var height: int = int(sim.map_height)
	if width <= 0 or height <= 0 or grid.h.is_empty():
		menu.set_status("Нет данных для экспорта")
		return
	var data := PackedByteArray()
	data.resize(width * height)
	var spacing: float = grid.spacing
	var cells_x: int = grid.cells_x
	var cells_y: int = grid.cells_y
	for y: int in height:
		for x: int in width:
			# Grid points are jittered, so a simple row*width lookup produces
			# visible diagonal bands in the export. Pick the nearest point from
			# the local 3x3 lattice neighbourhood; this is the same Voronoi
			# sampling used by the generated terrain rather than a stretched
			# texture approximation.
			var center_col: int = clampi(int(floor(float(x) / spacing)), 0, cells_x - 1)
			var center_row: int = clampi(int(floor(float(y) / spacing)), 0, cells_y - 1)
			var nearest: int = 0
			var nearest_d2: float = INF
			for row: int in range(maxi(center_row - 1, 0), mini(center_row + 2, cells_y)):
				for col: int in range(maxi(center_col - 1, 0), mini(center_col + 2, cells_x)):
					var candidate: int = row * cells_x + col
					if candidate >= grid.points.size():
						continue
					var dx: float = grid.points[candidate].x - float(x)
					var dy: float = grid.points[candidate].y - float(y)
					var d2: float = dx * dx + dy * dy
					if d2 < nearest_d2:
						nearest_d2 = d2
						nearest = candidate
			data[y * width + x] = clampi(int(round(float(grid.h[nearest]) * 2.55)), 0, 255)
	var img := Image.create_from_data(width, height, false, Image.FORMAT_R8, data)
	if img == null:
		menu.set_status("Ошибка создания изображения")
		return
	var err: Error = img.save_png(path)
	menu.set_status(("Экспортировано: %s" % path) if err == OK else ("Ошибка записи: %s" % error_string(err)))


## GeoJSON export: pack cells as polygons with attributes, burgs as points,
## rivers as linestrings. Coordinates are map pixels (y grows downward);
## see the "metadata" member of the collection.
func _export_geojson(path: String) -> void:
	var pack: FmgGraph = sim.pack
	if pack == null:
		menu.set_status("Нет данных для экспорта")
		return
	var features: Array = []
	for i: int in pack.cell_count():
		# Voronoi boundary cells may extend beyond the canvas. GeoJSON should
		# describe the same visible map as the renderer, not those construction
		# triangles outside the map rectangle.
		var poly: PackedVector2Array = FmgPaths.clip_poly(pack.get_polygon(i), sim.map_width, sim.map_height)
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
		menu.set_status("Ошибка записи: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(header + '"features":[' + ",".join(features) + "]}")
	f.close()
	menu.set_status("Экспортировано: %s" % path)


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
		menu.set_status("Нет данных для экспорта")
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		menu.set_status("Ошибка записи: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_line("id;x;y;height;biome;culture;state;province;religion;population;good;market;river;flux")
	for i: int in pack.cell_count():
		f.store_line("%d;%.1f;%.1f;%d;%d;%d;%d;%d;%.2f;%d;%d;%d;%.1f" % [
			i, pack.points[i].x, pack.points[i].y, pack.h[i], pack.biome[i],
			pack.culture[i], pack.state[i], pack.province[i], pack.religion[i],
			pack.pop[i], pack.good[i], pack.market[i], pack.r[i], pack.fl[i]
		])
	f.close()
	menu.set_status("Экспортировано: %s" % path)


# ---------------------------------------------------------------------------
# Interface scale and persisted settings

func _on_window_resized() -> void:
	_apply_ui_scale()
	if view != null:
		view.queue_redraw()
	if camera != null:
		camera.update_zoom_limits()


## Sets the interface scale. "Auto" leaves the scaling to the window (the
## project is authored on a 1680×960 canvas, so everything already grows with
## the window); the manual values add an extra factor on top of it.
func _apply_ui_scale() -> void:
	if menu != null:
		menu.sync_scale_controls(ui_scale_mode, ui_scale_value)
	var window := get_window()
	if window == null:
		return
	var factor: float = 1.0
	if ui_scale_mode == UiScaleMode.MANUAL:
		factor = ui_scale_value
	window.content_scale_factor = clampf(factor, 0.5, 4.0)


func set_ui_scale(mode: int, value: float) -> void:
	ui_scale_mode = mode
	ui_scale_value = clampf(value, 0.5, 4.0)
	_apply_ui_scale()
	_save_settings()


func _load_settings() -> void:
	var data: Dictionary = FmgSettings.load_all()
	if data.is_empty():
		_apply_ui_scale()
		return
	ui_scale_mode = UiScaleMode.MANUAL if str(data.get("ui_scale_mode", "auto")) == "manual" else UiScaleMode.AUTO
	ui_scale_value = float(data.get("ui_scale", 1.0))
	if ui_theme != null:
		var color_html: String = str(data.get("theme_color", ""))
		if color_html.is_valid_html_color():
			ui_theme.set_theme(Color.html(color_html), float(data.get("transparency", ui_theme.transparency)))
		else:
			ui_theme.set_theme(ui_theme.theme_color, float(data.get("transparency", ui_theme.transparency)))
	if view != null:
		view.label_scale_mode = clampi(int(data.get("label_scale_mode", MapView.LabelScale.WITH_MAP)), 0, 1)
		view.label_declutter = bool(data.get("label_declutter", true))
		view.label_avoid_overlap = bool(data.get("label_avoid_overlap", true))
		view.label_min_px = float(data.get("label_min_px", 6.0))
		view.style_label_scale = float(data.get("style_label_scale", 1.0))
		view.scale_bar_on_map = bool(data.get("scale_bar_on_map", true))
		view.vignette_on_map = bool(data.get("vignette_on_map", true))
		view.distance_scale = float(data.get("distance_scale", 3.0))
		var layers: Dictionary = data.get("layers", {})
		for key: String in layers.keys():
			if key.begins_with("show_") and view.get(key) is bool:
				view.set(key, bool(layers[key]))
		view.queue_redraw()
	if menu != null:
		menu.refresh_from_sim()
	_apply_ui_scale()
	_settings_loaded = true


func _collect_settings() -> Dictionary:
	var layers: Dictionary = {}
	if view != null:
		for property: Dictionary in view.get_property_list():
			var prop_name: String = str(property.get("name", ""))
			if prop_name.begins_with("show_") and view.get(prop_name) is bool:
				layers[prop_name] = bool(view.get(prop_name))
	return {
		"ui_scale_mode": "manual" if ui_scale_mode == UiScaleMode.MANUAL else "auto",
		"ui_scale": ui_scale_value,
		"theme_color": (ui_theme.theme_color if ui_theme != null else Color.html(FmgSettings.DEFAULT_THEME_COLOR)).to_html(false),
		"transparency": (ui_theme.transparency if ui_theme != null else FmgSettings.DEFAULT_TRANSPARENCY),
		"label_scale_mode": (view.label_scale_mode if view != null else 0),
		"label_declutter": (view.label_declutter if view != null else true),
		"label_avoid_overlap": (view.label_avoid_overlap if view != null else true),
		"label_min_px": (view.label_min_px if view != null else 6.0),
		"style_label_scale": (view.style_label_scale if view != null else 1.0),
		"scale_bar_on_map": (view.scale_bar_on_map if view != null else true),
		"vignette_on_map": (view.vignette_on_map if view != null else true),
		"distance_scale": (view.distance_scale if view != null else 3.0),
		"layers": layers
	}


func _save_settings() -> void:
	if not _settings_loaded:
		return
	FmgSettings.save_all(_collect_settings())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_save_settings()


# ---------------------------------------------------------------------------
# UI construction

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	ui_theme = FmgUiTheme.new()
	menu = FmgMainMenu.new()
	menu.name = "MainMenu"
	menu.setup(sim, view, ui_theme)
	layer.add_child(menu)

	overviews = FmgOverviewDialogs.new()
	overviews.name = "Overviews"
	overviews.setup(sim, view, ui_theme)
	layer.add_child(overviews)

	menu.generate_requested.connect(_on_generate_requested)
	menu.save_requested.connect(_on_save_requested)
	menu.load_requested.connect(_on_load_requested)
	menu.export_requested.connect(_on_export_requested)
	menu.fit_requested.connect(func() -> void: camera.fit_to_map())
	menu.climate_apply_requested.connect(_on_climate_apply_requested)
	menu.ui_scale_requested.connect(set_ui_scale)
	menu.settings_changed.connect(_save_settings)
	menu.overview_requested.connect(func(kind: String) -> void: overviews.open(kind))
	menu.brush_option.item_selected.connect(func(_i: int) -> void:
		brush_active = menu.brush_option.get_selected_id() >= 0
		view.queue_redraw())

	camera.fit_to_map()


func _process(_delta: float) -> void:
	if menu == null or camera == null:
		return
	# tools claim the left mouse button; otherwise LMB drag pans like the original
	camera.lmb_pan_enabled = not (brush_active or _ruler_active())
	if view.visible and not _generating:
		var zoom_percent: int = int(round(camera.zoom.x * 100.0))
		var pointer: String = ""
		var world := get_global_mouse_position()
		if world.x >= 0.0 and world.y >= 0.0 and world.x <= sim.map_width and world.y <= sim.map_height:
			pointer = "%.0f, %.0f" % [world.x, world.y]
		menu.set_zoom_info(zoom_percent, pointer)
		if brush_active:
			view.brush_preview_visible = true
			view.brush_preview_pos = world
			view.brush_preview_radius = menu.brush_size.value
			view.queue_redraw()
		elif view.brush_preview_visible:
			view.brush_preview_visible = false
			view.queue_redraw()
