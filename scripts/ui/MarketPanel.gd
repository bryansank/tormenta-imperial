extends CanvasLayer
## El MERCADO (rediseno fase 2, docs/28-guia-ui.md): ventana crema con la cinta
## de laton. Arriba, tu oro ([oro] 1.240). Debajo, una fila de UNA linea por
## recurso: [icono] compra [oro] 12 · venta [oro] 8 · [−] 10 [+] · COMPRAR ·
## VENDER. Sin cabeceras de columna: cada precio lleva su palabra debajo en PC
## y al mantener pulsado en telefono.
##
## En Gobernador (GameMode.market_dynamic) cada fila ensena ademas el spread
## (compra - venta) y una flecha de tendencia (hacia donde va el precio segun el
## calendario de la Tormenta), y arriba la estacion del mercado.
##
## Se abre desde su edificio (BuildingInfoPanel, ABRIR MERCADO) o desde la barra
## de abajo (open()).

const CT := preload("res://scripts/ui/CartoonTheme.gd")

var _panel: Control
var _win: Dictionary = {}
var _backdrop: ColorRect
var _market_btn: Button
var _sidebar_visible := false
var _is_open := false
var _rows: Dictionary = {}
var _season_label: Label
var _phone := false
var _scroll: ScrollContainer
var _list: VBoxContainer

const TREND_SIZE := Vector2(18, 18)
var _gold_label: Label = null

const TRADEABLE := ["food", "wood", "steel", "oil"]

## Ancho de la ventana en PC (el alto lo pone el contenido).
const WINDOW_W := 760.0

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "MarketPanel.modal")
	EventBus.market_prices_updated.connect(_on_prices_updated)
	EventBus.resource_unlocked.connect(func(_r): _rebuild())
	EventBus.market_trade_completed.connect(func(_r, _a, _b, _p): _update_prices())
	EventBus.phase_advanced.connect(_on_phase_advanced)
	# La estacion del mercado (Gobernador) cambia con la Tormenta, no con el tick.
	EventBus.storm_phase_changed.connect(func(_p, _s): _on_prices_updated({}))
	EventBus.tithe_resolved.connect(func(_p, _t): _on_prices_updated({}))
	EventBus.resource_changed.connect(func(_t, _a, _d): _on_prices_updated({}))
	# Va aqui y no en _setup_ui: _rebuild() vuelve a llamar a _setup_ui.
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	UILayoutManager.layout_changed.connect(_fit_layout)
	get_viewport().size_changed.connect(_fit_layout)
	if ProgressionManager.current_phase < GameConfig.Phase.ECONOMY:
		_market_btn.visible = false

func _on_phase_advanced(new_phase: int) -> void:
	if new_phase >= GameConfig.Phase.ECONOMY and _sidebar_visible:
		_market_btn.visible = true

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _setup_ui() -> void:
	_phone = CT.is_phone()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# El boton lateral de la columna vieja: se conserva, oculto, por si algo lo
	# busca (el Mercado se abre desde su edificio y desde la barra de abajo).
	_market_btn = Button.new()
	_market_btn.text = Tr.t("BTN_MARKET")
	_market_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_market_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_market_btn.offset_left = -176
	_market_btn.offset_top = UILayoutManager.get_sidebar_button_offset("MarketPanel.button")
	UITheme.style_card_button(_market_btn, UITheme.BTN.lightened(0.05), UITheme.POSITIVE)
	_market_btn.pressed.connect(_toggle_panel)
	_market_btn.visible = false
	root.add_child(_market_btn)

	_backdrop = CT.veil()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_win = CT.window(Tr.t("UI2C_MARKET_TITLE"), CT.sem("ACCENT"))
	_panel = _win["root"]
	_panel.name = "MarketWindow"
	_panel.visible = false
	(_win["close"] as Button).pressed.connect(_toggle_panel)
	(_win["close"] as Button).tooltip_text = Tr.t("UI2C_CLOSE")
	(_win["panel"] as Control).gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self))
	root.add_child(_panel)

	var body: VBoxContainer = _win["body"]
	body.add_theme_constant_override("separation", 6 if _phone else 10)

	# Arriba: tu oro y, en Gobernador, la estacion.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	var gold_row := HBoxContainer.new()
	gold_row.name = "GoldRow"
	gold_row.add_theme_constant_override("separation", 6)
	gold_row.mouse_filter = Control.MOUSE_FILTER_PASS
	gold_row.tooltip_text = Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD)
	var gi := UITheme.make_icon("gold", 30 if not _phone else 24)
	gi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_row.add_child(gi)
	var gold_label := CT.label(str(ResourceManager.get_amount(ResourceManager.Type.GOLD)), "number", CT.text("window"))
	gold_label.name = "GoldLabel"
	gold_row.add_child(gold_label)
	top.add_child(gold_row)
	var dynamic := GameMode.market_dynamic()
	_season_label = null
	if dynamic:
		_season_label = CT.label("", "small", CT.text("window", true))
		_season_label.name = "SeasonLabel"
		_season_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_season_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_season_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_season_label.tooltip_text = Tr.t("TIP_MARKET_SEASON")
		top.add_child(_season_label)

	# Una fila por recurso, en un scroll (en telefono no caben las cuatro).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "MarketRows"
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_scroll = scroll
	_list = list
	for res_name in TRADEABLE:
		if ResourceManager.is_unlocked_by_name(res_name):
			_add_resource_row(list, res_name)
	_fit_layout()

## Un precio: [oro] 12 y, en PC, su palabra debajo ("compra", "venta").
func _price(value: int, caption: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = caption
	row.custom_minimum_size.x = 60 if _phone else 74
	var ic := UITheme.make_icon("gold", 20 if _phone else 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := CT.label(str(value), "number", CT.text("window"))
	col.add_child(l)
	if not _phone:
		col.add_child(CT.label(caption, "small", CT.text("window", true)))
	row.add_child(col)
	return {"box": row, "label": l}

func _add_resource_row(parent: VBoxContainer, res_name: String) -> void:
	var card := PanelContainer.new()
	card.name = "Row_" + res_name
	var cs := CT.card_style("window")
	cs.set_content_margin_all(4 if _phone else 8)
	card.add_theme_stylebox_override("panel", cs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6 if _phone else 10)
	# Telefono en vertical: precios arriba, [−] n [+] COMPRAR VENDER debajo
	# (en una fila no cabia y VENDER se salia por la derecha).
	var trade_row: HBoxContainer = row
	if CT.portrait():
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)
		card.add_child(stack)
		stack.add_child(row)
		trade_row = HBoxContainer.new()
		trade_row.alignment = BoxContainer.ALIGNMENT_END
		trade_row.add_theme_constant_override("separation", 6)
		stack.add_child(trade_row)
	else:
		card.add_child(row)

	# El recurso por su icono; su nombre, en el tooltip.
	var icon := UITheme.make_icon(res_name, 30 if _phone else 36)
	icon.name = "ResIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.tooltip_text = Tr.res_cap(res_name)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var buy := _price(MarketManager.get_buy_price(res_name), Tr.t("UI2C_MARKET_BUY_PRICE"))
	row.add_child(buy["box"])
	var sell := _price(MarketManager.get_sell_price(res_name), Tr.t("UI2C_MARKET_SELL_PRICE"))
	row.add_child(sell["box"])

	var spread_label: Label = null
	var trend: Control = null
	if GameMode.market_dynamic():
		spread_label = CT.label(str(MarketManager.get_spread(res_name)), "small", CT.text("window", true))
		spread_label.name = "Spread_%s" % res_name
		spread_label.custom_minimum_size.x = 28
		spread_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spread_label.mouse_filter = Control.MOUSE_FILTER_PASS
		spread_label.tooltip_text = Tr.t("TIP_MARKET_SPREAD")
		row.add_child(spread_label)
		trend = make_trend_arrow()
		trend.name = "Trend_%s" % res_name
		var trend_box := CenterContainer.new()
		trend_box.mouse_filter = Control.MOUSE_FILTER_PASS
		trend_box.tooltip_text = Tr.t("TIP_MARKET_TREND")
		trend_box.custom_minimum_size = Vector2(24, TREND_SIZE.y)
		trend_box.add_child(trend)
		row.add_child(trend_box)
		set_trend(trend, MarketManager.get_price_trend(res_name))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# [−] 10 [+]: de 5 en 5, entre 1 y 100.
	var amount := 10
	var minus_btn := CT.pill_button("", "minus", "secondary", 48)
	minus_btn.tooltip_text = "−5"
	trade_row.add_child(minus_btn)
	var amount_label := CT.label(str(amount), "number", CT.text("window"))
	amount_label.name = "Amount"
	amount_label.custom_minimum_size.x = 32
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trade_row.add_child(amount_label)
	var plus_btn := CT.pill_button("", "plus", "secondary", 48)
	plus_btn.tooltip_text = "+5"
	trade_row.add_child(plus_btn)

	var buy_btn := CT.text_pill(Tr.t("UI2C_BTN_BUY"), "primary", 48)
	buy_btn.name = "Buy"
	trade_row.add_child(buy_btn)
	var sell_btn := CT.text_pill(Tr.t("UI2C_BTN_SELL"), "accent", 48)
	sell_btn.name = "Sell"
	trade_row.add_child(sell_btn)

	_rows[res_name] = {"buy_price": buy["label"], "sell_price": sell["label"], "amount_label": amount_label, "amount": amount,
		"spread": spread_label, "trend": trend, "buy_btn": buy_btn, "sell_btn": sell_btn}

	minus_btn.pressed.connect(func():
		_rows[res_name]["amount"] = maxi(1, _rows[res_name]["amount"] - 5)
		amount_label.text = str(_rows[res_name]["amount"])
		_update_trade_buttons()
	)
	plus_btn.pressed.connect(func():
		_rows[res_name]["amount"] = mini(100, _rows[res_name]["amount"] + 5)
		amount_label.text = str(_rows[res_name]["amount"])
		_update_trade_buttons()
	)
	buy_btn.pressed.connect(func():
		MarketManager.buy(res_name, _rows[res_name]["amount"])
		_update_prices()
	)
	sell_btn.pressed.connect(func():
		MarketManager.sell(res_name, _rows[res_name]["amount"])
		_update_prices()
	)
	parent.add_child(card)

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_gold_label = null
	_setup_ui()
	if _is_open:
		_panel.visible = true
		_backdrop.visible = true
		_update_prices()

## Telefono: a pantalla completa. PC: centrada, del alto de su contenido.
func _fit_layout() -> void:
	if _panel == null or not is_instance_valid(_panel) or not is_inside_tree():
		return
	var vp := _vp()
	if CT.is_phone():
		if _scroll != null:
			_scroll.custom_minimum_size.y = 0.0
		CT.fit_fullscreen(_win)
	else:
		# El scroll no pide alto: en PC se le da el de las filas (caben todas).
		if _scroll != null and _list != null:
			_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, vp.y - 200.0)
		CT.place_center(_win, vp, Vector2(WINDOW_W, 0))

func _update_prices() -> void:
	for res_name in _rows:
		_rows[res_name]["buy_price"].text = str(MarketManager.get_buy_price(res_name))
		_rows[res_name]["sell_price"].text = str(MarketManager.get_sell_price(res_name))
		if _rows[res_name].get("spread") != null:
			_rows[res_name]["spread"].text = str(MarketManager.get_spread(res_name))
		if _rows[res_name].get("trend") != null:
			set_trend(_rows[res_name]["trend"], MarketManager.get_price_trend(res_name))
	if _season_label != null:
		_season_label.text = Tr.t("MARKET_SEASON_%s" % MarketManager.season().to_upper())
	if _gold_label == null or not is_instance_valid(_gold_label) or _gold_label.is_queued_for_deletion():
		_gold_label = _panel.find_child("GoldLabel", true, false) as Label
	var gold_label := _gold_label
	if gold_label:
		gold_label.text = str(ResourceManager.get_amount(ResourceManager.Type.GOLD))
		gold_label.get_parent().tooltip_text = Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD)
	_update_trade_buttons()

## COMPRAR y VENDER en gris cuando no alcanza (el oro o el recurso); el porque
## en su tooltip.
func _update_trade_buttons() -> void:
	var gold: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	for res_name in _rows:
		var r: Dictionary = _rows[res_name]
		var n: int = int(r["amount"])
		var buy_btn: Button = r.get("buy_btn")
		var sell_btn: Button = r.get("sell_btn")
		if buy_btn != null:
			var price: int = MarketManager.get_buy_price(res_name) * n
			buy_btn.disabled = gold < price
			var buy_tip := "%d → %d %s" % [price, n, Tr.res_name(res_name)]
			buy_btn.tooltip_text = Tr.t("UI2C_MARKET_NO_GOLD") if buy_btn.disabled else buy_tip
		if sell_btn != null:
			var have: int = ResourceManager.get_amount(ResourceManager.name_to_type(res_name))
			sell_btn.disabled = have < n
			var sell_tip := "%d %s → %d" % [n, Tr.res_name(res_name), MarketManager.get_sell_price(res_name) * n]
			sell_btn.tooltip_text = (Tr.t("UI2C_MARKET_NO_STOCK") % Tr.res_name(res_name)) if sell_btn.disabled else sell_tip

func _on_prices_updated(_prices: Dictionary) -> void:
	if _is_open:
		_update_prices()

## Abre el Mercado (barra de abajo, ficha del edificio).
func open() -> void:
	if not _is_open:
		_toggle_panel()

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_update_prices()
		_fit_layout()
		# El alto del contenido solo se sabe dentro del arbol y visible.
		_fit_layout.call_deferred()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	if ProgressionManager.current_phase >= GameConfig.Phase.ECONOMY:
		_market_btn.visible = is_visible
	else:
		_market_btn.visible = false

# ── Flecha de tendencia (Gobernador) ──
# Dibujada y no un caracter: las fuentes del juego no garantizan ▲▼ en Android.

## Un triangulo que apunta arriba (sube, rojo: comprar sale mas caro), abajo
## (baja, verde) o una barra (estable). La direccion va en el meta "trend".
static func make_trend_arrow() -> Control:
	var c := Control.new()
	c.custom_minimum_size = TREND_SIZE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("trend", 0)
	c.draw.connect(func():
		var w: float = c.size.x
		var h: float = c.size.y
		var dir: int = int(c.get_meta("trend", 0))
		if dir > 0:
			c.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 2), Vector2(w - 2, h - 3), Vector2(2, h - 3)]), CT.sem("DANGER"))
		elif dir < 0:
			c.draw_colored_polygon(PackedVector2Array([Vector2(2, 3), Vector2(w - 2, 3), Vector2(w * 0.5, h - 2)]), CT.sem("POSITIVE"))
		else:
			c.draw_rect(Rect2(3, h * 0.5 - 2, w - 6, 4), CT.text("window", true)))
	return c

static func set_trend(arrow: Control, trend: float) -> void:
	var dir: int = 1 if trend > 0.0 else (-1 if trend < 0.0 else 0)
	arrow.set_meta("trend", dir)
	arrow.queue_redraw()
