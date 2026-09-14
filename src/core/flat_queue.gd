class_name FlatQueue
extends RefCounted
## Minimal binary min-priority queue, port of the FlatQueue used by FMG.
## Payloads can be any Variant (int cell ids or [cell, culture] pairs).

var _items: Array = []
var _priorities := PackedFloat64Array()


func size() -> int:
	return _items.size()


func clear() -> void:
	_items = []
	_priorities = PackedFloat64Array()


func push(item: Variant, priority: float) -> void:
	_items.append(item)
	_priorities.append(priority)
	var child: int = _items.size() - 1
	while child > 0:
		var parent: int = (child - 1) >> 1
		if _priorities[parent] <= _priorities[child]:
			break
		_swap(parent, child)
		child = parent


## returns [payload, priority]
func pop_pair() -> Array:
	var top_payload: Variant = _items[0]
	var top_priority: float = _priorities[0]
	var last: int = _items.size() - 1
	_swap(0, last)
	_items.resize(last)
	_priorities.resize(last)
	var parent: int = 0
	while true:
		var child: int = parent * 2 + 1
		if child >= _items.size():
			break
		if child + 1 < _items.size() and _priorities[child + 1] < _priorities[child]:
			child += 1
		if _priorities[parent] <= _priorities[child]:
			break
		_swap(parent, child)
		parent = child
	return [top_payload, top_priority]


func pop() -> Variant:
	return pop_pair()[0]


func _swap(a: int, b: int) -> void:
	var ti: Variant = _items[a]
	_items[a] = _items[b]
	_items[b] = ti
	var tp: float = _priorities[a]
	_priorities[a] = _priorities[b]
	_priorities[b] = tp
