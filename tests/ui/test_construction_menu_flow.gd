extends GdUnitTestSuite
## Un objetivo cumplido no vuelve (2026-10-24). Queja de Bryan: "si no hago clic
## en el Cuartel, me salgo y le doy a CONSTRUIR, me da nuevamente la opcion de
## crear Cuartel como objetivo, cuando ya pase ese objetivo". La lista de
## CONSTRUIR recordaba el ultimo edificio elegido: al abrirla otra vez salia el ya
## puesto en el detalle, con su boton CONSTRUIR. Ahora, al pulsar CONSTRUIR, la
## lista se queda sin nada elegido (salvo carretera y decoraciones, que se ponen
## en serie).

var _amounts: Dictionary = {}
var _guide := ""

func before_test() -> void:
	_amounts = {}
	for t in ResourceManager.get_all():
		_amounts[ResourceManager.get_type_name(t)] = ResourceManager.get_amount(t)
	ResourceManager.set_amounts({"gold": 500, "wood": 300})
	_guide = TutorialManager.guide_state
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	GridManager.clear_all()

func after_test() -> void:
	EventBus.building_placement_cancelled.emit()
	ResourceManager.set_amounts(_amounts)
	TutorialManager.guide_state = _guide
	GridManager.clear_all()

func _menu() -> CanvasLayer:
	var node: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(node)
	return node

func test_after_building_the_list_opens_with_nothing_chosen() -> void:
	var menu := _menu()
	menu.open_on("house")
	assert_str(menu.selected_building_id()).is_equal("house")
	menu._on_build_pressed()
	EventBus.building_placement_cancelled.emit()
	menu.open()
	assert_str(menu.selected_building_id()).is_equal("")
	assert_bool(menu.detail_build_button().visible).is_false()

func test_roads_stay_chosen_to_lay_another() -> void:
	var menu := _menu()
	menu.open_on("road")
	menu._on_build_pressed()
	EventBus.building_placement_cancelled.emit()
	menu.open()
	assert_str(menu.selected_building_id()).is_equal("road")
