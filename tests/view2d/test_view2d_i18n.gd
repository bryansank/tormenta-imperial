extends GdUnitTestSuite
## El rotulo de un edificio en la vista 2D sale en el idioma del jugador.
##
## Building2D leia el campo crudo `display_name` del .tres, que esta en espanol:
## en ingles la vista 2D ensenaba "Aserradero". El nombre sale de
## BuildingData.get_display_name(), como en 3D, y se rehace si cambia el idioma.
## Un nombre puesto por el jugador (custom_name) no se traduce: manda el suyo.
##
## Toca Tr (autoload): cada caso devuelve el idioma que encontro.

const Building2DScript := preload("res://scripts/view2d/Building2D.gd")

var _saved_locale := "es"
var _building: Node2D = null

func before_test() -> void:
	_saved_locale = Tr.get_locale()

func after_test() -> void:
	if is_instance_valid(_building):
		_building.queue_free()
	_building = null
	Tr.set_locale(_saved_locale)

func _spawn(id: String) -> Node2D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	_building = Building2DScript.new()
	_building.setup(data)
	add_child(_building)
	return _building

func _label_text() -> String:
	return (_building.get_node("NameLabel") as Label).text

func test_en_ingles_el_rotulo_2d_sale_en_ingles() -> void:
	Tr.set_locale("en")
	_spawn("sawmill")
	assert_str(_label_text()).is_equal("Sawmill")
	# Y sigue en ingles despues del primer frame, cuando la firma lo rehace.
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_label_text()).is_equal("Sawmill")

func test_en_espanol_el_rotulo_2d_sale_en_espanol() -> void:
	Tr.set_locale("es")
	_spawn("sawmill")
	await await_idle_frame()
	assert_str(_label_text()).is_equal("Aserradero")

func test_cambiar_de_idioma_retitula_el_rotulo_2d() -> void:
	Tr.set_locale("es")
	_spawn("gold_mine")
	await await_idle_frame()
	var es_text := _label_text()
	Tr.set_locale("en")
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_label_text()).is_equal(_building.data.get_display_name())
	assert_str(_label_text()).is_not_equal(es_text)

func test_el_nombre_puesto_por_el_jugador_no_se_traduce() -> void:
	Tr.set_locale("en")
	_spawn("sawmill")
	_building.set_meta("custom_name", "La Tala")
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_label_text()).is_equal("La Tala")
