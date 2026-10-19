extends CanvasLayer
## EJERCITO (Cuartel, Astillero, Aerodromo): entrenar unidades, ver el Poder
## Militar, la tropa y la cola. El puente de la base al combate: una base mas
## grande saca un ejercito mas fuerte.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28): ventana crema de borde grueso
## con su cinta, pestanas Tierra / Mar / Aire, y cada unidad en una fila
##   [disco] Soldado ×3            [ficha] [+]
##           [oro] 40 [madera] 20  Poder 10  [reloj][oro] 1
## Icono + numero; lo que no se puede, gris con candado y el porque en 2-3
## palabras; el detalle (topes, sueldo, quien abre que) al mantener pulsado.
## Telefono primero: a pantalla completa, pestanas solo icono menos la elegida.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const RegimentCard := preload("res://scripts/ui/RegimentCard.gd")
const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const PlacementRulesScript := preload("res://scripts/buildings/PlacementRules.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const TrainingSectionScript := preload("res://scripts/ui/TrainingSection.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

## Tope de la ventana en PC (en telefono va a pantalla completa).
const MAX_SIZE := Vector2(980, 640)
const DOMAIN_GLYPH := {"land": "tank", "sea": "anchor", "air": "plane"}
const DOMAIN_TAB_KEY := {"land": "ARMY2_TAB_LAND", "sea": "ARMY2_TAB_SEA", "air": "ARMY2_TAB_AIR"}

## La ventana (velo + cinta + cuerpo). `_panel` es su caja, `_backdrop` el velo.
var _win: Dictionary = {}
var _holder: Control
var _panel: PanelContainer
var _backdrop: ColorRect
var _army_btn: Button
var _is_open := false
var _sidebar_visible := false

var _power_label: Label
var _capacity_label: Label
var _slots_label: Label
var _tabs_row: HBoxContainer
var _units_vbox: VBoxContainer
var _training_vbox: VBoxContainer
var _training_bars: Array = []  # ProgressBar refs, index-aligned with ArmyManager.get_training()
## Las fichas abiertas (boton de ficha): unit_id -> true. Se mantienen al rehacer.
var _cards_open: Dictionary = {}
## La pestana elegida ("land" / "sea" / "air"); "" = la primera con edificio.
var _tab := ""


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
	get_viewport().size_changed.connect(_on_viewport_resized)
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

	# Boton de la barra lateral vieja (☰). La barra de abajo abre el panel con open().
	_army_btn = Button.new()
	_army_btn.text = Tr.t("BTN_ARMY")
	_army_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_army_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_army_btn.offset_left = -176
	_army_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ArmyPanel.button")
	CT.style_pill(_army_btn, "open", CT.BTN_SMALL, "hud", "army")
	_army_btn.pressed.connect(_toggle_panel)
	_army_btn.visible = false
	root.add_child(_army_btn)

	_win = CT.modal_window(root, Tr.t("LBL_ARMY_TITLE"), CT.sem("POSITIVE"))
	_holder = _win["holder"]
	_holder.visible = false
	_backdrop = _win["veil"]
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	_panel = _win["panel"]
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	(_win["close"] as Button).pressed.connect(_toggle_panel)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	var body: VBoxContainer = _win["body"]

	# Fila de arriba: las pestanas a la izquierda y tres cifras a la derecha.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	_tabs_row = HBoxContainer.new()
	_tabs_row.name = "ArmyTabs"
	_tabs_row.add_theme_constant_override("separation", 6)
	top.add_child(_tabs_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	top.add_child(stats)
	_power_label = _summary_chip(stats, "army", Tr.t("ARMY2_POWER"))
	# De donde sale cada tope, al mantener pulsado.
	_capacity_label = _summary_chip(stats, "res:workers", Tr.t("ARMY2_TROOPS"))
	_capacity_label.tooltip_text = Tr.t("LBL_ARMY_CAPACITY_HINT") % [GameConfig.army_base_capacity,
		GameConfig.army_capacity_per_barracks, GameConfig.army_full_capacity_barracks,
		GameConfig.army_capacity_per_extra_barracks, GameConfig.army_capacity_max] \
		+ "\n" + Tr.t("LBL_ARMY_CAPACITY_FLEET_HINT") % [int(GameConfig.army_capacity_per_building.get("shipyard", 0)),
			int(GameConfig.army_capacity_per_building.get("aerodrome", 0))]
	_capacity_label.get_parent().tooltip_text = _capacity_label.tooltip_text
	_slots_label = _summary_chip(stats, "clock", Tr.t("ARMY2_QUEUE"))
	_slots_label.tooltip_text = Tr.t("LBL_ARMY_SLOTS_HINT") % GameConfig.army_training_slots_max
	_slots_label.get_parent().tooltip_text = _slots_label.tooltip_text

	# La lista de la pestana y, al final, la tarjeta REGIMIENTO (solo cosmetica).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_units_vbox)
	col.add_child(RegimentCard.new())

	# La cola de entrenamiento, abajo y solo si hay algo.
	_training_vbox = VBoxContainer.new()
	_training_vbox.name = "Training"
	_training_vbox.add_theme_constant_override("separation", 4)
	body.add_child(_training_vbox)

	_fit()
	_refresh()

## [icono] cifra, con el nombre al mantener pulsado. Devuelve la etiqueta.
func _summary_chip(parent: Container, glyph: String, caption: String) -> Label:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = caption
	var ic := CT.make_glyph(glyph, 24 if CT.phone else 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(ic)
	var l := CT.label("", "number", CT.text("window"))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(l)
	parent.add_child(chip)
	return l

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _fit() -> void:
	CT.fit_window(_win, _vp(), MAX_SIZE)

func _on_viewport_resized() -> void:
	_fit()
	if _is_open:
		_refresh()

# ── Refresh ──

func _refresh(_arg = null) -> void:
	if not _power_label:
		return
	var power: int = ArmyManager.get_power()
	_power_label.text = str(power)
	_power_label.get_parent().tooltip_text = Tr.t("LBL_MILITARY_POWER") % power
	_capacity_label.text = "%d/%d" % [ArmyManager.get_used_capacity(), ArmyManager.get_capacity()]
	_slots_label.text = "%d/%d" % [ArmyManager.get_training().size(), ArmyManager.max_slots()]
	_rebuild_tabs()
	_rebuild_units()
	_rebuild_training()

## Quien esta fuera, segun CombatManager: el panel no lleva su propia cuenta.
func _units_on_expedition() -> Dictionary:
	return CombatManager.get_units_on_expedition()

func _on_expedition_resumed(_expedition_id: int) -> void:
	_request_refresh()

# ── Pestanas Tierra / Mar / Aire ──

func _domain_of(building_id: String) -> String:
	return String(GameConfig.MILITARY_BUILDING_DOMAIN.get(building_id, "land"))

func _building_of(domain: String) -> String:
	for building_id in GameConfig.MILITARY_BUILDINGS:
		if _domain_of(String(building_id)) == domain:
			return String(building_id)
	return ""

func _building_name(building_id: String) -> String:
	var data: BuildingData = PlacementRulesScript.load_building_data(building_id)
	return data.get_display_name() if data != null else building_id

## La pestana elegida; sin elegir, la primera cuyo edificio este en pie.
func current_tab() -> String:
	if _tab != "":
		return _tab
	for building_id in GameConfig.MILITARY_BUILDINGS:
		if ArmyManager.building_count(String(building_id)) > 0:
			return _domain_of(String(building_id))
	return "land"

## Cambia de pestana. Publico para la barra de abajo y las pruebas.
func select_tab(domain: String) -> void:
	_tab = domain
	if _is_open or _power_label != null:
		_refresh()

func _rebuild_tabs() -> void:
	for child in _tabs_row.get_children():
		_tabs_row.remove_child(child)
		child.queue_free()
	var ph := CT.is_phone()
	var current := current_tab()
	for building_id in GameConfig.MILITARY_BUILDINGS:
		var domain := _domain_of(String(building_id))
		var sel := domain == current
		var count: int = ArmyManager.building_count(String(building_id))
		var glyph: String = DOMAIN_GLYPH.get(domain, "army") if count > 0 else "lock"
		var word := Tr.t(String(DOMAIN_TAB_KEY.get(domain, "ARMY2_TAB_LAND")))
		var t := CT.tab(word if (sel or not ph) else "", glyph, sel, "window",
			CT.sem("POSITIVE") if sel else Color(0, 0, 0, 0), 48 if ph else CT.BTN)
		t.name = "ArmyTab_" + domain
		if ph and not sel:
			t.custom_minimum_size.x = 56
		var bname := _building_name(String(building_id))
		if count > 0:
			t.tooltip_text = "%s · %s" % [word, Tr.t("LBL_DOMAIN_SLOTS") % [bname, count,
				ArmyManager.training_in(String(building_id)), ArmyManager.max_slots(String(building_id))]]
		else:
			t.tooltip_text = "%s · %s" % [word, Tr.t("LBL_DOMAIN_NEEDS") % Objectives.building_a(String(building_id))]
		t.pressed.connect(select_tab.bind(domain))
		_tabs_row.add_child(t)

# ── Filas de unidades ──

## Las filas de la pestana elegida. Sin el edificio, el candado dice que
## construir; las filas siguen ahi en gris (se ve lo que vendra).
func _rebuild_units() -> void:
	for child in _units_vbox.get_children():
		_units_vbox.remove_child(child)
		child.queue_free()
	var domain := current_tab()
	var building_id := _building_of(domain)
	if building_id == "":
		return
	if ArmyManager.building_count(building_id) <= 0:
		var lock := CT.icon_line("lock", Tr.t("LBL_DOMAIN_NEEDS") % Objectives.building_a(building_id), "warning", "window", "body")
		lock.name = "Domain_" + domain
		_units_vbox.add_child(lock)
	for unit_id in GameConfig.get_unit_ids():
		if GameConfig.get_unit_building(String(unit_id)) == building_id:
			_units_vbox.add_child(_make_unit_row(String(unit_id)))

## La fila de una unidad: la misma pieza que la ficha del Cuartel
## (TrainingSection.make_unit_row), con solo "+" en el boton de entrenar.
func _make_unit_row(unit_id: String) -> PanelContainer:
	return TrainingSectionScript.make_unit_row(unit_id, _cards_open.has(unit_id), false,
		toggle_unit_card.bind(unit_id), _refresh)

## Por que no se puede entrenar `unit_id` (vive en TrainingSection).
static func blocked_text(unit_id: String, reason: String) -> String:
	return TrainingSectionScript.blocked_text(unit_id, reason)

## Abre o cierra la ficha de `unit_id` en su fila. Si la unidad es de otra
## pestana, se pasa a la suya.
func toggle_unit_card(unit_id: String) -> void:
	if _cards_open.has(unit_id):
		_cards_open.erase(unit_id)
	else:
		_cards_open[unit_id] = true
		var domain := _domain_of(GameConfig.get_unit_building(unit_id))
		if domain != current_tab():
			_tab = domain
			_rebuild_tabs()
	_rebuild_units()

func is_unit_card_open(unit_id: String) -> bool:
	return _cards_open.has(unit_id)

# ── Cola de entrenamiento ──

func _rebuild_training() -> void:
	var training := ArmyManager.get_training()
	if training.is_empty():
		for child in _training_vbox.get_children():
			_training_vbox.remove_child(child)
			child.queue_free()
		_training_bars.clear()
		_training_vbox.visible = ArmyManager.get_total_units() == 0
		if _training_vbox.visible:
			_training_vbox.add_child(CT.icon_line("army", Tr.t("LBL_ARMY_EMPTY"), ""))
		return
	# La cola entera (todos los edificios), con las piezas de TrainingSection.
	_training_bars = TrainingSectionScript.fill_queue(_training_vbox, "", _refresh)
	_training_vbox.visible = true

func _update_training_progress() -> void:
	TrainingSectionScript.update_bars(_training_bars)

func _missing(cost: Dictionary) -> Dictionary:
	return TrainingSectionScript.missing(cost)

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
	_holder.visible = _is_open
	set_process(_is_open)
	if _is_open:
		_fit()
		_refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

## Lo abre la barra de abajo (y ☰). Si ya esta abierto, no lo cierra.
func open() -> void:
	if not _is_open:
		_toggle_panel()

func toggle() -> void:
	_toggle_panel()

func is_open() -> bool:
	return _is_open
