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

var _node: Node = null
var _data: BuildingData = null
var _stock_row: HBoxContainer
var _stock_items: HBoxContainer
var _stock_label: Label
var _collect_btn: Button
var _crop_box: VBoxContainer
var _crop_buttons: Dictionary = {}  # crop_id -> Button
var _growing_label: Label
var _last_stock := {}

func _init() -> void:
	name = "HarvestSection"
	add_theme_constant_override("separation", 4)
	var header := UITheme.section_header(Tr.t("LBL_STOCK_HEADER"), UITheme.ACCENT)
	header.tooltip_text = Tr.t("LBL_STOCK_TIP")
	add_child(header)
	_stock_row = HBoxContainer.new()
	_stock_row.name = "StockRow"
	_stock_row.add_theme_constant_override("separation", 8)
	_stock_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_stock_row.tooltip_text = Tr.t("LBL_STOCK_TIP")
	_stock_items = TextKit.cost_inline({}, {}, "body", UITheme.POSITIVE)
	_stock_row.add_child(_stock_items)
	_stock_label = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	_stock_label.name = "StockAmount"
	_stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stock_row.add_child(_stock_label)
	add_child(_stock_row)
	_collect_btn = Button.new()
	_collect_btn.name = "CollectButton"
	_collect_btn.text = Tr.t("BTN_COLLECT")
	_collect_btn.tooltip_text = Tr.t("LBL_COLLECT_TIP")
	_collect_btn.custom_minimum_size.y = 48
	UITheme.style_button(_collect_btn, UITheme.POSITIVE.darkened(0.2), UITheme.FONT_SECTION)
	_collect_btn.pressed.connect(_on_collect)
	add_child(_collect_btn)

	_crop_box = VBoxContainer.new()
	_crop_box.name = "CropBox"
	_crop_box.add_theme_constant_override("separation", 4)
	var crop_header := UITheme.section_header(Tr.t("LBL_CROP_HEADER"), UITheme.ACCENT)
	crop_header.tooltip_text = Tr.t("LBL_CROP_CHANGE_HINT")
	_crop_box.add_child(crop_header)
	var food_icon := TextKit.res_icon("food")
	for crop in GameConfig.farm_crops:
		var btn := Button.new()
		btn.name = "Crop_" + String(crop["id"])
		btn.toggle_mode = true
		btn.custom_minimum_size.y = 44
		# "Lechugas · 1 min   [comida] +20": el nombre lleva su tiempo; la cifra, su icono.
		btn.text = "%s   %s" % [Tr.t(String(crop["name"])), Tr.t("LBL_CROP_YIELD") % int(crop["food"])]
		if food_icon != null:
			btn.icon = food_icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			btn.expand_icon = false
		btn.tooltip_text = Tr.t("LBL_CROP_CHANGE_HINT")
		UITheme.style_button(btn, UITheme.BTN, UITheme.FONT_BODY)
		var crop_id := String(crop["id"])
		btn.pressed.connect(func(): _on_crop(crop_id))
		_crop_box.add_child(btn)
		_crop_buttons[crop_id] = btn
	_growing_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
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
		TextKit.fill_cost_row(_stock_items, shown, {}, "body", UITheme.POSITIVE if total > 0 else UITheme.TEXT_DIM)
	# "12/40" y, lleno, "LLENO" en aviso; la frase entera, en el tooltip.
	_stock_label.text = Tr.t("LBL_STOCK_AMOUNT") % [total, cap]
	if full:
		_stock_label.text += "  " + Tr.t("LBL_STOCK_FULL_SHORT")
		_stock_row.tooltip_text = Tr.t("LBL_STOCK_FULL")
	else:
		_stock_row.tooltip_text = Tr.t("LBL_STOCK_TIP")
	UITheme.set_label_color(_stock_label, UITheme.WARNING if full else (UITheme.POSITIVE if total > 0 else UITheme.TEXT_DIM))
	_collect_btn.disabled = total <= 0
	if _crop_box.visible:
		var current: String = ProductionManager.get_crop(_node)
		for crop_id in _crop_buttons:
			(_crop_buttons[crop_id] as Button).set_pressed_no_signal(crop_id == current)
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
