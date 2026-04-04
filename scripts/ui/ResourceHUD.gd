extends CanvasLayer
## Collapsible resource panel — top-left corner.
## Collapsed: compact colored dots + amounts.  Expanded: full bars + storage info.

var _labels: Dictionary = {}       # Type -> Label (collapsed amounts)
var _exp_labels: Dictionary = {}   # Type -> Label (expanded amounts)
var _items: Dictionary = {}        # Type -> Control (collapsed row items)
var _exp_rows: Dictionary = {}     # Type -> Control (expanded rows)
var _bars: Dictionary = {}         # Type -> ProgressBar
var _panel: PanelContainer
var _content_box: VBoxContainer
var _toggle_btn: Button
var _storage_label: Label
var _feedback_label: Label
var _feedback_tween: Tween
var _is_expanded := false

var _resource_ids := ["gold", "steel", "oil", "wood"]
var _resource_types := [
	ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
	ResourceManager.Type.OIL, ResourceManager.Type.WOOD,
]
var _resource_colors := [UITheme.RES_GOLD, UITheme.RES_STEEL, UITheme.RES_OIL, UITheme.RES_WOOD]
var _resource_symbols := ["\u25C6", "\u2B23", "\u25CF", "\u25A0"]  # ◆ ⬣ ● ■

func _ready() -> void:
	layer = 10
	_setup_ui()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.resources_insufficient.connect(_on_insufficient)
	EventBus.resource_unlocked.connect(_on_resource_unlocked)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ResourceHUD", _panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.05, 0.92)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.border_color = UITheme.ACCENT
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 5
	style.shadow_offset = Vector2(1, 2)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(main_vbox)

	# ── Collapsed row: toggle + dots + amounts ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header)

	_toggle_btn = Button.new()
	_toggle_btn.text = "\u25BC"  # ▼
	_toggle_btn.custom_minimum_size = Vector2(22, 22)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0, 0, 0, 0)
	tb.set_content_margin_all(1)
	_toggle_btn.add_theme_stylebox_override("normal", tb)
	_toggle_btn.add_theme_stylebox_override("hover", tb)
	_toggle_btn.add_theme_stylebox_override("pressed", tb)
	_toggle_btn.add_theme_font_size_override("font_size", 10)
	_toggle_btn.add_theme_color_override("font_color", UITheme.ACCENT)
	_toggle_btn.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)
	_toggle_btn.pressed.connect(_toggle_expanded)
	header.add_child(_toggle_btn)

	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var color: Color = _resource_colors[i]
		var symbol: String = _resource_symbols[i]

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 2)

		var dot := Label.new()
		dot.text = symbol
		dot.add_theme_font_size_override("font_size", 12)
		dot.add_theme_color_override("font_color", color)
		item.add_child(dot)

		var amt := Label.new()
		amt.text = str(ResourceManager.get_amount(type))
		amt.add_theme_font_size_override("font_size", 13)
		amt.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
		item.add_child(amt)
		_labels[type] = amt

		header.add_child(item)
		_items[type] = item
		item.visible = ResourceManager.is_unlocked(type)

	# Storage compact
	_storage_label = Label.new()
	_storage_label.text = "/%d" % ResourceManager.get_storage_cap()
	_storage_label.add_theme_font_size_override("font_size", 10)
	_storage_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	header.add_child(_storage_label)

	# Clear save button (always visible in header)
	var clear_btn := Button.new()
	clear_btn.text = Tr.t("BTN_CLEAR")
	clear_btn.custom_minimum_size = Vector2(60, 22)
	clear_btn.add_theme_font_size_override("font_size", 10)
	clear_btn.add_theme_color_override("font_color", UITheme.DANGER)
	clear_btn.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)
	var clr_s := StyleBoxFlat.new()
	clr_s.bg_color = UITheme.DANGER.darkened(0.7)
	clr_s.set_corner_radius_all(3)
	clr_s.set_content_margin_all(3)
	clr_s.border_color = UITheme.DANGER.darkened(0.3)
	clr_s.set_border_width_all(1)
	clear_btn.add_theme_stylebox_override("normal", clr_s)
	var clr_h := clr_s.duplicate()
	clr_h.bg_color = UITheme.DANGER.darkened(0.4)
	clear_btn.add_theme_stylebox_override("hover", clr_h)
	clear_btn.add_theme_stylebox_override("pressed", clr_h)
	clear_btn.pressed.connect(func(): GameManager.clear_save())
	header.add_child(clear_btn)

	# ── Expanded detail rows ──
	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 4)
	_content_box.visible = false
	main_vbox.add_child(_content_box)

	_content_box.add_child(UITheme.make_separator())

	for i in range(_resource_ids.size()):
		var type: ResourceManager.Type = _resource_types[i]
		var res_id: String = _resource_ids[i]
		var color: Color = _resource_colors[i]
		var symbol: String = _resource_symbols[i]

		var row_box := VBoxContainer.new()
		row_box.add_theme_constant_override("separation", 2)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)

		var dot := Label.new()
		dot.text = symbol
		dot.add_theme_font_size_override("font_size", 13)
		dot.add_theme_color_override("font_color", color)
		row.add_child(dot)

		var name_lbl := Label.new()
		name_lbl.text = Tr.res_upper(res_id)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", color.darkened(0.1))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var amt_lbl := Label.new()
		amt_lbl.text = str(ResourceManager.get_amount(type))
		amt_lbl.add_theme_font_size_override("font_size", 14)
		amt_lbl.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amt_lbl)
		_exp_labels[type] = amt_lbl

		row_box.add_child(row)

		# Storage bar
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(140, 5)
		bar.max_value = ResourceManager.get_storage_cap()
		bar.value = ResourceManager.get_amount(type)
		bar.show_percentage = false
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.05, 0.04)
		bg.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = color.darkened(0.25)
		fill.set_corner_radius_all(1)
		bar.add_theme_stylebox_override("fill", fill)
		row_box.add_child(bar)
		_bars[type] = bar

		_content_box.add_child(row_box)
		_exp_rows[type] = row_box
		row_box.visible = ResourceManager.is_unlocked(type)


func _toggle_expanded() -> void:
	_is_expanded = not _is_expanded
	_content_box.visible = _is_expanded
	_toggle_btn.text = "\u25B2" if _is_expanded else "\u25BC"
	if _is_expanded:
		_sync_expanded()

func _sync_expanded() -> void:
	var cap := ResourceManager.get_storage_cap()
	for type in _exp_labels:
		var amt := ResourceManager.get_amount(type)
		_exp_labels[type].text = str(amt)
		if _bars.has(type):
			_bars[type].max_value = cap
			_bars[type].value = amt

func _on_resource_changed(resource_type: String, new_amount: int, _delta: int) -> void:
	var cap := ResourceManager.get_storage_cap()
	for type in _labels:
		if ResourceManager.get_type_name(type) == resource_type:
			_labels[type].text = str(new_amount)
			var at_cap := new_amount >= cap
			_labels[type].add_theme_color_override("font_color", UITheme.WARNING if at_cap else UITheme.TEXT_BRIGHT)
			if _exp_labels.has(type):
				_exp_labels[type].text = str(new_amount)
				_exp_labels[type].add_theme_color_override("font_color", UITheme.WARNING if at_cap else UITheme.TEXT_BRIGHT)
			if _bars.has(type):
				_bars[type].max_value = cap
				_bars[type].value = new_amount
			_storage_label.text = "/%d" % cap
			break

func _on_resource_unlocked(resource_name: String) -> void:
	for i in range(_resource_ids.size()):
		if _resource_ids[i] == resource_name:
			var type: ResourceManager.Type = _resource_types[i]
			if _items.has(type):
				_items[type].visible = true
				_items[type].modulate = Color(2.5, 2.0, 0.5, 0.0)
				var tween := create_tween()
				tween.tween_property(_items[type], "modulate", Color(1.5, 1.3, 0.8, 1.0), 0.4)
				tween.tween_property(_items[type], "modulate", Color.WHITE, 1.0)
			if _exp_rows.has(type):
				_exp_rows[type].visible = true
			break

func _on_insufficient(_resource_type: String, _required: int, _available: int) -> void:
	_show_feedback(Tr.t("LBL_NOT_ENOUGH_RESOURCES"))

func _show_feedback(text: String) -> void:
	if not _feedback_label:
		_feedback_label = Label.new()
		_feedback_label.add_theme_font_size_override("font_size", 15)
		_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		_feedback_label.add_theme_constant_override("outline_size", 3)
		_feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_feedback_label.position.y = 10
		_feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(_feedback_label)
	_feedback_label.text = text
	_feedback_label.modulate.a = 1.0
	_feedback_label.visible = true
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.5)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.8)
	_feedback_tween.tween_callback(func(): _feedback_label.visible = false)
