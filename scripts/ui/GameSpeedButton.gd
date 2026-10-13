extends CanvasLayer
## El boton de velocidad del juego, x1 / x2 (docs/21 §13). Pequeno, arriba en el
## centro, donde va el indicador de la Tormenta: en calma ocupa ese sitio y con
## la Tormenta a la vista se apila debajo (slot "speed_button"). Registrado en
## HudRegistry: se oculta en Ajustes > Interfaz y se mueve en Editar disposicion.
##
## En PC tambien con la tecla F. La velocidad vive en GameConfig.game_speed (no
## en la partida ni en settings.cfg: al abrir el juego es x1) y este boton solo
## la lee y la cambia; la simulacion la aplica con GameConfig.sim_delta().
##
## No esta en ninguna escena: lo crea PauseMenu al arrancar, como hermano suyo
## (las dos vistas tienen PauseMenu). Con el juego en pausa no responde.

const LAYER := 10
const BTN_W := 64.0
const SHORTCUT := KEY_F

var _dock: Control
var _button: Button

func _ready() -> void:
	layer = LAYER
	name = "GameSpeedButton"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_ui()
	EventBus.game_speed_changed.connect(func(_s): _refresh())
	_refresh()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dock = Control.new()
	_dock.name = "SpeedDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.custom_minimum_size = Vector2(UITheme.touch_px(BTN_W), UITheme.MIN_BTN_H)
	UILayoutManager.apply_layout("GameSpeedButton", _dock)
	root.add_child(_dock)

	_button = Button.new()
	_button.name = "SpeedButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.pressed.connect(GameConfig.toggle_game_speed)
	_dock.add_child(_button)

	HudRegistry.register("GameSpeedButton", _dock)

func _refresh() -> void:
	var fast := GameConfig.game_speed > 1.0
	_button.text = "x%d" % int(GameConfig.game_speed)
	_button.tooltip_text = Tr.ti("LBL_GAME_SPEED_TIP")
	UITheme.style_button(_button, UITheme.ACCENT.darkened(0.35) if fast else UITheme.BTN, UITheme.FONT_SECTION)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != SHORTCUT or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	GameConfig.toggle_game_speed()
	get_viewport().set_input_as_handled()

## Para pruebas y capturas.
func button() -> Button:
	return _button
