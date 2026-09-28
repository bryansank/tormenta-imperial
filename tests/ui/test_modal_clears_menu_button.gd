extends GdUnitTestSuite
## QA en tableta (flujo 04): con la lista de CONSTRUIR abierta, el boton
## "☰ MENÚ" (capa 30, arriba a la derecha) tapaba la X de la ventana. Las
## ventanas centradas que llegan debajo del boton se acortan lo justo para que su
## cabecera empiece por debajo; las pequenas no cambian.

var _saved_vp := Vector2.ZERO

func before_test() -> void:
	_saved_vp = UILayoutManager._viewport_size

func after_test() -> void:
	UILayoutManager._viewport_size = _saved_vp

func _band() -> float:
	var btn := get_tree().get_first_node_in_group("hud_menu_button") as Control
	if btn != null and btn.size.x > 0.0:
		return btn.get_global_rect().end.y + UILayoutManager.MENU_BUTTON_GAP
	return UILayoutManager.MENU_BUTTON_MARGIN + float(UITheme.MIN_BTN_H) + UILayoutManager.MENU_BUTTON_GAP

func test_a_big_modal_starts_below_the_menu_button() -> void:
	# Lienzo de la tableta 2560x1600 con la escala de interfaz del perfil tablet.
	UILayoutManager._viewport_size = Vector2(1024, 640)
	var size: Vector2 = UILayoutManager.clear_menu_button(Vector2(1000, 624))
	var top := (640.0 - size.y) * 0.5
	assert_float(top).is_greater_equal(_band() - 0.01)
	assert_float(size.x).is_equal(1000.0)

func test_a_small_modal_is_left_alone() -> void:
	UILayoutManager._viewport_size = Vector2(1280, 800)
	var size: Vector2 = UILayoutManager.clear_menu_button(Vector2(560, 400))
	assert_vector(size).is_equal(Vector2(560, 400))

func test_a_tall_but_narrow_modal_is_left_alone() -> void:
	# No llega debajo del boton por la derecha: nada que despejar.
	UILayoutManager._viewport_size = Vector2(1280, 800)
	var size: Vector2 = UILayoutManager.clear_menu_button(Vector2(600, 784))
	assert_vector(size).is_equal(Vector2(600, 784))

## Flujo 04: en tableta el detalle es mas alto que la ventana y el CONSTRUIR
## del detalle quedaba fuera, bajo el scroll. Ahora va fuera del scroll.
func test_the_detail_build_button_is_never_scrolled_away() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	var btn: Button = menu.find_child("DetailBuildButton", true, false)
	assert_object(btn).is_not_null()
	var n: Node = btn.get_parent()
	while n != null and n != menu:
		assert_bool(n is ScrollContainer).is_false()
		n = n.get_parent()

func test_the_build_list_x_is_not_under_the_menu_button() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	var modal: Control = menu.get("_modal")
	UILayoutManager.apply_layout("ConstructionMenu.modal", modal)
	var vp: Vector2 = UILayoutManager._viewport_size
	var size: Vector2 = UILayoutManager.clear_menu_button(Vector2(1000, 660))
	# El lugar donde va la ventana, segun el mismo calculo que _place.
	var top := (vp.y - size.y) * 0.5
	var right := (vp.x + size.x) * 0.5
	var btn_left := vp.x - UILayoutManager.MENU_BUTTON_MARGIN - UILayoutManager.MENU_BUTTON_FALLBACK_W
	if right > btn_left:
		assert_float(top).is_greater_equal(_band() - 0.01)
