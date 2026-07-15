extends CanvasLayer
## Market panel for buying/selling resources with gold.

var _panel: PanelContainer
var _backdrop: ColorRect
var _market_btn: Button
var _sidebar_toggle: Button
var _sidebar_visible := false
var _is_open := false
var _rows: Dictionary = {}

const TRADEABLE := ["wood", "steel", "oil"]

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "MarketPanel.modal")
	EventBus.market_prices_updated.connect(_on_prices_updated)
	EventBus.resource_unlocked.connect(func(_r): _rebuild())
	EventBus.market_trade_completed.connect(func(_r, _a, _b, _p): _update_prices())
	EventBus.phase_advanced.connect(_on_phase_advanced)
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

	# Sidebar toggle button (owned by MarketPanel, controls all right-side buttons)
	_sidebar_toggle = Button.new()
	_sidebar_toggle.text = "\u2630"  # ☰ hamburger
	_sidebar_toggle.custom_minimum_size = Vector2(36, 36)
	_sidebar_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sidebar_toggle.offset_left = -46
	_sidebar_toggle.offset_top = UILayoutManager.get_sidebar_button_offset("MarketPanel.sidebar_toggle")
	var stb := StyleBoxFlat.new()
	stb.bg_color = Color(0.08, 0.09, 0.07, 0.85)
	stb.set_corner_radius_all(4)
	stb.set_content_margin_all(4)
	stb.border_color = UITheme.ACCENT_DIM
	stb.set_border_width_all(2)
	_sidebar_toggle.add_theme_stylebox_override("normal", stb)
	var stb_h := stb.duplicate()
	stb_h.bg_color = Color(0.14, 0.15, 0.12, 0.9)
	stb_h.border_color = UITheme.ACCENT
	_sidebar_toggle.add_theme_stylebox_override("hover", stb_h)
	_sidebar_toggle.add_theme_stylebox_override("pressed", stb_h)
	_sidebar_toggle.add_theme_font_size_override("font_size", 16)
	_sidebar_toggle.add_theme_color_override("font_color", UITheme.ACCENT)
	_sidebar_toggle.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)
	_sidebar_toggle.pressed.connect(_toggle_sidebar)
	root.add_child(_sidebar_toggle)

	_market_btn = Button.new()
	_market_btn.text = Tr.t("BTN_MARKET")
	_market_btn.custom_minimum_size = Vector2(140, 38)
	_market_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_market_btn.offset_left = -152
	_market_btn.offset_top = UILayoutManager.get_sidebar_button_offset("MarketPanel.button")
	UITheme.style_card_button(_market_btn, UITheme.BTN.lightened(0.05), UITheme.POSITIVE)
	_market_btn.pressed.connect(_toggle_panel)
	_market_btn.visible = false  # Start collapsed
	root.add_child(_market_btn)
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)

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

	# Column headers
	var col_header := HBoxContainer.new()
	col_header.add_theme_constant_override("separation", 4)
	_add_col(col_header, Tr.t("LBL_RESOURCE"), 80)
	_add_col(col_header, Tr.t("LBL_BUY_PRICE"), 55)
	_add_col(col_header, Tr.t("LBL_SELL_PRICE"), 55)
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
	var gold_icon := ColorRect.new()
	gold_icon.custom_minimum_size = Vector2(12, 12)
	gold_icon.color = UITheme.RES_GOLD
	gold_row.add_child(gold_icon)
	var gold_label := UITheme.make_label(
		Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"body", UITheme.RES_GOLD
	)
	gold_label.name = "GoldLabel"
	gold_row.add_child(gold_label)
	vbox.add_child(gold_row)

func _add_resource_row(parent: VBoxContainer, res_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := UITheme.make_label(Tr.res_cap(res_name), "body", UITheme.TEXT)
	name_label.custom_minimum_size.x = 80
	row.add_child(name_label)

	var buy_label := UITheme.make_label(str(MarketManager.get_buy_price(res_name)), "body", UITheme.DANGER)
	buy_label.custom_minimum_size.x = 55
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(buy_label)

	var sell_label := UITheme.make_label(str(MarketManager.get_sell_price(res_name)), "body", UITheme.POSITIVE)
	sell_label.custom_minimum_size.x = 55
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(sell_label)

	var amount := 10
	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(minus_btn, UITheme.DANGER.darkened(0.3), UITheme.FONT_BODY)
	row.add_child(minus_btn)

	var amount_label := UITheme.make_label(str(amount), "body", UITheme.TEXT_BRIGHT)
	amount_label.custom_minimum_size.x = 30
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(amount_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(30, 30)
	UITheme.style_button(plus_btn, UITheme.POSITIVE.darkened(0.3), UITheme.FONT_BODY)
	row.add_child(plus_btn)

	var buy_btn := Button.new()
	buy_btn.text = Tr.t("BTN_BUY")
	buy_btn.custom_minimum_size = Vector2(60, 30)
	UITheme.style_button(buy_btn, UITheme.POSITIVE.darkened(0.2))
	row.add_child(buy_btn)

	var sell_btn := Button.new()
	sell_btn.text = Tr.t("BTN_SELL")
	sell_btn.custom_minimum_size = Vector2(60, 30)
	UITheme.style_button(sell_btn, UITheme.DANGER)
	row.add_child(sell_btn)

	_rows[res_name] = {"buy_price": buy_label, "sell_price": sell_label, "amount_label": amount_label, "amount": amount}

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
	var gold_label := _panel.find_child("GoldLabel", true, false)
	if gold_label:
		gold_label.text = Tr.t("LBL_YOUR_GOLD") % ResourceManager.get_amount(ResourceManager.Type.GOLD)

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

func _toggle_sidebar() -> void:
	_sidebar_visible = not _sidebar_visible
	_sidebar_toggle.text = "\u2715" if _sidebar_visible else "\u2630"  # ✕ / ☰
	EventBus.sidebar_toggled.emit(_sidebar_visible)

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	# Show market button only if sidebar visible AND phase allows it
	if ProgressionManager.current_phase >= GameConfig.Phase.ECONOMY:
		_market_btn.visible = visible
	else:
		_market_btn.visible = false

func _add_col(parent: HBoxContainer, text: String, min_w: float) -> void:
	var label := UITheme.make_label(text, "small", UITheme.TEXT_DIM)
	label.custom_minimum_size.x = min_w
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
