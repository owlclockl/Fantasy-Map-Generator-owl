class_name FmgCultures
extends RefCounted
## Cultures: placement of culture centers by suitability sorters, then
## cost-based Dijkstra expansion. Port of cultures-generator.ts.
## Sort formulas are evaluated by the built-in SortExpr mini-evaluator (see the
## bottom of this file) — deliberately NOT the engine's Expression class, which
## resolves bare identifiers against the base object and fails with
## "Invalid named index 'i' for base type Object" depending on how input names
## are bound. The helper methods n/td/tds/bd/sf/t_/h_/s_ live at the bottom.

const SEA_LEVEL: int = 20

const CULTURE_SETS := {
	"world": {"name": "All-world", "max": 32, "probability": 10, "nameRu": "Общемировой"},
	"european": {"name": "European", "max": 15, "probability": 10, "nameRu": "Европейский"},
	"oriental": {"name": "Oriental", "max": 13, "probability": 2, "nameRu": "Восточный"},
	"english": {"name": "English", "max": 10, "probability": 5, "nameRu": "Английский"},
	"antique": {"name": "Antique", "max": 10, "probability": 3, "nameRu": "Античный"},
	"highFantasy": {"name": "High Fantasy", "max": 17, "probability": 11, "nameRu": "Высокое фэнтези"},
	"darkFantasy": {"name": "Dark Fantasy", "max": 18, "probability": 3, "nameRu": "Тёмное фэнтези"},
	"random": {"name": "Random", "max": 100, "probability": 1, "nameRu": "Случайный"}
}

const CULTURE_TYPES: Array = ["Generic", "Hunting", "Highland", "River", "Lake", "Naval", "Nomadic"]

## rows: [name, nameBase, odd, sortExpression, shield]
const SET_WORLD := [
	["Shwazen", 0, 0.7, "n(i) / td(i, 10) / bd(i, 6, 8)", ""],
	["Angshire", 1, 1.0, "n(i) / td(i, 10) / sf(i)", ""],
	["Luari", 2, 0.6, "n(i) / td(i, 12) / bd(i, 6, 8)", ""],
	["Tallian", 3, 0.6, "n(i) / td(i, 15)", ""],
	["Astellian", 4, 0.6, "n(i) / td(i, 16)", ""],
	["Slovan", 5, 0.7, "(n(i) / td(i, 6)) * t_(i)", ""],
	["Norse", 6, 0.7, "n(i) / td(i, 5)", ""],
	["Elladan", 7, 0.7, "(n(i) / td(i, 18)) * h_(i)", ""],
	["Romian", 8, 0.7, "n(i) / td(i, 15)", ""],
	["Soumi", 9, 0.3, "(n(i) / td(i, 5) / bd(i, 9)) * t_(i)", ""],
	["Koryo", 10, 0.1, "n(i) / td(i, 12) / t_(i)", ""],
	["Hantzu", 11, 0.1, "n(i) / td(i, 13)", ""],
	["Yamoto", 12, 0.1, "n(i) / td(i, 15) / t_(i)", ""],
	["Portuzian", 13, 0.4, "n(i) / td(i, 17) / sf(i)", ""],
	["Nawatli", 14, 0.1, "h_(i) / td(i, 18) / bd(i, 7)", ""],
	["Vengrian", 15, 0.2, "(n(i) / td(i, 11) / bd(i, 4)) * t_(i)", ""],
	["Turchian", 16, 0.2, "n(i) / td(i, 13)", ""],
	["Berberan", 17, 0.1, "(n(i) / td(i, 19) / bd(i, 1, 2, 3, -1, 7)) * t_(i)", ""],
	["Eurabic", 18, 0.2, "(n(i) / td(i, 26) / bd(i, 1, 2, -1, -1, 7)) * t_(i)", ""],
	["Inuk", 19, 0.05, "td(i, -1) / bd(i, 10, 11) / sf(i)", ""],
	["Euskati", 20, 0.05, "(n(i) / td(i, 15)) * h_(i)", ""],
	["Yoruba", 21, 0.05, "n(i) / td(i, 15) / bd(i, 5, 7)", ""],
	["Keltan", 22, 0.05, "(n(i) / td(i, 11) / bd(i, 6, 8)) * t_(i)", ""],
	["Efratic", 23, 0.05, "(n(i) / td(i, 22)) * t_(i)", ""],
	["Tehrani", 24, 0.1, "(n(i) / td(i, 18)) * h_(i)", ""],
	["Maui", 25, 0.05, "n(i) / td(i, 24) / sf(i) / t_(i)", ""],
	["Carnatic", 26, 0.05, "n(i) / td(i, 26)", ""],
	["Inqan", 27, 0.05, "h_(i) / td(i, 13)", ""],
	["Kiswaili", 28, 0.1, "n(i) / td(i, 29) / bd(i, 1, 3, 5, 7)", ""],
	["Vietic", 29, 0.1, "n(i) / td(i, 25) / bd(i, 7, -1, -1, -1, 7) / t_(i)", ""],
	["Guantzu", 30, 0.1, "n(i) / td(i, 17)", ""],
	["Ulus", 31, 0.1, "(n(i) / td(i, 5) / bd(i, 2, 4, 10, -1, 7)) * t_(i)", ""],
	["Levent", 42, 0.2, "(n(i) / td(i, 18)) * sf(i)", ""]
]

const SET_EUROPEAN := [
	["Shwazen", 0, 1.0, "n(i) / td(i, 10) / bd(i, 6, 8)", ""],
	["Angshire", 1, 1.0, "n(i) / td(i, 10) / sf(i)", ""],
	["Luari", 2, 1.0, "n(i) / td(i, 12) / bd(i, 6, 8)", ""],
	["Tallian", 3, 1.0, "n(i) / td(i, 15)", ""],
	["Astellian", 4, 1.0, "n(i) / td(i, 16)", ""],
	["Slovan", 5, 1.0, "(n(i) / td(i, 6)) * t_(i)", ""],
	["Norse", 6, 1.0, "n(i) / td(i, 5)", ""],
	["Elladan", 7, 1.0, "(n(i) / td(i, 18)) * h_(i)", ""],
	["Romian", 8, 0.2, "n(i) / td(i, 15) / t_(i)", ""],
	["Soumi", 9, 1.0, "(n(i) / td(i, 5) / bd(i, 9)) * t_(i)", ""],
	["Portuzian", 13, 1.0, "n(i) / td(i, 17) / sf(i)", ""],
	["Vengrian", 15, 1.0, "(n(i) / td(i, 11) / bd(i, 4)) * t_(i)", ""],
	["Turchian", 16, 0.05, "n(i) / td(i, 14)", ""],
	["Euskati", 20, 0.05, "(n(i) / td(i, 15)) * h_(i)", ""],
	["Keltan", 22, 0.05, "(n(i) / td(i, 11) / bd(i, 6, 8)) * t_(i)", ""]
]

const SET_ORIENTAL := [
	["Koryo", 10, 1.0, "n(i) / td(i, 12) / t_(i)", ""],
	["Hantzu", 11, 1.0, "n(i) / td(i, 13)", ""],
	["Yamoto", 12, 1.0, "n(i) / td(i, 15) / t_(i)", ""],
	["Turchian", 16, 1.0, "n(i) / td(i, 12)", ""],
	["Berberan", 17, 0.2, "(n(i) / td(i, 19) / bd(i, 1, 2, 3, -1, 7)) * t_(i)", ""],
	["Eurabic", 18, 1.0, "(n(i) / td(i, 26) / bd(i, 1, 2, -1, -1, 7)) * t_(i)", ""],
	["Efratic", 23, 0.1, "(n(i) / td(i, 22)) * t_(i)", ""],
	["Tehrani", 24, 1.0, "(n(i) / td(i, 18)) * h_(i)", ""],
	["Maui", 25, 0.2, "n(i) / td(i, 24) / sf(i) / t_(i)", ""],
	["Carnatic", 26, 0.5, "n(i) / td(i, 26)", ""],
	["Vietic", 29, 0.8, "n(i) / td(i, 25) / bd(i, 7, -1, -1, -1, 7) / t_(i)", ""],
	["Guantzu", 30, 0.5, "n(i) / td(i, 17)", ""],
	["Ulus", 31, 1.0, "(n(i) / td(i, 5) / bd(i, 2, 4, 10, -1, 7)) * t_(i)", ""]
]

const SET_ANTIQUE := [
	["Roman", 8, 1.0, "n(i) / td(i, 14) / t_(i)", ""],
	["Roman", 8, 1.0, "n(i) / td(i, 15) / sf(i)", ""],
	["Roman", 8, 1.0, "n(i) / td(i, 16) / sf(i)", ""],
	["Roman", 8, 1.0, "n(i) / td(i, 17) / t_(i)", ""],
	["Hellenic", 7, 1.0, "(n(i) / td(i, 18) / sf(i)) * h_(i)", ""],
	["Hellenic", 7, 1.0, "(n(i) / td(i, 19) / sf(i)) * h_(i)", ""],
	["Macedonian", 7, 0.5, "(n(i) / td(i, 12)) * h_(i)", ""],
	["Celtic", 22, 1.0, "n(i) / tds(i, 11) / bd(i, 6, 8)", ""],
	["Germanic", 0, 1.0, "n(i) / tds(i, 10) / bd(i, 6, 8)", ""],
	["Persian", 24, 0.8, "(n(i) / td(i, 18)) * h_(i)", ""],
	["Scythian", 24, 0.5, "n(i) / tds(i, 11) / bd(i, 4)", ""],
	["Cantabrian", 20, 0.5, "(n(i) / td(i, 16)) * h_(i)", ""],
	["Estian", 9, 0.2, "(n(i) / td(i, 5)) * t_(i)", ""],
	["Carthaginian", 42, 0.3, "n(i) / td(i, 20) / sf(i)", ""],
	["Hebrew", 42, 0.2, "(n(i) / td(i, 19)) * sf(i)", ""],
	["Mesopotamian", 23, 0.2, "n(i) / td(i, 22) / bd(i, 1, 2, 3)", ""]
]

const SET_HIGH_FANTASY := [
	["Quenian (Elfish)", 33, 1.0, "(n(i) / bd(i, 6, 7, 8, 9, 10)) * t_(i)", ""],
	["Eldar (Elfish)", 33, 1.0, "(n(i) / bd(i, 6, 7, 8, 9, 10)) * t_(i)", ""],
	["Trow (Dark Elfish)", 34, 0.9, "(n(i) / bd(i, 7, 8, 9, 12, 10)) * t_(i)", ""],
	["Lothian (Dark Elfish)", 34, 0.3, "(n(i) / bd(i, 7, 8, 9, 12, 10)) * t_(i)", ""],
	["Dunirr (Dwarven)", 35, 1.0, "n(i) + h_(i)", ""],
	["Khazadur (Dwarven)", 35, 1.0, "n(i) + h_(i)", ""],
	["Kobold (Goblin)", 36, 1.0, "t_(i) - s_(i)", ""],
	["Uruk (Orkish)", 37, 1.0, "h_(i) * t_(i)", ""],
	["Ugluk (Orkish)", 37, 0.5, "(h_(i) * t_(i)) / bd(i, 1, 2, 10, 11)", ""],
	["Yotunn (Giants)", 38, 0.7, "td(i, -10)", ""],
	["Rake (Drakonic)", 39, 0.7, "-s_(i)", ""],
	["Arago (Arachnid)", 40, 0.7, "t_(i) - s_(i)", ""],
	["Aj'Snaga (Serpents)", 41, 0.7, "n(i) / bd(i, 12, -1, -1, -1, 10)", ""],
	["Anor (Human)", 32, 1.0, "n(i) / td(i, 10)", ""],
	["Dail (Human)", 32, 1.0, "n(i) / td(i, 13)", ""],
	["Rohand (Human)", 16, 1.0, "n(i) / td(i, 16)", ""],
	["Dulandir (Human)", 31, 1.0, "(n(i) / td(i, 5) / bd(i, 2, 4, 10, -1, 7)) * t_(i)", ""]
]

const SET_DARK_FANTASY := [
	["Angshire", 1, 1.0, "n(i) / td(i, 10) / sf(i)", ""],
	["Enlandic", 1, 1.0, "n(i) / td(i, 12)", ""],
	["Westen", 1, 1.0, "n(i) / td(i, 10)", ""],
	["Nortumbic", 1, 1.0, "n(i) / td(i, 7)", ""],
	["Mercian", 1, 1.0, "n(i) / td(i, 9)", ""],
	["Kentian", 1, 1.0, "n(i) / td(i, 12)", ""],
	["Norse", 6, 0.7, "n(i) / td(i, 5) / sf(i)", ""],
	["Schwarzen", 0, 0.3, "n(i) / td(i, 10) / bd(i, 6, 8)", ""],
	["Luarian", 2, 0.3, "n(i) / td(i, 12) / bd(i, 6, 8)", ""],
	["Hetallian", 3, 0.3, "n(i) / td(i, 15)", ""],
	["Astellian", 4, 0.3, "n(i) / td(i, 16)", ""],
	["Kiswaili", 28, 0.05, "n(i) / td(i, 29) / bd(i, 1, 3, 5, 7)", ""],
	["Yoruba", 21, 0.05, "n(i) / td(i, 15) / bd(i, 5, 7)", ""],
	["Koryo", 10, 0.05, "n(i) / td(i, 12) / t_(i)", ""],
	["Hantzu", 11, 0.05, "n(i) / td(i, 13)", ""],
	["Yamoto", 12, 0.05, "n(i) / td(i, 15) / t_(i)", ""],
	["Guantzu", 30, 0.05, "n(i) / td(i, 17)", ""],
	["Ulus", 31, 0.05, "(n(i) / td(i, 5) / bd(i, 2, 4, 10, -1, 7)) * t_(i)", ""],
	["Turan", 16, 0.05, "n(i) / td(i, 12)", ""],
	["Berberan", 17, 0.05, "(n(i) / td(i, 19) / bd(i, 1, 2, 3, -1, 7)) * t_(i)", ""],
	["Eurabic", 18, 0.05, "(n(i) / td(i, 26) / bd(i, 1, 2, -1, -1, 7)) * t_(i)", ""],
	["Slovan", 5, 0.05, "(n(i) / td(i, 6)) * t_(i)", ""],
	["Keltan", 22, 0.1, "n(i) / tds(i, 11) / bd(i, 6, 8)", ""],
	["Elladan", 7, 0.2, "(n(i) / td(i, 18) / sf(i)) * h_(i)", ""],
	["Romian", 8, 0.2, "n(i) / td(i, 14) / t_(i)", ""],
	["Eldar", 33, 0.5, "(n(i) / bd(i, 6, 7, 8, 9, 10)) * t_(i)", ""],
	["Trow", 34, 0.8, "(n(i) / bd(i, 7, 8, 9, 12, 10)) * t_(i)", ""],
	["Durinn", 35, 0.8, "n(i) + h_(i)", ""],
	["Kobblin", 36, 0.8, "t_(i) - s_(i)", ""],
	["Uruk", 37, 0.8, "(h_(i) * t_(i)) / bd(i, 1, 2, 10, 11)", ""],
	["Yotunn", 38, 0.8, "td(i, -10)", ""],
	["Drake", 39, 0.9, "-s_(i)", ""],
	["Rakhnid", 40, 0.9, "t_(i) - s_(i)", ""],
	["Aj'Snaga", 41, 0.9, "n(i) / bd(i, 12, -1, -1, -1, 10)", ""]
]

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var cultures_limit: int = 12
var cultures_set: String = "world"
var size_variety: float = 4.0
var growth_rate: float = 1.0

# expression evaluation state
var _s_max: float = 1.0


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func _rows_for_set(set_id: String) -> Array:
	match set_id:
		"european": return SET_EUROPEAN
		"oriental": return SET_ORIENTAL
		"antique": return SET_ANTIQUE
		"highFantasy": return SET_HIGH_FANTASY
		"darkFantasy": return SET_DARK_FANTASY
		"world": return SET_WORLD
	return SET_WORLD


## default culture definitions of the selected set (data-driven sorters)
func get_default_cultures(count: int) -> Array:
	if cultures_set == "english":
		var english: Array = []
		for i: int in 10:
			english.append({"name": Names.get_base(1, 5, 9, ""), "base": 1, "odd": 1.0, "sort": "s_(i)"})
		return english
	if cultures_set == "random":
		var out: Array = []
		for _i: int in count:
			var rnd: int = rng.rand(Names.name_bases.size() - 1)
			out.append({"name": Names.get_base_short(rnd), "base": rnd, "odd": 1.0, "sort": "s_(i)"})
		return out

	var rows := _rows_for_set(cultures_set)
	var out_rows: Array = []
	for row: Array in rows:
		out_rows.append({"name": row[0], "base": row[1], "odd": row[2], "sort": row[3]})
	return out_rows


func generate() -> void:
	var cells_count: int = pack.cell_count()
	var culture_ids := PackedInt32Array()
	culture_ids.resize(cells_count)

	var cultures_in_set_number: int = CULTURE_SETS[cultures_set]["max"] if CULTURE_SETS.has(cultures_set) else 0
	var count: int = mini(cultures_limit, cultures_in_set_number)
	var populated := PackedInt32Array()
	for i: int in cells_count:
		if pack.s[i] != 0:
			populated.append(i)

	if populated.size() < count * 25:
		count = int(floor(float(populated.size()) / 50.0))
		if count == 0:
			push_warning("There are no populated cells. Cannot generate cultures")
			pack.cultures = [{"name": "Wildlands", "i": 0, "base": 1, "type": "Generic"}]
			pack.culture = culture_ids
			return

	var cultures := _select_cultures(count)
	pack.cultures = [null]
	var centers := PackedVector2Array()
	var colors := FmgColors.get_colors(count)
	var codes: Array = []

	var s_max: float = 1.0
	for i: int in populated.size():
		s_max = maxf(s_max, float(pack.s[populated[i]]))
	_s_max = s_max

	for c_index: int in cultures.size():
		var c: Dictionary = cultures[c_index]
		var new_id: int = c_index + 1
		var center: int = _place_center(c["sort"], populated, culture_ids, centers, count)
		centers.append(pack.points[center])
		c["i"] = new_id
		c["center"] = center
		c["color"] = colors[c_index]
		c["type"] = _define_culture_type(center)
		c["expansionism"] = _define_expansionism(c["type"])
		c["origins"] = [0]
		c["code"] = FmgNames.abbreviate(c["name"], codes)
		codes.append(c["code"])
		culture_ids[center] = new_id
		pack.cultures.append(c)

	pack.culture = culture_ids

	# the first culture with id 0 is for wildlands
	pack.cultures[0] = {"name": "Wildlands", "i": 0, "base": 1, "origins": [null], "type": "Generic", "center": 0}

	for c in pack.cultures:
		if c == null:
			continue
		c["base"] = int(c["base"]) % Names.name_bases.size()


func _select_cultures(cultures_number: int) -> Array:
	var default_cultures := get_default_cultures(cultures_number)
	var cultures: Array = []
	if default_cultures.size() == cultures_number:
		return default_cultures
	var all_odd: bool = true
	for d: Dictionary in default_cultures:
		if d["odd"] != 1.0:
			all_odd = false
			break
	if all_odd:
		return default_cultures.slice(0, cultures_number)

	# original selectCultures semantics: one shared budget of 200 odd-rolls for
	# the whole selection; once the budget is spent, whatever is drawn is kept
	var pool := Array(default_cultures)
	var rolls: int = 0
	while cultures.size() < cultures_number and not pool.is_empty():
		var rnd: int = rng.rand(pool.size() - 1)
		var culture: Dictionary = pool[rnd]
		rolls += 1
		if rolls < 200 and not rng.P(culture["odd"]):
			continue
		cultures.append(culture)
		pool.remove_at(rnd)
	return cultures


func _place_center(sort_expr: String, populated: PackedInt32Array, culture_ids: PackedInt32Array, centers: PackedVector2Array, count: int) -> int:
	var spacing: float = (pack.width + pack.height) / 2.0 / float(count)
	var expr := SortExpr.new(self, sort_expr)
	if not expr.ok:
		push_warning("Cannot parse culture sort expression '%s': %s. Using population score instead." % [sort_expr, expr.error])

	var sort_values := {}
	for cell_id: int in populated:
		sort_values[cell_id] = expr.eval_cell(cell_id) if expr.ok else float(pack.s[cell_id])
	var sorted := Array(populated)
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return float(sort_values.get(a, -INF)) > float(sort_values.get(b, -INF)))

	var max_index: int = int(sorted.size() / 2.0)
	var cell_id: int = 0
	var min_spacing: float = spacing
	for attempt: int in 100:
		var pick_index: int = rng.biased(0, max_index, 5)
		cell_id = sorted[pick_index]
		min_spacing *= 0.9
		var too_close: bool = false
		for center: Vector2 in centers:
			if center.distance_to(pack.points[cell_id]) < min_spacing:
				too_close = true
				break
		if culture_ids[cell_id] == 0 and not too_close:
			break
	return cell_id


func _define_culture_type(i: int) -> String:
	if pack.h[i] < 70 and [1, 2, 4].has(pack.biome[i]):
		return "Nomadic"
	if pack.h[i] > 50:
		return "Highland"
	var fid: int = pack.f[pack.haven[i]]
	if fid > 0 and fid < pack.features.size():
		var f: Dictionary = pack.features[fid]
		if f["type"] == "lake" and f["cells"] > 5:
			return "Lake"
		if (pack.harbor[i] != 0 and f["type"] != "lake" and rng.P(0.1)) \
				or (pack.harbor[i] == 1 and rng.P(0.6)) \
				 or (f.get("subtype", "") == "isle" and rng.P(0.4)):
			return "Naval"
	if pack.r[i] != 0 and pack.fl[i] > 100.0:
		return "River"
	if pack.t[i] > 2 and [3, 7, 8, 9, 10, 12].has(pack.biome[i]):
		return "Hunting"
	return "Generic"


func _define_expansionism(type: String) -> float:
	var base: float = 1.0
	if type == "Lake": base = 0.8
	elif type == "Naval": base = 1.5
	elif type == "River": base = 0.9
	elif type == "Nomadic": base = 1.5
	elif type == "Hunting": base = 0.7
	elif type == "Highland": base = 1.2
	return FmgRng.rn((rng.random() * size_variety / 2.0 + 1.0) * base, 1)


func expand() -> void:
	var queue := FlatQueue.new()
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())

	var max_expansion_cost: float = float(pack.cell_count()) * 0.6 * growth_rate

	pack.culture = PackedInt32Array()
	pack.culture.resize(pack.cell_count())

	for culture in pack.cultures:
		if culture == null or int(culture["i"]) == 0:
			continue
		queue.push([int(culture["center"]), int(culture["i"]), 0.0], 0.0)

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var cell_id: int = pair[0][0]
		var priority: float = pair[1]
		var culture: Dictionary = pack.cultures[pair[0][1]]
		var type: String = culture["type"]
		var expansionism: float = culture["expansionism"]
		var source_biome: int = pack.biome[cell_id]

		for neib: int in pack.c[cell_id]:
			var target_biome: int = pack.biome[neib]
			var biome_cost: float = _get_biome_cost(int(culture["i"]), target_biome, type)
			var biome_change_cost: float = 0.0 if source_biome == target_biome else 20.0
			var height_cost: float = _get_height_cost(neib, pack.h[neib], type)
			var river_cost: float = _get_river_cost(pack.r[neib], neib, type)
			var type_cost: float = _get_type_cost(pack.t[neib], type)
			var cell_cost: float = (biome_cost + biome_change_cost + height_cost + river_cost + type_cost) / expansionism
			var total_cost: float = priority + cell_cost

			if total_cost > max_expansion_cost:
				continue
			if cost[neib] == 0.0 or total_cost < cost[neib]:
				if pack.pop[neib] > 0.0:
					pack.culture[neib] = int(culture["i"])
				cost[neib] = total_cost
				queue.push([neib, int(culture["i"]), total_cost], total_cost)


func _get_biome_cost(c: int, biome: int, type: String) -> float:
	var center: Dictionary = pack.cultures[c]
	var center_cell: int = int(center["center"])
	if pack.biome[center_cell] == biome:
		return 10.0
	var biome_cost: float = pack.biomes[biome]["cost"]
	if type == "Hunting":
		return biome_cost * 5.0
	if type == "Nomadic" and biome > 4 and biome < 10:
		return biome_cost * 10.0
	return biome_cost * 2.0


func _get_height_cost(i: int, h: int, type: String) -> float:
	var fid: int = pack.f[i]
	var is_lake: bool = false
	if fid > 0 and fid < pack.features.size():
		is_lake = pack.features[fid]["type"] == "lake"
	var a: float = pack.area[i]
	if type == "Lake" and is_lake:
		return 10.0
	if type == "Naval" and h < 20:
		return a * 2.0
	if type == "Nomadic" and h < 20:
		return a * 50.0
	if h < 20:
		return a * 6.0
	if type == "Highland" and h < 44:
		return 3000.0
	if type == "Highland" and h < 62:
		return 200.0
	if type == "Highland":
		return 0.0
	if h >= 67:
		return 200.0
	if h >= 44:
		return 30.0
	return 0.0


func _get_river_cost(river_id: int, cell_id: int, type: String) -> float:
	if type == "River":
		return 0.0 if river_id != 0 else 100.0
	if river_id == 0:
		return 0.0
	return clampf(pack.fl[cell_id] / 10.0, 20.0, 100.0)


func _get_type_cost(t: int, type: String) -> float:
	if t == 1:
		if type == "Naval" or type == "Lake":
			return 0.0
		return 60.0 if type == "Nomadic" else 20.0
	if t == 2:
		return 30.0 if type == "Naval" or type == "Nomadic" else 0.0
	if t != -1:
		return 100.0 if type == "Naval" or type == "Lake" else 0.0
	return 0.0


# --- Sort-formula helpers (called by SortExpr below) ---

func n(cell_id: int) -> float:
	return ceil(float(pack.s[cell_id]) / _s_max * 3.0)


func td(cell_id: int, goal: float) -> float:
	var d: float = absf(float(grid.temp[pack.g[cell_id]]) - goal)
	return d + 1.0 if d != 0.0 else 1.0


func tds(cell_id: int, goal: float) -> float:
	return sqrt(td(cell_id, goal))


## biome difference fee; `biomes` may hold any number of biome ids (the
## original JS is bd(cell, biomes[], fee) — some formulas list five biomes)
func bd(cell_id: int, biomes: Array, fee: float = 4.0) -> float:
	var biome: int = pack.biome[cell_id]
	for b: int in biomes:
		if b >= 0 and biome == b:
			return 1.0
	return fee


func sf(cell_id: int, fee: float = 4.0) -> float:
	var haven_cell: int = pack.haven[cell_id]
	if haven_cell != 0:
		var fid: int = pack.f[haven_cell]
		if fid > 0 and fid < pack.features.size():
			if pack.features[fid]["type"] != "lake":
				return 1.0
	return fee


func t_(cell_id: int) -> float:
	return float(pack.t[cell_id])


func h_(cell_id: int) -> float:
	return float(pack.h[cell_id])


func s_(cell_id: int) -> float:
	return float(pack.s[cell_id])


## A parsed culture sort formula, evaluated per cell in pure GDScript.
## Exists because the engine's Expression class resolves bare identifiers
## (like `i`) as named indexes into the base object and dies with
## "Invalid named index 'i' for base type Object" unless input names happen
## to be bound exactly right — this evaluator has no such state.
## Grammar: expr := term (('+'|'-') term)* ; term := unary (('*'|'/') unary)* ;
##          unary := '-' unary | atom ; atom := number | fn '(' args ')' | '(' expr ')'
## AST nodes: ["num", v] | ["fn", name, args] | ["bin", op, l, r] | ["neg", node]
class SortExpr:
	extends RefCounted

	var ok: bool = false
	var error: String = ""
	var ast: Array = []
	var _host: FmgCultures = null
	var _tokens: Array = []
	var _pos: int = 0


	func _init(host: FmgCultures, source: String) -> void:
		_host = host
		_tokens = _tokenize(source)
		if error != "":
			return
		if _tokens.is_empty():
			error = "empty expression"
			return
		ast = _parse_expr()
		if error == "" and _pos < _tokens.size():
			error = "unexpected token '%s'" % str(_tokens[_pos][1])
		ok = error == ""


	func eval_cell(cell_id: int) -> float:
		if not ok:
			return -INF
		var v: float = _eval(ast, cell_id)
		# NaN/INF would make the sort comparator inconsistent
		return -INF if is_nan(v) else v


	# --- tokenizer ---

	static func _is_digit(ch: String) -> bool:
		return ch >= "0" and ch <= "9"


	static func _is_ident_start(ch: String) -> bool:
		return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


	static func _is_ident_char(ch: String) -> bool:
		return _is_ident_start(ch) or _is_digit(ch)


	func _tokenize(src: String) -> Array:
		var out: Array = []
		var i: int = 0
		var len: int = src.length()
		while i < len:
			var ch: String = src[i]
			if ch == " " or ch == "\t" or ch == "\n":
				i += 1
				continue
			if _is_digit(ch) or ch == ".":
				var j: int = i
				while j < len and (_is_digit(src[j]) or src[j] == "."):
					j += 1
				var text: String = src.substr(i, j - i)
				if not text.is_valid_float():
					error = "bad number '%s'" % text
					return out
				out.append(["num", text.to_float()])
				i = j
				continue
			if _is_ident_start(ch):
				var j2: int = i
				while j2 < len and _is_ident_char(src[j2]):
					j2 += 1
				out.append(["id", src.substr(i, j2 - i)])
				i = j2
				continue
			if ch == "+" or ch == "-" or ch == "*" or ch == "/" or ch == "(" or ch == ")" or ch == ",":
				out.append(["sym", ch])
				i += 1
				continue
			error = "unexpected character '%s'" % ch
			return out
		return out


	# --- recursive descent parser ---

	func _peek() -> Array:
		if _pos < _tokens.size():
			return _tokens[_pos]
		return ["eof", ""]


	func _take() -> Array:
		var t: Array = _peek()
		_pos += 1
		return t


	func _parse_expr() -> Array:
		var node: Array = _parse_term()
		while error == "":
			var t: Array = _peek()
			if t[0] == "sym" and (t[1] == "+" or t[1] == "-"):
				_take()
				node = ["bin", t[1], node, _parse_term()]
			else:
				break
		return node


	func _parse_term() -> Array:
		var node: Array = _parse_unary()
		while error == "":
			var t: Array = _peek()
			if t[0] == "sym" and (t[1] == "*" or t[1] == "/"):
				_take()
				node = ["bin", t[1], node, _parse_unary()]
			else:
				break
		return node


	func _parse_unary() -> Array:
		var t: Array = _peek()
		if t[0] == "sym" and t[1] == "-":
			_take()
			return ["neg", _parse_unary()]
		if t[0] == "sym" and t[1] == "+":
			_take()
			return _parse_unary()
		return _parse_atom()


	func _parse_atom() -> Array:
		var t: Array = _take()
		if t[0] == "num":
			return ["num", t[1]]
		if t[0] == "sym" and t[1] == "(":
			var node: Array = _parse_expr()
			var closing: Array = _take()
			if error == "" and not (closing[0] == "sym" and closing[1] == ")"):
				error = "expected ')'"
			return node
		if t[0] == "id":
			var name: String = t[1]
			if name == "i":
				# bare `i`: the current cell id (normally wrapped in a function)
				return ["fn", "i", []]
			var opening: Array = _take()
			if not (opening[0] == "sym" and opening[1] == "("):
				error = "expected '(' after '%s'" % name
				return []
			var args: Array = []
			var next_t: Array = _peek()
			if next_t[0] == "sym" and next_t[1] == ")":
				_take()
			else:
				while error == "":
					args.append(_parse_expr())
					if error != "":
						break
					var sep: Array = _take()
					if sep[0] == "sym" and sep[1] == ",":
						continue
					if sep[0] == "sym" and sep[1] == ")":
						break
					error = "expected ',' or ')'"
			if error != "":
				return []
			match name:
				"n", "td", "tds", "bd", "sf", "t_", "h_", "s_":
					return ["fn", name, args]
			error = "unknown function '%s'" % name
			return []
		if t[0] == "eof":
			error = "unexpected end of expression"
		else:
			error = "unexpected token '%s'" % str(t[1])
		return []


	# --- evaluation ---

	func _eval(node: Array, cell_id: int) -> float:
		match node[0]:
			"num":
				return float(node[1])
			"neg":
				return -_eval(node[1], cell_id)
			"bin":
				var l: float = _eval(node[2], cell_id)
				var r: float = _eval(node[3], cell_id)
				match node[1]:
					"+": return l + r
					"-": return l - r
					"*": return l * r
					_:
						if r == 0.0:
							return INF # JS semantics: division by zero never traps
						return l / r
			"fn":
				return _eval_fn(node[1], node[2], cell_id)
		return 0.0


	func _eval_fn(fn_name: String, arg_nodes: Array, cell_id: int) -> float:
		var args: Array = []
		for a: Array in arg_nodes:
			args.append(_eval(a, cell_id))
		match fn_name:
			"i":
				return float(cell_id)
			"n":
				return _host.n(cell_id)
			"td":
				if args.size() >= 2:
					return _host.td(cell_id, args[1])
				error = "td() needs 2 arguments"
			"tds":
				if args.size() >= 2:
					return _host.tds(cell_id, args[1])
				error = "tds() needs 2 arguments"
			"bd":
				# flat args encode `bd(i, b1..bN[, -1 padding, fee])`: when a -1
				# pad is present the trailing value is the fee, otherwise every
				# argument is a biome and the fee defaults to 4
				var biomes: Array = []
				var fee: float = 4.0
				var padded: bool = false
				for a: float in args:
					if int(a) == -1:
						padded = true
						break
					biomes.append(int(a))
				if padded and args.size() >= 2:
					fee = args[args.size() - 1]
				return _host.bd(cell_id, biomes, fee)
			"sf":
				return _host.sf(cell_id, args[0] if args.size() >= 1 else 4.0)
			"t_":
				return _host.t_(cell_id)
			"h_":
				return _host.h_(cell_id)
			"s_":
				return _host.s_(cell_id)
		return 0.0
