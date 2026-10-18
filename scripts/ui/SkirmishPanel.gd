extends CanvasLayer
## Skirmish panel: where the player decides which troops to commit before the
## board opens. The whole point of this screen is the weight of the choice —
## what goes out can die out there, and Military Power back home is what pays
## for it.
##
## Shows the morale the expedition will be fought with, because morale is the
## bridge between the base and the battlefield and the player must see it before
## committing, not after losing.


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
## Por que "VOLVER A CONVOCARLOS" esta apagado. Mismo criterio que el lanzamiento:
## un boton apagado sin motivo escrito parece roto.
var _audit_reason: Label
var _empty_label: Label

## Lo que se ve en lugar del selector mientras la columna esta fuera.
var _campaign_box: VBoxContainer
var _campaign_status: Label
var _campaign_party: Label
var _map_btn: Button

## unit_id -> how many the player has picked for this run.
var _selection: Dictionary = {}

## El tablon de salidas (doc 21 §3.3-3.5, 2026-10-14): las ofertas a la vista y,
## de la elegida, el mapa entero, los enemigos, el botin y "Favorable/Dificil"
## ANTES de lanzar. Va dentro del mismo scroll que las unidades.
var _sortie_box: VBoxContainer
var _auto_btn: Button
## id de la oferta elegida en el tablon (-1 = la primera que haya).
var _selected_offer: int = -1
## Tres campanas (feat/tres-campanas): la pestana elegida. "land" / "sea" /
## "air" = esa campana; TAB_RAIDS = los ataques rapidos del tablon; "" = la que
## toque (la primera campana con algo que hacer).
const TAB_RAIDS := "raids"
var _tab: String = ""
const ODDS_KEYS := {"favorable": "ODDS_FAVORABLE", "even": "ODDS_EVEN", "hard": "ODDS_HARD"}
const ICON_PX := 24
const BuildingRules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

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
	# El tablon cambia solo (oferta nueva, rebaja gastada): con el panel abierto
	# se repinta.
	EventBus.sortie_offers_changed.connect(func(): if _is_open: _refresh())
	# Las tres campanas: mision ganada, perdida, lista tras descansar.
	EventBus.campaign_changed.connect(func(): if _is_open: _refresh())
	# Por si la partida se cargo antes de que este panel escuchara.
	_on_expedition_changed.call_deferred()
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
	UITheme.style_card_button(_skirmish_btn, UITheme.BTN.lightened(0.05), UITheme.CAT_MILITARY)
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

	_commit_label = UITheme.make_label("", "title", UITheme.CAT_MILITARY)
	_commit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_commit_label)

	# Morale is stated up front: it is the number that decides who swings first.
	_morale_label = UITheme.make_label("", "small", UITheme.ACCENT)
	_morale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_morale_label)

	vbox.add_child(UITheme.make_separator())

	_units_scroll = ScrollContainer.new()
	_units_scroll.custom_minimum_size = Vector2(0, UNITS_SCROLL_H)
	_units_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_units_scroll)

	# Un solo scroll: arriba a donde se sale (y lo que hay alli), debajo con quien.
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_units_scroll.add_child(body)

	_sortie_box = VBoxContainer.new()
	_sortie_box.name = "SortieBoard"
	_sortie_box.add_theme_constant_override("separation", 6)
	_sortie_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_sortie_box)

	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_units_vbox)

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
	UITheme.style_button(_map_btn, UITheme.CAT_MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_map_btn.pressed.connect(_on_view_map_pressed)
	_campaign_box.add_child(_map_btn)

	vbox.add_child(UITheme.make_separator())

	_launch_btn = Button.new()
	_launch_btn.text = Tr.t("BTN_LAUNCH_EXPEDITION")
	_launch_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	UITheme.style_button(_launch_btn, UITheme.CAT_MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_launch_btn.pressed.connect(_on_launch_pressed)
	vbox.add_child(_launch_btn)

	# RESOLVER SOLO (D6 = A): solo en incursiones y solo si la columna dobla al
	# enemigo. Apagado con el motivo en el tooltip cuando no llega.
	_auto_btn = Button.new()
	_auto_btn.name = "AutoResolveButton"
	_auto_btn.text = Tr.t("BTN_AUTO_RESOLVE")
	_auto_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(_auto_btn, UITheme.BTN, UITheme.FONT_BUTTON)
	_auto_btn.pressed.connect(_on_auto_pressed)
	_auto_btn.visible = false
	vbox.add_child(_auto_btn)

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

	_audit_reason = UITheme.make_label("", "small", UITheme.WARNING)
	_audit_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_audit_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audit_reason.visible = false
	vbox.add_child(_audit_reason)

	_dev_btn = Button.new()
	_dev_btn.text = Tr.t("BTN_DEV_SKIRMISH")
	_dev_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(_dev_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_dev_btn.pressed.connect(func(): if CombatManager.dev_start_encounter(): _close())
	vbox.add_child(_dev_btn)

	_refresh()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_height)

## El scroll de MISIONES mide 300 de serie; en un telefono apaisado (lienzo de
## ~400 de alto) el panel entero no cabia y se cortaban la cabecera con su X y
## el pie (ronda visual de la 1.1). Se encoge lo que haga falta, hasta 90.
const UNITS_SCROLL_H := 300.0
const UNITS_SCROLL_MIN_H := 90.0

static func units_scroll_height(vp_h: float, chrome_h: float) -> float:
	return clampf(vp_h - 32.0 - chrome_h, UNITS_SCROLL_MIN_H, UNITS_SCROLL_H)

func _fit_height() -> void:
	if _panel == null or _units_scroll == null or not is_inside_tree():
		return
	var chrome: float = _panel.get_combined_minimum_size().y - _units_scroll.custom_minimum_size.y
	var h := units_scroll_height(get_viewport().get_visible_rect().size.y, chrome)
	if not is_equal_approx(_units_scroll.custom_minimum_size.y, h):
		_units_scroll.custom_minimum_size.y = h

# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _commit_label:
		return
	_fit_height.call_deferred()
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
		_auto_btn.visible = false
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
	var ok: bool = bool(check.get("ok", false))
	var reason: String = String(check.get("reason", ""))
	# Las reglas del manager van primero; despues, que haya a donde salir.
	var offer: Dictionary = current_offer()
	# Tres campanas: con una campana elegida, su candado manda (edificio, era,
	# descanso, completa); sin oferta en ella, se dice por que.
	var tab_domain: String = current_campaign()
	if tab_domain != "":
		var lock: String = CombatManager.campaign_lock_reason(tab_domain)
		if lock != "" and (ok or lock in ["CAMP_DONE", "CAMP_LOCK_BUILDING", "CAMP_LOCK_ERA", "CAMP_LOCK_REST", "CAMP_LOCK_FIRST_SORTIE"]):
			ok = false
			reason = _campaign_lock_text(tab_domain)
	if ok and offer.is_empty():
		ok = false
		reason = "LBL_SORTIE_NONE"
	_launch_btn.disabled = not ok
	_reason_label.text = _reason_text(reason)
	_reason_label.visible = _launch_btn.disabled and reason != ""

	var preview: Dictionary = {} if offer.is_empty() else CombatManager.sortie_preview(offer, _party())
	_rebuild_sorties(offer, preview)
	_refresh_auto_button(offer, preview, ok)

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
	# Nadie elegido con tropas en casa: "sin unidades en casa" mentia (ronda de
	# pruebas 1.0). Se dice que hacer.
	if reason == "MSG_NO_UNITS":
		for unit_id in CombatManager.get_deployable_units():
			if int(CombatManager.get_deployable_units()[unit_id]) > 0:
				return Tr.t("MSG_PICK_UNITS")
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
	# Aire y mar: con la salida elegida delante, para que los barcos sin agua
	# digan por que no salen.
	return CombatManager.can_launch_to(party, current_offer())

## ¿Hay agua en la salida elegida? (Solo entonces se pueden llevar barcos.)
func _offer_has_water() -> bool:
	return CombatManager.offer_has_water(current_offer())

func _party() -> Dictionary:
	var party: Dictionary = {}
	for unit_id in _selection.keys():
		if int(_selection[unit_id]) > 0:
			party[unit_id] = int(_selection[unit_id])
	return party

## Drops picks the player no longer owns (units lost, disbanded or spent).
func _prune_selection() -> void:
	var available: Dictionary = CombatManager.get_deployable_units()
	var water: bool = _offer_has_water()
	var domain: String = current_campaign()
	for unit_id in _selection.keys():
		var owned: int = int(available.get(unit_id, 0))
		# Tres campanas: lo que no es de su medio (o no le puede pegar) se queda.
		if domain != "" and CombatManager.campaign_unit_block(String(unit_id), domain) != "":
			owned = 0
		# Sin agua en la salida elegida, los barcos se quedan en el puerto.
		if not water and GameConfig.get_unit_domain(String(unit_id)) == CombatUnit.DOMAIN_SEA:
			owned = 0
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

## Aire y mar: las filas van por medio (Tierra, Mar, Aire), con su cabecera solo
## si hay alguien de ese medio en casa. Los barcos, si la salida elegida no
## tiene agua, salen con el motivo y sin poder elegirse.
func _rebuild_units(available: Dictionary) -> void:
	for child in _units_vbox.get_children():
		child.queue_free()
	var water: bool = _offer_has_water()
	var camp: String = current_campaign()
	for domain in ["land", "sea", "air"]:
		# Tres campanas: dominio puro. Solo las filas del medio de la campana.
		if camp != "" and domain != camp:
			continue
		var ids: Array = []
		for unit_id in GameConfig.get_unit_ids_in_domain(domain):
			if int(available.get(unit_id, 0)) > 0:
				ids.append(unit_id)
		if ids.is_empty():
			if camp != "":
				var none := UITheme.make_label(Tr.t("CAMP_NO_UNITS_" + camp.to_upper()), "small", UITheme.WARNING)
				none.name = "CampaignNoUnits"
				none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_units_vbox.add_child(none)
			continue
		var header := UITheme.make_label(Tr.t("LBL_DOMAIN_" + domain.to_upper()), "section", UITheme.ACCENT)
		header.name = "DomainHeader_" + domain
		_units_vbox.add_child(header)
		var blocked: bool = domain == CombatUnit.DOMAIN_SEA and not water and camp == ""
		if blocked:
			var why := UITheme.make_label(Tr.t("LBL_SHIPS_NEED_WATER"), "small", UITheme.WARNING)
			why.name = "ShipsNeedWater"
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_units_vbox.add_child(why)
		for unit_id in ids:
			var unit_block: bool = blocked
			if camp != "" and CombatManager.campaign_unit_block(String(unit_id), camp) != "":
				unit_block = true
			var block_text: String = ""
			if unit_block and camp != "":
				block_text = Tr.t(CombatManager.campaign_unit_block(String(unit_id), camp))
			_units_vbox.add_child(_make_unit_row(unit_id, int(available[unit_id]), unit_block, block_text))

func _make_unit_row(unit_id: String, owned: int, blocked: bool = false, block_text: String = "") -> PanelContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var stats := GameConfig.get_combat_stats(unit_id)
	var picked: int = int(_selection.get(unit_id, 0))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_width_left = 5
	style.border_color = UITheme.CAT_MILITARY if picked > 0 else UITheme.TEXT_DIM
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
	title_row.add_child(UITheme.make_label(Tr.t("LBL_ARMY_OWNED") % owned, "section", UITheme.POSITIVE))
	info.add_child(title_row)

	# The combat stats, not the economic ones: this is a tactical decision.
	# Palabras y no siglas (HP, ATK...): el juego es para chavales (ronda 1.0).
	var r_min := int(stats.get("min_range", 1))
	var r_max := int(stats.get("range", 1))
	var reach := str(r_max) if r_min == r_max else "%d-%d" % [r_min, r_max]
	var line := Tr.t("FMT_UNIT_STATS_LINE") % [
		int(stats.get("hp", 0)), int(stats.get("atk", 0)), int(stats.get("def", 0)),
		int(stats.get("move", 0)), reach,
	]
	var stats_label := UITheme.make_label(line, "small", UITheme.TEXT_DIM)
	stats_label.name = "CombatStats"
	# Que es cada sigla, en el tooltip (y en la ayuda del tablero).
	stats_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_label.tooltip_text = Tr.t("LBL_COMBAT_STATS_HINT")
	info.add_child(stats_label)

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
	plus.disabled = blocked or picked >= owned or _committed() >= GameConfig.combat_deploy_cap
	if blocked:
		plus.tooltip_text = block_text if block_text != "" else Tr.t("LBL_SHIPS_NEED_WATER")
	plus.pressed.connect(func(): _adjust(unit_id, 1))
	row.add_child(plus)

	return card

func _adjust(unit_id: String, delta: int) -> void:
	var owned: int = int(CombatManager.get_deployable_units().get(unit_id, 0))
	var camp: String = current_campaign()
	if delta > 0 and camp != "" and CombatManager.campaign_unit_block(unit_id, camp) != "":
		return
	if delta > 0 and camp == "" and GameConfig.get_unit_domain(unit_id) == CombatUnit.DOMAIN_SEA and not _offer_has_water():
		return
	var picked: int = int(_selection.get(unit_id, 0))
	var next: int = clampi(picked + delta, 0, owned)
	if delta > 0 and _committed() >= GameConfig.combat_deploy_cap:
		return
	_selection[unit_id] = next
	_refresh()

# ── Launch ───────────────────────────────────────────────────────────

## Visible solo cuando hay algo que convocar: la primera vez (pendiente) o tras
## perder, si el ejercito ya da para volver a llamarlos.
##
## Con un tablero abierto o la columna fuera el boton se ve pero no se pulsa, y
## el tooltip dice por que: la oleada no tendria donde bajar.
func _refresh_audit_button() -> void:
	var blocked: String = CombatManager.final_audit_block_reason()
	_audit_btn.tooltip_text = Tr.t(blocked) if blocked != "" else ""
	if ProgressionManager.is_final_audit_pending():
		_audit_btn.text = Tr.t("BTN_AUDIT_BEGIN")
		_audit_btn.visible = true
		_audit_btn.disabled = blocked != ""
	elif ProgressionManager.is_final_audit_lost():
		_audit_btn.text = Tr.t("BTN_AUDIT_RESUMMON")
		_audit_btn.visible = true
		_audit_btn.disabled = blocked != "" or not ProgressionManager.can_resummon_final_audit()
	else:
		_audit_btn.visible = false
	var reason: String = audit_block_reason()
	_audit_reason.text = reason
	_audit_reason.visible = _audit_btn.visible and _audit_btn.disabled and reason != ""

## Por que no se puede volver a convocar a la Regencia ahora mismo, o "" si se
## puede (o si no hay nada que convocar). Las cifras salen del manager y de
## GameConfig: aqui no se decide nada, solo se explica.
func audit_block_reason() -> String:
	if not ProgressionManager.is_final_audit_lost():
		return ""
	if ProgressionManager.can_resummon_final_audit():
		return ""
	var standing: int = CombatManager.roster_size(CombatManager.get_garrison())
	return "%s %s" % [
		Tr.t("AUDIT_RESUMMON_LOCKED") % GameConfig.final_audit_resummon_min_units,
		Tr.t("LBL_AUDIT_STANDING") % standing,
	]

func _on_audit_pressed() -> void:
	var started: bool = false
	var blocked: String = CombatManager.final_audit_block_reason()
	if blocked != "":
		# Nada de reconvocar para luego no poder empezar: se avisa y ya.
		EventBus.notification_posted.emit(Tr.t(blocked), "warning", UITheme.WARNING)
		_refresh()
		return
	if ProgressionManager.is_final_audit_pending():
		started = ProgressionManager.begin_final_audit()
	elif ProgressionManager.is_final_audit_lost():
		started = ProgressionManager.resummon_final_audit() and ProgressionManager.begin_final_audit()
	if started:
		_close()
	else:
		# Nunca en silencio: si el boton se pulso y no paso nada, se dice por que.
		var reason: String = audit_block_reason()
		if reason == "" and has_expedition():
			reason = Tr.t("MSG_EXPEDITION_ACTIVE")
		if reason != "":
			EventBus.notification_posted.emit(reason, "warning", UITheme.WARNING)
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
	# Hasta ganar la primera, cada salida es la escaramuza facil de un solo nodo
	# (docs/15-combat.md §4). Despues, la oferta elegida del tablon.
	if CombatManager.is_first_sortie_due():
		CombatManager.launch_expedition(party, 0, true)
		_close()
		return
	var offer: Dictionary = current_offer()
	# Tres campanas: la mision que toca de la pestana elegida.
	if String(offer.get("kind", "")) == ExpeditionGenerator.KIND_CAMPAIGN:
		if CombatManager.launch_campaign_mission(String(offer.get("domain", "")), party):
			_close()
		else:
			# Nunca en silencio: el candado si lo hay, si no el motivo de la tropa.
			var why: String = _campaign_lock_text(String(offer.get("domain", "")))
			if why == "":
				why = _reason_text(String(evaluate_launch(party).get("reason", "MSG_SORTIE_GONE")))
			EventBus.notification_posted.emit(why, "warning", UITheme.WARNING)
			_refresh()
		return
	if offer.is_empty() or not CombatManager.launch_sortie(int(offer.get("id", 0)), party):
		EventBus.notification_posted.emit(Tr.t("MSG_SORTIE_GONE"), "warning", UITheme.WARNING)
		_refresh()
		return
	_close()

## RESOLVER SOLO: la incursion elegida se lanza y se juega de un tiron.
func _on_auto_pressed() -> void:
	var party: Dictionary = _party()
	var offer: Dictionary = current_offer()
	if offer.is_empty() or not bool(evaluate_launch(party).get("ok", false)):
		_refresh()
		return
	if not bool(CombatManager.sortie_preview(offer, party).get("can_auto", false)):
		_refresh()
		return
	if CombatManager.launch_sortie(int(offer.get("id", 0)), party, true):
		_close()
	else:
		_refresh()

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
	_skirmish_btn.visible = _sidebar_visible and ArmyManager.has_military_building()

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
	# Mirar el tablon apaga el punto rojo de "salida nueva".
	CombatManager.mark_sorties_seen()

## Lo abre el boton ESCARAMUZAS del HUD (y ☰ MENU). Si ya esta abierto, no lo cierra.
func open() -> void:
	if not _is_open:
		_open()

func is_open() -> bool:
	return _is_open

func _close() -> void:
	_is_open = false
	_panel.visible = false
	_backdrop.visible = false
	UIManager.close_panel(self)

# ── El tablon de salidas (doc 21 §3.3-3.5) ───────────────────────────

## La oferta elegida: la primera escaramuza mientras toque ({"kind": "first"}),
## si no la del tablon que el jugador marco (o la primera que haya). {} si no
## hay ninguna.
func current_offer() -> Dictionary:
	if CombatManager.is_first_sortie_due():
		return {"kind": "first", "era": ProgressionManager.current_era}
	# Tres campanas: la pestana de una campana ofrece su mision que toca.
	var domain: String = current_campaign()
	if domain != "":
		return CombatManager.campaign_offer(domain)
	var offers: Array = CombatManager.get_sortie_offers()
	if offers.is_empty():
		return {}
	for offer in offers:
		if int(offer.get("id", 0)) == _selected_offer:
			return offer
	_selected_offer = int(offers[0].get("id", 0))
	return offers[0]

func select_offer(offer_id: int) -> void:
	_selected_offer = offer_id
	_refresh()

func _rebuild_sorties(offer: Dictionary, preview: Dictionary) -> void:
	for child in _sortie_box.get_children():
		child.queue_free()
	# La rebaja del Diezmo ya ganada, para que se vea que sirvio.
	var cut: int = CombatManager.get_tithe_cut_pct()
	if cut > 0:
		_sortie_box.add_child(UITheme.make_label(Tr.t("LOOT_TITHE_CUT") % cut, "small", UITheme.POSITIVE))
	# Tres campanas: lo que falta para el Ataque Final, las pestanas y la
	# campana elegida. Mientras toca la primera escaramuza, nada de esto.
	if not CombatManager.is_first_sortie_due():
		_add_gate_line()
		_add_tabs()
		var domain: String = current_campaign()
		if domain != "":
			_add_campaign_header(domain)
			if not preview.is_empty():
				_sortie_box.add_child(_make_detail(offer, preview))
			return
	if not CombatManager.is_first_sortie_due():
		var offers: Array = CombatManager.get_sortie_offers()
		if offers.is_empty():
			var none := UITheme.make_label(Tr.t("LBL_SORTIE_NONE"), "small", UITheme.TEXT_DIM)
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_sortie_box.add_child(none)
			return
		_sortie_box.add_child(UITheme.section_header(Tr.t("LBL_SORTIE_PICK")))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		_sortie_box.add_child(row)
		for entry in offers:
			row.add_child(_make_offer_button(entry, int(entry.get("id", 0)) == int(offer.get("id", -1))))
	if not preview.is_empty():
		_sortie_box.add_child(_make_detail(offer, preview))

## Un boton por oferta: nombre y tipo. La elegida, con el color militar.
func _make_offer_button(offer: Dictionary, selected: bool) -> Button:
	var btn := Button.new()
	var offer_name: String = Tr.t(ExpeditionGenerator.offer_name_key(offer))
	var fights: int = ExpeditionGenerator.fights_on_path(CombatManager.offer_map(offer))
	btn.text = "%s\n%s" % [offer_name, _kind_text(offer, fights)]
	btn.custom_minimum_size = Vector2(UITheme.touch_px(200.0), UITheme.MIN_BTN_H + 16)
	btn.toggle_mode = true
	btn.button_pressed = selected
	UITheme.style_button(btn, UITheme.CAT_MILITARY.darkened(0.15) if selected else UITheme.BTN, UITheme.FONT_SMALL)
	var offer_id: int = int(offer.get("id", 0))
	btn.pressed.connect(func(): select_offer(offer_id))
	return btn

func _kind_text(offer: Dictionary, fights: int) -> String:
	if String(offer.get("kind", "")) == ExpeditionGenerator.KIND_CAMPAIGN:
		return Tr.t("CAMP_KIND_FIGHTS") % fights
	if String(offer.get("kind", "")) == ExpeditionGenerator.KIND_EXPEDITION:
		return Tr.t("SORTIE_KIND_EXPEDITION") % fights
	return Tr.t("SORTIE_KIND_RAID")

## La ficha de la salida elegida: nombre, mapa con los enemigos de cada combate,
## botin y la cuenta de fuerzas con su etiqueta. Iconos y numeros delante.
func _make_detail(offer: Dictionary, preview: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SortieDetail"
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(10)
	style.border_width_left = 5
	style.border_color = UITheme.CAT_MILITARY
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var title := UITheme.make_label("%s · %s" % [Tr.t(String(preview.get("name_key", ""))),
		_kind_text(offer, int(preview.get("fights", 1)))], "section", UITheme.TEXT_BRIGHT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	# Aire y mar: una salida de costa se dice antes de salir (hay agua, vienen
	# barcos y puedes llevar los tuyos).
	var camp_domain: String = String(preview.get("campaign_domain", ""))
	if camp_domain != "":
		var where := UITheme.make_label(Tr.t("CAMP_WHERE_" + camp_domain.to_upper()), "small", UITheme.INFO)
		where.name = "CampaignWhere"
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(where)
		if bool(preview.get("campaign_boss", false)):
			var boss := UITheme.make_label(Tr.t("CAMP_BOSS_WARNING"), "small", UITheme.DANGER)
			boss.name = "CampaignBoss"
			boss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(boss)
	elif bool(preview.get("coastal", false)):
		var coast := UITheme.make_label(Tr.t("LBL_SORTIE_COASTAL"), "small", UITheme.INFO)
		coast.name = "SortieCoastal"
		coast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(coast)

	# El mapa entero, por capas: lo que hay en cada combate.
	var map: Array = preview.get("map", [])
	var layers: Array = preview.get("layers", [])
	for i in range(layers.size()):
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 6)
		var is_boss_layer: bool = false
		for index in layers[i]:
			if bool(map[int(index)].get("is_boss", false)):
				is_boss_layer = true
		var label_text: String = Tr.t("LBL_SORTIE_BOSS") if is_boss_layer else Tr.t("LBL_SORTIE_FIGHT_N") % (i + 1)
		line.add_child(UITheme.make_label(label_text + ":", "small", UITheme.ACCENT))
		var first := true
		for index in layers[i]:
			if not first:
				line.add_child(UITheme.make_label(Tr.t("LBL_SORTIE_OR"), "small", UITheme.TEXT_DIM))
			first = false
			_add_roster_icons(line, map[int(index)].get("enemy_roster", {}))
		box.add_child(line)

	# El botin: lo exclusivo primero, despues oro y madera.
	var loot_row := HFlowContainer.new()
	loot_row.name = "SortieLoot"
	loot_row.add_theme_constant_override("h_separation", 10)
	loot_row.add_child(UITheme.make_label(Tr.t("LBL_SORTIE_LOOT") + ":", "small", UITheme.ACCENT))
	for text in loot_lines(preview.get("loot", {})):
		loot_row.add_child(UITheme.make_label(String(text), "small", UITheme.POSITIVE))
	var rewards: Dictionary = preview.get("rewards", {})
	for res_name in rewards:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.add_child(UITheme.make_icon(String(res_name), ICON_PX))
		chip.add_child(UITheme.make_label("+%d" % int(rewards[res_name]), "small", UITheme.resource_color(String(res_name))))
		loot_row.add_child(chip)
	box.add_child(loot_row)

	# Fuerzas y etiqueta (doc 21 §3.5).
	var odds_row := HFlowContainer.new()
	odds_row.add_theme_constant_override("h_separation", 10)
	# Sin nadie elegido no se dice "Dificil" en rojo: asusta y no es verdad
	# todavia (ronda de pruebas 1.0). Se dice que hacer.
	if roundi(float(preview.get("player_power", 0.0))) <= 0:
		var pick := UITheme.make_label(Tr.t("ODDS_PICK_FIRST"), "small", UITheme.TEXT_DIM)
		pick.name = "OddsLabel"
		odds_row.add_child(pick)
		box.add_child(odds_row)
		return card
	odds_row.add_child(UITheme.make_label(Tr.t("LBL_SORTIE_STRENGTH") % [
		roundi(float(preview.get("player_power", 0.0))), roundi(float(preview.get("enemy_power", 0.0)))],
		"small", UITheme.TEXT))
	var odds: String = String(preview.get("odds", "even"))
	var odds_label := UITheme.make_label(Tr.t(String(ODDS_KEYS.get(odds, "ODDS_EVEN"))), "section", _odds_color(odds))
	odds_label.name = "OddsLabel"
	odds_row.add_child(odds_label)
	box.add_child(odds_row)
	return card

## Las lineas del botin exclusivo, ya traducidas ("+3 repuestos", "Plano: ...").
## Publico y estatico: el parte de BattleScreen dice lo mismo con las mismas palabras.
static func loot_lines(loot: Dictionary) -> Array:
	var lines: Array = []
	if int(loot.get("parts", 0)) > 0:
		lines.append(Tr.t("LOOT_PARTS") % int(loot["parts"]))
	if int(loot.get("colonists", 0)) > 0:
		lines.append(Tr.t("LOOT_COLONISTS") % int(loot["colonists"]))
	if int(loot.get("tithe_pct", 0)) > 0:
		lines.append(Tr.t("LOOT_TITHE_CUT") % int(loot["tithe_pct"]))
	for id in loot.get("blueprints", []):
		var data: BuildingData = BuildingRules.load_building_data(String(id))
		lines.append(Tr.t("LOOT_BLUEPRINT") % (data.get_display_name() if data != null else String(id)))
	# El botin de un solo nodo lleva el plano suelto ("blueprint").
	var single: Variant = loot.get("blueprint", "")
	if single is String and String(single) != "":
		var single_data: BuildingData = BuildingRules.load_building_data(String(single))
		lines.append(Tr.t("LOOT_BLUEPRINT") % (single_data.get_display_name() if single_data != null else String(single)))
	if int(loot.get("colonists_no_room", 0)) > 0:
		lines.append(Tr.t("LOOT_COLONISTS_NO_ROOM") % int(loot["colonists_no_room"]))
	return lines

func _add_roster_icons(line: Container, roster: Dictionary) -> void:
	for unit_id in GameConfig.get_unit_ids():
		var count: int = int(roster.get(unit_id, 0))
		if count <= 0:
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		var icon := TextureRect.new()
		icon.texture = UITheme.unit_icon(String(unit_id), ICON_PX)
		icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UITheme.unit_icon_tint(false)
		icon.tooltip_text = Tr.t(String(GameConfig.get_unit_def(String(unit_id)).get("name", unit_id)))
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(icon)
		chip.add_child(UITheme.make_label("x%d" % count, "small", UITheme.TEXT))
		line.add_child(chip)

func _odds_color(odds: String) -> Color:
	match odds:
		"favorable":
			return UITheme.POSITIVE
		"hard":
			return UITheme.DANGER
	return UITheme.WARNING

## RESOLVER SOLO solo en incursiones; encendido si la columna dobla al enemigo.
func _refresh_auto_button(offer: Dictionary, preview: Dictionary, launch_ok: bool) -> void:
	var is_raid: bool = String(offer.get("kind", "")) == ExpeditionGenerator.KIND_RAID
	_auto_btn.visible = is_raid
	if not is_raid:
		return
	var can: bool = bool(preview.get("can_auto", false))
	_auto_btn.disabled = not (launch_ok and can)
	_auto_btn.tooltip_text = Tr.t("HINT_AUTO_RESOLVE") if can else Tr.t("HINT_AUTO_RESOLVE_LOCKED")

# ── Las tres campanas: pestanas Tierra / Mar / Aire (feat/tres-campanas) ──

## La campana de la pestana elegida ("land" / "sea" / "air"), o "" si la
## pestana es la de ataques rapidos (o toca la primera escaramuza).
func current_campaign() -> String:
	if CombatManager.is_first_sortie_due():
		return ""
	if _tab == "":
		_tab = _default_tab()
	return _tab if _tab in GameConfig.CAMPAIGN_DOMAINS else ""

## La pestana con la que se abre el panel: la campana con una mision nueva lista,
## si no la primera que tenga su edificio y algo por hacer, si no los ataques
## rapidos (si hay alguno), si no la de Tierra.
func _default_tab() -> String:
	var waiting: String = CombatManager.campaign_waiting_unseen()
	if waiting != "":
		return waiting
	for domain in GameConfig.CAMPAIGN_DOMAINS:
		var lock: String = CombatManager.campaign_lock_reason(String(domain))
		if lock in ["", "CAMP_LOCK_REST", "CAMP_LOCK_ERA"]:
			return String(domain)
	if not CombatManager.get_sortie_offers().is_empty():
		return TAB_RAIDS
	return "land"

## Cambia de pestana. Publico para la UI y las pruebas.
func select_tab(tab: String) -> void:
	_tab = tab
	_refresh()

func current_tab() -> String:
	current_campaign()
	return _tab

## "Para llamar al Ataque Final: Campana de Mar 2/5, ..." arriba del todo,
## mientras falte algo (y el modo tenga asedio).
func _add_gate_line() -> void:
	var text: String = ProgressionManager.final_audit_gate_text()
	if text == "":
		return
	var gate := UITheme.make_label(text, "small", UITheme.WARNING)
	gate.name = "AuditGateLine"
	gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sortie_box.add_child(gate)

## Las cuatro pestanas: Tierra, Mar y Aire con su N/M (o "cerrada" sin su
## edificio) y los ataques rapidos del tablon con cuantos hay.
func _add_tabs() -> void:
	var row := HFlowContainer.new()
	row.name = "CampaignTabs"
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	_sortie_box.add_child(row)
	var current: String = current_tab()
	for domain in GameConfig.CAMPAIGN_DOMAINS:
		var d: String = String(domain)
		var sub: String = ""
		var lock: String = CombatManager.campaign_lock_reason(d)
		if lock == "CAMP_LOCK_BUILDING":
			sub = Tr.t("CAMP_TAB_LOCKED")
		elif CombatManager.is_campaign_complete(d):
			sub = Tr.t("CAMP_TAB_DONE")
		else:
			sub = "%d/%d" % [CombatManager.campaign_won(d), CombatManager.campaign_total(d)]
		row.add_child(_make_tab_button("CampaignTab_" + d, "%s\n%s" % [Tr.t("LBL_DOMAIN_" + d.to_upper()), sub], d, current == d))
	var raids: int = CombatManager.get_sortie_offers().size()
	row.add_child(_make_tab_button("CampaignTab_raids", "%s\n%d" % [Tr.t("CAMP_TAB_RAIDS"), raids], TAB_RAIDS, current == TAB_RAIDS))

func _make_tab_button(node_name: String, text: String, tab: String, selected: bool) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = selected
	btn.custom_minimum_size = Vector2(UITheme.touch_px(96.0), UITheme.MIN_BTN_H + 12)
	UITheme.style_button(btn, UITheme.CAT_MILITARY.darkened(0.15) if selected else UITheme.BTN, UITheme.FONT_SMALL)
	btn.pressed.connect(func(): select_tab(tab))
	return btn

## La cabecera de la campana elegida: su nombre, la fila de misiones (hechas,
## la que toca y el jefe al final) y, si no se puede salir, por que.
func _add_campaign_header(domain: String) -> void:
	var won: int = CombatManager.campaign_won(domain)
	var total: int = CombatManager.campaign_total(domain)
	var title := UITheme.make_label(Tr.t("CAMP_NAME_" + domain.to_upper()), "section", UITheme.ACCENT)
	title.name = "CampaignTitle"
	_sortie_box.add_child(title)
	var pips: Array = []
	for i in range(total):
		var boss: bool = i == total - 1
		if i < won:
			pips.append("✔")
		elif i == won:
			pips.append("▶" if not boss else "☠")
		else:
			pips.append("☠" if boss else "·")
	var track := UITheme.make_label("%s   %s" % [" ".join(pips), Tr.t("CAMP_PROGRESS") % [won, total]], "small", UITheme.TEXT)
	track.name = "CampaignTrack"
	_sortie_box.add_child(track)
	var blurb := UITheme.make_label(Tr.t("CAMP_BLURB_" + domain.to_upper()), "small", UITheme.TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sortie_box.add_child(blurb)
	# El Leviatan pide acorazados: se dice antes de llegar a el (docs/15 §13).
	var need: String = Objectives.campaign_boss_need_text(domain)
	if need != "":
		var need_label := UITheme.make_label(need, "small", UITheme.WARNING)
		need_label.name = "CampaignBossNeed"
		need_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sortie_box.add_child(need_label)
	var lock: String = CombatManager.campaign_lock_reason(domain)
	if lock != "":
		var why := UITheme.make_label(_campaign_lock_text(domain), "small",
			UITheme.POSITIVE if lock == "CAMP_DONE" else UITheme.WARNING)
		why.name = "CampaignLock"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sortie_box.add_child(why)

## El candado de una campana en palabras, con su cifra: "Construye un Astillero",
## "Llega a la era 3", "La tropa descansa: 1:20".
func _campaign_lock_text(domain: String) -> String:
	var text: String = Objectives.campaign_lock_text(domain)
	# Los motivos de can_launch (columna fuera, asedio...) ya vienen traducidos.
	return text
