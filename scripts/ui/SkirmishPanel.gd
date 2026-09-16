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
var _units_scroll: ScrollContainer
var _units_vbox: VBoxContainer
var _launch_btn: Button
var _reason_label: Label
var _dev_btn: Button
var _audit_btn: Button
var _empty_label: Label

## Lo que se ve en lugar del selector mientras la columna esta fuera.
var _campaign_box: VBoxContainer
var _campaign_status: Label
var _campaign_party: Label
var _map_btn: Button

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
	# Con la columna fuera, este panel deja de ser un selector y pasa a ser el
	# parte de la campana: lo que hay que refrescar es lo mismo, lo que se pinta no.
	EventBus.expedition_started.connect(func(_id, _nodes): _on_expedition_changed())
	EventBus.expedition_node_selected.connect(func(_index): _on_expedition_changed())
	EventBus.expedition_ended.connect(func(_r, _rewards, _casualties): _on_expedition_changed())
	EventBus.expedition_resumed.connect(_on_expedition_resumed)
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

	_units_scroll = ScrollContainer.new()
	_units_scroll.custom_minimum_size = Vector2(0, 240)
	_units_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_units_scroll)

	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_units_scroll.add_child(_units_vbox)

	_empty_label = UITheme.make_label(Tr.t("MSG_NO_UNITS"), "small", UITheme.TEXT_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.visible = false
	vbox.add_child(_empty_label)

	# Con la expedicion en marcha no hay nada que elegir: lo unico util es saber
	# por donde va la columna y poder volver al mapa.
	_campaign_box = VBoxContainer.new()
	_campaign_box.add_theme_constant_override("separation", 6)
	_campaign_box.visible = false
	vbox.add_child(_campaign_box)

	_campaign_status = UITheme.make_label("", "section", UITheme.ACCENT)
	_campaign_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_campaign_box.add_child(_campaign_status)

	_campaign_party = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_campaign_party.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_campaign_party.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_campaign_box.add_child(_campaign_party)

	_map_btn = Button.new()
	_map_btn.text = Tr.t("BTN_VIEW_MAP")
	_map_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(_map_btn, MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_map_btn.pressed.connect(_on_view_map_pressed)
	_campaign_box.add_child(_map_btn)

	vbox.add_child(UITheme.make_separator())

	_launch_btn = Button.new()
	_launch_btn.text = Tr.t("BTN_LAUNCH_EXPEDITION")
	_launch_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	UITheme.style_button(_launch_btn, MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_launch_btn.pressed.connect(_on_launch_pressed)
	vbox.add_child(_launch_btn)

	# Un boton apagado sin motivo es un bug a ojos del jugador. El motivo va
	# debajo, escrito, siempre que `can_launch` diga que no.
	_reason_label = UITheme.make_label("", "small", UITheme.WARNING)
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason_label.visible = false
	vbox.add_child(_reason_label)

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
	var on_campaign: bool = has_expedition()

	_commit_label.text = Tr.t("LBL_EXPEDITION_ACTIVE") if on_campaign \
		else Tr.t("LBL_DEPLOY_CAP") % [_committed(), cap]

	# La moral con la que se pelea es la que tenia el pueblo cuando la columna
	# salio, no la de ahora: con expedicion en curso se muestra esa.
	var morale: float = _current_morale()
	_morale_label.text = Tr.t("LBL_MORALE_COMBAT") % [
		roundi(morale),
		CombatRules.morale_initiative_bonus(morale),
		CombatRules.morale_attack_mod(morale),
	]

	_refresh_audit_button()
	_dev_btn.visible = GameConfig.dev_mode and not on_campaign

	if on_campaign:
		_units_scroll.visible = false
		_empty_label.visible = false
		_launch_btn.visible = false
		_reason_label.visible = false
		_campaign_box.visible = true
		_refresh_campaign()
		return

	_campaign_box.visible = false
	_launch_btn.visible = true
	_units_scroll.visible = true

	var available: Dictionary = CombatManager.get_deployable_units()
	_empty_label.visible = available.is_empty()

	var check: Dictionary = evaluate_launch(_party())
	_launch_btn.disabled = not bool(check.get("ok", false))
	var reason: String = String(check.get("reason", ""))
	_reason_label.text = _reason_text(reason)
	_reason_label.visible = _launch_btn.disabled and reason != ""

	_rebuild_units(available)

## Lo que la campana esta haciendo ahora mismo, leido de la expedicion viva.
func _refresh_campaign() -> void:
	var run = _expedition()
	if run == null:
		_campaign_status.text = Tr.t("LBL_EXPEDITION_ACTIVE")
	else:
		_campaign_status.text = Tr.t("LBL_EXPEDITION_PROGRESS") % [run.nodes_cleared(), run.map.size()]
	_campaign_party.text = Tr.t("LBL_EXPEDITION_PARTY") % _unit_list(_units_on_expedition())

func _unit_list(counts: Dictionary) -> String:
	if counts.is_empty():
		return "-"
	var parts: Array = []
	for unit_id in counts:
		var def := GameConfig.get_unit_def(unit_id)
		parts.append("%d %s" % [int(counts[unit_id]), Tr.t(def.get("name", unit_id))])
	return "   ".join(parts)

## Traduce el motivo que devuelve `can_launch`. Las claves que llegan son de `Tr`;
## una frase ya escrita se deja pasar tal cual.
func _reason_text(reason: String) -> String:
	if reason == "":
		return ""
	var translated: String = Tr.t(reason)
	if translated != reason:
		return translated
	if reason == "MSG_LAUNCH_DEPLOY_CAP":
		return Tr.t(reason) % GameConfig.combat_deploy_cap
	return reason

# ── Lectura de la expedicion ─────────────────────────────────────────

func has_expedition() -> bool:
	return CombatManager.has_active_expedition()

func _expedition():
	return CombatManager.get_expedition()

func _units_on_expedition() -> Dictionary:
	return CombatManager.get_units_on_expedition()

## Por que se puede (o no) lanzar. El veredicto es del manager y solo de el: una
## segunda copia de las reglas viviendo aqui acabaria discrepando de la suya, y
## entonces el boton mentiria justo cuando mas claro tiene que hablar.
func evaluate_launch(party: Dictionary) -> Dictionary:
	return CombatManager.can_launch(party)

func _party() -> Dictionary:
	var party: Dictionary = {}
	for unit_id in _selection.keys():
		if int(_selection[unit_id]) > 0:
			party[unit_id] = int(_selection[unit_id])
	return party

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
	var run = _expedition()
	if run != null:
		return float(run.morale_snapshot)
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
	var party: Dictionary = _party()
	var check: Dictionary = evaluate_launch(party)
	if not bool(check.get("ok", false)):
		EventBus.notification_posted.emit(
			_reason_text(String(check.get("reason", "MSG_NO_UNITS"))), "warning", UITheme.WARNING
		)
		_refresh()
		return
	CombatManager.launch_expedition(party)
	_close()

## Vuelve al mapa de la campana en curso sin tocar nada de su estado.
func _on_view_map_pressed() -> void:
	var screen: Node = _battle_screen()
	if screen != null and screen.has_method("open_map"):
		screen.open_map()
		_close()

## La pantalla de batalla es hermana de este panel en Main; el barrido del arbol
## es el plan B para escenas de prueba que no la monten en el mismo sitio.
func _battle_screen() -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var sibling: Node = parent.get_node_or_null("BattleScreen")
		if sibling != null:
			return sibling
	return get_tree().root.find_child("BattleScreen", true, false)

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

func _on_expedition_changed() -> void:
	if _is_open:
		_refresh()
	_update_button_visibility()

func _on_expedition_resumed(_expedition_id: int) -> void:
	_on_expedition_changed()

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
