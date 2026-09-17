class_name FmgSettings
extends RefCounted
## Tiny persistent settings store (user://fmg_settings.cfg).
##
## The original keeps the interface scale, the element sizes and the layer
## switches in the browser's local storage. This is the desktop equivalent: the
## interface scale, the lettering behaviour, the map furniture modes and the
## layer/style choices survive a restart.

const PATH := "user://fmg_settings.cfg"
const VERSION := 1

# Defaults (kept in sync with MapView / FmgUiTheme).
const DEFAULT_UI_SCALE_MODE := "auto"
const DEFAULT_UI_SCALE := 1.0
const DEFAULT_LABEL_SCALE_MODE := 0 # MapView.LabelScale.WITH_MAP
const DEFAULT_LABEL_DECLUTTER := true
const DEFAULT_LABEL_AVOID_OVERLAP := true
const DEFAULT_LABEL_MIN_PX := 6.0
const DEFAULT_STYLE_LABEL_SCALE := 1.0
const DEFAULT_SCALE_BAR_ON_MAP := true
const DEFAULT_VIGNETTE_ON_MAP := true
const DEFAULT_DISTANCE_SCALE := 3.0
# geography of the world (the original keeps these as "pins" and reuses them)
const DEFAULT_GEO_AUTO := true
const DEFAULT_GEO_MAP_SIZE := -1.0
const DEFAULT_GEO_LATITUDE := 50.0
const DEFAULT_GEO_LONGITUDE := 50.0
const DEFAULT_TEMPLATE := "continents"
const DEFAULT_THEME_COLOR := "#4b70f5"
const DEFAULT_TRANSPARENCY := 8.0


static func load_all() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return {}
	var data: Dictionary = {}
	data["version"] = int(config.get_value("main", "version", VERSION))
	data["ui_scale_mode"] = str(config.get_value("interface", "scale_mode", DEFAULT_UI_SCALE_MODE))
	data["ui_scale"] = float(config.get_value("interface", "scale", DEFAULT_UI_SCALE))
	data["theme_color"] = str(config.get_value("interface", "theme_color", DEFAULT_THEME_COLOR))
	data["transparency"] = float(config.get_value("interface", "transparency", DEFAULT_TRANSPARENCY))
	data["label_scale_mode"] = int(config.get_value("map", "label_scale_mode", DEFAULT_LABEL_SCALE_MODE))
	data["label_declutter"] = bool(config.get_value("map", "label_declutter", DEFAULT_LABEL_DECLUTTER))
	data["label_avoid_overlap"] = bool(config.get_value("map", "label_avoid_overlap", DEFAULT_LABEL_AVOID_OVERLAP))
	data["label_min_px"] = float(config.get_value("map", "label_min_px", DEFAULT_LABEL_MIN_PX))
	data["style_label_scale"] = float(config.get_value("map", "style_label_scale", DEFAULT_STYLE_LABEL_SCALE))
	data["scale_bar_on_map"] = bool(config.get_value("map", "scale_bar_on_map", DEFAULT_SCALE_BAR_ON_MAP))
	data["vignette_on_map"] = bool(config.get_value("map", "vignette_on_map", DEFAULT_VIGNETTE_ON_MAP))
	data["distance_scale"] = float(config.get_value("map", "distance_scale", DEFAULT_DISTANCE_SCALE))
	data["template"] = str(config.get_value("map", "template", DEFAULT_TEMPLATE))
	data["geo_auto"] = bool(config.get_value("map", "geo_auto", DEFAULT_GEO_AUTO))
	data["geo_map_size"] = float(config.get_value("map", "geo_map_size", DEFAULT_GEO_MAP_SIZE))
	data["geo_latitude"] = float(config.get_value("map", "geo_latitude", DEFAULT_GEO_LATITUDE))
	data["geo_longitude"] = float(config.get_value("map", "geo_longitude", DEFAULT_GEO_LONGITUDE))
	var layers: Dictionary = {}
	if config.has_section("layers"):
		for key: String in config.get_section_keys("layers"):
			layers[key] = bool(config.get_value("layers", key, false))
	data["layers"] = layers
	return data


static func save_all(data: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("main", "version", VERSION)
	config.set_value("interface", "scale_mode", str(data.get("ui_scale_mode", DEFAULT_UI_SCALE_MODE)))
	config.set_value("interface", "scale", float(data.get("ui_scale", DEFAULT_UI_SCALE)))
	config.set_value("interface", "theme_color", str(data.get("theme_color", DEFAULT_THEME_COLOR)))
	config.set_value("interface", "transparency", float(data.get("transparency", DEFAULT_TRANSPARENCY)))
	config.set_value("map", "label_scale_mode", int(data.get("label_scale_mode", DEFAULT_LABEL_SCALE_MODE)))
	config.set_value("map", "label_declutter", bool(data.get("label_declutter", DEFAULT_LABEL_DECLUTTER)))
	config.set_value("map", "label_avoid_overlap", bool(data.get("label_avoid_overlap", DEFAULT_LABEL_AVOID_OVERLAP)))
	config.set_value("map", "label_min_px", float(data.get("label_min_px", DEFAULT_LABEL_MIN_PX)))
	config.set_value("map", "style_label_scale", float(data.get("style_label_scale", DEFAULT_STYLE_LABEL_SCALE)))
	config.set_value("map", "scale_bar_on_map", bool(data.get("scale_bar_on_map", DEFAULT_SCALE_BAR_ON_MAP)))
	config.set_value("map", "vignette_on_map", bool(data.get("vignette_on_map", DEFAULT_VIGNETTE_ON_MAP)))
	config.set_value("map", "distance_scale", float(data.get("distance_scale", DEFAULT_DISTANCE_SCALE)))
	config.set_value("map", "template", str(data.get("template", DEFAULT_TEMPLATE)))
	config.set_value("map", "geo_auto", bool(data.get("geo_auto", DEFAULT_GEO_AUTO)))
	config.set_value("map", "geo_map_size", float(data.get("geo_map_size", DEFAULT_GEO_MAP_SIZE)))
	config.set_value("map", "geo_latitude", float(data.get("geo_latitude", DEFAULT_GEO_LATITUDE)))
	config.set_value("map", "geo_longitude", float(data.get("geo_longitude", DEFAULT_GEO_LONGITUDE)))
	var layers: Dictionary = data.get("layers", {})
	for key: String in layers.keys():
		config.set_value("layers", key, bool(layers[key]))
	return config.save(PATH)
