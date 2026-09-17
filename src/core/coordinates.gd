class_name FmgCoordinates
extends RefCounted
## Where the map sits on the globe: its share of the world and the resulting
## lat/lon box. Port of the original `coordinates.ts`.
##
## Every template knows how large its world is and where it lies: real-world
## templates bring exact numbers (Britain is 7 % of the world at 51° N), the
## procedural ones roll a size and a latitude band. The box derived here drives
## the temperature, the precipitation, the ice and the coordinate grid, so a
## map of Iceland gets a sub-polar climate and a map of Africa the tropics —
## exactly as in the original.
##
## The module is deliberately stateless and value-based so that `FmgSim` stays
## the single owner of the world state (and so the math can be tested alone).

## [size in % of the world, North-South shift in %, West-East shift in %]
## per real-world template and for the pre-created heightmaps
const TEMPLATE_POSITIONS := {
	"africa-centric": [45.0, 53.0, 38.0],
	"arabia": [20.0, 35.0, 35.0],
	"atlantics": [42.0, 23.0, 65.0],
	"britain": [7.0, 20.0, 51.3],
	"caribbean": [15.0, 40.0, 74.8],
	"east-asia": [11.0, 28.0, 9.4],
	"eurasia": [38.0, 19.0, 27.0],
	"europe": [20.0, 16.0, 44.8],
	"europe-accented": [14.0, 22.0, 44.8],
	"europe-and-central-asia": [25.0, 10.0, 39.5],
	"europe-central": [11.0, 22.0, 46.4],
	"europe-north": [7.0, 18.0, 48.9],
	"greenland": [22.0, 7.0, 55.8],
	"hellenica": [8.0, 27.0, 43.5],
	"iceland": [2.0, 15.0, 55.3],
	"indian-ocean": [45.0, 55.0, 14.0],
	"mediterranean-sea": [10.0, 29.0, 45.8],
	"middle-east": [8.0, 31.0, 34.4],
	"north-america": [37.0, 17.0, 87.0],
	"us-centric": [66.0, 27.0, 100.0],
	"us-mainland": [16.0, 30.0, 77.5],
	"world": [78.0, 27.0, 40.0],
	"world-from-pacific": [75.0, 32.0, 30.0] # longitude does not fit
}

## chance for a random template to cover the whole world, when the land does
## not reach the map borders
const WHOLE_WORLD_CHANCE := {
	"pangea": 1.0,
	"shattered": 0.7,
	"continents": 0.5,
	"archipelago": 0.35,
	"highIsland": 0.25,
	"lowIsland": 0.1
}

## size distribution [expected, deviation, min, max] for a random template
const RANDOM_SIZE := {
	"pangea": [70.0, 20.0, 30.0, 100.0],
	"volcano": [20.0, 20.0, 10.0, 100.0],
	"mediterranean": [25.0, 30.0, 15.0, 80.0],
	"peninsula": [15.0, 15.0, 5.0, 80.0],
	"isthmus": [15.0, 20.0, 3.0, 80.0],
	"atoll": [3.0, 2.0, 1.0, 5.0]
}


## Does any land feature reach the map border? Such a map must not be declared
## a whole world: it continues beyond the edge (original's `partial`).
static func is_partial(features: Array) -> bool:
	for feature: Variant in features:
		if feature is Dictionary:
			var data: Dictionary = feature
			if bool(data.get("land", false)) and bool(data.get("border", false)):
				return true
	return false


## Roll the map size and position for a template:
## returns [size in % of the world, latitude shift %, longitude shift %].
static func resolve(template_id: String, partial: bool, rng: FmgRng) -> Array:
	if TEMPLATE_POSITIONS.has(template_id):
		return (TEMPLATE_POSITIONS[template_id] as Array).duplicate()

	var chance: float = float(WHOLE_WORLD_CHANCE.get(template_id, 0.0))
	if not partial and chance > 0.0 and rng.P(chance):
		return [100.0, 50.0, 50.0]

	var max_size: float = 80.0 if partial else 100.0
	var distribution: Array = RANDOM_SIZE.get(template_id, [30.0, 20.0, 15.0, max_size])
	var round_to: int = 1 if template_id == "atoll" else 0
	var size: float = rng.gauss(
		float(distribution[0]), float(distribution[1]), float(distribution[2]),
		minf(float(distribution[3]), max_size), round_to
	)
	# latitude shift: 40 % (northern hemisphere) or 60 %, never the poles
	var latitude: float = rng.gauss(40.0 if rng.P(0.5) else 60.0, 20.0, 25.0, 75.0)
	return [size, latitude, 50.0]


## Derive the lat/lon box from the three values (original's `calculate()`).
## Returns {latT, latN, latS, lonT, lonW, lonE} in degrees.
static func calculate(
	map_size: float, latitude: float, longitude: float, map_width: float, map_height: float
) -> Dictionary:
	var size_fraction: float = map_size / 100.0
	var lat_shift: float = latitude / 100.0
	var lon_shift: float = longitude / 100.0

	var lat_t: float = FmgRng.rn(size_fraction * 180.0, 1)
	lat_t = clampf(lat_t, 0.5, 180.0)
	var lat_n: float = FmgRng.rn(90.0 - (180.0 - lat_t) * lat_shift, 1)
	var lat_s: float = FmgRng.rn(lat_n - lat_t, 1)

	var lon_t: float = FmgRng.rn(minf(map_width / maxf(map_height, 1.0) * lat_t, 360.0), 1)
	lon_t = clampf(lon_t, 0.5, 360.0)
	var lon_e: float = FmgRng.rn(180.0 - (360.0 - lon_t) * lon_shift, 1)
	var lon_w: float = FmgRng.rn(lon_e - lon_t, 1)

	return {"latT": lat_t, "latN": lat_n, "latS": lat_s, "lonT": lon_t, "lonW": lon_w, "lonE": lon_e}


## Human-readable position of the map, e.g. «51.0° с. ш. … 48.7° с. ш., 12.3° з. д. … 8.9° в. д.»
static func describe(box: Dictionary) -> String:
	if box.is_empty():
		return "весь мир"
	return "%s … %s, %s … %s" % [
		format_latitude(float(box.get("latN", 90.0))),
		format_latitude(float(box.get("latS", -90.0))),
		format_longitude(float(box.get("lonW", -180.0))),
		format_longitude(float(box.get("lonE", 180.0))),
	]


static func format_latitude(value: float) -> String:
	var hemisphere: String = "с. ш." if value >= 0.0 else "ю. ш."
	return "%s° %s" % [_trim(value), hemisphere]


static func format_longitude(value: float) -> String:
	var hemisphere: String = "в. д." if value >= 0.0 else "з. д."
	return "%s° %s" % [_trim(value), hemisphere]


## What the menu shows next to a template before any map is generated.
static func template_hint(template_id: String) -> String:
	if TEMPLATE_POSITIONS.has(template_id):
		var position: Array = TEMPLATE_POSITIONS[template_id]
		return "фиксировано: %s %% мира, широтный сдвиг %s %%" % [_trim(float(position[0])), _trim(float(position[1]))]
	if WHOLE_WORLD_CHANCE.has(template_id):
		return "случайно: весь мир с шансом %d %%, иначе случайный регион" % int(float(WHOLE_WORLD_CHANCE[template_id]) * 100.0)
	return "случайный размер и широта"


static func _trim(value: float) -> String:
	var rounded: float = FmgRng.rn(value, 1)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(rounded))
	return "%.1f" % rounded
