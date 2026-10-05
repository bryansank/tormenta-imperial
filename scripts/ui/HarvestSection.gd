extends VBoxContainer
## La seccion "PARA RECOGER" y "CULTIVO" del panel de edificio (2026-10-04).
##
## Para cualquier productor: lo acumulado (con su tope) y el boton RECOGER, que
## hace lo mismo que tocar el edificio en el mapa. Para la Granja, ademas, los
## tres cultivos (1 / 5 / 20 min) con lo que rinde cada uno y lo que le falta al
## que esta creciendo. BuildingInfoPanel la crea una vez y llama a show_for() al
## abrir y a refresh() cada fotograma; se oculta sola en lo que no produce.

var _node: Node = null
var _data: BuildingData = null
var _stock_label: Label
var _collect_btn: Button
var _crop_box: VBoxContainer
var _crop_buttons: Dictionary = {}  # crop_id -> Button
var _growing_label: Label

func _init() -> void:
	name = "HarvestSection"
	add_theme_constant_override("separation", 4)
	add_child(UITheme.section_header(Tr.t("LBL_STOCK_HEADER"), UITheme.ACCENT))
	_stock_label = UITheme.make_label("", "body", UITheme.TEXT)
	_stock_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_stock_label)
	_collect_btn = Button.new()
	_collect_btn.name = "CollectButton"
	_collect_btn.text = Tr.t("BTN_COLLECT")
	_collect_btn.custom_minimum_size.y = 48
	UITheme.style_button(_collect_btn, UITheme.POSITIVE.darkened(0.2), UITheme.FONT_SECTION)
	_collect_btn.pressed.connect(_on_collect)
	add_child(_collect_btn)

	_crop_box = VBoxContainer.new()
	_crop_box.name = "CropBox"
	_crop_box.add_theme_constant_override("separation", 4)
	_crop_box.add_child(UITheme.section_header(Tr.t("LBL_CROP_HEADER"), UITheme.ACCENT))
	for crop in GameConfig.farm_crops:
		var btn := Button.new()
		btn.name = "Crop_" + String(crop["id"])
		btn.toggle_mode = true
		btn.custom_minimum_size.y = 44
		btn.text = "%s   %s" % [Tr.t(String(crop["name"])), Tr.t("LBL_CROP_YIELD") % int(crop["food"])]
		UITheme.style_button(btn, UITheme.BTN, UITheme.FONT_BODY)
		var crop_id := String(crop["id"])
		btn.pressed.connect(func(): _on_crop(crop_id))
		_crop_box.add_child(btn)
		_crop_buttons[crop_id] = btn
	_growing_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_growing_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_crop_box.add_child(_growing_label)
	var hint := UITheme.make_label(Tr.t("LBL_CROP_CHANGE_HINT"), "small", UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_crop_box.add_child(hint)
	add_child(_crop_box)

## Lo que ensena para este edificio. Nada si no produce.
func show_for(node: Node, data: BuildingData) -> void:
	_node = node
	_data = data
	visible = data != null and data.is_producer()
	_crop_box.visible = visible and data.id == ProductionManager.FARM_ID
	refresh()

func refresh() -> void:
	if not visible or _node == null or not is_instance_valid(_node):
		return
	var stock: Dictionary = ProductionManager.get_stock(_node)
	var cap: int = ProductionManager.get_stock_cap(_node)
	var total: int = ProductionManager.get_stock_total(_node)
	if total <= 0:
		_stock_label.text = Tr.t("LBL_STOCK_EMPTY") % cap
		UITheme.set_label_color(_stock_label, UITheme.TEXT_DIM)
	elif ProductionManager.is_full(_node):
		_stock_label.text = "%s\n%s" % [Tr.t("LBL_STOCK_AMOUNT") % [Tr.amount_list(stock), total, cap], Tr.t("LBL_STOCK_FULL")]
		UITheme.set_label_color(_stock_label, UITheme.WARNING)
	else:
		_stock_label.text = Tr.t("LBL_STOCK_AMOUNT") % [Tr.amount_list(stock), total, cap]
		UITheme.set_label_color(_stock_label, UITheme.POSITIVE)
	_collect_btn.disabled = total <= 0
	if _crop_box.visible:
		var current: String = ProductionManager.get_crop(_node)
		for crop_id in _crop_buttons:
			(_crop_buttons[crop_id] as Button).set_pressed_no_signal(crop_id == current)
		var crop: Dictionary = GameConfig.get_crop(current)
		_growing_label.text = Tr.t("LBL_CROP_GROWING") % [Tr.t(String(crop.get("name", ""))),
			ProductionManager.eta_text(ProductionManager.get_cycle_remaining(_node))]

func _on_collect() -> void:
	if _node != null and is_instance_valid(_node):
		ProductionManager.collect(_node)
	refresh()

func _on_crop(crop_id: String) -> void:
	if _node != null and is_instance_valid(_node):
		ProductionManager.plant_crop(_node, crop_id)
	refresh()
