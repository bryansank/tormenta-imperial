extends Node
## Manages UI window stacking, focus, and sequential closing with ESC.

signal window_opened(window: CanvasLayer)
signal window_closed(window: CanvasLayer)

var _window_stack: Array[CanvasLayer] = []
var _base_layer: int = 11
var _top_layer: int = 100

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if not _window_stack.is_empty():
			var top = _window_stack.back()
			if top.has_method("_toggle_panel"):
				top._toggle_panel()
			else:
				# Fallback if no toggle method
				close_window(top)
			get_viewport().set_input_as_handled()

## Registers a window and handles focus when it opens.
func register_window(window: CanvasLayer, is_open: bool) -> void:
	if is_open:
		open_window(window)

## Called when a window is opened to put it on top of the stack.
func open_window(window: CanvasLayer) -> void:
	if not _window_stack.has(window):
		_window_stack.append(window)
	else:
		# Move to top of stack
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
