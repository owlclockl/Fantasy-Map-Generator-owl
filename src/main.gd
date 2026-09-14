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
var states_spin: SpinBox = null
var burgs_check: CheckButton = null
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
	# save + load roundtrip
	var err: Error = sim.save_map("/tmp/fmg_smoke_test.map")
	print("[smoke] save_map -> ", error_string(err))
	err = sim.load_map("/tmp/fmg_smoke_test.map")
	print("[smoke] load_map -> ", error_string(err))
	view.rebuild_cache()
	print("[smoke] OK")
	get_tree().quit(0)


func _collect_state_names() -> String:
	var names: Array = []
	for s: Dictionary in sim.pack.states:
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
		var stage_fn: Callable = stage[1]
		stage_fn.call()

	sim.generation_time_ms = Time.get_ticks_msec() - t_start
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
	_generating = true
	generate_button.disabled = true
	progress_bar.show()
	var stages: Array = sim.pipeline_from_heightmap()
	var total: int = stages.size()
	for i: int in stages.size():
		var stage: Array = stages[i]
		status_label.text = "Пересчёт: %s…" % stage[0]
		progress_bar.value = float(i) / float(total)
		await get_tree().process_frame
		var stage_fn: Callable = stage[1]
		stage_fn.call()
	progress_bar.hide()
	view.rebuild_cache()
	status_label.text = sim.get_stats_text()
	_generating = false
	generate_button.disabled = false


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
		var motion := event as InputEventMouseMotion
		if brush_active:
			brush_world_pos = get_global_mouse_position()
			view.queue_redraw()


func _apply_brush(screen_pos: Vector2) -> void:
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
	clone.rebuild_cache()
	clone.scale = Vector2(scale_factor, scale_factor)
	sv.add_child(clone)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = sv.get_texture().get_image()
	img.save_png(path)
	status_label.text = "Экспортировано: %s" % path
	sv.queue_free()


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

	states_spin = SpinBox.new()
	states_spin.min_value = 1
	states_spin.max_value = 60
	states_spin.value = sim.states_limit
	vbox.add_child(_make_row("Государств", states_spin))

	burgs_check = CheckButton.new()
	burgs_check.text = "Города: авто"
	burgs_check.button_pressed = true
	vbox.add_child(burgs_check)

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
	io_row.add_child(save_btn)
	io_row.add_child(load_btn)
	io_row.add_child(png_btn)
	vbox.add_child(io_row)

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
		view.queue_redraw()
	)
