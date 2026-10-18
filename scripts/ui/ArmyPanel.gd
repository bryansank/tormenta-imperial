extends CanvasLayer
## Army / Barracks panel: train units, see Military Power, capacity and upkeep.
## The management → combat bridge — a bigger base fields a stronger army.
##
## Menos texto (2026-10-04): "Tropa 5/11 · En cola 1/1", cada unidad con "×3" y
## su coste en iconos; de donde salen los topes y el sueldo, en tooltips.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const RegimentCard := preload("res://scripts/ui/RegimentCard.gd")
const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const NewGameDialogScript := preload("res://scripts/ui/NewGameDialog.gd")
const PlacementRulesScript := preload("res://scripts/buildings/PlacementRules.gd")

var _panel: PanelContainer
var _backdrop: ColorRect
var _army_btn: Button
var _is_open := false
var _sidebar_visible := false

var _power_label: Label
var _capacity_label: Label
var _slots_label: Label
var _units_vbox: VBoxContainer
var _training_vbox: VBoxContainer
var _training_bars: Array = []  # ProgressBar refs, index-aligned with ArmyManager.get_training()
## Las fichas abiertas (boton FICHA): unit_id -> true. Se mantienen al rehacer.
var _cards_open: Dictionary = {}


func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "ArmyPanel.modal")
	EventBus.army_changed.connect(_request_refresh)
	EventBus.era_advanced.connect(_on_era_advanced)
	EventBus.resource_unlocked.connect(_request_refresh)
	EventBus.building_placed.connect(func(_d, _c): _on_base_changed())
	EventBus.building_demolished.connect(func(_n, _c): _on_base_changed())
	EventBus.game_load_completed.connect(_on_base_changed)
	EventBus.army_upkeep_unpaid.connect(_on_upkeep_unpaid)
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	# Lo que esta fuera sigue contando en el ejercito pero no se puede entrenar
	# ni mandar a ningun otro sitio: el panel tiene que decirlo.
	EventBus.expedition_started.connect(func(_id, _nodes): _request_refresh())
	EventBus.expedition_ended.connect(func(_r, _rewards, _casualties): _request_refresh())
	EventBus.expedition_resumed.connect(_on_expedition_resumed)
	_update_button_visibility()
	# Por si la partida se cargo antes de que este panel escuchara.
	_on_base_changed.call_deferred()
	# Las barras de entrenamiento solo se mueven con el panel abierto.
	set_process(false)

## Las senales del ejercito rehacen las filas solo con el panel abierto (al
## abrirlo se rehacen de todos modos), y una vez por fotograma como mucho.
var _refresh_queued := false
func _request_refresh(_arg = null) -> void:
	if not _is_open or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if _is_open:
		_refresh()

func _process(_delta: float) -> void:
	if not _is_open:
		return
	_update_training_progress()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sidebar button (hamburger menu)
	_army_btn = Button.new()
	_army_btn.text = Tr.t("BTN_ARMY")
	_army_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_army_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_army_btn.offset_left = -176
	_army_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ArmyPanel.button")
	UITheme.style_card_button(_army_btn, UITheme.BTN.lightened(0.05), UITheme.CAT_MILITARY)
	_army_btn.pressed.connect(_toggle_panel)
	_army_btn.visible = false
	root.add_child(_army_btn)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	# Modal
	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ArmyPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_ARMY_TITLE"), _toggle_panel))

	# Summary
	_power_label = UITheme.make_label("", "title", UITheme.CAT_MILITARY)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_power_label)

	# Flow y no HBox: en un movil en vertical las dos cifras van una debajo de
	# otra en vez de empujar el panel fuera de la pantalla.
	var stats_row := HFlowContainer.new()
	stats_row.alignment = FlowContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("h_separation", 20)
	# "Tropa 5/11" y "En cola 1/1"; de donde sale cada tope, en el tooltip.
	_capacity_label = UITheme.make_label("", "body", UITheme.TEXT)
	_capacity_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_capacity_label.tooltip_text = Tr.t("LBL_ARMY_CAPACITY_HINT") % [GameConfig.army_base_capacity,
		GameConfig.army_capacity_per_barracks, GameConfig.army_full_capacity_barracks,
		GameConfig.army_capacity_per_extra_barracks, GameConfig.army_capacity_max] 		+ "
" + Tr.t("LBL_ARMY_CAPACITY_FLEET_HINT") % [int(GameConfig.army_capacity_per_building.get("shipyard", 0)),
			int(GameConfig.army_capacity_per_building.get("aerodrome", 0))]
	_slots_label = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	_slots_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_slots_label.tooltip_text = Tr.t("LBL_ARMY_SLOTS_HINT") % GameConfig.army_training_slots_max
	stats_row.add_child(_capacity_label)
	stats_row.add_child(_slots_label)
	vbox.add_child(stats_row)

	vbox.add_child(UITheme.make_separator())

	# Unit list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	# Arriba de la lista, la tarjeta REGIMIENTO (nombre, color, emblema,
	# pintura; solo cosmetica). Se gobierna sola: ver RegimentCard.gd.
	var scroll_col := VBoxContainer.new()
	scroll_col.add_theme_constant_override("separation", 6)
	scroll_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_col)
	scroll_col.add_child(RegimentCard.new())

	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_col.add_child(_units_vbox)

	vbox.add_child(UITheme.make_separator())

	# In-training section
	vbox.add_child(UITheme.make_label(Tr.t("LBL_ARMY_IN_TRAINING"), "section", UITheme.ACCENT))
	_training_vbox = VBoxContainer.new()
	_training_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(_training_vbox)

	_refresh()

# ── Refresh ──

func _refresh(_arg = null) -> void:
	if not _power_label:
		return
	_power_label.text = Tr.t("LBL_MILITARY_POWER") % ArmyManager.get_power()
	_capacity_label.text = Tr.t("LBL_ARMY_CAPACITY") % [ArmyManager.get_used_capacity(), ArmyManager.get_capacity()]
	_slots_label.text = Tr.t("LBL_ARMY_SLOTS") % [ArmyManager.get_training().size(), ArmyManager.max_slots()]
	_rebuild_units()
	_rebuild_training()

## Quien esta fuera, segun CombatManager: el panel no lleva su propia cuenta.
func _units_on_expedition() -> Dictionary:
	return CombatManager.get_units_on_expedition()

func _on_expedition_resumed(_expedition_id: int) -> void:
	_request_refresh()

## Aire y mar (2026-10-17): la lista va por medios, TIERRA (Cuartel), MAR
## (Astillero) y AIRE (Aerodromo), cada uno con su cabecera. Sin el edificio, la
## cabecera lleva un candado y dice que construir; las filas siguen ahi (se ve
## lo que vendra) con el motivo en rojo.
func _rebuild_units() -> void:
	for child in _units_vbox.get_children():
		child.queue_free()
	for building_id in GameConfig.MILITARY_BUILDINGS:
		var domain: String = String(GameConfig.MILITARY_BUILDING_DOMAIN.get(building_id, "land"))
		var ids: Array = []
		for unit_id in GameConfig.get_unit_ids():
			if GameConfig.get_unit_building(String(unit_id)) == building_id:
				ids.append(String(unit_id))
		if ids.is_empty():
			continue
		_units_vbox.add_child(_make_domain_header(String(building_id), domain))
		for unit_id in ids:
			_units_vbox.add_child(_make_unit_row(unit_id))

## "MAR · Astillero 1 · en cola 0/1", o con candado "MAR · Necesitas un Astillero".
func _make_domain_header(building_id: String, domain: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Domain_" + domain
	row.add_theme_constant_override("separation", 6)
	var count: int = ArmyManager.building_count(building_id)
	if count <= 0:
		row.add_child(NewGameDialogScript.make_lock_icon())
	var title := UITheme.make_label(Tr.t("LBL_DOMAIN_" + domain.to_upper()), "section", UITheme.ACCENT if count > 0 else UITheme.TEXT_DIM)
	row.add_child(title)
	var data: BuildingData = PlacementRulesScript.load_building_data(building_id)
	var building_name: String = data.get_display_name() if data != null else building_id
	var detail := ""
	if count > 0:
		detail = Tr.t("LBL_DOMAIN_SLOTS") % [building_name, count, ArmyManager.training_in(building_id), ArmyManager.max_slots(building_id)]
	else:
		detail = Tr.t("LBL_DOMAIN_NEEDS") % building_name
	var info := UITheme.make_label(detail, "small", UITheme.TEXT_DIM if count > 0 else UITheme.WARNING)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	return row

func _make_unit_row(unit_id: String) -> PanelContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var unlocked := ArmyManager.is_unlocked(unit_id) \
		and ArmyManager.building_count(GameConfig.get_unit_building(unit_id)) > 0

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG if unlocked else UITheme.BTN_DISABLED
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_width_left = 5
	style.border_color = UITheme.CAT_MILITARY if unlocked else UITheme.TEXT_DIM
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	# Left: name + stats
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	# Nombre y "×3" (cuantas tienes). El nivel de era sobraba: si la era no
	# llega, el motivo lo dice debajo.
	var title_row := HFlowContainer.new()
	title_row.add_theme_constant_override("h_separation", 8)
	var name_label := UITheme.make_label(Tr.t(def.get("name", unit_id)), "section", UITheme.TEXT if unlocked else UITheme.TEXT_DIM)
	title_row.add_child(name_label)
	var owned_label := UITheme.make_label(Tr.t("LBL_ARMY_OWNED") % ArmyManager.get_count(unit_id), "section", UITheme.POSITIVE)
	owned_label.name = "Owned"
	title_row.add_child(owned_label)
	var on_campaign: int = int(_units_on_expedition().get(unit_id, 0))
	if on_campaign > 0:
		title_row.add_child(UITheme.make_label(Tr.t("LBL_ON_CAMPAIGN") % on_campaign, "small", UITheme.WARNING))
	info.add_child(title_row)

	# Coste en iconos (en rojo lo que falta), poder y sueldo: [oro] 40 [madera] 20 · Poder 10 · Sueldo [oro] 1
	var stats := HFlowContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("h_separation", 8)
	var cost: Dictionary = def.get("cost", {})
	stats.add_child(TextKit.cost_inline(cost, _missing(cost), "small", UITheme.TEXT_DIM))
	stats.add_child(UITheme.make_label(Tr.t("LBL_ARMY_POWER_EACH") % int(def.get("power", 0)), "small", UITheme.TEXT_DIM))
	var upkeep := UITheme.make_label(Tr.t("LBL_ARMY_UPKEEP_SHORT"), "small", UITheme.TEXT_DIM)
	upkeep.mouse_filter = Control.MOUSE_FILTER_PASS
	upkeep.tooltip_text = Tr.t("LBL_ARMY_UPKEEP_HINT") % int(GameConfig.army_upkeep_interval)
	stats.add_child(upkeep)
	var upkeep_row := TextKit.cost_inline({"gold": int(def.get("upkeep_gold", 0))}, {}, "small", UITheme.TEXT_DIM)
	upkeep_row.name = "Upkeep"
	stats.add_child(upkeep_row)
	info.add_child(stats)

	# La ficha de la unidad (docs/15 §3, "Ensenar el combate"): la misma que en el
	# tablero, sin vida actual. Se abre y se cierra en la propia fila.
	if _cards_open.has(unit_id):
		var unit_card = UnitCardScript.new()
		unit_card.setup(unit_id, null, false)
		info.add_child(unit_card)

	# Right: ficha + train button
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	row.add_child(buttons)
	var card_btn := Button.new()
	card_btn.name = "CardButton"
	card_btn.text = Tr.t("BTN_UNIT_CARD_HIDE") if _cards_open.has(unit_id) else Tr.t("BTN_UNIT_CARD")
	card_btn.tooltip_text = Tr.t("LBL_UNIT_CARD_TIP")
	card_btn.custom_minimum_size = Vector2(96, 36)
	UITheme.style_button(card_btn, UITheme.BTN, UITheme.FONT_SMALL)
	card_btn.pressed.connect(func():
		toggle_unit_card(unit_id)
	)
	buttons.add_child(card_btn)
	var check := ArmyManager.can_train(unit_id)
	# Por que no se puede entrenar, a la vista: antes solo iba en el tooltip, y
	# en movil no hay raton que se pose encima para leerlo.
	if not check["ok"] and check["reason"] != "":
		var why := UITheme.make_label(blocked_text(unit_id, String(check["reason"])), "small", UITheme.WARNING)
		why.name = "BlockedReason"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(why)
	var train_btn := Button.new()
	train_btn.text = Tr.t("BTN_TRAIN")
	train_btn.custom_minimum_size = Vector2(96, 40)
	UITheme.style_button(train_btn, UITheme.CAT_MILITARY.darkened(0.15) if check["ok"] else UITheme.BTN, UITheme.FONT_BODY)
	train_btn.disabled = not check["ok"]
	if not check["ok"] and check["reason"] != "":
		train_btn.tooltip_text = blocked_text(unit_id, String(check["reason"]))
	train_btn.pressed.connect(func():
		if ArmyManager.train(unit_id):
			_refresh()
	)
	buttons.add_child(train_btn)

	return card

## Por que no se puede entrenar `unit_id`, en palabras. Una unidad de otra era
## dice cual y que la abre (cuartel temprano, 2026-10-17: con el Cuartel en la
## era 1 la Artilleria y el Tanque salen apagados desde el principio, y
## "era superior" no le decia a nadie que hacer). Sin estado, para las pruebas.
static func blocked_text(unit_id: String, reason: String) -> String:
	if reason == "LBL_ARMY_LOCKED":
		var era: int = int(GameConfig.get_unit_def(unit_id).get("era", 1))
		var key := "LBL_ARMY_LOCKED_ERA_%d" % era
		if Tr.t(key) != key:
			return Tr.t(key)
	return Tr.t(reason)

## Abre o cierra la ficha de `unit_id` en su fila.
func toggle_unit_card(unit_id: String) -> void:
	if _cards_open.has(unit_id):
		_cards_open.erase(unit_id)
	else:
		_cards_open[unit_id] = true
	_rebuild_units()

func is_unit_card_open(unit_id: String) -> bool:
	return _cards_open.has(unit_id)

func _rebuild_training() -> void:
	for child in _training_vbox.get_children():
		child.queue_free()
	_training_bars.clear()
	var training := ArmyManager.get_training()
	if training.is_empty():
		var empty := UITheme.make_label(Tr.t("LBL_ARMY_EMPTY") if ArmyManager.get_total_units() == 0 else "—", "small", UITheme.TEXT_DIM)
		_training_vbox.add_child(empty)
		return
	for i in range(training.size()):
		var item: Dictionary = training[i]
		var def := GameConfig.get_unit_def(item["id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := UITheme.make_label(Tr.t(def.get("name", item["id"])), "small", UITheme.TEXT)
		name_label.custom_minimum_size.x = 130
		line.add_child(name_label)
		var bar := UITheme.make_progress_bar(UITheme.CAT_MILITARY, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = _training_progress(item)
		line.add_child(bar)
		line.add_child(_make_cancel_button(i))
		_training_vbox.add_child(line)
		_training_bars.append(bar)

## Cancelar un entrenamiento, diciendo en el propio boton cuanto vuelve.
## Entrenar era irreversible: pulsar ENTRENAR por error costaba la unidad entera.
func _make_cancel_button(index: int) -> Button:
	var refund := ArmyManager.get_training_refund(index)
	var btn := Button.new()
	if refund.is_empty():
		btn.text = Tr.t("LBL_CANCEL_NO_REFUND")
	else:
		btn.text = Tr.t("FMT_CANCEL_REFUND") % TextKit.cost_text(refund)
	# En rojo cuando la Tormenta se esta cobrando su parte de la cancelacion.
	var stormy := GameConfig.get_cancel_refund_ratio() < GameConfig.cancel_refund_ratio
	UITheme.style_button(btn, UITheme.DANGER.darkened(0.2) if stormy else UITheme.BTN, UITheme.FONT_SMALL)
	btn.pressed.connect(func():
		ArmyManager.cancel_training(index)
		_refresh()
	)
	return btn

func _update_training_progress() -> void:
	var training := ArmyManager.get_training()
	for i in range(mini(_training_bars.size(), training.size())):
		_training_bars[i].value = _training_progress(training[i])

func _training_progress(item: Dictionary) -> float:
	var dur: float = item.get("duration", 1.0)
	if dur <= 0.0:
		return 1.0
	return clampf(1.0 - (item.get("remaining", 0.0) / dur), 0.0, 1.0)

## Lo que falta para pagar `cost` (por nombre de recurso).
func _missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for res_name in cost:
		var type: int = ResourceManager.name_to_type(String(res_name))
		if type < 0:
			continue
		var short: int = int(cost[res_name]) - ResourceManager.get_amount(type)
		if short > 0:
			out[res_name] = short
	return out

# ── Visibility / open-close ──

func _on_era_advanced(_new_era: int) -> void:
	_request_refresh()
	_update_button_visibility()

func _on_base_changed(_arg = null) -> void:
	_update_button_visibility()
	if _is_open:
		_refresh()

func _update_button_visibility() -> void:
	# Army button appears in the sidebar once a Barracks exists.
	_army_btn.visible = _sidebar_visible and ArmyManager.has_military_building()

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_update_button_visibility()

func _on_upkeep_unpaid(gold_short: int) -> void:
	EventBus.notification_posted.emit(Tr.t("NOTIF_UPKEEP_UNPAID") % gold_short, "danger", UITheme.DANGER)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	set_process(_is_open)
	if _is_open:
		_refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
