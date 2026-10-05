extends GdUnitTestSuite
## El aspecto de los edificios en 3D: las fases de obra por huella que genera
## DieselpunkBuildingFactory, el andamio de mejora, los escombros de la ruina,
## la hoja de humo de BuildingFx y BuildingLookVisual aplicandolos sobre un
## edificio (modelo oculto en obra, hundido en ruina, humo al trabajar).

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const LookVisual := preload("res://scripts/buildings/BuildingLookVisual.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")
const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")
const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")

const CELL := 2.0

func _mesh_count(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for c in node.get_children():
		n += _mesh_count(c)
	return n

func _top(node: Node3D) -> float:
	return Badge.measure_top(node)

# ── Fabrica: una malla por huella y fase ─────────────────────────────

func test_factory_builds_every_phase_for_every_footprint() -> void:
	for fp in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]:
		for phase in 3:
			var site: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(fp, phase, CELL))
			assert_object(site).is_not_null()
			assert_str(String(site.name)).is_equal("ConstructionPhase%d" % phase)
			assert_int(_mesh_count(site)).is_greater(3)

func test_phases_rise_one_after_another() -> void:
	# Valla baja, cimientos bajos, estructura alta: la fase 2 es la que se ve de lejos.
	var fp := Vector2i(2, 2)
	var fence: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(fp, 0, CELL))
	var frame: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(fp, 2, CELL))
	assert_float(_top(frame)).is_greater(_top(fence) + 1.0)

func test_bigger_footprints_carry_more_pieces() -> void:
	var small: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(Vector2i(1, 1), 2, CELL))
	var big: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(Vector2i(3, 3), 2, CELL))
	assert_int(_mesh_count(big)).is_greater(_mesh_count(small))
	# La grua solo sale en las parcelas de 2x2 o mas.
	assert_object(small.find_child("CraneJib", true, false)).is_null()
	assert_object(big.find_child("CraneJib", true, false)).is_not_null()

func test_unknown_phase_is_null() -> void:
	assert_object(DieselpunkBuildingFactory.create_construction_phase(Vector2i(2, 2), 3, CELL)).is_null()
	assert_object(DieselpunkBuildingFactory.create_construction_phase(Vector2i(2, 2), -1, CELL)).is_null()

func test_site_materials_are_shared() -> void:
	var a: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(Vector2i(2, 2), 1, CELL))
	var b: Node3D = auto_free(DieselpunkBuildingFactory.create_construction_phase(Vector2i(3, 3), 1, CELL))
	var ma: Material = (a.get_child(0) as MeshInstance3D).get_surface_override_material(0)
	var mb: Material = (b.get_child(0) as MeshInstance3D).get_surface_override_material(0)
	assert_object(ma).is_same(mb)

func test_scaffold_and_ruin_overlay() -> void:
	var scaffold: Node3D = auto_free(DieselpunkBuildingFactory.create_scaffold(Vector2i(2, 2), CELL, 3.0))
	assert_str(String(scaffold.name)).is_equal("UpgradeScaffold")
	assert_float(_top(scaffold)).is_greater(2.5)
	var ruin: Node3D = auto_free(DieselpunkBuildingFactory.create_ruin_overlay(Vector2i(2, 2), CELL, 7))
	assert_str(String(ruin.name)).is_equal("RuinOverlay")
	assert_int(_mesh_count(ruin)).is_greater(8)

func test_ruin_overlay_is_deterministic() -> void:
	var a: Node3D = auto_free(DieselpunkBuildingFactory.create_ruin_overlay(Vector2i(2, 2), CELL, 42))
	var b: Node3D = auto_free(DieselpunkBuildingFactory.create_ruin_overlay(Vector2i(2, 2), CELL, 42))
	assert_int(a.get_child_count()).is_equal(b.get_child_count())
	for i in a.get_child_count():
		assert_vector((a.get_child(i) as Node3D).position).is_equal((b.get_child(i) as Node3D).position)

# ── Hoja de sprites ──────────────────────────────────────────────────

func test_fx_sheet_is_a_grid_of_frames() -> void:
	for kind in ["smoke", "dust", "glow"]:
		var img: Image = Fx.sheet_image(kind)
		assert_int(img.get_width()).is_equal(Fx.FRAME_PX * Fx.columns())
		assert_int(img.get_height()).is_equal(Fx.FRAME_PX * Fx.rows())
		# Cada fotograma tiene algo pintado.
		for i in Fx.frames():
			var rect := Rect2i((i % Fx.columns()) * Fx.FRAME_PX, (i / Fx.columns()) * Fx.FRAME_PX, Fx.FRAME_PX, Fx.FRAME_PX)
			assert_bool(img.get_region(rect).is_invisible()).is_false()

func test_fx_frames_and_fps_follow_the_brief() -> void:
	assert_int(Fx.frames()).is_between(4, 8)
	assert_float(GameConfig.building_fx_fps).is_between(10.0, 15.0)

func test_fx_materials_are_shared_per_kind() -> void:
	assert_object(Fx.material_3d("smoke")).is_same(Fx.material_3d("smoke"))
	assert_object(Fx.material_3d("smoke", "ruin")).is_not_same(Fx.material_3d("smoke"))
	assert_object(Fx.material_2d("glow")).is_same(Fx.material_2d("glow"))

# ── BuildingLookVisual sobre un edificio ─────────────────────────────

func _building(id: String) -> Array:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	var root: Node3D = auto_free(Node3D.new())
	root.name = id
	var model := Node3D.new()
	model.name = "Model"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 3, 3)
	mi.mesh = box
	mi.position.y = 1.5
	model.add_child(mi)
	root.add_child(model)
	var look: Node3D = LookVisual.new()
	root.add_child(look)
	look.setup(root, data, 3.0, CELL)
	return [root, model, look]

func test_construction_hides_the_model_and_shows_the_phase() -> void:
	var parts := _building("foundry")
	var model: Node3D = parts[1]
	var look = parts[2]
	look.apply({"look": LookRule.Look.CONSTRUCTION, "phase": 0})
	assert_bool(model.visible).is_false()
	assert_str(String(look.get_site().name)).is_equal("ConstructionPhase0")
	look.apply({"look": LookRule.Look.CONSTRUCTION, "phase": 2})
	assert_str(String(look.get_site().name)).is_equal("ConstructionPhase2")
	# Terminada: el modelo vuelve y la obra se va.
	look.apply({"look": LookRule.Look.IDLE, "phase": 0})
	assert_bool(model.visible).is_true()
	assert_object(look.get_site()).is_null()

func test_upgrade_keeps_the_model_with_scaffold() -> void:
	var parts := _building("foundry")
	var look = parts[2]
	look.apply({"look": LookRule.Look.UPGRADE, "phase": 2})
	assert_bool((parts[1] as Node3D).visible).is_true()
	assert_str(String(look.get_site().name)).is_equal("UpgradeScaffold")

func test_ruin_sinks_the_model_and_repair_restores_it() -> void:
	var parts := _building("barracks")
	var model: Node3D = parts[1]
	var look = parts[2]
	look.apply({"look": LookRule.Look.RUIN, "phase": 0})
	assert_float(model.position.y).is_less(-0.5)
	assert_float(absf(model.rotation.z)).is_greater(0.01)
	assert_object(look.get_ruin()).is_not_null()
	look.apply({"look": LookRule.Look.IDLE, "phase": 0})
	assert_vector(model.position).is_equal(Vector3.ZERO)
	assert_vector(model.rotation).is_equal(Vector3.ZERO)
	assert_object(look.get_ruin()).is_null()

func test_working_shows_the_effect_and_stopping_hides_it() -> void:
	var parts := _building("foundry")
	var look = parts[2]
	look.apply({"look": LookRule.Look.ACTIVE, "phase": 0})
	assert_object(look.get_active()).is_not_null()
	assert_bool(look.get_active().visible).is_true()
	look.apply({"look": LookRule.Look.IDLE, "phase": 0})
	assert_bool(look.get_active().visible).is_false()

func test_the_look_does_not_count_for_the_top_nor_takes_soot() -> void:
	var parts := _building("foundry")
	var root: Node3D = parts[0]
	var look = parts[2]
	var before := _top(root)
	look.apply({"look": LookRule.Look.ACTIVE, "phase": 0})
	assert_float(_top(root)).is_equal_approx(before, 0.001)
	# Hollin de BuildingHealth: el modelo lo lleva, el humo no.
	root.set_meta("health", 0)
	BuildingHealth.refresh_visual(root)
	var model_mesh: MeshInstance3D = (parts[1] as Node3D).get_child(0)
	assert_object(model_mesh.material_overlay).is_not_null()
	var smoke: MeshInstance3D = look.get_active().get_child(0)
	assert_object(smoke.material_overlay).is_null()

func test_sync_reads_the_real_metas() -> void:
	var parts := _building("foundry")
	var root: Node3D = parts[0]
	var look = parts[2]
	root.set_meta("health", 0)
	look.sync()
	assert_int(look.get_look()).is_equal(LookRule.Look.RUIN)
	root.remove_meta("health")
	look.sync()
	assert_int(look.get_look()).is_equal(LookRule.Look.IDLE)

# ── El colocador 3D lo cuelga de cada edificio ───────────────────────

func test_placer_gives_every_building_but_roads_a_look() -> void:
	var placer: Node3D = auto_free(Placer.new())
	var foundry: Node3D = auto_free(placer._create_building_mesh(load("res://data/buildings/foundry.tres")))
	var road: Node3D = auto_free(placer._create_building_mesh(load("res://data/buildings/road.tres")))
	assert_object(foundry.get_node_or_null("LookVisual")).is_not_null()
	assert_object(road.get_node_or_null("LookVisual")).is_null()
	# El modelo sigue siendo el primer hijo: la placa de nivel lo encuentra.
	assert_bool(foundry.get_child(0).is_in_group("building_fx")).is_false()
