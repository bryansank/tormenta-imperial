extends CanvasLayer
## Panel de recursos, esquina superior izquierda: [icono] cantidad por cada
## recurso desbloqueado y, debajo, UNA barra de almacen.
##
## El almacen es una bolsa compartida: un solo tope para la suma de los cuatro.
## Antes el HUD ensenaba "528/600" pegado a un recurso y mentia: parecia el tope
## de ese recurso. Ahora el tope sale una vez, bajo los cuatro, y la barra ensena
## como se reparte la bolsa. Cuando se llena, la barra y el numero se ponen
## rojos: lo que entre a partir de ahi se pierde y el jugador tiene que verlo.
##
## Los iconos (moneda, tronco, lingote, gota) los genera
## tools/gen_resource_icons.gd; los estilos salen todos de UITheme.

var _panel: PanelContainer
var _chips: Dictionary = {}     # Type -> HBoxContainer (UITheme.make_resource_chip)
var _segments: Dictionary = {}  # Type -> ColorRect, su tajada de la barra
var _free_segment: ColorRect
var _pool_bar: PanelContainer
var _storage_label: Label
var _storage_value: Label

## En orden de era: lo primero que ve un jugador nuevo es oro y madera.
var _resource_ids := ["gold", "wood", "steel", "oil"]
var _resource_types := [
	ResourceManager.Type.GOLD, ResourceManager.Type.WOOD,
	ResourceManager.Type.STEEL, ResourceManager.Type.OIL,
]

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.resources_insufficient.connect(_on_insufficient)
	EventBus.resource_unlocked.connect(_on_resource_unlocked)
	EventBus.storage_overflow.connect(_on_overflow)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ResourceHUD", _panel)
	_panel.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# ── Fila de fichas: [icono] cantidad, una por recurso desbloqueado ──
	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 14)
	vbox.add_child(chips_row)

	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var chip := UITheme.make_resource_chip(_resource_ids[i])
		chip.visible = ResourceManager.is_unlocked(type)
		chips_row.add_child(chip)
		_chips[type] = chip

	# ── Almacen: un nombre, un numero, una barra ──
	var storage_row := HBoxContainer.new()
	storage_row.add_theme_constant_override("separation", 6)
	vbox.add_child(storage_row)

	_storage_label = UITheme.make_label(Tr.t("LBL_STORAGE_USED").to_upper(), "small", UITheme.TEXT_DIM)
	_storage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_row.add_child(_storage_label)

	_storage_value = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_storage_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	storage_row.add_child(_storage_value)

	var colors: Array = []
	for res_id in _resource_ids:
		colors.append(UITheme.resource_color(res_id))
	_pool_bar = UITheme.make_pool_bar(colors, 8)
	vbox.add_child(_pool_bar)
	var segs := UITheme.pool_bar_segments(_pool_bar)
	for i in range(_resource_types.size()):
		_segments[_resource_types[i]] = segs[i]
	_free_segment = UITheme.pool_bar_free(_pool_bar)

	_refresh()

## Una bolsa significa un refresco: cualquier recurso que se mueva cambia el
## total compartido, asi que no hay nada que actualizar por separado.
func _refresh() -> void:
	var cap := ResourceManager.get_storage_cap()
	var total := ResourceManager.get_total_stored()
	var is_full := total >= cap

	for type in _chips:
		UITheme.chip_amount(_chips[type]).text = str(ResourceManager.get_amount(type))

	# Rojo mientras la bolsa esta llena: desde aqui, lo producido se pierde.
	var tone: Color = UITheme.DANGER if is_full else UITheme.TEXT_DIM
	_storage_value.text = "%d / %d" % [total, cap]
	UITheme.set_label_color(_storage_value, tone)
	UITheme.set_label_color(_storage_label, tone)
	UITheme.set_pool_bar_alert(_pool_bar, is_full)

	for type in _segments:
		var seg_amt := ResourceManager.get_amount(type)
		_segments[type].visible = seg_amt > 0
		_segments[type].size_flags_stretch_ratio = maxf(0.001, float(seg_amt))
	var free := maxi(0, cap - total)
	_free_segment.visible = free > 0
	_free_segment.size_flags_stretch_ratio = maxf(0.001, float(free))

func _on_resource_changed(_resource_type: String, _new_amount: int, _delta: int) -> void:
	_refresh()

func _on_resource_unlocked(resource_name: String) -> void:
	var type := _type_of(resource_name)
	if type < 0 or not _chips.has(type):
		return
	var chip: HBoxContainer = _chips[type]
	chip.visible = true
	# Destello al desbloquear: el jugador acaba de abrir una era y la fila
	# cambia de forma; sin aviso, el recurso nuevo aparece sin mas.
	chip.modulate = Color(2.5, 2.0, 0.5, 0.0)
	var tween := create_tween()
	tween.tween_property(chip, "modulate", Color(1.5, 1.3, 0.8, 1.0), 0.4)
	tween.tween_property(chip, "modulate", Color.WHITE, 1.0)
	_refresh()

## Falta un recurso: parpadea SU cifra y se avisa por el canal de mensajes.
## Antes era un texto flotante en el centro de la pantalla, encima del banner
## de la Tormenta y del objetivo; el aviso es efimero, pero tapaba.
func _on_insufficient(resource_type: String, required: int, available: int) -> void:
	var type := _type_of(resource_type)
	if type >= 0 and _chips.has(type):
		UITheme.flash_label(UITheme.chip_amount(_chips[type]), UITheme.TEXT_BRIGHT)
	EventBus.notification_posted.emit(
		Tr.t("FMT_NOT_ENOUGH_OF") % [Tr.res_name(resource_type), available, required],
		"warning", UITheme.WARNING)

## Desborde: la barra ya esta roja por _refresh; un parpadeo marca el momento
## exacto en que algo se ha perdido, que es lo que el jugador no veia.
func _on_overflow(_resource_type: String, _lost: int, _cap: int) -> void:
	_refresh()
	var tween := create_tween()
	tween.tween_property(_pool_bar, "modulate", Color(1.6, 1.2, 1.2, 1.0), 0.15)
	tween.tween_property(_pool_bar, "modulate", Color.WHITE, 0.5)

func _type_of(resource_name: String) -> int:
	var idx := _resource_ids.find(resource_name)
	return int(_resource_types[idx]) if idx >= 0 else -1
