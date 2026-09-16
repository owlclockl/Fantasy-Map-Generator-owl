class_name FmgProduction
extends RefCounted
## Economy summary. Port of production-generator.ts + states-generator.ts
## collectTaxes: rural cell production from biome output tables and resource
## bonuses, recipe manufacturing of produced goods, urban production per burg,
## state tax rates by government form and treasuries.
##
## RECIPES is a 1:1 port of the original `recipes` catalogue (good.recipes):
## output good id -> alternative ingredient maps {input good id: units per
## unit of output}. The per-burg worker loop with treasuries is simplified to
## a market-level pull model (see manufacture_all): market demand pulls
## outputs, demand propagates upstream through the recipe chains, and a
## workforce cap bounds total output.

const BONUS_RURAL_PRODUCTION: float = 0.25
const MAX_BONUS_PRODUCTION: float = 5.0
const BONUS_URBAN_PRODUCTION: float = 0.1

# manufacturing recipes, port of the original goods catalogue (good.recipes).
# Output good id -> array of alternative ingredient maps ({input id: units
# needed per unit of output}). Goods 34 (Coal) and 35 (Oil) are both gathered
# and manufactured, exactly like in the original.
const RECIPES := {
	32: [{1: 1.0}], # Tar <- Wood
	34: [{1: 1.5}], # Coal <- Wood
	35: [{14: 1.0}, {37: 1.0}], # Oil <- Olives | Whales
	43: [{10: 1.0}, {12: 1.0}, {18: 1.0}, {20: 1.0}], # Leather <- Cattle | Game | Horses | Camels
	44: [{30: 1.0}, {21: 1.0}, {26: 0.5}], # Cloth <- Sheep | Hemp | Silk
	45: [{44: 1.0, 24: 0.5}, {44: 0.5, 29: 1.0}], # Garments <- Cloth+Dyes | Cloth+Furs
	46: [{41: 1.0}], # Ceramics <- Clay
	47: [{42: 1.0}], # Glass <- White sand
	48: [{21: 1.0}], # Ropes <- Hemp
	49: [{21: 1.0}], # Paper <- Hemp
	50: [{35: 1.0}, {24: 0.5}], # Ink <- Oil | Dyes
	51: [{49: 1.0, 50: 0.5}, {43: 1.0, 50: 0.5}], # Books <- Paper+Ink | Leather+Ink
	52: [{44: 1.0}], # Sails <- Cloth
	53: [{1: 4.0, 52: 4.0, 48: 4.0, 32: 2.0}], # Ships <- Wood+Sails+Ropes+Tar
	54: [{43: 1.0}, {29: 0.5}], # Boots <- Leather | Furs
	55: [{43: 0.5, 4: 0.25}, {43: 0.5, 57: 0.25}, {43: 0.5, 5: 0.25}], # Harnesses <- Leather + Iron|Bronze|Copper
	56: [{1: 1.0}], # Barrels <- Wood
	57: [{5: 0.5, 34: 1.0}, {6: 0.5, 34: 1.0}], # Bronze <- Copper+Coal | Tin+Coal
	58: [{4: 0.5, 34: 1.0}, {57: 0.5, 34: 1.0}], # Tools <- Iron+Coal | Bronze+Coal
	59: [{4: 0.5, 34: 1.0, 43: 0.5}, {57: 0.25, 34: 1.0, 43: 0.5}], # Arms <- Iron|Bronze + Coal + Leather
	60: [{33: 0.5, 34: 0.5}], # Gunpowder <- Saltpeter+Coal
	61: [{4: 2.0, 34: 1.0}, {57: 1.0, 34: 1.0}], # Artillery <- Iron+Coal | Bronze+Coal
	62: [{8: 0.5, 34: 1.0}, {7: 1.0, 34: 1.0}], # Coins <- Gold+Coal | Silver+Coal
	63: [{23: 1.0, 8: 0.5}, {22: 1.0, 8: 0.5}, {28: 2.0, 8: 0.5}, {23: 1.0, 7: 1.0}, {22: 1.0, 7: 1.0}, {28: 2.0, 7: 1.0}], # Jewelry <- gems|pearls|amber + gold|silver
	64: [{11: 1.0, 16: 1.0}, {10: 1.0, 16: 1.0}, {12: 1.0, 16: 1.0}, {30: 1.0, 16: 1.0}, {11: 1.0, 65: 0.5}, {10: 1.0, 65: 0.5}, {12: 1.0, 65: 0.5}, {30: 1.0, 65: 0.5}, {11: 1.0, 1: 1.0}], # Preserved food <- fish|cattle|game|sheep + salt|vinegar, or fish+wood
	65: [{13: 1.0}, {15: 1.0}], # Vinegar <- Wine | Honey
	66: [{10: 0.5, 16: 0.25}, {30: 0.5, 16: 0.25}, {30: 0.5, 65: 0.25}, {10: 0.5, 65: 0.25}], # Cheese <- cattle|sheep + salt|vinegar
	67: [{9: 1.0, 56: 1.0}, {15: 0.5, 56: 1.0}], # Beer <- Grain+Barrels | Honey+Barrels
	68: [{9: 2.0, 1: 1.0, 56: 0.5}, {13: 1.0, 1: 1.0, 56: 0.5}, {9: 2.0, 1: 1.0, 46: 0.25}, {13: 1.0, 1: 1.0, 46: 0.25}, {9: 2.0, 1: 1.0, 47: 0.25}, {13: 1.0, 1: 1.0, 47: 0.25}], # Liquor <- grain|wine + wood + barrels|ceramics|glass
	69: [{15: 2.0}, {35: 1.0}], # Candles <- Honey | Oil
	70: [{14: 1.0}, {10: 1.0}], # Soap <- Olives | Cattle
	71: [{14: 1.0, 25: 0.5, 47: 0.5}, {14: 1.0, 12: 3.0, 47: 0.5}, {68: 0.25, 25: 0.5, 37: 0.5, 46: 0.5}], # Perfume <- olives + incense|game + glass, or liquor+incense+whales+ceramics
}

# demand targets per unit of population (DEMAND_TARGET_FACTORS)
const DEMAND_TARGET_FACTORS := {"food": 0.2, "utilities": 0.15, "construction": 0.1, "military": 0.08, "luxury": 0.07}

# workforce bound per market (the original caps each burg at MAX_WORKERS 1000)
const MAX_MARKET_WORKFORCE: float = 1000.0

# taxes per government form (states-generator.ts TAXES)
const TAXES := {
	"Monarchy": {"salesTax": 0.15, "pollTax": 0.2},
	"Theocracy": {"salesTax": 0.25, "pollTax": 0.1},
	"Union": {"salesTax": 0.07, "pollTax": 0.13},
	"Republic": {"salesTax": 0.05, "pollTax": 0.15},
	"Anarchy": {"salesTax": 0.0, "pollTax": 0.0},
	"Wild": {"salesTax": 0.0, "pollTax": 0.0}
}

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


## Rural production of one cell: biomeOutput × population × good modifiers,
## plus a capped bonus for the cell's resource. Port of
## Production.getCellProduction.
static func cell_production(pack_ref: FmgGraph, _grid_ref: FmgGraph, cell_id: int, biome_production: Dictionary) -> Dictionary:
	var produced := {}
	var is_water: bool = pack_ref.h[cell_id] < 20
	var pop: float = 0.0
	if is_water:
		for neib: int in pack_ref.c[cell_id]:
			pop += pack_ref.pop[neib]
	else:
		pop = pack_ref.pop[cell_id]
	if pop <= 0.0:
		return produced

	for entry: Variant in biome_production.get(pack_ref.biome[cell_id], []):
		var e: Dictionary = entry
		var good_id: int = int(e["goodId"])
		var amount: float = pop * float(e["production"]) * _modifiers(pack_ref, good_id, cell_id)
		produced[good_id] = FmgRng.rn(float(produced.get(good_id, 0.0)) + amount, 2)

	var bonus_good_id: int = pack_ref.good[cell_id]
	if bonus_good_id > 0:
		var bonus: float = minf(pop * BONUS_RURAL_PRODUCTION, MAX_BONUS_PRODUCTION)
		produced[bonus_good_id] = FmgRng.rn(float(produced.get(bonus_good_id, 0.0)) + bonus * _modifiers(pack_ref, bonus_good_id, cell_id), 2)
	return produced


## Good multipliers by culture type (subset of Production.getModifiers).
static func _modifiers(pack_ref: FmgGraph, good_id: int, cell_id: int) -> float:
	if good_id <= 0 or good_id > FmgGoods.GOODS_DATA.size():
		return 1.0
	var multipliers: Dictionary = FmgGoods.GOODS_DATA[good_id - 1].get("multipliers", {})
	if multipliers.is_empty():
		return 1.0
	var culture_id: int = pack_ref.culture[cell_id]
	var culture_type: String = ""
	var burg_id: int = pack_ref.burg[cell_id]
	if burg_id > 0 and burg_id < pack_ref.burgs.size() and pack_ref.burgs[burg_id] != null:
		culture_type = pack_ref.burgs[burg_id].get("type", "")
	elif culture_id > 0 and culture_id < pack_ref.cultures.size() and pack_ref.cultures[culture_id] != null:
		culture_type = pack_ref.cultures[culture_id].get("type", "")
	var by_type: Dictionary = multipliers.get("cultureType", {})
	return float(by_type.get(culture_type, 1.0))


## Urban production: each burg works the goods available in its market area.
func produce() -> void:
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		var market_id: int = int(burg.get("market", 0))
		var market: Dictionary = {}
		if market_id > 0 and market_id <= pack.markets.size():
			market = pack.markets[market_id - 1]
		var population: float = float(burg.get("population", 0.0))
		var records: Array = []
		var product_value: float = 0.0

		var goods_dict: Dictionary = market.get("goods", {})
		for good_key: Variant in goods_dict:
			var good_id: int = int(good_key)
			var stock: float = float(goods_dict[good_key].get("stock", 0.0))
			if stock <= 0.0:
				continue
			var bonus: float = clampf(population * BONUS_URBAN_PRODUCTION, 0.5, MAX_BONUS_PRODUCTION)
			var units: float = FmgRng.rn(minf(bonus, stock), 2)
			if units <= 0.0:
				continue
			records.append({"goodId": good_id, "units": units})
			product_value += units * float(goods_dict[good_key].get("price", _good_value(good_id)))
		burg["production"] = records
		burg["product"] = FmgRng.rn(product_value, 2)


func _good_value(good_id: int) -> float:
	if good_id > 0 and good_id <= FmgGoods.GOODS_DATA.size():
		return float(FmgGoods.GOODS_DATA[good_id - 1].get("value", 1))
	return 1.0


## Market population in burg-population units: urban burgs plus rural cells.
## Shared by manufacturing (workforce, demand) and market pricing.
static func market_population(pack_ref: FmgGraph) -> Dictionary:
	var population_by_market := {}
	for burg in pack_ref.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		var market_id: int = int(burg.get("market", 0))
		if market_id == 0:
			continue
		population_by_market[market_id] = float(population_by_market.get(market_id, 0.0)) + float(burg.get("population", 0.0))
	for cell_id: int in pack_ref.cell_count():
		if pack_ref.h[cell_id] >= 20 and pack_ref.market[cell_id] > 0:
			var rural_share: float = float(pack_ref.pop[cell_id]) / 1000.0
			population_by_market[pack_ref.market[cell_id]] = float(population_by_market.get(pack_ref.market[cell_id], 0.0)) + rural_share
	return population_by_market


## Recipe manufacturing for every market. Runs after rural production is
## collected and before prices are set, so manufactured goods are priced and
## traded like raw ones. Pull model per market:
## 1. demand targets from market population, current coverage from stocks;
## 2. desired outputs from unmet shortages, pulled upstream through recipe
##    chains (Books pull Paper and Ink, Ships pull Sails, Ropes and Tar...);
## 3. workforce cap with proportional scale-down;
## 4. production in chain order (ingredients before outputs), consuming
##    ingredient stocks and adding output stocks with the culture modifier.
## Results are logged in market["manufacturing"].
func manufacture_all() -> void:
	var populations: Dictionary = market_population(pack)
	var depths: Dictionary = _recipe_depths()
	var ordered: Array = RECIPES.keys()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(depths[a]) < int(depths[b]) or (int(depths[a]) == int(depths[b]) and int(a) < int(b)))
	for market in pack.markets:
		_manufacture_market(market, float(populations.get(int(market.get("i", 0)), 0.0)), ordered)


func _manufacture_market(market: Dictionary, population: float, ordered: Array) -> void:
	var goods_dict: Dictionary = market.get("goods", {})
	if population <= 0.0 or goods_dict.is_empty():
		market["manufacturing"] = []
		return

	# demand targets and current coverage from stocks
	var targets := {}
	var coverage := {}
	for category: String in DEMAND_TARGET_FACTORS:
		targets[category] = population * float(DEMAND_TARGET_FACTORS[category])
		coverage[category] = 0.0
	for key: Variant in goods_dict:
		var stock: float = float((goods_dict[key] as Dictionary).get("stock", 0.0))
		if stock <= 0.0:
			continue
		var stock_coverage: Dictionary = _demand_coverage(int(key))
		for category: String in stock_coverage:
			coverage[category] = float(coverage[category]) + stock * float(stock_coverage[category])

	# desired outputs from unmet shortages
	var desired := {}
	for gid: Variant in ordered:
		var good_coverage: Dictionary = _demand_coverage(int(gid))
		var need: float = 0.0
		for category: String in good_coverage:
			var weight: float = float(good_coverage[category])
			if weight > 0.0:
				need = maxf(need, maxf(float(targets[category]) - float(coverage[category]), 0.0) / weight)
		if need > 0.001:
			desired[int(gid)] = need
	if desired.is_empty():
		market["manufacturing"] = []
		return

	# pull demand upstream through the chains, deepest goods first
	for idx: int in range(ordered.size() - 1, -1, -1):
		var gid: int = int(ordered[idx])
		if not desired.has(gid):
			continue
		var recipe: Dictionary = (RECIPES[gid] as Array)[_choose_recipe(gid, goods_dict)]
		for in_key: Variant in recipe:
			var input_id: int = int(in_key)
			if RECIPES.has(input_id):
				desired[input_id] = float(desired.get(input_id, 0.0)) + float(desired[gid]) * float(recipe[in_key])

	# workforce cap with proportional scale-down
	var total_desired: float = 0.0
	for gid: Variant in desired:
		total_desired += float(desired[gid])
	var workforce: float = minf(population, MAX_MARKET_WORKFORCE)
	var scale: float = 1.0
	if total_desired > workforce:
		scale = workforce / total_desired

	# produce in chain order: ingredients before their outputs
	var center_cell: int = _market_center_cell(market)
	var log: Array = []
	for gid: Variant in ordered:
		var output_id: int = int(gid)
		if not desired.has(output_id):
			continue
		var want: float = float(desired[output_id]) * scale
		if want < 0.01:
			continue
		var recipe: Dictionary = (RECIPES[output_id] as Array)[_choose_recipe(output_id, goods_dict)]
		var units: float = want
		for in_key: Variant in recipe:
			units = minf(units, _stock_of(goods_dict, int(in_key)) / maxf(float(recipe[in_key]), 0.0001))
		if units < 0.01:
			continue
		var modifier: float = _modifiers(pack, output_id, center_cell) if center_cell >= 0 else 1.0
		if modifier <= 0.0:
			continue
		var used := {}
		for in_key: Variant in recipe:
			var need_amount: float = units * float(recipe[in_key])
			_add_stock(goods_dict, int(in_key), -need_amount)
			used[int(in_key)] = FmgRng.rn(need_amount, 2)
		var made: float = FmgRng.rn(units * modifier, 2)
		_add_stock(goods_dict, output_id, made)
		log.append({"goodId": output_id, "units": made, "recipe": used})
	market["manufacturing"] = log


## demandCoverage table of a good ({category: weight}), empty if none.
static func _demand_coverage(good_id: int) -> Dictionary:
	if good_id <= 0 or good_id > FmgGoods.GOODS_DATA.size():
		return {}
	return FmgGoods.GOODS_DATA[good_id - 1].get("demandCoverage", {})


## chain depth of every manufactured good: 1 + deepest manufactured input
## over the shallowest alternative (raw goods are depth 0).
func _recipe_depths() -> Dictionary:
	var depths := {}
	for gid: Variant in RECIPES:
		depths[int(gid)] = _depth_of(int(gid), {})
	return depths


func _depth_of(good_id: int, visiting: Dictionary) -> int:
	if not RECIPES.has(good_id):
		return 0
	if visiting.has(good_id):
		return 99 # cycle guard; the catalogue is acyclic
	visiting[good_id] = true
	var best: int = 99
	for alt: Variant in (RECIPES[good_id] as Array):
		var depth: int = 0
		for in_key: Variant in (alt as Dictionary):
			depth = maxi(depth, _depth_of(int(in_key), visiting))
		best = mini(best, depth + 1)
	visiting.erase(good_id)
	return best


## the recipe alternative with the most available ingredients (limiting
## input stock first, catalogue order breaks ties).
func _choose_recipe(good_id: int, goods_dict: Dictionary) -> int:
	var alternatives: Array = RECIPES[good_id]
	var best_idx: int = 0
	var best_score: float = -1.0
	for i: int in alternatives.size():
		var limiting: float = INF
		for in_key: Variant in (alternatives[i] as Dictionary):
			limiting = minf(limiting, _stock_of(goods_dict, int(in_key)) / maxf(float((alternatives[i] as Dictionary)[in_key]), 0.0001))
		if limiting > best_score:
			best_score = limiting
			best_idx = i
	return best_idx


static func _stock_of(goods_dict: Dictionary, good_id: int) -> float:
	if goods_dict.has(good_id):
		return float((goods_dict[good_id] as Dictionary).get("stock", 0.0))
	if goods_dict.has(str(good_id)):
		return float((goods_dict[str(good_id)] as Dictionary).get("stock", 0.0))
	return 0.0


static func _add_stock(goods_dict: Dictionary, good_id: int, delta: float) -> void:
	var key: Variant = good_id
	if not goods_dict.has(key) and goods_dict.has(str(good_id)):
		key = str(good_id)
	if not goods_dict.has(key):
		goods_dict[key] = {"stock": 0.0, "price": 1.0}
	goods_dict[key]["stock"] = FmgRng.rn(maxf(float((goods_dict[key] as Dictionary).get("stock", 0.0)) + delta, 0.0), 2)


## market center burg's cell, for culture-type production modifiers.
func _market_center_cell(market: Dictionary) -> int:
	var center_id: int = int(market.get("centerBurgId", 0))
	if center_id > 0 and center_id < pack.burgs.size() and pack.burgs[center_id] != null:
		return int((pack.burgs[center_id] as Dictionary).get("cell", -1))
	return -1


## State tax rates by form + treasuries: deal taxes + poll tax over the
## population (states-generator.ts collectTaxes).
func collect_taxes() -> void:
	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		var form: String = state.get("form", "Monarchy")
		var taxes: Dictionary = TAXES.get(form, TAXES["Monarchy"])
		state["salesTax"] = float(taxes["salesTax"])
		state["pollTax"] = float(taxes["pollTax"])
		state["treasury"] = 0.0

	for deal: Variant in pack.deals:
		var d: Dictionary = deal
		var tax: float = float(d.get("tax", 0.0))
		if tax <= 0.0:
			continue
		var seller_state: int = 0
		if d.get("sellerType", "") == "burg" and int(d["seller"]) < pack.burgs.size():
			seller_state = int(pack.burgs[int(d["seller"])].get("state", 0))
		elif d.get("sellerType", "") == "market" and int(d["seller"]) <= pack.markets.size():
			var market: Dictionary = pack.markets[int(d["seller"]) - 1]
			var center_burg_id: int = int(market.get("centerBurgId", 0))
			if center_burg_id > 0 and center_burg_id < pack.burgs.size() and pack.burgs[center_burg_id] != null:
				seller_state = int(pack.burgs[center_burg_id].get("state", 0))
		if seller_state > 0 and seller_state < pack.states.size() and pack.states[seller_state] != null:
			pack.states[seller_state]["treasury"] = float(pack.states[seller_state].get("treasury", 0.0)) + tax

	for state in pack.states:
		if state == null or int(state.get("i", 0)) == 0:
			continue
		var population: float = float(state.get("rural", 0.0)) + float(state.get("urban", 0.0))
		state["treasury"] = FmgRng.rn(float(state.get("treasury", 0.0)) + float(state.get("pollTax", 0.0)) * population, 2)
