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

## Olvida la pila y el registro. Lo llama GameManager antes de recargar la
## escena: los paneles viejos mueren con ella y los nuevos se registran en su
## _ready. Este autoload sobrevive a la recarga, asi que sin esto seguiria
## guardando CanvasLayer liberados y el primer _update_layers reventaria.
func reset() -> void:
	_window_stack.clear()
	_panel_ids.clear()

## Quita de la pila y del registro lo que ya no existe. Es la red de seguridad
## de reset(): cualquier camino que libere un panel sin avisar (una recarga que
## no pase por GameManager, un test) deja de poder romper la pila.
func _prune() -> void:
	# Sin `for` sobre un Array[CanvasLayer]: iterar un array tipado con un objeto
	# liberado dentro ya es un error. Se mira cada hueco como Variant.
	var i := _window_stack.size() - 1
	while i >= 0:
		var entry: Variant = _window_stack[i]
		if not is_instance_valid(entry):
			_window_stack.remove_at(i)
		i -= 1
	for key in _panel_ids.keys():
		if not is_instance_valid(key):
			_panel_ids.erase(key)

const DragScroll := preload("res://scripts/ui/DragScroll.gd")

func _ready() -> void:
	# Toda lista desplazable se arrastra con el dedo o el raton empiece donde
	# empiece el gesto (DragScroll). Se engancha sola a cada ScrollContainer que
	# entra al arbol, de cualquier panel, sin que cada panel tenga que acordarse.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		DragScroll.attach.call_deferred(node)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_prune()
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
	_prune()
	_panel_ids[window] = panel_id

## Opens a panel with automatic conflict resolution.
## Closes other panels sharing the same slot before opening.
func open_panel(window: CanvasLayer) -> void:
	_prune()
	var panel_id: String = _panel_ids.get(window, "")
	if not panel_id.is_empty():
		_close_conflicting(window, panel_id)
	open_window(window)

## Closes a panel (wrapper for close_window).
func close_panel(window: CanvasLayer) -> void:
	close_window(window)

## Called when a window is opened to put it on top of the stack.
func open_window(window: CanvasLayer) -> void:
	_prune()
	if not _window_stack.has(window):
		_window_stack.append(window)
	else:
		_window_stack.erase(window)
		_window_stack.append(window)
	_update_layers()
	window_opened.emit(window)

## Called when a window is closed to remove it from the stack.
func close_window(window: CanvasLayer) -> void:
	_prune()
	_window_stack.erase(window)
	_update_layers()
	window_closed.emit(window)

## Brings a window to the front (used when clicking on it).
func focus_window(window: CanvasLayer) -> void:
	_prune()
	if _window_stack.has(window):
		_window_stack.erase(window)
		_window_stack.append(window)
		_update_layers()

func _update_layers() -> void:
	_prune()
	for i in range(_window_stack.size()):
		_window_stack[i].layer = _base_layer + i + 1

## Cierra todas las ventanas de la pila, de arriba abajo, por el mismo camino
## que ESC (cada panel se cierra a si mismo). Lo usa el menu de la partida:
## su boton nunca puede quedarse sin hacer nada porque haya algo abierto.
func close_all_windows() -> void:
	_prune()
	# Tope por si un panel no se quita de la pila al cerrarse.
	var guard := _window_stack.size() + 4
	while not _window_stack.is_empty() and guard > 0:
		guard -= 1
		var top: CanvasLayer = _window_stack.back()
		if top.has_method("_toggle_panel"):
			top._toggle_panel()
		elif top.has_method("_close"):
			top._close()
		if _window_stack.has(top):
			close_window(top)
		_prune()

func is_any_window_open() -> bool:
	_prune()
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
