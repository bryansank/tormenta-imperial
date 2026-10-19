extends PanelContainer
## Una tarjeta de proceso o de minado a mano (fix/partidas-bryan, 2026-10-14).
##
## De un vistazo, iconos y cifras antes que frases:
##
##   Serrar tablones                       0:30  [obrero] 2
##   [madera] 20  →  +5 tablones
##   ✖ No hay trabajadores libres          (solo si no se puede)
##   [ ×1 ]  [ ×5 ]  [ MÁX ×12 ]
##
## Los botones piden un lote (ProcessManager.start_process / start_mining con
## `count`): se paga todo ahora y se hacen uno tras otro. MAX es lo que dejan los
## recursos, el hueco de la bolsa y los usos de la veta (ProcessManager.max_batch).
## El texto plano de la tarjeta va en su tooltip (mantener pulsado en tablet).
##
## La tarjeta no arranca nada: emite `batch_requested(count)` y quien la creo
## (ProcessActionsPanel) decide. Tampoco se repinta sola: `refresh(busy)` la pone
## al dia, y el panel la llama con cuentagotas (no cada fotograma).

const TextKit := preload("res://scripts/ui/TextKit.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

signal batch_requested(count: int)

## Tipo de tarjeta: un proceso (de un edificio o del Nucleo) o el minado de una veta.
enum Kind { PROCESS, DEPOSIT }

var _proc: Dictionary = {}
var _kind: int = Kind.PROCESS
var _node: Node = null
var _size_buttons: Dictionary = {}   # tamano del lote -> Button
var _max_btn: Button
var _block_label: Label
var _last_max := -1
var _last_block := "?"
var _last_busy := false

## `proc` es la definicion ya escalada (ProcessManager.get_processes_for o
## get_mining_info). `node` es el edificio o la veta. `from_tip` es un texto extra
## para el tooltip (de donde viene un proceso del Nucleo). `accent` tine el borde
## de la tarjeta (los grupos del Nucleo).
##
## Estilo nuevo (docs/28, fase 2): tarjeta crema con borde grueso, el coste y el
## producto en fichas hundidas ([madera] 20 → [+5 tablones]) y los lotes como
## pastillas: x1 verde (la accion), x5 y MAX en crema.
func setup(proc: Dictionary, kind: int, node: Node, accent: Color, from_tip: String = "") -> void:
	_proc = proc
	_kind = kind
	_node = node
	name = "ProcessCard_" + String(proc.get("id", ""))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", _card_style(accent))
	var tip := card_text(proc, _workers())
	if from_tip != "":
		tip += "\n" + from_tip
	tooltip_text = tip

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)

	# Fila 1: nombre a la izquierda; tiempo y obreros a la derecha.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(top)
	var title := CT.label(Tr.t(String(proc.get("name", ""))), "button", CT.text("window"))
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	var clock := CT.make_glyph("clock", 18)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock)
	var time := CT.label(TextKit.short_time(float(proc.get("duration", 0.0))), "small", CT.text("window", true))
	time.name = "Time"
	top.add_child(time)
	if _workers() > 0:
		var workers := HBoxContainer.new()
		workers.name = "Workers"
		workers.add_theme_constant_override("separation", 2)
		workers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wi := UITheme.make_icon("workers", 20)
		wi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		workers.add_child(wi)
		workers.add_child(CT.label(str(_workers()), "small", CT.text("window", true)))
		top.add_child(workers)

	# Fila 2: lo que cuesta → lo que sale, en fichas. Se parte por piezas
	# enteras si el panel es estrecho.
	var flow := HFlowContainer.new()
	flow.name = "Yield"
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(flow)
	var cost: Dictionary = proc.get("cost", {})
	if not cost.is_empty():
		var cost_row := CT.cost_strip(cost)
		cost_row.name = "Cost"
		flow.add_child(cost_row)
		var arrow := CT.make_glyph("next", 18, CT.text("window", true))
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		flow.add_child(arrow)
	var out_row := CT.cost_strip(proc.get("produces", {}), {}, "window", "+", "number", CT.positive_text())
	out_row.name = "Produces"
	flow.add_child(out_row)

	# Fila 3: por que no se puede (oculta si se puede).
	_block_label = CT.why_label()
	_block_label.name = "Block"
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_block_label)

	# Fila 4: los lotes. Del tamano de un dedo.
	var buttons := HBoxContainer.new()
	buttons.name = "Batch"
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var first := true
	for n in GameConfig.process_batch_sizes:
		var size_n: int = int(n)
		var btn := _make_batch_button(Tr.t("BTN_BATCH_N") % size_n, "primary" if first else "secondary")
		first = false
		btn.name = "Batch_%d" % size_n
		btn.tooltip_text = Tr.t("LBL_BATCH_TIP") % size_n
		btn.pressed.connect(func(): batch_requested.emit(size_n))
		buttons.add_child(btn)
		_size_buttons[size_n] = btn
	_max_btn = _make_batch_button(Tr.t("BTN_BATCH_MAX") % 0, "secondary")
	_max_btn.name = "BatchMax"
	_max_btn.size_flags_stretch_ratio = 1.6
	_max_btn.tooltip_text = Tr.t("LBL_BATCH_MAX_TIP") % GameConfig.process_batch_max
	_max_btn.pressed.connect(func(): batch_requested.emit(max_now()))
	buttons.add_child(_max_btn)
	refresh(false)

func _make_batch_button(text: String, kind_s: String) -> Button:
	var btn := CT.text_pill(text, kind_s, CT.h("small"))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn

func _card_style(accent: Color) -> StyleBoxFlat:
	var s := CT.card_style("window")
	if accent.a > 0.0 and accent != UITheme.ACCENT:
		s.border_color = accent
	s.set_content_margin_all(8)
	s.content_margin_left = 10
	return s

func _workers() -> int:
	if _kind == Kind.DEPOSIT:
		return GameConfig.mining_workers
	return int(_proc.get("workers", 0))

## Lo que MAX pediria ahora mismo.
func max_now() -> int:
	var uses := ProcessManager.deposit_uses_left(_node) if _kind == Kind.DEPOSIT else -1
	return ProcessManager.max_batch(_proc, uses)

## Por que no se puede arrancar ahora: "" si se puede, o una clave de Tr.
func blocker() -> String:
	if _kind == Kind.DEPOSIT:
		return ProcessManager.mining_blocker(_node)
	return ProcessManager.process_blocker(_proc)

## Pone los botones al dia: ocupado (algo en curso aqui), bloqueado o lo que
## alcanza. Solo toca lo que cambia.
func refresh(busy: bool) -> void:
	var mx := max_now()
	var block := blocker()
	if mx == _last_max and block == _last_block and busy == _last_busy:
		return
	_last_max = mx
	_last_block = block
	_last_busy = busy
	_block_label.text = Tr.t(block) if block != "" else ""
	_block_label.visible = block != "" and not busy
	var off := busy or block != ""
	for n in _size_buttons:
		var btn: Button = _size_buttons[n]
		btn.disabled = off or mx < int(n)
		if not busy and block == "" and mx < int(n):
			btn.tooltip_text = Tr.t("LBL_BATCH_CANT")
		else:
			btn.tooltip_text = Tr.t("LBL_BATCH_TIP") % int(n)
	_max_btn.text = Tr.t("BTN_BATCH_MAX") % maxi(mx, 0)
	# MAX solo tiene sentido si da para mas de una; si no, basta el x1.
	_max_btn.disabled = off or mx < 2

## Los botones de la tarjeta (para el panel y las pruebas).
func batch_buttons() -> Array:
	var out: Array = _size_buttons.values()
	out.append(_max_btn)
	return out

## "Serrar tablones\n20 madera → +5 tablones · 30 s · 2 trabajadores": la tarjeta
## en texto plano, para el tooltip y las pruebas.
static func card_text(proc: Dictionary, workers: int = 0) -> String:
	var line := ""
	if proc.has("cost") and not (proc["cost"] as Dictionary).is_empty():
		line = TextKit.cost_text(proc["cost"]) + " → "
	line += TextKit.cost_text(proc["produces"], "+")
	line += " · " + TextKit.short_time(float(proc["duration"]))
	if workers > 0:
		line += " · " + Tr.t("LBL_WORKERS_SHORT") % workers
	return "%s\n%s" % [Tr.t(String(proc["name"])), line]
