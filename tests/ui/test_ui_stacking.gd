extends GdUnitTestSuite
## El apilado real del HUD (A8), por encima.
##
## Los huecos del HUD eran offsets fijos en pixeles calibrados para una
## tipografia que ya no existe; cada vez que la letra crecio, un panel se comio
## el hueco del siguiente y "TODA la UI se superpone". Estas pruebas fijan la
## regla nueva: un panel con `stack_after` empieza debajo del borde inferior
## REAL del referido, sea cual sea su altura, y si el referido se oculta ocupa
## su sitio. Tocan el UILayoutManager real (autoload) con controles de prueba.
##
## No se usa monitor_signals sobre autoloads: libera el objeto vigilado.

var _saved_sidebar := false

func before_test() -> void:
	_saved_sidebar = UILayoutManager.is_sidebar_expanded()

func after_test() -> void:
	# El menu lateral se deja como estaba: otros tests leen su borde inferior.
	EventBus.sidebar_toggled.emit(_saved_sidebar)
	await await_idle_frame()

## Un panel con `lines` lineas de texto: su altura real depende de la fuente,
## que es justo lo que las pruebas no quieren dar por supuesto.
func _panel_with_lines(lines: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	for i in lines:
		vbox.add_child(UITheme.make_label("linea %d" % i, "body"))
	return panel

func _place(panel_id: String, lines: int) -> PanelContainer:
	var panel: PanelContainer = auto_free(_panel_with_lines(lines))
	UILayoutManager.apply_layout(panel_id, panel)
	add_child(panel)
	return panel

## Dos frames: uno para que el panel de arriba reciba su tamano (resized) y
## otro para el flush diferido que recoloca a los de abajo.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()

func _top(c: Control) -> float:
	return c.get_global_rect().position.y

func _bottom(c: Control) -> float:
	return c.get_global_rect().end.y

@warning_ignore("unused_parameter")
func test_the_status_panel_starts_below_resources_whatever_their_height(lines: int, test_parameters := [[1], [3], [7]]) -> void:
	var resources := _place("ResourceHUD", lines)
	var status := _place("NotificationPanel.status", 2)
	await _settle()
	assert_float(resources.size.y).is_greater(0.0)
	assert_float(_top(status)).is_greater_equal(_bottom(resources))
	# Y no se va al fondo de la pantalla: esta pegado, con el hueco configurado.
	assert_float(_top(status) - _bottom(resources)).is_less_equal(UILayoutManager.DEFAULT_STACK_GAP + 1.0)

func test_when_the_panel_above_grows_the_one_below_moves_down() -> void:
	var resources := _place("ResourceHUD", 1)
	var status := _place("NotificationPanel.status", 2)
	await _settle()
	var before := _top(status)

	var vbox: VBoxContainer = resources.get_child(0)
	for i in 4:
		vbox.add_child(UITheme.make_label("mas contenido %d" % i, "body"))
	await _settle()

	assert_float(_top(status)).is_greater(before)
	assert_float(_top(status)).is_greater_equal(_bottom(resources))

func test_a_hidden_panel_above_gives_its_place_to_the_one_below() -> void:
	var resources := _place("ResourceHUD", 3)
	var status := _place("NotificationPanel.status", 2)
	await _settle()
	assert_float(_top(status)).is_greater_equal(_bottom(resources))

	resources.visible = false
	await _settle()
	# Ocupa el hueco del de arriba: el margen superior del slot de recursos.
	var expected: float = float(UILayoutConfig.SLOTS["top_left"]["margin"]["top"])
	assert_float(_top(status)).is_equal_approx(expected, 1.0)

	resources.visible = true
	await _settle()
	assert_float(_top(status)).is_greater_equal(_bottom(resources))

func test_a_three_level_column_never_overlaps() -> void:
	var resources := _place("ResourceHUD", 2)
	var status := _place("NotificationPanel.status", 4)
	var log := _place("NotificationPanel.log", 1)
	await _settle()
	assert_float(_top(status)).is_greater_equal(_bottom(resources))
	assert_float(_top(log)).is_greater_equal(_bottom(status))

func test_the_objective_takes_the_top_of_the_center_column_when_the_storm_is_calm() -> void:
	var storm := _place("StormHUD", 1)
	var objective := _place("NotificationPanel.objective", 2)
	await _settle()
	assert_float(_top(objective)).is_greater_equal(_bottom(storm))

	storm.visible = false
	await _settle()
	var expected: float = float(UILayoutConfig.SLOTS["storm_banner"]["margin"]["top"])
	assert_float(_top(objective)).is_equal_approx(expected, 1.0)

func test_the_building_panel_starts_under_the_sidebar_open_or_closed() -> void:
	EventBus.sidebar_toggled.emit(false)
	var info := _place("BuildingInfoPanel", 3)
	await _settle()
	var collapsed_bottom := UILayoutManager.get_sidebar_bottom()
	assert_float(_top(info)).is_greater_equal(collapsed_bottom)

	EventBus.sidebar_toggled.emit(true)
	await _settle()
	var expanded_bottom := UILayoutManager.get_sidebar_bottom()
	assert_float(expanded_bottom).is_greater(collapsed_bottom)
	assert_float(_top(info)).is_greater_equal(expanded_bottom)

	EventBus.sidebar_toggled.emit(false)
	await _settle()
	assert_float(_top(info)).is_less(expanded_bottom)

func test_every_stack_reference_exists_and_has_no_cycles() -> void:
	# Un ciclo en la configuracion colgaria el layout; una referencia a un
	# panel que no existe dejaria el slot en su margen fijo sin avisar.
	for slot_name in UILayoutConfig.SLOTS:
		var slot: Dictionary = UILayoutConfig.SLOTS[slot_name]
		var after := String(slot.get("stack_after", ""))
		if after.is_empty():
			continue
		var known: bool = after == UILayoutConfig.SIDEBAR_STACK_REF or UILayoutConfig.PANEL_SLOTS.has(after)
		assert_bool(known).override_failure_message("'%s' apila bajo '%s', que no es un panel conocido" % [slot_name, after]).is_true()

		var seen := [slot_name]
		var cursor := after
		while not cursor.is_empty() and cursor != UILayoutConfig.SIDEBAR_STACK_REF:
			var next_slot := String(UILayoutConfig.PANEL_SLOTS.get(cursor, ""))
			assert_bool(next_slot in seen).override_failure_message("ciclo de apilado en '%s'" % slot_name).is_false()
			seen.append(next_slot)
			cursor = String(UILayoutConfig.SLOTS[next_slot].get("stack_after", ""))
		assert_int(seen.size()).is_less_equal(UILayoutManager.MAX_STACK_DEPTH)

func test_the_layout_rect_reports_the_stacked_top_too() -> void:
	var resources := _place("ResourceHUD", 3)
	await _settle()
	var rect := UILayoutManager.get_layout_rect("NotificationPanel.status")
	assert_float(rect.position.y).is_greater_equal(_bottom(resources))
