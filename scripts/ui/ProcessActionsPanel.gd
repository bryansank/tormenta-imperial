class_name ProcessActionsPanel
## Manages process/mining buttons and progress display.
## Uses UITheme card buttons for consistent styling.
##
## Menos texto (2026-10-04): cada tarjeta es "Nombre" y una linea
## "15 madera → 25 madera · 5 oro · 30 s"; la tasa de cancelacion normal va en el
## tooltip de Cancelar (la de la Tormenta, que cuesta el doble, sigue a la vista).

const TextKit := preload("res://scripts/ui/TextKit.gd")

var _processes_box: VBoxContainer
## Cuantas tarjetas de proceso ofrece el panel ahora (clear() libera en diferido).
var _count := 0
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
	_rate_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_rate_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_progress_container.add_child(_rate_label)

	_cancel_btn = Button.new()
	_cancel_btn.text = Tr.t("BTN_CANCEL")
	UITheme.style_button(_cancel_btn, UITheme.DANGER.darkened(0.2))
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
	for child in _processes_box.get_children():
		child.queue_free()

## Tarjetas (o avisos) que ofrece el panel. Sin ninguna, el panel del edificio
## esconde la cabecera "Acciones" en vez de decir "Sin acciones disponibles".
func action_count() -> int:
	return _count

func populate_building(node: Node, data: BuildingData, is_constructing: bool) -> void:
	clear()
	var processes := ProcessManager.get_processes_for(data.id)
	for proc in processes:
		if _process_has_locked_resource(proc):
			continue
		_add_process_card(proc, node)
	if is_constructing:
		set_buttons_disabled(true)
	update_progress(node, false, data)

func populate_deposit(node: Node, deposit_id: String) -> void:
	clear()
	if not GameConfig.is_deposit_unlocked(deposit_id):
		var locked_label := UITheme.make_label(Tr.t("LBL_DEPOSIT_LOCKED"), "small", UITheme.DANGER)
		locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked_label.autowrap_mode = TextServer.AUTOWRAP_WORD
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
		_progress_container.visible = false
		if not is_deposit and data and not ProductionManager.is_constructing(node):
			set_buttons_disabled(false)
		return
	_active_node = node
	_progress_container.visible = true
	_progress_bar.value = ProcessManager.get_progress(node)
	var remaining: float = active["remaining"]
	_progress_label.text = Tr.t("FMT_PROGRESS_SHORT") % [ProcessManager.get_active_name(node), TextKit.short_time(remaining)]
	_update_cancel_text(node)
	set_buttons_disabled(true)

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
	UITheme.set_label_color(_rate_label, UITheme.DANGER)

func set_buttons_disabled(disabled: bool) -> void:
	for child in _processes_box.get_children():
		if child is Button:
			child.disabled = disabled

func _add_process_card(proc: Dictionary, node: Node) -> void:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	btn.text = process_card_text(proc)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	UITheme.style_card_button(btn, UITheme.CARD_BG, UITheme.ACCENT)
	btn.pressed.connect(func(): _start_process(node, proc))
	_processes_box.add_child(btn)
	_count += 1

## "Madera refinada\n15 madera → 25 madera · 5 oro · 30 s". Estatica para las
## pruebas: coste, producto y tiempo, sin "Costo:", "Produce:" ni "Duracion:".
static func process_card_text(proc: Dictionary) -> String:
	var line := ""
	if proc.has("cost") and not proc["cost"].is_empty():
		line = TextKit.cost_text(proc["cost"]) + " → "
	line += TextKit.cost_text(proc["produces"], "+")
	line += " · " + TextKit.short_time(float(proc["duration"]))
	return "%s\n%s" % [Tr.t(proc["name"]), line]

func _add_mining_card(mining: Dictionary, node: Node, deposit_id: String) -> void:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Sin carretera hasta la veta o sin trabajadores libres, no se puede: se dice.
	var block: String = ProcessManager.mining_blocker(node)
	btn.text = mining_card_text(mining, block)
	btn.disabled = block != ""
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	UITheme.style_card_button(btn, UITheme.POSITIVE.darkened(0.6), UITheme.POSITIVE)
	btn.pressed.connect(func(): _start_mining(node, deposit_id))
	_processes_box.add_child(btn)
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

func _process_has_locked_resource(proc: Dictionary) -> bool:
	if proc.has("cost"):
		for res_name in proc["cost"]:
			if not ResourceManager.is_unlocked_by_name(res_name):
				return true
	if proc.has("produces"):
		for res_name in proc["produces"]:
			if not ResourceManager.is_unlocked_by_name(res_name):
				return true
	return false

func _start_process(node: Node, proc: Dictionary) -> void:
	if node and not ProcessManager.is_busy(node):
		ProcessManager.start_process(node, proc)

func _start_mining(node: Node, deposit_id: String) -> void:
	if node and not ProcessManager.is_busy(node):
		ProcessManager.start_mining(node, deposit_id)
