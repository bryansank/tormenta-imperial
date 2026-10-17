extends RefCounted
## Piezas para decir mas con menos texto (rama feat/menos-texto, 2026-10-04):
## icono + numero en vez de frase, tiempos cortos y costes en fila.
##
##   TextKit.cost_row({"gold": 50, "wood": 30}, {"wood": 20})
##       -> [oro] 50  [madera] 30, el 30 en rojo porque falta
##   TextKit.short_time(90)  -> "1:30"
##   TextKit.cost_text({"gold": 50}) -> "50 oro" (para botones, que no llevan iconos)
##
## Un recurso sin icono (los materiales del taller) se escribe con su nombre.
## Cada ficha lleva el nombre del recurso en el tooltip.
##
## Se usa con `preload`, no con class_name, como HelpCatalog.

## Lado de los iconos de una fila de costes.
const ICON_PX := 20

## "45 s", "1:30" o "2 h" / "2 h 15". Para cuentas atras y duraciones.
static func short_time(seconds: float) -> String:
	var s: int = maxi(0, ceili(seconds))
	if s < 60:
		return "%d s" % s
	if s < 3600:
		return "%d:%02d" % [floori(s / 60.0), s % 60]
	var h: int = floori(s / 3600.0)
	var m: int = floori((s % 3600) / 60.0)
	return "%d h" % h if m == 0 else "%d h %02d" % [h, m]

## El icono del recurso, o null si no lo tiene (los materiales del taller).
static func res_icon(res_id: String) -> Texture2D:
	if not (res_id in ["gold", "wood", "steel", "oil", "food"]):
		return null
	return UITheme.icon_texture(res_id, ICON_PX)

## Fila de cantidades por recurso: [icono] cifra, una ficha por recurso. Las que
## esten en `short` van en rojo (lo que falta). `prefix` va delante de cada cifra
## ("+" para lo que se produce). La fila guarda el diccionario en meta "amounts"
## y cada cifra se llama "Amount_<recurso>", para las pruebas.
static func cost_row(amounts: Dictionary, short: Dictionary = {}, size_name: String = "small",
		color: Color = UITheme.TEXT, prefix: String = "") -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "CostRow"
	row.add_theme_constant_override("h_separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	fill_cost_row(row, amounts, short, size_name, color, prefix)
	return row

## Como cost_row, pero en una fila que no se parte: para meterla dentro de otra
## fila (un HFlow dentro de otro se queda con el ancho de una ficha y apila).
static func cost_inline(amounts: Dictionary, short: Dictionary = {}, size_name: String = "small",
		color: Color = UITheme.TEXT, prefix: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CostRow"
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	fill_cost_row(row, amounts, short, size_name, color, prefix)
	return row

## Rehace el contenido de una fila de cost_row o cost_inline con otras cifras.
static func fill_cost_row(row: Container, amounts: Dictionary, short: Dictionary = {},
		size_name: String = "small", color: Color = UITheme.TEXT, prefix: String = "") -> void:
	# Las mismas cifras, lo mismo en rojo y el mismo estilo: la fila ya dice eso
	# y no se rehace (llega una senal por recurso y por tick; docs/26 §6.9).
	var sig := [amounts, short, size_name, color, prefix, UITheme.DANGER]
	if row.has_meta("fill_sig") and row.get_meta("fill_sig") == sig and row.get_child_count() == amounts.size():
		return
	row.set_meta("fill_sig", sig)
	for child in row.get_children():
		row.remove_child(child)
		child.free()
	row.set_meta("amounts", amounts.duplicate())
	for res_id in amounts:
		var id := String(res_id)
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var missing: int = int(short.get(id, 0))
		chip.tooltip_text = Tr.res_cap(id) if missing <= 0 else "%s · %s" % [Tr.res_cap(id), Tr.t("OBJ_MISSING") % ("%d" % missing)]
		var icon := res_icon(id)
		var text := "%s%d" % [prefix, int(amounts[id])]
		if icon != null:
			var rect := TextureRect.new()
			rect.texture = icon
			rect.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(rect)
		else:
			text += " " + Tr.res_name(id)
		var label := UITheme.make_label(text, size_name, UITheme.DANGER if missing > 0 else color)
		label.name = "Amount_" + id
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(label)
		row.add_child(chip)

## Lo que dice una fila, en texto plano ("50 oro · 30 madera"): para pruebas y
## para botones, que no llevan una fila de iconos dentro.
static func cost_text(amounts: Dictionary, prefix: String = "") -> String:
	var parts: Array = []
	for res_id in amounts:
		parts.append("%s%d %s" % [prefix, int(amounts[res_id]), Tr.res_name(String(res_id))])
	return " · ".join(parts)

## Las cifras de una fila hecha con cost_row, por recurso, leidas de sus
## etiquetas: lo que de verdad ve el jugador.
static func row_amounts(row: Control) -> Dictionary:
	var out := {}
	if row == null:
		return out
	for chip in row.get_children():
		for child in chip.get_children():
			if child is Label and String(child.name).begins_with("Amount_"):
				out[String(child.name).substr(7)] = (child as Label).text
	return out
