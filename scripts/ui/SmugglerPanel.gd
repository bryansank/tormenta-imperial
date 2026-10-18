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

const PANEL_ID := "SmugglerPanel.modal"
const NODE_NAME := "SmugglerPanel"
const BTN_MIN := Vector2(170, 52)
## Cada cuanto se repinta el reloj con el panel abierto.
const TICK_EVERY := 0.25

var _panel: PanelContainer
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
	set_process(false)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.name = "Modal"
	UILayoutManager.apply_layout(PANEL_ID, _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	var header := UITheme.make_panel_header(Tr.t("LBL_SMUGGLER_TITLE"), close)
	var title := header.get_child(0) as Label
	if title != null:
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		title.tooltip_text = Tr.t("LBL_SMUGGLER_HINT")
	vbox.add_child(header)

	# El barco dibujado (la misma silueta que en el mapa 2D) y su reloj.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var ship := _ShipPicture.new()
	ship.custom_minimum_size = Vector2(120, 56)
	top.add_child(ship)
	_clock = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_clock.name = "Clock"
	_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_clock)
	vbox.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "Offers"
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_footer = UITheme.make_label(Tr.t("LBL_SMUGGLER_FOOTER"), "small", UITheme.TEXT_DIM)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_footer)

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
	_panel.visible = value
	_backdrop.visible = value
	set_process(value)
	if value:
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
		var empty := UITheme.make_label(Tr.t("LBL_SMUGGLER_EMPTY"), "body", UITheme.TEXT_DIM)
		empty.name = "Empty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	_update_clock()

func _update_clock() -> void:
	if EconomyManager.is_ship_docked():
		_clock.text = Tr.t("LBL_SMUGGLER_LEAVES") % TextKit.short_time(EconomyManager.ship_seconds_left())
		_clock.add_theme_color_override("font_color", UITheme.WARNING if EconomyManager.ship_seconds_left() < 20.0 else UITheme.TEXT_BRIGHT)
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
	var kind := String(offer.get("kind", ""))
	var sold := bool(offer.get("sold", false))
	var color := UITheme.ACCENT if kind in ["parts", "plan"] else (UITheme.POSITIVE if kind == "buy" else UITheme.INFO)
	var card := PanelContainer.new()
	card.name = "Offer_%d" % index
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.BTN_DISABLED if sold else UITheme.CARD_BG
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(10)
	style.border_width_left = 6
	style.border_color = color
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var what := UITheme.make_label(Tr.t("LBL_SMUGGLER_KIND_" + kind.to_upper()), "small", color)
	what.mouse_filter = Control.MOUSE_FILTER_PASS
	what.tooltip_text = Tr.t("LBL_SMUGGLER_KIND_" + kind.to_upper() + "_TIP")
	info.add_child(what)

	var missing: Dictionary = {} if sold else EconomyManager.missing_for(index)
	var goods := HBoxContainer.new()
	goods.name = "Goods"
	goods.add_theme_constant_override("separation", 10)
	match kind:
		"plan":
			var id := String(offer.get("plan", ""))
			var data := Rules.load_building_data(id)
			if data != null:
				var icon: Control = BuildingIcon2D.new()
				icon.custom_minimum_size = Vector2(44, 44)
				icon.data = data
				goods.add_child(icon)
			var name_label := UITheme.make_label(Tr.t("LBL_SMUGGLER_PLAN_OF") % (data.get_display_name() if data != null else id), "body", UITheme.TEXT)
			name_label.mouse_filter = Control.MOUSE_FILTER_PASS
			name_label.tooltip_text = Tr.t("LBL_SMUGGLER_PLAN_TIP") % RankManager.building_rank(id)
			goods.add_child(name_label)
		"buy":
			goods.add_child(TextKit.cost_inline(offer.get("ask", {}), missing, "body", UITheme.TEXT))
		_:
			goods.add_child(TextKit.cost_inline(offer.get("give", {}), {}, "body", UITheme.POSITIVE, "+"))
	info.add_child(goods)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	if kind == "buy":
		price_row.add_child(UITheme.make_label(Tr.t("LBL_SMUGGLER_PAYS"), "small", UITheme.TEXT_DIM))
		price_row.add_child(TextKit.cost_inline({"gold": int(offer.get("pay", 0))}, {}, "body", UITheme.POSITIVE, "+"))
	else:
		price_row.add_child(UITheme.make_label(Tr.t("LBL_SMUGGLER_PRICE"), "small", UITheme.TEXT_DIM))
		price_row.add_child(TextKit.cost_inline({"gold": int(offer.get("price", 0))}, missing, "body", UITheme.TEXT))
	info.add_child(price_row)

	var take := Button.new()
	take.name = "Take"
	take.custom_minimum_size = BTN_MIN
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if sold:
		take.text = Tr.t("BTN_SMUGGLER_DONE")
		take.disabled = true
		UITheme.style_button(take, UITheme.BTN, UITheme.FONT_BODY)
	else:
		var can: bool = EconomyManager.can_take(index)
		take.text = Tr.t("BTN_SMUGGLER_TAKE")
		take.disabled = not can
		if not can:
			take.tooltip_text = Tr.t("LBL_SMUGGLER_MISSING_TIP")
		UITheme.style_button(take, UITheme.POSITIVE.darkened(0.2) if can else UITheme.BTN, UITheme.FONT_SECTION)
		take.pressed.connect(func():
			if EconomyManager.take_offer(index):
				refresh()
		)
	row.add_child(take)
	return card

## La silueta del barco en la cabecera (la del mapa 2D, mirando a la derecha).
class _ShipPicture extends Control:
	const ArtRef := preload("res://scripts/view2d/BuildingArt2D.gd")

	func _draw() -> void:
		var length := minf(size.x, size.y * 2.4) * 0.92
		draw_set_transform(size * 0.5, 0.0, Vector2.ONE)
		ArtRef.draw_smuggler_ship(self, length)
