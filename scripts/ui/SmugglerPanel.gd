extends CanvasLayer
## EL BARCO: las tres ofertas del contrabandista (feat/edificios-economia, doc 14
## §P4). Se abre tocando el barco atracado o con VER EL BARCO en la ficha del
## Puerto comercial. Sin barco, dice cuando llega el siguiente.
##
## No esta en Main.tscn ni en Main2D.tscn: se crea la primera vez que se pide
## (open_in) como hijo de la escena, igual en 3D y en 2D, y se queda alli.
##
## Iconos y cifras antes que frases; cada tarjeta es
##   Te vende   [repuestos] 3            por [oro] 180   [ TRATO HECHO ]
##   Te compra  [madera] 60              te da [oro] 230 [ TRATO HECHO ]
## y lo que falta sale en rojo. El panel solo lee EconomyManager y le llama
## (take_offer); no guarda nada del barco.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const BuildingIcon2D := preload("res://scripts/view2d/BuildingIcon2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")

const PANEL_ID := "SmugglerPanel.modal"
const NODE_NAME := "SmugglerPanel"
## Tope de la ventana en PC/tablet (en telefono, pantalla completa).
const MAX_SIZE := Vector2(720, 560)
## Cada cuanto se repinta el reloj con el panel abierto.
const TICK_EVERY := 0.25

var _win: Dictionary = {}
var _holder: Control
var _panel: Control
var _backdrop: ColorRect
var _is_open := false
var _list: VBoxContainer
var _clock: Label
var _footer: Label
var _tick_left := 0.0
var _refresh_queued := false

## Abre el panel de la escena actual (lo crea si aun no existe). Lo llaman los
## dos colocadores (toque en el barco) y la ficha del Puerto.
static func open_in(tree: SceneTree) -> CanvasLayer:
	if tree == null or tree.current_scene == null:
		return null
	var scene := tree.current_scene
	var panel := scene.get_node_or_null(NODE_NAME) as CanvasLayer
	if panel == null:
		panel = load("res://scripts/ui/SmugglerPanel.gd").new()
		panel.name = NODE_NAME
		scene.add_child(panel)
	panel.call("open")
	return panel

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, PANEL_ID)
	EventBus.economy_changed.connect(_request_refresh)
	EventBus.resource_changed.connect(func(_r, _a, _d): _request_refresh())
	get_viewport().size_changed.connect(func(): if _is_open: _fit())
	set_process(false)

## v1.2 (integracion, docs/28): ventana de CartoonTheme (cinta de laton, velo,
## X con el dodge del menu), el barco dibujado y su reloj arriba, una tarjeta
## por oferta con [icono] cifra y TRATO HECHO verde (gris con el porque).
func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_win = CT.modal_window(root, Tr.t("LBL_SMUGGLER_TITLE"), CT.sem("ACCENT"))
	_holder = _win["holder"]
	_holder.visible = false
	_backdrop = _win["veil"]
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	_panel = _win["panel"]
	_panel.name = "Modal"
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	(_win["close"] as Button).pressed.connect(close)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	(_win["ribbon"] as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	(_win["ribbon"] as Control).tooltip_text = Tr.t("LBL_SMUGGLER_HINT")
	var vbox: VBoxContainer = _win["body"]

	# El barco dibujado (la misma silueta que en el mapa 2D) y su reloj.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var ship := _ShipPicture.new()
	ship.custom_minimum_size = Vector2(90, 40) if CT.is_phone() else Vector2(120, 56)
	top.add_child(ship)
	_clock = CT.label("", "button", CT.text("window"))
	_clock.name = "Clock"
	_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_clock)
	vbox.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	DragScroll.attach.call_deferred(scroll)

	_list = VBoxContainer.new()
	_list.name = "Offers"
	_list.add_theme_constant_override("separation", 6 if CT.is_phone() else 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_footer = CT.label(Tr.t("LBL_SMUGGLER_FOOTER"), "small", CT.text("window", true))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_footer)
	_fit()

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _fit() -> void:
	CT.fit_window(_win, _vp(), MAX_SIZE)
	if _footer != null:
		_footer.visible = not CT.is_phone()

# ── Abrir y cerrar ───────────────────────────────────────────────────

func is_open() -> bool:
	return _is_open

func open() -> void:
	if _is_open:
		refresh()
		return
	_set_open(true)

func close() -> void:
	if not _is_open:
		return
	_set_open(false)

func toggle() -> void:
	_set_open(not _is_open)

## Lo llama UIManager (ESC, el boton atras, otra ventana en el mismo sitio).
func _close() -> void:
	close()

func _set_open(value: bool) -> void:
	_is_open = value
	_holder.visible = value
	set_process(value)
	if value:
		_fit()
		refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

# ── Repintar ─────────────────────────────────────────────────────────

func _request_refresh(_arg = null) -> void:
	if not _is_open or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if _is_open:
		refresh()

func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_EVERY
	_update_clock()

## Rehace las tarjetas. Publico para los tests.
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if EconomyManager.is_ship_docked():
		var offers: Array = EconomyManager.get_offers()
		for i in offers.size():
			_list.add_child(_make_card(i, offers[i]))
	else:
		var empty := CT.icon_line("anchor", Tr.t("LBL_SMUGGLER_EMPTY"), "", "window", "body")
		empty.name = "Empty"
		_list.add_child(empty)
	_update_clock()

func _update_clock() -> void:
	if EconomyManager.is_ship_docked():
		_clock.text = Tr.t("LBL_SMUGGLER_LEAVES") % TextKit.short_time(EconomyManager.ship_seconds_left())
		_clock.add_theme_color_override("font_color", CT.tone_color("warning") if EconomyManager.ship_seconds_left() < 20.0 else CT.text("window"))
		return
	_clock.remove_theme_color_override("font_color")
	var left: float = EconomyManager.seconds_until_ship()
	if left < 0.0:
		_clock.text = Tr.t("LBL_SMUGGLER_NO_PORT")
	elif left <= 0.0:
		_clock.text = Tr.t("LBL_SMUGGLER_SOON")
	else:
		_clock.text = Tr.t("LBL_SMUGGLER_NEXT") % TextKit.short_time(left)

func _make_card(index: int, offer: Dictionary) -> PanelContainer:
	var phone := CT.is_phone()
	var kind := String(offer.get("kind", ""))
	var sold := bool(offer.get("sold", false))
	var tone := "accent" if kind in ["parts", "plan"] else ("positive" if kind == "buy" else "info")
	var card := PanelContainer.new()
	card.name = "Offer_%d" % index
	var style := CT.card_style("window", false, CT.c("window", "CARD_ALT") if sold else Color(0, 0, 0, 0))
	style.set_content_margin_all(6 if phone else 10)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if phone else 12)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2 if phone else 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var what := CT.label(Tr.t("LBL_SMUGGLER_KIND_" + kind.to_upper()), "small", CT.tone_color(tone))
	what.mouse_filter = Control.MOUSE_FILTER_PASS
	what.tooltip_text = Tr.t("LBL_SMUGGLER_KIND_" + kind.to_upper() + "_TIP")
	info.add_child(what)

	var missing: Dictionary = {} if sold else EconomyManager.missing_for(index)
	var goods := HBoxContainer.new()
	goods.name = "Goods"
	goods.add_theme_constant_override("separation", 8)
	match kind:
		"plan":
			var id := String(offer.get("plan", ""))
			var data := Rules.load_building_data(id)
			if data != null:
				var icon: Control = BuildingIcon2D.new()
				icon.custom_minimum_size = Vector2(40, 40)
				icon.data = data
				goods.add_child(icon)
			var name_label := CT.label(Tr.t("LBL_SMUGGLER_PLAN_OF") % (data.get_display_name() if data != null else id), "body", CT.text("window"))
			name_label.mouse_filter = Control.MOUSE_FILTER_PASS
			name_label.tooltip_text = Tr.t("LBL_SMUGGLER_PLAN_TIP") % RankManager.building_rank(id)
			goods.add_child(name_label)
		"buy":
			goods.add_child(CT.cost_row(offer.get("ask", {}), missing))
		_:
			goods.add_child(CT.cost_row(offer.get("give", {}), {}, "+"))
	info.add_child(goods)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 6)
	if kind == "buy":
		price_row.add_child(CT.label(Tr.t("LBL_SMUGGLER_PAYS"), "small", CT.text("window", true)))
		price_row.add_child(CT.cost_row({"gold": int(offer.get("pay", 0))}, {}, "+"))
	else:
		price_row.add_child(CT.label(Tr.t("LBL_SMUGGLER_PRICE"), "small", CT.text("window", true)))
		price_row.add_child(CT.cost_row({"gold": int(offer.get("price", 0))}, missing))
	info.add_child(price_row)

	var take: Button
	if sold:
		take = CT.text_button(Tr.t("BTN_SMUGGLER_DONE"), "check", "disabled", 48 if phone else CT.BTN_SMALL)
		take.disabled = true
	else:
		var can: bool = EconomyManager.can_take(index)
		take = CT.text_button(Tr.t("BTN_SMUGGLER_TAKE"), "market", "primary" if can else "disabled", 48 if phone else CT.BTN_SMALL)
		take.disabled = not can
		if not can:
			take.tooltip_text = Tr.t("LBL_SMUGGLER_MISSING_TIP")
		take.pressed.connect(func():
			if EconomyManager.take_offer(index):
				refresh()
		)
	take.name = "Take"
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(take)
	return card

## La silueta del barco en la cabecera (la del mapa 2D, mirando a la derecha).
class _ShipPicture extends Control:
	const ArtRef := preload("res://scripts/view2d/BuildingArt2D.gd")

	func _draw() -> void:
		var length := minf(size.x, size.y * 2.4) * 0.92
		draw_set_transform(size * 0.5, 0.0, Vector2.ONE)
		ArtRef.draw_smuggler_ship(self, length)
