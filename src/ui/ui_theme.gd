class_name FmgUiTheme
extends RefCounted
## FMG-styled UI theme: derives the whole dialog palette from one theme color
## and a transparency value, exactly like the original's Options ▸ Theme color /
## Transparency controls (see options-tab.ts: changeDialogsTheme).

signal changed

const DEFAULT_THEME_COLOR := Color("#997787") # pale magenta, as in the original
const DEFAULT_TRANSPARENCY := 5.0 # percent of transparency, original default
const BORDER_COLOR := Color("#5e4fa2") # dialog outline color from index.css
const TEXT_COLOR := Color("#31272c")
const TIP_COLOR := Color("#444444")

var theme_color: Color = DEFAULT_THEME_COLOR
var transparency: float = DEFAULT_TRANSPARENCY
var ui_scale: float = 1.0

# cached palette (named like the original CSS variables)
var bg_main := Color.WHITE
var bg_lighter := Color.WHITE
var bg_light := Color.WHITE
var light_solid := Color.WHITE
var dark_solid := Color.WHITE
var header := Color.WHITE
var header_active := Color.WHITE
var bg_disabled := Color.WHITE
var bg_dialogs := Color.WHITE

static var _mono: Font = null


## Monospace font matching the original UI (Consolas in the browser).
static func mono() -> Font:
	if _mono == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray([
			"Consolas", "Menlo", "DejaVu Sans Mono", "Liberation Mono",
			"Noto Sans Mono", "Courier New", "Monospace"
		])
		_mono = system
	return _mono


func _init(color: Color = DEFAULT_THEME_COLOR, transparency_value: float = DEFAULT_TRANSPARENCY) -> void:
	set_theme(color, transparency_value)


func set_theme(color: Color, transparency_value: float) -> void:
	theme_color = color
	transparency = clampf(transparency_value, 0.0, 100.0)
	var alpha: float = (100.0 - transparency) / 100.0
	var alpha_reduced: float = minf(alpha + 0.3, 1.0)
	var hsl: Array = _to_hsl(theme_color)
	var h: float = float(hsl[0])
	var s: float = float(hsl[1])
	var l: float = float(hsl[2])
	bg_main = _from_hsl(h, s, l, alpha)
	bg_lighter = _from_hsl(h, s, l + 0.02, alpha)
	bg_light = _from_hsl(h, s - 0.02, l + 0.06, alpha)
	light_solid = _from_hsl(h, s + 0.01, l + 0.05, 1.0)
	dark_solid = _from_hsl(h, s, l - 0.2, 1.0)
	header = _from_hsl(h, s, l - 0.03, alpha_reduced)
	header_active = _from_hsl(h, s, l - 0.09, alpha_reduced)
	bg_disabled = _from_hsl(h, s - 0.04, l + 0.09, 1.0)
	bg_dialogs = _from_hsl(0.0, 0.0, 0.98, alpha)
	changed.emit()


func set_hue(hue: float) -> void:
	var hsl := _to_hsl(theme_color)
	set_theme(_from_hsl(clampf(hue, 0.0, 359.0), float(hsl[1]), float(hsl[2]), 1.0), transparency)


static func _to_hsl(color: Color) -> Array:
	var maxc: float = maxf(color.r, maxf(color.g, color.b))
	var minc: float = minf(color.r, minf(color.g, color.b))
	var l: float = (maxc + minc) / 2.0
	if is_equal_approx(maxc, minc):
		return [0.0, 0.0, l]
	var d: float = maxc - minc
	var s: float = d / (1.0 - absf(2.0 * l - 1.0)) if l > 0.0 and l < 1.0 else 0.0
	var h: float
	if is_equal_approx(maxc, color.r):
		h = fmod((color.g - color.b) / d, 6.0)
	elif is_equal_approx(maxc, color.g):
		h = (color.b - color.r) / d + 2.0
	else:
		h = (color.r - color.g) / d + 4.0
	h /= 6.0
	if h < 0.0:
		h += 1.0
	return [h * 360.0, s, l]


static func _from_hsl(h_deg: float, s: float, l: float, alpha: float) -> Color:
	var h: float = fmod(clampf(h_deg, 0.0, 360.0) / 360.0, 1.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	var c: Color
	if s <= 0.0:
		c = Color(l, l, l)
	else:
		var q: float = l * (1.0 + s) if l < 0.5 else l + s - l * s
		var p: float = 2.0 * l - q
		c = Color(_hue_to_rgb(p, q, h + 1.0 / 3.0), _hue_to_rgb(p, q, h), _hue_to_rgb(p, q, h - 1.0 / 3.0))
	c.a = clampf(alpha, 0.0, 1.0)
	return c


static func _hue_to_rgb(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p


# ---------------------------------------------------------------------------
# StyleBoxes. Controls are tagged with set_meta("fmg", kind) so a theme change
# can restyle the whole tree without rebuilding it.

func flat(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 0, h_margin: float = 6.0, v_margin: float = 3.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = h_margin
	box.content_margin_right = h_margin
	box.content_margin_top = v_margin
	box.content_margin_bottom = v_margin
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	return box


func apply_style(node: Control) -> void:
	var kind: String = str(node.get_meta("fmg", ""))
	if kind != "":
		_style_control(node, kind)
	for child in node.get_children():
		if child is Control:
			apply_style(child as Control)


func _style_control(node: Control, kind: String) -> void:
	match kind:
		"panel":
			if node is PanelContainer:
				node.add_theme_stylebox_override("panel", flat(bg_light, BORDER_COLOR, 1))
		"dragbar":
			if node is PanelContainer:
				node.add_theme_stylebox_override("panel", flat(dark_solid))
		"button":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(bg_main))
				node.add_theme_stylebox_override("hover", flat(header_active))
				node.add_theme_stylebox_override("pressed", flat(header_active))
				node.add_theme_stylebox_override("disabled", flat(bg_disabled))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_color_override("font_disabled_color", Color(0.4, 0.35, 0.4))
				node.add_theme_color_override("icon_normal_color", TEXT_COLOR)
				node.add_theme_color_override("icon_hover_color", Color.WHITE)
		"tab":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(bg_main, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("hover", flat(header_active, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("pressed", flat(header_active, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("focused", flat(header))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
		"tab_active":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(header, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("hover", flat(header, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("pressed", flat(header_active, Color.TRANSPARENT, 0, 0, 2.0, 3.0))
				node.add_theme_stylebox_override("focused", flat(header))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
		"sticked":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 2.0, 2.0))
				node.add_theme_stylebox_override("hover", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 2.0, 2.0))
				node.add_theme_stylebox_override("pressed", flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 2.0, 2.0))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", FmgUiTheme.mono())
		"accent":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(header))
				node.add_theme_stylebox_override("hover", flat(header_active))
				node.add_theme_stylebox_override("pressed", flat(header_active))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
		"layer":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(bg_main))
				node.add_theme_stylebox_override("hover", flat(header_active))
				node.add_theme_stylebox_override("pressed", flat(header_active))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
		"layer_active":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", flat(header))
				node.add_theme_stylebox_override("hover", flat(header))
				node.add_theme_stylebox_override("pressed", flat(header_active))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
		"field":
			if node is LineEdit:
				node.add_theme_stylebox_override("normal", flat(Color(1, 1, 1, 0.65)))
				node.add_theme_stylebox_override("focus", flat(Color(1, 1, 1, 0.85)))
				node.add_theme_stylebox_override("read_only", flat(bg_disabled))
			elif node is SpinBox:
				node.add_theme_stylebox_override("up_background", flat(Color.TRANSPARENT))
				node.add_theme_stylebox_override("down_background", flat(Color.TRANSPARENT))
				var line: LineEdit = (node as SpinBox).get_line_edit()
				line.add_theme_stylebox_override("normal", flat(Color(1, 1, 1, 0.65)))
				line.add_theme_stylebox_override("focus", flat(Color(1, 1, 1, 0.85)))
		"select":
			if node is OptionButton:
				node.add_theme_stylebox_override("normal", flat(Color(1, 1, 1, 0.65)))
				node.add_theme_stylebox_override("hover", flat(Color(1, 1, 1, 0.8)))
				node.add_theme_stylebox_override("pressed", flat(Color(1, 1, 1, 0.8)))
				node.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", TEXT_COLOR)
				node.add_theme_color_override("font_pressed_color", TEXT_COLOR)
				node.add_theme_color_override("icon_normal_color", TEXT_COLOR)
		"check":
			if node is BaseButton:
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", TEXT_COLOR)
				node.add_theme_color_override("font_pressed_color", TEXT_COLOR)
				node.add_theme_color_override("icon_normal_color", TEXT_COLOR)
				node.add_theme_color_override("icon_hover_color", TEXT_COLOR)
				node.add_theme_color_override("icon_pressed_color", TEXT_COLOR)
		"slider":
			if node is Slider:
				node.add_theme_stylebox_override("slider", flat(light_solid, dark_solid, 1, 2))
				node.add_theme_stylebox_override("grabber_area", flat(header))
				node.add_theme_stylebox_override("grabber_area_highlight", flat(header_active))
				var grabber := flat(light_solid, dark_solid, 1, 2)
				grabber.content_margin_left = 1.0
				grabber.content_margin_right = 1.0
				node.add_theme_stylebox_override("grabber_stylebox", flat(light_solid, dark_solid, 1, 2))
		"label":
			if node is Label:
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_font_override("font", FmgUiTheme.mono())
		"tip":
			if node is Label:
				node.add_theme_color_override("font_color", TIP_COLOR)
				node.add_theme_font_override("font", FmgUiTheme.mono())
		"sep":
			if node is Label:
				node.add_theme_color_override("font_color", dark_solid)
				node.add_theme_font_override("font", FmgUiTheme.mono())
		"scroll":
			if node is ScrollContainer:
				node.add_theme_stylebox_override("panel", flat(Color.TRANSPARENT))
		"table_header":
			if node is Label:
				node.add_theme_color_override("font_color", dark_solid)
				node.add_theme_font_override("font", FmgUiTheme.mono())
