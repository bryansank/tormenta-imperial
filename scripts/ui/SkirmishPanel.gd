extends CanvasLayer
## Skirmish panel: where the player decides which troops to commit before the
## board opens. The whole point of this screen is the weight of the choice —
## what goes out can die out there, and Military Power back home is what pays
## for it.
##
## Shows the morale the expedition will be fought with, because morale is the
## bridge between the base and the battlefield and the player must see it before
## committing, not after losing.

const MILITARY := Color(0.8, 0.35, 0.25)  # matches UITheme.CAT_MILITARY

var _panel: PanelContainer
var _backdrop: ColorRect
var _skirmish_btn: Button
var _is_open := false
var _sidebar_visible := false

var _commit_label: Label
var _morale_label: Label
var _units_vbox: VBoxContainer
var _launch_btn: Button
var _dev_btn: Button
var _audit_btn: Button
var _empty_label: Label

## unit_id -> how many the player has picked for this run.
var _selection: Dictionary = {}

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "SkirmishPanel.modal")
	EventBus.army_changed.connect(_on_army_changed)
	EventBus.morale_changed.connect(_on_morale_changed)
	EventBus.building_placed.connect(func(_d, _c): _update_button_visibility())
	EventBus.building_demolished.connect(func(_n, _c): _update_button_visibility())
	EventBus.game_load_completed.connect(func(): _update_button_visibility())
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	EventBus.encounter_started.connect(_on_encounter_started)
	# El asedio final cambia lo que este panel ofrece: aparece "QUE BAJEN" y se
	# bloquea salir de expedicion mientras la guarnicion esta defendiendo.
	EventBus.final_audit_summoned.connect(func(_w, _s): _refresh())
	EventBus.final_audit_started.connect(func(_w): _refresh())
	EventBus.final_audit_lost.connect(func(_w): _refresh())
	EventBus.storm_halted_forever.connect(_refresh)
	_update_button_visibility()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_skirmish_btn = Button.new()
	_skirmish_btn.text = Tr.t("BTN_SKIRMISH")
	_skirmish_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_skirmish_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skirmish_btn.offset_left = -176
	_skirmish_btn.offset_top = UILayoutManager.get_sidebar_button_offset("SkirmishPanel.button")
	UITheme.style_card_button(_skirmish_btn, UITheme.BTN.lightened(0.05), MILITARY)
	_skirmish_btn.pressed.connect(_toggle_panel)
	_skirmish_btn.visible = false
	root.add_child(_skirmish_btn)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("SkirmishPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_SKIRMISH_TITLE"), _toggle_panel))

	_commit_label = UITheme.make_label("", "title", MILITARY)
	_commit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_commit_label)

	# Morale is stated up front: it is the number that decides who swings first.
	_morale_label = UITheme.make_label("", "small", UITheme.ACCENT)
	_morale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_morale_label)

	vbox.add_child(UITheme.make_separator())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_units_vbox)

	_empty_label = UITheme.make_label(Tr.t("MSG_NO_UNITS"), "small", UITheme.TEXT_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.visible = false
	vbox.add_child(_empty_label)

	vbox.add_child(UITheme.make_separator())

	_launch_btn = Button.new()
	_launch_btn.text = Tr.t("BTN_LAUNCH_EXPEDITION")
	_launch_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	UITheme.style_button(_launch_btn, MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_launch_btn.pressed.connect(_on_launch_pressed)
	vbox.add_child(_launch_btn)

	# Convocar la Auditoria Final es la ultima decision de la partida, y se toma
	# aqui, donde se decide pelear. No arranca sola: un asedio de varias oleadas
	# sin que el jugador lo pida seria quitarle justo esa decision.
	_audit_btn = Button.new()
	_audit_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	UITheme.style_button(_audit_btn, UITheme.DANGER, UITheme.FONT_BUTTON)
	_audit_btn.pressed.connect(_on_audit_pressed)
	_audit_btn.visible = false
	vbox.add_child(_audit_btn)

	_dev_btn = Button.new()
	_dev_btn.text = Tr.t("BTN_DEV_SKIRMISH")
	_dev_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(_dev_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_dev_btn.pressed.connect(func(): if CombatManager.dev_start_encounter(): _close())
	vbox.add_child(_dev_btn)

	_refresh()

# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _commit_label:
		return
	_prune_selection()
	var cap: int = GameConfig.combat_deploy_cap
	_commit_label.text = Tr.t("LBL_DEPLOY_CAP") % [_committed(), cap]

	var morale: float = _current_morale()
	_morale_label.text = Tr.t("LBL_MORALE_COMBAT") % [
		roundi(morale),
		CombatRules.morale_initiative_bonus(morale),
		CombatRules.morale_attack_mod(morale),
	]

	var available: Dictionary = CombatManager.get_deployable_units()
	_empty_label.visible = available.is_empty()
	var audit_active: bool = ProgressionManager.is_final_audit_active()
	# Con el asedio en marcha la guarnicion esta ocupada: no se sale de expedicion.
	_launch_btn.disabled = _committed() <= 0 or audit_active
	_dev_btn.visible = GameConfig.dev_mode
	_refresh_audit_button()
	_rebuild_units(available)

## Drops picks the player no longer owns (units lost, disbanded or spent).
func _prune_selection() -> void:
	var available: Dictionary = CombatManager.get_deployable_units()
	for unit_id in _selection.keys():
		var owned: int = int(available.get(unit_id, 0))
		_selection[unit_id] = mini(int(_selection[unit_id]), owned)

func _committed() -> int:
	var total := 0
	for count in _selection.values():
		total += int(count)
	return total

func _current_morale() -> float:
	if PopulationManager.has_method("get_morale"):
		return float(PopulationManager.get_morale())
	return 50.0

func _rebuild_units(available: Dictionary) -> void:
	for child in _units_vbox.get_children():
		child.queue_free()
	for unit_id in GameConfig.get_unit_ids():
		if int(available.get(unit_id, 0)) > 0:
			_units_vbox.add_child(_make_unit_row(unit_id, int(available[unit_id])))

func _make_unit_row(unit_id: String, owned: int) -> PanelContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var stats := GameConfig.get_combat_stats(unit_id)
	var picked: int = int(_selection.get(unit_id, 0))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_width_left = 5
	style.border_color = MILITARY if picked > 0 else UITheme.TEXT_DIM
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.add_child(UITheme.make_label(Tr.t(def.get("name", unit_id)), "section", UITheme.TEXT))
	title_row.add_child(UITheme.make_label(Tr.t("LBL_ARMY_OWNED") % owned, "small", UITheme.POSITIVE))
	info.add_child(title_row)

	# The combat stats, not the economic ones: this is a tactical decision.
	var line := "HP %d   ATK %d   DEF %d   MOV %d   ALC %d-%d" % [
		int(stats.get("hp", 0)), int(stats.get("atk", 0)), int(stats.get("def", 0)),
		int(stats.get("move", 0)), int(stats.get("min_range", 1)), int(stats.get("range", 1)),
	]
	info.add_child(UITheme.make_label(line, "small", UITheme.TEXT_DIM))

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(44, 44)
	UITheme.style_button(minus, UITheme.BTN, UITheme.FONT_SECTION)
	minus.disabled = picked <= 0
	minus.pressed.connect(func(): _adjust(unit_id, -1))
	row.add_child(minus)

	var count_label := UITheme.make_label(str(picked), "section", UITheme.TEXT_BRIGHT)
	count_label.custom_minimum_size.x = 28
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count_label)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(44, 44)
	UITheme.style_button(plus, UITheme.BTN, UITheme.FONT_SECTION)
	plus.disabled = picked >= owned or _committed() >= GameConfig.combat_deploy_cap
	plus.pressed.connect(func(): _adjust(unit_id, 1))
	row.add_child(plus)

	return card

func _adjust(unit_id: String, delta: int) -> void:
	var owned: int = int(CombatManager.get_deployable_units().get(unit_id, 0))
	var picked: int = int(_selection.get(unit_id, 0))
	var next: int = clampi(picked + delta, 0, owned)
	if delta > 0 and _committed() >= GameConfig.combat_deploy_cap:
		return
	_selection[unit_id] = next
	_refresh()

# ── Launch ───────────────────────────────────────────────────────────

## Visible solo cuando hay algo que convocar: la primera vez (pendiente) o tras
## perder, si el ejercito ya da para volver a llamarlos.
func _refresh_audit_button() -> void:
	if ProgressionManager.is_final_audit_pending():
		_audit_btn.text = Tr.t("BTN_AUDIT_BEGIN")
		_audit_btn.visible = true
		_audit_btn.disabled = false
	elif ProgressionManager.is_final_audit_lost():
		_audit_btn.text = Tr.t("BTN_AUDIT_RESUMMON")
		_audit_btn.visible = true
		_audit_btn.disabled = not ProgressionManager.can_resummon_final_audit()
	else:
		_audit_btn.visible = false

func _on_audit_pressed() -> void:
	var started: bool = false
	if ProgressionManager.is_final_audit_pending():
		started = ProgressionManager.begin_final_audit()
	elif ProgressionManager.is_final_audit_lost():
		started = ProgressionManager.resummon_final_audit() and ProgressionManager.begin_final_audit()
	if started:
		_close()
	else:
		_refresh()

func _on_launch_pressed() -> void:
	var party: Dictionary = {}
	for unit_id in _selection.keys():
		if int(_selection[unit_id]) > 0:
			party[unit_id] = int(_selection[unit_id])
	if party.is_empty():
		EventBus.notification_posted.emit(Tr.t("MSG_NO_UNITS"), "warning", UITheme.WARNING)
		return
	CombatManager.start_skirmish(party)

# ── Visibility / open-close ──────────────────────────────────────────

func _on_army_changed(_arg = null) -> void:
	if _is_open:
		_refresh()
	_update_button_visibility()

func _on_morale_changed(_value = null) -> void:
	if _is_open:
		_refresh()

func _on_encounter_started(_index: int, _is_boss: bool) -> void:
	# The board takes over: get out of its way.
	if _is_open:
		_close()

func _update_button_visibility() -> void:
	# Skirmishes unlock with the Barracks, same gate as the army itself.
	_skirmish_btn.visible = _sidebar_visible and ArmyManager.barracks_count() > 0

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_update_button_visibility()

func _toggle_panel() -> void:
	if _is_open:
		_close()
	else:
		_open()

func _open() -> void:
	_is_open = true
	_panel.visible = true
	_backdrop.visible = true
	_refresh()
	UIManager.open_panel(self)

func _close() -> void:
	_is_open = false
	_panel.visible = false
	_backdrop.visible = false
	UIManager.close_panel(self)
