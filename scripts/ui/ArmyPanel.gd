extends CanvasLayer
## Army / Barracks panel: train units, see Military Power, capacity and upkeep.
## The management → combat bridge — a bigger base fields a stronger army.

var _panel: PanelContainer
var _backdrop: ColorRect
var _army_btn: Button
var _is_open := false
var _sidebar_visible := false

var _power_label: Label
var _capacity_label: Label
var _slots_label: Label
var _units_vbox: VBoxContainer
var _training_vbox: VBoxContainer
var _training_bars: Array = []  # ProgressBar refs, index-aligned with ArmyManager.get_training()

const MILITARY := Color(0.8, 0.35, 0.25)  # matches UITheme.CAT_MILITARY

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "ArmyPanel.modal")
	EventBus.army_changed.connect(_refresh)
	EventBus.era_advanced.connect(_on_era_advanced)
	EventBus.resource_unlocked.connect(func(_r): _refresh())
	EventBus.building_placed.connect(func(_d, _c): _on_base_changed())
	EventBus.building_demolished.connect(func(_n, _c): _on_base_changed())
	EventBus.game_load_completed.connect(_on_base_changed)
	EventBus.army_upkeep_unpaid.connect(_on_upkeep_unpaid)
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	_update_button_visibility()

func _process(_delta: float) -> void:
	if not _is_open:
		return
	_update_training_progress()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sidebar button (hamburger menu)
	_army_btn = Button.new()
	_army_btn.text = Tr.t("BTN_ARMY")
	_army_btn.custom_minimum_size = Vector2(140, 38)
	_army_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_army_btn.offset_left = -152
	_army_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ArmyPanel.button")
	UITheme.style_card_button(_army_btn, UITheme.BTN.lightened(0.05), MILITARY)
	_army_btn.pressed.connect(_toggle_panel)
	_army_btn.visible = false
	root.add_child(_army_btn)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	# Modal
	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ArmyPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_ARMY_TITLE"), _toggle_panel))

	# Summary
	_power_label = UITheme.make_label("", "title", MILITARY)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_power_label)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 20)
	_capacity_label = UITheme.make_label("", "body", UITheme.TEXT)
	_slots_label = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	stats_row.add_child(_capacity_label)
	stats_row.add_child(_slots_label)
	vbox.add_child(stats_row)

	vbox.add_child(UITheme.make_separator())

	# Unit list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_units_vbox = VBoxContainer.new()
	_units_vbox.add_theme_constant_override("separation", 6)
	_units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_units_vbox)

	vbox.add_child(UITheme.make_separator())

	# In-training section
	vbox.add_child(UITheme.make_label(Tr.t("LBL_ARMY_IN_TRAINING"), "section", UITheme.ACCENT))
	_training_vbox = VBoxContainer.new()
	_training_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(_training_vbox)

	_refresh()

# ── Refresh ──

func _refresh(_arg = null) -> void:
	if not _power_label:
		return
	_power_label.text = Tr.t("LBL_MILITARY_POWER") % ArmyManager.get_power()
	_capacity_label.text = Tr.t("LBL_ARMY_CAPACITY") % [ArmyManager.get_used_capacity(), ArmyManager.get_capacity()]
	_slots_label.text = Tr.t("LBL_ARMY_SLOTS") % [ArmyManager.get_training().size(), ArmyManager.max_slots()]
	_rebuild_units()
	_rebuild_training()

func _rebuild_units() -> void:
	for child in _units_vbox.get_children():
		child.queue_free()
	for unit_id in GameConfig.get_unit_ids():
		_units_vbox.add_child(_make_unit_row(unit_id))

func _make_unit_row(unit_id: String) -> PanelContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var unlocked := ArmyManager.is_unlocked(unit_id)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG if unlocked else UITheme.BTN_DISABLED
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_width_left = 5
	style.border_color = MILITARY if unlocked else UITheme.TEXT_DIM
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	# Left: name + stats
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var name_label := UITheme.make_label(Tr.t(def.get("name", unit_id)), "section", UITheme.TEXT if unlocked else UITheme.TEXT_DIM)
	title_row.add_child(name_label)
	var tier_label := UITheme.make_label(Tr.t("LBL_ARMY_TIER") % int(def.get("tier", 1)), "small", UITheme.TEXT_DIM)
	title_row.add_child(tier_label)
	var owned_label := UITheme.make_label(Tr.t("LBL_ARMY_OWNED") % ArmyManager.get_count(unit_id), "small", UITheme.POSITIVE)
	title_row.add_child(owned_label)
	info.add_child(title_row)

	var stats := "%s   |   %s   |   %s" % [
		_cost_text(def.get("cost", {})),
		Tr.t("LBL_ARMY_POWER_EACH") % int(def.get("power", 0)),
		Tr.t("LBL_ARMY_UPKEEP") % int(def.get("upkeep_gold", 0)),
	]
	info.add_child(UITheme.make_label(stats, "small", UITheme.TEXT_DIM))

	# Right: train button
	var check := ArmyManager.can_train(unit_id)
	var train_btn := Button.new()
	train_btn.text = Tr.t("BTN_TRAIN")
	train_btn.custom_minimum_size = Vector2(96, 40)
	UITheme.style_button(train_btn, MILITARY.darkened(0.15) if check["ok"] else UITheme.BTN, UITheme.FONT_BODY)
	train_btn.disabled = not check["ok"]
	if not check["ok"] and check["reason"] != "":
		train_btn.tooltip_text = Tr.t(check["reason"])
	train_btn.pressed.connect(func():
		if ArmyManager.train(unit_id):
			_refresh()
	)
	row.add_child(train_btn)

	return card

func _rebuild_training() -> void:
	for child in _training_vbox.get_children():
		child.queue_free()
	_training_bars.clear()
	var training := ArmyManager.get_training()
	if training.is_empty():
		var empty := UITheme.make_label(Tr.t("LBL_ARMY_EMPTY") if ArmyManager.get_total_units() == 0 else "—", "small", UITheme.TEXT_DIM)
		_training_vbox.add_child(empty)
		return
	for item in training:
		var def := GameConfig.get_unit_def(item["id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := UITheme.make_label(Tr.t(def.get("name", item["id"])), "small", UITheme.TEXT)
		name_label.custom_minimum_size.x = 130
		line.add_child(name_label)
		var bar := UITheme.make_progress_bar(MILITARY, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = _training_progress(item)
		line.add_child(bar)
		_training_vbox.add_child(line)
		_training_bars.append(bar)

func _update_training_progress() -> void:
	var training := ArmyManager.get_training()
	for i in range(mini(_training_bars.size(), training.size())):
		_training_bars[i].value = _training_progress(training[i])

func _training_progress(item: Dictionary) -> float:
	var dur: float = item.get("duration", 1.0)
	if dur <= 0.0:
		return 1.0
	return clampf(1.0 - (item.get("remaining", 0.0) / dur), 0.0, 1.0)

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res_name in cost:
		parts.append("%d %s" % [cost[res_name], Tr.res_name(res_name)])
	return " ".join(parts) if not parts.is_empty() else Tr.t("LBL_FREE")

# ── Visibility / open-close ──

func _on_era_advanced(_new_era: int) -> void:
	_refresh()
	_update_button_visibility()

func _on_base_changed(_arg = null) -> void:
	_update_button_visibility()
	if _is_open:
		_refresh()

func _update_button_visibility() -> void:
	# Army button appears in the sidebar once a Barracks exists.
	_army_btn.visible = _sidebar_visible and ArmyManager.barracks_count() > 0

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_update_button_visibility()

func _on_upkeep_unpaid(gold_short: int) -> void:
	EventBus.notification_posted.emit(Tr.t("NOTIF_UPKEEP_UNPAID") % gold_short, "danger", UITheme.DANGER)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
