extends GdUnitTestSuite
## La guia rapida (2026-09-28): una pantalla con cuatro bloques (recursos,
## extraer, edificios y carreteras, progreso). Desde el 14-10 ya no sale sola tras el prologo;
## pausa mientras se lee y queda en AYUDA con los mismos textos.

const QuickGuide := preload("res://scripts/ui/QuickGuide.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

## No pausa: tapa la pantalla, y al cerrarla avisa una vez.
func test_it_opens_without_pausing_and_tells_when_closed() -> void:
	get_tree().paused = false
	var g: CanvasLayer = auto_free(QuickGuide.new())
	add_child(g)
	var closed := [0]
	g.closed.connect(func(): closed[0] += 1)
	g.open()
	var shown: bool = g.is_open() and g.visible
	var paused_open: bool = get_tree().paused
	g.close()
	assert_bool(shown).is_true()
	assert_bool(paused_open).is_false()
	assert_int(closed[0]).is_equal(1)

func test_every_block_is_written_in_both_languages() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["QG_TITLE", "QG_OK"]:
			assert_str(Tr.t(key)).is_not_equal(key)
		for sec in QuickGuide.SECTIONS:
			for key in sec:
				assert_str(Tr.t(String(key))).is_not_equal(String(key))
	Tr.set_locale(saved)

func test_the_blocks_are_also_in_the_help_index() -> void:
	for id in ["guide_qg_resources", "guide_qg_extract", "guide_qg_buildings", "guide_qg_progress"]:
		assert_bool(HelpCatalog.ENTRIES.has(id)).is_true()

## Bryan, 14-10: la guia ya no sale sola al cerrar el prologo. Sus bloques
## siguen en AYUDA (prueba de arriba). Un `quick_guide` visto en una partida
## vieja se carga sin mas.
func test_closing_the_prologue_does_not_open_the_guide() -> void:
	var saved := TutorialManager.get_save_data()
	TutorialManager.reset()
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	panel._on_prologue_closed()
	var opened: bool = panel.quick_guide().is_open()
	TutorialManager.load_save_data(saved)
	assert_bool(opened).is_false()
