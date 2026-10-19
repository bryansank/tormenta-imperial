extends GdUnitTestSuite
## La noche y la Tormenta se notan en la vista 2D (feat/vista2d-y-prologo,
## ronda 1.0 mejora 11): suelos de tinte propios, vineta, luces de la colonia
## que el tinte no apaga y ceniza que cae despacio. Todo barato: nada repinta
## por fotograma.

const StormTint := preload("res://scripts/view2d/StormTint2D.gd")
const NightLights := preload("res://scripts/view2d/NightLights2D.gd")
const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

func test_the_2d_storm_darkens_more_than_the_3d_weights() -> void:
	for phase in [StormCycleScript.Phase.WARNING, StormCycleScript.Phase.ASH, StormCycleScript.Phase.STORM, StormCycleScript.Phase.TITHE]:
		var v: float = StormTint.view_target(phase, 1, false)
		assert_float(v).is_greater_equal(StormTint.target_weight(phase, 1, false))
		assert_float(v).is_greater_equal(0.3)
	# Cada fase apaga mas que la anterior, y la Tormenta ya pasa a la ceniza.
	assert_float(StormTint.view_target(StormCycleScript.Phase.ASH, 1, false)).is_greater(StormTint.view_target(StormCycleScript.Phase.WARNING, 1, false))
	assert_float(StormTint.view_target(StormCycleScript.Phase.STORM, 1, false)).is_greater(StormTint.view_target(StormCycleScript.Phase.ASH, 1, false))
	assert_float(StormTint.view_target(StormCycleScript.Phase.STORM, 1, false)).is_greater(StormTint.WARM_UNTIL)
	# Despejado y Auditoria ganada: nada.
	assert_float(StormTint.view_target(StormCycleScript.Phase.CALM, 3, false)).is_equal(0.0)
	assert_float(StormTint.view_target(StormCycleScript.Phase.STORM, 3, true)).is_equal(0.0)

func test_the_storm_tint_stays_readable() -> void:
	var c: Color = StormTint.tint_for(StormTint.view_target(StormCycleScript.Phase.STORM, 1, false))
	assert_float(c.get_luminance()).is_greater(0.5)
	assert_float(c.get_luminance()).is_less(0.9)

func test_ash_drifts_only_in_ash_and_storm() -> void:
	assert_bool(StormTint.drifting(StormCycleScript.Phase.CALM, false)).is_false()
	assert_bool(StormTint.drifting(StormCycleScript.Phase.WARNING, false)).is_false()
	assert_bool(StormTint.drifting(StormCycleScript.Phase.ASH, false)).is_true()
	assert_bool(StormTint.drifting(StormCycleScript.Phase.STORM, false)).is_true()
	assert_bool(StormTint.drifting(StormCycleScript.Phase.STORM, true)).is_false()

func test_lights_are_off_by_day_and_on_at_night_and_in_the_storm() -> void:
	assert_float(StormTint.lights_for(1.0, 0.0)).is_equal(0.0)
	assert_float(StormTint.lights_for(0.0, 0.0)).is_equal(1.0)
	assert_float(StormTint.lights_for(1.0, 0.9)).is_greater(0.5)
	# Con el tono de la Ceniza todavia no hacen falta.
	assert_float(StormTint.lights_for(1.0, 0.3)).is_equal(0.0)

func test_the_vignette_is_clear_by_day_blue_at_night_and_sepia_in_the_storm() -> void:
	assert_float(StormTint.vignette_for(1.0, 0.0).a).is_equal(0.0)
	var night: Color = StormTint.vignette_for(0.0, 0.0)
	assert_float(night.a).is_greater(0.3)
	assert_float(night.b).is_greater(night.r)
	var storm: Color = StormTint.vignette_for(1.0, 0.8)
	assert_float(storm.a).is_greater(0.3)
	assert_float(storm.r).is_greater(storm.b)
	assert_object(StormTint.vignette_texture()).is_not_null()

func test_road_lamps_are_one_in_a_few_and_always_the_same() -> void:
	var lit := 0
	for x in 20:
		var a: Array = NightLights.lights_for("road", [Vector2i(x, 3)], 32.0)
		var b: Array = NightLights.lights_for("road", [Vector2i(x, 3)], 32.0)
		assert_int(a.size()).is_equal(b.size())
		lit += a.size()
	assert_int(lit).is_between(2, 10)

func test_building_windows_sit_inside_the_footprint() -> void:
	var footprints: Array = [
		[Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)],
		[Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7)],
	]
	for cells in footprints:
		var pts: Array = NightLights.lights_for("house", cells, 32.0)
		assert_int(pts.size()).is_between(1, 3)
		var lo: Vector2i = cells[0]
		var hi: Vector2i = cells[cells.size() - 1]
		var rect := Rect2(View2D.cell_origin_px(lo), Vector2(hi - lo + Vector2i.ONE) * 32.0)
		for p in pts:
			var v: Vector3 = p
			assert_bool(rect.has_point(Vector2(v.x, v.y))).is_true()

func test_the_lights_hide_when_off_and_only_touch_modulate() -> void:
	var lights: Node2D = auto_free(NightLights.new())
	add_child(lights)
	lights.set_intensity(0.0)
	assert_bool(lights.visible).is_false()
	lights.set_intensity(0.8)
	assert_bool(lights.visible).is_true()
	assert_float(lights.modulate.a).is_equal_approx(0.8, 0.001)
	lights.set_intensity(0.0)
	assert_bool(lights.visible).is_false()
	assert_object(NightLights.glow_texture()).is_not_null()

func test_the_tint_builds_its_layers() -> void:
	var tint: CanvasModulate = auto_free(StormTint.new())
	add_child(tint)
	var lights_layer: CanvasLayer = tint.get_node("LightsLayer")
	assert_bool(lights_layer.follow_viewport_enabled).is_true()
	var ash_layer: CanvasLayer = tint.get_node("AshLayer")
	# Las luces por debajo de la vineta y la ceniza, y todo por debajo de la interfaz (10).
	assert_int(lights_layer.layer).is_less(ash_layer.layer)
	assert_int(ash_layer.layer).is_less(10)
	assert_object(ash_layer.get_node_or_null("Vignette")).is_not_null()
	assert_object(ash_layer.get_node_or_null("AshDrift")).is_not_null()
	assert_object(tint.lights()).is_not_null()
