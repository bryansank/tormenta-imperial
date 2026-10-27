extends GdUnitTestSuite
## La ficha del edificio nunca esconde su accion principal tras el pie fijo
## (QA escritorio punto 1): el contenido hace scroll por encima del pie.

const InfoScene := preload("res://scenes/ui/BuildingInfoPanel.tscn")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

var _nodes: Array = []
var _size0: Vector2i
var _phone0 := false
var _amounts := {}
var _unlocks := {}

func before_test() -> void:
	_size0 = get_window().size
	_phone0 = CT.phone
	_amounts = {}
	for t in ResourceManager.get_all():
		_amounts[ResourceManager.get_type_name(t)] = ResourceManager.get_amount(t)
	_unlocks = ResourceManager.get_unlock_state()
	GridManager.clear_all()
	ResourceManager.set_amounts({"gold": 9999, "wood": 9999, "steel": 9999, "oil": 9999})

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	ResourceManager.set_amounts(_amounts)
	ResourceManager.set_unlock_state(_unlocks)
	CT.phone = _phone0
	get_window().size = _size0

func _place(id: String) -> Node:
	var n := Node3D.new()
	n.set_meta("level", 1)
	_nodes.append(n)
	GridManager.place_building(Vector2i(10, 10), load("res://data/buildings/%s.tres" % id), n)
	return n

func _open(id: String, size: Vector2i, phone: bool, damaged: bool) -> Array:
	get_window().size = size
	CT.phone = phone
	var panel: CanvasLayer = auto_free(InfoScene.instantiate())
	add_child(panel)
	var n := _place(id)
	if damaged:
		BuildingHealth.damage_building(n, 40)
	EventBus.building_clicked.emit(n, load("res://data/buildings/%s.tres" % id))
	for i in 4:
		await await_idle_frame()
	return [panel, n]

func _check(panel: CanvasLayer, button: Control, label: String) -> void:
	var scroll: ScrollContainer = panel._scroll
	var foot: Control = panel._actions_box
	assert_bool(button.is_visible_in_tree()).override_failure_message(label + ": oculto").is_true()
	# El contenido acaba donde empieza el pie.
	assert_float(scroll.get_global_rect().end.y).override_failure_message(
		"%s: scroll %s pie %s" % [label, scroll.get_global_rect(), foot.get_global_rect()]).is_less_equal(foot.get_global_rect().position.y + 1.0)
	# El panel cabe en pantalla.
	var vp: Rect2 = get_viewport().get_visible_rect()
	assert_float(panel._panel.get_global_rect().end.y).override_failure_message(
		"%s: panel %s vp %s" % [label, panel._panel.get_global_rect(), vp]).is_less_equal(vp.end.y + 1.0)
	# Al abrir, la ficha ya baja hasta la accion: se ve entera sin tocar nada.
	var r := button.get_global_rect()
	var sr := scroll.get_global_rect()
	assert_bool(sr.grow(2.0).encloses(r)).override_failure_message(
		"%s: boton %s fuera del scroll %s" % [label, r, sr]).is_true()

func test_train_and_repair_are_reachable_everywhere() -> void:
	for cfg in [[Vector2i(1280, 720), false, "pc"], [Vector2i(1280, 800), false, "tablet"], [Vector2i(640, 360), true, "telefono"]]:
		var a: Array = await _open("barracks", cfg[0], cfg[1], false)
		var train: Control = a[0].find_child("TrainingSection", true, false)
		var btn: Control = null
		for b in train.find_children("*", "Button", true, false):
			if b.visible and b.is_visible_in_tree():
				btn = b
				break
		assert_object(btn).override_failure_message(cfg[2] + ": sin boton entrenar").is_not_null()
		await _check(a[0], btn, cfg[2] + " entrenar")
		var b2: Array = await _open("sawmill", cfg[0], cfg[1], true)
		await _check(b2[0], b2[0]._repair_btn, cfg[2] + " reparar")

func test_the_arrow_target_scrolls_the_real_repair_button_into_view() -> void:
	var a: Array = await _open("sawmill", Vector2i(1280, 720), false, true)
	var panel: CanvasLayer = a[0]
	panel._scroll.scroll_vertical = 0
	await await_idle_frame()
	var c := HelpTargets.control(get_tree(), "info_repair")
	assert_object(c).is_same(panel._repair_btn)
	await await_idle_frame()
	assert_bool(panel._scroll.get_global_rect().grow(2.0).encloses(c.get_global_rect())).is_true()

func test_the_demolish_question_has_its_group() -> void:
	var a: Array = await _open("sawmill", Vector2i(1280, 720), false, false)
	var panel: CanvasLayer = a[0]
	assert_bool(panel._confirm_container.is_in_group("hud_info_demolish_question")).is_true()
