class_name FmgJourneys
extends RefCounted
## Journeys. Simplified port of journeys-generator.ts: random trips between
## burgs that follow the road network (BFS over the route cell adjacency).
## Journey: {i, start, end, cells, points}.

var rng: FmgRng
var pack: FmgGraph
var routes: FmgRoutes


func _init(rng_ref: FmgRng, pack_ref: FmgGraph, routes_ref: FmgRoutes) -> void:
	rng = rng_ref
	pack = pack_ref
	routes = routes_ref


func generate(count: int = 3) -> void:
	var burgs_with_roads: Array = []
	for burg in pack.burgs:
		if burg == null or int(burg.get("i", 0)) == 0:
			continue
		if routes.is_connected(int(burg["cell"])):
			burgs_with_roads.append(burg)
	if burgs_with_roads.size() < 2:
		return

	var journeys: Array = []
	for k: int in count:
		var start_burg: Dictionary = rng.ra(burgs_with_roads)
		var end_burg: Dictionary = start_burg
		for _attempt: int in 5:
			end_burg = rng.ra(burgs_with_roads)
			if end_burg != start_burg:
				break
		if end_burg == start_burg:
			continue
		var cells_arr: Array = _find_route_cells(int(start_burg["cell"]), int(end_burg["cell"]))
		if cells_arr.size() < 2:
			continue
		var points := PackedVector2Array()
		for cell_id: Variant in cells_arr:
			points.append(pack.points[int(cell_id)])
		journeys.append({
			"i": k,
			"start": int(start_burg["i"]),
			"end": int(end_burg["i"]),
			"cells": cells_arr,
			"points": points,
			"name": "%s — %s" % [start_burg["name"], end_burg["name"]]
		})
	pack.journeys = journeys


## BFS over the route adjacency graph (pack.cell_routes).
func _find_route_cells(start: int, exit: int) -> Array:
	if start == exit:
		return []
	if not pack.cell_routes.has(start):
		return []
	var from := {}
	var queue: Array = [start]
	from[start] = -1
	var guard: int = 0
	while not queue.is_empty() and guard < 100000:
		guard += 1
		var current: int = queue.pop_front()
		for next: Variant in (pack.cell_routes[current] as Dictionary).keys():
			var neib: int = int(next)
			if from.has(neib):
				continue
			from[neib] = current
			if neib == exit:
				var path: Array = [exit]
				var node: int = exit
				while node != start:
					node = int(from[node])
					path.append(node)
				path.reverse()
				return path
			queue.append(neib)
	return []
