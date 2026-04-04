extends Node
## Manages UI window stacking, focus, sequential closing with ESC,
## and slot-based conflict resolution via UILayoutConfig.

signal window_opened(window: CanvasLayer)
signal window_closed(window: CanvasLayer)

var _window_stack: Array[CanvasLayer] = []
var _base_layer: int = 11
var _top_layer: int = 100

# Panel registry: CanvasLayer -> panel_id (String)
var _panel_ids: Dictionary = {}

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if not _window_stack.is_empty():
			var top = _window_stack.back()
			if top.has_method("_toggle_panel"):
				top._toggle_panel()
			elif top.has_method("_close"):
				top._close()
			else:
				close_window(top)
			get_viewport().set_input_as_handled()

## Register a panel with its layout ID for conflict resolution.
func register_panel(window: CanvasLayer, panel_id: String) -> void:
	_panel_ids[window] = panel_id

## Opens a panel with automatic conflict resolution.
## Closes other panels sharing the same slot before opening.
func open_panel(window: CanvasLayer) -> void:
	var panel_id: String = _panel_ids.get(window, "")
	if not panel_id.is_empty():
		_close_conflicting(window, panel_id)
	open_window(window)

## Closes a panel (wrapper for close_window).
func close_panel(window: CanvasLayer) -> void:
	close_window(window)

## Called when a window is opened to put it on top of the stack.
func open_window(window: CanvasLayer) -> void:
	if not _window_stack.has(window):
		_window_stack.append(window)
	else:
		_window_stack.erase(window)
		_window_stack.append(window)
	_update_layers()
	window_opened.emit(window)

## Called when a window is closed to remove it from the stack.
func close_window(window: CanvasLayer) -> void:
	_window_stack.erase(window)
	_update_layers()
	window_closed.emit(window)

## Brings a window to the front (used when clicking on it).
func focus_window(window: CanvasLayer) -> void:
	if _window_stack.has(window):
		_window_stack.erase(window)
		_window_stack.append(window)
		_update_layers()

func _update_layers() -> void:
	for i in range(_window_stack.size()):
		_window_stack[i].layer = _base_layer + i + 1

func is_any_window_open() -> bool:
	return not _window_stack.is_empty()

## Close panels that share the same slot or a conflicting slot.
func _close_conflicting(opening: CanvasLayer, opening_id: String) -> void:
	var opening_slot: String = UILayoutConfig.PANEL_SLOTS.get(opening_id, "")
	if opening_slot.is_empty():
		return

	# Build set of slots that conflict with the opening panel
	var conflicting_slots: Array = [opening_slot]
	var extra: Array = UILayoutConfig.SLOT_CONFLICTS.get(opening_slot, [])
	for s in extra:
		conflicting_slots.append(s)

	# Collect panels to close (avoid mutating stack during iteration)
	var to_close: Array[CanvasLayer] = []
	for panel in _window_stack:
		if panel == opening:
			continue
		var other_id: String = _panel_ids.get(panel, "")
		if other_id.is_empty():
			continue
		var other_slot: String = UILayoutConfig.PANEL_SLOTS.get(other_id, "")
		if other_slot in conflicting_slots:
			to_close.append(panel)

	for panel in to_close:
		if panel.has_method("_toggle_panel"):
			panel._toggle_panel()
		elif panel.has_method("_close"):
			panel._close()
		else:
			close_window(panel)
