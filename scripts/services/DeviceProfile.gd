extends Node
## Perfil de dispositivo: PC, tablet o movil. Decide los valores por defecto de
## la interfaz (escala, texto, lado tactil, controles en pantalla, variante de
## disposicion, textos de ayuda de raton o de dedo) y los aplica.
##
## Deteccion (detect_from, pura):
##   - Sin feature de movil (android, ios, mobile, web_android, web_ios): PC.
##     Un portatil Windows con pantalla tactil sigue siendo PC.
##   - Con feature de movil: lado corto de la pantalla en dp (px / (dpi / 160));
##     >= 600 dp es tablet (la regla de Android), por debajo es movil.
## El jugador puede forzarlo en Ajustes (GameConfig.ui_device_profile).
##
## Aplicar (apply_all):
##   - UITheme.configure(): paleta, alto contraste, opacidad, tamano de texto y
##     lado tactil minimo. Se reconstruye el tema global de la raiz.
##   - content_scale_factor de la ventana: la escala de interfaz. Con
##     stretch canvas_items + aspect expand el lienzo logico es 1280x720 como
##     minimo en apaisado; la escala lo encoge (UI mas grande) o lo agranda.
##     En vertical el lienzo se lleva a PORTRAIT_WIDTH de ancho para que el
##     movil use la disposicion estrecha (UILayoutConfig.NARROW_SLOTS).
##   - Engine.max_fps: el tope de fotogramas (fps_for, puro). El del perfil o el
##     elegido en Ajustes; menos con el juego en pausa y aun menos sin foco.
##     En PC con calidad Minima, el "auto" es GameConfig.fps_minimal_pc.
##
## Calidad grafica (docs/26 §7): aplica lo que no es del mundo 3D
## (GraphicsQuality.apply_runtime) al arrancar y con cada cambio, y hace la
## deteccion del primer arranque: solo con la calidad en "auto" y sin
## quality_detected en settings.cfg. Paso 1, senales estaticas; paso 2, una
## medida corta detras del menu de titulo; paso 3, un aviso de una linea al
## cerrar el menu, una sola vez.
## Los paneles se construyen una vez: lo que cambia tokens de UITheme (texto,
## paleta, contraste, opacidad) se ve tras rebuild_ui(), que recarga la escena
## conservando la partida. La escala se aplica al momento.
##
## Todo vive en user://settings.cfg [interfaz] (es del dispositivo, no de la
## partida). Ver docs/21-interfaz-y-dispositivos.md.

const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")

signal profile_changed(profile: String)
signal scale_applied(factor: float)

const PC := "pc"
const TABLET := "tablet"
const PHONE := "phone"
const PROFILES := [PC, TABLET, PHONE]

const MOBILE_FEATURES := ["android", "ios", "mobile", "web_android", "web_ios"]
## Lado corto minimo, en dp, para que un dispositivo movil cuente como tablet.
const TABLET_MIN_DP := 600.0
## Tamano base del lienzo (project.godot, window/size/viewport_*).
const BASE_SIZE := Vector2(1280, 720)
## Ancho logico del lienzo en vertical: por debajo de UILayoutConfig.NARROW_WIDTH,
## asi el movil en vertical usa la columna unica.
const PORTRAIT_WIDTH := 480.0
## Alto logico minimo en apaisado: por mucha escala que se pida, el lienzo no
## baja de aqui. 540 es lo que ocupa la columna del menu ☰ desplegada (diez
## botones de 44 + huecos) con aire; por debajo AYUDA se salia por abajo. A
## 1280x720 limita la escala a 133 %; en una tablet de 2560x1600, a 296 %.
const MIN_LOGICAL_HEIGHT := 540.0
## Ancho logico minimo en vertical (movil): lo justo para la columna izquierda.
const MIN_LOGICAL_WIDTH_PORTRAIT := 400.0

## Valores de cada perfil. `touch_controls` es lo que resuelve el "auto" de
## Controles en pantalla; `input` elige los textos de ayuda (Tr.ti); `fps` es el
## tope de fotogramas en "auto": un juego de gestion no gana nada por encima de 60,
## y en tablet y movil 30 estables gastan la mitad de bateria y no se calientan
## (las baratas bajan el reloj con el calor y entonces tironean). Docs/26 §7.4.
const DEFAULTS := {
	PC: {"ui_scale": 1.0, "text_size": "normal", "touch_target": 44,
		"touch_controls": false, "layout": "standard", "input": "mouse", "fps": 60},
	TABLET: {"ui_scale": 1.15, "text_size": "normal", "touch_target": 48,
		"touch_controls": true, "layout": "standard", "input": "touch", "fps": 30},
	PHONE: {"ui_scale": 1.3, "text_size": "large", "touch_target": 52,
		"touch_controls": true, "layout": "compact", "input": "touch", "fps": 30},
}

var _detected := PC
var _factor := 1.0
## Lo que decide el tope de fotogramas ademas de la preferencia.
var _focused := true
var _paused := false
## Pestana de Ajustes que hay que reabrir tras una reconstruccion (-1: ninguna).
## Estatica: sobrevive a la recarga de escena, que es justo cuando hace falta.
static var reopen_settings_tab := -1

## Deteccion de la calidad: estado de la medida del paso 2.
enum Detect { OFF, WAIT_GAME, WARMUP, MEASURE }
var _detect := Detect.OFF
var _detect_timer := 0.0
var _detect_frames: Array = []
var _detect_quality := ""
## Aviso pendiente hasta que se cierre el menu de titulo ("" = ninguno).
var _pending_notice := ""

func _ready() -> void:
	_detected = detect_from(_os_features(), _screen_px(), _screen_dpi())
	print("[DeviceProfile] detectado=%s, activo=%s" % [_detected, current()])
	get_tree().root.size_changed.connect(_on_window_resized)
	# Sigue corriendo en pausa: es justo cuando tiene que bajar los fotogramas.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.graphics_quality_changed.connect(_on_graphics_quality_changed)
	GraphicsQuality.apply_runtime(get_tree())
	# El override del renderizador sigue a la calidad guardada (por si alguien
	# borro o edito settings.cfg a mano).
	GraphicsQuality.sync_renderer_override()
	apply_all()
	print("[DeviceProfile] calidad=%s (%s), renderizador=%s" % [GraphicsQuality.current(),
		GameConfig.ui_graphics_quality, RenderingServer.get_current_rendering_method()])
	start_quality_detection(false)

# ── Deteccion (pura) ──────────────────────────────────────────────────

static func detect_from(features: Array, screen_px: Vector2i, dpi: int) -> String:
	var mobile := false
	for f in MOBILE_FEATURES:
		if f in features:
			mobile = true
			break
	if not mobile:
		return PC
	return TABLET if shortest_side_dp(screen_px, dpi) >= TABLET_MIN_DP else PHONE

## Lado corto de la pantalla en dp (160 dpi = 1 dp por px). Sin dpi conocido se
## asume 160: una pantalla de la que no se sabe nada se mide en pixeles.
static func shortest_side_dp(screen_px: Vector2i, dpi: int) -> float:
	var short_px := float(mini(screen_px.x, screen_px.y))
	var d := float(dpi) if dpi > 0 else 160.0
	return short_px / (d / 160.0)

func _os_features() -> Array:
	var out: Array = []
	for f in MOBILE_FEATURES:
		if OS.has_feature(f):
			out.append(f)
	return out

func _screen_px() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1280, 720)
	return DisplayServer.screen_get_size()

func _screen_dpi() -> int:
	if DisplayServer.get_name() == "headless":
		return 96
	return DisplayServer.screen_get_dpi()

# ── Perfil activo ─────────────────────────────────────────────────────

func detected() -> String:
	return _detected

## El perfil que manda: el forzado en Ajustes o, en "auto", el detectado.
func current() -> String:
	var forced := GameConfig.ui_device_profile
	return forced if forced in PROFILES else _detected

func defaults() -> Dictionary:
	return DEFAULTS.get(current(), DEFAULTS[PC])

## Tablet y movil: controles en pantalla en "auto" y lado tactil mayor.
func is_touch_profile() -> bool:
	return bool(defaults()["touch_controls"])

## "touch" o "mouse": que textos de ayuda tocan. Un PC que ya recibio un toque
## real (o con los controles tactiles forzados) habla de dedos.
func input_style() -> String:
	if defaults()["input"] == "touch" or GameConfig.touch_controls_enabled() 			or GameConfig.real_touch_seen():
		return "touch"
	return "mouse"

func layout_variant() -> String:
	return String(defaults()["layout"])

func set_profile_override(mode: String) -> void:
	if not mode in GameConfig.DEVICE_PROFILE_MODES:
		mode = "auto"
	if GameConfig.ui_device_profile == mode:
		return
	GameConfig.ui_device_profile = mode
	GameConfig.save_user_settings()
	apply_scale()
	apply_fps()
	profile_changed.emit(current())
	EventBus.touch_controls_changed.emit(GameConfig.touch_controls_enabled())

# ── Escala y texto ────────────────────────────────────────────────────

## Escala de interfaz que vale ahora (1.0 = 100 %).
func effective_ui_scale() -> float:
	if GameConfig.ui_scale_pct > 0:
		return float(GameConfig.ui_scale_pct) / 100.0
	return float(defaults()["ui_scale"])

func effective_text_size() -> String:
	if GameConfig.ui_text_size in UITheme.TEXT_SIZES:
		return GameConfig.ui_text_size
	return String(defaults()["text_size"])

## content_scale_factor para una ventana y una escala de interfaz. Puro.
## Apaisado: el lienzo sale de stretch (lado corto 720) y la escala lo divide.
## Vertical: el ancho logico se lleva a PORTRAIT_WIDTH. Nunca por debajo de
## MIN_LOGICAL_HEIGHT de alto (apaisado) ni de MIN_LOGICAL_WIDTH_PORTRAIT de
## ancho (vertical).
static func content_scale_for(window: Vector2, ui_scale: float) -> float:
	if window.x <= 0.0 or window.y <= 0.0:
		return ui_scale
	var s0 := minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)
	var desired := s0
	var max_factor: float
	if window.y > window.x:
		desired = window.x / PORTRAIT_WIDTH
		max_factor = window.x / (MIN_LOGICAL_WIDTH_PORTRAIT * s0)
	else:
		max_factor = window.y / (MIN_LOGICAL_HEIGHT * s0)
	var factor := desired / s0 * ui_scale
	return clampf(factor, 0.25, maxf(max_factor, 0.25))

## Tamano del lienzo logico que resulta (para tests y capturas). Puro.
static func logical_size_for(window: Vector2, factor: float) -> Vector2:
	var s0 := minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)
	return window / (s0 * factor)

## Cubo de proporcion para guardar la disposicion: una posicion movida en 16:9
## no vale en 4:3. Puro.
static func aspect_bucket(size: Vector2) -> String:
	if size.x <= 0.0 or size.y <= 0.0:
		return "16:9"
	var r := size.x / size.y
	if r < 1.0:
		return "portrait"
	if r < 1.45:
		return "4:3"
	if r < 1.7:
		return "16:10"
	if r < 2.05:
		return "16:9"
	return "21:9"

## Clave de GameConfig.ui_layout: perfil y proporcion de la ventana.
func layout_key() -> String:
	return "%s|%s" % [current(), aspect_bucket(_window_size())]

func _window_size() -> Vector2:
	if DisplayServer.get_name() == "headless":
		return Vector2(get_tree().root.get_visible_rect().size)
	return Vector2(DisplayServer.window_get_size())

# ── Aplicar ───────────────────────────────────────────────────────────

func apply_all() -> void:
	apply_theme()
	apply_scale()
	apply_fps()

## Tokens de UITheme y tema global de la raiz. Los paneles ya construidos no
## cambian: para eso rebuild_ui().
func apply_theme() -> void:
	UITheme.configure(GameConfig.ui_palette, GameConfig.ui_high_contrast,
		GameConfig.ui_panel_opacity, effective_text_size(), int(defaults()["touch_target"]))
	get_tree().root.theme = UITheme.build_global_theme()
	# El texto flotante del mundo usa GameConfig.resource_colors: misma paleta.
	# Se pisan los cuatro de la paleta y se conservan los demas (materiales,
	# comida): reemplazar el diccionario entero los dejaba sin color.
	for pair in [["gold", UITheme.RES_GOLD], ["steel", UITheme.RES_STEEL],
			["oil", UITheme.RES_OIL], ["wood", UITheme.RES_WOOD]]:
		GameConfig.resource_colors[pair[0]] = pair[1]

## Escala al momento. En headless no se toca: los tests miden paneles contra el
## lienzo de 1280x720 y no deben depender de la pantalla de quien los corre.
func apply_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var factor := content_scale_for(_window_size(), effective_ui_scale())
	var root := get_tree().root
	if is_equal_approx(root.content_scale_factor, factor) and is_equal_approx(_factor, factor):
		return
	_factor = factor
	root.content_scale_factor = factor
	# Cambiar la escala no siempre avisa size_changed: se recoloca a mano.
	UILayoutManager.refresh_viewport()
	scale_applied.emit(factor)

func current_factor() -> float:
	return get_tree().root.content_scale_factor

func _on_window_resized() -> void:
	# Girar la tablet o pasar a pantalla completa cambia la proporcion.
	apply_scale.call_deferred()

# ── Tope de fotogramas ────────────────────────────────────────────────

## Tope de fotogramas para una preferencia y un estado. Puro. 0 = sin tope
## (lo marca el vsync). `profile_fps` es el del perfil, para "auto". En pausa
## baja a GameConfig.fps_paused y sin foco a fps_background, nunca por encima de
## lo elegido (con 30 elegido, la pausa se queda en 30, no sube).
static func fps_for(mode: String, profile_fps: int, focused: bool, paused: bool) -> int:
	var cap := 0
	if mode == "auto":
		cap = profile_fps
	elif mode != "unlimited" and mode.is_valid_int():
		cap = int(mode)
	# Los dos a la vez: en pausa y sin foco manda el menor de los dos.
	if paused:
		cap = _min_cap(cap, GameConfig.fps_paused)
	if not focused:
		cap = _min_cap(cap, GameConfig.fps_background)
	return cap

## El menor de dos topes, donde 0 es "sin tope" (infinito).
static func _min_cap(a: int, b: int) -> int:
	if a <= 0:
		return b
	if b <= 0:
		return a
	return mini(a, b)

## El tope de "auto": el del perfil, o GameConfig.fps_minimal_pc en un PC con
## la calidad Minima.
func auto_fps() -> int:
	return auto_fps_for(current(), GraphicsQuality.is_minimal())

static func auto_fps_for(profile: String, minimal: bool) -> int:
	var fps := int(DEFAULTS.get(profile, DEFAULTS[PC])["fps"])
	if profile == PC and minimal:
		fps = mini(fps, int(GameConfig.fps_minimal_pc))
	return fps

## El tope que vale ahora mismo, con el foco y la pausa de este momento. Sin
## tope mientras se mide la calidad (la pausa del menu de titulo lo bajaria a 30
## y la medida veria un equipo flojo en cualquiera).
func effective_fps_cap() -> int:
	if _detect == Detect.WARMUP or _detect == Detect.MEASURE:
		return 0
	return fps_for(GameConfig.ui_fps_cap, auto_fps(), _focused, _paused)

## Lo aplica. En headless no: los tests esperan fotogramas y un tope los haria
## lentos, y las sondas sin ventana miden sin el.
func apply_fps() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cap := effective_fps_cap()
	if Engine.max_fps != cap:
		Engine.max_fps = cap

func set_fps_cap(mode: String) -> void:
	if not mode in GameConfig.FPS_CAP_MODES:
		mode = "auto"
	GameConfig.ui_fps_cap = mode
	GameConfig.save_user_settings()
	apply_fps()

## La pausa no avisa por ninguna senal (la ponen PauseMenu, TitleMenu y
## PrologueScreen a mano): se mira aqui, un booleano por fotograma.
func _process(delta: float) -> void:
	var paused := get_tree().paused
	if paused != _paused:
		_paused = paused
		apply_fps()
	if _detect != Detect.OFF:
		_step_detection(delta)
	elif _pending_notice != "" and not paused and GameManager.is_started():
		EventBus.notification_posted.emit(_pending_notice, "notice", UITheme.INFO)
		_pending_notice = ""

## La de aplicacion y no la de ventana: esto es un autoload (ver InputService).
## Minimizar en Windows tambien quita el foco.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			# Una medida sin foco no vale: se descarta y se repite en el
			# siguiente arranque (quality_detected sigue sin guardarse).
			if _detect != Detect.OFF:
				_detect = Detect.OFF
				print("[DeviceProfile] medida de calidad descartada (sin foco)")
			apply_fps()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			apply_fps()

## Reconstruye la interfaz con los tokens nuevos conservando la partida (la misma
## recarga que el cambio de idioma). Devuelve false si ahora no se puede (sin
## partida, o con un tablero abierto): la preferencia ya esta guardada y se vera
## la proxima vez que se construya la interfaz.
func rebuild_ui(reopen_tab: int = -1) -> bool:
	apply_theme()
	if not GameManager.is_started():
		return false
	if CombatManager.is_board_open() or not CombatManager.is_save_safe():
		EventBus.notification_posted.emit(Tr.t("NOTIF_UI_AFTER_BATTLE"), "info", UITheme.INFO)
		return false
	reopen_settings_tab = reopen_tab
	GameManager.reload_keeping_game.call_deferred()
	return true

# ── Calidad grafica ───────────────────────────────────────────────────

func _on_graphics_quality_changed(_q: String) -> void:
	GraphicsQuality.apply_runtime(get_tree())
	apply_fps()

## Arranca la deteccion. Sin `force`, solo la primera vez (calidad "auto" y sin
## quality_detected); con `force` ("Detectar de nuevo" en Ajustes), siempre:
## vuelve a "auto" y decide otra vez. Nunca en headless (tests, sondas sin
## ventana) ni con `-- --no-title` / `-- --no-detect` (sondas con ventana).
func start_quality_detection(force: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--no-title") or args.has("--no-detect"):
		return
	if not force and (GameConfig.ui_graphics_quality != "auto" or GameConfig.quality_detected):
		return
	if force and GameConfig.ui_graphics_quality != "auto":
		GraphicsQuality.set_quality("auto")
	var info := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter_type": RenderingServer.get_video_adapter_type(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"ram_mb": _system_ram_mb(),
		"threads": OS.get_processor_count(),
		"profile": current(),
		"mobile": GraphicsQuality.is_mobile_platform(),
	}
	var verdict := GraphicsQuality.static_verdict(info)
	print("[DeviceProfile] deteccion de calidad, paso 1: %s -> %s" % [info, verdict])
	if str(verdict["quality"]) != "":
		_finish_detection(str(verdict["quality"]), str(verdict["reason"]))
		return
	# Paso 2: se mide el mapa 3D, que es lo que Minima abarata. En la vista 2D
	# no se mide: queda pendiente para un arranque en 3D.
	if GameConfig.ui_view_mode == "2d":
		return
	_detect = Detect.WAIT_GAME
	_detect_timer = 0.0
	_detect_frames.clear()

func is_detecting_quality() -> bool:
	return _detect != Detect.OFF

func _system_ram_mb() -> int:
	var mem := OS.get_memory_info()
	var bytes := int(mem.get("physical", -1))
	return int(bytes / (1024 * 1024)) if bytes > 0 else -1

func _step_detection(delta: float) -> void:
	match _detect:
		Detect.WAIT_GAME:
			# El mapa ya cargado detras del menu de titulo (TitleMenu va encima).
			if GameManager.is_started():
				_detect = Detect.WARMUP
				_detect_timer = 0.0
				apply_fps()
		Detect.WARMUP:
			_detect_timer += delta
			if _detect_timer >= float(GameConfig.quality_detect_warmup):
				_detect = Detect.MEASURE
				_detect_timer = 0.0
				_detect_frames.clear()
				_detect_quality = GraphicsQuality.current()
		Detect.MEASURE:
			_detect_timer += delta
			_detect_frames.append(delta * 1000.0)
			if _detect_timer >= float(GameConfig.quality_detect_seconds):
				_detect = Detect.OFF
				var hz := DisplayServer.screen_get_refresh_rate()
				var q := GraphicsQuality.measure_verdict(_detect_frames, _detect_quality,
					hz if hz > 0.0 else 60.0)
				# Si el jugador eligio una calidad mientras se media, manda la suya.
				if GameConfig.ui_graphics_quality != "auto":
					q = ""
				var sorted := _detect_frames.duplicate()
				sorted.sort()
				var median := float(sorted[sorted.size() / 2]) if not sorted.is_empty() else 0.0
				_finish_detection(q, "medida %s: mediana %.1f ms, %d fotogramas" % [
					_detect_quality, median, _detect_frames.size()])
				apply_fps()

## Guarda el resultado (una sola vez) y, si se bajo la calidad, deja el aviso
## para cuando se cierre el menu de titulo.
func _finish_detection(quality: String, reason: String) -> void:
	GameConfig.quality_detected = true
	GameConfig.quality_detected_reason = reason
	print("[DeviceProfile] deteccion de calidad: '%s' (%s)" % [quality, reason])
	if quality == "":
		GameConfig.save_user_settings()
		return
	var restart := GraphicsQuality.set_quality(quality)
	var msg := Tr.t("MSG_QUALITY_AUTO_MINIMAL" if quality == "minimal" else "MSG_QUALITY_AUTO_LOW")
	if restart:
		msg += " " + Tr.t("MSG_QUALITY_RESTART")
	_pending_notice = msg
