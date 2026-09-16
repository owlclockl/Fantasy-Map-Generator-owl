class_name FmgMarkers
extends RefCounted
## Points of interest. Port of markers-generator.ts: candidate cells per
## type, selection by min/each quotas, flavored names and legends.
## Marker: {i, type, icon, cell, x, y, name, legend}.

var rng: FmgRng
var pack: FmgGraph
var grid: FmgGraph
var routes: FmgRoutes
var occupied := PackedByteArray()


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, grid_ref: FmgGraph, routes_ref: FmgRoutes) -> void:
	rng = rng_ref
	pack = pack_ref
	grid = grid_ref
	routes = routes_ref


func generate() -> void:
	pack.markers = []
	occupied = PackedByteArray()
	occupied.resize(pack.cell_count())

	var configs: Array = [
		{"type": "volcanoes", "icon": "🌋", "min": 10, "each": 500, "list": _list_volcanoes, "add": _add_volcano},
		{"type": "hot-springs", "icon": "♨️", "min": 30, "each": 1200, "list": _list_hot_springs, "add": _add_hot_spring},
		{"type": "water-sources", "icon": "💧", "min": 1, "each": 1000, "list": _list_water_sources, "add": _add_water_source},
		{"type": "mines", "icon": "⛏️", "min": 1, "each": 15, "list": _list_mines, "add": _add_mine},
		{"type": "bridges", "icon": "🌉", "min": 1, "each": 5, "list": _list_bridges, "add": _add_bridge},
		{"type": "inns", "icon": "🍻", "min": 1, "each": 10, "list": _list_inns, "add": _add_inn},
		{"type": "lighthouses", "icon": "🚨", "min": 1, "each": 2, "list": _list_lighthouses, "add": _add_lighthouse},
		{"type": "waterfalls", "icon": "⟱", "min": 1, "each": 5, "list": _list_waterfalls, "add": _add_waterfall},
		{"type": "battlefields", "icon": "⚔️", "min": 50, "each": 700, "list": _list_battlefields, "add": _add_battlefield},
		{"type": "dungeons", "icon": "🗝️", "min": 30, "each": 200, "list": _list_dungeons, "add": _add_dungeon},
		{"type": "lake-monsters", "icon": "🐉", "min": 2, "each": 10, "list": _list_lake_monsters, "add": _add_lake_monster},
		{"type": "sea-monsters", "icon": "🦑", "min": 50, "each": 700, "list": _list_sea_monsters, "add": _add_sea_monster},
		{"type": "hill-monsters", "icon": "👹", "min": 30, "each": 600, "list": _list_hill_monsters, "add": _add_hill_monster},
		{"type": "sacred-mountains", "icon": "🗻", "min": 1, "each": 5, "list": _list_sacred_mountains, "add": _add_sacred_mountain},
		{"type": "sacred-forests", "icon": "🌳", "min": 30, "each": 1000, "list": _list_sacred_forests, "add": _add_sacred_forest},
		{"type": "sacred-pineries", "icon": "🌲", "min": 30, "each": 800, "list": _list_sacred_pineries, "add": _add_sacred_pinery},
		{"type": "sacred-palm-groves", "icon": "🌴", "min": 1, "each": 100, "list": _list_sacred_palm_groves, "add": _add_sacred_palm_grove},
		{"type": "brigands", "icon": "💰", "min": 50, "each": 100, "list": _list_brigands, "add": _add_brigands},
		{"type": "pirates", "icon": "🏴", "min": 40, "each": 300, "list": _list_pirates, "add": _add_pirates},
		{"type": "statues", "icon": "🗿", "min": 80, "each": 1200, "list": _list_statues, "add": _add_statue},
		{"type": "ruins", "icon": "🏺", "min": 80, "each": 1200, "list": _list_ruins, "add": _add_ruins},
		{"type": "libraries", "icon": "📚", "min": 10, "each": 1200, "list": _list_libraries, "add": _add_library},
		{"type": "caves", "icon": "🕳️", "min": 60, "each": 1000, "list": _list_caves, "add": _add_cave},
		{"type": "portals", "icon": "🌀", "min": 16, "each": 8, "list": _list_portals, "add": _add_portal}
	]

	for config: Variant in configs:
		var cfg: Dictionary = config
		var candidates: Array = (cfg["list"] as Callable).call()
		if candidates.size() < int(cfg["min"]):
			continue
		_shuffle(candidates)
		var count: int = int(ceil(float(candidates.size()) / float(cfg["each"])))
		for k: int in mini(count, candidates.size()):
			var cell: int = candidates[k]
			if occupied[cell] == 1:
				continue
			occupied[cell] = 1
			var marker := {
				"i": pack.markers.size(), "type": cfg["type"], "icon": cfg["icon"],
				"cell": cell, "x": pack.points[cell].x, "y": pack.points[cell].y,
				"name": "", "legend": ""
			}
			(cfg["add"] as Callable).call(marker, cell)
			pack.markers.append(marker)


func _shuffle(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = int(rng.random() * float(i + 1))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _free(cell_id: int) -> bool:
	return occupied[cell_id] == 0


func _proper(cell_id: int) -> String:
	return Names.get_culture(pack.culture[cell_id])


# ---------------------------------------------------------------------------
# candidate lists

func _list_volcanoes() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] >= 70:
			out.append(i)
	return out


func _list_hot_springs() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] > 50 and pack.culture[i] != 0:
			out.append(i)
	return out


func _list_water_sources() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] > 30 and pack.r[i] != 0:
			out.append(i)
	return out


func _list_mines() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] > 47 and pack.burg[i] != 0:
			out.append(i)
	return out


func _list_bridges() -> Array:
	var flux_sum: float = 0.0
	var flux_count: int = 0
	for i: int in pack.cell_count():
		if pack.fl[i] > 0.0:
			flux_sum += pack.fl[i]
			flux_count += 1
	var mean_flux: float = flux_sum / float(maxi(flux_count, 1))
	var out: Array = []
	for i: int in pack.cell_count():
		if not _free(i) or pack.burg[i] == 0 or pack.t[i] == 1 or pack.r[i] == 0:
			continue
		var burg: Dictionary = pack.burgs[pack.burg[i]] if pack.burg[i] < pack.burgs.size() else null
		if burg != null and float(burg.get("population", 0.0)) > 20.0 and pack.fl[i] > mean_flux:
			out.append(i)
	return out


func _list_inns() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.pop[i] > 5.0 and routes.is_crossroad(i):
			out.append(i)
	return out


func _list_lighthouses() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if not _free(i) or pack.harbor[i] <= 6:
			continue
		var ok: bool = false
		for neib: int in pack.c[i]:
			if pack.h[neib] < 20 and routes.is_connected(neib):
				ok = true
				break
		if ok:
			out.append(i)
	return out


func _list_waterfalls() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if not _free(i) or pack.r[i] == 0 or pack.h[i] < 50:
			continue
		for neib: int in pack.c[i]:
			if pack.h[neib] < 40 and pack.r[neib] != 0:
				out.append(i)
				break
	return out


func _list_battlefields() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.state[i] != 0 and pack.pop[i] > 2.0 and pack.h[i] < 50 and pack.h[i] > 25:
			out.append(i)
	return out


func _list_dungeons() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.pop[i] > 0.0 and pack.pop[i] < 3.0:
			out.append(i)
	return out


func _list_lake_monsters() -> Array:
	var out: Array = []
	for feature in pack.features:
		if feature == null or feature.is_empty():
			continue
		if feature.get("type", "") == "lake" and feature.get("subtype", "") == "freshwater":
			var first_cell: int = int(feature.get("firstCell", 0))
			if first_cell > 0 and _free(first_cell):
				out.append(first_cell)
	return out


func _list_sea_monsters() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if not _free(i) or pack.h[i] >= 20 or not routes.is_connected(i):
			continue
		if pack.feature_of(i).get("type", "") == "ocean":
			out.append(i)
	return out


func _list_hill_monsters() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] >= 50 and pack.pop[i] > 0.0:
			out.append(i)
	return out


func _list_sacred_mountains() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if not _free(i) or pack.h[i] < 70:
			continue
		var some_culture: bool = false
		var all_low: bool = true
		for neib: int in pack.c[i]:
			if pack.culture[neib] != 0:
				some_culture = true
			if pack.h[neib] >= 60:
				all_low = false
		if some_culture and all_low:
			out.append(i)
	return out


func _list_sacred_forests() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and pack.religion[i] != 0 and (pack.biome[i] == 6 or pack.biome[i] == 8):
			out.append(i)
	return out


func _list_sacred_pineries() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and pack.religion[i] != 0 and pack.biome[i] == 9:
			out.append(i)
	return out


func _list_sacred_palm_groves() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and pack.religion[i] != 0 and pack.biome[i] == 1:
			out.append(i)
	return out


func _list_brigands() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and routes.has_road(i):
			out.append(i)
	return out


func _list_pirates() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] < 20 and routes.is_connected(i):
			out.append(i)
	return out


func _list_statues() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] >= 20 and pack.h[i] < 40:
			out.append(i)
	return out


func _list_ruins() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and pack.h[i] >= 20 and pack.h[i] < 60:
			out.append(i)
	return out


func _list_libraries() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.culture[i] != 0 and pack.burg[i] != 0 and pack.pop[i] > 10.0:
			out.append(i)
	return out


func _list_caves() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] >= 45 and pack.burg[i] == 0:
			out.append(i)
	return out


func _list_portals() -> Array:
	var out: Array = []
	for i: int in pack.cell_count():
		if _free(i) and pack.h[i] >= 20 and pack.h[i] < 65:
			out.append(i)
	return out


# ---------------------------------------------------------------------------
# names and legends

func _add_volcano(marker: Dictionary, cell: int) -> void:
	var proper: String = _proper(cell)
	var roll: float = rng.random()
	marker["name"] = "Гора %s" % proper if roll < 0.3 else ("Вулкан %s" % proper if roll < 0.7 else proper)
	var status: String = "Спящий" if rng.P(0.6) else ("Действующий" if rng.P(0.4) else "Извергающийся")
	marker["legend"] = "%s вулкан." % status


func _add_hot_spring(marker: Dictionary, cell: int) -> void:
	var proper: String = _proper(cell)
	var temp: int = int(rng.gauss(35.0, 15.0, 20.0, 100.0))
	marker["name"] = "Горячие источники %s" % proper if rng.P(0.5) else proper
	marker["legend"] = "Геотермальные источники с водой около %d°. Считаются целебными." % temp


func _add_water_source(marker: Dictionary, cell: int) -> void:
	var source_type: String = rng.rw({
		"Целебный источник": 5, "Очищающий колодец": 2, "Зачарованный водоём": 1,
		"Ручей удачи": 1, "Фонтан молодости": 1, "Источник мудрости": 1,
		"Источник жизни": 1, "Источник юности": 1, "Целебный ручей": 1
	})
	marker["name"] = "%s %s" % [_proper(cell), source_type]
	marker["legend"] = "Легендарный источник, о котором шепчутся в древних преданиях."


func _add_mine(marker: Dictionary, cell: int) -> void:
	var resource: String = rng.rw({"соли": 5, "золота": 2, "серебра": 4, "меди": 2, "железа": 3, "свинца": 1, "олова": 1})
	var burg: Dictionary = pack.burgs[pack.burg[cell]] if pack.burg[cell] < pack.burgs.size() else null
	var burg_name: String = burg.get("name", "") if burg != null else ""
	marker["name"] = "%s — шахта %s" % [burg_name, resource]
	marker["legend"] = "%s добывает здесь %s." % [burg_name, resource]


func _add_bridge(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Мост %s" % _proper(cell)
	marker["legend"] = "Старинный мост через реку."


func _add_inn(marker: Dictionary, cell: int) -> void:
	var color: String = rng.ra(["Тёмный", "Золотой", "Красный", "Весёлый", "Пьяный", "Старый"])
	var animal: String = rng.ra(["Волк", "Кабан", "Олень", "Медведь", "Гусь", "Дракон"])
	marker["name"] = "Таверна «%s %s»" % [color, animal]
	marker["legend"] = "Постоялый двор на перекрёстке дорог."


func _add_lighthouse(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Маяк %s" % _proper(cell)
	marker["legend"] = "Маяк, указывающий кораблям путь в гавань."


func _add_waterfall(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Водопад %s" % _proper(cell)
	marker["legend"] = "Река срывается здесь с высокого уступа."


func _add_battlefield(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Поле битвы %s" % _proper(cell)
	marker["legend"] = "Здесь произошло великое сражение."


func _add_dungeon(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Подземелье %s" % _proper(cell)
	marker["legend"] = "Тёмные тоннели, уходящие глубоко под землю."


func _add_lake_monster(marker: Dictionary, cell: int) -> void:
	var feature: Dictionary = pack.feature_of(cell)
	marker["name"] = "Чудовище озера %s" % feature.get("name", _proper(cell))
	marker["legend"] = "Рыбаки клянутся, что видели в этих водах огромное существо."


func _add_sea_monster(marker: Dictionary, _cell: int) -> void:
	marker["name"] = "Морское чудовище"
	marker["legend"] = "Моряки обходят эти воды стороной."


func _add_hill_monster(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Чудовище холмов %s" % _proper(cell)
	marker["legend"] = "В этих холмах обитает нечто опасное."


func _add_sacred_mountain(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Священная гора %s" % _proper(cell)
	marker["legend"] = "Гора, почитаемая окрестными народами."


func _add_sacred_forest(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Священная роща %s" % _proper(cell)
	marker["legend"] = "Древний лес, где слышны голоса духов."


func _add_sacred_pinery(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Священный бор %s" % _proper(cell)
	marker["legend"] = "Сосновый бор, охраняемый жрецами."


func _add_sacred_palm_grove(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Священная пальмовая роща %s" % _proper(cell)
	marker["legend"] = "Оазис, дарованный богами."


func _add_brigands(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Разбойники %s" % _proper(cell)
	marker["legend"] = "На этой дороге промышляют разбойники."


func _add_pirates(marker: Dictionary, _cell: int) -> void:
	marker["name"] = "Пираты"
	marker["legend"] = "В этих водах замечены пиратские корабли."


func _add_statue(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Статуя %s" % _proper(cell)
	marker["legend"] = "Древнее изваяние неизвестного мастера."


func _add_ruins(marker: Dictionary, _cell: int) -> void:
	var ruin_type: String = rng.ra(["Город", "Крепость", "Храм", "Амфитеатр", "Акведук", "Могильник"])
	marker["name"] = "Руины %s" % ruin_type.to_lower()
	marker["legend"] = "Развалины былой цивилизации."


func _add_library(marker: Dictionary, cell: int) -> void:
	var burg: Dictionary = pack.burgs[pack.burg[cell]] if pack.burg[cell] < pack.burgs.size() else null
	var burg_name: String = burg.get("name", "") if burg != null else ""
	marker["name"] = "Библиотека %s" % burg_name
	marker["legend"] = "Хранилище древних манускриптов."


func _add_cave(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Пещера %s" % _proper(cell)
	marker["legend"] = "Глубокая пещера в скалах."


func _add_portal(marker: Dictionary, cell: int) -> void:
	marker["name"] = "Портал %s" % _proper(cell)
	marker["legend"] = "Мерцающий портал в иные земли."
