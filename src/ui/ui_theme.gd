class_name FmgUiTheme
extends RefCounted
## Apple-style "Liquid Glass" (Glassmorphism) UI theme:
## Translucent frosted glass materials, specular rim highlights, smooth continuous
## rounded corners, diffused elevation shadows, modern San Francisco / system sans-serif
## typography, and vibrant dynamic accent colors derived from theme_color.
##
## Text rendering is configured for sharpness: the fonts are hinted and snapped to
## whole pixels (blurry, subpixel-positioned glyphs on a translucent panel were the
## main readability complaint), and the panels keep enough contrast to stay legible
## in front of the map.

signal changed

# Apple system accent defaults
const DEFAULT_THEME_COLOR := Color("#4b70f5") # Apple vibrant blue/indigo
const DEFAULT_TRANSPARENCY := 8.0 # percent of transparency for frosted glass
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.22) # specular glass rim
const TEXT_COLOR := Color("#f7f8fb") # crisp modern readable text
const TIP_COLOR := Color("#c2c9d6") # muted but still readable gray for tips/subtitles
const HEADER_COLOR := Color("#ffffff")
const BASE_FONT_SIZE := 13
const SMALL_FONT_SIZE := 12

var theme_color: Color = DEFAULT_THEME_COLOR
var transparency: float = DEFAULT_TRANSPARENCY
var ui_scale: float = 1.0

# Material palettes (Liquid Glass)
var bg_panel := Color.WHITE
var bg_card := Color.WHITE
var bg_dock := Color.WHITE
var bg_button := Color.WHITE
var bg_button_hover := Color.WHITE
var bg_button_pressed := Color.WHITE
var bg_tab_active := Color.WHITE
var bg_input := Color.WHITE
var bg_input_focus := Color.WHITE
var border_glass := Color.WHITE
var border_subtle := Color.WHITE
var accent_main := Color.WHITE
var accent_hover := Color.WHITE
var accent_active := Color.WHITE
var accent_layer := Color.WHITE
var accent_layer_hover := Color.WHITE
var accent_glow := Color.WHITE
var accent_glow_strong := Color.WHITE

# Legacy compatibility colors
var bg_main := Color.WHITE
var bg_lighter := Color.WHITE
var bg_light := Color.WHITE
var light_solid := Color.WHITE
var dark_solid := Color.WHITE
var header := Color.WHITE
var header_active := Color.WHITE
var bg_disabled := Color.WHITE
var bg_dialogs := Color.WHITE

static var _ui_font: Font = null
static var _mono_font: Font = null


## Modern Apple-style sans-serif font for UI elements (SF Pro, Inter, system-ui).
static func font_ui() -> Font:
	if _ui_font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray([
			"SF Pro Display", "SF Pro Text", "-apple-system", "BlinkMacSystemFont",
			"Inter", "Helvetica Neue", "Segoe UI", "DejaVu Sans", "Noto Sans", "system-ui", "sans-serif"
		])
		# Interface text is never rotated or scaled by a camera, so hinted glyphs
		# snapped to whole pixels are the crispest option (subpixel positioning
		# makes small bold text look soft on translucent panels).
		system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		system.hinting = TextServer.HINTING_LIGHT
		if ThemeDB.fallback_font != null:
			system.fallbacks = [ThemeDB.fallback_font]
		_ui_font = system
	return _ui_font


## Monospace font for seeds, numbers, coordinates and data tables.
static func mono() -> Font:
	if _mono_font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray([
			"SF Mono", "Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono",
			"Noto Sans Mono", "Courier New", "Monospace"
		])
		system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		system.hinting = TextServer.HINTING_LIGHT
		if ThemeDB.fallback_font != null:
			system.fallbacks = [ThemeDB.fallback_font]
		_mono_font = system
	return _mono_font


func _init(color: Color = DEFAULT_THEME_COLOR, transparency_value: float = DEFAULT_TRANSPARENCY) -> void:
	set_theme(color, transparency_value)


func set_theme(color: Color, transparency_value: float) -> void:
	theme_color = color
	transparency = clampf(transparency_value, 0.0, 90.0)

	# Frosted glass opacity factor (kept high enough for text to stay readable on
	# top of a busy map)
	var base_alpha: float = clampf(1.0 - (transparency / 100.0) * 0.55, 0.62, 0.97)

	# Deep Apple dark frosted glass tint, infused with subtle theme hue
	var dark_glass_base := Color(0.10, 0.12, 0.16, base_alpha)
	var tint := Color(theme_color.r * 0.25, theme_color.g * 0.25, theme_color.b * 0.25, base_alpha)
	bg_panel = dark_glass_base.lerp(tint, 0.15)
	bg_dialogs = bg_panel
	bg_light = bg_panel

	# Glass highlight rim: crisp specular reflection
	border_glass = Color(1.0, 1.0, 1.0, 0.24)
	border_subtle = Color(1.0, 1.0, 1.0, 0.10)

	# Inner grouping cards
	bg_card = Color(1.0, 1.0, 1.0, 0.05)
	bg_dock = Color(0.06, 0.08, 0.11, minf(base_alpha + 0.1, 0.95))

	# Vibrant Liquid Glass buttons
	bg_button = Color(1.0, 1.0, 1.0, 0.08)
	bg_button_hover = Color(1.0, 1.0, 1.0, 0.18)
	bg_button_pressed = Color(1.0, 1.0, 1.0, 0.28)
	bg_disabled = Color(1.0, 1.0, 1.0, 0.03)

	# Input fields
	bg_input = Color(0.0, 0.0, 0.0, 0.32)
	bg_input_focus = Color(0.0, 0.0, 0.0, 0.48)

	# Active tab segment
	bg_tab_active = Color(1.0, 1.0, 1.0, 0.18)

	# Vibrant Apple system accent
	accent_main = Color(theme_color.r, theme_color.g, theme_color.b, 0.88)
	accent_hover = accent_main.lightened(0.14)
	accent_active = accent_main.darkened(0.14)
	accent_glow = Color(theme_color.r, theme_color.g, theme_color.b, 0.42)
	accent_glow_strong = Color(theme_color.r, theme_color.g, theme_color.b, 0.65)

	# Active layer chip
	accent_layer = Color(theme_color.r, theme_color.g, theme_color.b, 0.46)
	accent_layer_hover = Color(theme_color.r, theme_color.g, theme_color.b, 0.68)

	# Legacy variables for compatibility
	bg_main = bg_button
	bg_lighter = bg_button_hover
	light_solid = Color(0.95, 0.96, 0.98)
	dark_solid = Color(0.85, 0.88, 0.95)
	header = accent_main
	header_active = accent_hover

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
# StyleBox factory for Liquid Glass aesthetic

func glass_box(
	bg: Color,
	border: Color = Color.TRANSPARENT,
	border_width: int = 0,
	radius: int = 12,
	h_margin: float = 10.0,
	v_margin: float = 6.0,
	shadow_sz: int = 0,
	shadow_off: Vector2 = Vector2.ZERO,
	shadow_col: Color = Color(0, 0, 0, 0.28)
) -> StyleBoxFlat:
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
	if shadow_sz > 0:
		box.shadow_color = shadow_col
		box.shadow_size = shadow_sz
		box.shadow_offset = shadow_off
	box.anti_aliasing = true
	box.anti_aliasing_size = 1.0
	return box


func flat(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 0, h_margin: float = 6.0, v_margin: float = 3.0) -> StyleBoxFlat:
	return glass_box(bg, border, border_width, radius, h_margin, v_margin)


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
				# Floating frosted glass window (Apple squircle, specular rim, deep shadow)
				node.add_theme_stylebox_override("panel", glass_box(
					bg_panel, border_glass, 1, 18, 14.0, 14.0, 26, Vector2(0, 8), Color(0, 0, 0, 0.40)
				))
		"card":
			if node is PanelContainer:
				# Inner grouping card with subtle luminous glass fill
				node.add_theme_stylebox_override("panel", glass_box(
					bg_card, border_subtle, 1, 12, 12.0, 10.0
				))
		"dock":
			if node is PanelContainer:
				# Apple bottom dock container
				node.add_theme_stylebox_override("panel", glass_box(
					bg_dock, border_glass, 1, 14, 8.0, 8.0, 12, Vector2(0, 4), Color(0, 0, 0, 0.28)
				))
		"segmented":
			if node is PanelContainer:
				# Capsule segmented control container
				node.add_theme_stylebox_override("panel", glass_box(
					Color(0.0, 0.0, 0.0, 0.32), border_subtle, 1, 12, 4.0, 4.0
				))
		"dragbar":
			if node is PanelContainer:
				node.add_theme_stylebox_override("panel", glass_box(
					Color.TRANSPARENT, Color.TRANSPARENT, 0, 18, 8.0, 4.0
				))
		"pill":
			if node is Button:
				# Dynamic Island / Floating pill button
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(bg_panel, border_glass, 1, 20, 14.0, 8.0, 16, Vector2(0, 5), Color(0, 0, 0, 0.35)))
				node.add_theme_stylebox_override("hover", glass_box(bg_button_hover, Color(1, 1, 1, 0.45), 1, 20, 14.0, 8.0, 20, Vector2(0, 6), Color(0, 0, 0, 0.42)))
				node.add_theme_stylebox_override("pressed", glass_box(bg_button_pressed, Color(1, 1, 1, 0.55), 1, 20, 14.0, 8.0, 8, Vector2(0, 2)))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"button":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(bg_button, border_subtle, 1, 10, 10.0, 6.0))
				node.add_theme_stylebox_override("hover", glass_box(bg_button_hover, border_glass, 1, 10, 10.0, 6.0, 6, Vector2(0, 2), Color(0, 0, 0, 0.22)))
				node.add_theme_stylebox_override("pressed", glass_box(bg_button_pressed, border_glass, 1, 10, 10.0, 6.0))
				node.add_theme_stylebox_override("disabled", glass_box(bg_disabled, Color(1, 1, 1, 0.04), 1, 10, 10.0, 6.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_color_override("font_disabled_color", Color(0.5, 0.54, 0.62, 0.6))
				node.add_theme_color_override("icon_normal_color", TEXT_COLOR)
				node.add_theme_color_override("icon_hover_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"tab":
			if node is Button:
				# Unselected segment
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8, 8.0, 6.0))
				node.add_theme_stylebox_override("hover", glass_box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.14), 1, 8, 8.0, 6.0))
				node.add_theme_stylebox_override("pressed", glass_box(Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.26), 1, 8, 8.0, 6.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color(0.76, 0.80, 0.88))
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"tab_active":
			if node is Button:
				# Selected elevated glass segment
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(bg_tab_active, border_glass, 1, 8, 8.0, 6.0, 6, Vector2(0, 2), Color(0, 0, 0, 0.24)))
				node.add_theme_stylebox_override("hover", glass_box(bg_tab_active, Color(1, 1, 1, 0.40), 1, 8, 8.0, 6.0, 8, Vector2(0, 2), Color(0, 0, 0, 0.28)))
				node.add_theme_stylebox_override("pressed", glass_box(Color(1, 1, 1, 0.25), border_glass, 1, 8, 8.0, 6.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"sticked":
			if node is Button:
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(bg_button, border_subtle, 1, 9, 8.0, 6.0))
				node.add_theme_stylebox_override("hover", glass_box(bg_button_hover, border_glass, 1, 9, 8.0, 6.0, 6, Vector2(0, 2), Color(0, 0, 0, 0.20)))
				node.add_theme_stylebox_override("pressed", glass_box(bg_button_pressed, border_glass, 1, 9, 8.0, 6.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		"accent":
			if node is Button:
				# Apple vibrant call-to-action button
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(accent_main, Color(1, 1, 1, 0.38), 1, 10, 12.0, 7.0, 10, Vector2(0, 3), accent_glow))
				node.add_theme_stylebox_override("hover", glass_box(accent_hover, Color(1, 1, 1, 0.60), 1, 10, 12.0, 7.0, 14, Vector2(0, 4), accent_glow_strong))
				node.add_theme_stylebox_override("pressed", glass_box(accent_active, Color(1, 1, 1, 0.30), 1, 10, 12.0, 7.0, 4, Vector2(0, 1)))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"layer":
			if node is Button:
				# Inactive layer toggle chip
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(bg_card, border_subtle, 1, 8, 8.0, 5.0))
				node.add_theme_stylebox_override("hover", glass_box(bg_button_hover, border_glass, 1, 8, 8.0, 5.0))
				node.add_theme_stylebox_override("pressed", glass_box(bg_button_pressed, border_glass, 1, 8, 8.0, 5.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color(0.74, 0.78, 0.86))
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		"layer_active":
			if node is Button:
				# Active illuminated layer toggle chip
				node.focus_mode = Control.FOCUS_NONE
				node.add_theme_stylebox_override("normal", glass_box(accent_layer, Color(1, 1, 1, 0.40), 1, 8, 8.0, 5.0, 6, Vector2(0, 1), accent_glow * 0.7))
				node.add_theme_stylebox_override("hover", glass_box(accent_layer_hover, Color(1, 1, 1, 0.60), 1, 8, 8.0, 5.0, 8, Vector2(0, 2), accent_glow))
				node.add_theme_stylebox_override("pressed", glass_box(accent_main, Color(1, 1, 1, 0.50), 1, 8, 8.0, 5.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		"field":
			if node is LineEdit:
				node.add_theme_stylebox_override("normal", glass_box(bg_input, border_subtle, 1, 8, 8.0, 5.0))
				node.add_theme_stylebox_override("focus", glass_box(bg_input_focus, accent_main, 1, 8, 8.0, 5.0, 6, Vector2.ZERO, accent_glow))
				node.add_theme_stylebox_override("read_only", glass_box(bg_disabled, Color(1, 1, 1, 0.05), 1, 8, 8.0, 5.0))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_placeholder_color", Color(0.55, 0.60, 0.68, 0.65))
				node.add_theme_font_override("font", mono())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
			elif node is SpinBox:
				node.add_theme_stylebox_override("up_background", glass_box(Color.TRANSPARENT))
				node.add_theme_stylebox_override("down_background", glass_box(Color.TRANSPARENT))
				var line: LineEdit = (node as SpinBox).get_line_edit()
				line.add_theme_stylebox_override("normal", glass_box(bg_input, border_subtle, 1, 8, 8.0, 5.0))
				line.add_theme_stylebox_override("focus", glass_box(bg_input_focus, accent_main, 1, 8, 8.0, 5.0, 6, Vector2.ZERO, accent_glow))
				line.add_theme_color_override("font_color", Color.WHITE)
				line.add_theme_font_override("font", mono())
				line.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"select":
			if node is OptionButton:
				node.add_theme_stylebox_override("normal", glass_box(bg_button, border_subtle, 1, 8, 10.0, 5.0))
				node.add_theme_stylebox_override("hover", glass_box(bg_button_hover, border_glass, 1, 8, 10.0, 5.0))
				node.add_theme_stylebox_override("pressed", glass_box(bg_button_pressed, border_glass, 1, 8, 10.0, 5.0))
				node.add_theme_stylebox_override("focus", glass_box(Color.TRANSPARENT))
				node.add_theme_color_override("font_color", Color.WHITE)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_color_override("icon_normal_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"check":
			if node is BaseButton:
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_color_override("font_hover_color", Color.WHITE)
				node.add_theme_color_override("font_pressed_color", Color.WHITE)
				node.add_theme_color_override("icon_normal_color", TEXT_COLOR)
				node.add_theme_color_override("icon_hover_color", Color.WHITE)
				node.add_theme_color_override("icon_pressed_color", Color.WHITE)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"slider":
			if node is Slider:
				node.add_theme_stylebox_override("slider", glass_box(Color(1, 1, 1, 0.16), Color.TRANSPARENT, 0, 3, 0.0, 0.0))
				node.add_theme_stylebox_override("grabber_area", glass_box(accent_main, Color.TRANSPARENT, 0, 3, 0.0, 0.0))
				node.add_theme_stylebox_override("grabber_area_highlight", glass_box(accent_hover, Color.TRANSPARENT, 0, 3, 0.0, 0.0))
				node.add_theme_stylebox_override("grabber_stylebox", glass_box(Color(1, 1, 1, 0.95), Color(0, 0, 0, 0.25), 1, 6, 2.0, 2.0, 4, Vector2(0, 1), Color(0, 0, 0, 0.35)))
		"label":
			if node is Label:
				node.add_theme_color_override("font_color", TEXT_COLOR)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"section_header":
			if node is Label:
				node.add_theme_color_override("font_color", HEADER_COLOR)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"tip":
			if node is Label:
				node.add_theme_color_override("font_color", TIP_COLOR)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
		"sep":
			if node is Label:
				node.add_theme_color_override("font_color", dark_solid)
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		"scroll":
			if node is ScrollContainer:
				node.add_theme_stylebox_override("panel", glass_box(Color.TRANSPARENT))
		"table_header":
			if node is Label:
				node.add_theme_color_override("font_color", Color(0.85, 0.89, 0.98))
				node.add_theme_font_override("font", font_ui())
				node.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
