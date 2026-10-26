extends PanelContainer
## Una RECETA como tarjeta grande (feat/recetas-tarjetas, 2026-10-25). Bryan:
## "no se entiende bien que se puede construir/fabricar". Se lee de un vistazo:
##
##   Serrar tablones
##   [madera ×20]  →  [tablones ×5]  [reloj] 20 s      (iconos y cifras grandes)
##   [ ×1 ] [ ×5 ] [ MÁX ×12 ]                         (cuantas suma cada toque)
##   [            SERRAR ×1             ]              (el verbo, la accion)
##   En cola: 7        [−1] [Vaciar] [✕]               (solo la que trabaja)
##   ▬▬▬▬▬▬░░░░  Tanda 2 de 7 · 12 s
##   Te faltan 5 madera                                (rojo; el boton, gris)
##
## Bloqueada (un recurso o material que aun no existe): tarjeta apagada, candado
## y el porque en una frase ("Falta acero: llega con la Fundición"), sin botones.
## El detalle (lo que es, cuanto da por minuto) va al mantener pulsado: el
## tooltip de la tarjeta (TouchTooltip en tactil, el raton en PC).
##
## Estructura y comportamiento aqui; la piel (colores, letras, iconos, cajas)
## sale toda de CartoonTheme (seccion RECETAS), para que cambiarla no toque esto.
##
## La tarjeta no arranca nada: emite `batch_requested(count)`,
## `dequeue_requested(count)` y `cancel_requested()`, y ProcessActionsPanel
## decide. Tampoco se repinta sola: `refresh(busy)` (con cuentagotas) y
## `set_progress()` (la barra de la que trabaja) la ponen al dia.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

signal batch_requested(count: int)
## Quitar tandas sin empezar de la cola (n = -1: todas).
signal dequeue_requested(count: int)
## Cancelar lo que hace ahora (la tanda en marcha y la cola).
signal cancel_requested

## Tipo de tarjeta: un proceso (de un edificio o del Nucleo) o el minado de una veta.
enum Kind { PROCESS, DEPOSIT }
## El selector en MAX: suma lo que alcance en ese momento.
const PICK_MAX := -1
## `refresh()` con este "ocupado": el edificio esta en obras.
const BUSY_BUILDING := "#obra"

var _proc: Dictionary = {}
var _kind: int = Kind.PROCESS
var _node: Node = null
## Recurso o material aun cerrado que pide o da la receta ("" = abierta).
var _locked_res := ""
var _pick := 1
var _pick_buttons: Dictionary = {}   # 1, 5, PICK_MAX -> Button
var _max_btn: Button
var _verb_btn: Button
var _title: Label
var _lock_icon: Control
var _cost_row: HBoxContainer
var _out_row: HBoxContainer
var _yield: HFlowContainer
var _controls: VBoxContainer
var _why: Label
var _queue_row: HFlowContainer
var _queue_label: Label
var _minus_btn: Button
var _clear_btn: Button
var _cancel_btn: Button
var _storm_label: Label
var _bar_box: VBoxContainer
var _bar: ProgressBar
var _bar_label: Label
var _last_sig: Array = []
var _state := ""
var _last_busy: Variant = ""

## `proc` es la definicion ya escalada (ProcessManager.get_processes_for o
## get_mining_info). `node` es el edificio o la veta. `from_tip` va al detalle
## (de donde viene un proceso del Nucleo). `_accent` se acepta por
## compatibilidad: el Nucleo ya no tine sus grupos, los separa en pestanas.
func setup(proc: Dictionary, kind: int, node: Node, _accent: Color = Color(0, 0, 0, 0), from_tip: String = "") -> void:
	_proc = proc
	_kind = kind
	_node = node
	_locked_res = locked_resource(proc)
	name = "ProcessCard_" + String(proc.get("id", ""))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = detail_text(proc, _workers(), from_tip)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6 if CT.is_phone() else 8)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)

	# Fila 1: el candado (si esta cerrada) y el nombre.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(top)
	_lock_icon = CT.make_glyph("lock", 22 if CT.is_phone() else 26)
	_lock_icon.name = "Lock"
	_lock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_lock_icon)
	_title = CT.label(Tr.t(String(proc.get("name", ""))), "button", CT.text("window"))
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_title)
	# Reloj y obreros: al final de la fila de la receta (el nombre, entero).
	var meta := HBoxContainer.new()
	meta.name = "Meta"
	meta.add_theme_constant_override("separation", 4)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock := CT.make_glyph("clock", 20 if CT.is_phone() else 24)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(clock)
	var time := CT.label(TextKit.short_time(float(proc.get("duration", 0.0))), "number", CT.text("window"))
	time.name = "Time"
	meta.add_child(time)
	if _workers() > 0:
		var wi := CT.make_glyph("res:workers", 20 if CT.is_phone() else 24)
		wi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meta.add_child(wi)
		var wl := CT.label(str(_workers()), "number", CT.text("window"))
		wl.name = "Workers"
		meta.add_child(wl)

	# Fila 2: lo que entra → lo que sale, con iconos y cifras grandes. Se parte
	# por piezas enteras si no cabe (nunca ensancha la tarjeta).
	_yield = HFlowContainer.new()
	_yield.name = "Yield"
	_yield.add_theme_constant_override("h_separation", 6)
	_yield.add_theme_constant_override("v_separation", 4)
	_yield.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_yield)
	var cost: Dictionary = proc.get("cost", {})
	_cost_row = HBoxContainer.new()
	_cost_row.name = "Cost"
	_cost_row.add_theme_constant_override("separation", 4)
	_cost_row.mouse_filter = Control.MOUSE_FILTER_PASS
	# La flecha va pegada a lo que sale: si no cabe en una linea, la segunda
	# empieza por "→ [tablones ×5]" y se sigue leyendo bien.
	var out_group := HBoxContainer.new()
	out_group.name = "Out"
	out_group.add_theme_constant_override("separation", 6)
	out_group.mouse_filter = Control.MOUSE_FILTER_PASS
	if not cost.is_empty():
		CT.fill_recipe_row(_cost_row, cost)
		_yield.add_child(_cost_row)
		var arrow := CT.make_glyph("next", 24 if CT.is_phone() else 30, CT.text("window", true))
		arrow.name = "Arrow"
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		out_group.add_child(arrow)
	_out_row = HBoxContainer.new()
	_out_row.name = "Produces"
	_out_row.add_theme_constant_override("separation", 4)
	_out_row.mouse_filter = Control.MOUSE_FILTER_PASS
	CT.fill_recipe_row(_out_row, proc.get("produces", {}), {}, true)
	out_group.add_child(_out_row)
	_yield.add_child(out_group)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_yield.add_child(meta)

	# Los mandos: cuantas suma cada toque y el verbo. Ocultos si esta cerrada.
	_controls = VBoxContainer.new()
	_controls.name = "Controls"
	_controls.add_theme_constant_override("separation", 6)
	box.add_child(_controls)
	var picks := HBoxContainer.new()
	picks.name = "Picks"
	picks.add_theme_constant_override("separation", 6)
	picks.tooltip_text = Tr.t("RCP_PICK_TIP")
	picks.mouse_filter = Control.MOUSE_FILTER_PASS
	_controls.add_child(picks)
	for n in GameConfig.process_batch_sizes:
		var size_n: int = int(n)
		var b := _make_pick(Tr.t("BTN_BATCH_N") % size_n, size_n)
		b.name = "Batch_%d" % size_n
		picks.add_child(b)
	_max_btn = _make_pick(Tr.t("UI3F_BATCH_MAX"), PICK_MAX)
	_max_btn.name = "BatchMax"
	_max_btn.size_flags_stretch_ratio = 1.6
	_max_btn.tooltip_text = Tr.t("LBL_BATCH_MAX_TIP") % GameConfig.process_batch_max
	picks.add_child(_max_btn)
	_verb_btn = CT.text_pill("", "primary", CT.h("big"), "window", "button")
	_verb_btn.name = "Verb"
	_verb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_verb_btn.tooltip_text = Tr.t("UI3F_TAP_ADDS")
	_verb_btn.pressed.connect(_on_verb)
	_controls.add_child(_verb_btn)

	# La cola de esta receta (solo la que trabaja): "En cola: 7", −1, Vaciar, ✕.
	_queue_row = HFlowContainer.new()
	_queue_row.name = "Queue"
	_queue_row.add_theme_constant_override("h_separation", 6)
	_queue_row.add_theme_constant_override("v_separation", 6)
	_queue_row.visible = false
	box.add_child(_queue_row)
	_queue_label = CT.label("", "button", CT.text("window"))
	_queue_label.name = "QueueCount"
	_queue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_queue_row.add_child(_queue_label)
	_minus_btn = CT.text_pill(Tr.t("UI2F_QUEUE_MINUS"), "secondary", CT.h("small"), "window", "body")
	_minus_btn.name = "QueueMinus"
	_minus_btn.tooltip_text = Tr.t("UI2F_QUEUE_MINUS_TIP")
	_minus_btn.pressed.connect(func(): dequeue_requested.emit(1))
	_queue_row.add_child(_minus_btn)
	_clear_btn = CT.text_pill(Tr.t("UI2F_QUEUE_CLEAR"), "secondary", CT.h("small"), "window", "body")
	_clear_btn.name = "QueueClear"
	_clear_btn.tooltip_text = Tr.t("UI2F_QUEUE_CLEAR_TIP")
	_clear_btn.pressed.connect(func(): dequeue_requested.emit(-1))
	_queue_row.add_child(_clear_btn)

	# La barra de la tanda en marcha y, a su lado, cancelarla (rojo, solo
	# icono; lo que devuelve, al mantener pulsado).
	_bar_box = VBoxContainer.new()
	_bar_box.name = "Progress"
	_bar_box.add_theme_constant_override("separation", 2)
	_bar_box.visible = false
	box.add_child(_bar_box)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	_bar_box.add_child(bar_row)
	_bar = CT.progress(0.0, CT.sem("ACCENT"), "window", 12 if CT.is_phone() else 16)
	_bar.name = "Bar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_bar)
	_cancel_btn = CT.pill_button("", "close", "danger", CT.h("small"))
	_cancel_btn.name = "CancelProcess"
	_cancel_btn.pressed.connect(func(): cancel_requested.emit())
	bar_row.add_child(_cancel_btn)
	_bar_label = CT.label("", "small", CT.text("window", true))
	_bar_label.name = "BarText"
	_bar_box.add_child(_bar_label)
	# Con la Tormenta, cancelar cuesta el doble: se dice a la vista.
	_storm_label = CT.why_label()
	_storm_label.name = "StormRate"
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_storm_label)

	# Por que no se puede: candado, ocupado, faltan recursos... en una frase.
	_why = CT.why_label()
	_why.name = "Block"
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(_why)

	_select(1)
	refresh("")

func _make_pick(text: String, n: int) -> Button:
	var b := CT.text_pill(text, "secondary", CT.h("small"), "window", "button")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if n > 0:
		b.tooltip_text = Tr.t("LBL_BATCH_TIP") % n
	b.pressed.connect(func(): select(n))
	_pick_buttons[n] = b
	return b

func _workers() -> int:
	if _kind == Kind.DEPOSIT:
		return GameConfig.mining_workers
	return int(_proc.get("workers", 0))

# ── Estado ──

## Si la receta esta cerrada (pide o da algo que aun no existe).
func is_locked() -> bool:
	return _locked_res != ""

## Lo que MAX pediria ahora mismo.
func max_now() -> int:
	if _node == null:
		return ProcessManager.max_batch(_proc, -1)
	var uses := ProcessManager.deposit_uses_left(_node) if _kind == Kind.DEPOSIT else -1
	return ProcessManager.room_for(_node, _proc, uses)

## Las tandas que sumaria el verbo ahora (lo elegido, o lo que alcance con MAX).
func count_now() -> int:
	return max_now() if _pick == PICK_MAX else _pick

## Lo elegido en el selector: 1, 5... o PICK_MAX.
func picked() -> int:
	return _pick

## Elegir cuantas suma cada toque. No encola nada: eso lo hace el verbo.
func select(n: int) -> void:
	_select(n)
	_last_sig = []
	refresh(_last_busy)

func _select(n: int) -> void:
	_pick = n
	for k in _pick_buttons:
		CT.style_pick(_pick_buttons[k], int(k) == n)

## Por que no se puede arrancar ahora (aparte de pagarlo): "" o una clave de Tr.
func blocker() -> String:
	if _kind == Kind.DEPOSIT:
		return ProcessManager.mining_blocker(_node)
	return ProcessManager.process_blocker(_proc)

## Pone la tarjeta al dia. `busy_id`: el proceso que hace ahora el edificio
## ("" = nada; BUSY_BUILDING = en obras). Con otro proceso en marcha la
## tarjeta se apaga y dice cual; con el suyo sigue abierta para sumar tandas y
## ensena la cola. Compatibilidad: `true` / `false`. Solo toca lo que cambia.
func refresh(busy_id: Variant = "") -> void:
	_last_busy = busy_id
	var busy: String = ("*" if bool(busy_id) else "") if busy_id is bool else String(busy_id)
	var own := String(_proc.get("id", ""))
	var queued := 0
	if _node != null and busy != "" and ProcessManager.is_busy(_node) \
			and String(ProcessManager.get_active(_node).get("id", "")) == own:
		queued = ProcessManager.get_batch_left(_node)
	var mx := 0 if is_locked() else max_now()
	var block := "" if is_locked() else blocker()
	var sig := [mx, block, busy, queued, _pick, {} if is_locked() else _short_for(1)]
	if sig == _last_sig:
		return
	_last_sig = sig

	var state := "locked" if is_locked() else ("active" if queued > 0 else "open")
	if state != _state:
		_state = state
		add_theme_stylebox_override("panel", CT.recipe_card_style(state))
	_lock_icon.visible = is_locked()
	_controls.visible = not is_locked()
	_yield.modulate.a = 0.55 if is_locked() else 1.0
	_title.add_theme_color_override("font_color", CT.text("window", is_locked()))

	var why := ""
	var short := {}
	var other := busy != "" and queued == 0
	if is_locked():
		why = locked_text(_locked_res)
	elif busy == BUSY_BUILDING:
		why = Tr.t("RCP_IN_CONSTRUCTION")
	elif other:
		var name_now := ProcessManager.get_active_name(_node) if _node != null else ""
		why = Tr.t("UI2F_BUSY_WITH") % name_now if name_now != "" else Tr.t("UI2F_BUSY")
	elif block != "" and queued == 0:
		why = Tr.t(block)
	elif mx <= 0:
		if queued > 0 and _kind == Kind.DEPOSIT and ProcessManager.deposit_uses_left(_node) - queued <= 0:
			why = Tr.t("RCP_NO_USES")
		elif queued >= GameConfig.process_batch_max:
			why = Tr.t("RCP_QUEUE_FULL") % GameConfig.process_batch_max
		else:
			short = _short_for(1)
			why = Tr.t("RCP_SHORT") % TextKit.cost_text(short) if not short.is_empty() else Tr.t("LBL_BATCH_CANT")
	_why.text = why
	_why.visible = why != ""
	# Lo que falta, tambien en rojo en la ficha de entrada.
	if _proc.has("cost") and not (_proc["cost"] as Dictionary).is_empty():
		CT.fill_recipe_row(_cost_row, _proc["cost"], short)

	if is_locked():
		_queue_row.visible = false
		_bar_box.visible = false
		_storm_label.visible = false
		return

	# El selector: lo que no alcanza, apagado; si lo elegido deja de alcanzar,
	# vuelve a ×1.
	var off := other or busy == BUSY_BUILDING or (block != "" and queued == 0)
	if _pick > 0 and mx < _pick and mx >= 1 and _pick != 1:
		_select(1)
	for k in _pick_buttons:
		var b: Button = _pick_buttons[k]
		var n := int(k)
		if n == PICK_MAX:
			b.disabled = off or mx < 2
			b.text = Tr.t("BTN_BATCH_MAX") % mx if (mx >= 2 and not off) else Tr.t("UI3F_BATCH_MAX")
		else:
			b.disabled = off or mx < n
			var cant := Tr.t("RCP_NO_ROOM") if _afford(n) else Tr.t("LBL_BATCH_CANT")
			b.tooltip_text = cant if (not off and mx < n) else Tr.t("LBL_BATCH_TIP") % n
	var n_now := count_now()
	_verb_btn.text = "%s %s" % [verb_text(_proc, _kind), Tr.t("BTN_BATCH_N") % maxi(1, n_now)]
	_verb_btn.disabled = off or mx < 1 or n_now < 1

	_queue_row.visible = queued > 0
	_queue_label.text = Tr.t("UI2F_QUEUE_N") % queued
	var waiting := maxi(0, queued - 1)
	_minus_btn.disabled = waiting <= 0
	_clear_btn.disabled = waiting <= 0
	_bar_box.visible = queued > 0
	_storm_label.visible = false
	if queued > 0 and _node != null:
		var refund := ProcessManager.get_refund_preview(_node)
		_cancel_btn.tooltip_text = Tr.t("FMT_CANCEL_REFUND") % TextKit.cost_text(refund) if not refund.is_empty() \
			else Tr.t("LBL_CANCEL_NO_REFUND")
		var pct := int(round(GameConfig.get_cancel_refund_ratio() * 100.0))
		if pct < int(round(GameConfig.cancel_refund_ratio * 100.0)):
			_storm_label.text = Tr.t("LBL_CANCEL_RATE_STORM") % pct
			_storm_label.visible = true

## Si los recursos dan para `n` tandas (aunque luego no quepan en el almacen
## o en la cola): para decir el porque correcto de un ×5 apagado.
func _afford(n: int) -> bool:
	return _short_for(n).is_empty()

## Lo que falta para pagar `n` tandas, por recurso ({} si alcanza).
func _short_for(n: int) -> Dictionary:
	var out := {}
	var cost: Dictionary = _proc.get("cost", {})
	for res_id in cost:
		var type: int = ResourceManager.name_to_type(String(res_id))
		if type == -1:
			continue
		var miss: int = int(cost[res_id]) * n - ResourceManager.get_amount(type)
		if miss > 0:
			out[String(res_id)] = miss
	return out

## La barra de la tanda en marcha: lo hecho (0..1) y "Tanda 2 de 7 · 12 s".
## Barata: el panel la llama cada fotograma solo en la tarjeta que trabaja.
func set_progress(ratio: float, text: String) -> void:
	_bar.value = ratio
	if _bar_label.text != text:
		_bar_label.text = text

func _on_verb() -> void:
	var n := count_now()
	if n >= 1:
		batch_requested.emit(n)

# ── Para el panel y las pruebas ──

## Los botones de la tarjeta: el selector y el verbo.
func batch_buttons() -> Array:
	var out: Array = []
	for k in _pick_buttons:
		out.append(_pick_buttons[k])
	out.append(_verb_btn)
	return out

func verb_button() -> Button:
	return _verb_btn

## La frase de por que no se puede ("" si se puede).
func why_text() -> String:
	return _why.text if _why.visible else ""

func queue_text() -> String:
	return _queue_label.text if _queue_row.visible else ""

# ── Textos (estaticos: las pruebas y la seccion los usan) ──

## El verbo del boton, en mayusculas: "SERRAR", "TALAR", "DESTILAR"... Sale
## de UI3F_VERB_<ID> (el minado desde el Nucleo usa el de su veta); sin verbo
## propio, HACER (procesos) o SACAR (a mano).
static func verb_text(proc: Dictionary, kind: int = Kind.PROCESS) -> String:
	var pid := String(proc.get("id", "")).trim_prefix(GameConfig.CORE_MINING_PREFIX)
	var key := "UI3F_VERB_" + pid.to_upper()
	if Tr.t(key) != key:
		return Tr.t(key)
	var hand := kind == Kind.DEPOSIT or pid.begins_with("mine_")
	return Tr.t("UI3F_VERB_HAND" if hand else "UI3F_VERB_DO")

## El primer recurso o material que la receta pide o da y aun no existe ("" si
## todo esta abierto). Es la regla de siempre de la ficha, ahora para decir el
## porque en vez de esconder la receta.
static func locked_resource(proc: Dictionary) -> String:
	for key in ["cost", "produces"]:
		var amounts: Dictionary = proc.get(key, {})
		for res_id in amounts:
			if not ResourceManager.is_unlocked_by_name(String(res_id)):
				return String(res_id)
	return ""

## "Falta acero: llega con la Fundición" (o "Falta acero" si no se sabe quien
## lo trae).
static func locked_text(res_id: String) -> String:
	var what := Tr.res_name(res_id)
	var bld := GameConfig.get_unlock_building(res_id)
	var with_key := "RCP_WITH_" + bld.to_upper()
	if bld != "" and Tr.t(with_key) != with_key:
		return Tr.t("RCP_LOCKED_WITH") % [what, Tr.t(with_key)]
	return Tr.t("RCP_LOCKED") % what

## Lo que sale por minuto ("+15 tablones · +2 oro"), para el detalle.
static func per_minute_text(proc: Dictionary) -> String:
	var dur := maxf(float(proc.get("duration", 1.0)), 0.01)
	var out := {}
	var produces: Dictionary = proc.get("produces", {})
	for res_id in produces:
		out[res_id] = roundi(float(produces[res_id]) * 60.0 / dur)
	return TextKit.cost_text(out, "+")

## El detalle de mantener pulsado: nombre, lo que es, la receta en texto, por
## minuto y de donde viene (Nucleo).
static func detail_text(proc: Dictionary, workers: int = 0, from_tip: String = "") -> String:
	var lines: Array = [card_text(proc, workers)]
	var pid := String(proc.get("id", "")).trim_prefix(GameConfig.CORE_MINING_PREFIX)
	var lore_key := "RCP_LORE_" + pid.to_upper()
	if Tr.t(lore_key) != lore_key:
		lines.insert(1, Tr.t(lore_key))
	lines.append(Tr.t("RCP_PER_MIN") % per_minute_text(proc))
	if from_tip != "":
		lines.append(from_tip)
	return "\n".join(lines)

## "Serrar tablones\n20 madera → +5 tablones · 30 s · 2 trabajadores": la tarjeta
## en texto plano, para el detalle y las pruebas.
static func card_text(proc: Dictionary, workers: int = 0) -> String:
	var line := ""
	if proc.has("cost") and not (proc["cost"] as Dictionary).is_empty():
		line = TextKit.cost_text(proc["cost"]) + " → "
	line += TextKit.cost_text(proc["produces"], "+")
	line += " · " + TextKit.short_time(float(proc["duration"]))
	if workers > 0:
		line += " · " + Tr.t("LBL_WORKERS_SHORT") % workers
	return "%s\n%s" % [Tr.t(String(proc["name"])), line]
