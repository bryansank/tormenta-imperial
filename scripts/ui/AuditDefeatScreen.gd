extends CanvasLayer
## El parte de un asedio perdido. Sale con `final_audit_lost` y dice tres cosas:
## que se perdio (el Diezmo maximo que se llevaron, los edificios que rompieron,
## la guarnicion que cayo), en que oleada, y que NO es el final: la Regencia se
## puede volver a convocar en cuanto haya `final_audit_resummon_min_units`
## unidades en pie.
##
## Lo que se llevaron no viaja en `final_audit_lost`: StormManager lo cobra al
## oirla y lo publica por `tithe_resolved` y `building_damaged/ruined`, en la
## misma cadena de llamadas. Quien conecte primero es cuestion de orden de
## `_ready`, asi que aqui no se supone nada: se apunta todo lo que llega en el
## mismo frame y el parte se monta diferido, cuando ya ha llegado todo.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28): ventana crema con cinta roja
## ASEDIO; titulo, la oleada en que cayo, lo perdido en iconos y lineas cortas,
## y lo que importa en verde: no es el final. REconstruir es el boton verde.

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const LAYER := 20
const CARD_WIDTH := 540.0

var _root: Control
var _win: Dictionary = {}
var _card: PanelContainer
var _icons: HFlowContainer
var _relayout_queued := false
var _wave_label: Label
var _lost_label: Label
var _resummon_label: Label
## Supervivencia: la variante "fin de la partida". Sin reconvocatoria, sin
## cerrar: solo empezar otra o salir.
var _title: Label
var _mode_label: Label
var _not_the_end: Label
var _run_over_label: Label
var _rebuild_btn: Button
var _end_row: HBoxContainer

## Lo ultimo que se apunto, con el frame en que llego.
var _tithe_frame: int = -1
var _tithe_taken: Dictionary = {}
var _hit_frame: int = -1
var _damaged: Dictionary = {}       ## instance_id -> true
var _ruined: Dictionary = {}        ## instance_id -> true
var _lost_frame: int = -1

func _ready() -> void:
	layer = LAYER
	# Mientras se ve, los avisos esperan (NotificationPanel.is_busy).
	add_to_group("modal_screen")
	_setup_ui()
	visible = false
	EventBus.final_audit_lost.connect(_on_final_audit_lost)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.building_damaged.connect(_on_building_damaged)
	EventBus.building_ruined.connect(_on_building_ruined)
	EventBus.game_load_completed.connect(_on_game_load_completed)
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Sin ✕: se sale con RECONSTRUIR (o, acabada la partida, con sus botones).
	_win = CT.modal_window(_root, Tr.t("ARMY2_SIEGE"), CT.sem("DANGER"), false)
	var veil: ColorRect = _win["veil"]
	veil.color = Color(veil.color, 0.7)
	_card = _win["panel"]
	_card.minimum_size_changed.connect(_queue_relayout)
	var column: VBoxContainer = _win["body"]
	column.add_theme_constant_override("separation", 6)

	column.add_child(ColonyByline.new("small", CT.text("window", true)))
	var title := _centered(CT.label(Tr.t("LBL_AUDIT_DEFEAT_TITLE"), "title", CT.tone_color("danger")))
	title.tooltip_text = Tr.t("AUDIT_TITLE")
	column.add_child(title)
	_title = title
	_mode_label = _centered(CT.label("", "small", CT.text("window", true)))
	column.add_child(_mode_label)
	_wave_label = _centered(CT.label("", "button", CT.text("window")))
	_wave_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_wave_label.tooltip_text = Tr.t("AUDIT_LOST")
	column.add_child(_wave_label)

	# Lo perdido: discos de la guarnicion caida y las lineas cortas.
	_icons = HFlowContainer.new()
	_icons.name = "LostIcons"
	_icons.alignment = FlowContainer.ALIGNMENT_CENTER
	_icons.add_theme_constant_override("h_separation", 8)
	_icons.mouse_filter = Control.MOUSE_FILTER_PASS
	_icons.tooltip_text = Tr.t("LBL_AUDIT_WHAT_WAS_LOST")
	column.add_child(_icons)
	_lost_label = _centered(CT.label("", "body", CT.text("window")))
	column.add_child(_lost_label)

	# Lo que mas importa, lo ultimo y en verde: no se ha perdido la partida.
	_not_the_end = _centered(CT.label(Tr.t("AUDIT_LOST_DESC"), "button", CT.tone_color("positive")))
	column.add_child(_not_the_end)
	_resummon_label = _centered(CT.label("", "small", CT.tone_color("warning")))
	column.add_child(_resummon_label)

	_rebuild_btn = CT.pill_button(Tr.t("BTN_AUDIT_REBUILD"), "wrench", "primary", CT.h("big"))
	_rebuild_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rebuild_btn.pressed.connect(close)
	column.add_child(_rebuild_btn)

	# Supervivencia: en vez de "reconstruye", "se acabo".
	_run_over_label = _centered(CT.label(Tr.t("LBL_RUN_OVER_DESC"), "body", CT.tone_color("warning")))
	column.add_child(_run_over_label)
	_end_row = HBoxContainer.new()
	_end_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_row.add_theme_constant_override("separation", 12)
	column.add_child(_end_row)
	var new_game := CT.pill_button(Tr.t("BTN_NEW_GAME"), "game", "primary", CT.h("big"))
	new_game.pressed.connect(_on_new_game)
	_end_row.add_child(new_game)
	var quit := CT.pill_button(Tr.t("BTN_QUIT"), "close", "danger", CT.h("big"))
	quit.pressed.connect(_on_quit)
	_end_row.add_child(quit)
	_apply_variant()
	_relayout()

static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## La tarjeta mide lo que su contenido; se recoloca cuando este cambia.
func _relayout() -> void:
	_relayout_queued = false
	if not is_inside_tree():
		return
	CT.fit_card(_win, get_viewport().get_visible_rect().size, CARD_WIDTH)

func _queue_relayout() -> void:
	if _relayout_queued:
		return
	_relayout_queued = true
	_relayout.call_deferred()

# ── Apuntes ──────────────────────────────────────────────────────────

func _frame() -> int:
	return Engine.get_process_frames()

func _on_tithe_resolved(repelled: bool, taken: Dictionary) -> void:
	if repelled:
		return
	_tithe_frame = _frame()
	_tithe_taken = taken.duplicate()

func _roll_hits() -> void:
	if _hit_frame != _frame():
		_hit_frame = _frame()
		_damaged.clear()
		_ruined.clear()

func _on_building_damaged(node: Node, _health: int, _max_health: int) -> void:
	_roll_hits()
	if node != null:
		_damaged[node.get_instance_id()] = true

func _on_building_ruined(node: Node) -> void:
	_roll_hits()
	if node != null:
		_ruined[node.get_instance_id()] = true

func _on_final_audit_lost(wave: int) -> void:
	_lost_frame = _frame()
	_show.call_deferred(wave, _lost_frame)

# ── Parte ────────────────────────────────────────────────────────────

## Monta y ensena el parte. `frame` es el del asedio perdido: solo cuenta lo que
## llego en ese mismo frame, para no mezclar un Diezmo viejo con esta derrota.
func _show(wave: int, frame: int) -> void:
	var taken: Dictionary = _tithe_taken if _tithe_frame == frame else {}
	var damaged: int = _damaged.size() if _hit_frame == frame else 0
	var ruined: int = _ruined.size() if _hit_frame == frame else 0
	var casualties: Dictionary = {}
	var total_waves: int = 0
	var audit = ProgressionManager.final_audit
	if audit != null:
		casualties = audit.result_summary().get("casualties", {})
		total_waves = audit.wave_count()
	_wave_label.text = Tr.t("LBL_AUDIT_FELL_AT") % (Tr.t("AUDIT_WAVE") % [wave + 1, maxi(total_waves, wave + 1)])
	_lost_label.text = "\n".join(loss_lines(taken, damaged, ruined, casualties))
	for child in _icons.get_children():
		_icons.remove_child(child)
		child.queue_free()
	var discs := CT.roster_discs(casualties, CT.kind_fill("disabled"), 40)
	if discs.get_child_count() > 0:
		_icons.add_child(discs)
	else:
		discs.queue_free()
	var resources: Dictionary = {}
	for key in taken:
		if key in ["gold", "wood", "steel", "oil"] and int(taken[key]) > 0:
			resources[key] = int(taken[key])
	if not resources.is_empty():
		_icons.add_child(CT.cost_row(resources, resources, "-"))
	_icons.visible = _icons.get_child_count() > 0
	_resummon_label.text = resummon_text()
	_apply_variant()
	_relayout()
	visible = true
	_queue_relayout()

func close() -> void:
	# Una partida terminada no se cierra: no hay nada detras a lo que volver.
	if GameMode.is_run_over():
		return
	visible = false

func is_showing() -> bool:
	return visible

## Las lineas de "lo que se perdio". Publico y sin estado para las pruebas.
static func loss_lines(taken: Dictionary, damaged: int, ruined: int, casualties: Dictionary) -> Array:
	var lines: Array = []
	var resources: Dictionary = {}
	for key in taken:
		if key in ["gold", "wood", "steel", "oil"] and int(taken[key]) > 0:
			resources[key] = int(taken[key])
	if not resources.is_empty():
		lines.append(Tr.t("LBL_TITHE_TOOK") % Tr.amount_list(resources))
	if int(taken.get("buildings", 0)) > 0:
		lines.append(Tr.t("LBL_TITHE_SEIZED_N") % int(taken["buildings"]))
	if int(taken.get("workers", 0)) > 0:
		lines.append(Tr.t("LBL_TITHE_WORKERS_N") % int(taken["workers"]))
	if damaged > 0 or ruined > 0:
		lines.append(Tr.t("LBL_AUDIT_DAMAGE") % [damaged, ruined])
	var dead: Array = []
	for unit_id in casualties:
		if int(casualties[unit_id]) > 0:
			dead.append("%d %s" % [int(casualties[unit_id]), Tr.t(GameConfig.get_unit_def(unit_id).get("name", unit_id))])
	if not dead.is_empty():
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), "   ".join(dead)])
	if lines.is_empty():
		lines.append(Tr.t("LBL_AUDIT_NOTHING_LOST"))
	return lines

## Cuanto falta para volver a llamarlos, o que ya se puede. Las cifras son del
## manager y de GameConfig.
static func resummon_text() -> String:
	var need: int = GameConfig.final_audit_resummon_min_units
	var standing: int = CombatManager.roster_size(CombatManager.get_garrison())
	if ProgressionManager.can_resummon_final_audit():
		return Tr.t("LBL_AUDIT_RESUMMON_READY")
	return "%s %s" % [Tr.t("AUDIT_RESUMMON_LOCKED") % need, Tr.t("LBL_AUDIT_STANDING") % standing]

# ── modos-de-juego ──

## Derrota normal (se puede reconvocar) o fin de la partida (Supervivencia).
func _apply_variant() -> void:
	var over: bool = GameMode.is_run_over()
	_title.text = Tr.t("LBL_RUN_OVER_TITLE") if over else Tr.t("LBL_AUDIT_DEFEAT_TITLE")
	_mode_label.visible = over
	_mode_label.text = Tr.t("LBL_MODE_CURRENT") % GameMode.display_name()
	_not_the_end.visible = not over
	_resummon_label.visible = not over
	_rebuild_btn.visible = not over
	_run_over_label.visible = over
	_end_row.visible = over
	# Terminada, la pantalla tiene que responder aunque el juego se pause por
	# encima (menu de pausa): es la unica salida que queda.
	process_mode = Node.PROCESS_MODE_ALWAYS if over else Node.PROCESS_MODE_INHERIT

## Cargar una partida terminada la vuelve a ensenar tal como acabo: lo que se
## perdio ya no se sabe (no viaja en el guardado), la baja de la guarnicion si.
func _on_game_load_completed() -> void:
	if not GameMode.is_run_over():
		return
	var audit = ProgressionManager.final_audit
	var wave: int = audit.current_wave if audit != null else 0
	_lost_frame = _frame()
	_show.call_deferred(wave, -2)

func is_run_over_variant() -> bool:
	return visible and GameMode.is_run_over()

func _on_new_game() -> void:
	GameManager.request_new_game()

func _on_quit() -> void:
	get_tree().quit()
