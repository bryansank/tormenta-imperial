extends GdUnitTestSuite
## El nivel de un edificio mejorado se ve (2026-10-17): en 3D el MISMO modelo
## crece (sobre todo en alto), se sube a un zocalo y gana chimeneas (farolas en
## las decoraciones) en una sola malla LevelTrim; sin la placa "II"/"III"
## flotante ni el aro de laton con banderin de antes. En 2D, el dibujo crece,
## lleva zocalo y galones sin caja.

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const Trim := preload("res://scripts/buildings/LevelTrim.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")

func _building(id: String) -> Node3D:
	var placer: Node3D = auto_free(Placer.new())
	var root: Node3D = placer._create_building_mesh(load("res://data/buildings/%s.tres" % id))
	add_child(root)
	return auto_free(root)

func _model(root: Node3D) -> Node3D:
	return root.get_node("LookVisual").get_model()

func _trim(root: Node3D) -> MeshInstance3D:
	return _model(root).get_node_or_null(Trim.NODE_NAME) as MeshInstance3D

func test_level_two_grows_lifts_and_adds_the_trim() -> void:
	var root := _building("sawmill")
	var model := _model(root)
	var scale0 := model.scale
	var pos0 := model.position
	ProductionManager.apply_level_visual(root, 2)
	assert_float(model.scale.y).is_greater(scale0.y * 1.1)
	assert_float(model.scale.x).is_greater(scale0.x)
	# Mas alto que ancho: crece sobre todo hacia arriba.
	assert_float(model.scale.y / scale0.y).is_greater(model.scale.x / scale0.x)
	assert_float(model.position.y).is_equal_approx(pos0.y + Trim.plinth_height(2), 0.001)
	var trim := _trim(root)
	assert_object(trim).is_not_null()
	assert_object(trim.mesh).is_not_null()
	assert_bool(trim.is_in_group("building_fx")).is_true()
	assert_int(trim.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# Sin placa flotante.
	assert_object(root.get_node_or_null("LevelPlate")).is_null()

func test_trim_is_measured_in_meters_whatever_the_model_scale() -> void:
	var root := _building("foundry")
	ProductionManager.apply_level_visual(root, 3)
	var model := _model(root)
	var trim := _trim(root)
	# La escala del remate deshace la del modelo.
	assert_vector(model.scale * trim.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)

func test_level_three_differs_from_two_and_one_removes_everything() -> void:
	var root := _building("house")
	var model := _model(root)
	var scale0 := model.scale
	var pos0 := model.position
	ProductionManager.apply_level_visual(root, 2)
	var mesh2: Mesh = _trim(root).mesh
	var top2 := model.scale.y
	ProductionManager.apply_level_visual(root, 3)
	assert_object(_trim(root).mesh).is_not_same(mesh2)
	assert_float(model.scale.y).is_greater(top2)
	assert_float(model.position.y).is_equal_approx(pos0.y + Trim.plinth_height(3), 0.001)
	ProductionManager.apply_level_visual(root, 1)
	assert_vector(model.scale).is_equal_approx(scale0, Vector3.ONE * 0.0001)
	assert_vector(model.position).is_equal_approx(pos0, Vector3.ONE * 0.0001)
	await get_tree().process_frame
	assert_object(_trim(root)).is_null()

func test_applying_twice_is_idempotent() -> void:
	var root := _building("gold_mine")
	ProductionManager.apply_level_visual(root, 3)
	var model := _model(root)
	var s := model.scale
	var p := model.position
	var mesh: Mesh = _trim(root).mesh
	ProductionManager.apply_level_visual(root, 3)
	assert_vector(model.scale).is_equal_approx(s, Vector3.ONE * 0.0001)
	assert_vector(model.position).is_equal_approx(p, Vector3.ONE * 0.0001)
	# La malla sale de la cache: la misma para la misma medida.
	assert_object(_trim(root).mesh).is_same(mesh)
	assert_int(model.get_children().filter(func(c: Node) -> bool: return c.name == Trim.NODE_NAME).size()).is_equal(1)

func test_trim_mesh_is_cached_per_level_and_size() -> void:
	var a := Trim.trim_mesh(2, Vector3(2.4, 1.8, 2.4))
	var b := Trim.trim_mesh(2, Vector3(2.4, 1.8, 2.4))
	var c := Trim.trim_mesh(3, Vector3(2.4, 1.8, 2.4))
	var d := Trim.trim_mesh(2, Vector3(2.4, 1.8, 2.4), true)
	assert_object(a).is_same(b)
	assert_object(a).is_not_same(c)
	assert_object(a).is_not_same(d)

func test_damaged_pose_keeps_the_new_level_on_repair() -> void:
	# Un edificio hundido o ladeado (dano, ruina) que sube de nivel: al reparar
	# vuelve a su sitio de ese nivel, encima del zocalo.
	var root := _building("warehouse")
	var model := _model(root)
	var pos0 := model.position
	ProductionManager.apply_level_visual(root, 1)
	model.set_meta("look_base_pos", model.position)
	model.set_meta("look_base_rot", model.rotation)
	model.position.y -= 0.5
	ProductionManager.apply_level_visual(root, 2)
	var target := Vector3(pos0.x * Trim.level_scale(2).x, pos0.y + Trim.plinth_height(2), pos0.z * Trim.level_scale(2).z)
	assert_vector(model.get_meta("look_base_pos")).is_equal_approx(target, Vector3.ONE * 0.001)
	assert_float(model.position.y).is_equal_approx(target.y - 0.5, 0.001)

# ── 2D ────────────────────────────────────────────────────────────────

func test_2d_plinth_grows_with_level() -> void:
	var r := Rect2(-20, -20, 40, 40)
	assert_that(Art.plinth_rect(r, 1)).is_equal(r)
	assert_float(Art.plinth_rect(r, 2).size.x).is_greater(r.size.x)
	assert_float(Art.plinth_rect(r, 3).size.x).is_greater(Art.plinth_rect(r, 2).size.x)
	assert_float(Art.level_scale(3)).is_greater(Art.level_scale(2))

# ── Todos los que se mejoran, los de la 1.1 incluidos (Muelle de pesca...) ──

func test_every_upgradable_building_shows_its_level() -> void:
	var Rules := preload("res://scripts/buildings/PlacementRules.gd")
	var checked := 0
	for data in BuildingData.load_all():
		var d: BuildingData = data
		if not Rules.upgrade_does_something(d):
			continue
		var root := _building(d.id)
		ProductionManager.apply_level_visual(root, 3)
		var trim := _trim(root)
		assert_object(trim).override_failure_message(d.id).is_not_null()
		if trim != null:
			assert_object(trim.mesh).override_failure_message(d.id).is_not_null()
		checked += 1
	assert_int(checked).is_greater(8)
