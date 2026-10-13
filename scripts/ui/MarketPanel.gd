extends CanvasLayer
## Market panel for buying/selling resources with gold.
##
## En Gobernador (GameMode.market_dynamic) ensena ademas el spread de cada
## recurso (compra - venta), una flecha de tendencia (hacia donde va el precio
## segun el calendario de la Tormenta) y la estacion del mercado. En Colono, el
## panel de siempre.

var _panel: PanelContainer
var _backdrop: ColorRect
var _market_btn: Button
var _sidebar_visible := false
var _is_open := false
var _rows: Dictionary = {}
var _season_label: Label

const TREND_SIZE := Vector2(18, 18)

const TRADEABLE := ["food", "wood", "steel", "oil"]

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
	# Va aqui y no en _setup_ui: _rebuild() vuelve a llamar a _setup_ui cada vez
	# que se desbloquea un recurso, y conectar dos veces la misma senal es error.
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	# Hide market button until Phase 2
	if ProgressionManager.current_phase < GameConfig.Phase.ECONOMY:
		_market_btn.visible = false

func _on_phase_advanced(new_phase: int) -> void:
	if new_phase >= GameConfig.Phase.ECONOMY and _sidebar_visible:
		_market_btn.visible = true

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# El boton ☰ que desplegaba la columna lateral ya no existe: el menu de la
	# partida (PauseMenu, "☰ MENU") es el unico y abre este panel desde COLONIA.
	# El boton lateral se conserva, oculto, por si algo lo busca.
	_market_btn = Button.new()
	_market_btn.text = Tr.t("BTN_MARKET")
	_market_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_market_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_market_btn.offset_left = -176
	_market_btn.offset_top = UILayoutManager.get_sidebar_button_offset("MarketPanel.button")
	UITheme.style_card_button(_market_btn, UITheme.BTN.lightened(0.05), UITheme.POSITIVE)
	_market_btn.pressed.connect(_toggle_panel)
	_market_btn.visible = false  # Start collapsed
	root.add_child(_market_btn)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("MarketPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_command_panel_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_MARKET_TITLE"), _toggle_panel))

	var dynamic := GameMode.market_dynamic()
	_season_label = null
	if dynamic:
		_season_label = UITheme.make_label("", "small", UITheme.ACCENT)
		_season_label.name = "SeasonLabel"
		_season_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_season_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_season_label.tooltip_text = Tr.t("TIP_MARKET_SEASON")
		vbox.add_child(_season_label)

	# Column headers. La de "Recurso" sobraba: cada fila lleva el icono del suyo.
	var col_header := HBoxContainer.new()
	col_header.add_theme_constant_override("separation", 4)
	_add_col(col_header, "", RES_COL_W)
	_add_col(col_header, Tr.t("LBL_BUY_PRICE"), 55)
	_add_col(col_header, Tr.t("LBL_SELL_PRICE"), 55)
	if dynamic:
		_add_col(col_header, Tr.t("LBL_MARKET_SPREAD"), 50)
		_add_col(col_header, Tr.t("LBL_MARKET_TREND"), 40)
	_add_col(col_header, "", 120)
	vbox.add_child(col_header)

	vbox.add_child(UITheme.make_separator())

	# Resource rows
	for res_name in TRADEABLE:
		if ResourceManager.is_unlocked_by_name(res_name):
			_add_resource_row(vbox, res_name)

	vbox.add_child(UITheme.make_separator())

	# Gold display
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 8)
	# Tu oro: el icono y la cifra, sin "Tu oro:" (el nombre va en el tooltip).
	gold_row.name = "GoldRow"
	gold_row.mouse_filter = Control.MOUSE_FILTER_PASS
	gold_row.tooltip_text = Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD)
	gold_row.add_child(UITheme.make_icon("gold"))
	var gold_label := UITheme.make_label(
		str(ResourceManager.get_amount(ResourceManager.Type.GOLD)), "body", UITheme.RES_GOLD
	)
	gold_label.name = "GoldLabel"
	gold_row.add_child(gold_label)
	vbox.add_child(gold_row)

## Ancho de la columna del recurso: el icono, no el nombre.
const RES_COL_W := 40.0

func _add_resource_row(parent: VBoxContainer, res_name: String) -> void:
	# Fila que se parte en dos si no cabe: con botones de tamano dedo, en un
	# movil en vertical (400 px) la fila entera no entraba y el panel se salia.
	var row := HFlowContainer.new()
	row.name = "Row_" + res_name
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 6)

	# El recurso por su icono; su nombre, en el tooltip.
	var icon := UITheme.make_icon(res_name, 28)
	icon.name = "ResIcon"
	icon.custom_minimum_size = Vector2(RES_COL_W, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.tooltip_text = Tr.res_cap(res_name)
	row.add_child(icon)

	var buy_label := UITheme.make_label(str(MarketManager.get_buy_price(res_name)), "body", UITheme.DANGER)
	buy_label.custom_minimum_size.x = 55
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(buy_label)

	var sell_label := UITheme.make_label(str(MarketManager.get_sell_price(res_name)), "body", UITheme.POSITIVE)
	sell_label.custom_minimum_size.x = 55
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(sell_label)

	var spread_label: Label = null
	var trend: Control = null
	if GameMode.market_dynamic():
		spread_label = UITheme.make_label(str(MarketManager.get_spread(res_name)), "body", UITheme.TEXT_DIM)
		spread_label.name = "Spread_%s" % res_name
		spread_label.custom_minimum_size.x = 50
		spread_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spread_label.mouse_filter = Control.MOUSE_FILTER_PASS
		spread_label.tooltip_text = Tr.t("TIP_MARKET_SPREAD")
		row.add_child(spread_label)
		trend = make_trend_arrow()
		trend.name = "Trend_%s" % res_name
		var trend_box := CenterContainer.new()
		trend_box.mouse_filter = Control.MOUSE_FILTER_PASS
		trend_box.tooltip_text = Tr.t("TIP_MARKET_TREND")
		trend_box.custom_minimum_size = Vector2(40, TREND_SIZE.y)
		trend_box.add_child(trend)
		row.add_child(trend_box)
		set_trend(trend, MarketManager.get_price_trend(res_name))

	var amount := 10
	var minus_btn := Button.new()
	minus_btn.text = "-"
	# Cuadrados de tamano dedo: con 30 px el pulgar acertaba el de al lado.
	minus_btn.custom_minimum_size = Vector2(UITheme.MIN_BTN_H, UITheme.MIN_BTN_H)
	UITheme.style_button(minus_btn, UITheme.DANGER.darkened(0.3), UITheme.FONT_BODY)
	row.add_child(minus_btn)

	var amount_label := UITheme.make_label(str(amount), "body", UITheme.TEXT_BRIGHT)
	amount_label.custom_minimum_size.x = 30
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(amount_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(UITheme.MIN_BTN_H, UITheme.MIN_BTN_H)
	UITheme.style_button(plus_btn, UITheme.POSITIVE.darkened(0.3), UITheme.FONT_BODY)
	row.add_child(plus_btn)

	var buy_btn := Button.new()
	buy_btn.text = Tr.t("BTN_BUY")
	buy_btn.custom_minimum_size = Vector2(60, UITheme.MIN_BTN_H)
	UITheme.style_button(buy_btn, UITheme.POSITIVE.darkened(0.2))
	row.add_child(buy_btn)

	var sell_btn := Button.new()
	sell_btn.text = Tr.t("BTN_SELL")
	sell_btn.custom_minimum_size = Vector2(60, UITheme.MIN_BTN_H)
	UITheme.style_button(sell_btn, UITheme.DANGER)
	row.add_child(sell_btn)

	_rows[res_name] = {"buy_price": buy_label, "sell_price": sell_label, "amount_label": amount_label, "amount": amount,
		"spread": spread_label, "trend": trend}

	minus_btn.pressed.connect(func():
		_rows[res_name]["amount"] = maxi(1, _rows[res_name]["amount"] - 5)
		amount_label.text = str(_rows[res_name]["amount"])
	)
	plus_btn.pressed.connect(func():
		_rows[res_name]["amount"] = mini(100, _rows[res_name]["amount"] + 5)
		amount_label.text = str(_rows[res_name]["amount"])
	)
	buy_btn.pressed.connect(func():
		MarketManager.buy(res_name, _rows[res_name]["amount"])
		_update_prices()
	)
	sell_btn.pressed.connect(func():
		MarketManager.sell(res_name, _rows[res_name]["amount"])
		_update_prices()
	)
	parent.add_child(row)

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rows.clear()
	_setup_ui()

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
	var gold_label := _panel.find_child("GoldLabel", true, false)
	if gold_label:
		gold_label.text = str(ResourceManager.get_amount(ResourceManager.Type.GOLD))
		gold_label.get_parent().tooltip_text = Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD)

func _on_prices_updated(_prices: Dictionary) -> void:
	if _is_open:
		_update_prices()

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_update_prices()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	# Show market button only if sidebar visible AND phase allows it
	if ProgressionManager.current_phase >= GameConfig.Phase.ECONOMY:
		# `is_visible` (el del menu), no `visible`: ese es el de la capa, que
		# siempre es true, y el boton se quedaba suelto al cerrar el menu.
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
			c.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 2), Vector2(w - 2, h - 3), Vector2(2, h - 3)]), UITheme.DANGER)
		elif dir < 0:
			c.draw_colored_polygon(PackedVector2Array([Vector2(2, 3), Vector2(w - 2, 3), Vector2(w * 0.5, h - 2)]), UITheme.POSITIVE)
		else:
			c.draw_rect(Rect2(3, h * 0.5 - 2, w - 6, 4), UITheme.TEXT_DIM))
	return c

static func set_trend(arrow: Control, trend: float) -> void:
	var dir: int = 1 if trend > 0.0 else (-1 if trend < 0.0 else 0)
	arrow.set_meta("trend", dir)
	arrow.queue_redraw()

func _add_col(parent: HBoxContainer, text: String, min_w: float) -> void:
	var label := UITheme.make_label(text, "small", UITheme.TEXT_DIM)
	label.custom_minimum_size.x = min_w
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
