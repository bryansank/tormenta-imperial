extends CanvasLayer
## ENCARGOS: el tablon con los tres encargos (la Regencia, los vecinos y el
## contrabandista). Se abre desde ☰ MENU > COLONIA > ENCARGOS.
##
## Iconos y cifras antes que frases: cada tarjeta es
##   [Quien]                         3:20
##   ███████████░░░░  (plazo)
##   Piden  [madera] 60   (en rojo lo que falta)
##   Dan    [moral] +8 · [oro] +30 · Diezmo −10 %
##   [ ENTREGAR ]  [ No, gracias ]
## Quien es cada uno y que significa cada premio va en los tooltips (en tactil,
## mantener pulsado).
##
## El panel solo lee ContractManager y le llama (deliver/discard); no guarda
## estado del tablon.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const BoardScript := preload("res://scripts/economy/ContractBoard.gd")

## Tamano tactil de los botones (tablet a dedo).
const BTN_MIN := Vector2(170, 52)
const BTN_SMALL_MIN := Vector2(140, 52)
## Iconos de la fila de premios.
const ICON_PX := 24
## Cada cuanto se repintan los relojes con el panel abierto.
const TICK_EVERY := 0.25

var _panel: PanelContainer
var _backdrop: ColorRect
var _is_open := false
var _list: VBoxContainer
var _footer: Label
## source -> {"time": Label, "bar": ProgressBar} de las tarjetas con encargo.
var _clocks: Dictionary = {}
## source -> Label de "Otro encargo en 1:20" de las tarjetas vacias.
var _waits: Dictionary = {}
var _tick_left := 0.0
var _refresh_queued := false

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "ContractPanel.modal")
	EventBus.contract_board_changed.connect(_request_refresh)
	# Lo que entra o sale de la bolsa cambia lo que falta y si se puede entregar.
	EventBus.resource_changed.connect(func(_r, _a, _d): _request_refresh())
	EventBus.era_advanced.connect(func(_e): _request_refresh())
	EventBus.game_load_completed.connect(_request_refresh)
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
	UILayoutManager.apply_layout("ContractPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	var header := UITheme.make_panel_header(Tr.t("LBL_CONTRACTS_TITLE"), close)
	var title := header.get_child(0) as Label
	if title != null:
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		title.tooltip_text = Tr.t("LBL_CONTRACTS_HINT")
	vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "Cards"
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_footer = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_footer)

# ── Abrir y cerrar ───────────────────────────────────────────────────

func is_open() -> bool:
	return _is_open

func open() -> void:
	if _is_open:
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

## Las senales repintan solo con el panel abierto, y una vez por fotograma.
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
	if not _is_open:
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_EVERY
	_update_clocks()

## Rehace las tres tarjetas. Publico para los tests.
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_clocks.clear()
	_waits.clear()
	for source in BoardScript.SOURCES:
		_list.add_child(_make_card(source))
	_footer.text = Tr.t("LBL_CONTRACT_HARD") if GameMode.is_governor() else Tr.t("LBL_CONTRACT_EASY")
	_update_clocks()

func _update_clocks() -> void:
	for source in _clocks:
		var contract: Dictionary = ContractManager.get_contract(source)
		if contract.is_empty():
			continue
		var refs: Dictionary = _clocks[source]
		var frac: float = BoardScript.time_fraction(contract)
		(refs["time"] as Label).text = TextKit.short_time(float(contract.get("seconds_left", 0.0)))
		(refs["bar"] as ProgressBar).value = frac
	for source in _waits:
		var label := _waits[source] as Label
		label.text = _wait_text(source)

func _source_color(source: String) -> Color:
	match source:
		"regency":
			return UITheme.DANGER
		"neighbors":
			return UITheme.POSITIVE
	return UITheme.ACCENT

func _make_card(source: String) -> PanelContainer:
	var color := _source_color(source)
	var contract: Dictionary = ContractManager.get_contract(source)
	var card := PanelContainer.new()
	card.name = "Card_" + source
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG if not contract.is_empty() else UITheme.BTN_DISABLED
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(10)
	style.border_width_left = 6
	style.border_color = color
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	# Quien lo pide (y, en Gobernador, cuanto paga ahora) · reloj.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var who := UITheme.make_label(Tr.t(ContractManager.source_name_key(source)), "section", color)
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	who.tooltip_text = Tr.t(ContractManager.source_name_key(source) + "_TIP")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var rep: int = ContractManager.get_reputation(source)
	if GameMode.is_governor() and rep < 0:
		var pays := UITheme.make_label(Tr.t("LBL_CONTRACT_PAYS") % roundi(ContractManager.get_board().reward_mult(source) * 100.0),
			"small", UITheme.WARNING)
		pays.name = "Pays"
		pays.mouse_filter = Control.MOUSE_FILTER_PASS
		pays.tooltip_text = Tr.t("LBL_CONTRACT_PAYS_TIP")
		top.add_child(pays)
	box.add_child(top)

	if contract.is_empty():
		var wait := UITheme.make_label(_wait_text(source), "body", UITheme.TEXT_DIM)
		wait.name = "Wait"
		box.add_child(wait)
		_waits[source] = wait
		return card

	var time := UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	time.name = "Time"
	time.mouse_filter = Control.MOUSE_FILTER_PASS
	time.tooltip_text = Tr.t("LBL_CONTRACT_TIME_TIP")
	top.add_child(time)
	var bar := UITheme.make_progress_bar(color, 10)
	bar.name = "Clock"
	bar.max_value = 1.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(bar)
	_clocks[source] = {"time": time, "bar": bar}

	# Piden: en rojo lo que falta.
	var missing: Dictionary = ContractManager.missing_for(source)
	var ask_row := HBoxContainer.new()
	ask_row.name = "Ask"
	ask_row.add_theme_constant_override("separation", 10)
	ask_row.add_child(_row_label(Tr.t("LBL_CONTRACT_ASK")))
	var ask := TextKit.cost_inline(contract.get("ask", {}), missing, "body", UITheme.TEXT)
	ask.tooltip_text = Tr.t("LBL_CONTRACT_MISSING_TIP")
	ask_row.add_child(ask)
	box.add_child(ask_row)

	# Dan: el premio entero, a la vista.
	var give_row := HFlowContainer.new()
	give_row.name = "Give"
	give_row.add_theme_constant_override("h_separation", 12)
	give_row.add_child(_row_label(Tr.t("LBL_CONTRACT_GIVE")))
	_fill_reward(give_row, contract.get("reward", {}))
	box.add_child(give_row)

	# Botones a dedo.
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	var can: bool = ContractManager.can_deliver(source)
	var deliver := Button.new()
	deliver.name = "Deliver"
	deliver.text = Tr.t("BTN_CONTRACT_DELIVER")
	deliver.custom_minimum_size = BTN_MIN
	UITheme.style_button(deliver, UITheme.POSITIVE.darkened(0.2) if can else UITheme.BTN, UITheme.FONT_SECTION)
	deliver.disabled = not can
	if not can:
		deliver.tooltip_text = Tr.t("LBL_CONTRACT_MISSING_TIP")
	deliver.pressed.connect(func():
		if ContractManager.deliver(source):
			refresh()
	)
	buttons.add_child(deliver)
	var discard := Button.new()
	discard.name = "Discard"
	discard.text = Tr.t("BTN_CONTRACT_DISCARD")
	discard.custom_minimum_size = BTN_SMALL_MIN
	UITheme.style_button(discard, UITheme.BTN, UITheme.FONT_BODY)
	discard.pressed.connect(func():
		if ContractManager.discard(source):
			refresh()
	)
	buttons.add_child(discard)
	box.add_child(buttons)
	return card

func _row_label(text: String) -> Label:
	var label := UITheme.make_label(text, "small", UITheme.TEXT_DIM)
	label.custom_minimum_size.x = 70
	return label

## Premio: recursos con su icono (+cifra), moral y colonos con el suyo, la
## rebaja del Diezmo con su porcentaje.
func _fill_reward(row: Container, reward: Dictionary) -> void:
	var resources := {}
	for kind in reward:
		var amount: int = int(reward[kind])
		match String(kind):
			"morale":
				row.add_child(_icon_chip("morale", "+%d" % amount, Tr.t("LBL_CONTRACT_MORALE_TIP")))
			"colonists":
				row.add_child(_icon_chip("workers", "+%d" % amount, Tr.t("LBL_CONTRACT_PEOPLE_TIP")))
			"tithe_discount":
				var tithe := UITheme.make_label(Tr.t("LBL_CONTRACT_TITHE") % amount, "body", UITheme.POSITIVE)
				tithe.name = "Tithe"
				tithe.mouse_filter = Control.MOUSE_FILTER_PASS
				tithe.tooltip_text = Tr.t("LBL_CONTRACT_TITHE_TIP")
				row.add_child(tithe)
			_:
				resources[String(kind)] = amount
	if not resources.is_empty():
		row.add_child(TextKit.cost_inline(resources, {}, "body", UITheme.POSITIVE, "+"))

func _icon_chip(icon_id: String, text: String, tip: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.name = "Chip_" + icon_id
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = tip
	chip.add_child(UITheme.make_icon(icon_id, ICON_PX))
	chip.add_child(UITheme.make_label(text, "body", UITheme.POSITIVE))
	return chip

func _wait_text(source: String) -> String:
	if not ContractManager.is_source_open(source):
		return Tr.t("LBL_CONTRACT_LOCKED") % int(GameConfig.contract_source_era.get(source, 1))
	var left: float = ContractManager.seconds_until_next(source)
	if left <= 0.0:
		return Tr.t("LBL_CONTRACT_SOON")
	return Tr.t("LBL_CONTRACT_NEXT") % TextKit.short_time(left)
