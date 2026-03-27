extends Node
## Orchestrates game lifecycle: new game, save, load, clear.
## Waits for BuildingPlacer and MapGenerator to register before starting.

const SAVE_PATH := "user://save_game.json"

var _placer: Node = null
var _map_gen: Node = null
var _camera: Camera3D = null
var _started := false

func register_placer(placer: Node) -> void:
	_placer = placer
	_try_start()

func register_map_generator(map_gen: Node) -> void:
	_map_gen = map_gen
	_try_start()

func _try_start() -> void:
	if _placer == null or _map_gen == null:
		return
	if _started:
		return
	_started = true
	_camera = get_viewport().get_camera_3d()
	if FileAccess.file_exists(SAVE_PATH):
		_load_game()
	else:
		_new_game()
	if not EventBus.building_placed.is_connected(_on_building_changed):
		EventBus.building_placed.connect(_on_building_changed)
	if not EventBus.building_moved.is_connected(_on_building_moved):
		EventBus.building_moved.connect(_on_building_moved)

func _new_game() -> void:
	ResourceManager.reset()
	# Place nucleo at center
	var nucleo_data := _load_building_data("nucleo")
	if nucleo_data:
		var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
		_placer.place_building_at(nucleo_data, center)
	# Generate random deposits
	_map_gen.generate_new_map()
	save_game()
	EventBus.game_new_started.emit()

func _load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		_new_game()
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_new_game()
		return
	var data: Dictionary = json.data

	# Restore resources
	if data.has("resources"):
		ResourceManager.set_amounts(data["resources"])

	# Restore buildings
	if data.has("buildings"):
		for entry in data["buildings"]:
			var building_data := _load_building_data(entry["id"])
			if building_data:
				_placer.place_building_at(building_data, Vector2i(entry["cell_x"], entry["cell_y"]))

	# Restore deposits
	if data.has("deposits"):
		for entry in data["deposits"]:
			_map_gen.spawn_deposit(entry["id"], Vector2i(entry["cell_x"], entry["cell_y"]))

	# Restore camera
	if data.has("camera") and _camera and _camera.has_method("set_state"):
		_camera.set_state(data["camera"])

	EventBus.game_load_completed.emit()

func save_game() -> void:
	var data := {}

	# Resources
	var res_all := ResourceManager.get_all()
	var resources := {}
	for type in res_all:
		resources[ResourceManager.get_type_name(type)] = res_all[type]
	data["resources"] = resources

	# Buildings
	data["buildings"] = _placer.get_all_placed_buildings()

	# Deposits
	data["deposits"] = _map_gen.get_all_deposits()

	# Camera
	if _camera and _camera.has_method("get_state"):
		data["camera"] = _camera.get_state()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	GridManager.clear_all()
	_placer = null
	_map_gen = null
	_camera = null
	_started = false
	get_tree().reload_current_scene()

func _on_building_changed(_data: Resource, _cell: Vector2i) -> void:
	save_game()

func _on_building_moved(_from: Vector2i, _to: Vector2i) -> void:
	save_game()

func _load_building_data(id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path) as BuildingData
	return null
