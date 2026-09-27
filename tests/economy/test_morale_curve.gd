extends GdUnitTestSuite
## La moral multiplica la produccion por la curva que promete el diseno:
## 0,5x a moral 0, 1,0x a 50 y 1,2x a 100, lineal a tramos entre esos puntos.

func test_the_three_design_points_hold() -> void:
	assert_float(PopulationManager.morale_to_multiplier(0)).is_equal_approx(0.5, 0.0001)
	assert_float(PopulationManager.morale_to_multiplier(50)).is_equal_approx(1.0, 0.0001)
	assert_float(PopulationManager.morale_to_multiplier(100)).is_equal_approx(1.2, 0.0001)

func test_each_half_is_linear() -> void:
	assert_float(PopulationManager.morale_to_multiplier(25)).is_equal_approx(0.75, 0.0001)
	assert_float(PopulationManager.morale_to_multiplier(75)).is_equal_approx(1.1, 0.0001)

func test_out_of_range_morale_is_clamped() -> void:
	assert_float(PopulationManager.morale_to_multiplier(-40)).is_equal_approx(0.5, 0.0001)
	assert_float(PopulationManager.morale_to_multiplier(180)).is_equal_approx(1.2, 0.0001)

func test_the_curve_never_goes_down_as_morale_rises() -> void:
	var previous := 0.0
	for m in range(0, 101):
		var value := PopulationManager.morale_to_multiplier(m)
		assert_float(value).is_greater_equal(previous)
		previous = value

func test_the_live_multiplier_reads_the_current_morale() -> void:
	var saved := PopulationManager.get_save_data()
	PopulationManager.load_save_data({"population": saved["population"], "morale": 50})
	assert_float(PopulationManager.get_morale_multiplier()).is_equal_approx(1.0, 0.0001)
	PopulationManager.load_save_data(saved)
