extends GdUnitTestSuite
## El indicador de fase de la Tormenta, por encima.
##
## El HUD dibuja su icono a mano (`_draw`), y un `_draw` que revienta lo hace en
## silencio: el panel sale vacio y nadie se entera hasta que hay ceniza cayendo.
## Esta prueba recorre las cuatro fases visibles y comprueba que cada una se
## estila, se dibuja y trae texto traducido.
##
## Toca miembros privados del panel a proposito: es la unica forma de forzar una
## fase sin montar media partida, y lo que se quiere vigilar es justo el dibujo.

func _hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/StormHUD.tscn").instantiate())
	add_child(hud)
	return hud

func test_every_visible_phase_styles_and_draws() -> void:
	var hud := _hud()
	await await_idle_frame()
	for phase in [StormCycle.Phase.WARNING, StormCycle.Phase.ASH,
			StormCycle.Phase.STORM, StormCycle.Phase.TITHE]:
		hud._panel.visible = true
		hud._style_for(phase)
		hud._icon.queue_redraw()
		await await_idle_frame()
		assert_str(hud._label.text).is_not_empty()

func test_the_phase_name_comes_from_the_translations() -> void:
	# Nada de cadenas sueltas en la interfaz: si falta la clave, Tr devuelve la
	# clave misma y esto lo cantaria.
	var hud := _hud()
	await await_idle_frame()
	hud._panel.visible = true
	hud._style_for(StormCycle.Phase.ASH)
	assert_str(hud._label.text).is_equal(Tr.t("STORM_PHASE_ASH"))
	assert_str(hud._label.text).is_not_equal("STORM_PHASE_ASH")

func test_the_calm_shows_nothing_before_the_clock_is_armed() -> void:
	# Antes de la Fundicion la calma no ensena nada. Desde que el reloj esta
	# armado ensena el barometro (doc 21, D5 = A): test_regency_order lo cubre.
	var hud := _hud()
	await await_idle_frame()
	if StormManager.is_armed():
		return   # partida ya avanzada en este proceso; nada que comprobar
	assert_bool(hud._should_show(StormCycle.Phase.CALM)).is_false()

func test_the_barometer_shows_a_range_never_a_single_number() -> void:
	# "3–5 min" o "< 2 min": siempre un margen, nunca el minuto exacto.
	assert_str(load("res://scripts/ui/StormHUD.gd").barometer_text({"fill": 0.3, "low": 3, "high": 5})) 		.is_equal(Tr.t("STORM_BAROMETER") % [3, 5])
	assert_str(load("res://scripts/ui/StormHUD.gd").barometer_text({"fill": 0.9, "low": 0, "high": 2})) 		.is_equal(Tr.t("STORM_BAROMETER_SOON") % 2)
	assert_str(load("res://scripts/ui/StormHUD.gd").barometer_text({})).is_empty()

func test_nothing_shows_before_the_clock_is_armed() -> void:
	var hud := _hud()
	await await_idle_frame()
	if StormManager.is_armed():
		return   # partida ya avanzada en este proceso; nada que comprobar
	for phase in [StormCycle.Phase.WARNING, StormCycle.Phase.STORM]:
		assert_bool(hud._should_show(phase)).is_false()

func test_the_indicator_never_puts_a_number_on_screen() -> void:
	# La cuenta atras resolvia sola la unica pregunta que el juego quiere hacer.
	# Tampoco se enseña la severidad: eso se sabe cuando ya esta encima.
	var hud := _hud()
	await await_idle_frame()
	for phase in [StormCycle.Phase.WARNING, StormCycle.Phase.ASH,
			StormCycle.Phase.STORM, StormCycle.Phase.TITHE]:
		hud._panel.visible = true
		hud._style_for(phase)
		for character in hud._label.text:
			assert_bool(character.is_valid_int()).is_false()
