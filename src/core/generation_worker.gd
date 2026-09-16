class_name FmgGenerationWorker
extends RefCounted
## Runs the pure generation pipeline away from the main thread.
##
## The worker never touches the SceneTree, CanvasItem or UI. The live FmgSim
## is passed in only after the UI has disabled edits; this is important because
## the Names autoload resolves names against the global Sim singleton. The map
## view is hidden while the worker owns the simulation and is rebuilt after
## wait_to_finish().

var _options: Dictionary = {}
var _target: FmgSim = null
var _tail: String = ""
var _progress_mutex := Mutex.new()
var _stage_index: int = 0
var _stage_total: int = 1
var _stage_name: String = "Подготовка"


func _init(options: Dictionary = {}, target: FmgSim = null, tail: String = "") -> void:
	_options = options.duplicate(true)
	_target = target
	_tail = tail


func run() -> FmgSim:
	var target: FmgSim = _target
	if target == null:
		return null

	var started: int = Time.get_ticks_msec()
	var stages: Array
	match _tail:
		"heightmap":
			stages = target.pipeline_from_heightmap()
		"climate":
			stages = target.pipeline_from_climate()
		_:
			stages = target.pipeline()

	_progress_mutex.lock()
	_stage_total = maxi(stages.size(), 1)
	_progress_mutex.unlock()
	for index: int in stages.size()
		var stage: Array = stages[index]
		_set_progress(index, str(stage[0]))
		# Do not call FmgSim.run_stage here: that method emits a signal and
		# signals are intentionally kept on the main thread.
		var stage_fn: Callable = stage[1]
		stage_fn.call()
	_set_progress(stages.size(), "Готово")
	target.generation_time_ms = Time.get_ticks_msec() - started
	return target


func get_progress() -> Dictionary:
	_progress_mutex.lock()
	var snapshot := {"index": _stage_index, "total": _stage_total, "name": _stage_name}
	_progress_mutex.unlock()
	return snapshot


func _set_progress(index: int, name: String) -> void:
	_progress_mutex.lock()
	_stage_index = index
	_stage_name = name
	_progress_mutex.unlock()
