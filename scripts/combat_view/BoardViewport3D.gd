extends SubViewportContainer
## La ventana al tablero 3D dentro de BattleScreen: un SubViewport con su propio
## mundo (la luz y el cielo de la base no entran) donde vive Board3D, y la
## traduccion de toques y clics a casillas.
##
## Un toque (o clic) que no arrastra es una casilla: `cell_pressed`. La rueda y el
## pellizco acercan un poco (Board3D.ZOOM_MIN..MAX). Con raton, la casilla bajo
## el puntero se marca y el tooltip dice quien hay (`tooltip_provider`). Nada
## de esto decide: BattleScreen recibe la casilla y llama a CombatManager igual
## que con el tablero 2D.

signal cell_pressed(cell: Vector2i)

const BOARD_SCENE := preload("res://scenes/combat/Board3D.tscn")
const TAP_SLOP := 14.0

var board = null                  ## Board3D
var viewport: SubViewport
## Callable(cell: Vector2i) -> String: el texto del tooltip de una casilla.
var tooltip_provider: Callable

var _press_pos := Vector2.ZERO
var _pressed := false
var _hover_enabled := true

func _init() -> void:
	name = "Board3DView"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.name = "BoardViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(viewport)
	board = BOARD_SCENE.instantiate()
	viewport.add_child(board)

## Calidad del tablero: `settings` de WorldLook.settings_for() mas "high".
func apply_quality(settings: Dictionary) -> void:
	viewport.scaling_3d_scale = float(settings.get("scale_3d", 1.0))
	viewport.msaa_3d = Viewport.MSAA_2X if bool(settings.get("high", false)) else Viewport.MSAA_DISABLED
	viewport.positional_shadow_atlas_size = 0
	board.apply_quality(settings)

## Con el dedo no hay puntero que seguir: la marca de "bajo el raton" se apaga.
func set_touch_mode(touch: bool) -> void:
	_hover_enabled = not touch
	if touch and board != null:
		board.set_hover(Vector2i(-1, -1))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_press_pos = mb.position
				# Con el dedo, en el frente, la pieza que se pisa es el foco mientras
				# se mantiene: su etiqueta de objetivo (dano previsto, buen/mal
				# objetivo) se lee antes de soltar. En el tablero no cambia nada.
				if not _hover_enabled and board.is_front():
					board.set_hover(board.pick_cell(_to_viewport(mb.position)))
			elif _pressed:
				_pressed = false
				if mb.position.distance_to(_press_pos) <= TAP_SLOP:
					var cell: Vector2i = board.pick_cell(_to_viewport(mb.position))
					if cell.x >= 0:
						cell_pressed.emit(cell)
				if not _hover_enabled:
					board.set_hover(Vector2i(-1, -1))
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			board.zoom_by(0.95)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			board.zoom_by(1.05)
			accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0:
			board.zoom_by(1.0 / mg.factor)
		accept_event()
	elif event is InputEventMouseMotion and _hover_enabled:
		var mm := event as InputEventMouseMotion
		if mm.device != InputEvent.DEVICE_ID_EMULATION:
			board.set_hover(board.pick_cell(_to_viewport(mm.position)))

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and board != null:
		board.set_hover(Vector2i(-1, -1))

## El SubViewport mide lo que el contenedor (stretch, sin encoger): las
## coordenadas locales del contenedor ya son las suyas.
func _to_viewport(p: Vector2) -> Vector2:
	var shrink := float(maxi(1, stretch_shrink))
	return p / shrink

## Coordenadas del contenedor de un punto del SubViewport (pruebas y sondas).
func to_local_point(p: Vector2) -> Vector2:
	return p * float(maxi(1, stretch_shrink))

func _get_tooltip(at_position: Vector2) -> String:
	if not tooltip_provider.is_valid() or board == null:
		return ""
	var cell: Vector2i = board.pick_cell(_to_viewport(at_position))
	if cell.x < 0:
		return ""
	return String(tooltip_provider.call(cell))
