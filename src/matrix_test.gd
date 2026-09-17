extends Node2D
## Matrix test scene: run every heightmap template across several seeds at low
## density, verifying the pipeline and the full draw path don't error.
## Usage: godot --headless res://src/matrix_test.tscn

var sim: FmgSim = null
var view: MapView = null
var templates: Array = []
var seeds: Array = ["11", "42", "777"]
var index: int = 0
var failures: int = 0

func _ready() -> void:
	sim = get_node("/root/Sim") as FmgSim
	view = MapView.new()
	view.sim = sim
	add_child(view)
	templates = HeightmapTemplates.TEMPLATES.keys()
	templates.append_array(HeightmapTemplates.PRECREATED.keys()) # the 23 real worlds
	templates.push_front("random")
	sim.cells_desired = 1000
	sim.states_limit = 12
	sim.burgs_limit = 300
	_next()

func _next() -> void:
	if index >= templates.size() * seeds.size():
		print("[matrix] done, failures: ", failures)
		get_tree().quit(1 if failures > 0 else 0)
		return
	var template: String = templates[index % templates.size()]
	var seed: String = seeds[int(index / templates.size())]
	sim.seed_value = seed
	sim.template_id = template
	sim.poles_cache = {}
	var worker := FmgGenerationWorker.new({}, sim)
	var result: FmgSim = worker.run()
	if result == null:
		failures += 1
		print("[matrix] FAIL ", template, " ", seed)
	else:
		if result != sim:
			sim.adopt_generation(result)
		sim.map_generated.emit()
		view.rebuild_cache()
		for prop: Dictionary in view.get_property_list():
			var prop_name: String = str(prop.get("name", ""))
			if prop_name.begins_with("show_") and view.get(prop_name) is bool:
				view.set(prop_name, true)
		view.notification(CanvasItem.NOTIFICATION_DRAW)
		var rivers: int = maxi(sim.pack.rivers.size() - 1, 0)
		var states: int = 0
		for s in sim.pack.states:
			if s != null and int(s["i"]) > 0:
				states += 1
		print("[matrix] OK ", template, " seed=", seed, " rivers=", rivers, " states=", states,
			" geo=", sim.geo_map_size, "% ", sim.geography_text())
	index += 1
	_next.call_deferred()
