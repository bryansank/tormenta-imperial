extends CanvasLayer
## Panel de recursos, esquina superior izquierda: [icono] cantidad por cada
## recurso desbloqueado, los obreros libres y (con la Tormenta armada) la moral,
## todo en una fila; debajo, UNA barra de almacen con su cifra.
##
## El almacen es una bolsa compartida: un solo tope para la suma de los cuatro.
## Antes el HUD ensenaba "528/600" pegado a un recurso y mentia: parecia el tope
## de ese recurso. Ahora el tope sale una vez, bajo los cuatro, y la barra ensena
## como se reparte la bolsa. Cuando se llena, la barra y el numero se ponen
## rojos: lo que entre a partir de ahi se pierde y el jugador tiene que verlo.
##
## Sin texto fijo (2026-10): ni nombres al lado de los numeros, ni "ALMACEN
## COMPARTIDO", ni la tarjeta aparte de trabajadores y moral (NotificationPanel)
## que repetia en palabras lo mismo. Lo que significa cada cifra va en su
## tooltip con el raton y, con el dedo (Godot no ensena tooltips al tocar), un
## toque en cualquier ficha o en la barra despliega el detalle con nombres y
## explicaciones; otro toque lo recoge.
##
## Obreros: la cifra es los LIBRES, lo que decide si cabe el siguiente edificio.
## Habitantes, ocupados y retirados van al tooltip. Si algun edificio se queda
## sin obreros, la cifra pasa a UITheme.WARNING.
## Moral: solo desde que la Tormenta esta armada (morale_visible()): antes no
## presiona y era ruido. Numero con el color de su umbral.
##
## Los iconos (moneda, tronco, lingote, gota, obrero, corazon) los genera
## tools/gen_resource_icons.gd; los estilos salen todos de UITheme.
##
## Nombres bajo los iconos (feat/hud-y-tutorial, ronda 1.0 mejora 4): cada ficha
## va en una celda con su palabra debajo ("Oro", "Trabajadores", "Moral"). Se
## ven segun GameConfig.hud_words_enabled() (Ajustes > Interfaz > Nombres junto
## a los iconos: en "auto", tableta y movil siempre; PC, la primera hora de las
## primeras partidas). Con palabras la fila no pasa de WORDS_ROW_MAX y se parte
## en dos filas (cabe en 1280x720 y en un movil). Sin palabras, la celda es solo
## la ficha: nada cambia respecto a antes.

## Umbrales de color de la moral (los mismos que tenia la tarjeta vieja).
const MORALE_DANGER := 30
const MORALE_WARNING := 60
## Hueco entre fichas, y entre la fila y el boton ☰ cuando se parte.
const ROW_SEPARATION := 10
const MENU_GAP := 6.0
## Margenes de la tarjeta del HUD (UITheme.make_hud_card_style), izq. + der.
const CARD_MARGINS := 20.0
## Alto del LIMPIAR de desarrollo en escritorio (con el dedo, MIN_BTN_H).
const DEV_BTN_PX := 28.0
## Ancho maximo de la fila con palabras: cinco recursos en la primera fila y
## trabajadores y moral en la segunda; la columna central no se desplaza.
const WORDS_ROW_MAX := 380.0
## Cada cuanto se mira si el "auto" ya paso la primera hora (segundos reales).
## Una comprobacion por minuto: nada de _process.
const WORDS_CHECK_SECONDS := 60.0

var _panel: PanelContainer
var _chips: Dictionary = {}       # Type -> HBoxContainer (UITheme.make_resource_chip)
var _exp_rows: Dictionary = {}    # Type -> HBoxContainer (fila con nombre, desplegada)
var _exp_labels: Dictionary = {}  # Type -> Label (cantidad en la fila desplegada)
var _segments: Dictionary = {}    # Type -> ColorRect, su tajada de la barra
var _free_segment: ColorRect
var _pool_bar: PanelContainer
var _storage_value: Label
var _content_box: VBoxContainer
var _chips_row: HFlowContainer
## Obreros y moral: fichas como las de recursos, con su detalle desplegable.
var _workers_chip: HBoxContainer
var _morale_chip: HBoxContainer
var _workers_detail: Label
var _morale_detail: Label
## TALLER: los materiales (tablones, lingotes, vigas, combustible), fuera de la
## bolsa. Una fila aparte, solo con los que ya estan en el juego.
var _mat_row: HBoxContainer
var _mat_labels: Dictionary = {}  # Type -> Label
var _is_expanded := false
## Nombres bajo los iconos: ficha -> su celda (VBox) y su palabra (Label).
var _cells: Dictionary = {}
var _words: Dictionary = {}
var _words_on := false
var _words_timer: Timer = null

## En orden de era: lo primero que ve un jugador nuevo es oro y madera.
var _resource_ids := ["gold", "wood", "food", "steel", "oil"]
var _resource_types := [
	ResourceManager.Type.GOLD, ResourceManager.Type.WOOD, ResourceManager.Type.FOOD,
	ResourceManager.Type.STEEL, ResourceManager.Type.OIL,
]

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.resources_insufficient.connect(_on_insufficient)
	EventBus.resource_unlocked.connect(_on_resource_unlocked)
	EventBus.storage_overflow.connect(_on_overflow)
	# Con el dedo, cada ficha que se toca crece a UITheme.MIN_BTN_H.
	EventBus.touch_controls_changed.connect(func(_on): _size_for_touch())
	EventBus.population_changed.connect(func(_c, _m): _refresh_people())
	EventBus.workers_changed.connect(func(_u, _t): _refresh_people())
	EventBus.morale_changed.connect(func(_m): _refresh_people())
	# La moral aparece cuando se arma la Tormenta. No hay senal de "armada":
	# se arma al subir de fase (y al cargar), y en Sandbox se invoca a mano.
	# Se mira en diferido, cuando StormManager ya ha procesado la senal.
	EventBus.phase_advanced.connect(func(_p): _refresh_people.call_deferred())
	EventBus.storm_phase_changed.connect(func(_p, _s): _refresh_people.call_deferred())
	EventBus.storm_incoming.connect(func(_s): _refresh_people.call_deferred())
	EventBus.storm_ash_started.connect(func(): _refresh_people.call_deferred())
	EventBus.storm_started.connect(func(_s): _refresh_people.call_deferred())
	EventBus.storm_ended.connect(func(_s): _refresh_people.call_deferred())
	EventBus.storm_halted_forever.connect(func(): _refresh_people.call_deferred())
	EventBus.game_load_completed.connect(func(): _refresh_people.call_deferred())
	EventBus.game_new_started.connect(func(): _refresh_people.call_deferred())
	# Nombres bajo los iconos: al cambiar el ajuste, el perfil (tableta/PC) o la
	# partida (la "primera hora" es de cada partida).
	EventBus.hud_words_changed.connect(func(_on): apply_words())
	EventBus.touch_controls_changed.connect(func(_on): apply_words())
	EventBus.game_load_completed.connect(func(): apply_words.call_deferred())
	EventBus.game_new_started.connect(func(): apply_words.call_deferred())

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ResourceHUD", _panel)
	_panel.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT))
	root.add_child(_panel)
	HudRegistry.register("ResourceHUD", _panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# ── Fila de fichas: [icono] cantidad por recurso, obreros y moral ──
	# Una fila que se parte en dos si choca con el boton ☰ (movil en vertical):
	# seis fichas no caben en 400 px. Ver _fit_row().
	var chips_row := HFlowContainer.new()
	chips_row.name = "ChipsRow"
	chips_row.add_theme_constant_override("h_separation", ROW_SEPARATION)
	chips_row.add_theme_constant_override("v_separation", 4)
	vbox.add_child(chips_row)
	_chips_row = chips_row

	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var chip := UITheme.make_resource_chip(_resource_ids[i])
		# Cada numero dice que es (bug 11): nombre al pasar el raton y, con el
		# dedo, un toque despliega la fila con nombres.
		chip.name = "Chip_" + _resource_ids[i]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(_on_tap_expand)
		_add_cell(chip, _resource_ids[i], Tr.res_cap(_resource_ids[i]), chips_row)
		_set_chip_shown(chip, ResourceManager.is_unlocked(type))
		_chips[type] = chip

	_workers_chip = _make_people_chip("workers", Tr.t("HUD_WORD_WORKERS"), chips_row)
	_morale_chip = _make_people_chip("morale", Tr.t("HUD_WORD_MORALE"), chips_row)

	# Dev-only shortcut to wipe the save. Players use Settings > New game instead.
	if GameConfig.dev_mode:
		var clear_btn := Button.new()
		clear_btn.text = Tr.t("BTN_CLEAR")
		UITheme.style_button(clear_btn, UITheme.DANGER, UITheme.FONT_SMALL)
		clear_btn.custom_minimum_size.y = UITheme.touch_px(DEV_BTN_PX)
		clear_btn.pressed.connect(GameManager.request_new_game)
		chips_row.add_child(clear_btn)

	# ── Detalle desplegable: una fila con nombre por recurso ──
	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 4)
	_content_box.visible = false
	vbox.add_child(_content_box)
	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var res_id: String = _resource_ids[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# La muestra de color es la leyenda de la barra del almacen.
		var swatch := ColorRect.new()
		swatch.color = UITheme.resource_color(res_id)
		swatch.custom_minimum_size = Vector2(10, 10)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(UITheme.make_icon(res_id, 20))
		var name_lbl := UITheme.make_label(Tr.res_upper(res_id), "small", UITheme.resource_color(res_id))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var amt := UITheme.make_label("0", "small", UITheme.TEXT_BRIGHT)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amt)
		row.visible = ResourceManager.is_unlocked(type)
		_content_box.add_child(row)
		_exp_rows[type] = row
		_exp_labels[type] = amt

	# Obreros y moral, en palabras: lo mismo que sus tooltips, para el dedo.
	_workers_detail = _make_detail_label("WorkersDetail")
	_morale_detail = _make_detail_label("MoraleDetail")
	# Que es la barra: un tope para los cuatro, y lo que no cabe se pierde.
	var legend := _make_detail_label("StorageLegend")
	legend.text = Tr.t("HINT_HUD_STORAGE")

	# ── Almacen: la barra y "730/1000" en una linea. Sin titulo: lo que es va
	# en el tooltip y en el detalle (el tope es uno para los cuatro). ──
	var storage_row := HBoxContainer.new()
	storage_row.name = "StorageRow"
	storage_row.add_theme_constant_override("separation", 8)
	storage_row.mouse_filter = Control.MOUSE_FILTER_STOP
	storage_row.tooltip_text = Tr.t("HINT_HUD_STORAGE")
	storage_row.gui_input.connect(_on_tap_expand)
	vbox.add_child(storage_row)

	var colors: Array = []
	for res_id in _resource_ids:
		colors.append(UITheme.resource_color(res_id))
	_pool_bar = UITheme.make_pool_bar(colors, 8)
	_pool_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	storage_row.add_child(_pool_bar)

	_storage_value = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_storage_value.name = "StorageValue"
	_storage_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_storage_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	storage_row.add_child(_storage_value)
	var segs := UITheme.pool_bar_segments(_pool_bar)
	for i in range(_resource_types.size()):
		_segments[_resource_types[i]] = segs[i]
	_free_segment = UITheme.pool_bar_free(_pool_bar)

	# ── Taller: materiales, fuera de la bolsa ──
	_mat_row = HBoxContainer.new()
	_mat_row.name = "MaterialsRow"
	_mat_row.add_theme_constant_override("separation", 10)
	_mat_row.tooltip_text = Tr.t("HINT_MATERIALS")
	_mat_row.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_mat_row)
	# Sin el rotulo "TALLER": los nombres ya dicen lo que son; el tooltip, donde estan.
	for type in ResourceManager.MATERIALS:
		var res_id: String = ResourceManager.get_type_name(type)
		var lbl := UITheme.make_label("", "small", UITheme.resource_color(res_id))
		lbl.name = "Mat_" + res_id
		lbl.tooltip_text = Tr.t("HINT_MATERIALS")
		_mat_row.add_child(lbl)
		_mat_labels[type] = lbl

	_refresh()
	_refresh_people()
	_size_for_touch()
	apply_words()
	get_viewport().size_changed.connect(_fit_row.call_deferred)
	_fit_row.call_deferred()

## Mete `chip` en una celda con su palabra debajo (oculta hasta apply_words).
func _add_cell(chip: HBoxContainer, word_id: String, word: String, row: Container) -> void:
	var cell := VBoxContainer.new()
	cell.name = "Cell_" + word_id
	cell.add_theme_constant_override("separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(chip)
	var lbl := UITheme.make_label(word, "small", UITheme.TEXT_DIM)
	lbl.name = "Word_" + word_id
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Tocar la palabra hace lo mismo que tocar la ficha: desplegar el detalle.
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.tooltip_text = word
	lbl.gui_input.connect(_on_tap_expand)
	lbl.visible = false
	cell.add_child(lbl)
	row.add_child(cell)
	_cells[chip] = cell
	_words[chip] = lbl

## Ensena u oculta una ficha con su celda (la palabra va con ella).
func _set_chip_shown(chip: HBoxContainer, on: bool) -> void:
	chip.visible = on
	var cell: Control = _cells.get(chip)
	if cell != null:
		cell.visible = on

## Pone o quita las palabras bajo los iconos segun el ajuste (y el "auto").
## Publica: la llaman las senales y las pruebas.
func apply_words() -> void:
	if _chips_row == null:
		return
	var on := GameConfig.hud_words_enabled()
	_words_on = on
	for chip in _words:
		(_words[chip] as Label).visible = on
	# El "auto" de PC se apaga solo pasada la primera hora: un vistazo por minuto
	# mientras siga encendido por eso. Con "siempre", "nunca" o en tableta, nada.
	_watch_words(on and GameConfig.hud_words_timed())
	_fit_row()

func _watch_words(on: bool) -> void:
	if not on:
		if _words_timer != null:
			_words_timer.stop()
		return
	if _words_timer == null:
		_words_timer = Timer.new()
		_words_timer.name = "WordsTimer"
		_words_timer.wait_time = WORDS_CHECK_SECONDS
		_words_timer.timeout.connect(func():
			if GameConfig.hud_words_enabled() != _words_on:
				apply_words())
		add_child(_words_timer)
	if _words_timer.is_stopped() and _words_timer.is_inside_tree():
		_words_timer.start()

## Si las palabras estan a la vista ahora (pruebas).
func words_shown() -> bool:
	return _words_on

## La palabra bajo una ficha (pruebas), o null.
func word_of(chip: HBoxContainer) -> Label:
	return _words.get(chip) as Label

## Las fichas se tocan: con el dedo no bajan de MIN_BTN_H de alto (el ancho
## lo da el numero; forzarlo ensanchaba la fila y empujaba la columna central).
## Con el raton se quedan en su tamano natural. La barra del almacen no crece:
## las fichas ya despliegan el mismo detalle.
func _size_for_touch() -> void:
	var side := UITheme.touch_px(0.0)
	for c in tap_targets():
		(c as Control).custom_minimum_size.y = side

## La fila de fichas, en una linea mientras quepa a la izquierda del boton ☰;
## si no, se parte (HFlowContainer) al ancho que deja libre. En PC y tablet en
## horizontal el ☰ queda lejos y la fila nunca se parte.
func _fit_row() -> void:
	if _chips_row == null:
		return
	var natural := 0.0
	var shown := 0
	for c in _chips_row.get_children():
		if (c as Control).visible:
			natural += (c as Control).get_combined_minimum_size().x
			shown += 1
	# +1: sin holgura, un redondeo parte la fila aunque quepa.
	natural += float(maxi(0, shown - 1) * ROW_SEPARATION) + 1.0
	var room := _room_before_menu()
	# Con palabras la fila es mas ancha: no pasa de WORDS_ROW_MAX y se parte en
	# dos filas, para no empujar la columna central (1280x720) ni el ☰ (movil).
	if _words_on:
		room = minf(room, WORDS_ROW_MAX)
	_chips_row.custom_minimum_size.x = minf(natural, room)

## Ancho util de la fila hasta el boton ☰ (o sin limite si no hay boton o no
## esta en la misma franja de arriba).
func _room_before_menu() -> float:
	if not is_inside_tree():
		return INF
	var btn := get_tree().get_first_node_in_group("hud_menu_button") as Control
	if btn == null or not btn.is_visible_in_tree() or _panel == null:
		return INF
	var b := btn.get_global_rect()
	var p := _panel.get_global_rect()
	if b.position.y > p.position.y + 60.0:
		return INF
	return maxf(120.0, b.position.x - MENU_GAP - p.position.x - CARD_MARGINS)

## Las fichas que se tocan (tests).
func tap_targets() -> Array:
	return _chips.values() + [_workers_chip, _morale_chip]

## Ficha de obreros o de moral: la misma forma que la de un recurso.
func _make_people_chip(icon_id: String, word: String, row: Container) -> HBoxContainer:
	var chip := UITheme.make_resource_chip(icon_id)
	chip.name = "Chip_" + icon_id
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.gui_input.connect(_on_tap_expand)
	_add_cell(chip, icon_id, word, row)
	return chip

func _make_detail_label(node_name: String) -> Label:
	var lbl := UITheme.make_label("", "small", UITheme.TEXT_DIM)
	lbl.name = node_name
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 220
	_content_box.add_child(lbl)
	return lbl

## Un toque (o clic) en una ficha o en el almacen despliega el detalle.
func _on_tap_expand(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_expanded()
		get_viewport().set_input_as_handled()

func _toggle_expanded() -> void:
	_is_expanded = not _is_expanded
	_content_box.visible = _is_expanded

func is_expanded() -> bool:
	return _is_expanded

## La ficha de obreros / de moral (tests, HelpTargets).
func workers_chip() -> HBoxContainer:
	return _workers_chip

func morale_chip() -> HBoxContainer:
	return _morale_chip

## La moral se ensena desde que la Tormenta esta armada (y despues de pararla
## para siempre, cuando importa igual). Antes de eso no aprieta: era ruido.
static func morale_visible() -> bool:
	return StormManager.is_armed() or StormManager.is_halted()

## Color de la moral por umbral, de los tokens de la paleta.
static func morale_color(morale: int) -> Color:
	if morale <= MORALE_DANGER:
		return UITheme.DANGER
	if morale <= MORALE_WARNING:
		return UITheme.WARNING
	return UITheme.POSITIVE

## Obreros y moral, leidos de los servicios (no de los argumentos de la senal:
## varias senales disparan esto y cada una trae otra cosa).
func _refresh_people() -> void:
	if _workers_chip == null:
		return
	var pop := PopulationManager.get_population()
	var max_pop := PopulationManager.get_max_population()
	var used := PopulationManager.get_used_workers()
	var free := maxi(0, pop - used)
	var short := PopulationManager.get_understaffed_count()
	var retired := PopulationManager.get_retired_workers()
	var amount := UITheme.chip_amount(_workers_chip)
	amount.text = str(free)
	UITheme.set_label_color(amount, UITheme.WARNING if short > 0 else UITheme.TEXT_BRIGHT)
	var lines: Array = [Tr.t("HINT_HUD_WORKERS") % [free, pop, max_pop, used]]
	if retired > 0:
		lines.append(Tr.t("HINT_HUD_WORKERS_OFF") % retired)
	if short > 0:
		lines.append(Tr.t("HINT_HUD_WORKERS_SHORT") % short)
	var tip := "\n".join(lines)
	_workers_chip.tooltip_text = tip
	_workers_detail.text = tip

	var shown := morale_visible()
	_set_chip_shown(_morale_chip, shown)
	_morale_detail.visible = shown
	var morale := PopulationManager.get_morale()
	var m_amount := UITheme.chip_amount(_morale_chip)
	m_amount.text = str(morale)
	UITheme.set_label_color(m_amount, morale_color(morale))
	var m_tip := Tr.t("HINT_HUD_MORALE") % [morale, PopulationManager.morale_to_multiplier(morale)]
	_morale_chip.tooltip_text = m_tip
	_morale_detail.text = m_tip
	_fit_row()

## Una bolsa significa un refresco: cualquier recurso que se mueva cambia el
## total compartido, asi que no hay nada que actualizar por separado.
func _refresh() -> void:
	var cap := ResourceManager.get_storage_cap()
	var total := ResourceManager.get_total_stored()
	var is_full := total >= cap

	for type in _chips:
		var amount := str(ResourceManager.get_amount(type))
		UITheme.chip_amount(_chips[type]).text = amount
		var res_id: String = _resource_ids[_resource_types.find(type)]
		(_chips[type] as Control).tooltip_text = Tr.t("HINT_HUD_RESOURCE") % [Tr.res_cap(res_id), amount]
		if _exp_labels.has(type):
			_exp_labels[type].text = amount

	# Rojo mientras la bolsa esta llena: desde aqui, lo producido se pierde.
	var tone: Color = UITheme.DANGER if is_full else UITheme.TEXT_DIM
	_storage_value.text = "%d/%d" % [total, cap]
	UITheme.set_label_color(_storage_value, tone)
	UITheme.set_pool_bar_alert(_pool_bar, is_full)

	for type in _segments:
		var seg_amt := ResourceManager.get_amount(type)
		_segments[type].visible = seg_amt > 0
		_segments[type].size_flags_stretch_ratio = maxf(0.001, float(seg_amt))
	var free := maxi(0, cap - total)
	_free_segment.visible = free > 0
	_free_segment.size_flags_stretch_ratio = maxf(0.001, float(free))

	var any_material := false
	for type in _mat_labels:
		var on: bool = ResourceManager.is_unlocked(type) or ResourceManager.get_amount(type) > 0
		var lbl: Label = _mat_labels[type]
		lbl.visible = on
		lbl.text = "%s %d" % [Tr.res_cap(ResourceManager.get_type_name(type)), ResourceManager.get_amount(type)]
		any_material = any_material or on
	_mat_row.visible = any_material
	_fit_row()

## Llega una senal por recurso (cuatro en un tick de consumo, una por coste al
## construir): se repinta una vez, al final del fotograma (docs/26 §6.9).
var _refresh_queued := false
func _on_resource_changed(_resource_type: String, _new_amount: int, _delta: int) -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	_refresh()

func _on_resource_unlocked(resource_name: String) -> void:
	# Un material nuevo: se ensena en el taller y se dice donde se fabrica.
	if ResourceManager.is_material_name(resource_name):
		_refresh()
		EventBus.notification_posted.emit(
			Tr.t("NOTIF_MATERIAL_UNLOCKED") % Tr.res_cap(resource_name), "notice", UITheme.INFO)
		return
	var type := _type_of(resource_name)
	if type < 0 or not _chips.has(type):
		return
	var chip: HBoxContainer = _chips[type]
	_set_chip_shown(chip, true)
	if _exp_rows.has(type):
		_exp_rows[type].visible = true
	# Destello al desbloquear: el jugador acaba de abrir una era y la fila
	# cambia de forma; sin aviso, el recurso nuevo aparece sin mas.
	chip.modulate = Color(2.5, 2.0, 0.5, 0.0)
	if chip.has_meta("unlock_tween"):
		var old: Tween = chip.get_meta("unlock_tween")
		if old != null and old.is_valid():
			old.kill()
	var tween := create_tween()
	chip.set_meta("unlock_tween", tween)
	tween.tween_property(chip, "modulate", Color(1.5, 1.3, 0.8, 1.0), 0.4)
	tween.tween_property(chip, "modulate", Color.WHITE, 1.0)
	_refresh()

## Falta un recurso: parpadea SU cifra y se avisa por el canal de mensajes.
## Antes era un texto flotante en el centro de la pantalla, encima del banner
## de la Tormenta y del objetivo; el aviso es efimero, pero tapaba.
func _on_insufficient(resource_type: String, required: int, available: int) -> void:
	var type := _type_of(resource_type)
	if type >= 0 and _chips.has(type):
		UITheme.flash_label(UITheme.chip_amount(_chips[type]), UITheme.TEXT_BRIGHT)
	EventBus.notification_posted.emit(
		Tr.t("FMT_NOT_ENOUGH_OF") % [Tr.res_name(resource_type), available, required],
		"warning", UITheme.WARNING)

## Desborde: la barra ya esta roja por _refresh; un parpadeo marca el momento
## exacto en que algo se ha perdido, que es lo que el jugador no veia.
## Con la bolsa llena llega en cada produccion: un parpadeo a la vez (antes se
## apilaban tweens que se pisaban la misma propiedad).
var _overflow_tween: Tween = null
func _on_overflow(_resource_type: String, _lost: int, _cap: int) -> void:
	_refresh()
	if _overflow_tween != null and _overflow_tween.is_valid():
		_overflow_tween.kill()
	_overflow_tween = create_tween()
	_overflow_tween.tween_property(_pool_bar, "modulate", Color(1.6, 1.2, 1.2, 1.0), 0.15)
	_overflow_tween.tween_property(_pool_bar, "modulate", Color.WHITE, 0.5)

func _type_of(resource_name: String) -> int:
	var idx := _resource_ids.find(resource_name)
	return int(_resource_types[idx]) if idx >= 0 else -1
