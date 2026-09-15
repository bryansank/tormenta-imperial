extends GdUnitTestSuite
## La cuadricula visible y suave (A10).
##
## La escena decia "plano de 50x50 desde (-25,-25)" y la rejilla real era 40
## celdas x 2.0 = 80x80 desde (-40,-40): las lineas no coincidian con nada. El
## overlay se ajusta ahora a GridManager al arrancar, asi que estos casos fijan
## que plano y shader miden lo que mide la rejilla.

const Overlay := preload("res://scripts/grid/GridOverlayControl.gd")

var _saved_visible := true

func before_test() -> void:
	_saved_visible = GameConfig.ui_grid_visible

func after_test() -> void:
	GameConfig.ui_grid_visible = _saved_visible

func _make_overlay() -> MeshInstance3D:
	var node: MeshInstance3D = auto_free(Overlay.new())
	node.mesh = PlaneMesh.new()
	(node.mesh as PlaneMesh).size = Vector2(50, 50)  # el valor viejo, a proposito
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/grid/grid_overlay.gdshader")
	mat.set_shader_parameter("grid_origin", Vector2(-25, -25))
	mat.set_shader_parameter("cell_size", 1.0)
	node.set_surface_override_material(0, mat)
	add_child(node)
	return node

func test_the_plane_covers_the_whole_grid_plus_the_edge_pad() -> void:
	var overlay := _make_overlay()
	var expected: Vector2 = GridManager.get_world_size() + Vector2(Overlay.EDGE_PAD, Overlay.EDGE_PAD) * 2.0
	assert_vector(overlay.get_plane_size()).is_equal_approx(expected, Vector2(0.001, 0.001))
	assert_vector(GridManager.get_world_size()).is_equal(Vector2(80, 80))

func test_the_shader_origin_and_cell_size_follow_the_grid() -> void:
	var overlay := _make_overlay()
	var mat := overlay.get_surface_override_material(0) as ShaderMaterial
	var origin: Vector3 = GridManager.get_origin()
	assert_vector(mat.get_shader_parameter("grid_origin")).is_equal(Vector2(origin.x, origin.z))
	assert_float(mat.get_shader_parameter("cell_size")).is_equal(GridManager.cell_size)

func test_the_plane_is_centred_on_the_grid() -> void:
	var overlay := _make_overlay()
	var origin: Vector3 = GridManager.get_origin()
	var size: Vector2 = GridManager.get_world_size()
	assert_float(overlay.position.x).is_equal_approx(origin.x + size.x * 0.5, 0.001)
	assert_float(overlay.position.z).is_equal_approx(origin.z + size.y * 0.5, 0.001)

func test_the_grid_is_on_by_default() -> void:
	# Fresh preferences (no settings.cfg) mean the owner's default: visible.
	# Una instancia suelta del script no pasa por _ready(), asi que no lee el
	# settings.cfg de esta maquina: es el valor por defecto puro.
	var fresh: Node = load("res://scripts/services/GameConfig.gd").new()
	assert_bool(fresh.ui_grid_visible).is_true()
	fresh.free()

func test_visibility_follows_the_preference_and_the_toggle_signal() -> void:
	GameConfig.ui_grid_visible = false
	var overlay := _make_overlay()
	assert_bool(overlay.visible).is_false()
	EventBus.grid_overlay_toggled.emit(true)
	assert_bool(overlay.visible).is_true()
	EventBus.grid_overlay_toggled.emit(false)
	assert_bool(overlay.visible).is_false()

func test_the_scene_material_is_faint() -> void:
	# alpha ~0.08-0.10: se ve la celda, no una malla de neon encima del cesped.
	var scene: PackedScene = load("res://scenes/main/Main.tscn")
	var state := scene.get_state()
	var alpha := -1.0
	var size := Vector2.ZERO
	var origin := Vector2.ZERO
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "GridOverlay":
			continue
		for p in range(state.get_node_property_count(i)):
			var pname := state.get_node_property_name(i, p)
			var value = state.get_node_property_value(i, p)
			if pname == "surface_material_override/0" and value is ShaderMaterial:
				alpha = (value as ShaderMaterial).get_shader_parameter("grid_color").a
				origin = (value as ShaderMaterial).get_shader_parameter("grid_origin")
			elif pname == "mesh" and value is PlaneMesh:
				size = (value as PlaneMesh).size
	assert_float(alpha).is_between(0.07, 0.11)
	assert_vector(origin).is_equal(Vector2(-40, -40))
	assert_float(size.x).is_greater_equal(80.0)
	assert_float(size.y).is_greater_equal(80.0)
