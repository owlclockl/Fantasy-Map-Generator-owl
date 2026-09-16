class_name FmgMarkets
extends RefCounted
## Markets and trade. Port of markets-generator.ts (simplified edition):
## market centers picked among the biggest burgs with a spacing rule, market
## territories expanded with a multi-source Dijkstra, rural production stock,
## prices from demand/supply and deals between neighboring markets.
## The original worker-loop economy (production-generator.ts) is reduced to
## this stock/price/deal model — see production.gd.

const PRICE_FLOOR_FACTOR: float = 0.1
const PRICE_CEILING_FACTOR: float = 5.0
const LAPLACE_PRICE_SMOOTHING: float = 5.0

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref


func generate() -> void:
	var markets: Array = _create_markets()
	_expand_markets(markets)
	pack.markets = markets
	_collect_rural_production()
	_initialize_market_prices()
	_generate_deals()


## Score burgs by population (capitals and ports weighted higher) and place
## market centers with an increasing minimum spacing.
func _create_markets() -> Array:
	var scored: Array = []
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		var score: float = float(burg.get("population", 0.0))
		if int(burg.get("capital", 0)) == 1:
			score *= 2.5
		if int(burg.get("port", 0)) != 0:
			score *= 1.2
		score *= rng.random() * 2.0 + 0.5
		scored.append({"burg": burg, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))

	var burg_count: int = maxi(pack.burgs.size(), 1)
	var min_spacing: int = int((pack.width + pack.height) * 2.0 / pow(float(burg_count), 0.6))
	var markets: Array = []
	var placed: Array = [] # [x, y]

	for entry: Dictionary in scored:
		var burg: Dictionary = entry["burg"]
		var x: float = float(burg["x"])
		var y: float = float(burg["y"])
		var nearest_too_close: bool = false
		for pt: Variant in placed:
			var p: Vector2 = pt
			if p.distance_to(Vector2(x, y)) < float(min_spacing):
				nearest_too_close = true
				break
		if not nearest_too_close:
			markets.append({"i": markets.size() + 1, "centerBurgId": int(burg["i"]), "color": FmgColors.get_random_color(rng), "goods": {}})
			placed.append(Vector2(x, y))
			min_spacing += 1
	return markets


## Multi-source Dijkstra: every cell joins the closest (cheapest) market.
func _expand_markets(markets: Array) -> void:
	pack.market = PackedInt32Array()
	pack.market.resize(pack.cell_count())
	var cost := PackedFloat64Array()
	cost.resize(pack.cell_count())
	for i: int in pack.cell_count():
		cost[i] = INF
	var queue := FlatQueue.new()
	var trade_centers := {}

	for market: Dictionary in markets:
		var center_burg: Dictionary = pack.burgs[int(market["centerBurgId"])] if int(market["centerBurgId"]) < pack.burgs.size() else null
		if center_burg == null:
			continue
		trade_centers[int(market["centerBurgId"])] = true
		var start_cell: int = int(center_burg["cell"])
		pack.market[start_cell] = int(market["i"])
		cost[start_cell] = 1.0
		queue.push({"cellId": start_cell, "marketId": int(market["i"]), "burg": center_burg}, 1.0)

	while queue.size() > 0:
		var pair: Array = queue.pop_pair()
		var payload: Dictionary = pair[0]
		var cell_id: int = payload["cellId"]
		var market_id: int = payload["marketId"]
		var burg: Dictionary = payload["burg"]
		var priority: float = pair[1]

		for neib: int in pack.c[cell_id]:
			var is_water: bool = pack.h[neib] < 20
			var step: float = 10.0
			if is_water:
				step += 50.0
				if int(burg.get("port", 0)) != pack.f[neib]:
					step += 50.0
			else:
				if pack.f[int(burg["cell"])] != pack.f[neib]:
					step += 100.0
				if pack.state[neib] != 0 and int(burg.get("state", 0)) != pack.state[neib]:
					step += 100.0
			var total_cost: float = priority + step
			if total_cost >= cost[neib]:
				continue
			cost[neib] = total_cost
			queue.push({"cellId": neib, "marketId": market_id, "burg": burg}, total_cost)
			if is_water and pack.good[neib] == 0:
				continue # exclude water cells without goods
			pack.market[neib] = market_id

	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		burg["market"] = pack.market[int(burg["cell"])]
		burg["plaza"] = 1 if trade_centers.has(int(burg["i"])) else int(burg.get("plaza", 0))


## Rural production of every market cell goes to its market stock.
func _collect_rural_production() -> void:
	var biome_production: Dictionary = FmgGoods.new(rng, pack, grid).biomes_production()
	for cell_id: int in pack.cell_count():
		var market_id: int = pack.market[cell_id]
		if market_id == 0 or market_id > pack.markets.size():
			continue
		var market: Dictionary = pack.markets[market_id - 1]
		var produced: Dictionary = FmgProduction.cell_production(pack, grid, cell_id, biome_production)
		for good_key: Variant in produced:
			var good_id: int = int(good_key)
			var goods_dict: Dictionary = market["goods"]
			if not goods_dict.has(good_id):
				goods_dict[good_id] = {"stock": 0.0, "price": _good_value(good_id)}
			goods_dict[good_id]["stock"] = FmgRng.rn(float(goods_dict[good_id]["stock"]) + float(produced[good_key]), 2)


func _good_value(good_id: int) -> float:
	if good_id > 0 and good_id <= FmgGoods.GOODS_DATA.size():
		return float(FmgGoods.GOODS_DATA[good_id - 1].get("value", 1))
	return 1.0


## Price = base value × demand/supply ratio (simplified: demand from market
## population and the good's demand coverage; manufactured goods skipped).
func _initialize_market_prices() -> void:
	var population_by_market := {}
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		var market_id: int = int(burg.get("market", 0))
		if market_id == 0:
			continue
		population_by_market[market_id] = float(population_by_market.get(market_id, 0.0)) + float(burg.get("population", 0.0))
	for cell_id: int in pack.cell_count():
		if pack.h[cell_id] >= 20 and pack.market[cell_id] > 0:
			var rural_share: float = float(pack.pop[cell_id]) / 1000.0 # rural pop in the same units as burg population
			population_by_market[pack.market[cell_id]] = float(population_by_market.get(pack.market[cell_id], 0.0)) + rural_share

	for market: Dictionary in pack.markets:
		var population: float = float(population_by_market.get(int(market["i"]), 0.0))
		var goods_dict: Dictionary = market["goods"]
		for good: Dictionary in FmgGoods.GOODS_DATA:
			if not good.has("distribution"):
				continue
			var good_id: int = int(good["i"])
			if not goods_dict.has(good_id):
				goods_dict[good_id] = {"stock": 0.0, "price": float(good["value"])}
			var coverage: Dictionary = good.get("demandCoverage", {})
			var demand_factor: float = 0.0
			for cat: Variant in coverage:
				demand_factor += float(coverage[cat])
			var demand: float = population * demand_factor * 0.2
			var stock: float = float(goods_dict[good_id]["stock"])
			var ratio: float = (demand + LAPLACE_PRICE_SMOOTHING) / (stock + LAPLACE_PRICE_SMOOTHING)
			goods_dict[good_id]["price"] = FmgRng.rn(float(good["value"]) * clampf(ratio, PRICE_FLOOR_FACTOR, PRICE_CEILING_FACTOR), 2)


## Deals: each market trades its cheapest goods with the nearest markets.
func _generate_deals() -> void:
	pack.deals = []
	var deal_id: int = 0
	for market: Dictionary in pack.markets:
		var center: Dictionary = pack.burgs[int(market["centerBurgId"])] if int(market["centerBurgId"]) < pack.burgs.size() else null
		if center == null:
			continue
		var center_pos := Vector2(center["x"], center["y"])
		var others: Array = []
		for other: Dictionary in pack.markets:
			if other == market:
				continue
			var other_center: Dictionary = pack.burgs[int(other["centerBurgId"])] if int(other["centerBurgId"]) < pack.burgs.size() else null
			if other_center == null:
				continue
			others.append({"market": other, "dist": center_pos.distance_to(Vector2(other_center["x"], other_center["y"]))})
		others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
		for k: int in mini(2, others.size()):
			var partner: Dictionary = others[k]["market"]
			# sell goods cheaper here than at the partner's market
			var goods_here: Dictionary = market["goods"]
			var goods_there: Dictionary = partner["goods"]
			for good_key: Variant in goods_here:
				var good_id: int = int(good_key)
				if not goods_there.has(good_id):
					continue
				var price_here: float = float(goods_here[good_id]["price"])
				var price_there: float = float(goods_there[good_id]["price"])
				if price_there <= price_here * 1.1:
					continue
				var units: float = FmgRng.rn(minf(float(goods_here[good_id]["stock"]), float(goods_there[good_id].get("stock", 0.0)) + 1.0), 2)
				if units <= 0.0:
					continue
				var tax: float = FmgRng.rn(units * (price_there - price_here) * 0.1, 2)
				pack.deals.append({
					"i": deal_id, "seller": int(market["i"]), "sellerType": "market",
					"buyer": int(partner["i"]), "buyerType": "market",
					"good": good_id, "units": units, "price": price_here, "tax": tax
				})
				deal_id += 1
