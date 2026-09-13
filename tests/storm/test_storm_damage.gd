extends GdUnitTestSuite
## La aritmética del daño de la Tormenta y de las torres que lo frenan.
##
## Es la palanca de preparación principal del juego: si las torres dejan de
## mitigar, construirlas no tiene sentido; si mitigan demasiado, la Tormenta deja
## de ser una amenaza y el juego se queda otra vez sin reloj.

func test_the_storm_always_leaves_a_mark() -> void:
	# Ni con todas las torres del mundo un golpe cuesta cero: un daño que se
	# redondea a nada convierte la tormenta en decorado.
	assert_int(GameConfig.get_storm_damage(1, 10, 99)).is_greater(0)

func test_a_harsher_storm_bites_deeper() -> void:
	var mild: int = GameConfig.get_storm_damage(1, 200, 0)
	var harsh: int = GameConfig.get_storm_damage(GameConfig.storm_severity_max, 200, 0)
	assert_int(harsh).is_greater(mild)

func test_a_sturdier_building_loses_more_absolute_health() -> void:
	# El daño es proporcional: el Cuartel General encaja más puntos que una casa,
	# pero ambos aguantan el mismo número de tics.
	assert_int(GameConfig.get_storm_damage(2, 500, 0)).is_greater(GameConfig.get_storm_damage(2, 100, 0))

# ── Las torres ───────────────────────────────────────────────────────

func test_towers_reduce_the_damage() -> void:
	var unprotected: int = GameConfig.get_storm_damage(3, 300, 0)
	var protected: int = GameConfig.get_storm_damage(3, 300, 2)
	assert_int(protected).is_less(unprotected)

func test_more_towers_protect_more() -> void:
	assert_float(GameConfig.get_storm_mitigation(3)).is_greater(GameConfig.get_storm_mitigation(1))

func test_no_towers_means_no_shelter() -> void:
	assert_float(GameConfig.get_storm_mitigation(0)).is_equal(0.0)

func test_towers_can_never_make_the_base_immune() -> void:
	# Con techo a propósito: sin él, una fila de torres apagaría la mecánica
	# central del juego y volveríamos a no tener presión.
	assert_float(GameConfig.get_storm_mitigation(999)).is_equal(GameConfig.storm_tower_mitigation_max)
	assert_bool(GameConfig.storm_tower_mitigation_max < 1.0).is_true()

func test_a_protected_building_still_takes_damage() -> void:
	assert_int(GameConfig.get_storm_damage(5, 500, 999)).is_greater(0)

func test_mitigation_ignores_nonsense_counts() -> void:
	assert_float(GameConfig.get_storm_mitigation(-5)).is_equal(0.0)

# ── Cuánto aguanta una base ──────────────────────────────────────────

func test_a_building_survives_several_ticks_of_a_mild_storm() -> void:
	# Una tormenta suave no puede arruinar nada de un solo mordisco: el jugador
	# tiene que poder ver cómo se degrada y decidir.
	var max_health := 200
	var per_tick: int = GameConfig.get_storm_damage(1, max_health, 0)
	assert_int(int(max_health / maxi(1, per_tick))).is_greater(3)

func test_the_worst_storm_is_genuinely_dangerous() -> void:
	# Y la peor sí tiene que poder tumbar algo dentro de una misma tormenta.
	var max_health := 200
	var per_tick: int = GameConfig.get_storm_damage(GameConfig.storm_severity_max, max_health, 0)
	var ticks_to_ruin: int = int(max_health / maxi(1, per_tick))
	var ticks_in_a_storm: int = int(GameConfig.storm_duration / GameConfig.storm_tick_interval)
	assert_int(ticks_to_ruin).is_less_equal(ticks_in_a_storm)
