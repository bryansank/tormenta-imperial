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
	if not EventBus.building_renamed.is_connected(_on_building_renamed):
		EventBus.building_renamed.connect(_on_building_renamed)
	if not EventBus.building_demolished.is_connected(_on_building_demolished):
		EventBus.building_demolished.connect(_on_building_demolished)

func _new_game() -> void:
	ResourceManager.reset()
	# Place nucleo at center (no build time for core)
	var nucleo_data := _load_building_data("nucleo")
	if nucleo_data:
		var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
		var node := _placer.place_building_at(nucleo_data, center)
		if node:
			ProductionManager.register_building(node, nucleo_data, 0.0)
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
				var node := _placer.place_building_at(building_data, Vector2i(entry["cell_x"], entry["cell_y"]))
				if not node:
					continue
				# Restore custom name
				if entry.has("custom_name") and entry["custom_name"] != "":
					node.set_meta("custom_name", entry["custom_name"])
					var label := node.get_node_or_null("NameLabel")
					if label and label is Label3D:
						label.text = entry["custom_name"]
				# Register with ProductionManager (restore construction state)
				var constr_remaining := 0.0
				if entry.has("construction_remaining"):
					constr_remaining = float(entry["construction_remaining"])
				ProductionManager.register_building(node, building_data, constr_remaining)

	# Restore deposits
	if data.has("deposits"):
		for entry in data["deposits"]:
			_map_gen.spawn_deposit(entry["id"], Vector2i(entry["cell_x"], entry["cell_y"]))

	# Restore camera
	if data.has("camera") and _camera and _camera.has_method("set_state"):
		_camera.set_state(data["camera"])

	# Apply offline progression
	if data.has("saved_at"):
		var saved_at: float = float(data["saved_at"])
		var now := Time.get_unix_time_from_system()
		var elapsed := now - saved_at
		if elapsed > 2.0:
			var earnings := ProductionManager.apply_offline_progression(elapsed)
			_show_offline_report(elapsed, earnings)

	EventBus.game_load_completed.emit()

func save_game() -> void:
	var data := {}
	data["saved_at"] = Time.get_unix_time_from_system()

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

func _on_building_renamed(_node: Node3D, _name: String) -> void:
	save_game()

func _on_building_demolished(_node: Node3D, _cell: Vector2i) -> void:
	save_game()

func _show_offline_report(elapsed: float, earnings: Dictionary) -> void:
	var has_any := false
	for res in earnings:
		if earnings[res] > 0:
			has_any = true
			break
	if not has_any:
		return

	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.7, 0.55, 0.15, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Mientras estuviste fuera (%s)" % _format_elapsed(elapsed)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var res_names := {"gold": "Oro", "steel": "Acero", "oil": "Petroleo", "wood": "Madera"}
	var res_colors := {
		"gold": Color(1.0, 0.85, 0.1),
		"steel": Color(0.7, 0.75, 0.8),
		"oil": Color(0.5, 0.4, 0.6),
		"wood": Color(0.55, 0.35, 0.15),
	}
	for res in earnings:
		if earnings[res] > 0:
			var lbl := Label.new()
			lbl.text = "+%d %s" % [earnings[res], res_names.get(res, res)]
			lbl.add_theme_font_size_override("font_size", 16)
			lbl.add_theme_color_override("font_color", res_colors.get(res, Color.WHITE))
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(lbl)

	canvas.add_child(panel)

	# Auto-dismiss after 5 seconds
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 1.5)
	tween.tween_callback(canvas.queue_free)

func _format_elapsed(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	var h := s / 3600
	var m := (s % 3600) / 60
	return "%dh %dm" % [h, m]

func _load_building_data(id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path) as BuildingData
	return null
