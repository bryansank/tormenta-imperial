extends RefCounted
## La cola de avisos de NotificationPanel, sin nodos ni reloj propio (se prueba
## sola, tests/ui/test_alert_queue.gd). Reglas (Bryan, 2026-10-18: "las alertas
## se sobreponen a todo, se ve feo"):
##
##   - Un aviso igual a otro que ya esta en pantalla o esperando no sale dos
##     veces: se agrupa ("×3") y su reloj vuelve a empezar.
##   - En pantalla, como mucho `cap` a la vez (2; 1 en telefono pequeno). El
##     resto espera en orden; los de peligro pasan delante.
##   - Con una ventana abierta (`busy`) solo puede verse UN aviso de peligro, y
##     pequeno; los demas vuelven a la cola, con su cuenta, y salen al cerrarla.
##   - La cola no crece sin fin: lo que pase de MAX_WAITING se resume en un
##     "N avisos mas en el REGISTRO" (todos estan ya en el registro).

## Lo que puede verse con una ventana abierta: peligro inmediato.
const URGENT := ["danger"]
## Segundos en pantalla (sin animaciones: aparece y desaparece).
const DURATION := 5.0
const DURATION_URGENT := 7.0
## Avisos esperando antes de resumir los mas viejos.
const MAX_WAITING := 4

var shown: Array = []
var waiting: Array = []
var _seq := 0

static func is_urgent(category: String) -> bool:
	return category in URGENT

static func duration_for(category: String) -> float:
	return DURATION_URGENT if is_urgent(category) else DURATION

## Un aviso nuevo (o uno repetido, que se agrupa). Devuelve su entrada.
func post(text: String, category: String, color: Color) -> Dictionary:
	var key := category + "|" + text
	for e in shown + waiting:
		if String(e["key"]) == key:
			e["count"] = int(e["count"]) + 1
			e["left"] = duration_for(category)
			return e
	_seq += 1
	var entry := {"key": key, "text": text, "category": category, "color": color,
		"count": 1, "left": duration_for(category), "seq": _seq, "summary": false}
	waiting.append(entry)
	_trim()
	return entry

## Coloca: cuales se ven ahora. `cap` avisos sin ventana; con ventana (`busy`)
## uno de peligro como mucho. Devuelve true si cambio lo que se ve.
func arrange(cap: int, busy: bool) -> bool:
	var before := _keys(shown)
	var limit := 1 if busy else maxi(cap, 1)
	# Los que no pueden verse ahora vuelven delante de la cola (con su cuenta).
	var back: Array = []
	var keep: Array = []
	for e in shown:
		if busy and not is_urgent(String(e["category"])):
			back.append(e)
		else:
			keep.append(e)
	while keep.size() > limit:
		back.append(keep.pop_front())
	# Un peligro que espera no se queda detras de un aviso corriente: este
	# vuelve a la cola (con su cuenta) y el peligro pasa.
	var urgent_waiting := waiting.filter(func(e): return is_urgent(String(e["category"]))).size()
	while urgent_waiting > 0 and keep.size() >= limit:
		var plain := -1
		for i in keep.size():
			if not is_urgent(String(keep[i]["category"])):
				plain = i
				break
		if plain < 0:
			break
		back.append(keep[plain])
		keep.remove_at(plain)
		urgent_waiting -= 1
	shown = keep
	back.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	waiting = back + waiting
	# Rellenar: peligro primero, luego por orden de llegada.
	while shown.size() < limit:
		var pick := _next_waiting(busy)
		if pick < 0:
			break
		var e: Dictionary = waiting[pick]
		waiting.remove_at(pick)
		e["left"] = duration_for(String(e["category"]))
		shown.append(e)
	shown.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	_trim()
	return _keys(shown) != before

## Pasa el reloj de los que se ven. Devuelve true si alguno se fue.
func tick(delta: float) -> bool:
	var gone := false
	for e in shown.duplicate():
		e["left"] = float(e["left"]) - delta
		if float(e["left"]) <= 0.0:
			shown.erase(e)
			gone = true
	return gone

## El jugador lo cerro con ✕.
func dismiss(key: String) -> void:
	for e in shown.duplicate():
		if String(e["key"]) == key:
			shown.erase(e)

func clear() -> void:
	shown.clear()
	waiting.clear()

func waiting_count() -> int:
	var n := 0
	for e in waiting:
		n += int(e["count"]) if bool(e["summary"]) else 1
	return n

## El siguiente en salir: peligro primero, luego por orden de llegada, y el
## resumen ("N avisos mas en el REGISTRO") el ultimo de todos.
func _next_waiting(busy: bool) -> int:
	var best := -1
	var best_rank := 99
	for i in waiting.size():
		var e: Dictionary = waiting[i]
		var urgent := is_urgent(String(e["category"]))
		if busy and not urgent:
			continue
		var rank := 0 if urgent else (2 if bool(e["summary"]) else 1)
		if rank < best_rank:
			best = i
			best_rank = rank
	return best

## Lo que pase de MAX_WAITING (sin contar los de peligro) va a un resumen.
func _trim() -> void:
	var plain: Array = waiting.filter(func(e): return not is_urgent(String(e["category"])) and not bool(e["summary"]))
	var extra := waiting.size() - MAX_WAITING
	if extra <= 0 or plain.is_empty():
		return
	var summary: Dictionary = {}
	for e in waiting:
		if bool(e["summary"]):
			summary = e
	if summary.is_empty():
		_seq += 1
		summary = {"key": "summary", "text": "", "category": "info", "color": Color.WHITE,
			"count": 0, "left": DURATION, "seq": _seq, "summary": true}
		waiting.append(summary)
		extra += 1
	for e in plain:
		if extra <= 0:
			break
		waiting.erase(e)
		summary["count"] = int(summary["count"]) + 1
		extra -= 1

func _keys(list: Array) -> Array:
	return list.map(func(e): return "%s#%d" % [e["key"], int(e["count"])])
