class_name FmgOverviewDialogs
extends Control
## Draggable overview windows (Burgs / States / Rivers / Markers / Markets /
## Diplomacy) in the Apple Liquid Glass dialog style: frosted glass panel,
## specular rim, macOS-style header, search field and scrollable data table.

const WINDOW_SIZE := Vector2(620, 450)

var sim: FmgSim = null
var view: MapView = null
var ui_theme: FmgUiTheme = null
var window: PanelContainer = null
var title_label: Label = null
var filter_edit: LineEdit = null
var table_grid: GridContainer = null
var table_scroll: ScrollContainer = null
var info_label: Label = null
var _columns: Array = []
var _rows: Array = []
var _dragging: bool = false


func setup(sim_ref: FmgSim, view_ref: MapView, theme_ref: FmgUiTheme) -> void:
	sim = sim_ref
	view = view_ref
	ui_theme = theme_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	window = PanelContainer.new()
	window.visible = false
	window.custom_minimum_size = WINDOW_SIZE
	window.set_meta("fmg", "panel")
	add_child(window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	window.add_child(box)

	# Window header (macOS style frosted glass bar with grab handle & close pill)
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.set_meta("fmg", "dragbar")
	box.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header.add_child(header_row)

	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_override("font", FmgUiTheme.font_ui())
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	header_row.add_child(title_label)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Закрыть окно (Esc)"
	close.custom_minimum_size = Vector2(26, 26)
	close.set_meta("fmg", "button")
	close.pressed.connect(close_window)
	header_row.add_child(close)
	header.gui_input.connect(_on_header_input)

	# Spotlight-style search pill
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "🔍 Фильтр по названию…"
	filter_edit.set_meta("fmg", "field")
	filter_edit.add_theme_font_override("font", FmgUiTheme.font_ui())
	filter_edit.text_changed.connect(_apply_filter)
	box.add_child(filter_edit)

	# Table card container
	var table_card := PanelContainer.new()
	table_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_card.set_meta("fmg", "card")
	box.add_child(table_card)

	table_scroll = ScrollContainer.new()
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	table_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_scroll.set_meta("fmg", "scroll")
	table_card.add_child(table_scroll)

	table_grid = GridContainer.new()
	table_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_grid.add_theme_constant_override("h_separation", 14)
	table_grid.add_theme_constant_override("v_separation", 4)
	table_scroll.add_child(table_grid)

	info_label = Label.new()
	info_label.set_meta("fmg", "tip")
	info_label.add_theme_font_override("font", FmgUiTheme.font_ui())
	info_label.add_theme_font_size_override("font_size", 11)
	box.add_child(info_label)

	ui_theme.changed.connect(_restyle)
	_restyle()


func _restyle() -> void:
	if ui_theme != null and window != null:
		ui_theme.apply_style(window)


func open(kind: String) -> void:
	if sim == null or sim.pack == null:
		return
	match kind:
		"burgs":
			_build_burgs()
		"states":
			_build_states()
		"rivers":
			_build_rivers()
		"markers":
			_build_markers()
		"markets":
			_build_markets()
		"diplomacy":
			_build_diplomacy()
		_:
			return
	window.position = Vector2(380, 50)
	window.visible = true
	filter_edit.text = ""
	_apply_filter("")


func close_window() -> void:
	window.visible = false


func is_open() -> bool:
	return window != null and window.visible


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var size: Vector2 = get_viewport_rect().size
		window.position = Vector2(
			clampf(window.position.x + motion.relative.x, 0.0, maxf(size.x - 80.0, 0.0)),
			clampf(window.position.y + motion.relative.y, 0.0, maxf(size.y - 60.0, 0.0)))


# ---------------------------------------------------------------------------
# Tables

func _start_table(columns: Array) -> void:
	_columns = columns
	_rows = []
	for child in table_grid.get_children():
		child.queue_free()
	table_grid.columns = columns.size()
	for column: String in columns:
		var label := Label.new()
		label.text = column
		label.set_meta("fmg", "table_header")
		label.add_theme_font_override("font", FmgUiTheme.font_ui())
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
		table_grid.add_child(label)


func _add_row(values: Array, sort_key: float = 0.0, name_key: String = "") -> void:
	_rows.append({"values": values, "sort_key": sort_key, "name": name_key})


func _finish_table(sort_descending: bool = true) -> void:
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["sort_key"]) > float(b["sort_key"]) if sort_descending else float(a["sort_key"]) < float(b["sort_key"])
	)
	_apply_filter("")


func _apply_filter(_query: String) -> void:
	for child in table_grid.get_children():
		if child.get_index() < _columns.size():
			continue
		child.queue_free()
	var needle: String = filter_edit.text.strip_edges().to_lower()
	if needle.begins_with("🔍"):
		needle = needle.substr(1).strip_edges()
	var shown: int = 0
	for row_value: Variant in _rows:
		var row: Dictionary = row_value
		if not needle.is_empty() and not str(row["name"]).to_lower().contains(needle):
			continue
		var col_idx: int = 0
		for value: Variant in row["values"]:
			var label := Label.new()
			var val_str: String = str(value)
			label.text = val_str
			label.set_meta("fmg", "label")
			# Use mono font for numbers and short codes, font_ui for names
			var is_numeric: bool = val_str.is_valid_float() or val_str.is_valid_int()
			label.add_theme_font_override("font", FmgUiTheme.mono() if is_numeric else FmgUiTheme.font_ui())
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", FmgUiTheme.TEXT_COLOR)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			table_grid.add_child(label)
			col_idx += 1
		shown += 1
	info_label.text = "Показано строк: %d из %d" % [shown, _rows.size()]


func _table_name(table: Array, entry_id: int) -> String:
	if entry_id <= 0 or entry_id >= table.size() or table[entry_id] == null:
		return "—"
	return str((table[entry_id] as Dictionary).get("name", "—"))


func _build_burgs() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "🏙️ Обзор городов"
	_start_table(["Город", "Государство", "Культура", "Насел., тыс.", "Столица", "Порт"])
	for burg_value: Variant in pack.burgs:
		if burg_value == null:
			continue
		var burg: Dictionary = burg_value
		_add_row([
			str(burg.get("name", "—")),
			_table_name(pack.states, int(burg.get("state", 0))),
			_table_name(pack.cultures, int(burg.get("culture", 0))),
			"%.1f" % float(burg.get("population", 0.0)),
			"★" if int(burg.get("capital", 0)) == 1 else "",
			"⚓" if int(burg.get("port", 0)) != 0 else ""
		], float(burg.get("population", 0.0)), str(burg.get("name", "")))
	_finish_table()


func _build_states() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "🚩 Обзор государств"
	_start_table(["Государство", "Форма правления", "Столица", "Городов", "Площ., тыс. км²", "Насел., млн"])
	var km_per_px: float = view.distance_scale if view != null else 3.0
	var km2_per_px2: float = km_per_px * km_per_px
	for state_value: Variant in pack.states:
		if state_value == null or int((state_value as Dictionary).get("i", 0)) == 0:
			continue
		var state: Dictionary = state_value
		var area: float = 0.0
		var population: float = 0.0
		var burgs_count: int = 0
		for burg_value: Variant in pack.burgs:
			if burg_value == null:
				continue
			var burg: Dictionary = burg_value
			if int(burg.get("state", 0)) != int(state["i"]):
				continue
			burgs_count += 1
			population += float(burg.get("population", 0.0)) * 1000.0
		for i: int in pack.cell_count():
			if pack.state[i] == int(state["i"]):
				area += pack.area[i] if i < pack.area.size() else 0.0
				population += float(pack.pop[i]) * 1000.0
		var capital: String = "—"
		var capital_id: int = int(state.get("capital", 0))
		if capital_id > 0 and capital_id < pack.burgs.size() and pack.burgs[capital_id] != null:
			capital = str((pack.burgs[capital_id] as Dictionary).get("name", "—"))
		_add_row([
			str(state.get("fullName", state.get("name", "—"))),
			str(state.get("form", "—")),
			capital,
			str(burgs_count),
			"%.1f" % (area * km2_per_px2 / 1000.0),
			"%.2f" % (population / 1000000.0)
		], population, str(state.get("name", "")))
	_finish_table()


func _build_rivers() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "🌊 Обзор рек"
	_start_table(["Река", "Тип", "Длина, км", "Ширина, усл.", "Ячеек"])
	var km_per_px: float = view.distance_scale if view != null else 3.0
	for river_value: Variant in pack.rivers:
		if river_value == null:
			continue
		var river: Dictionary = river_value
		var name_v: String = str(river.get("name", "—"))
		if name_v.is_empty():
			name_v = "—"
		var cells_count: int = 0
		var cells_value: Variant = river.get("cells", [])
		if cells_value is PackedInt32Array:
			cells_count = (cells_value as PackedInt32Array).size()
		elif cells_value is Array:
			cells_count = (cells_value as Array).size()
		_add_row([
			name_v,
			str(river.get("type", "—")),
			"%.0f" % (float(river.get("length", 0.0)) * km_per_px),
			"%.2f" % float(river.get("width", 0.0)),
			str(cells_count)
		], float(river.get("length", 0.0)), name_v)
	_finish_table()


func _build_markers() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "📍 Обзор маркеров"
	_start_table(["Тип", "№", "X", "Y", "Описание"])
	for marker_value: Variant in pack.markers:
		var marker: Dictionary = marker_value
		var mtype: String = str(marker.get("type", "—"))
		_add_row([
			mtype,
			str(marker.get("i", 0)),
			"%.0f" % float(marker.get("x", 0.0)),
			"%.0f" % float(marker.get("y", 0.0)),
			str(marker.get("legend", ""))
		], float(marker.get("y", 0.0)), mtype)
	_finish_table(false)


func _build_markets() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "⚖️ Обзор рынков"
	_start_table(["Рынок", "Центр", "Товаров", "Сделок", "Казна"])
	var deals_by_market: Dictionary = {}
	var tax_by_market: Dictionary = {}
	for deal_value: Variant in pack.deals:
		var deal: Dictionary = deal_value
		var seller: int = int(deal.get("seller", 0))
		deals_by_market[seller] = int(deals_by_market.get(seller, 0)) + 1
		tax_by_market[seller] = float(tax_by_market.get(seller, 0.0)) + float(deal.get("tax", 0.0))
	for market_value: Variant in pack.markets:
		var market: Dictionary = market_value
		var burg_id: int = int(market.get("centerBurgId", 0))
		var center: String = "—"
		if burg_id > 0 and burg_id < pack.burgs.size() and pack.burgs[burg_id] != null:
			center = str((pack.burgs[burg_id] as Dictionary).get("name", "—"))
		_add_row([
			center,
			center,
			str((market.get("goods", {}) as Dictionary).size()),
			str(deals_by_market.get(int(market.get("i", 0)), 0)),
			"%.1f" % float(market.get("treasury", tax_by_market.get(int(market.get("i", 0)), 0.0)))
		], float((market.get("goods", {}) as Dictionary).size()), center)
	_finish_table()


func _build_diplomacy() -> void:
	var pack: FmgGraph = sim.pack
	title_label.text = "🤝 Дипломатия"
	_start_table(["Государство", "Отношения с соседями и державами"])
	for state_value: Variant in pack.states:
		var state: Dictionary = state_value
		if state == null or int(state.get("i", 0)) == 0:
			continue
		var parts: Array = []
		var matrix: Array = state.get("diplomacy", [])
		for other: int in matrix.size():
			var relation: String = str(matrix[other])
			if other == int(state["i"]) or relation == "x" or relation.is_empty():
				continue
			if other >= pack.states.size() or pack.states[other] == null:
				continue
			var other_name: String = str((pack.states[other] as Dictionary).get("name", "?"))
			parts.append("%s — %s" % [other_name, _relation_title(relation)])
		_add_row([
			str(state.get("fullName", state.get("name", "—"))),
			", ".join(parts) if not parts.is_empty() else "нет связей"
		], float(state.get("cells", 0)), str(state.get("name", "")))
	_finish_table()


func _relation_title(relation: String) -> String:
	match relation:
		"Ally":
			return "союз"
		"Friendly":
			return "дружба"
		"Neutral":
			return "нейтралитет"
		"Suspicion":
			return "подозрение"
		"Rival":
			return "соперничество"
		"Enemy":
			return "вражда"
		"Unknown":
			return "нет данных"
		"Vassal":
			return "вассал"
		"Suzerain":
			return "сюзерен"
		"War":
			return "война"
	return relation
