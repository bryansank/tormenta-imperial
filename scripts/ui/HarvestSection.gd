extends VBoxContainer
## La seccion "PARA RECOGER" y "CULTIVO" del panel de edificio (2026-10-04).
##
## Para cualquier productor: lo acumulado ([icono] cifra y "12/40") y el boton
## RECOGER, que hace lo mismo que tocar el edificio en el mapa. Para la Granja,
## ademas, los tres cultivos (1 / 5 / 20 min) con lo que rinde cada uno y la
## cuenta atras del que esta creciendo. Estilo "menos texto" (TextKit): iconos y
## cifras a la vista, la explicacion en el tooltip (mantener pulsado en tactil).
## BuildingInfoPanel la crea una vez y llama a show_for() al abrir y a refresh()
## cada fotograma; se oculta sola en lo que no produce.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

var _node: Node = null
var _data: BuildingData = null
var _stock_row: HFlowContainer
var _stock_items: HBoxContainer
var _stock_label: Label
var _collect_btn: Button
var _crop_box: VBoxContainer
var _crop_buttons: Dictionary = {}  # crop_id -> Button
var _growing_label: Label
var _last_stock := {}

func _init() -> void:
	name = "HarvestSection"
	add_theme_constant_override("separation", 6)
	# Lo acumulado y RECOGER en una fila: [madera] 12  12/40  [RECOGER].
	var header := CT.section(Tr.t("LBL_STOCK_HEADER"), "check")
	header.tooltip_text = Tr.t("LBL_STOCK_TIP")
	add_child(header)
	# Se parte si no cabe (RECOGER baja de linea): en la ficha estrecha de PC la
	# fila de la Fundicion salia 50 px por la derecha.
	_stock_row = HFlowContainer.new()
	_stock_row.name = "StockRow"
	_stock_row.add_theme_constant_override("h_separation", 8)
	_stock_row.add_theme_constant_override("v_separation", 4)
	_stock_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_stock_row.tooltip_text = Tr.t("LBL_STOCK_TIP")
	_stock_items = CT.cost_strip({}, {}, "window", "", "number", CT.positive_text())
	_stock_items.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stock_row.add_child(_stock_items)
	_stock_label = CT.label("", "small", CT.text("window", true))
	_stock_label.name = "StockAmount"
	_stock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_row.add_child(_stock_label)
	_collect_btn = CT.pill_button(Tr.t("UI2C_BTN_COLLECT"), "check", "primary", CT.h("small"))
	_collect_btn.name = "CollectButton"
	_collect_btn.tooltip_text = Tr.t("LBL_COLLECT_TIP")
	_collect_btn.pressed.connect(_on_collect)
	_stock_row.add_child(_collect_btn)
	add_child(_stock_row)

	# Cultivo (Granja): tres pastillas, la elegida en azul.
	_crop_box = VBoxContainer.new()
	_crop_box.name = "CropBox"
	_crop_box.add_theme_constant_override("separation", 6)
	var crop_header := CT.section(Tr.t("LBL_CROP_HEADER"), "res:food")
	crop_header.tooltip_text = Tr.t("LBL_CROP_CHANGE_HINT")
	_crop_box.add_child(crop_header)
	var crops := HFlowContainer.new()
	crops.add_theme_constant_override("h_separation", 6)
	crops.add_theme_constant_override("v_separation", 6)
	_crop_box.add_child(crops)
	for crop in GameConfig.farm_crops:
		# "Lechugas · 1 min   +20 [comida]": el nombre lleva su tiempo; la cifra, su icono.
		var btn := CT.text_pill("%s  %s" % [Tr.t(String(crop["name"])), Tr.t("LBL_CROP_YIELD") % int(crop["food"])],
			"secondary", CT.h("small"), "window", "body", "food")
		btn.name = "Crop_" + String(crop["id"])
		btn.toggle_mode = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn.tooltip_text = Tr.t("LBL_CROP_CHANGE_HINT")
		var crop_id := String(crop["id"])
		btn.pressed.connect(func(): _on_crop(crop_id))
		crops.add_child(btn)
		_crop_buttons[crop_id] = btn
	_growing_label = CT.label("", "small", CT.text("window", true))
	_growing_label.name = "Growing"
	_growing_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_crop_box.add_child(_growing_label)
	add_child(_crop_box)

## Lo que ensena para este edificio. Nada si no produce.
func show_for(node: Node, data: BuildingData) -> void:
	_node = node
	_data = data
	_last_stock = {}
	visible = data != null and data.is_producer()
	_crop_box.visible = visible and data.id == ProductionManager.FARM_ID
	refresh()

func refresh() -> void:
	if not visible or _node == null or not is_instance_valid(_node):
		return
	var stock: Dictionary = ProductionManager.get_stock(_node)
	var cap: int = ProductionManager.get_stock_cap(_node)
	var total: int = ProductionManager.get_stock_total(_node)
	var full: bool = total > 0 and ProductionManager.is_full(_node)
	if stock != _last_stock or _stock_items.get_child_count() == 0:
		_last_stock = stock.duplicate()
		var shown := stock.duplicate()
		if shown.is_empty() and _data != null:
			shown = _produced_kinds(_data)
		CT.fill_cost_strip(_stock_items, shown, {}, "window", "", "number",
			CT.positive_text() if total > 0 else CT.text("window", true))
	# "12/40" y, lleno, "LLENO" en aviso; la frase entera, en el tooltip.
	_stock_label.text = Tr.t("LBL_STOCK_AMOUNT") % [total, cap]
	if full:
		_stock_label.text += "  " + Tr.t("LBL_STOCK_FULL_SHORT")
		_stock_row.tooltip_text = Tr.t("LBL_STOCK_FULL")
	else:
		_stock_row.tooltip_text = Tr.t("LBL_STOCK_TIP")
	_stock_label.add_theme_color_override("font_color", CT.tone_color("warning") if full else CT.text("window", true))
	_collect_btn.disabled = total <= 0
	if _crop_box.visible:
		var current: String = ProductionManager.get_crop(_node)
		for crop_id in _crop_buttons:
			var b := _crop_buttons[crop_id] as Button
			var on: bool = crop_id == current
			b.set_pressed_no_signal(on)
			# La elegida en azul (selector, docs/28 §7); solo se repinta al cambiar.
			if bool(b.get_meta("crop_on", false)) != on or not b.has_meta("crop_on"):
				b.set_meta("crop_on", on)
				CT.style_text_pill(b, "info" if on else "secondary", CT.h("small"), "window", "body")
		var crop: Dictionary = GameConfig.get_crop(current)
		_growing_label.text = Tr.t("LBL_CROP_GROWING") % TextKit.short_time(ProductionManager.get_cycle_remaining(_node))
		_growing_label.tooltip_text = Tr.t(String(crop.get("name", "")))

## Lo que hace un productor, a cero: para que la fila vacia diga "[comida] 0".
static func _produced_kinds(data: BuildingData) -> Dictionary:
	var out := {}
	for pair in [["gold", data.produces_gold], ["steel", data.produces_steel], ["oil", data.produces_oil],
			["wood", data.produces_wood], ["food", data.produces_food]]:
		if int(pair[1]) > 0:
			out[pair[0]] = 0
	if out.is_empty() and data.id == ProductionManager.FARM_ID:
		out["food"] = 0
	return out

func _on_collect() -> void:
	if _node != null and is_instance_valid(_node):
		ProductionManager.collect(_node)
	refresh()

func _on_crop(crop_id: String) -> void:
	if _node != null and is_instance_valid(_node):
		ProductionManager.plant_crop(_node, crop_id)
	refresh()
