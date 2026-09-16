class_name FmgProduction
extends RefCounted
## Economy summary. Simplified port of production-generator.ts +
## states-generator.ts collectTaxes: rural cell production from biome output
## tables and resource bonuses, urban production per burg, state tax rates by
## government form and treasuries. The original worker-loop economy with
## recipes/demand satisfaction is reduced to this model.

const BONUS_RURAL_PRODUCTION: float = 0.25
const MAX_BONUS_PRODUCTION: float = 5.0
const BONUS_URBAN_PRODUCTION: float = 0.1

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
