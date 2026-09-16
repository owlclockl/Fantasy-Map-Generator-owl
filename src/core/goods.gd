class_name FmgGoods
extends RefCounted
## Cell resources (goods). Port of goods-generator.ts: the full original
## GOODS_DATA table plus a small evaluator for the boolean "distribution"
## expressions (biome(), minHeight(), shore(), ... combined with && || !).
## No engine Expression class is used — see cultures.gd SortExpr for why.

const GOODS_DATA := [
	{"i": 1, "name": "Wood", "tags": ["construction", "fuel"], "color": "#966F33", "value": 1, "unit": "pile", "chance": 4, "distribution": "biome(5, 6, 7, 8, 9)", "demandCoverage": {"construction": 1, "utilities": 1}, "multipliers": {"cultureType": {"Hunting": 1.5}}, "biomeOutput": {"5": 0.1, "6": 0.1, "7": 0.1, "8": 0.1, "9": 0.1, "12": 0.05}},
	{"i": 2, "name": "Stone", "tags": ["construction"], "color": "#979EA2", "value": 2, "unit": "pallet", "chance": 4, "distribution": "(minHeight(40) || (minHeight(20) && elevation())) && biome(1, 2, 3, 4)", "demandCoverage": {"construction": 1}, "multipliers": {"cultureType": {"Hunting": 0.6, "Nomadic": 0.6}}, "biomeOutput": {"1": 0.05, "2": 0.05}},
	{"i": 3, "name": "Marble", "tags": ["construction", "luxury"], "color": "#d6d0bf", "value": 6, "unit": "pallet", "chance": 1, "distribution": "minHeight(60) || (minHeight(30) && elevation())", "demandCoverage": {"construction": 0.5, "luxury": 0.5}, "multipliers": {"cultureType": {"Highland": 1.4}}},
	{"i": 4, "name": "Iron", "tags": ["ore", "military"], "color": "#5D686E", "value": 3, "unit": "wagon", "chance": 5, "distribution": "minHeight(60) || (biome(12) && nth(7)) || (minHeight(20) && nth(10))", "multipliers": {"cultureType": {"Highland": 1.4}}, "biomeOutput": {"12": 0.1}},
	{"i": 5, "name": "Copper", "tags": ["ore"], "color": "#b87333", "value": 4, "unit": "wagon", "chance": 2, "distribution": "minHeight(60) || (minHeight(30) && elevation())", "multipliers": {"cultureType": {"Highland": 1.4}}},
	{"i": 6, "name": "Tin", "tags": ["ore"], "color": "#454343", "value": 4, "unit": "wagon", "chance": 2, "distribution": "minHeight(60) || (minHeight(30) && elevation())", "multipliers": {"cultureType": {"Highland": 1.4}}},
	{"i": 7, "name": "Silver", "tags": ["ore", "luxury"], "color": "#C0C0C0", "value": 8, "unit": "bullion", "chance": 2, "distribution": "minHeight(60) || (minHeight(30) && elevation())", "multipliers": {"cultureType": {"Hunting": 0.5, "Highland": 1.4, "Nomadic": 0.5}}},
	{"i": 8, "name": "Gold", "tags": ["ore", "luxury"], "color": "#ffd700", "value": 15, "unit": "bullion", "chance": 2, "distribution": "river() && minHeight(40)", "multipliers": {"cultureType": {"Highland": 1.4, "Nomadic": 0.5}}},
	{"i": 9, "name": "Grain", "tags": ["food"], "color": "#F5DEB3", "value": 1, "unit": "wain", "chance": 4, "distribution": "minHabitability(20) && habitability()", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"River": 1.2, "Lake": 1.2, "Nomadic": 0.5}}, "biomeOutput": {"5": 0.1, "6": 0.1, "7": 0.1, "8": 0.1}},
	{"i": 10, "name": "Cattle", "tags": ["food"], "color": "#56b000", "value": 2, "unit": "head", "chance": 4, "distribution": "(biome(3, 4) && !elevation()) || (biome(6) && random(70)) || (biome(5) && nth(5))", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"Nomadic": 2}}, "biomeOutput": {"3": 0.1, "4": 0.1}},
	{"i": 11, "name": "Fish", "tags": ["food", "aquatic"], "color": "#7fcdff", "value": 1, "unit": "wain", "chance": 4, "distribution": "shore(-1) && (type(\"ocean\", \"freshwater\", \"salt\") || (river() && shore(1, 2)))", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"River": 1.4, "Lake": 1.4, "Naval": 1.4, "Nomadic": 0.2}}},
	{"i": 12, "name": "Game", "tags": ["food"], "color": "#c38a8a", "value": 2, "unit": "wain", "chance": 3, "distribution": "biome(5, 6, 7, 8, 9)", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"Naval": 0.6, "Nomadic": 1.4, "Hunting": 2}}, "biomeOutput": {"3": 0.01, "4": 0.01, "5": 0.02, "6": 0.02, "7": 0.02, "8": 0.02, "9": 0.05}},
	{"i": 13, "name": "Wine", "tags": ["food", "luxury"], "color": "#963e48", "value": 2, "unit": "barrel", "chance": 3, "distribution": "biome(6) || (biome(4) && random(50) && river())", "demandCoverage": {"food": 0.5, "luxury": 0.5}, "multipliers": {"cultureType": {"Highland": 1.2, "Nomadic": 0.5}}, "biomeOutput": {"6": 0.1}},
	{"i": 14, "name": "Olives", "tags": ["food"], "color": "#BDBD7D", "value": 2, "unit": "barrel", "chance": 3, "distribution": "biome(3) && shore(1, 2)", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"Generic": 0.8, "Nomadic": 0.5}}, "biomeOutput": {"3": 0.1}},
	{"i": 15, "name": "Honey", "tags": ["food", "preservative"], "color": "#DCBC66", "value": 2, "unit": "barrel", "chance": 3, "distribution": "biome(6, 8, 9)", "demandCoverage": {"food": 0.5}, "multipliers": {"cultureType": {"Generic": 1.2}}, "biomeOutput": {"6": 0.05, "8": 0.03, "9": 0.03}},
	{"i": 16, "name": "Salt", "tags": ["preservative", "mineral"], "color": "#E5E4E5", "value": 2, "unit": "bag", "chance": 3, "distribution": "shore(1) && type(\"salt\", \"dry\") || (biome(1, 2) && random(70)) || (biome(12) && nth(10))", "demandCoverage": {"utilities": 1}, "multipliers": {"cultureType": {"Naval": 1.2}}, "biomeOutput": {"1": 0.1, "2": 0.1}},
	{"i": 17, "name": "Dates", "tags": ["food"], "color": "#dbb2a3", "value": 2, "unit": "wain", "chance": 2, "distribution": "biome(1)", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"Hunting": 0.8, "Highland": 0.8}}, "biomeOutput": {"1": 0.1}},
	{"i": 18, "name": "Horses", "tags": ["supply", "military"], "color": "#ba7447", "value": 5, "unit": "head", "chance": 4, "distribution": "biome(3) || (biome(2) && nth(4))", "demandCoverage": {"utilities": 0.6, "military": 0.4}, "multipliers": {"cultureType": {"Nomadic": 2}}, "biomeOutput": {"4": 0.01}},
	{"i": 19, "name": "Elephants", "tags": ["supply", "military"], "color": "#C5CACD", "value": 7, "unit": "head", "chance": 2, "distribution": "biome(1, 3, 5, 7)", "demandCoverage": {"utilities": 0.2, "military": 0.8}, "multipliers": {"cultureType": {"Highland": 0.2}}},
	{"i": 20, "name": "Camels", "tags": ["supply", "military"], "color": "#C19A6B", "value": 5, "unit": "head", "chance": 3, "distribution": "biome(1, 2)", "demandCoverage": {"utilities": 0.7, "military": 0.3}, "multipliers": {"cultureType": {"Nomadic": 2, "Generic": 0.8}}, "biomeOutput": {"1": 0.05, "2": 0.05}},
	{"i": 21, "name": "Hemp", "tags": ["clothing", "naval"], "color": "#069a06", "value": 1, "unit": "wain", "chance": 3, "distribution": "biome(6, 7, 8)", "multipliers": {"cultureType": {"River": 1.4, "Lake": 1.4}}, "biomeOutput": {"6": 0.1, "7": 0.1, "8": 0.1}},
	{"i": 22, "name": "Pearls", "tags": ["luxury", "aquatic"], "color": "#EAE0C8", "value": 13, "unit": "pearl", "chance": 2, "distribution": "shore(-1) && minTemp(18)", "demandCoverage": {"luxury": 0.6}, "multipliers": {"cultureType": {"Naval": 1.4}}},
	{"i": 23, "name": "Gemstones", "tags": ["luxury", "mineral"], "color": "#e463e4", "value": 15, "unit": "gem", "chance": 2, "distribution": "minHeight(60) || (minHeight(30) && elevation())", "demandCoverage": {"luxury": 0.6}, "multipliers": {"cultureType": {"Highland": 1.4}}},
	{"i": 24, "name": "Dyes", "tags": ["luxury"], "color": "#fecdea", "value": 5, "unit": "bag", "chance": 1, "distribution": "shore(-1) || minHabitability(1)", "multipliers": {"cultureType": {"Generic": 1.2}}},
	{"i": 25, "name": "Incense", "tags": ["luxury", "ritual"], "color": "#ebe5a7", "value": 10, "unit": "chest", "chance": 2, "distribution": "biome(1, 7)", "demandCoverage": {"luxury": 1}},
	{"i": 26, "name": "Silk", "tags": ["luxury", "clothing"], "color": "#e0f0f8", "value": 9, "unit": "bolt", "chance": 1, "distribution": "biome(7)", "demandCoverage": {"luxury": 1}, "multipliers": {"cultureType": {"River": 1.2, "Lake": 1.2}}},
	{"i": 27, "name": "Spices", "tags": ["luxury"], "color": "#e99c75", "value": 15, "unit": "chest", "chance": 2, "distribution": "biome(7)", "demandCoverage": {"luxury": 1}, "multipliers": {"cultureType": {"Generic": 1.2}}},
	{"i": 28, "name": "Amber", "tags": ["luxury"], "color": "#e68200", "value": 7, "unit": "stone", "chance": 2, "distribution": "shore(1) && biome(6, 7, 8, 9)", "demandCoverage": {"luxury": 0.5}, "multipliers": {"cultureType": {"Generic": 1.2}}},
	{"i": 29, "name": "Furs", "tags": ["clothing", "luxury"], "color": "#8a5e51", "value": 4, "unit": "pelt", "chance": 2, "distribution": "biome(9) || (biome(10) && nth(2)) || (biome(6, 8) && nth(5)) || (biome(12) && nth(10))", "demandCoverage": {"luxury": 0.5, "utilities": 0.3}, "multipliers": {"cultureType": {"Hunting": 2}}, "biomeOutput": {"6": 0.02, "8": 0.02, "9": 0.02, "10": 0.02, "12": 0.02}},
	{"i": 30, "name": "Sheep", "tags": ["clothing"], "color": "#53b574", "value": 2, "unit": "head", "chance": 3, "distribution": "(biome(3, 4) && !elevation()) || (biome(6) && random(70)) || (biome(5) && nth(5))", "demandCoverage": {"food": 1}, "multipliers": {"cultureType": {"Naval": 1.4, "Highland": 1.4}}, "biomeOutput": {"4": 0.1}},
	{"i": 31, "name": "Slaves", "tags": ["supply"], "color": "#757575", "value": 8, "unit": "slave", "chance": 2, "distribution": "shore(1) && minHabitability(1) && !habitability()", "demandCoverage": {"utilities": 1}, "multipliers": {"cultureType": {"Naval": 1.4, "Nomadic": 2, "Hunting": 0.6, "Highland": 0.4}}},
	{"i": 32, "name": "Tar", "tags": ["naval"], "color": "#727272", "value": 3, "unit": "barrel", "chance": 0, "demandCoverage": {"utilities": 0.4, "military": 0.1}, "multipliers": {"cultureType": {"Hunting": 1.2}}},
	{"i": 33, "name": "Saltpeter", "tags": ["military", "mineral"], "color": "#e6e3e3", "value": 2, "unit": "barrel", "chance": 3, "distribution": "biome(1, 2) || (minHeight(50) && random(20))", "demandCoverage": {}},
	{"i": 34, "name": "Coal", "tags": ["fuel"], "color": "#5a6a75", "value": 3, "unit": "wain", "chance": 3, "distribution": "minHeight(40) || (minHeight(20) && elevation(25))", "demandCoverage": {"utilities": 0.5}},
	{"i": 35, "name": "Oil", "tags": ["fuel"], "color": "#565656", "value": 3, "unit": "barrel", "chance": 2, "distribution": "biome(1, 2, 10) || (shore(-1) && minTemp(18) && random(15))", "demandCoverage": {"utilities": 1}},
	{"i": 36, "name": "Mahogany", "tags": ["luxury"], "color": "#a45a52", "value": 7, "unit": "pile", "chance": 1, "distribution": "biome(5, 7) && random(50)", "demandCoverage": {"luxury": 1}},
	{"i": 37, "name": "Whales", "tags": ["food", "aquatic", "fuel"], "color": "#7fcdff", "value": 1, "unit": "barrel", "chance": 3, "distribution": "shore(-1) && type('ocean') && maxTemp(7)", "demandCoverage": {"food": 1, "utilities": 0.2}, "multipliers": {"cultureType": {"Naval": 1.4, "Nomadic": 0.5}}},
	{"i": 38, "name": "Sugarcane", "tags": ["preservative", "food"], "color": "#7abf87", "value": 4, "unit": "bag", "chance": 3, "distribution": "biome(7)", "demandCoverage": {"food": 0.6, "luxury": 0.4}},
	{"i": 39, "name": "Tea", "tags": ["luxury"], "color": "#d0f0c0", "value": 5, "unit": "bag", "chance": 2, "distribution": "minHeight(40) && (biome(5) || (biome(7) || biome(8)))", "demandCoverage": {"luxury": 1}, "multipliers": {"cultureType": {"Highland": 1.2}}},
	{"i": 40, "name": "Tobacco", "tags": ["luxury"], "color": "#6D5843", "value": 5, "unit": "bag", "chance": 1, "distribution": "random(20) && (biome(3) || (biome(5) || biome(6)))", "demandCoverage": {"luxury": 1}},
	{"i": 41, "name": "Clay", "tags": ["mineral", "construction"], "color": "#b07c60", "value": 1, "unit": "wain", "chance": 5, "distribution": "minTemp(8) && (shore(1) || river())", "demandCoverage": {"construction": 1}, "multipliers": {"cultureType": {"River": 1.4, "Lake": 1.4}}},
	{"i": 42, "name": "White sand", "tags": ["mineral"], "color": "#e6d69c", "value": 1, "unit": "wain", "chance": 4, "distribution": "minTemp(8) && (shore(1) || river())", "multipliers": {"cultureType": {"River": 1.4, "Lake": 1.4}}},
	{"i": 43, "name": "Leather", "tags": ["clothing", "military"], "color": "#8b5a2b", "value": 4, "unit": "roll", "chance": 0, "multipliers": {"cultureType": {"Naval": 0.6}}},
	{"i": 44, "name": "Cloth", "tags": ["clothing"], "color": "#e8e69c", "value": 4, "unit": "bolt", "chance": 0, "demandCoverage": {"utilities": 0.2}},
	{"i": 45, "name": "Garments", "tags": ["clothing"], "color": "#bd21ec", "value": 9, "unit": "set", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 46, "name": "Ceramics", "tags": ["storage", "construction"], "color": "#c1440e", "value": 6, "unit": "wain", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 47, "name": "Glass", "tags": ["storage", "construction"], "color": "#a0c8e8", "value": 7, "unit": "wain", "chance": 0, "demandCoverage": {"luxury": 1}, "multipliers": {"cultureType": {"Nomadic": 0.2}}},
	{"i": 48, "name": "Ropes", "tags": ["naval", "construction"], "color": "#ba9773", "value": 4, "unit": "coil", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 49, "name": "Paper", "tags": ["ritual", "educational"], "color": "#f5f5dc", "value": 5, "unit": "ream", "chance": 0, "demandCoverage": {}},
	{"i": 50, "name": "Ink", "tags": ["ritual", "educational"], "color": "#000000", "value": 5, "unit": "bottle", "chance": 0, "demandCoverage": {}},
	{"i": 51, "name": "Books", "tags": ["ritual", "educational"], "color": "#deb887", "value": 13, "unit": "volume", "chance": 0, "demandCoverage": {"luxury": 1}, "multipliers": {"cultureType": {"Nomadic": 0.2, "Hunting": 0.5}}},
	{"i": 52, "name": "Sails", "tags": ["naval"], "color": "#ffffff", "value": 7, "unit": "set", "chance": 0, "demandCoverage": {"military": 1}},
	{"i": 53, "name": "Ships", "tags": ["naval"], "color": "#654321", "value": 50, "unit": "ship", "chance": 0, "demandCoverage": {"military": 0.5}, "multipliers": {"cultureType": {"Naval": 2}}},
	{"i": 54, "name": "Boots", "tags": ["clothing", "military"], "color": "#654321", "value": 6, "unit": "pair", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 55, "name": "Harnesses", "tags": ["military"], "color": "#a0522d", "value": 8, "unit": "set", "chance": 0, "demandCoverage": {"military": 1}, "multipliers": {"cultureType": {"Nomadic": 1.2}}},
	{"i": 56, "name": "Barrels", "tags": ["naval", "storage"], "color": "#b46e3b", "value": 3, "unit": "barrel", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 57, "name": "Bronze", "tags": ["military"], "color": "#e46f21", "value": 9, "unit": "wagon", "chance": 0, "multipliers": {"cultureType": {"Highland": 1.2}}},
	{"i": 58, "name": "Tools", "tags": ["construction", "military"], "color": "#808080", "value": 17, "unit": "set", "chance": 0, "demandCoverage": {"utilities": 1}},
	{"i": 59, "name": "Arms", "tags": ["military"], "color": "#333333", "value": 25, "unit": "set", "chance": 0, "demandCoverage": {"military": 1}},
	{"i": 60, "name": "Gunpowder", "tags": ["military"], "color": "#b0c4de", "value": 10, "unit": "barrel", "chance": 0, "demandCoverage": {"military": 2}},
	{"i": 61, "name": "Artillery", "tags": ["military"], "color": "#cd7f32", "value": 21, "unit": "cannon", "chance": 0, "demandCoverage": {"military": 1}},
	{"i": 62, "name": "Coins", "tags": ["currency"], "color": "#ffd700", "value": 25, "unit": "bag", "chance": 0, "demandCoverage": {"luxury": 1}},
	{"i": 63, "name": "Jewelry", "tags": ["luxury"], "color": "#34861b", "value": 34, "unit": "piece", "chance": 0, "demandCoverage": {"luxury": 1}},
	{"i": 64, "name": "Preserved food", "tags": ["food"], "color": "#c2b280", "value": 4, "unit": "wain", "chance": 0, "demandCoverage": {"food": 1}},
	{"i": 65, "name": "Vinegar", "tags": ["food", "preservative"], "color": "#9b111e", "value": 2, "unit": "barrel", "chance": 0, "demandCoverage": {"utilities": 0.5}},
	{"i": 66, "name": "Cheese", "tags": ["food"], "color": "#f5e1a4", "value": 4, "unit": "wain", "chance": 0, "demandCoverage": {"food": 1}},
	{"i": 67, "name": "Beer", "tags": ["food"], "color": "#fbb117", "value": 7, "unit": "barrel", "chance": 0, "demandCoverage": {"food": 1}},
	{"i": 68, "name": "Liquor", "tags": ["food", "luxury"], "color": "#8a0303", "value": 9, "unit": "vessel", "chance": 0, "demandCoverage": {"luxury": 1}},
	{"i": 69, "name": "Candles", "tags": ["luxury", "ritual"], "color": "#fffacd", "value": 8, "unit": "block", "chance": 0, "demandCoverage": {"utilities": 0.5, "luxury": 0.5}},
	{"i": 70, "name": "Soap", "tags": ["luxury", "ritual"], "color": "#e0e4cc", "value": 5, "unit": "barrel", "chance": 0, "demandCoverage": {"utilities": 0.4, "luxury": 0.6}},
	{"i": 71, "name": "Perfume", "tags": ["luxury", "ritual"], "color": "#ff69b4", "value": 17, "unit": "bottle", "chance": 0, "demandCoverage": {"luxury": 2}},]

const DEMAND_PRIORITY := ["food", "utilities", "construction", "military", "luxury"]

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


## Assign resources to cells. Port of GoodsModule.generate(): shuffled cell
## walk, per-good chance roll + distribution expression, max ~200 cells per
## 5000 per resource.
func generate() -> void:
	pack.good = PackedInt32Array()
	pack.good.resize(pack.cell_count())

	var resource_max_cells: int = int(ceil((200.0 * pack.cell_count()) / 5000.0))
	var resources := {}
	var cell_order: Array = range(pack.cell_count())
	_shuffle(cell_order)
	var goods: Array = GOODS_DATA.duplicate()
	var glacier_habitable: bool = pack.biomes.size() > 11 and int(pack.biomes[11].get("habitability", 0)) > 0

	for cell_id: int in cell_order:
		if int(cell_id) % 10 == 0:
			_shuffle(goods)
		if pack.biome[cell_id] == 11 and not glacier_habitable:
			continue # skip glaciers
		for good: Dictionary in goods:
			var chance: float = float(good.get("chance", 0.0))
			var distribution: String = good.get("distribution", "")
			if distribution.is_empty() or chance <= 0.0:
				continue
			if int(resources.get(good["i"], 0)) >= resource_max_cells:
				continue
			if rng.random() * 100.0 > chance:
				continue
			if not eval_distribution(distribution, int(cell_id)):
				continue
			pack.good[cell_id] = int(good["i"])
			resources[good["i"]] = int(resources.get(good["i"], 0)) + 1
			break


func _shuffle(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = int(rng.random() * float(i + 1))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Total output of a good in a biome per rural cell (biomeOutput table).
func biome_output(good_id: int, biome_id: int) -> float:
	if good_id <= 0 or good_id > GOODS_DATA.size():
		return 0.0
	var output: Dictionary = GOODS_DATA[good_id - 1].get("biomeOutput", {})
	return float(output.get(str(biome_id), 0.0))


## Per-biome production table: biome -> [{good, production}].
func biomes_production() -> Dictionary:
	var out := {}
	for good: Dictionary in GOODS_DATA:
		var output: Dictionary = good.get("biomeOutput", {})
		for biome_key: String in output:
			var production: float = float(output[biome_key])
			if production == 0.0:
				continue
			if not out.has(int(biome_key)):
				out[int(biome_key)] = []
			out[int(biome_key)].append({"goodId": int(good["i"]), "production": production})
	return out


# ---------------------------------------------------------------------------
# Distribution expression evaluator. Grammar (subset used by GOODS_DATA):
#   expr := term ("||" term)*   term := factor ("&&" factor)*
#   factor := "!" factor | "(" expr ")" | call | number
#   call := ident "(" [arg ("," arg)*] ")"   arg := number | string

func eval_distribution(expression: String, cell_id: int) -> bool:
	var tokens: Array = _tokenize(expression)
	if tokens.is_empty():
		return false
	var pos := {"i": 0}
	var result: bool = _parse_or(tokens, pos, cell_id)
	return result


func _tokenize(expression: String) -> Array:
	var tokens: Array = []
	var i: int = 0
	var n: int = expression.length()
	while i < n:
		var ch: String = expression[i]
		if ch == " " or ch == "\t":
			i += 1
		elif ch == "(":
			tokens.append({"t": "("})
			i += 1
		elif ch == ")":
			tokens.append({"t": ")"})
			i += 1
		elif ch == ",":
			tokens.append({"t": ","})
			i += 1
		elif ch == "!":
			tokens.append({"t": "!"})
			i += 1
		elif ch == "&" and i + 1 < n and expression[i + 1] == "&":
			tokens.append({"t": "&&"})
			i += 2
		elif ch == "|" and i + 1 < n and expression[i + 1] == "|":
			tokens.append({"t": "||"})
			i += 2
		elif ch == "'" or ch == "\"":
			var j: int = i + 1
			while j < n and expression[j] != ch:
				j += 1
			tokens.append({"t": "str", "v": expression.substr(i + 1, j - i - 1)})
			i = j + 1
		elif ch.is_valid_int() or ch == "-" or ch == ".":
			var j: int = i + 1
			while j < n and (expression[j].is_valid_int() or expression[j] == "." or expression[j] == "-"):
				j += 1
			tokens.append({"t": "num", "v": float(expression.substr(i, j - i))})
			i = j
		elif ch.is_valid_identifier():
			var j: int = i + 1
			while j < n and expression[j].is_valid_identifier():
				j += 1
			tokens.append({"t": "ident", "v": expression.substr(i, j - i)})
			i = j
		else:
			i += 1
	return tokens


func _peek(tokens: Array, pos: Dictionary) -> Dictionary:
	if pos["i"] < tokens.size():
		return tokens[pos["i"]]
	return {"t": "eof"}


func _parse_or(tokens: Array, pos: Dictionary, cell_id: int) -> bool:
	var result: bool = _parse_and(tokens, pos, cell_id)
	while _peek(tokens, pos)["t"] == "||":
		pos["i"] += 1
		var right: bool = _parse_and(tokens, pos, cell_id)
		result = result or right
	return result


func _parse_and(tokens: Array, pos: Dictionary, cell_id: int) -> bool:
	var result: bool = _parse_factor(tokens, pos, cell_id)
	while _peek(tokens, pos)["t"] == "&&":
		pos["i"] += 1
		var right: bool = _parse_factor(tokens, pos, cell_id)
		result = result and right
	return result
	# note: unlike JS &&/||, both sides are always evaluated. The boolean
	# result is identical; only the order of RNG consumption differs from the
	# original short-circuiting expressions.


func _parse_factor(tokens: Array, pos: Dictionary, cell_id: int) -> bool:
	var token: Dictionary = _peek(tokens, pos)
	if token["t"] == "!":
		pos["i"] += 1
		return not _parse_factor(tokens, pos, cell_id)
	if token["t"] == "(":
		pos["i"] += 1
		var result: bool = _parse_or(tokens, pos, cell_id)
		if _peek(tokens, pos)["t"] == ")":
			pos["i"] += 1
		return result
	if token["t"] == "ident":
		pos["i"] += 1
		var name_v: String = token["v"]
		var args: Array = []
		if _peek(tokens, pos)["t"] == "(":
			pos["i"] += 1
			while _peek(tokens, pos)["t"] != ")" and _peek(tokens, pos)["t"] != "eof":
				var arg: Dictionary = _peek(tokens, pos)
				if arg["t"] == "num" or arg["t"] == "str":
					args.append(arg["v"])
				pos["i"] += 1
			if _peek(tokens, pos)["t"] == ")":
				pos["i"] += 1
		return _call_method(name_v, args, cell_id)
	if token["t"] == "num":
		pos["i"] += 1
		return float(token["v"]) != 0.0
	pos["i"] += 1
	return false


## Port of GoodsModule.getMethods(): the primitives a distribution may call.
func _call_method(name_v: String, args: Array, cell_id: int) -> bool:
	match name_v:
		"random":
			var number: float = float(args[0]) if args.size() > 0 else 100.0
			return number >= 100.0 or (number > 0.0 and number / 100.0 > rng.random())
		"nth":
			var number: int = int(args[0]) if args.size() > 0 else 1
			return number > 0 and cell_id % number == 0
		"minHabitability":
			var min_hab: float = float(args[0]) if args.size() > 0 else 0.0
			return float(pack.biomes[pack.biome[cell_id]]["habitability"]) >= min_hab
		"habitability":
			return float(pack.biomes[pack.biome[cell_id]]["habitability"]) > rng.random() * 100.0
		"elevation":
			return float(pack.h[cell_id]) / 100.0 > rng.random()
		"biome":
			var b: int = pack.biome[cell_id]
			for arg: Variant in args:
				if int(arg) == b:
					return true
			return false
		"minHeight":
			var min_h: float = float(args[0]) if args.size() > 0 else 0.0
			return float(pack.h[cell_id]) >= min_h
		"maxHeight":
			var max_h: float = float(args[0]) if args.size() > 0 else 100.0
			return float(pack.h[cell_id]) <= max_h
		"minTemp":
			var min_t: float = float(args[0]) if args.size() > 0 else -255.0
			return float(grid.temp[pack.g[cell_id]]) >= min_t
		"maxTemp":
			var max_t: float = float(args[0]) if args.size() > 0 else 255.0
			return float(grid.temp[pack.g[cell_id]]) <= max_t
		"shore":
			var t: int = pack.t[cell_id]
			for arg: Variant in args:
				if int(arg) == t:
					return true
			return false
		"type":
			var feature: Dictionary = pack.feature_of(cell_id)
			if feature.is_empty():
				return false
			var subtype: String = feature.get("subtype", "")
			var ftype: String = feature.get("type", "")
			for arg: Variant in args:
				if str(arg) == subtype or str(arg) == ftype:
					return true
			return false
		"river":
			return pack.r[cell_id] != 0
	return false
