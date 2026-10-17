extends GdUnitTestSuite
## Deteccion de la calidad (docs/26 §7.2): una medida pegada a un tope de
## fotogramas o al refresco no mide la GPU y no decide nada; y la reparacion de
## las detecciones del 1.0.0, que median el tope de 30 fps de la pausa.
##
## Reglas puras de GraphicsQuality. Solo leen GameConfig (umbrales).

const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")

## n fotogramas alrededor de `ms`, con un vaiven de +-`jitter`.
func _frames(ms: float, n: int = 90, jitter: float = 0.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(ms + jitter * sin(float(i) * 1.7))
	return out

# ── Medidas que no valen ─────────────────────────────────────────────

func test_the_1_0_0_measure_at_33_3_ms_is_rejected() -> void:
	var frames := _frames(1000.0 / 30.0, 90, 2.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 60.0)).is_not_empty()
	assert_str(GraphicsQuality.measure_verdict(frames, "high", 60.0)).is_equal("")

func test_a_median_on_the_60_fps_cap_is_rejected() -> void:
	var frames := _frames(16.7, 90, 2.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 144.0)).is_not_empty()

func test_a_median_on_the_screen_refresh_is_rejected() -> void:
	# 144 Hz: 6,94 ms, ni 30 ni 60.
	var frames := _frames(1000.0 / 144.0, 300, 2.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 144.0)).is_not_empty()

func test_half_the_refresh_is_a_cap_too() -> void:
	# vsync a medio ritmo en 50 Hz: 40 ms.
	var frames := _frames(40.0, 60, 2.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 50.0)).is_not_empty()
	assert_str(GraphicsQuality.measure_verdict(frames, "high", 50.0)).is_equal("")

func test_frames_nailed_to_one_value_are_rejected() -> void:
	var frames := _frames(28.0, 90, 0.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 60.0)).is_not_empty()
	assert_str(GraphicsQuality.measure_verdict(frames, "high", 60.0)).is_equal("")

func test_too_few_frames_are_rejected() -> void:
	assert_str(GraphicsQuality.measure_rejection(_frames(50.0, 5, 3.0), 60.0)).is_not_empty()

# ── Medidas que si valen ─────────────────────────────────────────────

func test_a_really_slow_machine_still_goes_to_minimal() -> void:
	# 45 ms con vaiven: lejos de cualquier tope.
	var frames := _frames(45.0, 60, 4.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 60.0)).is_equal("")
	assert_str(GraphicsQuality.measure_verdict(frames, "high", 60.0)).is_equal("minimal")

func test_a_fast_machine_without_cap_keeps_auto() -> void:
	var frames := _frames(5.0, 600, 1.0)
	assert_str(GraphicsQuality.measure_rejection(frames, 60.0)).is_equal("")
	assert_str(GraphicsQuality.measure_verdict(frames, "high", 60.0)).is_equal("")

func test_the_stats_give_mean_fps_and_percentiles() -> void:
	var stats := GraphicsQuality.measure_stats(_frames(20.0, 100, 0.0))
	assert_int(int(stats["frames"])).is_equal(100)
	assert_float(float(stats["median"])).is_equal_approx(20.0, 0.001)
	assert_float(float(stats["mean_fps"])).is_equal_approx(50.0, 0.01)

# ── Reparar las detecciones del 1.0.0 ────────────────────────────────

const OLD_REASON := "medida high: mediana 33.3 ms, 90 fotogramas"

func test_the_reason_keeps_its_median() -> void:
	assert_float(GraphicsQuality.reason_median_ms(OLD_REASON)).is_equal_approx(33.3, 0.001)
	assert_float(GraphicsQuality.reason_median_ms("gpu=Intel(R) HD Graphics 520")).is_equal(-1.0)

func test_the_1_0_0_minimal_from_a_capped_measure_is_repaired() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", true, OLD_REASON, 0)).is_true()

func test_a_low_from_a_measure_at_16_7_ms_is_repaired() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("low", true,
		"medida high: mediana 16.7 ms, 180 fotogramas", 0)).is_true()

func test_any_old_minimal_from_the_measure_is_repaired() -> void:
	# El paso 1 no la pedia: la puso la medida vieja, que no era de fiar.
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", true,
		"medida high: mediana 41.0 ms, 70 fotogramas", 0)).is_true()

func test_a_minimal_from_step_1_is_left_alone() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", true,
		"ram_mb=4000", 0)).is_false()

func test_a_minimal_chosen_by_hand_is_left_alone() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", true,
		"manual: minimal", 0)).is_false()

func test_a_detection_of_the_current_rule_is_never_repaired() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", true, OLD_REASON,
		GameConfig.QUALITY_DETECT_VERSION)).is_false()

func test_without_a_detection_there_is_nothing_to_repair() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("minimal", false, OLD_REASON, 0)).is_false()

func test_an_old_auto_is_left_alone() -> void:
	assert_bool(GraphicsQuality.detection_needs_repair("auto", true, OLD_REASON, 0)).is_false()
