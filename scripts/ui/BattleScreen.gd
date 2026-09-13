extends CanvasLayer
## The board. Full-screen overlay that opens when an encounter starts and closes
## when it resolves.
##
## It owns no combat state: it reads CombatManager and redraws on every combat
## signal (constitution, principle IV). Every click is routed back through the
## manager's public API, so an illegal action is impossible to express here —
## the rules reject it, the screen never has to know why.

const Rules := preload("res://scripts/combat/CombatRules.gd")

const PLAYER := 0
const ENEMY := 1

## Highlight roles, kept apart from the unit colours so the board stays readable
## for players who cannot rely on hue alone.
const COL_EMPTY := Color(0.11, 0.12, 0.10)
const COL_MOVE := Color(0.20, 0.33, 0.45)
const COL_TARGET := Color(0.48, 0.18, 0.14)

var _root: Control
var _backdrop: ColorRect
var _grid: GridContainer
var _cells: Array = []              ## Button, row-major, index = y * width + x
var _cell_bars: Array = []          ## ProgressBar aligned with _cells

var _title_label: Label
var _round_label: Label
var _turn_label: Label
var _order_box: HBoxContainer
var _defend_btn: Button
var _wait_btn: Button
var _end_btn: Button
var _result_panel: PanelContainer
var _result_title: Label
var _result_detail: Label

var _board: Vector2i = Vector2i(8, 8)
var _cell_size: int = 52
var _is_open := false

func _ready() -> void:
	# Above every base panel, including the tutorial callouts (14) and the modal
	# slots (15): the board is a mode, not a window, and nothing from the base
	# may draw on top of it. Only the victory overlay (20) outranks it.
	#
	# Deliberately kept out of UIManager's window stack: that stack reassigns
	# `layer` as `_base_layer + position`, which would drop the board back under
	# the panels it must cover. It also makes ESC close the top window, and a
	# fight is not something you should be able to dismiss with a keypress.
	# The full-screen backdrop below is what makes it modal instead.
	layer = 18
	_setup_ui()
	visible = false

	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_defended.connect(func(_uid): _refresh())
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	get_viewport().size_changed.connect(_on_viewport_resized)

# ── Construction ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	UILayoutManager.apply_layout("BattleScreen", _root)
	add_child(_root)

	# Opaque enough to take the base out of play: this is a different mode, and
	# it should feel like one.
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.04, 0.03, 0.93)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	# Header: which fight, and how much time is left in it.
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 24)
	_title_label = UITheme.make_label("", "title", UITheme.ACCENT)
	header.add_child(_title_label)
	_round_label = UITheme.make_label("", "section", UITheme.TEXT_DIM)
	header.add_child(_round_label)
	column.add_child(header)

	_turn_label = UITheme.make_label("", "section", UITheme.TEXT)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_label)

	# Initiative strip: the whole round, in the order it will happen (FR-006).
	_order_box = HBoxContainer.new()
	_order_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_box.add_theme_constant_override("separation", 4)
	column.add_child(_order_box)

	var grid_center := HBoxContainer.new()
	grid_center.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(grid_center)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	grid_center.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	_defend_btn = _make_action(Tr.t("BTN_DEFEND"), func(): _act_defend())
	_wait_btn = _make_action(Tr.t("BTN_WAIT"), func(): _act_wait())
	_end_btn = _make_action(Tr.t("BTN_END_TURN"), func(): _act_end_turn())
	actions.add_child(_defend_btn)
	actions.add_child(_wait_btn)
	actions.add_child(_end_btn)
	column.add_child(actions)

	_build_result_panel()

func _make_action(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(132, UITheme.MIN_BTN_H + 4)
	UITheme.style_button(btn, UITheme.BTN, UITheme.FONT_BUTTON)
	btn.pressed.connect(callback)
	return btn

func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.custom_minimum_size = Vector2(340, 0)
	_result_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_result_panel.visible = false
	_root.add_child(_result_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_result_panel.add_child(vbox)

	_result_title = UITheme.make_label("", "title", UITheme.ACCENT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_result_title)

	_result_detail = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_detail)

	var close := Button.new()
	close.text = Tr.t("BTN_CLOSE")
	close.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(close, UITheme.BTN, UITheme.FONT_BUTTON)
	close.pressed.connect(_close_board)
	vbox.add_child(close)

# ── Board construction ───────────────────────────────────────────────

## Cells are rebuilt only when the board size or the viewport changes; a normal
## refresh just restyles them.
func _build_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cells.clear()
	_cell_bars.clear()

	_grid.columns = _board.x
	for y in range(_board.y):
		for x in range(_board.x):
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(_cell_size, _cell_size)
			cell.focus_mode = Control.FOCUS_NONE
			cell.clip_text = true
			cell.add_theme_font_size_override("font_size", maxi(12, _cell_size / 3))
			var heavy := UITheme.heavy_font()
			if heavy:
				cell.add_theme_font_override("font", heavy)
			var coords := Vector2i(x, y)
			cell.pressed.connect(func(): _on_cell_pressed(coords))
			_grid.add_child(cell)
			_cells.append(cell)

			# Health reads as a bar under the letter — the one number a player
			# checks constantly should never need a tooltip.
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_left = 4
			bar.offset_right = -4
			bar.offset_top = -8
			bar.offset_bottom = -3
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(bar)
			_cell_bars.append(bar)

## Keeps the board inside the window on a phone without letting cells drop below
## a touchable size (quickstart E9).
func _recalculate_cell_size() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var by_width: float = (vp.x * 0.92) / float(_board.x)
	var by_height: float = (vp.y * 0.58) / float(_board.y)
	_cell_size = int(clampf(minf(by_width, by_height), 34.0, 62.0))

func _on_viewport_resized() -> void:
	if not _is_open:
		return
	var previous := _cell_size
	_recalculate_cell_size()
	if previous != _cell_size:
		_build_grid()
	_refresh()

# ── Signal handlers ──────────────────────────────────────────────────

func _on_encounter_started(index: int, is_boss: bool) -> void:
	_board = CombatManager.get_board_size()
	_recalculate_cell_size()
	_build_grid()
	_title_label.text = Tr.t("LBL_ENCOUNTER_N") % (index + 1)
	if is_boss:
		_title_label.text += "  " + Tr.t("LBL_BOSS")
	_result_panel.visible = false
	_open_board()
	_refresh()

func _on_turn_started(_side: int, _uid: int) -> void:
	_refresh()

func _on_unit_moved(_uid: int, _from: Vector2i, _to: Vector2i) -> void:
	_refresh()

func _on_unit_attacked(_attacker_uid: int, target_uid: int, damage: int) -> void:
	var target := CombatManager.get_unit(target_uid)
	if target != null:
		_spawn_damage_number(target.position, damage)
	_refresh()

func _on_unit_died(_uid: int, _side: int) -> void:
	_refresh()

func _on_encounter_ended(victory: bool, turns_used: int) -> void:
	_refresh()
	_result_title.text = Tr.t("LBL_VICTORY") if victory else Tr.t("LBL_DEFEAT")
	_result_title.add_theme_color_override("font_color", UITheme.POSITIVE if victory else UITheme.DANGER)
	_result_detail.text = _result_text(turns_used)
	_result_panel.visible = true
	_set_actions_enabled(false)

## What the fight actually cost and paid. The dead are named, because a list of
## units that are not coming back is the part the player has to feel.
func _result_text(turns_used: int) -> String:
	var lines: Array = [Tr.t("LBL_ROUND") % [turns_used, CombatManager.get_turn_limit()]]
	var result: Dictionary = CombatManager.get_last_result()
	if result.is_empty():
		return "\n".join(lines)

	var rewards: Dictionary = result.get("rewards", {})
	if not rewards.is_empty():
		lines.append("%s: %s" % [Tr.t("LBL_REWARDS"), _resource_list(rewards)])

	var casualties: Dictionary = result.get("casualties", {})
	if casualties.is_empty():
		lines.append(Tr.t("LBL_NO_CASUALTIES"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), _unit_list(casualties)])

	var morale_delta: int = int(result.get("morale_delta", 0))
	if morale_delta != 0:
		lines.append(Tr.t("LBL_MORALE_DELTA") % morale_delta)
	return "\n".join(lines)

func _resource_list(amounts: Dictionary) -> String:
	var parts: Array = []
	for res_name in amounts:
		parts.append("%d %s" % [int(amounts[res_name]), Tr.res_name(res_name)])
	return "   ".join(parts)

func _unit_list(counts: Dictionary) -> String:
	var parts: Array = []
	for unit_id in counts:
		var def := GameConfig.get_unit_def(unit_id)
		parts.append("%d %s" % [int(counts[unit_id]), Tr.t(def.get("name", unit_id))])
	return "   ".join(parts)

# ── Refresh ──────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _is_open or _cells.is_empty():
		return
	_refresh_header()
	_refresh_cells()
	_refresh_order()
	_refresh_actions()

func _refresh_header() -> void:
	_round_label.text = Tr.t("LBL_ROUND") % [CombatManager.get_round(), CombatManager.get_turn_limit()]
	var active := CombatManager.get_active_unit()
	if active == null:
		_turn_label.text = ""
		return
	var is_player: bool = active.side == PLAYER
	_turn_label.text = Tr.t("LBL_TURN_PLAYER") if is_player else Tr.t("LBL_TURN_ENEMY")
	_turn_label.add_theme_color_override("font_color", UITheme.POSITIVE if is_player else UITheme.DANGER)

func _refresh_cells() -> void:
	var active := CombatManager.get_active_unit()
	var moves: Array = []
	var targets: Array = []
	if active != null and CombatManager.is_player_turn():
		moves = CombatManager.get_valid_moves(active.uid)
		targets = CombatManager.get_valid_targets(active.uid)

	for y in range(_board.y):
		for x in range(_board.x):
			var index: int = y * _board.x + x
			var cell: Button = _cells[index]
			var bar: ProgressBar = _cell_bars[index]
			var coords := Vector2i(x, y)
			var unit := CombatManager.get_unit_at(coords)
			_style_cell(cell, bar, coords, unit, active, moves, targets)

func _style_cell(cell: Button, bar: ProgressBar, coords: Vector2i, unit: CombatUnit,
		active: CombatUnit, moves: Array, targets: Array) -> void:
	var background: Color = COL_EMPTY
	var border: Color = UITheme.ACCENT_DIM
	var border_width: int = 1

	if unit == null:
		cell.text = ""
		bar.visible = false
		if moves.has(coords):
			background = COL_MOVE
			border = UITheme.INFO
	else:
		cell.text = _unit_glyph(unit)
		bar.visible = true
		bar.value = float(unit.hp) / float(maxi(1, unit.max_hp))
		_style_health_bar(bar, unit)
		background = UITheme.POSITIVE.darkened(0.45) if unit.side == PLAYER else UITheme.DANGER.darkened(0.35)
		border = UITheme.POSITIVE if unit.side == PLAYER else UITheme.DANGER
		if targets.has(unit.uid):
			background = COL_TARGET
			border = UITheme.WARNING
			border_width = 3
		if unit.defending:
			border = UITheme.INFO
			border_width = 3
		if active != null and unit.uid == active.uid:
			border = UITheme.ACCENT
			border_width = 4

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(UITheme.CORNER)
	style.border_color = border
	style.set_border_width_all(border_width)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		cell.add_theme_stylebox_override(state, style)
	cell.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	cell.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)

func _style_health_bar(bar: ProgressBar, unit: CombatUnit) -> void:
	var ratio: float = float(unit.hp) / float(maxi(1, unit.max_hp))
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.POSITIVE if ratio > 0.5 else (UITheme.WARNING if ratio > 0.25 else UITheme.DANGER)
	fill.set_corner_radius_all(1)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.04, 0.9)
	bg.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)

## One letter per unit type, taken from the translated name so it still reads in
## English. Real icons are an art task, deliberately left for later.
func _unit_glyph(unit: CombatUnit) -> String:
	var def := GameConfig.get_unit_def(unit.unit_id)
	var label: String = Tr.t(def.get("name", unit.unit_id))
	return label.substr(0, 1).to_upper() if label != "" else "?"

## The initiative strip: who acts, in order, with the current unit lit up.
func _refresh_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	var active := CombatManager.get_active_unit()
	for uid in CombatManager.get_turn_order():
		var unit := CombatManager.get_unit(uid)
		if unit == null or not unit.is_alive():
			continue
		var chip := Label.new()
		chip.text = _unit_glyph(unit)
		chip.custom_minimum_size = Vector2(26, 26)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		var is_active: bool = active != null and uid == active.uid
		var tint: Color = UITheme.POSITIVE if unit.side == PLAYER else UITheme.DANGER
		chip.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT if is_active else UITheme.TEXT_DIM)
		var style := StyleBoxFlat.new()
		style.bg_color = tint.darkened(0.2 if is_active else 0.6)
		style.set_corner_radius_all(UITheme.CORNER)
		style.border_color = UITheme.ACCENT if is_active else UITheme.ACCENT_DIM
		style.set_border_width_all(2 if is_active else 1)
		chip.add_theme_stylebox_override("normal", style)
		# A unit that already acted is dimmed, so the strip shows what is left.
		chip.modulate.a = 1.0 if not unit.has_acted else 0.45
		_order_box.add_child(chip)

func _refresh_actions() -> void:
	_set_actions_enabled(CombatManager.is_player_turn())

func _set_actions_enabled(enabled: bool) -> void:
	_defend_btn.disabled = not enabled
	_wait_btn.disabled = not enabled
	_end_btn.disabled = not enabled

# ── Input ────────────────────────────────────────────────────────────

## One click, one meaning: an enemy in range is an attack, a lit cell is a move,
## anything else is nothing. No mode switching, no right-click.
func _on_cell_pressed(coords: Vector2i) -> void:
	if not CombatManager.is_player_turn():
		return
	var active := CombatManager.get_active_unit()
	if active == null or active.side != PLAYER:
		return

	var occupant := CombatManager.get_unit_at(coords)
	if occupant != null and occupant.side == ENEMY:
		if CombatManager.get_valid_targets(active.uid).has(occupant.uid):
			CombatManager.attack(active.uid, occupant.uid)
		return
	if occupant == null and CombatManager.get_valid_moves(active.uid).has(coords):
		CombatManager.move_unit(active.uid, coords)

func _act_defend() -> void:
	var active := CombatManager.get_active_unit()
	if active != null:
		CombatManager.defend(active.uid)

func _act_wait() -> void:
	var active := CombatManager.get_active_unit()
	if active != null:
		CombatManager.wait_unit(active.uid)

func _act_end_turn() -> void:
	CombatManager.end_turn()

# ── Damage numbers ───────────────────────────────────────────────────

## A number that rises off the target and fades. Without it a hit is just two
## bars changing and the player never feels the exchange.
func _spawn_damage_number(cell: Vector2i, amount: int) -> void:
	var index: int = cell.y * _board.x + cell.x
	if cell.x < 0 or index < 0 or index >= _cells.size():
		return
	var anchor: Button = _cells[index]
	var label := UITheme.make_label("-%d" % amount, "title", UITheme.DANGER.lightened(0.35))
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	label.global_position = anchor.global_position + Vector2(float(_cell_size) * 0.25, 0.0)

	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y - 42.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tween.tween_callback(label.queue_free)

# ── Open / close ─────────────────────────────────────────────────────

func _open_board() -> void:
	_is_open = true
	visible = true

func _close_board() -> void:
	_is_open = false
	visible = false
	_result_panel.visible = false
	CombatManager.end_encounter()
