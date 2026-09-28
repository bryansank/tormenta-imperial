extends CanvasLayer
## Collapsible resource panel — top-left corner.
## Collapsed: compact colored dots + amounts + the shared storage counter.
## Expanded: per-resource amounts + one bar showing how the single pool is split.
##
## Storage is one shared bag for all four resources, so there is one number and one
## bar here, not four bars racing the same ceiling. While the bag is full the counter
## turns red: incoming harvest is being lost and the player has to see it happen.

var _labels: Dictionary = {}       # Type -> Label (collapsed amounts)
var _exp_labels: Dictionary = {}   # Type -> Label (expanded amounts)
var _items: Dictionary = {}        # Type -> Control (collapsed row items)
var _exp_rows: Dictionary = {}     # Type -> Control (expanded rows)
var _segments: Dictionary = {}     # Type -> ColorRect (its slice of the shared bar)
var _free_segment: ColorRect
var _panel: PanelContainer
var _content_box: VBoxContainer
var _toggle_btn: Button
var _storage_label: Label
var _storage_detail_label: Label
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
	UITheme.set_label_color(_toggle_btn, UITheme.ACCENT)
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
		UITheme.set_label_color(dot, color)
		item.add_child(dot)

		var amt := Label.new()
		amt.text = str(ResourceManager.get_amount(type))
		amt.add_theme_font_size_override("font_size", 13)
		UITheme.set_label_color(amt, UITheme.TEXT_BRIGHT)
		item.add_child(amt)
		_labels[type] = amt

		header.add_child(item)
		_items[type] = item
		item.visible = ResourceManager.is_unlocked(type)

	# Shared storage: everything stored, against the one cap.
	_storage_label = Label.new()
	_storage_label.add_theme_font_size_override("font_size", 10)
	header.add_child(_storage_label)

	# Dev-only shortcut to wipe the save. Players use Settings > New game instead.
	if GameConfig.dev_mode:
		var clear_btn := Button.new()
		clear_btn.text = Tr.t("BTN_CLEAR")
		clear_btn.custom_minimum_size = Vector2(60, 22)
		clear_btn.add_theme_font_size_override("font_size", 10)
		UITheme.set_label_color(clear_btn, UITheme.DANGER)
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
		clear_btn.pressed.connect(GameManager.request_new_game)
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
		UITheme.set_label_color(dot, color)
		row.add_child(dot)

		var name_lbl := Label.new()
		name_lbl.text = Tr.res_upper(res_id)
		name_lbl.add_theme_font_size_override("font_size", 11)
		UITheme.set_label_color(name_lbl, color)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var amt_lbl := Label.new()
		amt_lbl.text = str(ResourceManager.get_amount(type))
		amt_lbl.add_theme_font_size_override("font_size", 14)
		UITheme.set_label_color(amt_lbl, UITheme.TEXT_BRIGHT)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amt_lbl)
		_exp_labels[type] = amt_lbl

		row_box.add_child(row)

		_content_box.add_child(row_box)
		_exp_rows[type] = row_box
		row_box.visible = ResourceManager.is_unlocked(type)

	# The shared pool, as one bar split by what is actually inside it: the slices
	# push each other, which is the whole point of the system.
	_content_box.add_child(UITheme.make_separator())

	_storage_detail_label = Label.new()
	_storage_detail_label.add_theme_font_size_override("font_size", 11)
	UITheme.set_label_color(_storage_detail_label, UITheme.TEXT_DIM)
	_content_box.add_child(_storage_detail_label)

	var bar_box := HBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 0)
	bar_box.custom_minimum_size = Vector2(150, 7)
	_content_box.add_child(bar_box)

	for i in range(_resource_ids.size()):
		var seg_type: ResourceManager.Type = _resource_types[i]
		var seg := ColorRect.new()
		seg.color = _resource_colors[i].darkened(0.2)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(0, 7)
		bar_box.add_child(seg)
		_segments[seg_type] = seg

	_free_segment = ColorRect.new()
	_free_segment.color = Color(0.07, 0.08, 0.06)
	_free_segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_segment.custom_minimum_size = Vector2(0, 7)
	bar_box.add_child(_free_segment)

	_refresh()


func _toggle_expanded() -> void:
	_is_expanded = not _is_expanded
	_content_box.visible = _is_expanded
	_toggle_btn.text = "\u25B2" if _is_expanded else "\u25BC"
	if _is_expanded:
		_refresh()

## One pool means one refresh: any resource moving changes the shared total, so
## there is nothing meaningful to update in isolation.
func _refresh() -> void:
	var cap := ResourceManager.get_storage_cap()
	var total := ResourceManager.get_total_stored()
	var is_full := total >= cap

	for type in _labels:
		var amt := ResourceManager.get_amount(type)
		_labels[type].text = str(amt)
		if _exp_labels.has(type):
			_exp_labels[type].text = str(amt)

	# Red while the bag is full: from here on, anything produced is being lost.
	_storage_label.text = "%d/%d" % [total, cap]
	UITheme.set_label_color(_storage_label, UITheme.DANGER if is_full else UITheme.TEXT_DIM)

	if not _storage_detail_label:
		return
	_storage_detail_label.text = "%s  %d/%d" % [Tr.t("LBL_STORAGE_USED"), total, cap]
	UITheme.set_label_color(_storage_detail_label, UITheme.DANGER if is_full else UITheme.TEXT_DIM)

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
		UITheme.set_label_color(_feedback_label, UITheme.DANGER)
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
