class_name FmgFeatureNames
extends RefCounted
## Feature names. Port of features-generator.ts defineNames: oceans get an
## adjective or a compass-side name, lakes and landmasses take a culture
## name (10% replaced by an adjective).

const ADJECTIVES := [
	"Autumn", "Azure", "Black", "Blue", "Bony", "Boundless", "Broken", "Calm", "Cold", "Crimson",
	"Deep", "Draconic", "Dreamy", "Echoing", "Emerald", "Endless", "Far", "Forbidden", "Forgotten", "Fortunate",
	"Frozen", "Glassy", "Glittering", "Golden", "Great", "Green", "Grey", "Icy", "Inner", "Kingly",
	"Lost", "Misty", "Outer", "Pale", "Pearly", "Reedy", "Red", "Restless", "Roaring", "Ruinous",
	"Sailing", "Salty", "Sapphire", "Serene", "Serpentine", "Shattered", "Shining", "Shadowy", "Silent", "Sirenic",
	"Sleeping", "Sorrowful", "Starry", "Still", "Stormy", "Sunlit", "Summer", "Tearful", "Thunderous", "Tidal",
	"Yellow", "Wandering", "Whispering", "White", "Wide", "Wild", "Windy", "Winter", "Wondrous", "World"
]

var rng: FmgRng
var pack: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref


func define_names() -> void:
	for feature in pack.features:
		if feature == null or feature.is_empty():
			continue
		if feature.get("name", "") != "":
			continue
		feature["name"] = _get_name(feature)


func _get_name(feature: Dictionary) -> String:
	if feature.get("type", "") == "ocean":
		return _get_ocean_name(feature)
	if rng.P(0.1):
		return rng.ra(ADJECTIVES)
	var cell: int = int(feature.get("firstCell", 0))
	if feature.get("type", "") == "lake":
		var shoreline: PackedInt32Array = feature.get("shoreline", PackedInt32Array())
		if not shoreline.is_empty():
			cell = shoreline[0]
	if cell <= 0 or cell >= pack.culture.size():
		return rng.ra(ADJECTIVES)
	var culture: int = pack.culture[cell]
	if culture > 0 and culture < pack.cultures.size() and pack.cultures[culture] != null:
		return Names.get_culture(culture)
	return rng.ra(ADJECTIVES)


## Oceans belong to no culture: an adjective or the map side.
func _get_ocean_name(feature: Dictionary) -> String:
	if rng.P(0.8):
		return rng.ra(ADJECTIVES)
	var cell: int = int(feature.get("firstCell", 0))
	if cell <= 0 or cell >= pack.points.size():
		return rng.ra(ADJECTIVES)
	var pos: Vector2 = pack.points[cell]
	var dx: float = pos.x / pack.width - 0.5
	var dy: float = pos.y / pack.height - 0.5
	if absf(dx) > absf(dy):
		return "Western" if dx < 0.0 else "Eastern"
	return "Northern" if dy < 0.0 else "Southern"
