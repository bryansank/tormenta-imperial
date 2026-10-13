extends GdUnitTestSuite
## El reloj del dia (scripts/storm/DayCycle.gd) es puro: se recorre un dia
## entero sin escena, con duraciones de prueba (10 + 60 + 10 + 20 = 100 s).

const DayCycleScript := preload("res://scripts/storm/DayCycle.gd")
const StormSkyScript := preload("res://scripts/map/StormSky.gd")
const StormTint := preload("res://scripts/view2d/StormTint2D.gd")

func _cycle() -> DayCycle:
	return DayCycleScript.create(10.0, 60.0, 10.0, 20.0)

func _phases(events: Array) -> Array:
	var out: Array = []
	for e in events:
		assert_str(String(e["e"])).is_equal("day_phase_changed")
		out.append(int(e["phase"]))
	return out

func test_a_new_day_starts_in_full_daylight() -> void:
	var c := _cycle()
	assert_int(c.phase).is_equal(DayCycle.Phase.DAY)
	assert_float(c.hour).is_equal_approx(0.1, 0.0001)
	assert_float(c.light_weight()).is_equal(1.0)
	assert_float(c.warm_weight()).is_equal(0.0)
	assert_bool(c.is_night()).is_false()
	assert_float(c.length()).is_equal(100.0)

func test_one_full_turn_goes_through_every_phase_in_order() -> void:
	var c := _cycle()
	var seen: Array = []
	for i in 1001:
		seen.append_array(_phases(c.tick(0.1)))
	assert_array(seen).is_equal([DayCycle.Phase.DUSK, DayCycle.Phase.NIGHT, DayCycle.Phase.DAWN, DayCycle.Phase.DAY])
	assert_float(c.hour).is_equal_approx(0.101, 0.001)

func test_events_carry_the_hour_of_the_edge() -> void:
	var c := _cycle()
	var events := c.tick(60.0)
	assert_int(events.size()).is_equal(1)
	assert_int(int(events[0]["phase"])).is_equal(DayCycle.Phase.DUSK)
	assert_float(float(events[0]["hour"])).is_equal_approx(0.7, 0.0001)

func test_a_huge_jump_never_loops_more_than_once() -> void:
	var c := _cycle()
	var events := c.tick(100000.0 + 65.0)
	# Mil vueltas enteras se saltan; quedan 65 s: del dia al atardecer.
	assert_int(events.size()).is_equal(1)
	assert_int(c.phase).is_equal(DayCycle.Phase.DUSK)
	assert_float(c.hour).is_equal_approx(0.75, 0.0001)

func test_nothing_moves_with_no_time() -> void:
	var c := _cycle()
	assert_array(c.tick(0.0)).is_empty()
	assert_array(c.tick(-5.0)).is_empty()
	assert_float(c.hour).is_equal_approx(0.1, 0.0001)

func test_night_is_dark_and_dawn_climbs_smoothly() -> void:
	var c := _cycle()
	c.set_hour(0.9)
	assert_bool(c.is_night()).is_true()
	assert_float(c.light_weight()).is_equal(0.0)
	c.set_hour(0.0)
	assert_int(c.phase).is_equal(DayCycle.Phase.DAWN)
	assert_float(c.light_weight()).is_equal_approx(0.0, 0.0001)
	c.set_hour(0.05)
	assert_float(c.light_weight()).is_equal_approx(0.5, 0.0001)
	assert_float(c.warm_weight()).is_equal_approx(1.0, 0.0001)
	c.set_hour(0.75)
	assert_int(c.phase).is_equal(DayCycle.Phase.DUSK)
	assert_float(c.light_weight()).is_equal_approx(0.5, 0.0001)

func test_the_light_never_jumps_across_a_whole_day() -> void:
	# Ni la luz ni el arco del sol saltan en ningun borde de fase.
	var c := _cycle()
	var last_light := c.light_weight()
	var last_arc := c.sun_arc()
	for i in 2000:
		c.tick(0.05)
		assert_float(absf(c.light_weight() - last_light)).is_less(0.02)
		assert_float(absf(c.sun_arc() - last_arc)).is_less(0.02)
		last_light = c.light_weight()
		last_arc = c.sun_arc()

func test_the_sun_crosses_from_east_to_west_and_the_moon_comes_back() -> void:
	var c := _cycle()
	c.set_hour(0.0)
	assert_float(c.sun_arc()).is_equal_approx(-1.0, 0.0001)
	c.set_hour(0.4)
	assert_float(c.sun_arc()).is_equal_approx(0.0, 0.0001)
	c.set_hour(0.8)
	assert_float(c.sun_arc()).is_equal_approx(1.0, 0.0001)
	c.set_hour(0.9)
	assert_float(c.sun_arc()).is_equal_approx(0.0, 0.0001)

func test_the_hour_survives_a_save_and_wraps() -> void:
	var c := _cycle()
	c.set_hour(0.83)
	var data: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var back := _cycle()
	back.load_dict(data)
	back.load_dict(data)
	assert_float(back.hour).is_equal_approx(0.83, 0.0001)
	assert_int(back.phase).is_equal(DayCycle.Phase.NIGHT)
	back.set_hour(1.25)
	assert_float(back.hour).is_equal_approx(0.25, 0.0001)

func test_an_old_save_without_hour_starts_in_daylight() -> void:
	var c := _cycle()
	c.set_hour(0.9)
	c.load_dict({})
	assert_int(c.phase).is_equal(DayCycle.Phase.DAY)

func test_noon_keeps_the_scene_sun_and_dusk_lowers_it() -> void:
	var base := Vector3(-0.9, 0.6, 0.0)
	assert_that(StormSkyScript.sun_rotation_for(base, 0.0)).is_equal(base)
	var low: Vector3 = StormSkyScript.sun_rotation_for(base, 1.0)
	assert_float(-low.x).is_less(0.9)
	assert_float(-low.x).is_greater_equal(StormSkyScript.MIN_ELEVATION - 0.0001)

func test_the_2d_tint_is_white_by_day_and_blue_but_readable_at_night() -> void:
	assert_that(StormTint.day_tint(1.0, 0.0)).is_equal(Color.WHITE)
	var night: Color = StormTint.day_tint(0.0, 0.0)
	assert_float(night.b).is_greater(night.r)
	assert_float(night.get_luminance()).is_greater(0.6)
