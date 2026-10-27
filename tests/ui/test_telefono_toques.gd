extends GdUnitTestSuite
## Telefono pequeno (fix/telefono-toques): 48 para el dedo, la X lejos del ☰,
## girar/CANCELAR opacos al colocar, la barra de abajo anclada en vertical.

const OSC := preload("res://scripts/ui/OnScreenControls.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

func test_dodge_leaves_a_clear_gap_next_to_the_menu_button() -> void:
	var low := CanvasLayer.new()
	low.layer = 12
	add_child(auto_free(low))
	var close := Control.new()
	close.position = Vector2(400, 20)
	close.size = Vector2(50, 50)
	low.add_child(close)
	var high := CanvasLayer.new()
	high.layer = 30
	add_child(auto_free(high))
	var menu := Control.new()
	menu.position = Vector2(446, 14)
	menu.size = Vector2(54, 54)
	menu.add_to_group("hud_menu_button")
	high.add_child(menu)
	CT.dodge_menu_button(close)
	var gap: float = menu.get_global_rect().position.x - close.get_global_rect().end.x
	assert_float(gap).is_greater_equal(15.9)

func test_placement_buttons_stay_opaque_while_placing() -> void:
	var osc = auto_free(OSC.new())
	add_child(osc)
	osc.set_opacity(0.45)
	var rot: Button = osc.find_child("RotateBuilding", true, false)
	if rot == null:
		rot = osc._rotate_building_btn
	var cancel: Button = osc._cancel_placement_btn
	osc._set_placing(true)
	assert_float(rot.modulate.a).is_equal(1.0)
	assert_float(cancel.modulate.a).is_equal(1.0)
	osc._set_placing(false)
	assert_float(rot.modulate.a).is_equal_approx(0.45, 0.001)

func test_help_rows_and_color_swatches_are_48() -> void:
	var b := CT.list_button("help", "Titulo", true)
	assert_float(b.custom_minimum_size.y).is_greater_equal(48.0)
	var ColonyPanel := load("res://scripts/ui/ColonyIdentityPanel.gd")
	assert_float(ColonyPanel.SWATCH).is_greater_equal(48.0)

func test_narrow_bottom_bar_hugs_the_bottom() -> void:
	var bar: Dictionary = UILayoutConfig.NARROW_SLOTS["bottom_bar"]
	assert_int(int(bar["margin"]["bottom"])).is_less(60)
	var step: Dictionary = UILayoutConfig.NARROW_SLOTS["next_step"]
	assert_int(int(step["margin"]["bottom"])).is_less(160)
