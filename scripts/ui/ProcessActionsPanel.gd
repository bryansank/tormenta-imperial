class_name ProcessActionsPanel
## Manages process/mining cards and progress display.
##
## Menos texto (2026-10-04): cada tarjeta es "Nombre" y una linea
## "15 madera → 25 madera · 5 oro · 30 s"; la tasa de cancelacion normal va en el
## tooltip de Cancelar (la de la Tormenta, que cuesta el doble, sigue a la vista).
##
## Lotes y el Nucleo como taller de todo (fix/partidas-bryan, 2026-10-14): cada
## proceso o minado es una tarjeta (scripts/ui/ProcessCard.gd) con iconos y
## cifras —coste → producto, tiempo, obreros— y botones x1 / x5 / MAX. En el
## Nucleo las tarjetas van en tres grupos: lo suyo, lo de los talleres y lo que
## se saca a mano (mas lentos: GameConfig.core_process_time_mult).

const TextKit := preload("res://scripts/ui/TextKit.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const ProcessCard := preload("res://scripts/ui/ProcessCard.gd")
const MapGeneratorScript := preload("res://scripts/map/MapGenerator.gd")

## Cada cuanto se recalcula lo que alcanza (MAX, bloqueos) mientras el panel
## esta abierto. No cada fotograma: rendimiento es prioridad.
const REFRESH_MS := 300

## Orden y cabecera de los grupos del Nucleo.
const CORE_GROUPS := [
	["own", "LBL_CORE_OWN"],
	["workshop", "LBL_CORE_WORKSHOPS"],
	["hand", "LBL_CORE_BY_HAND"],
]

var _processes_box: VBoxContainer
## Cuantas tarjetas de proceso ofrece el panel ahora (clear() libera en diferido).
var _count := 0
var _cards: Array = []
var _busy := false
## El proceso que hace ahora el edificio ("" = nada): su tarjeta sigue abierta
## para sumar tandas (ProcessManager.enqueue_process); las demas, apagadas.
var _busy_id := ""
var _last_refresh_ms := 0
var _progress_container: VBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _rate_label: Label
var _cancel_btn: Button
var _active_node: Node = null

func _init(processes_box: VBoxContainer, progress_container: VBoxContainer,
		progress_bar: ProgressBar, progress_label: Label) -> void:
	_processes_box = processes_box
	_progress_container = progress_container
	_progress_bar = progress_bar
	_progress_label = progress_label
	_build_cancel_controls()

## Cancelar vive junto a la barra de progreso, con el reembolso escrito encima.
## Hasta ahora no habia boton: la unica forma de parar algo era demoler el
## edificio entero, y se perdia el 100% sin decirlo.
func _build_cancel_controls() -> void:
	_rate_label = CT.why_label()
	_rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_progress_container.add_child(_rate_label)

	# Cancelar: rojo (quita), con lo que devuelve escrito en el propio boton.
	_cancel_btn = CT.text_pill(Tr.t("BTN_CANCEL"), "danger", CT.h("small"), "window", "body")
	_cancel_btn.name = "CancelProcess"
	# "Cancelar (vuelven 114 acero · 57 madera)" baja a dos lineas antes que
	# sacar la ficha por la derecha (ficha estrecha, telefono en vertical).
	_cancel_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_progress_container.add_child(_cancel_btn)

func _on_cancel_pressed() -> void:
	if _active_node == null or not is_instance_valid(_active_node):
		return
	ProcessManager.cancel(_active_node)
	_progress_container.visible = false
	set_buttons_disabled(false)

func clear() -> void:
	_count = 0
	_cards.clear()
	_busy = false
	for child in _processes_box.get_children():
		child.queue_free()

## Tarjetas (o avisos) que ofrece el panel. Sin ninguna, el panel del edificio
## esconde la cabecera "Acciones" en vez de decir "Sin acciones disponibles".
func action_count() -> int:
	return _count

## Las tarjetas que hay ahora (ProcessCard), para las pruebas.
func cards() -> Array:
	return _cards.duplicate()

func populate_building(node: Node, data: BuildingData, is_constructing: bool) -> void:
	clear()
	var processes: Array = []
	for proc in ProcessManager.get_processes_for(data.id):
		if not _process_has_locked_resource(proc):
			processes.append(proc)
	if data.id == "nucleo":
		_add_core_groups(node, processes)
	else:
		for proc in processes:
			_add_process_card(proc, node, Color(0, 0, 0, 0))
	if is_constructing:
		set_buttons_disabled(true)
	update_progress(node, false, data)

## El Nucleo: lo suyo, lo de los talleres y lo que se saca a mano, cada grupo
## con su cabecera corta. Un grupo sin nada desbloqueado no sale.
func _add_core_groups(node: Node, processes: Array) -> void:
	for group in CORE_GROUPS:
		var gid: String = group[0]
		var in_group: Array = processes.filter(func(p): return String(p.get("core_group", "own")) == gid)
		if in_group.is_empty():
			continue
		var header := CT.section(Tr.t(String(group[1])), {"own": "build", "workshop": "wrench", "hand": "res:workers"}.get(gid, ""))
		header.name = "CoreGroup_" + gid
		_processes_box.add_child(header)
		var accent: Color = UITheme.ACCENT if gid == "own" else (
			CT.sem("POSITIVE") if gid == "hand" else CT.sem("INFO"))
		for proc in in_group:
			_add_process_card(proc, node, accent, _from_tip(proc))

## "Lo mismo que en: Aserradero. Aqui tarda mas." para lo que el Nucleo copia.
func _from_tip(proc: Dictionary) -> String:
	var from := String(proc.get("from", ""))
	if from == "":
		return ""
	var where := ""
	if MapGeneratorScript.DEPOSIT_TYPES.has(from):
		where = Tr.t(String(MapGeneratorScript.DEPOSIT_TYPES[from]["display_name"]))
	else:
		where = Tr.t("BLD_%s_NAME" % from.to_upper())
	return Tr.t("LBL_CORE_FROM") % where

func populate_deposit(node: Node, deposit_id: String) -> void:
	clear()
	if not GameConfig.is_deposit_unlocked(deposit_id):
		var locked_label := CT.why_label()
		locked_label.text = Tr.t("LBL_DEPOSIT_LOCKED")
		locked_label.visible = true
		_processes_box.add_child(locked_label)
		_count += 1
		_progress_container.visible = false
		return
	var mining := ProcessManager.get_mining_info(deposit_id)
	if not mining.is_empty():
		_add_mining_card(mining, node, deposit_id)
	update_progress(node, true, null)

func update_progress(node: Node, is_deposit: bool, data: BuildingData) -> void:
	if not node:
		_active_node = null
		_progress_container.visible = false
		return
	var active := ProcessManager.get_active(node)
	if active.is_empty():
		_active_node = null
		_busy_id = ""
		_progress_container.visible = false
		var constructing: bool = not is_deposit and data != null and ProductionManager.is_constructing(node)
		if not constructing and (is_deposit or data != null):
			if _busy:
				set_buttons_disabled(false)
			else:
				_refresh_cards(false)
		return
	_active_node = node
	_busy_id = String(active.get("id", "*"))
	_progress_container.visible = true
	_progress_bar.value = ProcessManager.get_progress(node)
	var total: int = ProcessManager.get_batch_total(node)
	var proc_name := ProcessManager.get_active_name(node)
	if total > 1:
		# Lote: "Serrar tablones · 2 de 5 · 2:10" (tiempo hasta acabar el lote).
		var current: int = total - ProcessManager.get_batch_left(node) + 1
		_progress_label.text = Tr.t("FMT_PROGRESS_BATCH") % [proc_name, current, total,
			TextKit.short_time(ProcessManager.get_batch_remaining(node))]
	else:
		_progress_label.text = Tr.t("FMT_PROGRESS_SHORT") % [proc_name, TextKit.short_time(float(active["remaining"]))]
	_update_cancel_text(node)
	if not _busy:
		set_buttons_disabled(true)
	else:
		_refresh_cards(false)

## El boton dice exactamente cuanto devuelve. La tasa normal va en su tooltip;
## con la Tormenta en marcha se dice a la vista y en rojo: cancelar entonces
## cuesta el doble.
func _update_cancel_text(node: Node) -> void:
	var refund := ProcessManager.get_refund_preview(node)
	if refund.is_empty():
		_cancel_btn.text = Tr.t("LBL_CANCEL_NO_REFUND")
	else:
		_cancel_btn.text = Tr.t("FMT_CANCEL_REFUND") % TextKit.cost_text(refund)
	var pct := int(round(GameConfig.get_cancel_refund_ratio() * 100.0))
	var stormy := pct < int(round(GameConfig.cancel_refund_ratio * 100.0))
	_rate_label.text = Tr.t("LBL_CANCEL_RATE_STORM") % pct if stormy else ""
	_rate_label.visible = stormy
	_cancel_btn.tooltip_text = Tr.t("LBL_CANCEL_RATE_STORM") % pct if stormy else Tr.t("LBL_CANCEL_RATE") % pct

func set_buttons_disabled(disabled: bool) -> void:
	_busy = disabled
	_refresh_cards(true)

## Pone las tarjetas al dia: siempre si `force`, si no como mucho cada REFRESH_MS.
func _refresh_cards(force: bool) -> void:
	var now := Time.get_ticks_msec()
	if not force and now - _last_refresh_ms < REFRESH_MS:
		return
	_last_refresh_ms = now
	var busy: Variant = (_busy_id if _busy_id != "" else true) if _busy else ""
	for card in _cards:
		if is_instance_valid(card):
			card.refresh(busy)

func _add_process_card(proc: Dictionary, node: Node, accent: Color, from_tip: String = "") -> void:
	var card: PanelContainer = ProcessCard.new()
	card.setup(proc, ProcessCard.Kind.PROCESS, node, accent, from_tip)
	card.batch_requested.connect(func(n: int): _start_process(node, proc, n))
	card.dequeue_requested.connect(func(n: int): _dequeue(node, n))
	_processes_box.add_child(card)
	_cards.append(card)
	_count += 1

## "Madera refinada\n15 madera → 25 madera · 5 oro · 30 s". Estatica para las
## pruebas: coste, producto y tiempo, sin "Costo:", "Produce:" ni "Duracion:".
static func process_card_text(proc: Dictionary) -> String:
	return ProcessCard.card_text(proc, int(proc.get("workers", 0)))

func _add_mining_card(mining: Dictionary, node: Node, deposit_id: String) -> void:
	var card: PanelContainer = ProcessCard.new()
	card.setup(mining, ProcessCard.Kind.DEPOSIT, node, Color(0, 0, 0, 0))
	card.batch_requested.connect(func(n: int): _start_mining(node, deposit_id, n))
	card.dequeue_requested.connect(func(n: int): _dequeue(node, n))
	_processes_box.add_child(card)
	_cards.append(card)
	_count += 1

## "Talar\n+10 madera · 30 s · 2 trabajadores" y, si no se puede, "✖ motivo".
static func mining_card_text(mining: Dictionary, block: String = "") -> String:
	var line := "%s · %s · %s" % [
		TextKit.cost_text(mining["produces"], "+"),
		TextKit.short_time(float(mining["duration"])),
		Tr.t("LBL_WORKERS_SHORT") % GameConfig.mining_workers,
	]
	var text := "%s\n%s" % [Tr.t(mining["name"]), line]
	if block != "":
		text += "\n✖ " + Tr.t(block)
	return text

## Un proceso sale solo cuando TODOS sus recursos y materiales estan
## desbloqueados (por era o por el primer edificio de su material). Es tambien
## la regla del Nucleo: ofrece lo de un taller en cuanto su material existe.
static func _process_has_locked_resource(proc: Dictionary) -> bool:
	if proc.has("cost"):
		for res_name in proc["cost"]:
			if not ResourceManager.is_unlocked_by_name(res_name):
				return true
	if proc.has("produces"):
		for res_name in proc["produces"]:
			if not ResourceManager.is_unlocked_by_name(res_name):
				return true
	return false

## Cada lote SUMA a la cola de ese proceso (o la empieza).
func _start_process(node: Node, proc: Dictionary, count: int = 1) -> void:
	if node and ProcessManager.enqueue_process(node, proc, count):
		update_progress(node, false, null)
		_refresh_cards(true)

func _start_mining(node: Node, deposit_id: String, count: int = 1) -> void:
	if node and ProcessManager.enqueue_mining(node, deposit_id, count):
		update_progress(node, true, null)
		_refresh_cards(true)

## Quita tandas sin empezar (n = -1: todas) y devuelve lo pagado por ellas.
func _dequeue(node: Node, n: int) -> void:
	if node == null:
		return
	ProcessManager.dequeue(node, ProcessManager.queued_not_started(node) if n < 0 else n)
	update_progress(node, false, null)
	_refresh_cards(true)
