class_name FmgMainMenu
extends Control
## Apple-style "Liquid Glass" (Glassmorphism) main menu for Fantasy Map Generator:
## Translucent frosted glass panel with specular rim highlight, smooth rounded squircles,
## Apple segmented tab bar (Layers / Style / Options / Tools / About),
## Dynamic Island floating trigger pill, bottom glass action dock,
## Spotlight-style command palette, and responsive status bar.

signal generate_requested
signal save_requested
signal load_requested
signal export_requested(kind: String) # png / svg / csv / geojson / height
signal fit_requested
signal climate_apply_requested
signal brush_regen_requested
signal overview_requested(kind: String) # burgs / states / rivers / markers
signal ui_scale_requested(mode: int, value: float) # 0 = auto, 1 = manual
signal settings_changed() # persist the current interface/map preferences

const MENU_WIDTH := 376.0
const TAB_IDS: Array = ["layers", "style", "options", "tools", "about"]
const TAB_TITLES: Dictionary = {
	"layers": "Слои", "style": "Стиль", "options": "Опции",
	"tools": "Инструменты", "about": "Инфо"
}
const TAB_ICONS: Dictionary = {
	"layers": "🗺️", "style": "🎨", "options": "⚙️",
	"tools": "🛠️", "about": "ℹ️"
}

# 33 layer registry
const LAYERS: Array = [
	{"id": "heightmap", "label": "Высоты", "key": KEY_H, "prop": "show_heights"},
	{"id": "relief_shading", "label": "Затенение высот", "key": 0, "prop": "show_relief"},
	{"id": "relief", "label": "Иконки рельефа", "key": KEY_F, "prop": "show_relief_icons"},
	{"id": "lakes", "label": "Озёра", "key": KEY_Q, "prop": "show_lakes"},
	{"id": "rivers", "label": "Реки", "key": KEY_V, "prop": "show_rivers"},
	{"id": "biomes", "label": "Биомы", "key": KEY_B, "prop": "show_biomes"},
	{"id": "ice", "label": "Лёд", "key": KEY_J, "prop": "show_ice"},
	{"id": "states", "label": "Государства", "key": KEY_S, "prop": "show_politics"},
	{"id": "provinces", "label": "Провинции", "key": KEY_P, "prop": "show_provinces"},
	{"id": "borders", "label": "Границы", "key": KEY_D, "prop": "show_borders"},
	{"id": "burgIcons", "label": "Города", "key": KEY_I, "prop": "show_burgs"},
	{"id": "cultures", "label": "Культуры", "key": KEY_C, "prop": "show_cultures"},
	{"id": "religions", "label": "Религии", "key": KEY_R, "prop": "show_religions"},
	{"id": "population", "label": "Население", "key": KEY_N, "prop": "show_population"},
	{"id": "compass", "label": "Роза ветров", "key": KEY_W, "prop": "show_compass"},
	{"id": "grid", "label": "Сетка", "key": KEY_SEMICOLON, "prop": "show_grid"},
	{"id": "coordinates", "label": "Координаты", "key": KEY_O, "prop": "show_coordinates"},
	{"id": "scaleBar", "label": "Масштаб", "key": KEY_SLASH, "prop": "show_scale_bar"},
	{"id": "rulers", "label": "Линейка", "key": KEY_EQUAL, "prop": "show_rulers"},
	{"id": "routes", "label": "Дороги", "key": KEY_U, "prop": "show_routes"},
	{"id": "journeys", "label": "Путешествия", "key": 0, "prop": "show_journeys"},
	{"id": "goods", "label": "Ресурсы", "key": KEY_G, "prop": "show_goods"},
	{"id": "markets", "label": "Рынки", "key": 0, "prop": "show_markets"},
	{"id": "trade", "label": "Торговля", "key": KEY_QUOTELEFT, "prop": "show_trade"},
	{"id": "military", "label": "Армии", "key": KEY_M, "prop": "show_armies"},
	{"id": "emblems", "label": "Гербы", "key": KEY_Y, "prop": "show_emblems"},
	{"id": "markers", "label": "Маркеры", "key": KEY_K, "prop": "show_markers"},
	{"id": "zones", "label": "Зоны", "key": KEY_Z, "prop": "show_zones"},
	{"id": "labels", "label": "Подписи", "key": KEY_L, "prop": "show_labels"},
	{"id": "legend", "label": "Легенда карты", "key": KEY_BACKSLASH, "prop": "show_legend"},
	{"id": "vignette", "label": "Виньетка", "key": KEY_BRACKETLEFT, "prop": "show_vignette"},
	{"id": "cells", "label": "Ячейки", "key": KEY_E, "prop": "show_cell_borders"},
	{"id": "temperature", "label": "Температура", "key": KEY_T, "prop": "show_temperature"},
	{"id": "precipitation", "label": "Осадки", "key": KEY_A, "prop": "show_precipitation"}
]

const LAYER_CATEGORIES: Array = [
	{
		"title": "🏔️ Рельеф и природа",
		"ids": ["heightmap", "relief_shading", "relief", "lakes", "rivers", "biomes", "ice"]
	},
	{
		"title": "👑 Государства и общество",
		"ids": ["states", "provinces", "borders", "burgIcons", "cultures", "religions", "population"]
	},
	{
		"title": "🧭 Навигация и разметка",
		"ids": ["compass", "grid", "coordinates", "scaleBar", "rulers", "legend", "routes", "journeys"]
	},
	{
		"title": "⚖️ Экономика и события",
		"ids": ["goods", "markets", "trade", "military", "emblems", "markers", "zones"]
	},
	{
		"title": "🎨 Климат и эффекты",
		"ids": ["labels", "vignette", "cells", "temperature", "precipitation"]
	}
]

# 13 layer presets
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

# Menu elements
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

# Options
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
# geography: where the map lies on the globe (FmgCoordinates)
var geo_auto_check: CheckButton = null
var geo_size_spin: SpinBox = null
var geo_lat_spin: SpinBox = null
var geo_lon_spin: SpinBox = null
var geo_info_label: Label = null
var distance_scale_spin: SpinBox = null
var climate_equator_spin: SpinBox = null
var climate_north_spin: SpinBox = null
var climate_south_spin: SpinBox = null
var climate_precip_spin: SpinBox = null
var wind_spins: Array = []

# Tools
var brush_option: OptionButton = null
var brush_size: HSlider = null
var ruler_check: CheckButton = null

# Interface / lettering preferences
var ui_scale_option: OptionButton = null
var label_overlap_check: CheckButton = null
var label_mode_option: OptionButton = null
var declutter_check: CheckButton = null
var label_min_spin: SpinBox = null
var label_scale_spin: SpinBox = null
var scale_bar_option: OptionButton = null
var vignette_option: OptionButton = null

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

	select_tab("layers")
	ui_theme.changed.connect(_on_theme_changed)
	_on_theme_changed()
	apply_preset("political")

	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_fit_panel_to_viewport):
		viewport.size_changed.connect(_fit_panel_to_viewport)
	_fit_panel_to_viewport()


# ---------------------------------------------------------------------------
# Construction

## Dynamic Island / Floating pill trigger button when the menu is collapsed.
func _build_trigger() -> void:
	trigger_box = HBoxContainer.new()
	trigger_box.position = Vector2(16, 16)
	trigger_box.add_theme_constant_override("separation", 8)
	trigger_box.visible = false
	add_child(trigger_box)

	trigger_button = Button.new()
	trigger_button.text = "🧭 Меню (Tab)"
	trigger_button.tooltip_text = "Открыть панель управления картой (Tab)"
	trigger_button.pressed.connect(show_menu)
	_style_tag(trigger_button, "pill")
	trigger_box.add_child(trigger_button)

	new_map_button = Button.new()
	new_map_button.text = "✦ Новая карта (F2)"
	new_map_button.tooltip_text = "Сгенерировать новую случайную карту (F2)"
	new_map_button.pressed.connect(request_new_map)
	_style_tag(new_map_button, "accent")
	trigger_box.add_child(new_map_button)


## Keeps the floating panel inside the visible canvas. The canvas shrinks when
## the window is small or when the interface scale is raised, and the tab content
## then has to scroll instead of running off the bottom of the screen.
func _fit_panel_to_viewport() -> void:
	if menu == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_scroll: float = clampf(viewport_size.y - 240.0, 140.0, 620.0)
	for scroll_value: Variant in tab_contents.values():
		var scroll: ScrollContainer = scroll_value
		if scroll != null:
			scroll.custom_minimum_size = Vector2(0.0, minf(440.0, max_scroll))
	if menu.size.y > viewport_size.y:
		menu.size.y = viewport_size.y


## The main Liquid Glass panel.
func _build_menu() -> void:
	menu = PanelContainer.new()
	menu.position = Vector2(16, 16)
	menu.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_style_tag(menu, "panel")
	add_child(menu)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	menu.add_child(main_vbox)

	# --- Window Header (macOS style frosted bar with grip and close button) ---
	var header_bar := PanelContainer.new()
	header_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	header_bar.tooltip_text = "Перетащите, чтобы переместить панель"
	_style_tag(header_bar, "dragbar")
	main_vbox.add_child(header_bar)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	header_bar.add_child(header_row)

	var logo_label := Label.new()
	logo_label.text = "✨ FMG"
	logo_label.add_theme_font_override("font", FmgUiTheme.font_ui())
	logo_label.add_theme_font_size_override("font_size", 13)
	logo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	logo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(logo_label)

	var grip := Label.new()
	grip.text = "━━━━━"
	grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.add_theme_font_override("font", FmgUiTheme.font_ui())
	grip.add_theme_font_size_override("font_size", 10)
	grip.add_theme_color_override("font_color", Color(1, 1, 1, 0.28))
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(grip)

	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Свернуть панель (Tab или Esc)"
	close_button.custom_minimum_size = Vector2(24, 24)
	close_button.pressed.connect(hide_menu)
	_style_tag(close_button, "button")
	header_row.add_child(close_button)

	header_bar.gui_input.connect(_on_drag_bar_input.bind(header_bar))

	# --- Apple Segmented Tab Bar ---
	var segmented_bar := PanelContainer.new()
	_style_tag(segmented_bar, "segmented")
	main_vbox.add_child(segmented_bar)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	segmented_bar.add_child(tabs)

	for tab_id: String in TAB_IDS:
		var tab := Button.new()
		tab.text = "%s %s" % [str(TAB_ICONS[tab_id]), str(TAB_TITLES[tab_id])]
		tab.tooltip_text = "Вкладка «%s»" % str(TAB_TITLES[tab_id])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 11)
		tab.clip_text = true
		_style_tag(tab, "tab")
		tab.pressed.connect(func() -> void: select_tab(tab_id))
		tabs.add_child(tab)
		tab_buttons[tab_id] = tab

	# --- Tab Contents Container ---
	var contents_area := PanelContainer.new()
	contents_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tag(contents_area, "card")
	main_vbox.add_child(contents_area)

	for tab_id: String in TAB_IDS:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 440)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.visible = false
		_style_tag(scroll, "scroll")

		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 8)
		scroll.add_child(content)
		contents_area.add_child(scroll)
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

	# --- Apple Bottom Dock (Action pill row) ---
	var dock := PanelContainer.new()
	_style_tag(dock, "dock")
	main_vbox.add_child(dock)

	var sticked := HBoxContainer.new()
	sticked.add_theme_constant_override("separation", 4)
	sticked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock.add_child(sticked)

	var sticked_list: Array = [
		["new", "✦ Новая", "accent"],
		["export", "⤓ Экспорт", "sticked"],
		["save", "💾 Сохр.", "sticked"],
		["load", "📂 Загр.", "sticked"],
		["fit", "⛶ Обзор", "sticked"],
		["search", "🔍 Поиск", "sticked"]
	]
	for entry: Array in sticked_list:
		var button := Button.new()
		button.text = str(entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = _sticked_tooltip(str(entry[0]))
		_style_tag(button, str(entry[2]))
		button.pressed.connect(_on_sticked_pressed.bind(str(entry[0])))
		sticked.add_child(button)
		button.add_theme_font_size_override("font_size", 11)
		if str(entry[0]) == "export":
			export_button = button


func _sticked_tooltip(id: String) -> String:
	match id:
		"new":
			return "Сгенерировать новую карту со случайным сидом (F2)"
		"export":
			return "Экспорт карты: PNG, SVG, CSV, GeoJSON, Высоты"
		"save":
			return "Сохранить карту в файл .map"
		"load":
			return "Загрузить карту из файла .map"
		"fit":
			return "Вписать всю карту в экран (0)"
		"search":
			return "Поиск команд, слоёв и инструментов (Пробел)"
	return ""


# ---------------------------------------------------------------------------
# Tab 1: Layers (Categorized Glass Cards)

func _build_layers_tab(content: VBoxContainer) -> void:
	# Preset Selector Card
	var preset_card := _make_card(content)
	_label(preset_card, "Пресет отображения:", "section_header", true)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 6)
	preset_card.add_child(preset_row)

	preset_option = OptionButton.new()
	preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(preset_option, "select")
	for preset_id: String in PRESETS.keys():
		preset_option.add_item(str(PRESET_TITLES[preset_id]))
		preset_option.set_item_metadata(preset_option.item_count - 1, preset_id)
	preset_option.item_selected.connect(func(index: int) -> void:
		apply_preset(str(preset_option.get_item_metadata(index))))
	preset_row.add_child(preset_option)

	# Quick Actions Row
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	preset_card.add_child(quick_row)

	var def_btn := Button.new()
	def_btn.text = "✦ Стандарт"
	def_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(def_btn, "button")
	def_btn.pressed.connect(func() -> void: apply_preset("political"))
	quick_row.add_child(def_btn)

	var all_btn := Button.new()
	all_btn.text = "✓ Все"
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(all_btn, "button")
	all_btn.pressed.connect(_enable_all_layers)
	quick_row.add_child(all_btn)

	var clear_btn := Button.new()
	clear_btn.text = "✕ Скрыть"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(clear_btn, "button")
	clear_btn.pressed.connect(_disable_all_layers)
	quick_row.add_child(clear_btn)

	# Categorized Layer Groups
	for cat: Dictionary in LAYER_CATEGORIES:
		var cat_card := _make_card(content)
		_label(cat_card, str(cat["title"]), "section_header", true)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 4)
		cat_card.add_child(grid)

		for layer_id: String in cat["ids"]:
			var layer_data: Dictionary = _find_layer_data(layer_id)
			if layer_data.is_empty():
				continue
			var button := Button.new()
			button.text = str(layer_data["label"])
			button.toggle_mode = true
			button.tooltip_text = "Слой «%s»" % str(layer_data["label"])
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_tag(button, "layer")
			var prop: String = str(layer_data["prop"])
			button.button_pressed = bool(view.get(prop))
			button.toggled.connect(func(pressed: bool) -> void:
				view.set(prop, pressed)
				if prop == "show_rulers" and pressed:
					view.ruler_points = PackedVector2Array()
				view.queue_redraw()
				_refresh_layer_button(button, pressed)
				settings_changed.emit())
			grid.add_child(button)
			layer_buttons[layer_id] = button
			_refresh_layer_button(button, button.button_pressed)


func _find_layer_data(id: String) -> Dictionary:
	for layer: Dictionary in LAYERS:
		if str(layer["id"]) == id:
			return layer
	return {}


func _enable_all_layers() -> void:
	for layer: Dictionary in LAYERS:
		var prop: String = str(layer["prop"])
		view.set(prop, true)
		if layer_buttons.has(str(layer["id"])):
			var btn: Button = layer_buttons[str(layer["id"])]
			btn.button_pressed = true
			_refresh_layer_button(btn, true)
	view.queue_redraw()


func _disable_all_layers() -> void:
	for layer: Dictionary in LAYERS:
		var prop: String = str(layer["prop"])
		view.set(prop, false)
		if layer_buttons.has(str(layer["id"])):
			var btn: Button = layer_buttons[str(layer["id"])]
			btn.button_pressed = false
			_refresh_layer_button(btn, false)
	view.queue_redraw()


# ---------------------------------------------------------------------------
# Tab 2: Style

func _build_style_tab(content: VBoxContainer) -> void:
	var color_card := _make_card(content)
	_label(color_card, "🎨 Цветовая палитра карты:", "section_header", true)

	var color_grid := GridContainer.new()
	color_grid.columns = 2
	color_grid.add_theme_constant_override("h_separation", 8)
	color_grid.add_theme_constant_override("v_separation", 4)
	color_card.add_child(color_grid)

	_color_grid_item(color_grid, "Океан", "style_ocean")
	_color_grid_item(color_grid, "Глубины", "style_ocean_deep")
	_color_grid_item(color_grid, "Суша", "style_land")
	_color_grid_item(color_grid, "Озёра", "style_lake")
	_color_grid_item(color_grid, "Реки", "style_river")
	_color_grid_item(color_grid, "Берег", "style_coast")
	_color_grid_item(color_grid, "Дороги", "style_road")
	_color_grid_item(color_grid, "Границы", "style_border")

	var line_card := _make_card(content)
	_label(line_card, "📏 Линии и масштаб надписей:", "section_header", true)
	_spin_row(line_card, "Толщина берега", 0.2, 4.0, 0.1, view.style_coast_width, func(v: float) -> void:
		view.style_coast_width = v
		view.queue_redraw())
	_spin_row(line_card, "Толщина границ", 0.2, 6.0, 0.1, view.style_border_width, func(v: float) -> void:
		view.style_border_width = v
		view.queue_redraw())
	_spin_row(line_card, "Толщина дорог", 0.2, 6.0, 0.1, view.style_road_width, func(v: float) -> void:
		view.style_road_width = v
		view.queue_redraw())
	label_scale_spin = _spin_row(line_card, "Масштаб подписей", 0.25, 4.0, 0.05, view.style_label_scale, func(v: float) -> void:
		view.style_label_scale = v
		view.queue_redraw()
		settings_changed.emit())

	# --- lettering behaviour ---
	var text_card := _make_card(content)
	_label(text_card, "🔤 Подписи при приближении:", "section_header", true)

	label_mode_option = OptionButton.new()
	label_mode_option.add_item("Растут вместе с картой")
	label_mode_option.set_item_metadata(0, MapView.LabelScale.WITH_MAP)
	label_mode_option.add_item("Постоянный размер на экране")
	label_mode_option.set_item_metadata(1, MapView.LabelScale.FIXED_SCREEN)
	label_mode_option.select(view.label_scale_mode)
	label_mode_option.tooltip_text = "В обоих режимах текст рисуется резко: глифы растеризуются под текущий зум, а не растягиваются"
	_style_tag(label_mode_option, "select")
	label_mode_option.item_selected.connect(func(index: int) -> void:
		view.label_scale_mode = int(label_mode_option.get_item_metadata(index))
		view.queue_redraw()
		settings_changed.emit())
	_option_row(text_card, "Поведение", label_mode_option)

	declutter_check = CheckButton.new()
	declutter_check.text = "Скрывать нечитаемо мелкие подписи"
	declutter_check.button_pressed = view.label_declutter
	_style_tag(declutter_check, "check")
	declutter_check.toggled.connect(func(pressed: bool) -> void:
		view.label_declutter = pressed
		view.queue_redraw()
		settings_changed.emit())
	text_card.add_child(declutter_check)

	label_min_spin = _spin_row(text_card, "Порог читаемости, px", 3.0, 20.0, 0.5, view.label_min_px, func(v: float) -> void:
		view.label_min_px = v
		view.queue_redraw()
		settings_changed.emit())
	label_min_spin.tooltip_text = "Подписи мельче этого размера на экране не рисуются (как уровни подписей в оригинале)"

	label_overlap_check = CheckButton.new()
	label_overlap_check.text = "Убирать налезающие названия"
	label_overlap_check.button_pressed = view.label_avoid_overlap
	label_overlap_check.tooltip_text = "Столицы и крупные города получают приоритет, мелкие названия скрываются, чтобы текст не сливался"
	_style_tag(label_overlap_check, "check")
	label_overlap_check.toggled.connect(func(pressed: bool) -> void:
		view.label_avoid_overlap = pressed
		view.queue_redraw()
		settings_changed.emit())
	text_card.add_child(label_overlap_check)

	# --- map furniture ---
	var furniture_card := _make_card(content)
	_label(furniture_card, "🧭 Мебель карты:", "section_header", true)

	scale_bar_option = OptionButton.new()
	scale_bar_option.add_item("Напечатана на карте")
	scale_bar_option.set_item_metadata(0, true)
	scale_bar_option.add_item("Закреплена на экране")
	scale_bar_option.set_item_metadata(1, false)
	scale_bar_option.select(0 if view.scale_bar_on_map else 1)
	_style_tag(scale_bar_option, "select")
	scale_bar_option.item_selected.connect(func(index: int) -> void:
		view.scale_bar_on_map = bool(scale_bar_option.get_item_metadata(index))
		view.queue_redraw()
		settings_changed.emit())
	_option_row(furniture_card, "Линейка масштаба", scale_bar_option)

	vignette_option = OptionButton.new()
	vignette_option.add_item("Рамка на карте")
	vignette_option.set_item_metadata(0, true)
	vignette_option.add_item("Виньетка на экране")
	vignette_option.set_item_metadata(1, false)
	vignette_option.select(0 if view.vignette_on_map else 1)
	_style_tag(vignette_option, "select")
	vignette_option.item_selected.connect(func(index: int) -> void:
		view.vignette_on_map = bool(vignette_option.get_item_metadata(index))
		view.queue_redraw()
		settings_changed.emit())
	_option_row(furniture_card, "Виньетка", vignette_option)

	_tip(content, "Цвета, толщины, подписи и мебель применяются мгновенно без повторного расчёта геометрии и запоминаются между запусками.")


# ---------------------------------------------------------------------------
# Tab 3: Options (Map Settings & Generation)

func _build_options_tab(content: VBoxContainer) -> void:
	var geom_card := _make_card(content)
	_label(geom_card, "🗺️ Геометрия мира:", "section_header", true)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	geom_card.add_child(size_row)
	_label(size_row, "Размер", "label")
	map_width_spin = _make_spin(240, 8192, 1, sim.map_width, 86.0)
	map_height_spin = _make_spin(135, 8192, 1, sim.map_height, 86.0)
	size_row.add_child(map_width_spin)
	_label(size_row, "×", "label")
	size_row.add_child(map_height_spin)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	geom_card.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.text = sim.seed_value
	seed_edit.placeholder_text = "Сид карты"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.tooltip_text = "Сид генерации (число)"
	_style_tag(seed_edit, "field")
	seed_row.add_child(seed_edit)
	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "Сгенерировать случайный сид"
	_style_tag(dice, "button")
	dice.pressed.connect(func() -> void:
		seed_edit.text = str(randi() % 1000000000))
	seed_row.add_child(dice)

	density_option = OptionButton.new()
	for d: Array in DENSITIES:
		density_option.add_item("%s ячеек" % str(d[1]), int(d[0]))
	density_option.select(3)
	density_option.tooltip_text = "Число точек графа Вороного (10 000 — баланс качества и скорости)"
	_style_tag(density_option, "select")
	_option_row(geom_card, "Детализация", density_option)

	template_option = OptionButton.new()
	template_option.add_item("Случайный", 0)
	template_option.set_item_metadata(0, "random")
	var t_index: int = 1
	for tid: String in HeightmapTemplates.TEMPLATES:
		template_option.add_item(HeightmapTemplates.template_name(tid), t_index)
		template_option.set_item_metadata(t_index, tid)
		t_index += 1
	# the pre-created real-world heightmaps of the original
	template_option.add_separator("Реальные миры")
	for tid: String in HeightmapTemplates.PRECREATED:
		template_option.add_item("🌍 " + HeightmapTemplates.template_name(tid), t_index)
		template_option.set_item_metadata(t_index, tid)
		t_index += 1
	template_option.select(1 + 3)
	template_option.tooltip_text = "Шаблон высотной карты: процедурный или реальный мир (Британия, Исландия, Европа…)"
	_style_tag(template_option, "select")
	template_option.item_selected.connect(func(_index: int) -> void: _update_geography_hint())
	_option_row(geom_card, "Шаблон", template_option)

	# Geography Card: the map's place on the globe. It is what makes a map of
	# Britain temperate and a map of Iceland sub-polar, exactly like in the
	# original, where the template provides the size and the position.
	var geo_card := _make_card(content)
	_label(geo_card, "🌍 Положение на глобусе:", "section_header", true)

	geo_auto_check = CheckButton.new()
	geo_auto_check.text = "По шаблону (авто)"
	geo_auto_check.button_pressed = sim.geo_auto
	geo_auto_check.tooltip_text = "Размер и широту выбирает шаблон (у реальных миров они фиксированы)"
	_style_tag(geo_auto_check, "check")
	geo_auto_check.toggled.connect(func(pressed: bool) -> void:
		sim.geo_auto = pressed
		if not pressed and sim.geo_map_size < 0.0:
			# unlocking the sliders starts from the values the template produced
			sim.geo_map_size = maxf(sim.lat_t / 1.8, 1.0)
			sim.geo_latitude = clampf((90.0 - sim.lat_n) / maxf(180.0 - sim.lat_t, 1.0) * 100.0, 0.0, 100.0)
			sim.geo_longitude = clampf((180.0 - sim.lon_e) / maxf(360.0 - sim.lon_t, 1.0) * 100.0, 0.0, 100.0)
		_sync_geography_controls()
		settings_changed.emit())
	geo_card.add_child(geo_auto_check)

	geo_size_spin = _make_spin(1.0, 100.0, 0.5, maxf(sim.geo_map_size, 1.0))
	_spin_control_row(geo_card, "Размер мира %", geo_size_spin)
	geo_lat_spin = _make_spin(0.0, 100.0, 0.5, sim.geo_latitude)
	_spin_control_row(geo_card, "Сдвиг широты %", geo_lat_spin)
	geo_lon_spin = _make_spin(0.0, 100.0, 0.5, sim.geo_longitude)
	_spin_control_row(geo_card, "Сдвиг долготы %", geo_lon_spin)
	for spin: SpinBox in [geo_size_spin, geo_lat_spin, geo_lon_spin]:
		spin.editable = not sim.geo_auto
		spin.value_changed.connect(func(_v: float) -> void:
			_apply_geography_from_controls()
			settings_changed.emit())

	geo_info_label = _label(geo_card, sim.geography_text(), "tip")
	_tip(geo_card, "Шаблоны реальных миров несут своё положение: Британия — 7 % мира на 51° с. ш., Исландия — 2 % на 55°, Африка — 45 % на экваторе. Широтный пояс задаёт температуру, осадки, лёд, биомы и градусную сетку; пересчёт — кнопкой «Применить климат».")

	var civ_card := _make_card(content)
	_label(civ_card, "🏛️ Население и державы:", "section_header", true)

	cultures_spin = _make_spin(1, 32, 1, float(sim.cultures_limit))
	_spin_control_row(civ_card, "Культур", cultures_spin)

	cultures_set_option = OptionButton.new()
	var set_index: int = 0
	for set_id: String in FmgCultures.CULTURE_SETS:
		var set_meta: Dictionary = FmgCultures.CULTURE_SETS[set_id]
		cultures_set_option.add_item(str(set_meta["nameRu"]), set_index)
		cultures_set_option.set_item_metadata(set_index, set_id)
		if set_id == sim.cultures_set:
			cultures_set_option.select(set_index)
		set_index += 1
	_style_tag(cultures_set_option, "select")
	_option_row(civ_card, "Набор культур", cultures_set_option)

	states_spin = _make_spin(0, 100, 1, float(sim.states_limit))
	_spin_control_row(civ_card, "Государств", states_spin)

	religions_spin = _make_spin(0, 24, 1, float(sim.religions_limit))
	_spin_control_row(civ_card, "Религий", religions_spin)

	provinces_ratio_spin = _make_spin(0, 100, 5, sim.provinces_ratio)
	_spin_control_row(civ_card, "Провинции %", provinces_ratio_spin)

	burgs_check = CheckButton.new()
	burgs_check.text = "Города: автоматически"
	burgs_check.button_pressed = sim.burgs_limit < 0
	_style_tag(burgs_check, "check")
	civ_card.add_child(burgs_check)

	distance_scale_spin = _make_spin(0.01, 20.0, 0.1, view.distance_scale)
	_spin_control_row(civ_card, "Км / пиксель", distance_scale_spin)
	distance_scale_spin.value_changed.connect(func(v: float) -> void:
		view.distance_scale = v
		view.queue_redraw())

	# Climate Card
	var climate_card := _make_card(content)
	_label(climate_card, "☀️ Климат и ветра:", "section_header", true)
	climate_equator_spin = _climate_row(climate_card, "Экватор °C", -10.0, 40.0, sim.climate_equator, func(v: float) -> void: sim.climate_equator = v)
	climate_north_spin = _climate_row(climate_card, "Сев. полюс °C", -60.0, 15.0, sim.climate_north_pole, func(v: float) -> void: sim.climate_north_pole = v)
	climate_south_spin = _climate_row(climate_card, "Юж. полюс °C", -60.0, 15.0, sim.climate_south_pole, func(v: float) -> void: sim.climate_south_pole = v)
	climate_precip_spin = _climate_row(climate_card, "Осадки %", 0.0, 400.0, sim.climate_precipitation, func(v: float) -> void: sim.climate_precipitation = v)

	wind_spins = []
	var wind_names: Array = ["Ветер N пол.", "Ветер N ум.", "Ветер троп. N", "Ветер троп. S", "Ветер S ум.", "Ветер S пол."]
	for i: int in 6:
		var wind_spin := _make_spin(0.0, 360.0, 5.0, float(sim.climate_winds[i]) if i < sim.climate_winds.size() else 0.0)
		_spin_control_row(climate_card, str(wind_names[i]), wind_spin)
		wind_spin.value_changed.connect(_on_wind_changed.bind(i))
		wind_spins.append(wind_spin)

	var climate_btn := Button.new()
	climate_btn.text = "Применить климат"
	climate_btn.tooltip_text = "Пересчитать климат, реки, биомы и государства"
	_style_tag(climate_btn, "button")
	climate_btn.pressed.connect(func() -> void: climate_apply_requested.emit())
	climate_card.add_child(climate_btn)

	# Interface Theme Card
	var theme_card := _make_card(content)
	_label(theme_card, "✨ Оформление Liquid Glass:", "section_header", true)
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 8)
	theme_card.add_child(theme_row)
	_label(theme_row, "Оттенок", "label")
	var hue_slider := HSlider.new()
	hue_slider.min_value = 0.0
	hue_slider.max_value = 359.0
	hue_slider.step = 1.0
	hue_slider.value = 228.0
	hue_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tag(hue_slider, "slider")
	hue_slider.value_changed.connect(func(v: float) -> void:
		ui_theme.set_hue(v)
		settings_changed.emit())
	theme_row.add_child(hue_slider)
	var color_picker := ColorPickerButton.new()
	color_picker.custom_minimum_size = Vector2(38, 24)
	color_picker.color = ui_theme.theme_color
	color_picker.color_changed.connect(func(color: Color) -> void:
		ui_theme.set_theme(color, ui_theme.transparency)
		settings_changed.emit())
	theme_row.add_child(color_picker)
	_spin_row(theme_card, "Прозрачность %", 0.0, 90.0, 1.0, ui_theme.transparency, func(v: float) -> void:
		ui_theme.set_theme(ui_theme.theme_color, v)
		settings_changed.emit())

	# Interface scale (HiDPI / 4K screens)
	var ui_card := _make_card(content)
	_label(ui_card, "🖥️ Интерфейс:", "section_header", true)
	ui_scale_option = OptionButton.new()
	ui_scale_option.add_item("Авто (по размеру окна)")
	ui_scale_option.set_item_metadata(0, {"mode": 0, "scale": 1.0})
	var scale_choices: Array = [1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
	for factor: float in scale_choices:
		var index: int = ui_scale_option.item_count
		ui_scale_option.add_item("%d %%" % int(round(factor * 100.0)))
		ui_scale_option.set_item_metadata(index, {"mode": 1, "scale": factor})
	_style_tag(ui_scale_option, "select")
	ui_scale_option.item_selected.connect(func(index: int) -> void:
		var meta: Dictionary = ui_scale_option.get_item_metadata(index)
		ui_scale_requested.emit(int(meta.get("mode", 0)), float(meta.get("scale", 1.0))))
	_option_row(ui_card, "Масштаб UI", ui_scale_option)
	_tip(ui_card, "Интерфейс масштабируется под размер окна; здесь можно добавить множитель для плотных экранов. Текст интерфейса и карты растеризуется под итоговый масштаб, поэтому остаётся резким.")

	# Big Call-to-Action button
	var generate := Button.new()
	generate.text = "✦ Сгенерировать карту (F2)"
	generate.custom_minimum_size = Vector2(0, 44)
	generate.tooltip_text = "Создать новую карту с текущими параметрами (F2)"
	_style_tag(generate, "accent")
	generate.pressed.connect(request_new_map)
	content.add_child(generate)


# ---------------------------------------------------------------------------
# Tab 4: Tools

func _build_tools_tab(content: VBoxContainer) -> void:
	var edit_card := _make_card(content)
	_label(edit_card, "🖌️ Кисть рельефа и линейка:", "section_header", true)
	brush_option = OptionButton.new()
	brush_option.add_item("Кисть: выключена", -1)
	brush_option.add_item("Поднять рельеф", 0)
	brush_option.add_item("Опустить рельеф", 1)
	brush_option.add_item("Сгладить", 2)
	brush_option.select(0)
	_style_tag(brush_option, "select")
	_option_row(edit_card, "Режим кисти", brush_option)

	brush_size = HSlider.new()
	brush_size.min_value = 10.0
	brush_size.max_value = 150.0
	brush_size.value = 45.0
	_style_tag(brush_size, "slider")
	var brush_row := HBoxContainer.new()
	edit_card.add_child(brush_row)
	_label(brush_row, "Радиус кисти", "label")
	brush_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brush_row.add_child(brush_size)

	ruler_check = CheckButton.new()
	ruler_check.text = "Линейка измерений активна"
	_style_tag(ruler_check, "check")
	ruler_check.toggled.connect(func(pressed: bool) -> void:
		view.show_rulers = pressed
		if pressed:
			view.ruler_points = PackedVector2Array()
		view.queue_redraw())
	edit_card.add_child(ruler_check)

	var table_card := _make_card(content)
	_label(table_card, "📊 Обзоры и таблицы данных:", "section_header", true)
	var overview_grid := GridContainer.new()
	overview_grid.columns = 3
	overview_grid.add_theme_constant_override("h_separation", 6)
	overview_grid.add_theme_constant_override("v_separation", 6)
	table_card.add_child(overview_grid)
	for entry: Array in [
		["burgs", "🏙️ Города"], ["states", "🚩 Державы"], ["rivers", "🌊 Реки"],
		["markers", "📍 Маркеры"], ["markets", "⚖️ Рынки"], ["diplomacy", "🤝 Связи"]
	]:
		var button := Button.new()
		button.text = str(entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tag(button, "button")
		button.pressed.connect(func() -> void: overview_requested.emit(str(entry[0])))
		overview_grid.add_child(button)

	var export_card := _make_card(content)
	_label(export_card, "💾 Экспорт карты и данных:", "section_header", true)
	var export_grid := GridContainer.new()
	export_grid.columns = 3
	export_grid.add_theme_constant_override("h_separation", 6)
	export_grid.add_theme_constant_override("v_separation", 6)
	export_card.add_child(export_grid)
	for entry: Array in [
		["png", "🖼️ PNG"], ["svg", "📐 SVG"], ["csv", "📊 CSV"],
		["geojson", "🌐 GeoJSON"], ["height", "⛰️ Высоты"]
	]:
		var button := Button.new()
		button.text = str(entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tag(button, "button")
		button.pressed.connect(func() -> void: export_requested.emit(str(entry[0])))
		export_grid.add_child(button)

	var regen_card := _make_card(content)
	var regen := Button.new()
	regen.text = "🔄 Пересчитать карту с тем же сидом"
	regen.tooltip_text = "Повторить генерацию с текущими настройками"
	_style_tag(regen, "button")
	regen.pressed.connect(func() -> void: generate_requested.emit())
	regen_card.add_child(regen)


# ---------------------------------------------------------------------------
# Tab 5: About

func _build_about_tab(content: VBoxContainer) -> void:
	var hero_card := _make_card(content)
	var title := Label.new()
	title.text = "Fantasy Map Generator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_font_override("font", FmgUiTheme.font_ui())
	title.add_theme_color_override("font_color", Color.WHITE)
	hero_card.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Godot 4 · Liquid Glass Edition"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	_style_tag(subtitle, "tip")
	hero_card.add_child(subtitle)

	var desc_card := _make_card(content)
	var about := Label.new()
	about.text = "Процедурный генератор фэнтезийных карт: рельеф, реки, биомы, климат, культуры, государства, провинции, религии, города, дороги, рынки и торговля, армии, дипломатия, маркеры, зоны и геральдика.\n\nИнтерфейс выполнен в современном стиле Apple Liquid Glass с полупрозрачным матовым стеклом и плавающими панелями."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_font_override("font", FmgUiTheme.font_ui())
	about.add_theme_font_size_override("font_size", 12)
	about.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	desc_card.add_child(about)

	var hotkey_card := _make_card(content)
	_label(hotkey_card, "⌨️ Горячие клавиши:", "section_header", true)
	var hotkeys := Label.new()
	hotkeys.text = "Tab — показать / скрыть меню\nF2 — новая карта со случайным сидом\n0 — вписать карту в видимую область\nПробел — поиск по слоям и командам (Spotlight)\nEsc — закрыть активный диалог\nКолесо мыши — плавный зум; ЛКМ / ПКМ — панорама\nB, S, C, R, P, T, N и другие — быстрое переключение слоёв\n\\ — легенда карты"
	hotkeys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hotkeys.add_theme_font_override("font", FmgUiTheme.font_ui())
	_style_tag(hotkeys, "tip")
	hotkey_card.add_child(hotkeys)


# ---------------------------------------------------------------------------
# Floating Overlays & Helpers

func _make_card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	_style_tag(card, "card")
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return box


func _build_export_popup() -> void:
	export_popup = PanelContainer.new()
	export_popup.visible = false
	_style_tag(export_popup, "panel")
	add_child(export_popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	export_popup.add_child(box)
	for entry: Array in [
		["png", "🖼️ Изображение PNG"], ["svg", "📐 Векторная карта SVG"],
		["csv", "📊 Данные ячеек CSV"], ["geojson", "🌐 Геоданные GeoJSON"],
		["height", "⛰️ Высотная карта PNG"]
	]:
		var button := Button.new()
		button.text = str(entry[1])
		_style_tag(button, "button")
		button.pressed.connect(func() -> void:
			export_popup.visible = false
			export_requested.emit(str(entry[0])))
		box.add_child(button)


## Spotlight-style command palette (Space).
func _build_omnibar() -> void:
	omnibar = PanelContainer.new()
	omnibar.visible = false
	omnibar.custom_minimum_size = Vector2(440, 0)
	_style_tag(omnibar, "panel")
	add_child(omnibar)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	omnibar.add_child(box)

	omnibar_edit = LineEdit.new()
	omnibar_edit.placeholder_text = "🔍 Поиск слоёв, инструментов и команд…"
	_style_tag(omnibar_edit, "field")
	omnibar_edit.add_theme_font_override("font", FmgUiTheme.font_ui())
	omnibar_edit.text_changed.connect(_refresh_omnibar)
	box.add_child(omnibar_edit)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_tag(scroll, "scroll")
	box.add_child(scroll)

	omnibar_results = VBoxContainer.new()
	omnibar_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	omnibar_results.add_theme_constant_override("separation", 3)
	scroll.add_child(omnibar_results)


## Frosted glass loading overlay.
func _build_loading_overlay() -> void:
	loading_overlay = Control.new()
	loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_overlay.visible = false
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(loading_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(bg)

	var center_card := PanelContainer.new()
	center_card.set_anchors_preset(Control.PRESET_CENTER)
	center_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_card.custom_minimum_size = Vector2(360, 280)
	_style_tag(center_card, "panel")
	center_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_overlay.add_child(center_card)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_card.add_child(center)

	var rose := Control.new()
	rose.custom_minimum_size = Vector2(120, 120)
	rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(rose)

	var title := Label.new()
	title.text = "Fantasy Map Generator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_font_override("font", FmgUiTheme.font_ui())
	title.add_theme_color_override("font_color", Color.WHITE)
	center.add_child(title)

	loading_stage_label = Label.new()
	loading_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_stage_label.add_theme_font_size_override("font_size", 14)
	loading_stage_label.add_theme_font_override("font", FmgUiTheme.font_ui())
	loading_stage_label.add_theme_color_override("font_color", Color(0.85, 0.89, 0.98))
	loading_stage_label.text = "Генерация мира…"
	center.add_child(loading_stage_label)

	loading_progress = ProgressBar.new()
	loading_progress.min_value = 0.0
	loading_progress.max_value = 1.0
	loading_progress.show_percentage = false
	loading_progress.custom_minimum_size = Vector2(300, 6)
	center.add_child(loading_progress)

	rose.draw.connect(_draw_loading_rose.bind(rose))
	rose.set_meta("start_ms", Time.get_ticks_msec())


func _draw_loading_rose(rose: Control) -> void:
	var center := rose.size / 2.0
	var rotation_angle := TAU * float((Time.get_ticks_msec() - int(rose.get_meta("start_ms", 0))) % 16000) / 16000.0
	var dark := Color("#202838")
	var light := Color("#f0f4fc")
	var radius := minf(center.x, center.y) * 0.90
	rose.draw_arc(center, radius, 0.0, TAU, 56, Color(1, 1, 1, 0.35), 1.5, true)
	for k: int in 16:
		var major: bool = k % 2 == 0
		var angle: float = rotation_angle - PI / 2.0 + TAU * float(k) / 16.0
		var length: float = radius * (0.92 if major else 0.5)
		var half_width: float = TAU / 16.0 * 0.55
		var tip := center + Vector2(cos(angle), sin(angle)) * length
		var left := center + Vector2(cos(angle - half_width), sin(angle - half_width)) * radius * 0.1
		var right := center + Vector2(cos(angle + half_width), sin(angle + half_width)) * radius * 0.1
		var tone := dark if k % 4 == 0 else light
		if major:
			rose.draw_colored_polygon(PackedVector2Array([center, tip, left]), tone)
			rose.draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(tone, 0.6))
		else:
			rose.draw_colored_polygon(PackedVector2Array([center, tip, left]), Color(tone, 0.75))
			rose.draw_colored_polygon(PackedVector2Array([center, tip, right]), Color(tone, 0.4))
	rose.draw_circle(center, radius * 0.08, dark)
	rose.draw_circle(center, radius * 0.04, light)


## Floating capsule status bar docked at bottom left.
func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16.0
	bar.offset_right = -16.0
	bar.offset_bottom = -12.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_tag(bar, "dock")
	add_child(bar)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	status_label = Label.new()
	status_label.text = "● Готов к генерации"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_override("font", FmgUiTheme.font_ui())
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#e8ecf8"))
	status_label.clip_text = true
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status_label)

	zoom_label = Label.new()
	zoom_label.text = "100%"
	zoom_label.add_theme_font_override("font", FmgUiTheme.mono())
	zoom_label.add_theme_font_size_override("font_size", 13)
	zoom_label.add_theme_color_override("font_color", Color("#a0acc4"))
	zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(zoom_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 4)
	progress_bar.visible = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(progress_bar)


# ---------------------------------------------------------------------------
# Behavior & Handlers

func _process(_delta: float) -> void:
	if loading_overlay != null and loading_overlay.visible:
		for child in loading_overlay.get_children():
			if child is PanelContainer:
				var vbox: VBoxContainer = child.get_child(0) as VBoxContainer
				if vbox != null and vbox.get_child_count() > 0:
					(vbox.get_child(0) as Control).queue_redraw()


func show_menu() -> void:
	menu.visible = true
	trigger_box.visible = false


func hide_menu() -> void:
	menu.visible = false
	export_popup.visible = false
	trigger_box.visible = true


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
	if ui_theme != null:
		ui_theme.apply_style(menu)


func _on_drag_bar_input(event: InputEvent, _bar: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			set_meta("drag_offset", menu.position - (event as InputEventMouseButton).global_position)
		else:
			set_meta("drag_offset", null)
	elif event is InputEventMouseMotion and get_meta("drag_offset", null) != null:
		var offset: Vector2 = get_meta("drag_offset")
		var size: Vector2 = get_viewport_rect().size
		var target: Vector2 = (event as InputEventMouseMotion).global_position + offset
		menu.position = Vector2(
			clampf(target.x, 0.0, maxf(size.x - 80.0, 0.0)),
			clampf(target.y, 0.0, maxf(size.y - 80.0, 0.0)))


func request_new_map() -> void:
	if _busy:
		return
	if seed_edit != null:
		seed_edit.text = str(randi() % 1000000000)
	generate_requested.emit()


func _on_sticked_pressed(id: String) -> void:
	match id:
		"new":
			request_new_map()
		"export":
			if export_button != null:
				export_popup.position = export_button.global_position + Vector2(0, 30)
				export_popup.visible = not export_popup.visible
		"save":
			save_requested.emit()
		"load":
			load_requested.emit()
		"fit":
			fit_requested.emit()
		"search":
			_toggle_omnibar()


func open_omnibar() -> void:
	omnibar.position = menu.position
	omnibar_edit.text = ""
	_refresh_omnibar("")
	omnibar.visible = true
	omnibar_edit.grab_focus()


func close_popups() -> void:
	if export_popup != null:
		export_popup.visible = false
	if omnibar != null:
		omnibar.visible = false


func _toggle_omnibar() -> void:
	if omnibar.visible:
		omnibar.visible = false
	else:
		open_omnibar()


func _refresh_omnibar(query: String) -> void:
	for child in omnibar_results.get_children():
		child.queue_free()
	var needle: String = query.strip_edges().to_lower()
	var actions: Array = _collect_actions()
	var count: int = 0
	for action: Dictionary in actions:
		var title: String = str(action["title"])
		if not needle.is_empty() and not title.to_lower().contains(needle):
			continue
		var btn := Button.new()
		btn.text = title
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_tag(btn, "button")
		var run_callable: Callable = action["run"]
		btn.pressed.connect(func() -> void:
			omnibar.visible = false
			run_callable.call())
		omnibar_results.add_child(btn)
		count += 1
		if count >= 10:
			break


func _collect_actions() -> Array:
	var actions: Array = []
	actions.append({"title": "✦ Новая карта (F2)", "run": func() -> void: request_new_map()})
	actions.append({"title": "⛶ Вписать карту в экран (0)", "run": func() -> void: fit_requested.emit()})
	actions.append({"title": "💾 Сохранить карту в .map", "run": func() -> void: save_requested.emit()})
	actions.append({"title": "📂 Загрузить карту из .map", "run": func() -> void: load_requested.emit()})
	actions.append({"title": "🖼️ Экспорт: PNG изображение", "run": func() -> void: export_requested.emit("png")})
	actions.append({"title": "📐 Экспорт: SVG вектор", "run": func() -> void: export_requested.emit("svg")})
	actions.append({"title": "📊 Экспорт: CSV ячейки", "run": func() -> void: export_requested.emit("csv")})
	actions.append({"title": "🌐 Экспорт: GeoJSON данные", "run": func() -> void: export_requested.emit("geojson")})
	actions.append({"title": "⛰️ Экспорт: Высотная карта", "run": func() -> void: export_requested.emit("height")})

	for preset_id: String in PRESETS.keys():
		var p_name: String = str(PRESET_TITLES[preset_id])
		actions.append({
			"title": "Пресет: %s" % p_name,
			"run": func() -> void: apply_preset(preset_id)
		})

	for layer: Dictionary in LAYERS:
		var l_name: String = str(layer["label"])
		var prop: String = str(layer["prop"])
		actions.append({
			"title": "Слой: %s" % l_name,
			"run": func() -> void:
				view.set(prop, not bool(view.get(prop)))
				view.queue_redraw()
				if layer_buttons.has(str(layer["id"])):
					_refresh_layer_button(layer_buttons[str(layer["id"])], bool(view.get(prop)))
		})
	return actions


func apply_preset(preset_id: String) -> void:
	if not PRESETS.has(preset_id):
		return
	var active_ids: Array = PRESETS[preset_id]
	for layer: Dictionary in LAYERS:
		var lid: String = str(layer["id"])
		var should_show: bool = active_ids.has(lid)
		var prop: String = str(layer["prop"])
		view.set(prop, should_show)
		if layer_buttons.has(lid):
			_refresh_layer_button(layer_buttons[lid], should_show)
	view.queue_redraw()
	if preset_option != null:
		for i: int in preset_option.item_count:
			if str(preset_option.get_item_metadata(i)) == preset_id:
				preset_option.select(i)
				break
	settings_changed.emit()


func _refresh_layer_button(button: Button, active: bool) -> void:
	button.button_pressed = active
	_style_tag(button, "layer_active" if active else "layer")
	if ui_theme != null:
		ui_theme.apply_style(button)


func handle_layer_key(keycode: int) -> bool:
	for layer: Dictionary in LAYERS:
		if int(layer["key"]) == keycode:
			var prop: String = str(layer["prop"])
			var new_val: bool = not bool(view.get(prop))
			view.set(prop, new_val)
			view.queue_redraw()
			if layer_buttons.has(str(layer["id"])):
				_refresh_layer_button(layer_buttons[str(layer["id"])], new_val)
			settings_changed.emit()
			return true
	return false


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


func set_status(text: String) -> void:
	if status_label != null and status_label.text != "● " + text:
		status_label.text = "● " + text


func set_zoom(zoom: float) -> void:
	set_zoom_info(int(round(zoom * 100.0)), "")


## Called every frame: only touch the label when the text actually changes, so the
## status bar does not re-layout continuously while the map moves.
func set_zoom_info(zoom_percent: int, pointer: String) -> void:
	if zoom_label == null:
		return
	var text: String = "🔍 %d%%" % zoom_percent if pointer.is_empty() else "🔍 %d%% · %s" % [zoom_percent, pointer]
	if zoom_label.text != text:
		zoom_label.text = text


func show_progress(vis: bool) -> void:
	if progress_bar != null:
		progress_bar.visible = vis


func set_progress(value: float) -> void:
	if progress_bar != null:
		progress_bar.value = clampf(value, 0.0, 1.0)


func show_loading(vis: bool, stage_text: String = "Генерация мира…") -> void:
	_busy = vis
	if loading_overlay != null:
		loading_overlay.visible = vis
		if vis:
			loading_stage_label.text = stage_text
			loading_progress.value = 0.0


func set_loading_stage(stage_text: String, progress_value: float) -> void:
	if loading_stage_label != null:
		loading_stage_label.text = stage_text
	if loading_progress != null:
		loading_progress.value = clampf(progress_value, 0.0, 1.0)


## Push the simulation's geography into the controls of the geography card
func _sync_geography_controls() -> void:
	if geo_auto_check != null:
		geo_auto_check.set_pressed_no_signal(sim.geo_auto)
	var editable: bool = not sim.geo_auto
	if geo_size_spin != null:
		geo_size_spin.editable = editable
		geo_size_spin.set_value_no_signal(clampf(maxf(sim.geo_map_size, 1.0), 1.0, 100.0))
	if geo_lat_spin != null:
		geo_lat_spin.editable = editable
		geo_lat_spin.set_value_no_signal(clampf(sim.geo_latitude, 0.0, 100.0))
	if geo_lon_spin != null:
		geo_lon_spin.editable = editable
		geo_lon_spin.set_value_no_signal(clampf(sim.geo_longitude, 0.0, 100.0))
	_update_geography_hint()


## The sliders own the values as soon as "авто" is off. The lat/lon box is
## re-derived at once, so the interface shows the new position immediately and
## the next "Применить климат" uses it.
func _apply_geography_from_controls() -> void:
	if sim.geo_auto:
		return
	if geo_size_spin != null:
		sim.geo_map_size = clampf(float(geo_size_spin.value), 1.0, 100.0)
	if geo_lat_spin != null:
		sim.geo_latitude = clampf(float(geo_lat_spin.value), 0.0, 100.0)
	if geo_lon_spin != null:
		sim.geo_longitude = clampf(float(geo_lon_spin.value), 0.0, 100.0)
	sim.recalculate_geography()
	_update_geography_hint()


## Hint under the controls: the template's own position before the first
## generation, the resulting box afterwards
func _update_geography_hint() -> void:
	if geo_info_label == null:
		return
	var template: String = sim.template_id
	if template_option != null and template_option.selected >= 0:
		var meta: Variant = template_option.get_item_metadata(template_option.selected)
		if meta != null:
			template = str(meta)
	if sim.geo_auto:
		if sim.grid == null:
			geo_info_label.text = "Шаблон «%s»: %s" % [
				HeightmapTemplates.template_name(template), FmgCoordinates.template_hint(template)
			]
		else:
			geo_info_label.text = "Авто: %d %% мира · %s" % [int(round(maxf(sim.geo_map_size, 0.0))), sim.geography_text()]
	else:
		geo_info_label.text = "Вручную: %d %% мира · %s" % [int(round(sim.geo_map_size)), sim.geography_text()]


func apply_generation_options() -> void:
	if seed_edit != null:
		sim.seed_value = seed_edit.text.strip_edges()
		if sim.seed_value.is_empty():
			sim.seed_value = str(randi() % 1000000000)
			seed_edit.text = sim.seed_value
	if template_option != null and template_option.selected >= 0:
		var template_id: Variant = template_option.get_item_metadata(template_option.selected)
		sim.template_id = str(template_id) if template_id != null else "random"
	if density_option != null:
		var d_id: int = density_option.get_selected_id()
		if POINTS_BY_DENSITY.has(d_id):
			sim.cells_desired = POINTS_BY_DENSITY[d_id]
	if map_width_spin != null:
		sim.map_width = float(map_width_spin.value)
	if map_height_spin != null:
		sim.map_height = float(map_height_spin.value)
	if cultures_spin != null:
		sim.cultures_limit = int(cultures_spin.value)
	if cultures_set_option != null and cultures_set_option.selected >= 0:
		var c_set: Variant = cultures_set_option.get_item_metadata(cultures_set_option.selected)
		if c_set != null:
			sim.cultures_set = str(c_set)
	if states_spin != null:
		sim.states_limit = int(states_spin.value)
	if religions_spin != null:
		sim.religions_limit = int(religions_spin.value)
	if provinces_ratio_spin != null:
		sim.provinces_ratio = float(provinces_ratio_spin.value)
	if burgs_check != null:
		sim.burgs_limit = -1 if burgs_check.button_pressed else 1000
	# geography: "auto" lets the template decide, otherwise the sliders win
	if geo_auto_check != null:
		sim.geo_auto = geo_auto_check.button_pressed
	if sim.geo_auto:
		sim.geo_map_size = -1.0
	else:
		_apply_geography_from_controls()
	sim.poles_cache = {}
	if distance_scale_spin != null and view != null:
		view.distance_scale = float(distance_scale_spin.value)


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
	if distance_scale_spin != null:
		distance_scale_spin.set_value_no_signal(view.distance_scale)
	_sync_geography_controls()
	if climate_equator_spin != null:
		climate_equator_spin.set_value_no_signal(sim.climate_equator)
		climate_north_spin.set_value_no_signal(sim.climate_north_pole)
		climate_south_spin.set_value_no_signal(sim.climate_south_pole)
		climate_precip_spin.set_value_no_signal(sim.climate_precipitation)
		for i: int in mini(wind_spins.size(), sim.climate_winds.size()):
			(wind_spins[i] as SpinBox).set_value_no_signal(float(sim.climate_winds[i]))
	if label_mode_option != null:
		label_mode_option.select(view.label_scale_mode)
	if declutter_check != null:
		declutter_check.set_pressed_no_signal(view.label_declutter)
	if label_overlap_check != null:
		label_overlap_check.set_pressed_no_signal(view.label_avoid_overlap)
	if label_min_spin != null:
		label_min_spin.set_value_no_signal(view.label_min_px)
	if label_scale_spin != null:
		label_scale_spin.set_value_no_signal(view.style_label_scale)
	if scale_bar_option != null:
		scale_bar_option.select(0 if view.scale_bar_on_map else 1)
	if vignette_option != null:
		vignette_option.select(0 if view.vignette_on_map else 1)
	for layer: Dictionary in LAYERS:
		var id: String = str(layer["id"])
		if layer_buttons.has(id):
			var pressed: bool = bool(view.get(str(layer["prop"])))
			var button: Button = layer_buttons[id]
			button.set_pressed_no_signal(pressed)
			_refresh_layer_button(button, pressed)


func sync_from_sim() -> void:
	refresh_from_sim()


## Mirrors the interface scale that main.gd actually applied.
func sync_scale_controls(mode: int, value: float) -> void:
	if ui_scale_option == null:
		return
	for index: int in ui_scale_option.item_count:
		var meta: Dictionary = ui_scale_option.get_item_metadata(index)
		if int(meta.get("mode", 0)) != mode:
			continue
		if mode == 0 or is_equal_approx(float(meta.get("scale", 1.0)), value):
			ui_scale_option.select(index)
			return


func _on_theme_changed() -> void:
	if ui_theme != null:
		ui_theme.apply_style(self)
		for root: Control in [menu, trigger_box, export_popup, omnibar]:
			if root != null:
				ui_theme.apply_style(root)


func _on_wind_changed(value: float, index: int) -> void:
	if index >= 0 and index < sim.climate_winds.size():
		sim.climate_winds[index] = value


# ---------------------------------------------------------------------------
# UI Helpers

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


func _spin_row(parent: Control, label_text: String, min_value: float, max_value: float, step: float, value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, label_text, "label")
	var spin := _make_spin(min_value, max_value, step, value)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	spin.value_changed.connect(func(v: float) -> void: on_change.call(v))
	return spin


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


func _color_grid_item(parent: Control, label_text: String, property: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var lbl := _label(row, label_text, "label")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := ColorPickerButton.new()
	picker.color = view.get(property)
	picker.custom_minimum_size = Vector2(40, 22)
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
