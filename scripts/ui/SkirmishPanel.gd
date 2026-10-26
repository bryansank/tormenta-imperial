extends CanvasLayer
## MISIONES: donde se decide a donde salir y con quien, antes de que se abra el
## tablero. Lo que sale puede morir fuera, y el Poder Militar de casa es lo que
## lo paga: el peso de la eleccion es el sentido de la pantalla.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28; maqueta aprobada en
## tools/ui_mockup/mock_screens.gd, build_missions): ventana crema con cinta roja,
##   [Tierra][Mar][Aire][Ataques rapidos]               (pestanas)
##   [Ataque Final: ✓ CG 3 · ✓ Tierra · 🔒 Mar 2/5]      (solo si falta algo)
##   ┌ la mision ──────────────────┐ ┌ tu tropa ─────────┐
##   │ ✓ ✓ ★ 4 5 [jefe]   3 de 6   │ │ [o] Soldado - 3 + │
##   │ Mision 3 · El vado Favorable│ │ [o] Canon   - 1 + │
##   │ [enemigos]       [botin]    │ │                   │
##   └─────────────────────────────┘ └───────────────────┘
##   [moral 72] [salen 3/6]  [ ¡AL ATAQUE! ]            (fijo abajo)
## Icono + numero; lo que no se puede, con su porque en 2-3 palabras; el detalle
## (el mapa entero, de que va la campana, las cuentas) al mantener pulsado.
##
## La moral con la que se pelea va delante: es el puente entre la base y el
## campo de batalla, y se tiene que ver antes de comprometerse, no al perder.

const BuildingRules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Tope de la ventana en PC (en telefono va a pantalla completa).
const MAX_SIZE := Vector2(1080, 560)
const DOMAIN_GLYPH := {"land": "tank", "sea": "anchor", "air": "plane"}
const DOMAIN_TAB_KEY := {"land": "ARMY2_TAB_LAND", "sea": "ARMY2_TAB_SEA", "air": "ARMY2_TAB_AIR"}

var _win: Dictionary = {}
var _holder: Control
var _panel: PanelContainer
var _backdrop: ColorRect
var _skirmish_btn: Button
var _is_open := false
var _sidebar_visible := false

## "3/6": cuantos salen de cuantos caben. Y la moral de la pelea.
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
var _campaign_party: HBoxContainer
var _map_btn: Button

## unit_id -> how many the player has picked for this run.
var _selection: Dictionary = {}

## El selector: pestanas y lo que falta para el Ataque Final arriba (`_head_box`,
## se rehace), y debajo la mision elegida (`_mission_box`) y la tropa.
var _sortie_box: VBoxContainer
var _head_box: VBoxContainer
var _main_row: HBoxContainer
var _mission_card: PanelContainer
var _mission_box: VBoxContainer
var _troop_card: PanelContainer
var _troop_title: Label
var _auto_btn: Button
var _footer: HBoxContainer
## id de la oferta elegida en el tablon (-1 = la primera que haya).
var _selected_offer: int = -1
## Tres campanas (feat/tres-campanas): la pestana elegida. "land" / "sea" /
## "air" = esa campana; TAB_RAIDS = los ataques rapidos del tablon; "" = la que
## toque (la primera campana con algo que hacer).
const TAB_RAIDS := "raids"
var _tab: String = ""
const ODDS_KEYS := {"favorable": "ODDS_FAVORABLE", "even": "ODDS_EVEN", "hard": "ODDS_HARD"}
const ICON_PX := 24

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
	get_viewport().size_changed.connect(_on_viewport_resized)
	# Por si la partida se cargo antes de que este panel escuchara.
	_on_expedition_changed.call_deferred()
	_update_button_visibility()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Boton de la barra lateral vieja (☰). La barra de abajo y SkirmishButton
	# abren el panel con open().
	_skirmish_btn = Button.new()
	_skirmish_btn.text = Tr.t("BTN_SKIRMISH")
	_skirmish_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_skirmish_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skirmish_btn.offset_left = -176
	_skirmish_btn.offset_top = UILayoutManager.get_sidebar_button_offset("SkirmishPanel.button")
	CT.style_pill(_skirmish_btn, "open", CT.BTN_SMALL, "hud", "missions")
	_skirmish_btn.pressed.connect(_toggle_panel)
	_skirmish_btn.visible = false
	root.add_child(_skirmish_btn)

	_win = CT.modal_window(root, Tr.t("LBL_SKIRMISH_TITLE"), CT.sem("DANGER"))
	_holder = _win["holder"]
	_holder.visible = false
	_backdrop = _win["veil"]
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	_panel = _win["panel"]
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	(_win["close"] as Button).pressed.connect(_toggle_panel)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	var body: VBoxContainer = _win["body"]

	# ── El selector ──
	_sortie_box = VBoxContainer.new()
	_sortie_box.name = "SortieBoard"
	_sortie_box.add_theme_constant_override("separation", 6)
	_sortie_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_sortie_box)

	_head_box = VBoxContainer.new()
	_head_box.add_theme_constant_override("separation", 6)
	_sortie_box.add_child(_head_box)

	# Apaisado siempre (docs/28 §4): mision y tropa lado a lado.
	_main_row = HBoxContainer.new()
	_main_row.add_theme_constant_override("separation", 8)
	_main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sortie_box.add_child(_main_row)

	_mission_card = PanelContainer.new()
	_mission_card.name = "SortieDetail"
	_mission_card.add_theme_stylebox_override("panel", CT.card_style("window", true))
	_mission_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_row.add_child(_mission_card)
	var mission_scroll := ScrollContainer.new()
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mission_card.add_child(mission_scroll)
	_mission_box = VBoxContainer.new()
	_mission_box.add_theme_constant_override("separation", 6)
	_mission_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_scroll.add_child(_mission_box)

	_troop_card = PanelContainer.new()
	_troop_card.name = "TroopCard"
	_troop_card.add_theme_stylebox_override("panel", CT.card_style("window"))
	# Telefono en vertical: la tropa va debajo de la mision (al lado se salia
	# por la derecha en 400 px).
	if CT.portrait():
		_troop_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_sortie_box.add_child(_troop_card)
	else:
		_main_row.add_child(_troop_card)
	var troop_col := VBoxContainer.new()
	troop_col.add_theme_constant_override("separation", 4)
	_troop_card.add_child(troop_col)
	_troop_title = CT.label(Tr.t("ARMY2_TROOP"), "title", CT.text("window"))
	troop_col.add_child(_troop_title)
	_units_scroll = ScrollContainer.new()
	_units_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	troop_col.add_child(_units_scroll)
	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 4)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_units_scroll.add_child(_units_vbox)
	_empty_label = CT.para(Tr.t("MSG_NO_UNITS"), "window", true, "small")
	_empty_label.visible = false
	troop_col.add_child(_empty_label)

	# ── Con la expedicion en marcha no hay nada que elegir: por donde va la
	# columna, quien va en ella y volver al mapa. ──
	_campaign_box = VBoxContainer.new()
	_campaign_box.add_theme_constant_override("separation", 10)
	_campaign_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_campaign_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_box.visible = false
	body.add_child(_campaign_box)
	_campaign_status = CT.label("", "title", CT.text("window"))
	_campaign_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_campaign_box.add_child(_campaign_status)
	_campaign_party = HBoxContainer.new()
	_campaign_party.alignment = BoxContainer.ALIGNMENT_CENTER
	_campaign_party.add_theme_constant_override("separation", 6)
	_campaign_box.add_child(_campaign_party)
	_map_btn = CT.pill_button(Tr.t("BTN_VIEW_MAP"), "missions", "open", CT.h("big"))
	_map_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map_btn.pressed.connect(_on_view_map_pressed)
	_campaign_box.add_child(_map_btn)

	# ── El pie, fijo abajo: moral, cuantos salen y ¡AL ATAQUE! ──
	var foot_col := VBoxContainer.new()
	foot_col.add_theme_constant_override("separation", 2)
	body.add_child(foot_col)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 10)
	foot_col.add_child(_footer)
	# Telefono en vertical: los botones van en su propia fila, bajo las cifras.
	var actions: HBoxContainer = _footer
	if CT.portrait():
		actions = HBoxContainer.new()
		actions.name = "FooterActions"
		actions.add_theme_constant_override("separation", 8)
		foot_col.add_child(actions)
	var morale := _foot_chip("res:morale")
	_morale_label = morale.get_child(1)
	var commit := _foot_chip("army")
	_commit_label = commit.get_child(1)

	# Convocar el Ataque Final es la ultima decision de la partida, y se toma
	# aqui, donde se decide pelear. No arranca solo.
	_audit_btn = CT.pill_button(Tr.t("BTN_AUDIT_BEGIN"), "storm", "danger", CT.h("big"))
	_audit_btn.name = "AuditButton"
	_audit_btn.pressed.connect(_on_audit_pressed)
	_audit_btn.visible = false
	actions.add_child(_audit_btn)

	# RESOLVER SOLO (D6 = A): solo en incursiones y solo si la columna dobla al
	# enemigo. Apagado con el motivo en el tooltip cuando no llega.
	_auto_btn = CT.pill_button(Tr.t("BTN_AUTO_RESOLVE"), "raid", "secondary", CT.h("big"), "window", "small")
	_auto_btn.name = "AutoResolveButton"
	_auto_btn.pressed.connect(_on_auto_pressed)
	_auto_btn.visible = false
	actions.add_child(_auto_btn)

	_launch_btn = CT.pill_button(Tr.t("ARMY2_BTN_ATTACK"), "missions", "primary", CT.h("big"))
	_launch_btn.name = "LaunchButton"
	# El tutorial senala ¡A LA MISION! en la primera batalla (HelpTargets "mission_launch").
	_launch_btn.add_to_group("hud_mission_launch")
	_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_btn.pressed.connect(_on_launch_pressed)
	actions.add_child(_launch_btn)

	_dev_btn = CT.pill_button(Tr.t("BTN_DEV_SKIRMISH"), "", "secondary", 48, "window", "small")
	_dev_btn.pressed.connect(func(): if CombatManager.dev_start_encounter(): _close())
	actions.add_child(_dev_btn)

	# Un boton apagado sin motivo es un bug a ojos del jugador. El motivo va
	# debajo, escrito, siempre que `can_launch` diga que no.
	_reason_label = CT.label("", "small", CT.tone_color("warning"))
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason_label.visible = false
	foot_col.add_child(_reason_label)
	_audit_reason = CT.label("", "small", CT.tone_color("warning"))
	_audit_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_audit_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audit_reason.visible = false
	foot_col.add_child(_audit_reason)

	_fit()
	_refresh()

## [icono] cifra en el pie, con el detalle al mantener pulsado.
func _foot_chip(glyph: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := CT.make_glyph(glyph, 26 if CT.phone else 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(ic)
	var l := CT.label("", "number", CT.text("window"))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(l)
	_footer.add_child(chip)
	return chip

## El scroll de la tropa medio 300 de serie en la 1.1; en un telefono apaisado
## (lienzo de ~400 de alto) el panel no cabia (ronda visual de la 1.1). La
## ventana nueva reparte el alto sola, pero la cuenta sigue aqui para quien la use.
const UNITS_SCROLL_H := 300.0
const UNITS_SCROLL_MIN_H := 90.0

static func units_scroll_height(vp_h: float, chrome_h: float) -> float:
	return clampf(vp_h - 32.0 - chrome_h, UNITS_SCROLL_MIN_H, UNITS_SCROLL_H)

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _phone() -> bool:
	return CT.is_phone()

func _fit() -> void:
	CT.fit_window(_win, _vp(), MAX_SIZE)
	if _troop_card != null:
		_troop_card.custom_minimum_size.x = 280.0 if _phone() else 380.0
		_troop_title.visible = not _phone()

func _on_viewport_resized() -> void:
	_fit()
	if _is_open:
		_refresh()

# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _commit_label:
		return
	_prune_selection()
	var cap: int = GameConfig.combat_deploy_cap
	var on_campaign: bool = has_expedition()

	_commit_label.text = "%d/%d" % [_committed(), cap]
	_commit_label.get_parent().tooltip_text = Tr.t("LBL_DEPLOY_CAP") % [_committed(), cap]
	_commit_label.get_parent().visible = not on_campaign

	# La moral con la que se pelea es la que tenia el pueblo cuando la columna
	# salio, no la de ahora: con expedicion en curso se muestra esa.
	var morale: float = _current_morale()
	_morale_label.text = str(roundi(morale))
	_morale_label.get_parent().tooltip_text = Tr.t("LBL_MORALE_COMBAT") % [
		roundi(morale),
		CombatRules.morale_initiative_bonus(morale),
		CombatRules.morale_attack_mod(morale),
	]

	_refresh_audit_button()
	_dev_btn.visible = GameConfig.dev_mode and not on_campaign

	if on_campaign:
		_sortie_box.visible = false
		_empty_label.visible = false
		_launch_btn.visible = false
		_auto_btn.visible = false
		_reason_label.visible = false
		_campaign_box.visible = true
		_refresh_campaign()
		return

	_campaign_box.visible = false
	_launch_btn.visible = true
	_sortie_box.visible = true
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
	for child in _campaign_party.get_children():
		_campaign_party.remove_child(child)
		child.queue_free()
	var away: Dictionary = _units_on_expedition()
	var discs := CT.roster_discs(away, CT.sem("POSITIVE"), 40 if _phone() else 48)
	_campaign_party.add_child(discs)
	_campaign_party.tooltip_text = Tr.t("LBL_EXPEDITION_PARTY") % _unit_list(away)

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

# ── Tu tropa ─────────────────────────────────────────────────────────

## Las filas van por medio (Tierra, Mar, Aire). En una campana, solo las de su
## medio; en los ataques rapidos, con su icono de medio delante. Los barcos, si
## la salida elegida no tiene agua, salen con el motivo y sin poder elegirse.
func _rebuild_units(available: Dictionary) -> void:
	for child in _units_vbox.get_children():
		_units_vbox.remove_child(child)
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
				var none := CT.icon_line("lock", Tr.t("CAMP_NO_UNITS_" + camp.to_upper()), "warning")
				none.name = "CampaignNoUnits"
				_units_vbox.add_child(none)
			continue
		var blocked: bool = domain == CombatUnit.DOMAIN_SEA and not water and camp == ""
		if camp == "":
			var header := CT.icon_line(String(DOMAIN_GLYPH.get(domain, "army")),
				Tr.t(String(DOMAIN_TAB_KEY.get(domain, "ARMY2_TAB_LAND"))), "", "window", "small")
			header.name = "DomainHeader_" + domain
			_units_vbox.add_child(header)
		if blocked:
			var why := CT.icon_line("anchor", Tr.t("LBL_SHIPS_NEED_WATER"), "warning")
			why.name = "ShipsNeedWater"
			_units_vbox.add_child(why)
		for unit_id in ids:
			var unit_block: bool = blocked
			if camp != "" and CombatManager.campaign_unit_block(String(unit_id), camp) != "":
				unit_block = true
			var block_text: String = ""
			if unit_block and camp != "":
				block_text = Tr.t(CombatManager.campaign_unit_block(String(unit_id), camp))
			_units_vbox.add_child(_make_unit_row(unit_id, int(available[unit_id]), unit_block, block_text))

## [disco] Soldado        [−] 3 [+]
##         en casa: 6
func _make_unit_row(unit_id: String, owned: int, blocked: bool = false, block_text: String = "") -> HBoxContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var picked: int = int(_selection.get(unit_id, 0))
	var ph := _phone()
	var row := HBoxContainer.new()
	row.name = "Troop_" + unit_id
	row.add_theme_constant_override("separation", 6)

	var disc := CT.unit_disc(unit_id, CT.sem("POSITIVE") if not blocked else CT.kind_fill("disabled"), 38 if ph else 46)
	disc.mouse_filter = Control.MOUSE_FILTER_PASS
	# Las cifras de combate al mantener pulsado (es una decision tactica).
	var stats := GameConfig.get_combat_stats(unit_id)
	var r_min := int(stats.get("min_range", 1))
	var r_max := int(stats.get("range", 1))
	var reach := str(r_max) if r_min == r_max else "%d-%d" % [r_min, r_max]
	disc.tooltip_text = Tr.t("FMT_UNIT_STATS_LINE") % [
		int(stats.get("hp", 0)), int(stats.get("atk", 0)), int(stats.get("def", 0)),
		int(stats.get("move", 0)), reach,
	] + "\n" + Tr.t("LBL_COMBAT_STATS_HINT")
	row.add_child(disc)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	# El nombre entero (antes se cortaba: "Infanteri"); en telefono, un punto
	# mas pequeno para que quepa junto a − n +.
	var name_label := CT.label(Tr.t(def.get("name", unit_id)), "body" if ph else "button", CT.text("window", blocked))
	name_label.name = "UnitName"
	info.add_child(name_label)
	var sub_text: String = block_text if (blocked and block_text != "") else Tr.t("ARMY2_HOME_N") % owned
	var sub := CT.label(sub_text, "small", CT.tone_color("warning") if blocked else CT.text("window", true))
	sub.name = "CombatStats"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub)
	row.add_child(info)

	var h := 48 if ph else CT.BTN_SMALL
	var minus := CT.pill_button("", "minus", "secondary", h)
	minus.name = "Minus"
	minus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minus.disabled = picked <= 0
	minus.pressed.connect(_adjust.bind(unit_id, -1))
	row.add_child(minus)

	var count_label := CT.label(str(picked), "number", CT.text("window"))
	count_label.name = "Picked"
	count_label.custom_minimum_size.x = 24
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_label)

	var plus := CT.pill_button("", "plus", "open", h)
	plus.name = "Plus"
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.disabled = blocked or picked >= owned or _committed() >= GameConfig.combat_deploy_cap
	if blocked:
		plus.tooltip_text = block_text if block_text != "" else Tr.t("LBL_SHIPS_NEED_WATER")
	plus.pressed.connect(_adjust.bind(unit_id, 1))
	row.add_child(plus)
	return row

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
		CT.set_pill_text(_audit_btn, Tr.t("BTN_AUDIT_BEGIN"))
		_audit_btn.visible = true
		_audit_btn.disabled = blocked != ""
	elif ProgressionManager.is_final_audit_lost():
		CT.set_pill_text(_audit_btn, Tr.t("BTN_AUDIT_RESUMMON"))
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
	_holder.visible = true
	# La primera escaramuza: el soldado de casa ya va elegido, basta con ¡A LA
	# MISION! (tutorial corto, 2026-10-24; antes habia que sumarlo con +).
	if CombatManager.is_first_sortie_due() and _party().is_empty():
		var first: Dictionary = Objectives.first_sortie_party()
		for unit_id in first:
			_selection[unit_id] = int(first[unit_id])
	_fit()
	_refresh()
	UIManager.open_panel(self)
	# Mirar el tablon apaga el punto rojo de "salida nueva".
	CombatManager.mark_sorties_seen()

## Lo abre el boton MISIONES (barra de abajo, SkirmishButton) y ☰. Si ya esta
## abierto, no lo cierra.
func open() -> void:
	if not _is_open:
		_open()

func is_open() -> bool:
	return _is_open

func _close() -> void:
	_is_open = false
	_holder.visible = false
	UIManager.close_panel(self)

# ── La mision elegida (doc 21 §3.3-3.5) ──────────────────────────────

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

## Rehace la cabecera (pestanas y lo que falta para el Ataque Final) y la
## tarjeta de la mision elegida.
func _rebuild_sorties(offer: Dictionary, preview: Dictionary) -> void:
	for box in [_head_box, _mission_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var first: bool = CombatManager.is_first_sortie_due()
	# Tres campanas: las pestanas y lo que falta para el Ataque Final. Mientras
	# toca la primera escaramuza, nada de esto.
	if not first:
		_add_tabs()
		_add_gate_line()
	_head_box.visible = _head_box.get_child_count() > 0
	# La rebaja del Diezmo ya ganada, para que se vea que sirvio.
	var cut: int = CombatManager.get_tithe_cut_pct()
	var domain: String = current_campaign()
	if domain != "":
		_add_campaign_header(domain)
	elif not first:
		var offers: Array = CombatManager.get_sortie_offers()
		if offers.is_empty():
			_mission_box.add_child(CT.icon_line("clock", Tr.t("LBL_SORTIE_NONE"), "", "window", "body"))
		else:
			var row := HFlowContainer.new()
			row.name = "Offers"
			row.add_theme_constant_override("h_separation", 6)
			row.add_theme_constant_override("v_separation", 6)
			for entry in offers:
				row.add_child(_make_offer_button(entry, int(entry.get("id", 0)) == int(offer.get("id", -1))))
			_mission_box.add_child(row)
	if not preview.is_empty():
		_fill_detail(offer, preview)
	if cut > 0:
		_mission_box.add_child(CT.icon_line("star", Tr.t("LOOT_TITHE_CUT") % cut, "positive"))

## Un boton por ataque rapido: su nombre; el tipo al mantener pulsado. La
## elegida, azul.
func _make_offer_button(offer: Dictionary, selected: bool) -> Button:
	var offer_name: String = Tr.t(ExpeditionGenerator.offer_name_key(offer))
	var fights: int = ExpeditionGenerator.fights_on_path(CombatManager.offer_map(offer))
	var btn := CT.pill_button(offer_name, "raid" if fights <= 1 else "missions",
		"open" if selected else "secondary", 48 if _phone() else CT.BTN_SMALL, "window", "small")
	btn.name = "Offer_%d" % int(offer.get("id", 0))
	btn.tooltip_text = _kind_text(offer, fights)
	btn.pressed.connect(select_offer.bind(int(offer.get("id", 0))))
	return btn

func _kind_text(offer: Dictionary, fights: int) -> String:
	if String(offer.get("kind", "")) == ExpeditionGenerator.KIND_CAMPAIGN:
		return Tr.t("CAMP_KIND_FIGHTS") % fights
	if String(offer.get("kind", "")) == ExpeditionGenerator.KIND_EXPEDITION:
		return Tr.t("SORTIE_KIND_EXPEDITION") % fights
	return Tr.t("SORTIE_KIND_RAID")

## La tarjeta de la mision elegida, iconos y cifras delante:
##   Mision 3 · El vado                    [Favorable]
##   [enemigos del primer combate] [N combates]   [botin]
## El mapa entero (que hay en cada combate), al mantener pulsado.
func _fill_detail(offer: Dictionary, preview: Dictionary) -> void:
	var ph := _phone()
	var camp_domain: String = String(preview.get("campaign_domain", ""))
	var fights: int = int(preview.get("fights", 1))

	# Nombre de la mision y el pronostico.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title_text: String = Tr.t(String(preview.get("name_key", "")))
	if camp_domain != "" and offer.has("mission"):
		title_text = "%s · %s" % [Tr.t("ARMY2_MISSION_N") % (int(offer.get("mission", 0)) + 1), title_text]
	var title := CT.label(title_text, "title", CT.text("window"))
	title.name = "MissionTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	# Donde es (tierra, costa, cielo) y el aviso del jefe: al mantener pulsado.
	var where_lines: Array = [_kind_text(offer, fights)]
	if camp_domain != "":
		where_lines.append(Tr.t("CAMP_WHERE_" + camp_domain.to_upper()))
	elif bool(preview.get("coastal", false)):
		where_lines.append(Tr.t("LBL_SORTIE_COASTAL"))
	title.tooltip_text = "\n".join(where_lines)
	head.add_child(title)
	if camp_domain == "" and bool(preview.get("coastal", false)):
		var coast := CT.make_glyph("anchor", 24)
		coast.name = "SortieCoastal"
		coast.mouse_filter = Control.MOUSE_FILTER_PASS
		coast.tooltip_text = Tr.t("LBL_SORTIE_COASTAL")
		coast.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(coast)
	# Sin nadie elegido no se dice "Dificil" en rojo: asusta y no es verdad
	# todavia (ronda de pruebas 1.0). Se dice que hacer.
	var odds_badge: PanelContainer
	if roundi(float(preview.get("player_power", 0.0))) <= 0:
		odds_badge = CT.odds_badge("", Tr.t("ARMY2_PICK_TROOPS"))
		odds_badge.tooltip_text = Tr.t("ODDS_PICK_FIRST")
	else:
		var odds: String = String(preview.get("odds", "even"))
		odds_badge = CT.odds_badge(odds, Tr.t(String(ODDS_KEYS.get(odds, "ODDS_EVEN"))))
		odds_badge.tooltip_text = Tr.t("LBL_SORTIE_STRENGTH") % [
			roundi(float(preview.get("player_power", 0.0))), roundi(float(preview.get("enemy_power", 0.0)))]
	odds_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(odds_badge)
	_mission_box.add_child(head)

	# Enemigos (los del primer combate; el mapa entero al mantener) y botin.
	var map: Array = preview.get("map", [])
	var layers: Array = preview.get("layers", [])
	var row := HFlowContainer.new()
	row.name = "EnemiesAndLoot"
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 4)
	var enemies := HBoxContainer.new()
	enemies.name = "Enemies"
	enemies.add_theme_constant_override("separation", 4)
	enemies.mouse_filter = Control.MOUSE_FILTER_PASS
	enemies.tooltip_text = "%s\n%s" % [Tr.t("ARMY2_ENEMY_TIP"), "\n".join(_layer_lines(map, layers))]
	var first_roster: Dictionary = {}
	var has_boss := false
	for i in range(layers.size()):
		for index in layers[i]:
			if bool(map[int(index)].get("is_boss", false)):
				has_boss = true
	if not layers.is_empty() and not (layers[0] as Array).is_empty():
		first_roster = map[int(layers[0][0])].get("enemy_roster", {})
	enemies.add_child(CT.roster_discs(first_roster, CT.sem("DANGER"), 36 if ph else 46))
	if fights > 1:
		var many := CT.badge(Tr.t("ARMY2_FIGHTS_N") % fights, CT.c("window", "CARD_ALT"), "missions")
		many.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		enemies.add_child(many)
	if has_boss:
		var boss := CT.make_glyph("demolish", 30 if ph else 36)
		boss.name = "SortieBoss"
		boss.mouse_filter = Control.MOUSE_FILTER_PASS
		boss.tooltip_text = Tr.t("LBL_SORTIE_BOSS")
		boss.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		enemies.add_child(boss)
	row.add_child(enemies)

	# El botin: recursos con su icono y, lo exclusivo, una estrella con su lista.
	var loot := HBoxContainer.new()
	loot.name = "SortieLoot"
	loot.add_theme_constant_override("separation", 4)
	loot.mouse_filter = Control.MOUSE_FILTER_PASS
	loot.tooltip_text = Tr.t("ARMY2_LOOT_TIP")
	var rewards: Dictionary = preview.get("rewards", {})
	if not rewards.is_empty():
		var chips := CT.cost_row(rewards, {}, "+")
		chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		loot.add_child(chips)
	var extra: Array = loot_lines(preview.get("loot", {}))
	if not extra.is_empty():
		var star := CT.badge("+%d" % extra.size(), CT.sem("ACCENT"), "star")
		star.mouse_filter = Control.MOUSE_FILTER_PASS
		star.tooltip_text = "\n".join(extra)
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		loot.add_child(star)
		loot.tooltip_text += "\n" + "\n".join(extra)
	if loot.get_child_count() > 0:
		row.add_child(loot)
	_mission_box.add_child(row)

## Las lineas del mapa de una salida: "Combate 1: 3 Soldado o 2 Canon", ...
func _layer_lines(map: Array, layers: Array) -> Array:
	var lines: Array = []
	for i in range(layers.size()):
		var is_boss_layer := false
		var options: Array = []
		for index in layers[i]:
			var node: Dictionary = map[int(index)]
			if bool(node.get("is_boss", false)):
				is_boss_layer = true
			options.append(_unit_list(node.get("enemy_roster", {})))
		var lead: String = Tr.t("LBL_SORTIE_BOSS") if is_boss_layer else Tr.t("LBL_SORTIE_FIGHT_N") % (i + 1)
		lines.append("%s: %s" % [lead, (" %s " % Tr.t("LBL_SORTIE_OR")).join(options)])
	return lines

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

## Lo que falta para el Ataque Final, como lista de comprobacion: CG nivel 3 y
## cada campana, con ✓ lo hecho y candado lo que falta. Solo mientras falte
## algo (y el modo tenga asedio). La frase entera, al mantener pulsado.
func _add_gate_line() -> void:
	var text: String = ProgressionManager.final_audit_gate_text()
	if text == "":
		return
	var gate := HFlowContainer.new()
	gate.name = "AuditGateLine"
	gate.add_theme_constant_override("h_separation", 10)
	gate.add_theme_constant_override("v_separation", 2)
	gate.mouse_filter = Control.MOUSE_FILTER_PASS
	gate.tooltip_text = text
	var lead := HBoxContainer.new()
	lead.add_theme_constant_override("separation", 4)
	lead.add_child(CT.make_glyph("storm", 22))
	lead.add_child(CT.label(Tr.t("ARMY2_GATE") + ":", "small", CT.text("window")))
	gate.add_child(lead)
	gate.add_child(_gate_item(ProgressionManager.milestones_completed.has("hq_max"), Tr.t("ARMY2_GATE_HQ")))
	if GameMode.audit_needs_campaigns():
		for domain in GameConfig.CAMPAIGN_DOMAINS:
			var d := String(domain)
			var done: bool = CombatManager.is_campaign_complete(d)
			var word := Tr.t(String(DOMAIN_TAB_KEY.get(d, "ARMY2_TAB_LAND")))
			if not done:
				word += " %d/%d" % [CombatManager.campaign_won(d), CombatManager.campaign_total(d)]
			gate.add_child(_gate_item(done, word))
	_head_box.add_child(gate)

func _gate_item(done: bool, text: String) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 3)
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	item.set_meta("done", done)
	item.add_child(CT.make_glyph("check" if done else "lock", 20))
	item.add_child(CT.label(text, "small", CT.tone_color("positive") if done else CT.text("window", true)))
	return item

## Las cuatro pestanas: Tierra, Mar y Aire (candado sin su edificio, ✓ hecha) y
## los ataques rapidos del tablon. En telefono, las no elegidas solo con icono.
func _add_tabs() -> void:
	var ph := _phone()
	var row := HBoxContainer.new()
	row.name = "CampaignTabs"
	row.add_theme_constant_override("separation", 6)
	_head_box.add_child(row)
	var current: String = current_tab()
	for domain in GameConfig.CAMPAIGN_DOMAINS:
		var d: String = String(domain)
		var lock: String = CombatManager.campaign_lock_reason(d)
		var glyph: String = DOMAIN_GLYPH.get(d, "missions")
		var status: String = "%d/%d" % [CombatManager.campaign_won(d), CombatManager.campaign_total(d)]
		if lock == "CAMP_LOCK_BUILDING":
			glyph = "lock"
			status = Tr.t("CAMP_TAB_LOCKED")
		elif CombatManager.is_campaign_complete(d):
			glyph = "check"
			status = Tr.t("CAMP_TAB_DONE")
		var word := Tr.t(String(DOMAIN_TAB_KEY.get(d, "ARMY2_TAB_LAND")))
		var tip := "%s · %s\n%s" % [Tr.t("CAMP_NAME_" + d.to_upper()), status, Tr.t("CAMP_BLURB_" + d.to_upper())]
		if lock == "CAMP_LOCK_BUILDING":
			tip += "\n" + Objectives.campaign_lock_text(d)
		row.add_child(_make_tab_button("CampaignTab_" + d, word, glyph, d, current == d, ph, tip))
	var raids: int = CombatManager.get_sortie_offers().size()
	row.add_child(_make_tab_button("CampaignTab_raids", Tr.t("ARMY2_TAB_RAIDS"), "raid", TAB_RAIDS,
		current == TAB_RAIDS, ph, "%s: %d" % [Tr.t("ARMY2_TAB_RAIDS"), raids]))
	# En telefono, "3 de 6" a la derecha de las pestanas (en PC va en la tarjeta).
	var camp := current_campaign()
	# En vertical no cabe junto a las pestanas: va en la tarjeta (como en PC).
	if ph and camp != "" and not CT.portrait():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
		var progress := CT.label(Tr.t("CAMP_PROGRESS") % [CombatManager.campaign_won(camp), CombatManager.campaign_total(camp)],
			"small", CT.text("window", true))
		row.add_child(progress)

func _make_tab_button(node_name: String, word: String, glyph: String, tab: String, selected: bool,
		phone: bool, tip: String) -> Button:
	var btn := CT.tab(word if (selected or not phone) else "", glyph, selected, "window",
		CT.sem("POSITIVE") if selected else Color(0, 0, 0, 0), 48 if phone else CT.BTN)
	btn.name = node_name
	if phone and not selected:
		btn.custom_minimum_size.x = 56
	btn.tooltip_text = tip
	btn.pressed.connect(select_tab.bind(tab))
	return btn

## La cabecera de la campana elegida, dentro de la tarjeta: su nombre y "3 de 6"
## (PC), el recorrido de misiones (hechas, la que toca y el jefe al final) y, si
## no se puede salir, por que.
func _add_campaign_header(domain: String) -> void:
	var ph := _phone()
	var won: int = CombatManager.campaign_won(domain)
	var total: int = CombatManager.campaign_total(domain)
	if not ph or CT.portrait():
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var title := CT.label(Tr.t("CAMP_NAME_" + domain.to_upper()), "small", CT.text("window", true))
		title.name = "CampaignTitle"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(CT.label(Tr.t("CAMP_PROGRESS") % [won, total], "small", CT.text("window", true)))
		_mission_box.add_child(head)
	var boss_tip := Tr.t("LBL_SORTIE_BOSS")
	var track := CT.campaign_track(won, total, ph, boss_tip)
	track.tooltip_text = Tr.t("CAMP_BLURB_" + domain.to_upper())
	_mission_box.add_child(track)
	# El Leviatan pide acorazados: se dice antes de llegar a el (docs/15 §13).
	var need: String = Objectives.campaign_boss_need_text(domain)
	if need != "":
		var need_line := CT.icon_line("demolish", need, "warning")
		need_line.name = "CampaignBossNeed"
		_mission_box.add_child(need_line)
	var lock: String = CombatManager.campaign_lock_reason(domain)
	if lock != "":
		var done: bool = lock == "CAMP_DONE"
		var why := CT.icon_line("check" if done else "lock", _campaign_lock_text(domain), "positive" if done else "warning")
		why.name = "CampaignLock"
		_mission_box.add_child(why)

## El candado de una campana en palabras, con su cifra: "Construye un Astillero",
## "Llega a la era 3", "La tropa descansa: 1:20".
func _campaign_lock_text(domain: String) -> String:
	var text: String = Objectives.campaign_lock_text(domain)
	# Los motivos de can_launch (columna fuera, asedio...) ya vienen traducidos.
	return text
