extends GdUnitTestSuite
## Los yacimientos 3D en maqueta (scripts/map/DepositMesh.gd, docs/02
## "Yacimientos en el mapa"): una malla con color por vertice y los materiales
## comunes de la paleta, a la medida de su huella (sin estirar), determinista
## por semilla, con etapas de agotamiento que quitan piezas, y una cache que
## comparte mallas entre yacimientos iguales. MapGenerator la monta una vez y
## la cambia solo cuando cambia la etapa.

const DepositMesh := preload("res://scripts/map/DepositMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const CELL := 2.0

func before_test() -> void:
	DepositMesh.clear_cache()

func after_test() -> void:
	DepositMesh.clear_cache()

static func _tris(mesh: Mesh) -> int:
	var t := 0
	for s in mesh.get_surface_count():
		t += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

# ── La malla ──────────────────────────────────────────────────────────

func test_every_type_builds_one_mesh_with_the_shared_materials() -> void:
	for id in MapGen.DEPOSIT_IDS:
		var mesh := DepositMesh.build(id, Vector2i(3, 3), 7)
		assert_object(mesh).override_failure_message(id).is_not_null()
		# Una superficie solida (y la de brillo solo en el oro): 1-2 llamadas.
		assert_int(mesh.get_surface_count()).override_failure_message(id).is_between(1, 2)
		assert_object(mesh.surface_get_material(0)).is_same(Palette.solid_material())
		if mesh.get_surface_count() > 1:
			assert_object(mesh.surface_get_material(1)).is_same(Palette.glow_material())

func test_only_gold_glows() -> void:
	assert_int(DepositMesh.build("gold_vein", Vector2i(2, 2), 3).get_surface_count()).is_equal(2)
	for id in ["forest", "iron_deposit", "oil_well"]:
		assert_int(DepositMesh.build(id, Vector2i(2, 2), 3).get_surface_count()).override_failure_message(id).is_equal(1)

func test_mesh_fits_its_footprint_without_stretching() -> void:
	for id in MapGen.DEPOSIT_IDS:
		for size in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(4, 4)]:
			var a := DepositMesh.build(id, size, 11).get_aabb()
			var w := float(size.x) * CELL
			var d := float(size.y) * CELL
			var msg := "%s %s: %s" % [id, size, a]
			# Dentro de su huella (holgura por las crestas inclinadas del borde).
			assert_float(a.position.x).override_failure_message(msg).is_greater_equal(-w * 0.5 - 0.25)
			assert_float(a.end.x).override_failure_message(msg).is_less_equal(w * 0.5 + 0.25)
			assert_float(a.position.z).override_failure_message(msg).is_greater_equal(-d * 0.5 - 0.25)
			assert_float(a.end.z).override_failure_message(msg).is_less_equal(d * 0.5 + 0.25)
			# Y la llena: no es una pieza de 2x2 encogida en un 4x4.
			assert_float(a.size.x).override_failure_message(msg).is_greater(w * 0.75)
			assert_float(a.size.z).override_failure_message(msg).is_greater(d * 0.75)
			# Altura de miniatura: ni plano ni mas alto que un edificio con todo.
			assert_float(a.end.y).override_failure_message(msg).is_between(0.6, 3.4)

func test_same_seed_same_mesh_and_seeds_vary() -> void:
	var a := DepositMesh.build("forest", Vector2i(3, 3), 42)
	var b := DepositMesh.build("forest", Vector2i(3, 3), 42)
	var c := DepositMesh.build("forest", Vector2i(3, 3), 43)
	assert_array(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]).is_equal(b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	assert_bool(a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == c.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]).is_false()

func test_unknown_type_or_depleted_gives_no_mesh() -> void:
	assert_object(DepositMesh.build("salt_flat", Vector2i(2, 2), 1)).is_null()
	assert_object(DepositMesh.build("forest", Vector2i(2, 2), 1, 0)).is_null()
	assert_object(DepositMesh.mesh_for("forest", Vector2i(2, 2), 1, 0)).is_null()

func test_cost_stays_small() -> void:
	# El presupuesto de "va en una papa": el mayor bosque (4x4) por debajo de
	# 4000 triangulos, el resto por debajo de 2500.
	assert_int(_tris(DepositMesh.build("forest", Vector2i(4, 4), 5))).is_less(4000)
	for id in ["gold_vein", "iron_deposit", "oil_well"]:
		assert_int(_tris(DepositMesh.build(id, Vector2i(3, 3), 5))).override_failure_message(id).is_less(2500)

# ── Agotamiento ───────────────────────────────────────────────────────

func test_stage_of_uses() -> void:
	assert_int(DepositMesh.stage_of(8, 8)).is_equal(4)
	assert_int(DepositMesh.stage_of(7, 8)).is_equal(4)
	assert_int(DepositMesh.stage_of(6, 8)).is_equal(3)
	assert_int(DepositMesh.stage_of(4, 8)).is_equal(2)
	assert_int(DepositMesh.stage_of(1, 8)).is_equal(1)
	assert_int(DepositMesh.stage_of(0, 8)).is_equal(0)
	assert_int(DepositMesh.stage_of(1, 10)).is_equal(1)
	assert_int(DepositMesh.stage_of(10, 10)).is_equal(4)

func test_a_mined_forest_has_fewer_trees() -> void:
	# Menos arboles en pie = menos triangulos (un tocon cuesta menos que un pino).
	var full := _tris(DepositMesh.build("forest", Vector2i(3, 3), 9, 4))
	var half := _tris(DepositMesh.build("forest", Vector2i(3, 3), 9, 2))
	var last := _tris(DepositMesh.build("forest", Vector2i(3, 3), 9, 1))
	assert_int(half).is_less(full)
	assert_int(last).is_less(half)

func test_mining_keeps_the_ground_in_place() -> void:
	# El suelo se monta antes que nada y con el mismo azar: igual en cada etapa.
	for id in MapGen.DEPOSIT_IDS:
		var a: PackedVector3Array = DepositMesh.build(id, Vector2i(3, 3), 21, 4).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = DepositMesh.build(id, Vector2i(3, 3), 21, 1).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in 60:
			assert_vector(b[i]).override_failure_message(id).is_equal(a[i])

# ── Cache ─────────────────────────────────────────────────────────────

func test_cache_shares_meshes_by_variant() -> void:
	var a := DepositMesh.mesh_for("iron_deposit", Vector2i(2, 3), 5, 4)
	var b := DepositMesh.mesh_for("iron_deposit", Vector2i(2, 3), 5 + DepositMesh.VARIANTS, 4)
	var c := DepositMesh.mesh_for("iron_deposit", Vector2i(2, 3), 5, 3)
	var e := DepositMesh.mesh_for("iron_deposit", Vector2i(3, 2), 5, 4)
	assert_object(a).is_same(b)
	assert_object(a).is_not_same(c)
	assert_object(a).is_not_same(e)

func test_variant_of_negative_seeds() -> void:
	for s in [-7, -1, 0, 3, 123456789]:
		assert_int(DepositMesh.variant_of(s)).is_between(0, DepositMesh.VARIANTS - 1)

# ── En el mapa (MapGenerator) ─────────────────────────────────────────

func test_map_deposit_carries_one_look_mesh_and_updates_when_mined() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	var map: Node = auto_free(MapGen.new())
	add_child(map)
	var node: Node3D = map.spawn_deposit("forest", Vector2i(6, 6), -1, Vector2i(3, 3))
	var look := node.get_node("Look") as MeshInstance3D
	assert_object(look.mesh).is_not_null()
	# Una sola malla visible (el Label3D del nombre va oculto).
	var meshes := 0
	for c in node.get_children():
		if c is MeshInstance3D:
			meshes += 1
	assert_int(meshes).is_equal(1)
	var full: Mesh = look.mesh
	# Un uso de 8 no cruza la etapa: la misma malla.
	map._on_mining_completed(node, "forest")
	assert_object(look.mesh).is_same(full)
	# Cuatro mas, si: otra malla.
	for i in 4:
		map._on_mining_completed(node, "forest")
	assert_object(look.mesh).is_not_same(full)
	assert_int(int(node.get_meta("look_stage"))).is_equal(DepositMesh.stage_of(int(node.get_meta("uses_remaining")), int(node.get_meta("max_uses"))))
	map.clear_all_deposits()
	GridManager.clear_all()

func test_loaded_half_used_deposit_starts_at_its_stage() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	var map: Node = auto_free(MapGen.new())
	add_child(map)
	var node: Node3D = map.spawn_deposit("oil_well", Vector2i(8, 8), 2, Vector2i(2, 2))
	assert_int(int(node.get_meta("look_stage"))).is_equal(DepositMesh.stage_of(2, GameConfig.get_deposit_max_uses("oil_well")))
	map.clear_all_deposits()
	GridManager.clear_all()
