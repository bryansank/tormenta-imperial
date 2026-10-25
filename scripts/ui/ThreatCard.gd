extends CanvasLayer
## La tarjeta corta de una amenaza de costa (feat/amenazas-costa): sale al tocar
## su marca en el mapa (EventBus.threat_clicked). Que es, cuanto le queda, que
## enemigos trae, el botin y ¡AL ATAQUE! (abre MISIONES > ATAQUES RAPIDOS con
## ella elegida, para escoger la tropa) o EXPLORAR (el pecio, con trabajadores).
##
## La crea SkirmishPanel (su hijo, en las dos escenas). Solo lee ThreatManager y
## le llama; el unico reloj es el de la cuenta atras, y solo con la tarjeta a la
## vista (1 vez por segundo).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const ICON_PX := 24

var _panel: PanelContainer
var _box: VBoxContainer
var _tick: Timer
var _threat_id: int = 0

func _ready() -> void:
	layer = 12
	name = "ThreatCard"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.name = "ThreatCardPanel"
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(UITheme.touch_px(380.0), 0)
	# Encima de la barra de CONSTRUIR.
	_panel.offset_bottom = -UITheme.touch_px(150.0)
	_panel.visible = false
	root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(_refresh)
	add_child(_tick)
	EventBus.threat_clicked.connect(show_threat)
	EventBus.threats_changed.connect(func(): if _panel.visible: _refresh())
	EventBus.encounter_started.connect(func(_i, _b): close())
	EventBus.building_clicked.connect(func(_n, _d): close())
	EventBus.building_selected_for_placement.connect(func(_d): close())

## Abre la tarjeta de `threat_id` (y la da por vista: se apaga su sugerencia).
func show_threat(threat_id: int) -> void:
	_threat_id = threat_id
	if ThreatManager.get_threat(threat_id).is_empty():
		close()
		return
	ThreatManager.mark_seen(threat_id)
	_panel.visible = true
	_tick.start()
	_refresh()

func close() -> void:
	_threat_id = 0
	if _panel != null:
		_panel.visible = false
	if _tick != null:
		_tick.stop()

func is_open() -> bool:
	return _panel != null and _panel.visible

func current_threat() -> int:
	return _threat_id

func _refresh() -> void:
	var threat: Dictionary = ThreatManager.get_threat(_threat_id)
	if threat.is_empty():
		close()
		return
	for child in _box.get_children():
		child.queue_free()
	var threat_type: String = String(threat.get("type", ""))
	var water: bool = bool(threat.get("water", false))
	var domain: String = "sea" if water else "land"
	var name_key: String = Generator.threat_name_key(threat_type, domain)
	_box.add_child(UITheme.make_panel_header(Tr.t(name_key), close))

	var desc := UITheme.make_label(Tr.t(name_key.replace("THREAT_NAME_", "THREAT_DESC_")), "small", UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(desc)

	# Cuanto le queda (o cuanto falta para volver del pecio).
	var left: int = ceili(ThreatManager.seconds_left(_threat_id))
	var exploring: bool = String(threat.get("state", "")) == ThreatBoard.STATE_EXPLORING
	var engaged: bool = String(threat.get("state", "")) == ThreatBoard.STATE_ENGAGED
	var time_key: String = "THREAT_EXPLORING_LEFT" if exploring else ("THREAT_ENGAGED_NOW" if engaged else "THREAT_TIME_LEFT")
	var time_label := UITheme.make_label(Tr.t(time_key).replace("{t}", "%d:%02d" % [left / 60, left % 60]), "section", UITheme.WARNING)
	time_label.name = "ThreatTimeLeft"
	_box.add_child(time_label)

	var offer: Dictionary = ThreatBoard.offer_for(ThreatManager.get_board().get_threat(_threat_id))
	if Generator.threat_is_fight(threat_type):
		var map: Array = Generator.threat_map(offer)
		if not map.is_empty():
			var enemies := HFlowContainer.new()
			enemies.add_theme_constant_override("h_separation", 6)
			enemies.add_child(UITheme.make_label(Tr.t("THREAT_ENEMIES") + ":", "small", UITheme.ACCENT))
			_add_roster(enemies, map[0].get("enemy_roster", {}))
			_box.add_child(enemies)
		# Como se ve con lo mejor que hay en casa de su medio.
		var party: Dictionary = ThreatManager.best_party(domain)
		if not party.is_empty():
			var preview: Dictionary = CombatManager.sortie_preview(offer, party)
			var odds: String = String(preview.get("odds", "even"))
			var odds_key: String = {"favorable": "ODDS_FAVORABLE", "hard": "ODDS_HARD"}.get(odds, "ODDS_EVEN")
			var odds_label := UITheme.make_label(Tr.t("THREAT_ODDS") % Tr.t(odds_key), "small",
				UITheme.POSITIVE if odds == "favorable" else (UITheme.DANGER if odds == "hard" else UITheme.WARNING))
			odds_label.name = "ThreatOdds"
			_box.add_child(odds_label)
	else:
		var need := UITheme.make_label(Tr.t("THREAT_EXPLORE_NEED") % [GameConfig.threat_wreck_workers,
			ceili(GameConfig.get_duration(GameConfig.threat_wreck_explore_seconds))], "small", UITheme.TEXT)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(need)

	# El botin: oro/madera/acero y lo exclusivo (repuestos, material).
	var loot_row := HFlowContainer.new()
	loot_row.name = "ThreatLoot"
	loot_row.add_theme_constant_override("h_separation", 10)
	loot_row.add_child(UITheme.make_label(Tr.t("LBL_SORTIE_LOOT") + ":", "small", UITheme.ACCENT))
	var rewards: Dictionary = ThreatManager.rewards_of(_threat_id)
	for res_name in rewards:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.add_child(UITheme.make_icon(String(res_name), ICON_PX))
		chip.add_child(UITheme.make_label("+%d" % int(rewards[res_name]), "small", UITheme.resource_color(String(res_name))))
		loot_row.add_child(chip)
	var panel_script: Script = load("res://scripts/ui/SkirmishPanel.gd")
	for text in panel_script.loot_lines(ThreatManager.loot_of(_threat_id)):
		loot_row.add_child(UITheme.make_label(String(text), "small", UITheme.POSITIVE))
	_box.add_child(loot_row)

	# La accion, con su motivo escrito si no se puede.
	var btn := Button.new()
	btn.name = "ThreatAction"
	btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	var reason: String = ""
	if Generator.threat_is_fight(threat_type):
		btn.text = Tr.t("BTN_THREAT_ATTACK")
		reason = ThreatManager.attack_block_reason(_threat_id)
		UITheme.style_button(btn, UITheme.DANGER, UITheme.FONT_BUTTON)
		btn.pressed.connect(_on_attack_pressed)
	else:
		btn.text = Tr.t("BTN_THREAT_EXPLORE")
		reason = ThreatManager.explore_block_reason(_threat_id)
		UITheme.style_button(btn, UITheme.POSITIVE.darkened(0.25), UITheme.FONT_BUTTON)
		btn.pressed.connect(_on_explore_pressed)
	btn.disabled = reason != ""
	_box.add_child(btn)
	if reason != "":
		var why := UITheme.make_label(Tr.t(reason), "small", UITheme.WARNING)
		why.name = "ThreatReason"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(why)
	var safe := UITheme.make_label(Tr.t("THREAT_HARMLESS"), "small", UITheme.TEXT_DIM)
	safe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(safe)

func _add_roster(line: Container, roster: Dictionary) -> void:
	for unit_id in GameConfig.get_unit_ids():
		var count: int = int(roster.get(unit_id, 0))
		if count <= 0:
			continue
		var icon := TextureRect.new()
		icon.texture = UITheme.unit_icon(String(unit_id), ICON_PX)
		icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UITheme.unit_icon_tint(false)
		icon.tooltip_text = Tr.t(String(GameConfig.get_unit_def(String(unit_id)).get("name", unit_id)))
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(icon)
		line.add_child(UITheme.make_label("x%d" % count, "small", UITheme.TEXT))

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
