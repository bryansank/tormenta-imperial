extends GdUnitTestSuite
## Lo que el jugador ve al construir (2026-09-28): el coste en cada tarjeta de la
## lista, el tiempo que le falta a una obra y, en el tutorial, que la tarjeta que
## se pide se desplace a la vista y que, ya elegida, el foco pase a CONSTRUIR.

const MenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func test_a_card_says_what_the_building_costs() -> void:
	var text: String = MenuScript.card_cost_text(_data("house"))
	assert_str(text).contains(str(_data("house").cost_gold))
	assert_str(text).contains(Tr.res_name("gold"))
	assert_str(text).contains(Tr.res_name("wood"))

func test_the_core_is_free_and_says_nothing() -> void:
	assert_str(MenuScript.card_cost_text(_data("nucleo"))).is_equal("")

func test_the_time_left_reads_at_a_glance() -> void:
	assert_str(ProductionManager.eta_text(11.2)).is_equal("12 s")
	assert_str(ProductionManager.eta_text(0.0)).is_equal("0 s")
	assert_str(ProductionManager.eta_text(125.0)).is_equal("2:05 min")

func test_the_house_card_scrolls_into_view_then_hands_over_to_build() -> void:
	var main := Node.new()
	main.name = "FakeMain"
	add_child(main)
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	menu.name = "ConstructionMenu"
	main.add_child(menu)
	await await_idle_frame()
	menu.call("_open")
	await await_idle_frame()
	var card := HelpTargets.building_card(get_tree(), "house")
	assert_object(card).is_not_null()
	# Sin elegir: el objetivo es la tarjeta.
	assert_object(HelpTargets.card_or_build(get_tree(), "house")).is_same(card)
	# Elegida: el objetivo es el CONSTRUIR del detalle.
	menu.call("_select_building", _data("house"))
	var target := HelpTargets.card_or_build(get_tree(), "house")
	var build: Button = menu.detail_build_button()
	menu.call("_close")
	main.free()
	assert_object(target).is_same(build)

## Al empezar, el Cuartel General dice todo lo que le falta en vez de salir gris
## sin mas: acero y petroleo por desbloquear, y un Cuartel y una Refineria antes.
func test_the_headquarters_says_everything_it_lacks_at_the_start() -> void:
	if ResourceManager.is_unlocked(ResourceManager.Type.STEEL):
		return
	var reasons: Array = Rules.block_reasons(_data("headquarters"))
	var text := "\n".join(reasons)
	assert_str(text).contains(Tr.res_name("steel"))
	assert_str(text).contains(Tr.res_name("oil"))
	assert_str(text).contains(_data("barracks").get_display_name())
	assert_str(text).contains(_data("refinery").get_display_name())

func test_a_house_card_says_it_brings_workers() -> void:
	assert_str(Tr.t("LBL_CARD_WORKERS") % _data("house").population_capacity).contains(str(_data("house").population_capacity))
