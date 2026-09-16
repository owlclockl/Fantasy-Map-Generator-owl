class_name FmgMainMenu
extends Control
## The main menu, replicated from the original Fantasy Map Generator: a
## draggable panel with a tab bar (Layers / Style / Options / Tools / About),
## a trigger button (►) when hidden, a bottom "sticked" button row, a command
## search (omnibar) and a loading overlay. All controls are styled by
## FmgUiTheme, exactly like the browser version's palette.

signal generate_requested
signal save_requested
signal load_requested
signal export_requested(kind: String) # png / svg / csv / geojson / height
signal fit_requested
signal climate_apply_requested
signal brush_regen_requested
signal overview_requested(kind: String) # burgs / states / rivers / markers

const MENU_WIDTH := 348.0
const TAB_IDS: Array = ["layers", "style", "options", "tools", "about"]
const TAB_TITLES: Dictionary = {
	"layers": "Слои", "style": "Стиль", "options": "Опции",
	"tools": "Инструменты", "about": "О программе"
}

# layer registry: id -> {label, key, prop} (prop is a MapView boolean)
const LAYERS: Array = [
	{"id": "heightmap", "label": "Высоты", "key": KEY_H, "prop": "show_heights"},
	{"id": "lakes", "label": "Озёра", "key": KEY_Q, "prop": "show_lakes"},
	{"id": "biomes", "label": "Биомы", "key": KEY_B, "prop": "show_biomes"},
	{"id": "cells", "label": "Ячейки", "key": KEY_E, "prop": "show_cell_borders"},
	{"id": "grid", "label": "Сетка", "key": KEY_SEMICOLON, "prop": "show_grid"},
	{"id": "coordinates", "label": "Координаты", "key": KEY_O, "prop": "show_coordinates"},
	{"id": "compass", "label": "Роза ветров", "key": KEY_W, "prop": "show_compass"},
	{"id": "rivers", "label": "Реки", "key": KEY_V, "prop": "show_rivers"},
	{"id": "relief", "label": "Иконки рельефа", "key": KEY_F, "prop": "show_relief_icons"},
	{"id": "relief_shading", "label": "Затенение высот", "key": 0, "prop": "show_relief"},
	{"id": "religions", "label": "Религии", "key": KEY_R, "prop": "show_religions"},
	{"id": "cultures", "label": "Культуры", "key": KEY_C, "prop": "show_cultures"},
	{"id": "states", "label": "Государства", "key": KEY_S, "prop": "show_politics"},
	{"id": "provinces", "label": "Провинции", "key": KEY_P, "prop": "show_provinces"},
	{"id": "zones", "label": "Зоны", "key": KEY_Z, "prop": "show_zones"},
	{"id": "borders", "label": "Границы", "key": KEY_D, "prop": "show_borders"},
	{"id": "routes", "label": "Дороги", "key": KEY_U, "prop": "show_routes"},
	{"id": "temperature", "label": "Температура", "key": KEY_T, "prop": "show_temperature"},
	{"id": "ice", "label": "Лёд", "key": KEY_J, "prop": "show_ice"},
	{"id": "goods", "label": "Ресурсы", "key": KEY_G, "prop": "show_goods"},
	{"id": "markets", "label": "Рынки", "key": 0, "prop": "show_markets"},
	{"id": "trade", "label": "Торговля", "key": KEY_QUOTELEFT, "prop": "show_trade"},
	{"id": "precipitation", "label": "Осадки", "key": KEY_A, "prop": "show_precipitation"},
	{"id": "population", "label": "Население", "key": KEY_N, "prop": "show_population"},
	{"id": "emblems", "label": "Гербы", "key": KEY_Y, "prop": "show_emblems"},
	{"id": "burgIcons", "label": "Иконки городов", "key": KEY_I, "prop": "show_burgs"},
	{"id": "labels", "label": "Подписи", "key": KEY_L, "prop": "show_labels"},
	{"id": "military", "label": "Армии", "key": KEY_M, "prop": "show_armies"},
	{"id": "markers", "label": "Маркеры", "key": KEY_K, "prop": "show_markers"},
	{"id": "journeys", "label": "Путешествия", "key": 0, "prop": "show_journeys"},
	{"id": "rulers", "label": "Линейка", "key": KEY_EQUAL, "prop": "show_rulers"},
	{"id": "scaleBar", "label": "Масштаб", "key": KEY_SLASH, "prop": "show_scale_bar"},
	{"id": "vignette", "label": "Виньетка", "key": KEY_BRACKETLEFT, "prop": "show_vignette"}
]

# layer presets from layers-presets.ts (mapped to this port's layer ids)
const PRESETS: Dictionary = {
	"political": ["borders", "burgIcons", "ice", "labels", "lakes", "rivers", "routes", "scaleBar", "states", "vignette"],
	"cultural": ["borders", "burgIcons", "cultures", "labels", "lakes", "rivers", "routes", "scaleBar", "vignette"],
	"religions": ["borders", "burgIcons", "labels", "lakes", "religions", "rivers", "routes", "scaleBar", "vignette"],
	"provinces": ["borders", "burgIcons", "labels", "lakes", "provinces", "rivers", "scaleBar", "vignette"],
	"biomes": ["biomes", "ice", "lakes", "rivers", "scaleBar", "vignette"],
	"heightmap": ["heightmap", "lakes", "rivers", "vignette"],
	"physical": ["coordinates", "heightmap", "ice", "lakes", "rivers", "scaleBar", "vignette"],
	"poi": ["borders", "burgIcons", "heightmap", "ice", "lakes", "markers", "rivers", "routes", "scaleBar", "vignette"],
	"goods": ["borders", "burgIcons", "cells", "goods", "lakes", "markets", "rivers", "routes", "scaleBar", "trade", "vignette"],
	"trade": ["borders", "burgIcons", "lakes", "rivers", "routes", "scaleBar", "states", "trade", "vignette"],
	"military": ["borders", "burgIcons", "labels", "lakes", "military", "rivers", "routes", "scaleBar", "states", "vignette"],
	"emblems": ["borders", "burgIcons", "emblems", "ice", "lakes", "rivers", "routes", "scaleBar", "states", "vignette"],
	"landmass": ["scaleBar"]
}
const PRESET_TITLES: Dictionary = {
	"political": "Политическая", "cultural": "Культурная", "religions": "Религии",
	"provinces": "Провинции", "biomes": "Биомы", "heightmap": "Высоты",
	"physical": "Физическая", "poi": "Достопримечательности", "goods": "Ресурсы",
	"trade": "Торговля", "military": "Военная", "emblems": "Гербы", "landmass": "Чистая суша"
}

var sim: FmgSim = null
var view: MapView = null
var ui_theme: FmgUiTheme = null

# menu controls
var menu: PanelContainer = null
var trigger_box: HBoxContainer = null
var trigger_button: Button = null
var new_map_button: Button = null
var tab_buttons: Dictionary = {}
var tab_contents: Dictionary = {}
var layer_buttons: Dictionary = {}
var preset_option: OptionButton = null
var status_label: Label = null
var zoom_label: Label = null
var progress_bar: ProgressBar = null
var loading_overlay: Control = null
var loading_stage_label: Label = null
var loading_progress: ProgressBar = null
var export_popup: PanelContainer = null
var export_button: Button = null
var omnibar: PanelContainer = null
var omnibar_edit: LineEdit = null
var omnibar_results: VBoxContainer = null

# options (map settings for the next generation)
var seed_edit: LineEdit = null
var template_option: OptionButton = null
var density_option: OptionButton = null
var cultures_spin: SpinBox = null
var cultures_set_option: OptionButton = null
var states_spin: SpinBox = null
var religions_spin: SpinBox = null
var provinces_ratio_spin: SpinBox = null
var burgs_check: CheckButton = null
var map_width_spin: SpinBox = null
var map_height_spin: SpinBox = null
var distance_scale_spin: SpinBox = null
var climate_equator_spin: SpinBox = null
var climate_north_spin: SpinBox = null
var climate_south_spin: SpinBox = null
var climate_precip_spin: SpinBox = null
var wind_spins: Array = []

# tools
var brush_option: OptionButton = null
var brush_size: HSlider = null
var ruler_check: CheckButton = null

const DENSITIES := [[1, "1 000"], [2, "2 000"], [3, "5 000"], [4, "10 000"], [5, "20 000"]]
const POINTS_BY_DENSITY := {1: 1000, 2: 2000, 3: 5000, 4: 10000, 5: 20000}

var _busy: bool = false


func setup(sim_ref: FmgSim, view_ref: MapView, theme_ref: FmgUiTheme) -> void:
	sim = sim_ref
	view = view_ref
	ui_theme = theme_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_trigger()
	_build_menu()
	_build_export_popup()
	_build_omnibar()
	_build_loading_overlay()
	_build_status_bar()
	# the monospace font and a compact size cascade to every child control
	for root: Control in [menu, trigger_box, export_popup, omnibar]:
		root.add_theme_font_override("font", FmgUiTheme.mono())
		root.add_theme_font_size_override("font_size", 13)
	select_tab("layers")
	ui_theme.changed.connect(_on_theme_changed)
	_on_theme_changed()
	apply_preset("political")


# ---------------------------------------------------------------------------
# Construction

func _build_trigger() -> void:
	trigger_box = HBoxContainer.new()
	trigger_box.position = Vector2(10, 10)
	trigger_box.add_theme_constant_override("separation", 6)
	trigger_box.visible = false # the menu itself starts visible
	add_child(trigger_box)
	trigger_button = Button.new()
	trigger_button.text = "►"
	trigger_button.tooltip_text = "Показать меню (Tab)"
	trigger_button.pressed.connect(show_menu)
	_style_tag(trigger_button, "button")
	trigger_box.add_child(trigger_button)
	new_map_button = Button.new()
	new_map_button.text = "Новая карта!"
	new_map_button.tooltip_text = "Сгенерировать новую карту (F2)"
	new_map_button.visible = false
	new_map_button.pressed.connect(func() -> void: generate_requested.emit())
	_style_tag(new_map_button, "accent")
	trigger_box.add_child(new_map_button)


func _build_menu() -> void:
	menu = PanelContainer.new()
	menu.position = Vector2(10, 10)
	menu.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_style_tag(menu, "panel")
	add_child(menu)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	menu.add_child(box)

	# drag bar
	var drag := PanelContainer.new()
	drag.custom_minimum_size = Vector2(0, 14)
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	drag.tooltip_text = "Перетащите, чтобы переместить меню"
	_style_tag(drag, "dragbar")
	var grip := Label.new()
	grip.text = "≡"
	grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grip.add_theme_font_override("font", FmgUiTheme.mono())
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag.add_child(grip)
	box.add_child(drag)
	drag.gui_input.connect(_on_drag_bar_input.bind(drag))

	# tab bar
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 1)
	box.add_child(tabs)
	var hide_button := Button.new()
	hide_button.text = "◄"
	hide_button.tooltip_text = "Скрыть меню (Tab или Esc)"
	hide_button.custom_minimum_size = Vector2(28, 0)
	hide_button.pressed.connect(hide_menu)
	_style_tag(hide_button, "tab")
	tabs.add_child(hide_button)
	for tab_id: String in TAB_IDS:
		var tab := Button.new()
		tab.text = str(TAB_TITLES[tab_id])
		tab.tooltip_text = "Открыть вкладку «%s»" % str(TAB_TITLES[tab_id])
		tab.toggle_mode = false
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 11)
		tab.clip_text = true
		_style_tag(tab, "tab")
		tab.pressed.connect(func() -> void: select_tab(tab_id))
		tabs.add_child(tab)
		tab_buttons[tab_id] = tab

	# tab contents
	for tab_id: String in TAB_IDS:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 560)
		scroll.visible = false
		_style_tag(scroll, "scroll")
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 4)
		scroll.add_child(content)
		box.add_child(scroll)
		tab_contents[tab_id] = scroll
		match tab_id:
			"layers":
				_build_layers_tab(content)
			"style":
				_build_style_tab(content)
			"options":
				_build_options_tab(content)
			"tools":
				_build_tools_tab(content)
			"about":
				_build_about_tab(content)

	# sticked buttons
	var sticked_sep := HSeparator.new()
	box.add_child(sticked_sep)
	var sticked := HBoxContainer.new()
	sticked.add_theme_constant_override("separation", 0)
	sticked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(sticked)
	var sticked_list: Array = [
		["new", "Новая карта"], ["export", "Экспорт"], ["save", "Сохранить"],
		["load", "Загрузить"], ["fit", "Обзор"], ["search", "Поиск"]
	]
	for entry: Array in sticked_list:
		var button := Button.new()
		button.text = str(entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = _sticked_tooltip(str(entry[0]))
		_style_tag(button, "sticked")
		button.pressed.connect(_on_sticked_pressed.bind(str(entry[0])))
		sticked.add_child(button)
		button.add_theme_font_size_override("font_size", 11)
		if str(entry[0]) == "export":
			export_button = button


func _sticked_tooltip(id: String) -> String:
	match id:
		"new":
			return "Сгенерировать новую карту (F2)"
		"export":
			return "Выбрать формат для экспорта карты или данных"
		"save":
			return "Сохранить карту в файл .map"
		"load":
			return "Загрузить карту из файла .map"
		"fit":
			return "Показать всю карту (0)"
		"search":
			return "Поиск по слоям и командам (Пробел)"
	return ""


func _build_layers_tab(content: VBoxContainer) -> void:
	_label(content, "Пресет слоёв:", "label", true)
	var preset_row := HBoxContainer.new()
	content.add_child(preset_row)
	preset_option = OptionButton.new()
	preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(preset_option, "select")
	for preset_id: String in PRESETS.keys():
		preset_option.add_item(str(PRESET_TITLES[preset_id]))
		preset_option.set_item_metadata(preset_option.item_count - 1, preset_id)
	preset_option.item_selected.connect(func(index: int) -> void:
		apply_preset(str(preset_option.get_item_metadata(index))))
	preset_row.add_child(preset_option)

	_label(content, "Отображаемые слои:", "label", true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	content.add_child(grid)
	for layer: Dictionary in LAYERS:
		var button := Button.new()
		button.text = str(layer["label"])
		button.toggle_mode = true
		button.tooltip_text = "Показать или скрыть слой «%s»" % str(layer["label"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tag(button, "layer")
		var prop: String = str(layer["prop"])
		button.button_pressed = bool(view.get(prop))
		button.toggled.connect(func(pressed: bool) -> void:
			view.set(prop, pressed)
			if prop == "show_rulers" and pressed:
				view.ruler_points = PackedVector2Array()
			view.queue_redraw()
			_refresh_layer_button(button, pressed))
		grid.add_child(button)
		layer_buttons[str(layer["id"])] = button
		_refresh_layer_button(button, button.button_pressed)
	_tip(content, "Клик — переключить слой. Буквенные клавиши тоже переключают слои.")
	_tip(content, "Пресет «Политическая» соответствует виду по умолчанию оригинала.")


func _build_style_tab(content: VBoxContainer) -> void:
	_label(content, "Цвета карты (применяются сразу):", "label", true)
	_color_row(content, "Океан", "style_ocean")
	_color_row(content, "Глубины", "style_ocean_deep")
	_color_row(content, "Суша", "style_land")
	_color_row(content, "Озёра", "style_lake")
	_color_row(content, "Реки", "style_river")
	_color_row(content, "Берег", "style_coast")
	_color_row(content, "Дороги", "style_road")
	_color_row(content, "Границы", "style_border")
	_label(content, "Линии и подписи:", "label", true)
	_spin_row(content, "Толщина берега", 0.2, 4.0, 0.1, view.style_coast_width, func(v: float) -> void:
		view.style_coast_width = v
		view.queue_redraw())
	_spin_row(content, "Толщина границ", 0.2, 6.0, 0.1, view.style_border_width, func(v: float) -> void:
		view.style_border_width = v
		view.queue_redraw())
	_spin_row(content, "Толщина дорог", 0.2, 6.0, 0.1, view.style_road_width, func(v: float) -> void:
		view.style_road_width = v
		view.queue_redraw())
	_spin_row(content, "Масштаб подписей", 0.25, 4.0, 0.05, view.style_label_scale, func(v: float) -> void:
		view.style_label_scale = v
		view.queue_redraw())
	_tip(content, "Базовые слои окрашиваются мгновенно — геометрия не пересчитывается.")


func _build_options_tab(content: VBoxContainer) -> void:
	_label(content, "Настройки карты (для новой карты):", "label", true)
	var size_row := HBoxContainer.new()
	content.add_child(size_row)
	_label(size_row, "Размер", "label")
	map_width_spin = _make_spin(240, 8192, 1, sim.map_width, 90.0)
	map_height_spin = _make_spin(135, 8192, 1, sim.map_height, 90.0)
	size_row.add_child(map_width_spin)
	_label(size_row, "×", "label")
	size_row.add_child(map_height_spin)

	var seed_row := HBoxContainer.new()
	content.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.text = sim.seed_value
	seed_edit.placeholder_text = "Сид"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.tooltip_text = "Сид карты: одно и то же число даёт одну и ту же карту (при равных прочих настройках)"
	_style_tag(seed_edit, "field")
	seed_row.add_child(seed_edit)
	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "Случайный сид"
	_style_tag(dice, "button")
	dice.pressed.connect(func() -> void:
		seed_edit.text = str(randi() % 1000000000))
	seed_row.add_child(dice)

	density_option = OptionButton.new()
	for d: Array in DENSITIES:
		density_option.add_item("%s ячеек" % str(d[1]), int(d[0]))
	density_option.select(3)
	density_option.tooltip_text = "Число точек графа; сильно влияет на скорость (10 000 — рекомендуемое)"
	_style_tag(density_option, "select")
	_option_row(content, "Детализация", density_option)

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
	template_option.tooltip_text = "Шаблон рельефа для новой карты"
	_style_tag(template_option, "select")
	_option_row(content, "Шаблон", template_option)

	cultures_spin = _make_spin(1, 32, 1, float(sim.cultures_limit))
	_spin_control_row(content, "Культур", cultures_spin)
	cultures_set_option = OptionButton.new()
	var set_index: int = 0
	for set_id: String in FmgCultures.CULTURE_SETS:
		var set_meta: Dictionary = FmgCultures.CULTURE_SETS[set_id]
		cultures_set_option.add_item(str(set_meta["nameRu"]), set_index)
		cultures_set_option.set_item_metadata(set_index, set_id)
		if set_id == sim.cultures_set:
			cultures_set_option.select(set_index)
		set_index += 1
	cultures_set_option.tooltip_text = "Набор культур: влияет на имена и размещение"
	_style_tag(cultures_set_option, "select")
	_option_row(content, "Набор культур", cultures_set_option)

	states_spin = _make_spin(0, 100, 1, float(sim.states_limit))
	_spin_control_row(content, "Государств", states_spin)
	religions_spin = _make_spin(0, 24, 1, float(sim.religions_limit))
	_spin_control_row(content, "Религий", religions_spin)
	provinces_ratio_spin = _make_spin(0, 100, 5, sim.provinces_ratio)
	provinces_ratio_spin.tooltip_text = "Доля городов государства, ставших центрами провинций"
	_spin_control_row(content, "Провинции %", provinces_ratio_spin)

	burgs_check = CheckButton.new()
	burgs_check.text = "Города: автоматически"
	burgs_check.button_pressed = sim.burgs_limit < 0
	_style_tag(burgs_check, "check")
	content.add_child(burgs_check)

	distance_scale_spin = _make_spin(0.01, 20.0, 0.1, view.distance_scale)
	distance_scale_spin.tooltip_text = "Масштаб расстояний: километров на пиксель карты (линейка и масштабная линейка)"
	_spin_control_row(content, "Км / пиксель", distance_scale_spin)
	distance_scale_spin.value_changed.connect(func(v: float) -> void:
		view.distance_scale = v
		view.queue_redraw())

	_label(content, "Интерфейс:", "label", true)
	var theme_row := HBoxContainer.new()
	content.add_child(theme_row)
	_label(theme_row, "Цвет темы", "label")
	var hue_slider := HSlider.new()
	hue_slider.min_value = 0.0
	hue_slider.max_value = 359.0
	hue_slider.step = 1.0
	hue_slider.value = 332.0
	hue_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hue_slider.tooltip_text = "Оттенок меню и диалогов"
	_style_tag(hue_slider, "slider")
	hue_slider.value_changed.connect(func(v: float) -> void: ui_theme.set_hue(v))
	theme_row.add_child(hue_slider)
	var color_picker := ColorPickerButton.new()
	color_picker.custom_minimum_size = Vector2(44, 22)
	color_picker.color = ui_theme.theme_color
	color_picker.color_changed.connect(func(color: Color) -> void: ui_theme.set_theme(color, ui_theme.transparency))
	theme_row.add_child(color_picker)
	_spin_row(content, "Прозрачность %", 0.0, 100.0, 1.0, ui_theme.transparency, func(v: float) -> void:
		ui_theme.set_theme(ui_theme.theme_color, v))

	_label(content, "Климат (пересчёт кнопкой ниже):", "label", true)
	climate_equator_spin = _climate_row(content, "Экватор °C", -10.0, 40.0, sim.climate_equator, func(v: float) -> void: sim.climate_equator = v)
	climate_north_spin = _climate_row(content, "Сев. полюс °C", -60.0, 15.0, sim.climate_north_pole, func(v: float) -> void: sim.climate_north_pole = v)
	climate_south_spin = _climate_row(content, "Юж. полюс °C", -60.0, 15.0, sim.climate_south_pole, func(v: float) -> void: sim.climate_south_pole = v)
	climate_precip_spin = _climate_row(content, "Осадки %", 0.0, 400.0, sim.climate_precipitation, func(v: float) -> void: sim.climate_precipitation = v)
	wind_spins = []
	var wind_names: Array = ["Ветер N пол.", "Ветер N ум.", "Ветер троп. N", "Ветер троп. S", "Ветер S ум.", "Ветер S пол."]
	for i: int in 6:
		var wind_spin := _make_spin(0.0, 360.0, 5.0, float(sim.climate_winds[i]) if i < sim.climate_winds.size() else 0.0)
		wind_spin.tooltip_text = "Направление преобладающего ветра пояса, в градусах"
		_spin_control_row(content, str(wind_names[i]), wind_spin)
		wind_spin.value_changed.connect(_on_wind_changed.bind(i))
		wind_spins.append(wind_spin)
	var climate_btn := Button.new()
	climate_btn.text = "Применить климат"
	climate_btn.tooltip_text = "Пересчитать температуру, осадки и всё ниже по конвейеру"
	_style_tag(climate_btn, "accent")
	climate_btn.pressed.connect(func() -> void: climate_apply_requested.emit())
	content.add_child(climate_btn)

	var generate := Button.new()
	generate.text = "Сгенерировать карту"
	generate.custom_minimum_size = Vector2(0, 40)
	generate.tooltip_text = "Создать новую карту с текущими настройками (F2)"
	_style_tag(generate, "accent")
	generate.pressed.connect(func() -> void: generate_requested.emit())
	content.add_child(generate)


func _build_tools_tab(content: VBoxContainer) -> void:
	_label(content, "Редактирование:", "sep", true)
	brush_option = OptionButton.new()
	brush_option.add_item("Кисть: выключена", -1)
	brush_option.add_item("Поднять рельеф", 0)
	brush_option.add_item("Опустить рельеф", 1)
	brush_option.add_item("Сгладить", 2)
	brush_option.select(0)
	brush_option.tooltip_text = "Кисть высот: применяется к сетке, затем весь конвейер пересчитывается"
	_style_tag(brush_option, "select")
	_option_row(content, "Кисть", brush_option)
	brush_size = HSlider.new()
	brush_size.min_value = 10.0
	brush_size.max_value = 150.0
	brush_size.value = 45.0
	brush_size.tooltip_text = "Радиус кисти в пикселях"
	_style_tag(brush_size, "slider")
	var brush_row := HBoxContainer.new()
	content.add_child(brush_row)
	_label(brush_row, "Размер", "label")
	brush_row.add_child(brush_size)

	ruler_check = CheckButton.new()
	ruler_check.text = "Линейка активна"
	ruler_check.tooltip_text = "Клик по карте — добавить точку; ПКМ или Esc — сбросить. Показывает расстояние"
	_style_tag(ruler_check, "check")
	ruler_check.toggled.connect(func(pressed: bool) -> void:
		view.show_rulers = pressed
		if pressed:
			view.ruler_points = PackedVector2Array()
		view.queue_redraw())
	content.add_child(ruler_check)

	_label(content, "Обзоры:", "sep", true)
	var overview_grid := GridContainer.new()
	overview_grid.columns = 3
	overview_grid.add_theme_constant_override("h_separation", 4)
	overview_grid.add_theme_constant_override("v_separation", 4)
	content.add_child(overview_grid)
	for entry: Array in [["burgs", "Города"], ["states", "Государства"], ["rivers", "Реки"], ["markers", "Маркеры"], ["markets", "Рынки"], ["diplomacy", "Дипломатия"]]:
		var button := Button.new()
		button.text = str(entry[1])
		button.tooltip_text = "Открыть таблицу «%s»" % str(entry[1])
		_style_tag(button, "button")
		button.pressed.connect(func() -> void: overview_requested.emit(str(entry[0])))
		overview_grid.add_child(button)

	_label(content, "Экспорт:", "sep", true)
	var export_grid := GridContainer.new()
	export_grid.columns = 3
	export_grid.add_theme_constant_override("h_separation", 4)
	export_grid.add_theme_constant_override("v_separation", 4)
	content.add_child(export_grid)
	for entry: Array in [["png", "PNG"], ["svg", "SVG"], ["csv", "CSV"], ["geojson", "GeoJSON"], ["height", "Высоты"]]:
		var button := Button.new()
		button.text = str(entry[1])
		button.tooltip_text = "Экспортировать карту или данные: %s" % str(entry[1])
		_style_tag(button, "button")
		button.pressed.connect(func() -> void: export_requested.emit(str(entry[0])))
		export_grid.add_child(button)

	_label(content, "Пересчёт:", "sep", true)
	var regen := Button.new()
	regen.text = "Пересчитать карту с тем же сидом"
	regen.tooltip_text = "Повторить генерацию с текущими настройками (например, после смены шаблона)"
	_style_tag(regen, "button")
	regen.pressed.connect(func() -> void: generate_requested.emit())
	content.add_child(regen)


func _build_about_tab(content: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "FANTASY MAP GENERATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_font_override("font", FmgUiTheme.mono())
	title.add_theme_color_override("font_color", ui_theme.dark_solid if ui_theme != null else Color("#5e4452"))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Порт для Godot 4 · версия 1.0"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_font_override("font", FmgUiTheme.mono())
	_style_tag(subtitle, "tip")
	content.add_child(subtitle)
	var about := Label.new()
	about.text = "Процедурный генератор фэнтезийных карт: рельеф, реки, биомы, климат, культуры, государства, провинции, религии, города, дороги, рынки и торговля, армии, дипломатия, маркеры, зоны и геральдика.\n\nЭто свободный порт генератора Azgaar на GDScript (Godot 4). Алгоритмы и данные перенесены из оригинального проекта; интерфейс повторяет меню оригинала.\n\nОригинал: github.com/Azgaar/Fantasy-Map-Generator (Azgaar, лицензия MIT)."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(MENU_WIDTH - 34.0, 0)
	about.add_theme_font_override("font", FmgUiTheme.mono())
	about.add_theme_color_override("font_color", Color("#31272c"))
	content.add_child(about)
	_label(content, "Горячие клавиши:", "sep", true)
	var hotkeys := Label.new()
	hotkeys.text = "Tab — показать/скрыть меню\nF2 — новая карта\n0 — показать всю карту\nПробел — поиск\nEsc — закрыть диалоги\nКолесо — зум; перетаскивание (ЛКМ/ПКМ) — панорама\nB, S, C, R, P, T, N и другие буквы — переключение слоёв"
	hotkeys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hotkeys.custom_minimum_size = Vector2(MENU_WIDTH - 34.0, 0)
	hotkeys.add_theme_font_override("font", FmgUiTheme.mono())
	_style_tag(hotkeys, "tip")
	content.add_child(hotkeys)


# ---------------------------------------------------------------------------
# Small builders

func _style_tag(node: Control, kind: String) -> void:
	node.set_meta("fmg", kind)


func _label(parent: Control, text: String, kind: String = "label", bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	_style_tag(label, kind)
	if bold:
		label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)
	return label


func _tip(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(MENU_WIDTH - 34.0, 0)
	label.add_theme_font_size_override("font_size", 11)
	_style_tag(label, "tip")
	parent.add_child(label)


func _make_spin(min_value: float, max_value: float, step: float, value: float, width: float = 0.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if width > 0.0:
		spin.custom_minimum_size = Vector2(width, 0)
	_style_tag(spin, "field")
	return spin


func _spin_row(parent: Control, label_text: String, min_value: float, max_value: float, step: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label_text, "label")
	var spin := _make_spin(min_value, max_value, step, value)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	spin.value_changed.connect(func(v: float) -> void: on_change.call(v))


func _spin_control_row(parent: Control, label_text: String, spin: SpinBox) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label_text, "label")
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)


func _option_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label_text, "label")
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _color_row(parent: Control, label_text: String, property: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label_text, "label")
	var picker := ColorPickerButton.new()
	picker.color = view.get(property)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size = Vector2(0, 22)
	picker.color_changed.connect(func(color: Color) -> void:
		view.set(property, color)
		view.queue_redraw())
	row.add_child(picker)


func _climate_row(parent: Control, label_text: String, min_value: float, max_value: float, initial: float, on_change: Callable) -> SpinBox:
	var spin := _make_spin(min_value, max_value, 0.5, initial)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_control_row(parent, label_text, spin)
	spin.value_changed.connect(func(v: float) -> void: on_change.call(v))
	return spin


func _build_export_popup() -> void:
	export_popup = PanelContainer.new()
	export_popup.visible = false
	_style_tag(export_popup, "panel")
	add_child(export_popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	export_popup.add_child(box)
	for entry: Array in [["png", "Изображение PNG"], ["svg", "Векторная карта SVG"], ["csv", "Данные ячеек CSV"], ["geojson", "Геоданные GeoJSON"], ["height", "Высотная карта PNG"]]:
		var button := Button.new()
		button.text = str(entry[1])
		_style_tag(button, "button")
		button.pressed.connect(func() -> void:
			export_popup.visible = false
			export_requested.emit(str(entry[0])))
		box.add_child(button)


func _build_omnibar() -> void:
	omnibar = PanelContainer.new()
	omnibar.visible = false
	omnibar.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_style_tag(omnibar, "panel")
	add_child(omnibar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	omnibar.add_child(box)
	omnibar_edit = LineEdit.new()
	omnibar_edit.placeholder_text = "Слои, пресеты, инструменты…"
	_style_tag(omnibar_edit, "field")
	omnibar_edit.text_changed.connect(_refresh_omnibar)
	box.add_child(omnibar_edit)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_tag(scroll, "scroll")
	box.add_child(scroll)
	omnibar_results = VBoxContainer.new()
	omnibar_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	omnibar_results.add_theme_constant_override("separation", 1)
	scroll.add_child(omnibar_results)


func _build_loading_overlay() -> void:
	loading_overlay = Control.new()
	loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_overlay.visible = false
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(loading_overlay)
	var bg := ColorRect.new()
	bg.color = Color("#466eab")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(bg)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", 10)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(center)
	var rose := Control.new()
	rose.custom_minimum_size = Vector2(160, 160)
	rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(rose)
	var title := Label.new()
	title.text = "Fantasy Map Generator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_font_override("font", FmgUiTheme.mono())
	title.add_theme_color_override("font_color", Color("#fff5da"))
	title.add_theme_color_override("font_shadow_color", Color("#4c3a35"))
	center.add_child(title)
	loading_stage_label = Label.new()
	loading_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_stage_label.add_theme_font_size_override("font_size", 17)
	loading_stage_label.add_theme_font_override("font", FmgUiTheme.mono())
	loading_stage_label.add_theme_color_override("font_color", Color("#fff5da"))
	loading_stage_label.text = "Генерация…"
	center.add_child(loading_stage_label)
	loading_progress = ProgressBar.new()
	loading_progress.min_value = 0.0
	loading_progress.max_value = 1.0
	loading_progress.show_percentage = false
	loading_progress.custom_minimum_size = Vector2(320, 8)
	center.add_child(loading_progress)
	rose.draw.connect(_draw_loading_rose.bind(rose))
	rose.set_meta("start_ms", Time.get_ticks_msec())


## The original's loading screen: a slowly spinning compass rose.
func _draw_loading_rose(rose: Control) -> void:
	var center := rose.size / 2.0
	var rotation_angle := TAU * float((Time.get_ticks_msec() - int(rose.get_meta("start_ms", 0))) % 20000) / 20000.0
	var dark := Color("#3d3a50")
	var light := Color("#fff5da")
	var radius := minf(center.x, center.y) * 0.92
	rose.draw_arc(center, radius, 0.0, TAU, 56, Color("#2f3d55"), 2.0, true)
	for k: int in 16:
		var major: bool = k % 2 == 0
		var angle: float = rotation_angle - PI / 2.0 + TAU * float(k) / 16.0
		var length: float = radius * (0.95 if major else 0.5)
		var half_width: float = TAU / 16.0 * 0.55
		var tip := center + Vector2(cos(angle), sin(angle)) * length
		var left := center + Vector2(cos(angle - half_width), sin(angle - half_width)) * radius * 0.1
		var right := center + Vector2(cos(angle + half_width), sin(angle + half_width)) * radius * 0.1
		var tone := dark if k % 4 == 0 else light
		if major:
			rose.draw_colored_polygon(PackedVector2Array([center, tip, left]), tone)
			rose.draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(tone, 0.55))
		else:
			rose.draw_colored_polygon(PackedVector2Array([center, tip, left]), Color(tone, 0.7))
			rose.draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(tone, 0.35))
	rose.draw_circle(center, radius * 0.07, dark)
	rose.draw_circle(center, radius * 0.035, light)


func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_tag(bar, "dragbar")
	add_child(bar)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	status_label = Label.new()
	status_label.text = "Готов к генерации"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_override("font", FmgUiTheme.mono())
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("#e8e4da"))
	status_label.clip_text = true
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status_label)
	zoom_label = Label.new()
	zoom_label.text = ""
	zoom_label.add_theme_font_override("font", FmgUiTheme.mono())
	zoom_label.add_theme_font_size_override("font_size", 12)
	zoom_label.add_theme_color_override("font_color", Color("#c9c2b4"))
	zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(zoom_label)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 6)
	progress_bar.visible = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(progress_bar)


# ---------------------------------------------------------------------------
# Behavior

func _process(_delta: float) -> void:
	if loading_overlay != null and loading_overlay.visible:
		for child in loading_overlay.get_children():
			if child is VBoxContainer:
				(child as VBoxContainer).get_child(0).queue_redraw()


func show_menu() -> void:
	menu.visible = true
	trigger_box.visible = false


func hide_menu() -> void:
	menu.visible = false
	export_popup.visible = false
	trigger_box.position = Vector2(10, 10)
	trigger_box.visible = true
	new_map_button.visible = true


func is_menu_visible() -> bool:
	return menu != null and menu.visible


func toggle_menu() -> void:
	if is_menu_visible():
		hide_menu()
	else:
		show_menu()


func select_tab(tab_id: String) -> void:
	for id: String in TAB_IDS:
		(tab_contents[id] as ScrollContainer).visible = id == tab_id
		_style_tag(tab_buttons[id], "tab_active" if id == tab_id else "tab")
	ui_theme.apply_style(menu)


func _on_drag_bar_input(event: InputEvent, _bar: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# start drag
			set_meta("drag_offset", menu.position - (event as InputEventMouseButton).global_position)
		else:
			set_meta("drag_offset", null)
	elif event is InputEventMouseMotion and get_meta("drag_offset", null) != null:
		var offset: Vector2 = get_meta("drag_offset")
		var size: Vector2 = get_viewport_rect().size
		var target: Vector2 = (event as InputEventMouseMotion).global_position + offset
		menu.position = Vector2(
			clampf(target.x, 0.0, maxf(size.x - 60.0, 0.0)),
			clampf(target.y, 0.0, maxf(size.y - 60.0, 0.0)))


func _on_sticked_pressed(id: String) -> void:
	match id:
		"new":
			generate_requested.emit()
		"export":
			if export_button != null:
				export_popup.position = export_button.global_position + Vector2(0, 24)
				export_popup.visible = not export_popup.visible
		"save":
			save_requested.emit()
		"load":
			load_requested.emit()
		"fit":
			fit_requested.emit()
		"search":
			open_omnibar()


func _find_buttons(root: Node) -> Array:
	var result: Array = []
	if root is Button:
		result.append(root)
	for child in root.get_children():
		result.append_array(_find_buttons(child))
	return result


func open_omnibar() -> void:
	omnibar.position = menu.position
	omnibar_edit.text = ""
	_refresh_omnibar("")
	omnibar.visible = true
	omnibar_edit.grab_focus()


func close_popups() -> void:
	export_popup.visible = false
	omnibar.visible = false


# ---------------------------------------------------------------------------
# Layers

func _refresh_layer_button(button: Button, pressed: bool) -> void:
	_style_tag(button, "layer_active" if pressed else "layer")
	if ui_theme != null:
		ui_theme.apply_style(button)


func apply_preset(preset_id: String) -> void:
	if not PRESETS.has(preset_id):
		return
	var active: Array = PRESETS[preset_id]
	for layer: Dictionary in LAYERS:
		var id: String = str(layer["id"])
		var prop: String = str(layer["prop"])
		var pressed: bool = active.has(id)
		view.set(prop, pressed)
		if layer_buttons.has(id):
			var button: Button = layer_buttons[id]
			button.set_pressed_no_signal(pressed)
			_refresh_layer_button(button, pressed)
	view.queue_redraw()


func set_layer(id: String, pressed: bool) -> void:
	for layer: Dictionary in LAYERS:
		if str(layer["id"]) != id:
			continue
		var prop: String = str(layer["prop"])
		view.set(prop, pressed)
		if layer_buttons.has(id):
			var button: Button = layer_buttons[id]
			button.set_pressed_no_signal(pressed)
			_refresh_layer_button(button, pressed)
		view.queue_redraw()
		return


## Keyboard layer toggles: letters switch layers like in the original.
func handle_layer_key(keycode: int) -> bool:
	if _text_input_focused():
		return false
	for layer: Dictionary in LAYERS:
		if int(layer["key"]) == keycode:
			set_layer(str(layer["id"]), not bool(view.get(str(layer["prop"]))))
			return true
	return false


func _text_input_focused() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox or focus is TextEdit or focus is CodeEdit


# ---------------------------------------------------------------------------
# Omnibar

func _refresh_omnibar(query: String) -> void:
	for child in omnibar_results.get_children():
		child.queue_free()
	var needle: String = query.strip_edges().to_lower()
	var actions: Array = _collect_actions()
	var shown: int = 0
	for action: Dictionary in actions:
		if shown >= 12:
			break
		var title: String = str(action["title"])
		if not needle.is_empty() and not title.to_lower().contains(needle):
			continue
		var button := Button.new()
		button.text = title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_tag(button, "button")
		var action_ref: Dictionary = action
		button.pressed.connect(func() -> void:
			omnibar.visible = false
			_run_action(action_ref))
		omnibar_results.add_child(button)
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "Ничего не найдено"
		_style_tag(empty, "tip")
		omnibar_results.add_child(empty)


func _collect_actions() -> Array:
	var actions: Array = []
	actions.append({"title": "Новая карта (F2)", "run": func() -> void: generate_requested.emit()})
	actions.append({"title": "Показать всю карту (0)", "run": func() -> void: fit_requested.emit()})
	actions.append({"title": "Сохранить карту", "run": func() -> void: save_requested.emit()})
	actions.append({"title": "Загрузить карту", "run": func() -> void: load_requested.emit()})
	actions.append({"title": "Экспорт PNG", "run": func() -> void: export_requested.emit("png")})
	actions.append({"title": "Экспорт SVG", "run": func() -> void: export_requested.emit("svg")})
	actions.append({"title": "Экспорт CSV", "run": func() -> void: export_requested.emit("csv")})
	actions.append({"title": "Экспорт GeoJSON", "run": func() -> void: export_requested.emit("geojson")})
	actions.append({"title": "Экспорт высотной карты", "run": func() -> void: export_requested.emit("height")})
	actions.append({"title": "Пересчитать климат", "run": func() -> void: climate_apply_requested.emit()})
	for preset_id: String in PRESETS.keys():
		var title: String = "Пресет: %s" % str(PRESET_TITLES[preset_id])
		var preset_ref: String = preset_id
		var runner := func() -> void:
			apply_preset(preset_ref)
			if preset_option != null:
				for i: int in preset_option.item_count:
					if str(preset_option.get_item_metadata(i)) == preset_ref:
						preset_option.select(i)
						break
		actions.append({"title": title, "run": runner})
	for layer: Dictionary in LAYERS:
		var id: String = str(layer["id"])
		var prop: String = str(layer["prop"])
		var state: String = "вкл" if not bool(view.get(prop)) else "выкл"
		actions.append({"title": "Слой: %s — %s" % [str(layer["label"]), state], "run": func() -> void: set_layer(id, not bool(view.get(prop)))})
	actions.append({"title": "Обзор: Города", "run": func() -> void: overview_requested.emit("burgs")})
	actions.append({"title": "Обзор: Государства", "run": func() -> void: overview_requested.emit("states")})
	actions.append({"title": "Обзор: Реки", "run": func() -> void: overview_requested.emit("rivers")})
	return actions


func _run_action(action: Dictionary) -> void:
	(action["run"] as Callable).call()


# ---------------------------------------------------------------------------
# State sync

func _on_theme_changed() -> void:
	if ui_theme == null or menu == null:
		return
	for tab_id: String in TAB_IDS:
		if tab_buttons.has(tab_id):
			var is_active: bool = (tab_contents[tab_id] as ScrollContainer).visible
			_style_tag(tab_buttons[tab_id], "tab_active" if is_active else "tab")
	ui_theme.apply_style(self)


func set_busy(busy: bool) -> void:
	_busy = busy
	_set_node_busy(self, busy, [loading_overlay])


func _set_node_busy(node: Node, busy: bool, skip: Array = []) -> void:
	if node in skip:
		return
	if node.get_meta("keep_enabled", false):
		pass
	elif node is BaseButton:
		(node as BaseButton).disabled = busy
	elif node is LineEdit:
		(node as LineEdit).editable = not busy
	elif node is SpinBox:
		(node as SpinBox).editable = not busy
	elif node is Slider:
		(node as Slider).editable = not busy
	for child in node.get_children():
		_set_node_busy(child, busy, skip)


func show_loading(visible: bool) -> void:
	loading_overlay.visible = visible
	if visible:
		loading_stage_label.text = "Генерация…"
		loading_progress.value = 0.0


func set_loading_stage(text: String, progress: float) -> void:
	if loading_overlay.visible:
		loading_stage_label.text = text
		loading_progress.value = clampf(progress, 0.0, 1.0)


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func set_zoom_info(zoom_percent: int, pointer: String) -> void:
	if zoom_label != null:
		zoom_label.text = "Масштаб: %d%% · %s" % [zoom_percent, pointer]


func show_progress(visible: bool) -> void:
	if progress_bar != null:
		progress_bar.visible = visible


func set_progress(value: float) -> void:
	if progress_bar != null:
		progress_bar.value = clampf(value, 0.0, 1.0)


## Push current UI values into the simulation (before generation).
func apply_generation_options() -> void:
	sim.seed_value = seed_edit.text.strip_edges()
	if sim.seed_value.is_empty():
		sim.seed_value = str(randi() % 1000000000)
		seed_edit.text = sim.seed_value
	var template_id: Variant = template_option.get_item_metadata(template_option.selected)
	sim.template_id = str(template_id) if template_id != null else "random"
	sim.cells_desired = POINTS_BY_DENSITY[density_option.get_selected_id()]
	sim.map_width = float(map_width_spin.value)
	sim.map_height = float(map_height_spin.value)
	sim.cultures_limit = int(cultures_spin.value)
	sim.cultures_set = str(cultures_set_option.get_selected_metadata())
	sim.states_limit = int(states_spin.value)
	sim.religions_limit = int(religions_spin.value)
	sim.provinces_ratio = float(provinces_ratio_spin.value)
	sim.burgs_limit = -1 if burgs_check.button_pressed else 1000
	sim.poles_cache = {}
	view.distance_scale = float(distance_scale_spin.value)


## Refresh controls from the simulation (after load).
func refresh_from_sim() -> void:
	if seed_edit != null:
		seed_edit.text = sim.seed_value
	if template_option != null:
		for i: int in template_option.item_count:
			if str(template_option.get_item_metadata(i)) == sim.template_id:
				template_option.select(i)
				break
	if density_option != null:
		for i: int in density_option.item_count:
			var density_id: int = int(density_option.get_item_id(i))
			if POINTS_BY_DENSITY.has(density_id) and POINTS_BY_DENSITY[density_id] == sim.cells_desired:
				density_option.select(i)
				break
	if map_width_spin != null:
		map_width_spin.set_value_no_signal(sim.map_width)
	if map_height_spin != null:
		map_height_spin.set_value_no_signal(sim.map_height)
	if cultures_spin != null:
		cultures_spin.set_value_no_signal(sim.cultures_limit)
	if cultures_set_option != null:
		for i: int in cultures_set_option.item_count:
			if str(cultures_set_option.get_item_metadata(i)) == sim.cultures_set:
				cultures_set_option.select(i)
				break
	if states_spin != null:
		states_spin.set_value_no_signal(sim.states_limit)
	if religions_spin != null:
		religions_spin.set_value_no_signal(sim.religions_limit)
	if provinces_ratio_spin != null:
		provinces_ratio_spin.set_value_no_signal(sim.provinces_ratio)
	if burgs_check != null:
		burgs_check.set_pressed_no_signal(sim.burgs_limit < 0)
	if climate_equator_spin != null:
		climate_equator_spin.set_value_no_signal(sim.climate_equator)
		climate_north_spin.set_value_no_signal(sim.climate_north_pole)
		climate_south_spin.set_value_no_signal(sim.climate_south_pole)
		climate_precip_spin.set_value_no_signal(sim.climate_precipitation)
		for i: int in mini(wind_spins.size(), sim.climate_winds.size()):
			(wind_spins[i] as SpinBox).set_value_no_signal(float(sim.climate_winds[i]))
	for layer: Dictionary in LAYERS:
		var id: String = str(layer["id"])
		if layer_buttons.has(id):
			var pressed: bool = bool(view.get(str(layer["prop"])))
			var button: Button = layer_buttons[id]
			button.set_pressed_no_signal(pressed)
			_refresh_layer_button(button, pressed)


func _on_wind_changed(value: float, index: int) -> void:
	if index >= 0 and index < sim.climate_winds.size():
		sim.climate_winds[index] = value
