extends CanvasLayer
## La tarjeta corta de una amenaza de costa (feat/amenazas-costa): sale al tocar
## su marca en el mapa (EventBus.threat_clicked). Que es, cuanto le queda, que
## enemigos trae, el botin y ¡AL ATAQUE! (abre MISIONES > ATAQUES RAPIDOS con
## ella elegida, para escoger la tropa) o EXPLORAR (el pecio, con trabajadores).
##
## v1.2 (integracion, docs/28): ficha de CartoonTheme como la del edificio, a la
## derecha y sin velo (la marca se sigue viendo), cinta roja (o azul el pecio),
## ✕ con el dodge del ☰, iconos y cifras delante y la frase larga al mantener
## pulsado. El contenido va en un scroll: en 640x360 no se sale. Sin animacion.
##
## La crea SkirmishPanel (su hijo, en las dos escenas). Solo lee ThreatManager y
## le llama; el unico reloj es el de la cuenta atras, y solo con la tarjeta a la
## vista (1 vez por segundo).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")
const ICON_PX := 24
## Ancho de la ficha (PC / telefono) y margen con el borde.
const CARD_W := 360.0
const CARD_W_PHONE := 330.0
const EDGE := 14.0
## Hueco arriba (el ☰ y la Tormenta) y abajo (la barra), telefono / PC.
const TOP_PHONE := 54.0
const TOP_PC := 84.0
const BOTTOM_PHONE := 8.0
const BOTTOM_PC := 96.0

var _root: Control
var _panel: Control
var _win: Dictionary = {}
var _box: VBoxContainer
var _scroll: ScrollContainer
var _tick: Timer
var _threat_id: int = 0

func _ready() -> void:
	layer = 12
	name = "ThreatCard"
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(_refresh)
	add_child(_tick)
	EventBus.threat_clicked.connect(show_threat)
	EventBus.threats_changed.connect(func(): if is_open(): _refresh())
	EventBus.encounter_started.connect(func(_i, _b): close())
	EventBus.building_clicked.connect(func(_n, _d): close())
	EventBus.building_selected_for_placement.connect(func(_d): close())
	get_viewport().size_changed.connect(func(): if is_open(): _place())

## Abre la tarjeta de `threat_id` (y la da por vista: se apaga su sugerencia).
func show_threat(threat_id: int) -> void:
	_threat_id = threat_id
	if ThreatManager.get_threat(threat_id).is_empty():
		close()
		return
	ThreatManager.mark_seen(threat_id)
	_tick.start()
	_refresh()

func close() -> void:
	_threat_id = 0
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	if _tick != null:
		_tick.stop()

func is_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and not _panel.is_queued_for_deletion()

func current_threat() -> int:
	return _threat_id

## La ventana se rehace entera en cada refresco (una vez por segundo como
## mucho, solo abierta): asi la cinta sigue al tipo y el contenido al estado.
func _refresh() -> void:
	var threat: Dictionary = ThreatManager.get_threat(_threat_id)
	if threat.is_empty():
		close()
		return
	var keep_scroll: int = _scroll.scroll_vertical if is_open() and _scroll != null else 0
	if _panel != null and is_instance_valid(_panel):
		_root.remove_child(_panel)
		_panel.queue_free()
	var phone := CT.is_phone()
	var threat_type: String = String(threat.get("type", ""))
	var water: bool = bool(threat.get("water", false))
	var domain: String = "sea" if water else "land"
	var name_key: String = Generator.threat_name_key(threat_type, domain)
	var fight: bool = Generator.threat_is_fight(threat_type)
	# La cinta, una palabra (el nombre entero no cabe en 290); el nombre, dentro.
	_win = CT.window(Tr.t("THREAT_RIBBON_FIGHT" if fight else "THREAT_RIBBON_WRECK"),
		CT.sem("DANGER") if fight else CT.sem("INFO"), true)
	_panel = _win["root"]
	_panel.name = "ThreatCardPanel"
	_root.add_child(_panel)
	(_win["close"] as Button).pressed.connect(close)
	var body: VBoxContainer = _win["body"]
	if phone:
		var s := CT.window_style()
		s.set_content_margin_all(8)
		(_win["panel"] as PanelContainer).add_theme_stylebox_override("panel", s)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	DragScroll.attach.call_deferred(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 4 if phone else 8)
	_scroll.add_child(_box)

	var title := CT.label(Tr.t(name_key), "button" if phone else "title", CT.text("window"))
	title.name = "ThreatName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(title)
	# Una frase; el resto al mantener pulsado.
	var desc := CT.para(Tr.t(name_key.replace("THREAT_NAME_", "THREAT_DESC_")), "window", true, "small")
	desc.name = "ThreatDesc"
	desc.tooltip_text = Tr.t("THREAT_HARMLESS")
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	_box.add_child(desc)

	# Cuanto le queda (o cuanto falta para volver del pecio).
	var left: int = ceili(ThreatManager.seconds_left(_threat_id))
	var exploring: bool = String(threat.get("state", "")) == ThreatBoard.STATE_EXPLORING
	var engaged: bool = String(threat.get("state", "")) == ThreatBoard.STATE_ENGAGED
	var time_key: String = "THREAT_EXPLORING_LEFT" if exploring else ("THREAT_ENGAGED_NOW" if engaged else "THREAT_TIME_LEFT")
	var time_line := CT.icon_line("clock", Tr.t(time_key).replace("{t}", "%d:%02d" % [left / 60, left % 60]), "warning", "window", "body")
	time_line.name = "ThreatTimeLeft"
	_box.add_child(time_line)

	var offer: Dictionary = ThreatBoard.offer_for(ThreatManager.get_board().get_threat(_threat_id))
	if fight:
		var map: Array = Generator.threat_map(offer)
		if not map.is_empty():
			var enemies := CT.roster_discs(map[0].get("enemy_roster", {}), CT.sem("DANGER"), 34 if phone else 42)
			enemies.name = "ThreatEnemies"
			enemies.tooltip_text = Tr.t("THREAT_ENEMIES")
			_box.add_child(enemies)
		# Como se ve con lo mejor que hay en casa de su medio.
		var party: Dictionary = ThreatManager.best_party(domain)
		if not party.is_empty():
			var preview: Dictionary = CombatManager.sortie_preview(offer, party)
			var odds: String = String(preview.get("odds", "even"))
			var odds_key: String = {"favorable": "ODDS_FAVORABLE", "hard": "ODDS_HARD"}.get(odds, "ODDS_EVEN")
			var badge := CT.odds_badge(odds, Tr.t(odds_key))
			badge.name = "ThreatOdds"
			badge.tooltip_text = Tr.t("THREAT_ODDS") % Tr.t(odds_key)
			badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_box.add_child(badge)
	else:
		var need := CT.icon_line("workers_off", Tr.t("THREAT_EXPLORE_NEED") % [GameConfig.threat_wreck_workers,
			ceili(GameConfig.get_duration(GameConfig.threat_wreck_explore_seconds))])
		need.name = "ThreatNeed"
		_box.add_child(need)

	# El botin: [icono] cifra por recurso; lo exclusivo (repuestos, material), en
	# una linea verde debajo.
	var rewards: Dictionary = ThreatManager.rewards_of(_threat_id)
	var loot_box := VBoxContainer.new()
	loot_box.name = "ThreatLoot"
	loot_box.add_theme_constant_override("separation", 2)
	_box.add_child(loot_box)
	if not rewards.is_empty():
		var row := CT.cost_row(rewards, {}, "+")
		row.tooltip_text = Tr.t("LBL_SORTIE_LOOT")
		loot_box.add_child(row)
	var panel_script: Script = load("res://scripts/ui/SkirmishPanel.gd")
	for text in panel_script.loot_lines(ThreatManager.loot_of(_threat_id)):
		loot_box.add_child(CT.icon_line("star", String(text), "positive"))

	# La accion, con su motivo escrito debajo si no se puede.
	var reason: String = ""
	var btn: Button
	if fight:
		reason = ThreatManager.attack_block_reason(_threat_id)
		btn = CT.text_button(Tr.t("BTN_THREAT_ATTACK"), "raid", "primary" if reason == "" else "disabled", CT.menu_h("btn"))
		btn.pressed.connect(_on_attack_pressed)
	else:
		reason = ThreatManager.explore_block_reason(_threat_id)
		btn = CT.text_button(Tr.t("BTN_THREAT_EXPLORE"), "anchor", "primary" if reason == "" else "disabled", CT.menu_h("btn"))
		btn.pressed.connect(_on_explore_pressed)
	btn.name = "ThreatAction"
	btn.disabled = reason != ""
	body.add_child(btn)
	if reason != "":
		var why := CT.icon_line("lock", Tr.t(reason), "warning")
		why.name = "ThreatReason"
		body.add_child(why)
	_place()
	_scroll.scroll_vertical = keep_scroll
	CT.dodge_menu_button.call_deferred(_win["close"])

## A la derecha, centrada en alto, con su tope: como la ficha del edificio.
func _place() -> void:
	if not is_open():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var phone := CT.is_phone()
	var w: float = minf(CARD_W_PHONE if phone else CARD_W, vp.x - EDGE * 2.0)
	# Debajo del ☰ (que no tape la ✕) y encima de la barra de abajo.
	var top: float = TOP_PHONE if phone else TOP_PC
	var h: float = minf(vp.y - top - (BOTTOM_PHONE if phone else BOTTOM_PC), 540.0)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(vp.x - w - EDGE, top)
	_panel.size = Vector2(w, h)

## ¡AL ATAQUE!: MISIONES se abre en ATAQUES RAPIDOS con esta amenaza elegida,
## para escoger la tropa (y ver Favorable / Dificil con la tropa elegida).
func _on_attack_pressed() -> void:
	var id: int = _threat_id
	var panel: Node = get_parent()
	close()
	if panel != null and panel.has_method("open_threat"):
		panel.open_threat(id)

func _on_explore_pressed() -> void:
	if ThreatManager.explore(_threat_id):
		_refresh()
	else:
		var why: String = ThreatManager.explore_block_reason(_threat_id)
		if why != "":
			EventBus.notification_posted.emit(Tr.t(why), "warning", UITheme.WARNING)
		_refresh()
