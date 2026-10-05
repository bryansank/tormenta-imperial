extends GdUnitTestSuite
## La parcela de cada edificio (docs/03, "Parcela y atrezo"; guia de estilo):
## LotPlan decide suelo, remate, atrezo y elemento exagerado; BuildingLot lo
## monta en 3D y BuildingArt2D lo dibuja en 2D. Y el Aserradero abierto.

const Plan := preload("res://scripts/buildings/LotPlan.gd")
const Lot := preload("res://scripts/buildings/BuildingLot.gd")
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

const CELL := 2.0

func _all_data() -> Array:
	return BuildingData.load_all()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func _lot_ids() -> Array:
	var ids: Array = []
	for d in _all_data():
		if Plan.has_lot((d as BuildingData).id):
			ids.append((d as BuildingData).id)
	return ids

## Un edificio del colocador con su parcela montada en `cell`.
func _building(id: String, cell := Vector2i(5, 5), sides := 0) -> Array:
	var placer: Node3D = auto_free(Placer.new())
	var root: Node3D = auto_free(placer._create_building_mesh(_data(id)))
	var lot = root.get_node_or_null("Lot")
	if lot != null:
		lot.build(cell, sides)
	return [root, lot]

# ── Las 16 ───────────────────────────────────────────────────────────

func test_every_building_but_the_road_has_a_lot() -> void:
	var all := _all_data()
	assert_int(all.size()).is_equal(16)
	for d in all:
		var id: String = (d as BuildingData).id
		var parts := _building(id)
		if id == "road":
			assert_object(parts[1]).is_null()
		else:
			assert_object(parts[1]).override_failure_message("%s sin parcela" % id).is_not_null()

func test_lot_ground_covers_the_whole_footprint() -> void:
	for id in _lot_ids():
		var d := _data(id)
		var parts := _building(id)
		var lot = parts[1]
		var plane := (lot.get_ground() as MeshInstance3D).mesh as PlaneMesh
		var want := Vector2(d.grid_size) * CELL
		# El suelo llega al borde (menos un filo de 2 cm por lado) y el plan dice lo mismo.
		assert_float(plane.size.x).is_greater_equal(want.x - 0.05)
		assert_float(plane.size.y).is_greater_equal(want.y - 0.05)
		assert_vector(lot.get_plan()["lot"] as Vector2).is_equal(Vector2(d.grid_size))
		assert_object(lot.get_props_node().mesh).is_not_null()

func test_lot_is_building_fx_so_soot_and_badge_skip_it() -> void:
	var parts := _building("foundry")
	assert_bool((parts[1] as Node).is_in_group("building_fx")).is_true()
	# El modelo sigue siendo el primer hijo.
	assert_bool((parts[0] as Node).get_child(0).is_in_group("building_fx")).is_false()

func test_lot_materials_are_shared() -> void:
	var a = _building("warehouse", Vector2i(2, 2))[1]
	var b = _building("warehouse", Vector2i(9, 4))[1]
	assert_object(a.get_ground().material_override).is_same(b.get_ground().material_override)
	assert_object(a.get_shadow().material_override).is_same(b.get_shadow().material_override)
	var ma: Material = (a.get_props_node().mesh as ArrayMesh).surface_get_material(0)
	var mb: Material = (b.get_props_node().mesh as ArrayMesh).surface_get_material(0)
	assert_object(ma).is_same(mb)

# ── Atrezo: determinista, distinto, dentro del patio ─────────────────

func test_props_are_deterministic_per_instance() -> void:
	for id in _lot_ids():
		var fp := _data(id).grid_size
		var s := Plan.seed_for(Vector2i(7, 3), id)
		assert_str(str(Plan.plan(id, fp, s))).is_equal(str(Plan.plan(id, fp, s)))

func test_two_instances_get_different_props() -> void:
	for id in _lot_ids():
		var fp := _data(id).grid_size
		var a := Plan.plan(id, fp, Plan.seed_for(Vector2i(3, 4), id))
		var b := Plan.plan(id, fp, Plan.seed_for(Vector2i(12, 9), id))
		assert_str(str(a["props"])).override_failure_message("%s: dos parcelas iguales" % id).is_not_equal(str(b["props"]))

func test_props_stay_in_the_yard() -> void:
	# Ni pisan el rectangulo del modelo ni se salen de la parcela (asi nunca
	# pisan una calzada vecina), con cualquier semilla y cualquier calzada.
	for id in _lot_ids():
		var fp := _data(id).grid_size
		var lot := Rect2(-Vector2(fp) * 0.5, Vector2(fp))
		var model := Plan.model_rect(id, fp)
		for k in 6:
			var plan := Plan.plan(id, fp, Plan.seed_for(Vector2i(k * 5, k * 3 + 1), id), k % 16)
			for p in plan["props"]:
				var c: Vector2 = p["pos"]
				var r := float(p["radius"])
				var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
				assert_bool(lot.encloses(box)).override_failure_message("%s: %s se sale" % [id, p["kind"]]).is_true()
				assert_bool(model.intersects(box)).override_failure_message("%s: %s pisa el modelo" % [id, p["kind"]]).is_false()

func test_road_sides_stay_clear() -> void:
	for id in _lot_ids():
		var fp := _data(id).grid_size
		var half := Vector2(fp) * 0.5
		var yard := Plan.yard_of(id)
		var sides := Plan.SIDE_S | Plan.SIDE_E
		var plan := Plan.plan(id, fp, Plan.seed_for(Vector2i(4, 4), id), sides)
		for p in plan["props"]:
			var c: Vector2 = p["pos"]
			assert_float(c.y).override_failure_message("%s: atrezo en la entrada S" % id).is_less(half.y - yard)
			assert_float(c.x).override_failure_message("%s: atrezo en la entrada E" % id).is_less(half.x - yard)
		for run in plan["trim_runs"]:
			assert_int(int(run["side"]) & sides).is_equal(0)

func test_local_and_world_sides_round_trip() -> void:
	for steps in 4:
		for side in [Plan.SIDE_N, Plan.SIDE_E, Plan.SIDE_S, Plan.SIDE_W]:
			for cw in [true, false]:
				var w := Plan.world_side(side, steps, cw)
				assert_int(Plan.local_sides(w, steps, cw)).is_equal(side)
	# 3D: un cuarto de vuelta lleva la cara de atras (N, -Z) al oeste.
	assert_int(Plan.world_side(Plan.SIDE_N, 1, false)).is_equal(Plan.SIDE_W)
	# 2D (y hacia abajo): la de arriba va al este.
	assert_int(Plan.world_side(Plan.SIDE_N, 1, true)).is_equal(Plan.SIDE_E)

func test_real_road_next_to_the_lot_is_seen() -> void:
	GridManager.clear_all()
	var road := _data("road")
	var origin := Vector2i(10, 10)
	var node := Node3D.new()
	GridManager.place_building(Vector2i(10, 12), road, node)
	var sides := Plan.road_sides_of(origin, Vector2i(2, 2))
	assert_int(sides).is_equal(Plan.SIDE_S)
	GridManager.clear_all()
	node.free()

# ── Obra y ruina ─────────────────────────────────────────────────────

func test_construction_half_prepares_the_lot() -> void:
	var parts := _building("foundry")
	var lot = parts[1]
	var idle_mesh: Mesh = lot.get_props_node().mesh
	lot.set_look(LookRule.Look.CONSTRUCTION, 1)
	var plan: Dictionary = lot.get_plan()
	assert_str(String(plan["state"])).is_equal("construction")
	assert_str(String(plan["ground"])).is_equal("dirt")
	assert_bool((plan["signature"] as Dictionary).is_empty()).is_true()
	for p in plan["props"]:
		assert_bool(String(p["kind"]) in ["stake", "pallet"]).is_true()
	# Fase 1: un lado del remate puesto, no los cuatro.
	assert_int((plan["trim_runs"] as Array).size()).is_equal(1)
	assert_bool(lot.get_shadow().visible).is_false()
	assert_object(lot.get_props_node().mesh).is_not_same(idle_mesh)
	lot.set_look(LookRule.Look.CONSTRUCTION, 2)
	assert_int((lot.get_plan()["trim_runs"] as Array).size()).is_equal(2)

func test_ruin_topples_and_burns_the_props() -> void:
	var parts := _building("warehouse")
	var lot = parts[1]
	var idle_props: Array = lot.get_plan()["props"]
	var idle_ground: Material = lot.get_ground().material_override
	lot.set_look(LookRule.Look.RUIN, 0)
	var plan: Dictionary = lot.get_plan()
	assert_str(String(plan["state"])).is_equal("ruin")
	assert_int((plan["props"] as Array).size()).is_less_equal(idle_props.size())
	var toppled := 0
	for p in plan["props"]:
		assert_bool(bool(p["burnt"])).is_true()
		if bool(p["toppled"]) or bool(p["snapped"]):
			toppled += 1
	assert_int(toppled).is_greater(0)
	assert_bool(bool((plan["signature"] as Dictionary).get("ruined", false))).is_true()
	# El suelo tambien se quema.
	assert_object(lot.get_ground().material_override).is_not_same(idle_ground)
	# Y vuelve a estar en pie al repararse.
	lot.set_look(LookRule.Look.IDLE, 0)
	assert_str(str(lot.get_plan()["props"])).is_equal(str(idle_props))

func test_look_visual_drives_the_lot() -> void:
	var parts := _building("gold_mine")
	var root: Node3D = parts[0]
	var look = root.get_node("LookVisual")
	look.apply({"look": LookRule.Look.CONSTRUCTION, "phase": 0})
	assert_str(parts[1].get_state()).is_equal("construction")
	look.apply({"look": LookRule.Look.RUIN, "phase": 0})
	assert_str(parts[1].get_state()).is_equal("ruin")
	look.apply({"look": LookRule.Look.ACTIVE, "phase": 0})
	assert_str(parts[1].get_state()).is_equal("idle")

# ── El modelo cabe en su rectangulo; lo exagerado no lo atraviesa ────

func test_models_fit_inside_their_rect() -> void:
	for id in _lot_ids():
		var d := _data(id)
		var parts := _building(id)
		var root: Node3D = parts[0]
		var a := Lot.model_aabb(root.get_child(0) as Node3D, root)
		var rect := Plan.model_rect(id, d.grid_size)
		var m := Rect2(rect.position * CELL, rect.size * CELL).grow(0.02)
		assert_bool(m.encloses(Rect2(Vector2(a.position.x, a.position.z), Vector2(a.size.x, a.size.z)))) \
			.override_failure_message("%s: el modelo se sale de su rectangulo" % id).is_true()

func test_each_productive_building_has_its_exaggerated_element() -> void:
	for id in ["gold_mine", "foundry", "refinery", "warehouse", "laboratory", "barracks", "tower", "headquarters"]:
		assert_str(String(Plan.signature_of(id).get("kind", ""))).override_failure_message(id).is_not_empty()
	# Y es distinto en cada uno: silueta propia.
	var kinds := {}
	for id in ["gold_mine", "foundry", "refinery", "warehouse", "laboratory", "barracks", "tower", "headquarters"]:
		kinds[String(Plan.signature_of(id)["kind"])] = true
	assert_int(kinds.size()).is_equal(8)

func test_signature_corner_keeps_no_props() -> void:
	for id in _lot_ids():
		var sig := Plan.signature_of(id)
		if (sig.get("corners", []) as Array).is_empty():
			continue
		var fp := _data(id).grid_size
		var yard := Plan.yard_of(id)
		for k in 5:
			var plan := Plan.plan(id, fp, Plan.seed_for(Vector2i(k, 2 * k), id))
			for sgn in sig["corners"]:
				var c := Plan.corner_center(fp, yard, sgn)
				for p in plan["props"]:
					assert_float((p["pos"] as Vector2).distance_to(c)).is_greater(yard * 1.1)

func test_tall_signatures_rise_above_the_model() -> void:
	# La chimenea, la grua, la antena y la bandera se ven por encima del edificio.
	for id in ["foundry", "warehouse", "laboratory", "barracks"]:
		var parts := _building(id)
		var lot = parts[1]
		var top: float = lot.get_model_top()
		var a: AABB = (lot.get_props_node().mesh as ArrayMesh).get_aabb()
		assert_float(a.end.y).override_failure_message(id).is_greater(top)

func test_roof_emblem_sits_on_the_roof() -> void:
	var parts := _building("headquarters")
	var lot = parts[1]
	var roof: float = lot.get_model_roof()
	assert_float(roof).is_greater(1.0)
	assert_float(roof).is_less_equal(lot.get_model_top() + 0.01)
	var a: AABB = (lot.get_props_node().mesh as ArrayMesh).get_aabb()
	assert_float(a.end.y).is_greater(roof + 1.0)

# ── El Aserradero abierto ────────────────────────────────────────────

func test_sawmill_is_procedural_and_open() -> void:
	var d := _data("sawmill")
	assert_object(d.model_scene).is_null()
	var saw: Node3D = auto_free(DieselpunkBuildingFactory.create("sawmill", CELL, d.grid_size))
	for path in ["Shed/Roof", "Shed/Rafters", "Shed/BackWall", "Saw/SawBlade", "Saw/SawTable", "Saw/Log", "PlankStack", "LogPile", "FxAnchor"]:
		assert_object(saw.get_node_or_null(path)).override_failure_message("falta " + path).is_not_null()
	assert_object(saw.find_child("FrontWall", true, false)).is_null()
	# Sin pared en el frente: ninguna pieza de la mitad de delante cierra mas
	# de la mitad del ancho entre el suelo y el tejado.
	var width := Lot.model_aabb(saw).size.x
	var shed := saw.get_node("Shed")
	for mi in shed.find_children("*", "MeshInstance3D", true, false):
		var a := Lot.model_aabb(mi as Node3D, saw)
		if a.get_center().z > 0.3 and a.size.y > 0.6:
			assert_float(a.size.x).is_less(width * 0.5)
	# La cubierta solo tapa la mitad de atras: la sierra queda a la vista.
	var roof := Lot.model_aabb(saw.get_node("Shed/Roof") as Node3D, saw)
	var blade := Lot.model_aabb(saw.get_node("Saw/SawBlade") as Node3D, saw)
	assert_float(roof.end.z).is_less(blade.position.z)

func test_sawmill_blade_is_the_exaggerated_element() -> void:
	var saw: Node3D = auto_free(DieselpunkBuildingFactory.create("sawmill", CELL, Vector2i(2, 2)))
	var blade := Lot.model_aabb(saw.get_node("Saw/SawBlade") as Node3D, saw)
	var table := Lot.model_aabb(saw.get_node("Saw/SawTable") as Node3D, saw)
	# Casi tan alta como el cobertizo hasta las cerchas y mas que la mesa de ancha.
	assert_float(blade.size.y).is_greater(1.6)
	assert_float(blade.size.x).is_greater(table.size.z * 2.0)

func test_sawmill_dust_comes_out_of_the_saw() -> void:
	var parts := _building("sawmill")
	var root: Node3D = parts[0]
	var look = root.get_node("LookVisual")
	look.apply({"look": LookRule.Look.ACTIVE, "phase": 0})
	var fx: Node3D = look.get_active().get_child(0)
	var blade := Lot.model_aabb(root.get_child(0).get_node("Saw/SawBlade") as Node3D, root)
	# A la altura de la hoja (no flotando sobre el tejado) y sobre ella en planta.
	assert_float(fx.position.y).is_less(Badge.measure_top(root))
	assert_float(absf(fx.position.x - blade.get_center().x)).is_less(0.5)
	assert_float(absf(fx.position.z - blade.get_center().z)).is_less(0.5)

func test_nucleo_flag_corner_and_seed_are_shared() -> void:
	# La bandera de la colonia (ColonyFlag3D/2D) va en la esquina NE del Nucleo:
	# ahi no hay atrezo.
	var fp := _data("nucleo").grid_size
	var c := Plan.corner_center(fp, Plan.yard_of("nucleo"), Vector2(1, -1))
	for k in 6:
		for p in Plan.plan("nucleo", fp, Plan.seed_for(Vector2i(k, k + 2), "nucleo"))["props"]:
			assert_float((p["pos"] as Vector2).distance_to(c)).is_greater(Plan.yard_of("nucleo") * 1.1)
	# La parcela usa la misma semilla que la obra.
	assert_int(Plan.seed_for(Vector2i(4, 9), "foundry")).is_equal(LookRule.site_seed("foundry", Vector2i(4, 9)))
