extends Node
## Central configuration table for all tunable game values.
## dev_mode (fast timings) is on in the editor and off in exports; see below.

# ── Master Controls ──

## dev_mode comprime todas las duraciones (dev_time_scale) y enseña los botones de
## desarrollo (borrar partida en ResourceHUD, combate de prueba en SkirmishPanel).
## No se decide a mano: vale true cuando el juego corre desde el editor (F5, tests,
## sondas) y false en cualquier exportado, sea release o debug. Así un .exe que se
## reparte nunca sale con tiempos de prueba por un commit despistado.
## Para forzarlo, argumentos de usuario tras `--`:
##   TormentaImperial.exe -- --dev      exportado con tiempos de prueba
##   godot --path . -- --no-dev         editor con tiempos reales
var dev_mode := _resolve_dev_mode()
var time_multiplier := 1.0
## Cuanto se acelera todo en dev_mode. Estaba a 1/10 y Bryan, jugando, no llegaba a
## leer que pasaba: construir en 1 s y una tormenta cada 30 s convierten el ciclo en
## un borron. A 1/5 sigue siendo una partida de minutos, pero se entiende.
var dev_time_scale := 0.2

# ── Population & Morale Constants ──

var morale_start := 75
var morale_min := 0
var morale_max := 100
var morale_growth_threshold := 30
var morale_danger_threshold := 20
var morale_satisfied_recovery := 3
var morale_unsatisfied_penalty := -8
var population_start := 5
var consumption_interval := 30.0
var growth_interval := 20.0

# ── Random Event Timing ──

var event_interval_min := 120.0
var event_interval_max := 300.0
var event_interval_min_dev := 30.0
var event_interval_max_dev := 60.0

# ── Starting Resources ──

var starting_resources := {
	"gold": 300,
	"wood": 200,
}

# ── Upgrade System ──

var max_building_level := 3

## Cost multiplier per level: level 1 = base cost, level 2 = 1.8x, level 3 = 3.0x
var upgrade_cost_multiplier := [1.0, 1.8, 3.0]

## Production multiplier per level
var upgrade_production_multiplier := [1.0, 1.6, 2.5]

## Lo que da subir de nivel lo que no produce (2026-09-28). Antes una vivienda,
## un almacen o una fuente subian de nivel sin cambiar nada.
## Vivienda: sitio para trabajadores por nivel (6 -> 9 -> 12).
var upgrade_capacity_multiplier := [1.0, 1.5, 2.0]
## Decoraciones: moral por nivel.
var upgrade_morale_multiplier := [1.0, 1.5, 2.0]
## Almacen: almacen extra por cada nivel por encima del 1.
var warehouse_level_bonus := 250

## Multiplicador de una tabla por nivel (1..max), 1.0 fuera de rango.
func level_mult(table: Array, level: int) -> float:
	if level < 1 or level > table.size():
		return 1.0
	return float(table[level - 1])

## Upgrade duration base (seconds), scaled by time_multiplier
var upgrade_base_duration := 15.0

# ── HQ Upgrade Override (capstone building, much more expensive) ──

var hq_upgrade_costs := {
	2: {"gold": 800, "steel": 500, "oil": 300, "wood": 400, "beams": 15, "ingots": 10, "fuel": 15},
	3: {"gold": 1500, "steel": 800, "oil": 500, "wood": 700, "beams": 25, "ingots": 20, "fuel": 25},
}

# ── Building Limits (max per type, -1 = unlimited) ──

var building_limits := {
	"sawmill": 5,
	"gold_mine": 4,
	"foundry": 3,
	"refinery": 2,
	"warehouse": 5,
	# El Mercado y el Laboratorio abren el comercio y el arbol tecnologico
	# (2026-09-28): uno de cada basta.
	"market": 1,
	"laboratory": 1,
	"barracks": 3,
	"tower": 6,
	"headquarters": 1,
	"house": 10,
	"garden": -1,
	"statue": 5,
	"fountain": 5,
	"road": -1,
}

# ── Building Prerequisites (must have at least 1 of each listed) ──

## La Fundicion abre la era 2 y la Refineria la 3: no se sube de era sin la base
## de la anterior en pie (2026-09-28). Era 1 completa = madera, oro, gente y
## almacen; era 2 completa = acero y un Cuartel que la defienda.
var building_prerequisites := {
	"foundry": ["sawmill", "gold_mine", "house", "warehouse"],
	"market": ["gold_mine"],
	"laboratory": ["house"],
	"refinery": ["foundry", "barracks"],
	"barracks": ["foundry", "sawmill"],
	"tower": ["barracks"],
	"headquarters": ["barracks", "refinery"],
}

# ── Deposit Placement Rules (extractor next to its deposit) ──
#
# Decision del dueno (P1, 2026-09-14): cada extractor se levanta junto al
# yacimiento que explota, y sigue produciendo pasivamente como siempre. La
# produccion se lee como "cosechar ese bosque / esa veta", no como madera que
# aparece de la nada. Nada se agota por producir: el minado a mano en el
# yacimiento sigue igual.
#
# - `deposit`:  id del yacimiento (MapGenerator.DEPOSIT_TYPES).
# - `reach`:    0 = el edificio debe SOLAPAR el yacimiento (la Refineria se
#               planta sobre el pozo); 1 = alguna celda del edificio toca alguna
#               del yacimiento, diagonal incluida, sin pisarlo (nadie construye
#               encima de los arboles).
# - `consumes`: si al colocarlo el yacimiento desaparece (solo la Refineria,
#               como hasta ahora). Con alcance 1 nunca se consume.
# - `message`:  clave de Tr con el aviso al jugador cuando no se cumple.
#
# La misma regla vale para colocar y para MOVER: si no, se colocaba bien y luego
# se arrastraba a cualquier sitio.

var building_deposit_rules := {
	"refinery":  {"deposit": "oil_well",     "reach": 0, "consumes": true,  "message": "LBL_REQUIRES_DEPOSIT"},
	"sawmill":   {"deposit": "forest",       "reach": 1, "consumes": false, "message": "LBL_NEEDS_FOREST_NEAR"},
	"gold_mine": {"deposit": "gold_vein",    "reach": 1, "consumes": false, "message": "LBL_NEEDS_GOLD_VEIN_NEAR"},
	"foundry":   {"deposit": "iron_deposit", "reach": 1, "consumes": false, "message": "LBL_NEEDS_IRON_NEAR"},
}

## Regla de yacimiento de un edificio, o {} si construye donde quiera.
func get_deposit_rule(building_id: String) -> Dictionary:
	return building_deposit_rules.get(building_id, {})

# ── Storage ──
#
# El almacen es UNA bolsa compartida por los cuatro recursos, no un tope por
# recurso. Guardar oro tiene que significar no guardar acero: es lo que hace que
# el mercado sirva, que gastar antes de la Tormenta sea la jugada correcta y que
# llegar lleno al Diezmo sea una decision y no un descuido.
#
# Los dos extremos de la tabla estan fijados por razones distintas:
#
# - **Era 1 = 600 porque la apertura tiene que poder jugarse.** Se empieza con 500
#   (300 oro + 200 madera) y los dos primeros edificios que el juego pide, serreria
#   (80/50) y mina de oro (120/80), suman 330. Con un tope de 300 el jugador
#   arrancaba 200 por encima del limite y perdia recursos antes de tomar su primera
#   decision: el juego le quitaba cosas por existir, no por elegir mal. 600 sigue
#   siendo asfixiante frente a los 800 POR RECURSO de antes (1600 utiles en Era 1),
#   pero deja jugar la apertura y obliga a elegir a partir de ahi.
# - **Era 3 = 1000 porque cuadra con el precio de la victoria.** 1000 + 5x500 = 3500,
#   exactamente lo que cuesta la mejora del Cuartel General a Nv.3 (1500 oro + 800
#   acero + 500 petroleo + 700 madera). Para ganar hay que llegar con la bolsa llena
#   y los cinco almacenes en pie, que es justo cuando mas tienes que perder. Este
#   numero no se mueve sin mover tambien `hq_upgrade_costs`.

## Tope base de la bolsa, por era.
var base_storage_cap_by_era := {
	1: 600,
	2: 800,
	3: 1000,
}

var warehouse_storage_bonus := 500

## Bonificacion permanente de almacenamiento del arbol tecnologico (runtime).
var tech_storage_bonus := 0

# ── Building Processes (margins ~1.5x) ──

var building_processes := {
	"nucleo": [
		{"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 35}},
		{"id": "iron_sheets", "name": "PROC_IRON_SHEETS", "duration": 45.0,
		 "cost": {"steel": 20}, "produces": {"steel": 30}},
		{"id": "water_pipes", "name": "PROC_WATER_PIPES", "duration": 60.0,
		 "cost": {"steel": 15, "wood": 10}, "produces": {"gold": 60}},
	],
	"sawmill": [
		{"id": "make_planks", "name": "PROC_MAKE_PLANKS", "duration": 20.0,
		 "cost": {"wood": 20}, "produces": {"planks": 5}},
		{"id": "refined_lumber", "name": "PROC_REFINED_LUMBER", "duration": 30.0,
		 "cost": {"wood": 15}, "produces": {"wood": 25, "gold": 5}},
		{"id": "charcoal", "name": "PROC_CHARCOAL", "duration": 25.0,
		 "cost": {"wood": 25}, "produces": {"steel": 12}},
	],
	"gold_mine": [
		{"id": "make_ingots", "name": "PROC_MAKE_INGOTS", "duration": 30.0,
		 "cost": {"gold": 30}, "produces": {"ingots": 3}},
		{"id": "deep_mining", "name": "PROC_DEEP_MINING", "duration": 35.0,
		 "cost": {"steel": 10}, "produces": {"gold": 35}},
		{"id": "gem_extraction", "name": "PROC_GEM_EXTRACTION", "duration": 60.0,
		 "cost": {"gold": 20, "steel": 5}, "produces": {"gold": 60}},
	],
	"foundry": [
		{"id": "make_beams", "name": "PROC_MAKE_BEAMS", "duration": 30.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"beams": 4}},
		{"id": "alloy_smelting", "name": "PROC_ALLOY_SMELTING", "duration": 40.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"steel": 45}},
		{"id": "armor_plates", "name": "PROC_ARMOR_PLATES", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 15, "gold": 20}},
	],
	"refinery": [
		{"id": "make_fuel", "name": "PROC_MAKE_FUEL", "duration": 25.0,
		 "cost": {"oil": 15}, "produces": {"fuel": 5}},
		{"id": "fuel_distillation", "name": "PROC_FUEL_DISTILLATION", "duration": 30.0,
		 "cost": {"oil": 15}, "produces": {"oil": 25}},
		{"id": "chemical_processing", "name": "PROC_CHEMICAL_PROCESSING", "duration": 50.0,
		 "cost": {"oil": 20, "steel": 10}, "produces": {"oil": 18, "gold": 25}},
	],
}

# ── Materiales (2026-09-28) ──
#
# Cada edificio especializado fabrica, con su recurso, un material para los
# edificios avanzados (el primer proceso de su lista en building_processes). El
# material aparece en el juego cuando se termina el primero de su edificio.
# Viven fuera de la bolsa compartida (ResourceManager: el taller del Nucleo).
var material_sources := {
	"planks": "sawmill",
	"ingots": "gold_mine",
	"beams": "foundry",
	"fuel": "refinery",
}

## El edificio que fabrica un material ("" si no es un material).
func get_material_source(res_name: String) -> String:
	return String(material_sources.get(res_name, ""))

## El material que fabrica un edificio ("" si ninguno).
func get_material_of(building_id: String) -> String:
	for m in material_sources:
		if material_sources[m] == building_id:
			return m
	return ""

# ── Mining Data ──

var mining_data := {
	"gold_vein": {"id": "mine_gold", "name": "PROC_MINE_GOLD", "duration": 12.0, "produces": {"gold": 20}},
	"iron_deposit": {"id": "mine_iron", "name": "PROC_MINE_IRON", "duration": 18.0, "produces": {"steel": 15}},
	"oil_well": {"id": "mine_oil", "name": "PROC_MINE_OIL", "duration": 22.0, "produces": {"oil": 10}},
	"forest": {"id": "mine_wood", "name": "PROC_MINE_WOOD", "duration": 8.0, "produces": {"wood": 20}},
}

## Trabajadores que ocupa sacar una veta a mano mientras dura (2026-09-28):
## minar no es gratis, se quitan a un edificio o se esperan.
var mining_workers := 2

# ── Deposit Config ──

var deposit_max_uses := {
	"gold_vein": 8,
	"iron_deposit": 7,
	"oil_well": 10,
	"forest": 8,
}

var deposit_count_min := 18
var deposit_count_max := 28
var deposit_center_exclusion := 6
## Lo minimo de cada tipo que trae cualquier isla, por encima del sorteo. Sin
## esto ~2 de cada 100 mapas salian sin pozo (sin era 3, sin final) o sin bosque.
## Dos pozos porque la Refineria se come el suyo y el tope es de dos; dos vetas
## porque el oro paga la comida, los sueldos y casi cada obra.
var deposit_min_per_type := {
	"forest": 2,
	"gold_vein": 2,
	"iron_deposit": 1,
	"oil_well": 2,
}

# ── Deposit Sizes (random range per type: min_w, max_w, min_h, max_h) ──
var deposit_sizes := {
	"gold_vein": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"iron_deposit": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"oil_well": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"forest": {"min_w": 2, "max_w": 4, "min_h": 2, "max_h": 4},
}

# ── Deposit Resource Mapping (which resource a deposit requires unlocked) ──

var deposit_resource_required := {
	"gold_vein": "gold",
	"iron_deposit": "steel",
	"oil_well": "oil",
	"forest": "wood",
}

# ── Resource Display Colors ──

var resource_colors := {
	"gold": Color(1.0, 0.85, 0.1),
	"steel": Color(0.7, 0.75, 0.8),
	"oil": Color(0.5, 0.4, 0.6),
	"wood": Color(0.55, 0.35, 0.15),
	"planks": Color(0.82, 0.62, 0.36),
	"ingots": Color(1.0, 0.72, 0.25),
	"beams": Color(0.55, 0.62, 0.72),
	"fuel": Color(0.85, 0.38, 0.2),
}

# ── Audio ──
# Volumes are linear [0.0, 1.0]; AudioManager converts to dB per bus.
# Master scales all others. Set any to 0.0 to mute that channel.

## Valores de serie bajos (bug 4): el primer arranque sonaba muy fuerte. Los
## deslizadores siguen una curva perceptual (AudioManager.slider_to_db), asi que
## 0.8 / 0.5 ya bajan de verdad. Quien ya guardo settings.cfg conserva lo suyo.
## Los de serie, en un sitio: Ajustes > Audio > Restablecer vuelve a estos.
const AUDIO_DEFAULTS := {"master": 0.8, "music": 0.35, "sfx": 0.5, "ambient": 0.4}
var audio_master_volume: float = AUDIO_DEFAULTS["master"]
## Bajada de 0.6 a 0.35: el dueno la encontraba muy invasiva. Quien ya guardo
## un volumen en settings.cfg conserva el suyo.
var audio_music_volume: float = AUDIO_DEFAULTS["music"]
## Musica si/no, aparte del volumen (Ajustes y el menu ☰). Apagada, AudioManager
## no arranca ninguna pista, ni al cambiar de era ni al entrar en combate.
var audio_music_enabled := true
var audio_sfx_volume: float = AUDIO_DEFAULTS["sfx"]
var audio_ambient_volume: float = AUDIO_DEFAULTS["ambient"]

# ── Camara: arrastrar el mapa ──
# El raton y el dedo mueven el mapa con la misma cuenta (agarrar el terreno y
# llevarlo), asi que lo unico que se ajusta por separado es cuanto hay que
# moverse antes de que un clic deje de ser un clic.

## Pixeles que el cursor recorre con el boton izquierdo pulsado antes de que el
## clic pase a ser un arrastre del mapa. Mas bajo: el mapa se mueve al minimo
## temblor y cuesta seleccionar un edificio. Mas alto: el arrastre parece que
## tarda en enganchar el terreno.
var mouse_drag_threshold_px := 6.0

## Lo mismo para el dedo, en dp (1 dp = 1/160 de pulgada): un dedo se mueve un par
## de milimetros incluso en un toque que el jugador siente inmovil, y eso son
## pixeles distintos en cada pantalla. Con los 12 px fisicos de antes, en una
## tablet de ~280 dpi un toque normal (1-2 mm) pasaba el umbral, se volvia
## arrastre y el aserradero no se colocaba. 14 dp son ~2,2 mm; el paneo no pierde
## nada por esperar, porque arranca desde donde se apoyo el dedo.
## InputService.touch_slop_px() lo pasa a pixeles del lienzo con el dpi real.
var touch_drag_threshold_dp := 14.0
## Suelo del umbral anterior, en pixeles del lienzo: por mucho que el dpi diga,
## un toque nunca se vuelve arrastre por menos de esto.
var touch_drag_threshold_px := 8.0

## Pellizco: cuanto tiene que cambiar la separacion entre los dos dedos (en
## pixeles) para mover el zoom. Absorbe el temblor de dos dedos quietos; si se
## sube, el zoom empieza a ir a tirones.
var pinch_zoom_dead_zone_px := 1.0

## Zoom por pellizco: unidades de distancia de camara por pixel de separacion
## ganada entre los dedos. Mas alto = el mapa se acerca de golpe.
var pinch_zoom_sensitivity := 0.05

# ── tactil ──
## Dos dedos: el gesto se bloquea en giro si la linea entre ellos gira esto (en
## grados) antes de que la separacion cambie pinch_lock_scale (8 %), y en zoom al
## reves. Mas bajo: cuesta hacer un pellizco que no gire. Mas alto: el giro tarda
## en engancharse.
var twist_lock_degrees := 8.0
var pinch_lock_scale := 0.08
## Sentido del giro con dos dedos (+1: el terreno gira con los dedos). Solo 3D.
var twist_rotate_sign := 1.0
## Mantener pulsado un boton de accion en pantalla lo repite: primero al tocar,
## luego tras hold_repeat_delay_sec, y despues cada hold_repeat_interval_sec.
var hold_repeat_delay_sec := 0.3
var hold_repeat_interval_sec := 0.08
## Grados por segundo que gira la camara con ↺/↻ mantenidos (tras el primer paso).
var hold_rotate_degrees_per_sec := 90.0
## Opacidad de los controles en pantalla (cruceta, zoom, giro, colocar): fondo,
## borde y simbolo. Al pulsar un boton se ve entero; en reposo vuelve a esto.
## Del dispositivo, en settings.cfg [ui] touch_controls_opacity.
const TOUCH_OPACITY_MIN := 0.15
const TOUCH_OPACITY_MAX := 1.0
var ui_touch_controls_opacity := 0.45

# ── User Settings persistence ──
# Device-local preferences (volumes, UI toggles) — separate from save_game.json
# so they survive "new game" and apply before any save is loaded.

const USER_SETTINGS_PATH := "user://settings.cfg"

## Whether the map cell grid overlay is shown permanently (toggle in Settings).
## On by default (A10): the owner wants to see the cells at all times, faintly;
## the alpha lives in the GridOverlay material in Main.tscn.
var ui_grid_visible := true

## Whether the on-screen helper callouts are shown ("?" button). On by default
## so new players get guidance; the choice persists once toggled.
var ui_helper_visible := true

## Whether the game runs in exclusive fullscreen. Toggled with F11 or from the
## Settings panel; persists in user://settings.cfg like the rest of preferences.
var ui_fullscreen := false

## Vista del mapa: "3d" (Main.tscn) o "2d" (Main2D.tscn, docs/18-vista-2d.md).
## Cambiar el valor por defecto a "2d" es lo unico que hace falta para que la
## vista 2D sea la de serie. `--view=2d` en la linea de comandos manda sobre esto
## solo en esa sesion (ViewMode.gd).
var ui_view_mode := "3d"
## Controles tactiles en pantalla (D-pad, zoom, rotar, cancelar colocacion).
## "auto" sigue al perfil de dispositivo (DeviceProfile): tablet y movil los
## ensenan, PC nunca, aunque la pantalla sea tactil; "always" y "never" fuerzan. En escritorio sobran:
## hay WASD y rueda, y los botones ocupaban las cuatro esquinas de la pantalla.
## El mismo estado decide si los botones pequenos del HUD crecen a tamano dedo
## (UITheme.touch_px).
const TOUCH_CONTROLS_MODES := ["auto", "always", "never"]
var ui_touch_controls := "auto"
## Idioma de la interfaz ("es" / "en"). Vive en settings.cfg y no en la partida:
## es del dispositivo, sobrevive a "partida nueva" y se aplica antes de pintar nada.
var ui_locale := "es"

# ── interfaz-dispositivos (docs/21-interfaz-y-dispositivos.md) ──
# Todo del dispositivo, en settings.cfg [interfaz]: una tablet y un PC del mismo
# jugador no tienen por que querer la misma letra ni la misma disposicion.

## Perfil de dispositivo: "auto" lo detecta DeviceProfile; "pc", "tablet" y
## "phone" lo fuerzan.
const DEVICE_PROFILE_MODES := ["auto", "pc", "tablet", "phone"]
var ui_device_profile := "auto"
## Escala global de la interfaz en %. 0 = la del perfil de dispositivo.
const UI_SCALE_MIN := 75
const UI_SCALE_MAX := 150
var ui_scale_pct := 0
## Tamano de texto: "auto" (el del perfil) o uno de UITheme.TEXT_SIZES.
var ui_text_size := "auto"
## Paleta de colores (UITheme.PALETTES), alto contraste y opacidad de paneles.
var ui_palette := "default"
var ui_high_contrast := false
var ui_panel_opacity := 1.0
## Ids de HudRegistry que el jugador oculto.
var ui_hud_hidden: Array = []
## Disposicion movida a mano: {"<perfil>|<aspecto>": {panel_id: [dx, dy]}}.
var ui_layout: Dictionary = {}

func _ready() -> void:
	# Una línea en el log: quien reporte un fallo con el .exe dirá en qué modo jugaba.
	print("[GameConfig] version %s, dev_mode=%s" % [ProjectSettings.get_setting("application/config/version", "?"), dev_mode])
	load_user_settings()
	# El modo de ventana se aplica en cuanto arranca, antes de que se dibuje la UI.
	_apply_window_mode()

## Resuelve dev_mode al arrancar (ver el comentario de la variable). El feature tag
## "editor" solo existe en el binario del editor, nunca en una plantilla de exportación.
static func _resolve_dev_mode() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-dev"):
		return false
	if args.has("--dev"):
		return true
	return OS.has_feature("editor")

func load_user_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(USER_SETTINGS_PATH) != OK:
		return
	audio_master_volume = clampf(float(cf.get_value("audio", "master", audio_master_volume)), 0.0, 1.0)
	audio_music_volume = clampf(float(cf.get_value("audio", "music", audio_music_volume)), 0.0, 1.0)
	audio_sfx_volume = clampf(float(cf.get_value("audio", "sfx", audio_sfx_volume)), 0.0, 1.0)
	audio_ambient_volume = clampf(float(cf.get_value("audio", "ambient", audio_ambient_volume)), 0.0, 1.0)
	audio_music_enabled = bool(cf.get_value("audio", "music_enabled", audio_music_enabled))
	ui_grid_visible = bool(cf.get_value("ui", "grid_visible", ui_grid_visible))
	ui_helper_visible = bool(cf.get_value("ui", "helper_visible", ui_helper_visible))
	ui_fullscreen = bool(cf.get_value("ui", "fullscreen", ui_fullscreen))
	var view := String(cf.get_value("ui", "view_mode", ui_view_mode))
	ui_view_mode = view if view in ["3d", "2d"] else ui_view_mode
	var touch_mode := String(cf.get_value("ui", "touch_controls", ui_touch_controls))
	# Un valor desconocido en el archivo (edicion a mano, version vieja) vuelve
	# a "auto" en vez de dejar los controles en un estado que nadie eligio.
	ui_touch_controls = touch_mode if touch_mode in TOUCH_CONTROLS_MODES else "auto"
	# Una sola clave: [ui] touch_controls_opacity. La vieja `touch_opacity` (menu
	# unico, #31) se lee si la nueva no esta y desaparece al guardar.
	var old_opacity: Variant = cf.get_value("ui", "touch_opacity", ui_touch_controls_opacity)
	ui_touch_controls_opacity = clampf(float(cf.get_value("ui", "touch_controls_opacity",
		old_opacity)), TOUCH_OPACITY_MIN, TOUCH_OPACITY_MAX)
	var locale := str(cf.get_value("ui", "locale", ui_locale))
	if Tr.LOCALES.has(locale):
		ui_locale = locale
	Tr.set_locale(ui_locale)
	_load_interface_settings(cf)

## [interfaz]: cada valor se valida; uno desconocido vuelve al de serie en vez
## de dejar la interfaz en un estado que nadie eligio.
func _load_interface_settings(cf: ConfigFile) -> void:
	var prof := str(cf.get_value("interfaz", "device_profile", ui_device_profile))
	ui_device_profile = prof if prof in DEVICE_PROFILE_MODES else "auto"
	var scale := int(cf.get_value("interfaz", "ui_scale_pct", ui_scale_pct))
	ui_scale_pct = 0 if scale == 0 else clampi(scale, UI_SCALE_MIN, UI_SCALE_MAX)
	var text := str(cf.get_value("interfaz", "text_size", ui_text_size))
	ui_text_size = text if (text == "auto" or text in UITheme.TEXT_SIZES) else "auto"
	var pal := str(cf.get_value("interfaz", "palette", ui_palette))
	ui_palette = pal if pal in UITheme.PALETTES else "default"
	ui_high_contrast = bool(cf.get_value("interfaz", "high_contrast", ui_high_contrast))
	ui_panel_opacity = clampf(float(cf.get_value("interfaz", "panel_opacity", ui_panel_opacity)),
		UITheme.OPACITY_MIN, UITheme.OPACITY_MAX)
	var hidden: Variant = cf.get_value("interfaz", "hud_hidden", ui_hud_hidden)
	ui_hud_hidden = []
	if hidden is Array:
		for id in hidden:
			ui_hud_hidden.append(str(id))
	var layout: Variant = cf.get_value("interfaz", "layout", ui_layout)
	ui_layout = layout.duplicate(true) if layout is Dictionary else {}

func save_user_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(USER_SETTINGS_PATH)  # keep unknown sections if the file already exists
	cf.set_value("audio", "master", audio_master_volume)
	cf.set_value("audio", "music", audio_music_volume)
	cf.set_value("audio", "sfx", audio_sfx_volume)
	cf.set_value("audio", "ambient", audio_ambient_volume)
	cf.set_value("audio", "music_enabled", audio_music_enabled)
	cf.set_value("ui", "grid_visible", ui_grid_visible)
	cf.set_value("ui", "helper_visible", ui_helper_visible)
	cf.set_value("ui", "fullscreen", ui_fullscreen)
	cf.set_value("ui", "view_mode", ui_view_mode)
	cf.set_value("ui", "touch_controls", ui_touch_controls)
	cf.set_value("ui", "touch_controls_opacity", ui_touch_controls_opacity)
	if cf.has_section_key("ui", "touch_opacity"):
		cf.erase_section_key("ui", "touch_opacity")
	cf.set_value("ui", "locale", ui_locale)
	cf.set_value("interfaz", "device_profile", ui_device_profile)
	cf.set_value("interfaz", "ui_scale_pct", ui_scale_pct)
	cf.set_value("interfaz", "text_size", ui_text_size)
	cf.set_value("interfaz", "palette", ui_palette)
	cf.set_value("interfaz", "high_contrast", ui_high_contrast)
	cf.set_value("interfaz", "panel_opacity", ui_panel_opacity)
	cf.set_value("interfaz", "hud_hidden", ui_hud_hidden)
	cf.set_value("interfaz", "layout", ui_layout)
	cf.save(USER_SETTINGS_PATH)

# ── Controles tactiles ──

## Si ya ha llegado un toque de pantalla REAL en esta sesion (InputService lo
## avisa). No se guarda: un portatil tactil que hoy se usa con el dedo manana
## puede usarse con raton, y el ajuste explicito es "Siempre".
var _real_touch_seen := false

## Si los controles en pantalla deben verse ahora, resolviendo el "auto".
## Es la unica pregunta que hace OnScreenControls.
##
## "auto" sigue al perfil de dispositivo (DeviceProfile): tablet y movil los
## llevan, PC NUNCA (norma de Bryan). Ni DisplayServer.is_touchscreen_available()
## ni un toque real los encienden en un PC: un portatil Windows tactil que se
## toca una vez no se llena de flechas. Quien los quiera en PC elige "Siempre"
## o el perfil Tablet.
func touch_controls_enabled() -> bool:
	match ui_touch_controls:
		"always":
			return true
		"never":
			return false
		_:
			return _touch_profile()

## "auto" sigue al perfil de dispositivo (tablet y movil llevan controles en
## pantalla; PC no), asi que forzar el perfil Tablet en Ajustes los trae.
## Sin DeviceProfile (no deberia pasar) se mira el sistema, como antes.
func _touch_profile() -> bool:
	var dp := get_node_or_null("/root/DeviceProfile")
	if dp != null and dp.has_method("is_touch_profile"):
		return dp.is_touch_profile()
	return is_mobile_os()

## Movil de verdad: exportado a Android/iOS, o la web abierta en uno de ellos.
static func is_mobile_os() -> bool:
	for feature in ["mobile", "android", "ios", "web_android", "web_ios"]:
		if OS.has_feature(feature):
			return true
	return false

## InputService llama aqui con cada InputEventScreenTouch real (el proyecto no
## emula toques desde el raton, asi que un toque es un dedo). Solo se anota:
## en PC un toque ya no enciende los controles (ver touch_controls_enabled);
## sirve para que los textos de ayuda hablen de dedos (DeviceProfile.input_style).
func notice_real_touch() -> void:
	_real_touch_seen = true

func real_touch_seen() -> bool:
	return _real_touch_seen

## Cambia el modo, lo guarda y anuncia el estado resuelto para que los controles
## aparezcan o desaparezcan sin reiniciar.
func set_touch_controls(mode: String) -> void:
	if not mode in TOUCH_CONTROLS_MODES:
		mode = "auto"
	if ui_touch_controls == mode:
		return
	ui_touch_controls = mode
	save_user_settings()
	EventBus.touch_controls_changed.emit(touch_controls_enabled())

## Cambia la opacidad de los controles en pantalla y la anuncia (OnScreenControls
## la aplica al momento). `persist` = false mientras se arrastra el deslizador.
func set_touch_controls_opacity(value: float, persist: bool = true) -> void:
	ui_touch_controls_opacity = clampf(value, TOUCH_OPACITY_MIN, TOUCH_OPACITY_MAX)
	if persist:
		save_user_settings()
	EventBus.touch_controls_opacity_changed.emit(ui_touch_controls_opacity)

# ── Pantalla completa ──

## Pone la ventana en el modo que marque ui_fullscreen. Sin senales: se usa
## tambien en _ready(), cuando EventBus todavia no existe.
## En movil no hay ventana que elegir: siempre pantalla completa (inmersiva en
## Android). "Ventana" alli significa enseñar las barras del sistema encima del
## juego, y es lo que pasaba con la preferencia por defecto (false).
func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wanted := _wanted_window_mode(ui_fullscreen, OS.has_feature("mobile"))
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)

## Modo de ventana que corresponde a la preferencia en esta plataforma.
static func _wanted_window_mode(fullscreen: bool, mobile: bool) -> DisplayServer.WindowMode:
	if mobile or fullscreen:
		return DisplayServer.WINDOW_MODE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED

## Cambia a pantalla completa (o vuelve a ventana), lo guarda y lo anuncia.
func set_fullscreen(enabled: bool) -> void:
	if ui_fullscreen == enabled and not _window_mode_mismatched(enabled):
		return
	ui_fullscreen = enabled
	_apply_window_mode()
	save_user_settings()
	EventBus.fullscreen_changed.emit(ui_fullscreen)

## Cambia el idioma, lo guarda y lo anuncia. Un idioma sin tabla o el mismo que
## ya estaba no hace nada (ni guarda ni avisa): asi un clic repetido no recarga.
func set_locale(locale: String) -> void:
	if not Tr.LOCALES.has(locale) or locale == ui_locale:
		return
	ui_locale = locale
	Tr.set_locale(locale)
	save_user_settings()
	EventBus.locale_changed.emit(locale)

func toggle_fullscreen() -> void:
	set_fullscreen(not ui_fullscreen)

## True si la ventana no esta en el modo que dice la preferencia (p.ej. el
## usuario salio de pantalla completa con el gestor de ventanas).
func _window_mode_mismatched(enabled: bool) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return DisplayServer.window_get_mode() != _wanted_window_mode(enabled, OS.has_feature("mobile"))

## Seconds to cross-fade between music tracks (e.g. on era change).
var audio_music_fade := 1.5

## Number of pooled voices for overlapping one-shot SFX.
var audio_sfx_voices := 8

# ── Economy ──

var demolish_refund_ratio := 0.5
var max_offline_seconds := 28800.0

# ── Autosave ──
## Segundos REALES entre guardados periodicos. No pasa por get_duration(): es
## una red contra cierres inesperados, no parte del ritmo del juego, y dev_mode
## no debe convertirlo en un guardado por segundo.
var autosave_interval := 60.0
## Ventana en la que una rafaga de eventos (fin de pelea + Diezmo + fin de
## expedicion llegan en el mismo instante) se funde en un solo guardado.
var autosave_debounce := 0.5

# ── Market Config ──

var market_base_prices := {
	"wood": 3,
	"steel": 8,
	"oil": 12,
}

var market_spread := 0.3
var market_volatility := 0.15
var market_tick_interval := 60.0
var market_price_sensitivity := 0.02
var market_min_price_mult := 0.5
var market_max_price_mult := 2.5
var market_mean_reversion := 0.05

# ── Era Config ──

var era_names := {
	1: "ERA_FRONTIER",
	2: "ERA_INDUSTRIAL",
	3: "ERA_PETROLEUM",
}

# ── Milestone Definitions ──

var milestone_definitions := [
	{"id": "first_sawmill", "name": "MILE_PIONEER", "era": 1},
	{"id": "first_gold_mine", "name": "MILE_PROSPECTOR", "era": 1},
	{"id": "first_warehouse", "name": "MILE_STOCKPILER", "era": 1},
	{"id": "era_2", "name": "MILE_INDUSTRIALIST", "era": 2},
	{"id": "era_3", "name": "MILE_OIL_BARON", "era": 3},
	{"id": "market_10_trades", "name": "MILE_MERCHANT", "era": 0},
	{"id": "military_ready", "name": "MILE_COMMANDER", "era": 0},
	{"id": "hq_built", "name": "MILE_GENERAL", "era": 3},
	# hq_max ya no gana: convoca la Auditoria Final. El nombre decia "Victoria".
	{"id": "hq_max", "name": "MILE_AUDIT", "era": 3},
]

# ── Tech Tree Config ──

## Bonuses applied by researched techs (modified at runtime)
var tech_production_bonus := 0.0       # added to production multiplier
var tech_consumption_reduction := 0.0  # subtracted from consumption per pop
var tech_build_speed_bonus := 0.0      # subtracted from build times

## 15 techs across 3 branches, 5 tiers each
var tech_definitions := [
	# ── Industrial Branch (production & efficiency) ──
	{"id": "ind_1", "branch": "industrial", "tier": 1, "name": "TECH_IND_1",
	 "cost": {"gold": 150, "wood": 80}, "duration": 30.0, "requires": [],
	 "bonus": {"production_mult": 0.1}},
	{"id": "ind_2", "branch": "industrial", "tier": 2, "name": "TECH_IND_2",
	 "cost": {"gold": 300, "steel": 100}, "duration": 45.0, "requires": ["ind_1"],
	 "bonus": {"storage_bonus": 200}},
	{"id": "ind_3", "branch": "industrial", "tier": 3, "name": "TECH_IND_3",
	 "cost": {"gold": 500, "steel": 200, "wood": 100}, "duration": 60.0, "requires": ["ind_2"],
	 "bonus": {"production_mult": 0.15}},
	{"id": "ind_4", "branch": "industrial", "tier": 4, "name": "TECH_IND_4",
	 "cost": {"gold": 800, "steel": 300, "oil": 100}, "duration": 90.0, "requires": ["ind_3"],
	 "bonus": {"consumption_reduction": 0.3}},
	{"id": "ind_5", "branch": "industrial", "tier": 5, "name": "TECH_IND_5",
	 "cost": {"gold": 1200, "steel": 500, "oil": 200}, "duration": 120.0, "requires": ["ind_4"],
	 "bonus": {"production_mult": 0.25}},

	# ── Military Branch (defense & combat prep) ──
	{"id": "mil_1", "branch": "military", "tier": 1, "name": "TECH_MIL_1",
	 "cost": {"gold": 200, "steel": 50}, "duration": 30.0, "requires": [],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_2", "branch": "military", "tier": 2, "name": "TECH_MIL_2",
	 "cost": {"gold": 350, "steel": 150}, "duration": 45.0, "requires": ["mil_1"],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_3", "branch": "military", "tier": 3, "name": "TECH_MIL_3",
	 "cost": {"gold": 600, "steel": 250, "wood": 100}, "duration": 60.0, "requires": ["mil_2"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_4", "branch": "military", "tier": 4, "name": "TECH_MIL_4",
	 "cost": {"gold": 900, "steel": 400, "oil": 150}, "duration": 90.0, "requires": ["mil_3"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_5", "branch": "military", "tier": 5, "name": "TECH_MIL_5",
	 "cost": {"gold": 1500, "steel": 600, "oil": 300}, "duration": 120.0, "requires": ["mil_4"],
	 "bonus": {"morale_bonus": 3}},

	# ── Logistics Branch (market, storage, speed) ──
	{"id": "log_1", "branch": "logistics", "tier": 1, "name": "TECH_LOG_1",
	 "cost": {"gold": 120, "wood": 60}, "duration": 25.0, "requires": [],
	 "bonus": {"market_spread_reduction": 0.05}},
	{"id": "log_2", "branch": "logistics", "tier": 2, "name": "TECH_LOG_2",
	 "cost": {"gold": 250, "wood": 120, "steel": 50}, "duration": 40.0, "requires": ["log_1"],
	 "bonus": {"storage_bonus": 300}},
	{"id": "log_3", "branch": "logistics", "tier": 3, "name": "TECH_LOG_3",
	 "cost": {"gold": 450, "steel": 150, "wood": 80}, "duration": 55.0, "requires": ["log_2"],
	 "bonus": {"build_speed": 0.15}},
	{"id": "log_4", "branch": "logistics", "tier": 4, "name": "TECH_LOG_4",
	 "cost": {"gold": 700, "steel": 250, "oil": 100}, "duration": 80.0, "requires": ["log_3"],
	 "bonus": {"market_spread_reduction": 0.08}},
	{"id": "log_5", "branch": "logistics", "tier": 5, "name": "TECH_LOG_5",
	 "cost": {"gold": 1100, "steel": 400, "oil": 250}, "duration": 110.0, "requires": ["log_4"],
	 "bonus": {"storage_bonus": 500, "build_speed": 0.2}},
]

# ── Duration Helpers ──

func get_duration(base: float) -> float:
	if dev_mode:
		return maxf(base * dev_time_scale, 1.0)
	return base * time_multiplier

func get_build_time(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 2.0
	var speed_reduction := maxf(0.0, 1.0 - tech_build_speed_bonus)
	return base * time_multiplier * speed_reduction

func get_production_interval(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 4.0
	return base * time_multiplier

func get_upgrade_duration(level: int) -> float:
	return get_duration(upgrade_base_duration * level)

# ── Upgrade Helpers ──

func get_upgrade_cost(data: BuildingData, to_level: int) -> Dictionary:
	if to_level < 1 or to_level > max_building_level:
		return {}
	# HQ has special override costs
	if data.id == "headquarters" and hq_upgrade_costs.has(to_level):
		var hq_cost_raw: Dictionary = hq_upgrade_costs[to_level]
		var cost := {}
		for res_name in hq_cost_raw:
			var type := ResourceManager.name_to_type(res_name)
			if type != -1:
				cost[type] = hq_cost_raw[res_name]
		return cost
	var mult: float = upgrade_cost_multiplier[to_level - 1]
	var cost := {}
	var base: Dictionary = data.get_cost()
	for type in base:
		cost[type] = int(base[type] * mult)
	return cost

func get_production_multiplier(level: int) -> float:
	if level < 1 or level > max_building_level:
		return 1.0
	return upgrade_production_multiplier[level - 1]

# ── Process/Mining with duration already scaled ──

func get_processes_for(building_id: String) -> Array:
	var procs: Array = building_processes.get(building_id, [])
	var result: Array = []
	for proc in procs:
		var copy: Dictionary = proc.duplicate()
		copy["duration"] = get_duration(proc["duration"])
		result.append(copy)
	return result

func get_mining_info(deposit_id: String) -> Dictionary:
	var data: Dictionary = mining_data.get(deposit_id, {})
	if data.is_empty():
		return {}
	var copy: Dictionary = data.duplicate()
	copy["duration"] = get_duration(data["duration"])
	return copy

func get_deposit_max_uses(deposit_id: String) -> int:
	return deposit_max_uses.get(deposit_id, 3)

# ── Building Limit Helpers ──

func get_building_limit(building_id: String) -> int:
	if GameMode.all_unlocked():
		return -1  # Sandbox: sin tope por tipo (ver docs/20-modos-de-juego.md).
	return building_limits.get(building_id, -1)

func get_prerequisites(building_id: String) -> Array:
	if GameMode.all_unlocked():
		return []
	return building_prerequisites.get(building_id, [])

# ══════════════════════════════════════════════════════════════════════
# ── Army / Units (management → combat bridge) ──
# ══════════════════════════════════════════════════════════════════════
# Units are trained at Barracks, cost resources + time, consume gold upkeep,
# and contribute to Military Power. Combat (planned) will consume this army.

## Unit definitions. `era` gates availability; `power` feeds the Military Power
## score; `upkeep_gold` is deducted per upkeep tick; `train_time` in seconds.
var unit_types := {
	"infantry": {
		"name": "UNIT_INFANTRY",
		"tier": 1,
		"era": 1,
		"cost": {"gold": 40, "wood": 20},
		"train_time": 20.0,
		"upkeep_gold": 1,
		"power": 10,
	},
	"artillery": {
		"name": "UNIT_ARTILLERY",
		"tier": 2,
		"era": 2,
		"cost": {"gold": 80, "steel": 30},
		"train_time": 35.0,
		"upkeep_gold": 2,
		"power": 28,
	},
	"vehicle": {
		"name": "UNIT_VEHICLE",
		"tier": 3,
		"era": 3,
		"cost": {"gold": 140, "steel": 60, "oil": 30},
		"train_time": 55.0,
		"upkeep_gold": 4,
		"power": 65,
	},
}

## Army capacity: you may hold a few units even with no barracks; each barracks
## raises the ceiling. Bigger base = larger, stronger army.
var army_base_capacity := 3
var army_capacity_per_barracks := 8
## Seconds between upkeep deductions (scaled by dev_mode like other durations).
var army_upkeep_interval := 30.0

func get_unit_def(unit_id: String) -> Dictionary:
	return unit_types.get(unit_id, {})

func get_unit_ids() -> Array:
	return unit_types.keys()

func get_army_capacity(barracks_count: int) -> int:
	return army_base_capacity + army_capacity_per_barracks * maxi(0, barracks_count)

func get_army_upkeep_interval() -> float:
	return get_duration(army_upkeep_interval)

# ══════════════════════════════════════════════════════════════════════
# ── Combat (PVE expeditions) ──
# ══════════════════════════════════════════════════════════════════════
# The army trained above is spent here. Kept deliberately small: an 8x8 board
# with up to 6 units per side stays readable on a phone and resolves in minutes.

## Board and party limits.
var combat_board_size := Vector2i(8, 8)
var combat_deploy_cap := 6
## Rounds before the encounter is force-resolved by total HP (FR-015).
var combat_turn_limit := 20
## Seconds between enemy AI actions, so the player can follow what happened.
var combat_ai_step_delay := 0.45

## Per-unit combat stats, parallel to `unit_types`. `min_range` keeps artillery
## from firing at adjacent targets, which is what makes positioning matter.
##
## Los HP son lo unico que fija la DURACION de un encuentro: el dano es
## `atk - def` y no lleva dados, asi que las rondas salen de dividir vida entre
## golpe. Con los 30/22/60 originales un encuentro se resolvia en 3-5 rondas,
## poco mas de un minuto de reloj; x3.3 lo deja en 8-12 rondas, que es la
## ventana de 3-5 minutos que pide el diseno. `atk` y `def` no se tocan: son la
## relacion que hace que la artilleria pegue y el vehiculo aguante, y ademas la
## IA de objetivos esta fijada sobre esos numeros en `tests/combat/test_combat_ai.gd`.
## Medido en `tools/balance_probe.gd`; tablas en `docs/16-balance-combate.md`.
var combat_unit_stats := {
	"infantry":  {"hp": 100, "atk": 8,  "def": 2, "move": 3, "range": 1, "min_range": 1, "initiative": 5},
	"artillery": {"hp": 75, "atk": 14, "def": 1, "move": 1, "range": 3, "min_range": 2, "initiative": 3},
	"vehicle":   {"hp": 200, "atk": 12, "def": 5, "move": 4, "range": 1, "min_range": 1, "initiative": 4},
}

## Enemy scaling: deeper nodes and later eras field tougher rosters.
##
## Son deliberadamente pequenos. El multiplicador sube los HP **y** el ataque a
## la vez, asi que una escala `s` vale `s²` de poder de combate; y la misma
## presion engorda ademas el roster. El jugador, en cambio, no repone bajas ni
## cura entre nodos: su unico crecimiento son los drafts, que suman +2 a un stat.
## Con los 0.15/0.25/1.8 originales, ninguna expedicion se ganaba jamas — ni con
## seis unidades, ni en ninguna era (0% sobre 3.600 expediciones simuladas, la mitad de ellas bien jugadas).
var combat_enemy_scale_per_depth := 0.02
var combat_enemy_scale_per_era := 0.12
var combat_boss_multiplier := 1.15

## Expedition map shape (min, max).
var combat_map_depth := Vector2i(4, 6)
var combat_map_branching := Vector2i(2, 3)
var combat_draft_options := 3

## Node risk (0 low / 1 medium / 2 high). The same dial pushes the roster up and
## the loot with it, so taking the dangerous road is a bet, not a punishment.
## El lado del enemigo es pequeno por lo mismo que `combat_enemy_scale_per_depth`;
## el del botin no se toca, para que el riesgo siga pagando mas de lo que cuesta.
var combat_risk_enemy_scale := 0.05
var combat_risk_reward_bonus := 0.35

## Enemy roster size at depth 0, era 1, risk 0. Every pressure term grows it from
## here up to `combat_deploy_cap`.
var combat_enemy_base_slots := 2

## What one draft pick is worth. Kept modest on purpose: a run is 6-8 fights, not
## thirty, so a single pick should tilt a fight, never decide the expedition.
##
## `heal_pct` es la excepcion, y con motivo: es la UNICA forma de recuperar vida
## en toda la expedicion, y solo aparece en 3 de las 5 cartas. Al 0.3 original la
## columna llegaba al jefe con el deposito por debajo del 20%; al 0.5, un cuatro
## de era 1 bien jugado gana el 56% de las veces contra el 29% de antes. Cura a
## todos los vivos, asi que lo que sobra de un herido leve se pierde.
var combat_draft_values := {
	"atk": 2,
	"def": 2,
	"move": 1,
	"initiative": 2,
	"heal_pct": 0.5,
}
## A draft aimed at one unit type instead of the whole party hits harder, because
## it helps fewer units.
var combat_draft_focus_multiplier := 2

## Base reward per cleared encounter, scaled by node depth and risk.
var combat_reward_base := {"gold": 60, "wood": 30}

## Morale is the bridge between base and battlefield: a demoralised population
## reacts late and hits softer, and casualties cost morale back home.
##
## El rango de ataque es ancho a proposito. Es el unico modificador que solo
## tiene el jugador — el enemigo pelea siempre a 1.0 —, asi que es la palanca que
## permite que una columna pequena gane un nodo sin dejarse a nadie. Con el
## (0.85, 1.15) de antes, la moral de salida (75) daba un x1.075 que el redondeo
## se comia entero (8 x 1.075 = 8.6 -> 9, el mismo 9 que sin moral); con
## (0.60, 1.40) da x1.20, la infanteria pega 10 en vez de 9, y el mismo cuatro de
## era 1 pasa del 11% al 56% de expediciones ganadas. El rango sigue siendo
## **simetrico alrededor de 1.0**, que es la regla que fija
## `tests/combat/test_combat_rules.gd`: moral 50 no suma ni resta. El precio de
## la otra mitad es real: salir con la moral por los suelos es salir a perder,
## que es justo lo que la moral deberia significar.
var combat_morale_initiative_bonus := 2
var combat_morale_attack_range := Vector2(0.60, 1.40)
var combat_morale_on_victory := 8.0
var combat_morale_per_casualty := 3.0

func get_combat_stats(unit_id: String) -> Dictionary:
	return combat_unit_stats.get(unit_id, {})

func get_combat_ai_step_delay() -> float:
	return combat_ai_step_delay if not dev_mode else combat_ai_step_delay * 0.5

# ══════════════════════════════════════════════════════════════════════
# ── The Imperial Storm ──
# ══════════════════════════════════════════════════════════════════════
# The storm is dispatched, not rolled: it always announces itself and always runs
# the same three phases in the same order. What the dice decide is when the calm
# ends and whether a given warning amounts to anything — never how hard it hits.
# A disaster nobody can prepare for is noise; one that always means the same
# thing is arithmetic.

## How long the calm lasts. A range, not a metronome: a storm you can set your
## watch by stops being weather and becomes a spreadsheet column.
##
## Linea jugable (docs/22-linea-jugable.md): con 240-420 s la Tormenta volvia cada
## 7-10 minutos, 35-45 tormentas en una partida, y cada Diezmo es un tablero de
## 4-7 minutos: el jugador pasaba casi la mitad del tiempo peleando la misma
## pelea. Con 360-600 s son 9-18 tormentas hasta la victoria.
var storm_interval_min := 360.0
var storm_interval_max := 600.0

## The three phases are always exactly this long, in this order: Warning, Ash,
## Storm. The arrival is uncertain; what happens once it starts never is. That
## asymmetry is what makes the Warning worth acting on.
var storm_warning := 45.0
var storm_ash_duration := 60.0
var storm_duration := 60.0

## En que fase de la colonia se arma el reloj de la Tormenta. Hasta ella no
## existe: la colonia todavia no sale en el libro.
##
## EXPANSION = la primera Fundicion (era 2). Es el Acto II del diseno ("llega la
## primera Tormenta"): las chimeneas de la Fundicion son lo que se ve desde el
## mar. Armada con el primer Aserradero (antes), la primera tormenta caia en el
## minuto ~9 de una colonia que no puede tener Cuartel hasta la era 2, y el
## Diezmo se cobraba en obreros sin que el jugador hubiera podido hacer nada.
var storm_arm_phase: int = Phase.EXPANSION

## The first storm is deliberately late and gentle: it has to teach the cycle,
## not end the run. Diez minutos desde la Fundicion: lo justo para levantar el
## Cuartel y la guarnicion que la pelea. Nunca menor que storm_interval_max.
var storm_first_interval := 600.0
var storm_first_severity := 1

## One Warning in four turns out to be nothing. The player still paid to prepare,
## and the Regency loses nothing by crying wolf — which is the point.
var storm_false_alarm_chance := 0.25
## What a false alarm costs: the assessment is deferred, not forgiven. This much
## severity is saved up and rides along with the next real storm.
var storm_false_alarm_carry := 1

## Production multiplier per biting phase. The Warning does not touch production
## at all — it is the one clean window in which to decide. Neither is zero:
## watching the factories crawl is worse than watching them stop.
var storm_ash_production_multiplier := 0.5
var storm_production_multiplier := 0.15
## Live, temporary multiplier applied on top of everything else in
## ProductionManager. 1.0 means nothing is happening. Only the STORM writes to
## it, and it is responsible for putting it back.
var event_production_multiplier := 1.0
## El mismo papel para los eventos aleatorios (la plaga). Es otra variable a
## proposito: si la plaga y la tormenta escribieran la misma, la que acabara
## primero borraria el castigo de la otra. Solo RandomEventManager la toca.
var random_event_production_multiplier := 1.0
## Lo que la plaga deja producir mientras dura: la mitad.
var plague_production_multiplier := 0.5

## Todo lo pasajero junto: tormenta por evento aleatorio. Se multiplican, nunca se
## pisan. ProductionManager lee esto y no las variables sueltas.
func get_event_production_multiplier() -> float:
	return event_production_multiplier * random_event_production_multiplier
## Morale lost per tick of ash, and how often those ticks land. The Warning
## costs none of it.
##
## Por punto de severidad, con decimales (StormManager lleva la cuenta). Una
## tormenta tiene 12 tics de ceniza y 12 de tormenta (x3): se lleva 12 puntos de
## moral por punto de severidad. Severidad 1 = -12 (se nota y se recupera en dos
## minutos), 3 = -36, 5 = -60 (muerde: hacen falta decoraciones o moral alta de
## entrada). Con el 2,0 de antes una tormenta de severidad 1 se llevaba 96 puntos
## y la moral vivia en 0 a partir de la segunda.
var storm_morale_per_tick := 0.25
## The Storm bleeds this much harder than the Ash. Same clock, three times the
## bill — the difference between the two phases has to be felt, not read.
var storm_morale_storm_multiplier := 3.0
var storm_tick_interval := 5.0

## Severity climbs with the era and with how much smoke you make. The Regency does
## not spend a storm on a province that does not show up in the ledger.
var storm_severity_max := 5
var storm_severity_per_era := 1
## One extra step of severity per this many producing buildings.
var storm_buildings_per_severity := 6

## Daño por tic de tormenta, como fracción de la salud máxima del edificio. Se
## multiplica por la severidad: una tormenta fuerte deja la base en ruinas.
##
## 0,03 y no 0,06: son 24 mordiscos por tormenta y van primero a torres y
## cuarteles. A 0,06 una severidad 3 ya arruinaba las dos torres ANTES del Diezmo,
## asi que sus dotaciones no llegaban nunca al tablero que venian a defender (la
## sonda: 1-3 Diezmos echados de ~40 por partida, con guarnicion de cinco). A
## 0,03 una severidad 5 deja las torres
## tocadas (~15% de vida con dos en pie) y sin torres las arruina.
var storm_damage_per_tick := 0.03
## Cuántos edificios muerde cada tic. No los toca todos: la tormenta se siente
## caprichosa, y eso hace que proteger los importantes signifique algo.
var storm_buildings_hit_per_tick := 2

## Las torres, por fin, sirven: cada una en pie reduce el daño de la tormenta.
## Es la palanca de preparación principal y la razón de que existan.
var storm_tower_mitigation := 0.15
var storm_tower_mitigation_max := 0.6

## Reparar cuesta esta fracción del coste de construcción, escalada por el daño
## recibido. Reparar un rasguño es barato; levantar una ruina, casi construirla.
var storm_repair_cost_ratio := 0.5

## ── A quién muerde primero ──
## El daño dejó de ser un sorteo. El orden es de balance, no de código: decide
## qué se siente al perder, y eso se afina en pruebas, no reescribiendo el
## algoritmo.
##
## Primero lo que sostiene la defensa y la moral, **decoraciones incluidas**.
## Romper una estatua es el golpe más legible que tiene la Tormenta: te quita
## justo el colchón de moral con el que contabas para aguantarla, y lo hace
## antes de pasar la cuenta.
var storm_targets_defense := ["tower", "barracks"]
## Después el techo. Perder casas duele a plazo —baja el aforo, no la
## producción—, así que va en segundo escalón y no en el primero.
var storm_targets_shelter := ["house"]
## La economía (fundición, refinería, minas, aserraderos, almacenes) solo entra
## en el reparto a partir de esta severidad. Que una tormenta menor no pueda
## tocar la fundición es lo que deja margen para rehacerse; si entrara siempre,
## la primera mala racha sería terminal.
var storm_production_target_severity := 4
## La regla anti-softlock: nunca cae el **último** de estos en pie. Sin madera y
## sin oro no hay con qué reparar, y una base que no puede repararse ya perdió
## sin que nadie se lo haya dicho todavía.
var storm_essential_buildings := ["sawmill", "gold_mine"]

func get_storm_damage(severity: int, max_health: int, towers: int) -> int:
	var raw: float = float(max_health) * storm_damage_per_tick * float(maxi(1, severity)) * GameMode.storm_damage_mult()
	return maxi(1, roundi(raw * (1.0 - get_storm_mitigation(towers))))

## Cuánto absorben las torres. Con techo: ninguna cantidad de torres vuelve a la
## base inmune, porque entonces la Tormenta dejaría de ser una amenaza.
func get_storm_mitigation(towers: int) -> float:
	return clampf(storm_tower_mitigation * float(maxi(0, towers)), 0.0, storm_tower_mitigation_max)

## Share of everything in store that the Assessors take when the Tithe is not
## repelled. A percentage, not a flat sum: hoarding into a storm is the mistake.
var storm_tithe_ratio := 0.25
## How many enemies the Assessors field, before severity scaling.
var storm_tithe_base_force := 3

## ── La Cuota Mínima ──
## El porcentaje solo no bastaba: con el almacén en cero se llevaban cero, así
## que meter la bolsa en la cola convertía el Diezmo en un trámite gratis. Ahora
## hay una **deuda base** que no depende de lo que tengas, y lo que no se cubre
## con recursos se cobra en carne. Los Tasadores no se van con las manos vacías;
## esa es toda su función en el mundo.
var storm_tithe_base_debt := 60
var storm_tithe_debt_per_severity := 40
var storm_tithe_debt_per_era := 30
## Lo que salda arruinar un edificio embargado. Alto a propósito: el embargo es
## el último recurso y tiene que cerrar la cuenta rápido, no desmantelar la base
## entera por una deuda pequeña.
var storm_tithe_building_value := 80
## Lo que salda llevarse a un obrero, y lo que cuesta de moral cada uno. Vale
## menos que un edificio porque la gente es lo último que se toca y lo que más
## se nota: un Diezmo que se lleva obreros tiene que doler durante horas.
var storm_tithe_worker_value := 50
## La primera visita es un alta en el libro, no un embargo: se llevan su
## porcentaje de lo almacenado y nada mas. Con la Cuota Minima desde el primer dia,
## el Diezmo de la primera tormenta (minuto ~9, sin cuartel posible hasta la era 2)
## se cobraba en obreros a una colonia de cinco casas: la primera lección era
## perder gente sin haber podido hacer nada (docs/22-linea-jugable.md).
var storm_first_tithe_has_floor := false
var storm_tithe_worker_morale := 10

## Carrera armamentística: cada Diezmo echado engorda la escolta que vuelve.
## Ganarles hoy no te quita el problema, te lo encarece — que es exactamente lo
## que hace una contaduría cuando una provincia demuestra que puede pagar más.
## Cuenta los Diezmos REPELIDOS (StormCycle.tithes_repelled), no las tormentas:
## contando las pagadas la escolta llegaba al tope a la séptima sin que el
## jugador hubiera ganado ninguna.
var storm_assessor_growth_per_win := 0.15
## Con techo, porque el tablero también lo tiene: sin tope, la escalada dejaría
## de leerse en cuanto la escolta desbordara `combat_deploy_cap`.
var storm_assessor_growth_max := 2.0

## Cuánto se llevan de lo almacenado, escalado por severidad. Vive aquí y no en
## StormManager porque es la curva del impuesto, no el procedimiento de cobro.
func get_tithe_ratio(severity: int) -> float:
	return clampf(
		storm_tithe_ratio * (float(severity) / float(maxi(1, storm_severity_max)) + 0.5),
		0.0, 0.9)

## La deuda del día. El suelo existe para el que llega con la bolsa vacía, no
## para abaratarle el Diezmo al que llega lleno: por eso manda el mayor de los
## dos, y el que acumula sigue pagando el porcentaje de siempre.
func get_tithe_debt(severity: int, era: int, stored: int, first_visit: bool = false) -> int:
	var floor_debt: int = storm_tithe_base_debt 		+ storm_tithe_debt_per_severity * maxi(0, severity - 1) 		+ storm_tithe_debt_per_era * maxi(0, era - 1)
	if first_visit and not storm_first_tithe_has_floor:
		floor_debt = 0
	var share: int = int(float(maxi(0, stored)) * get_tithe_ratio(severity))
	return int(round(float(maxi(floor_debt, share)) * GameMode.tithe_mult()))

## El multiplicador de la escolta por Diezmos echados.
func get_assessor_escalation(tithes_repelled: int) -> float:
	return clampf(
		1.0 + storm_assessor_growth_per_win * float(maxi(0, tithes_repelled)),
		1.0, storm_assessor_growth_max)

func get_storm_first_interval() -> float:
	return get_duration(storm_first_interval) * GameMode.storm_interval_mult()

## Bounds of the calm. The roll itself belongs to StormCycle's own generator, so
## the model stays deterministic under a seed.
func get_storm_interval_min() -> float:
	return get_duration(storm_interval_min) * GameMode.storm_interval_mult()

func get_storm_interval_max() -> float:
	return get_duration(storm_interval_max) * GameMode.storm_interval_mult()

## Severidad que el modo suma a toda tormenta (Supervivencia: +1). StormCycle la
## lee aqui para seguir sin conocer a nadie mas que a GameConfig.
func get_storm_severity_bonus() -> int:
	return GameMode.storm_severity_bonus()

func get_storm_warning() -> float:
	return get_duration(storm_warning)

func get_storm_ash_duration() -> float:
	return get_duration(storm_ash_duration)

func get_storm_duration() -> float:
	return get_duration(storm_duration)

func get_storm_tick_interval() -> float:
	return get_duration(storm_tick_interval)

# ══════════════════════════════════════════════════════════════════════
# ── Las torres en el tablero del Diezmo ──
# ══════════════════════════════════════════════════════════════════════
# Mitigar el daño ya justifica construir torres. Esto justifica tenerlas **en
# pie** el día que los Tasadores se bajan del carro: una torre entera pelea.

## Qué edificio cuenta como torre. Aquí para que ningún servicio vuelva a
## escribir "tower" a mano.
var storm_tower_building_id := "tower"

## Qué pone una torre en el tablero. Una torre es una posición fija con un
## reflector y un arma pesada: ve venir al enemigo de lejos y no maniobra. Eso es
## artillería (alcance 3, movimiento 1), no infantería — una dotación de torre
## que corretea por el tablero sería una unidad que no vive en ninguna parte.
var storm_tower_garrison_unit := "artillery"
## Dotaciones por torre en pie, y su tope. El tope existe por lo mismo que el de
## la mitigación: una fila de torres no puede convertir el Diezmo en un trámite.
var storm_tower_garrison_per_tower := 1
var storm_tower_garrison_max := 2

## Cuántas dotaciones se suman a la guarnición.
##
## Van **además** del tope de despliegue, no dentro: si ocuparan hueco de la
## guarnición, construir una torre sería cambiar un soldado entrenado por una
## dotación y las torres no aportarían nada al tablero, que es justo lo que
## venían a arreglar.
##
## El límite duro no es `combat_deploy_cap` sino el tablero. La defensa nunca
## pasa de una fila del defensor (`combat_board_size.x`), así que si alguien sube
## el tope de despliegue las torres ceden el sitio antes que desbordar la zona de
## despliegue y dejar unidades fuera del tablero.
func get_tower_garrison(standing_towers: int, garrison_size: int) -> int:
	var crews: int = mini(
		maxi(0, standing_towers) * storm_tower_garrison_per_tower, storm_tower_garrison_max)
	return maxi(0, mini(crews, combat_board_size.x - maxi(0, garrison_size)))

# ── Storage Helpers ──

## Tope base de la era. Una era fuera de tabla se acota a la mas cercana en vez de
## devolver 0: un save corrupto no puede dejar al jugador sin almacen.
func get_base_storage_cap(era: int) -> int:
	var keys: Array = base_storage_cap_by_era.keys()
	keys.sort()
	var clamped: int = clampi(era, int(keys[0]), int(keys[-1]))
	return int(base_storage_cap_by_era.get(clamped, base_storage_cap_by_era[keys[0]]))

## Tope de la bolsa compartida: escala con la era y con cada almacen en pie.
func get_storage_cap(warehouse_count: int, era: int = 1) -> int:
	if GameMode.infinite_resources():
		return sandbox_storage_cap
	return get_base_storage_cap(era) + (warehouse_count * warehouse_storage_bonus) + tech_storage_bonus

# ── Deposit Helpers ──

func is_deposit_unlocked(deposit_id: String) -> bool:
	var res_name: String = deposit_resource_required.get(deposit_id, "")
	if res_name.is_empty():
		return true
	return ResourceManager.is_unlocked_by_name(res_name)

# ══════════════════════════════════════════════════════════════════════
# ── Game Phase System (gradual unlock of mechanics) ──
# ══════════════════════════════════════════════════════════════════════
#
# Phase 0 "Fundacion"   — Build freely. No consumption, no morale changes, no market, no events.
# Phase 1 "Asentamiento" — Consumption starts (gentle). Pop growth starts.
# Phase 2 "Economia"     — Market unlocks. Morale becomes dynamic.
# Phase 3 "Supervivencia"— Random events start. Decorations affect morale.
# Phase 4+ "Expansion"   — Everything active (eras 2, 3 flow naturally).

enum Phase { FOUNDATION, SETTLEMENT, ECONOMY, SURVIVAL, EXPANSION }

## Which milestone triggers each phase transition
var phase_triggers := {
	Phase.SETTLEMENT: "first_sawmill",     # Build first Sawmill
	Phase.ECONOMY: "first_gold_mine",      # Build first Gold Mine
	Phase.SURVIVAL: "first_warehouse",     # Build first Warehouse
	Phase.EXPANSION: "era_2",              # Build Foundry (era 2)
}

## Gentle early-game timers (overrides for phases 1-2)
var early_consumption_interval := 60.0     # Phase 1-2: every 60s (vs 30s normal)
var early_morale_penalty := -3             # Phase 1-2: gentle penalty (vs -8)
var early_growth_interval := 40.0          # Phase 1-2: slow growth (vs 20s)

# ══════════════════════════════════════════════════════════════════════
# ── Cancelacion, hambruna y suelo de ruina ──
# ══════════════════════════════════════════════════════════════════════
# Tres reglas que van juntas: lo que cuesta arrepentirse, lo que cuesta no pagar
# y hasta donde se puede caer. Seccion aparte a proposito, para que el balance de
# la Tormenta y el de la economia se toquen sin pisarse.

## La Tasa de Corrupcion: que fraccion de lo pagado vuelve al cancelar un
## proceso, un minado o un entrenamiento — y lo que hoy se perdia al demoler con
## algo en curso. En calma solo se pierde la comision; con la Tormenta en marcha
## los Tasadores ya vienen de camino y la fuga de capitales se cobra el doble.
## Si cancelar fuese igual de barato siempre, cancelar seria gratis.
var cancel_refund_ratio := 0.70
var cancel_refund_ratio_storm := 0.40

## Tics de impago que se perdonan antes de que empiece a morir gente y a desertar
## tropa. Dos de gracia: al tercero duele. Margen para reaccionar, no para
## ignorarlo.
var unpaid_grace_ticks := 2
## Cuanto se pierde por tic una vez agotada la gracia.
var starvation_deaths_per_tick := 1
var desertion_units_per_tick := 1
## Moral que cuestan la hambruna y la desercion, ademas del golpe que ya pega el
## impago por si mismo.
var starvation_morale_penalty := -6
var desertion_morale_penalty := -5

## El suelo de ruina: se puede caer hasta el fondo, pero no se pierde la partida.
## Siempre queda alguien para volver a empezar.
var population_floor := 1
## Por debajo de esta poblacion la gente vuelve a nacer aunque la moral este bajo
## el umbral de crecimiento: son los cinco del Nucleo, justo los obreros del
## primer aserradero y la primera mina. Es la salida del pozo (docs/22-linea-jugable.md).
var population_regrow_floor := 5

## Cuanto devuelve cancelar ahora mismo.
func get_cancel_refund_ratio() -> float:
	return cancel_refund_ratio_storm if _storm_cycle_running() else cancel_refund_ratio

## Reembolso exacto de un coste (nombre de recurso -> cantidad). Redondea hacia
## abajo, y es exactamente el numero que la UI ensena antes de confirmar: nadie
## deberia descubrir el porcentaje perdiendolo.
func get_cancel_refund(cost: Dictionary) -> Dictionary:
	var ratio := get_cancel_refund_ratio()
	var refund := {}
	for res_name in cost:
		var amount := int(floor(float(cost[res_name]) * ratio))
		if amount > 0:
			refund[res_name] = amount
	return refund

## Si un contador de tics impagados ya agoto la gracia y toca cobrarselo.
func unpaid_hurts(unpaid_ticks: int) -> bool:
	return unpaid_ticks > unpaid_grace_ticks

## UNICA lectura de la fase de la Tormenta en todo el sistema de cancelacion.
## Aislada a proposito: cuando el ciclo gane fases nuevas o cambien de nombre,
## adaptarlo es esta linea y ninguna mas. Cualquier fase que no sea calma cuenta
## como "Tormenta en marcha", el Diezmo incluido — que es cuando mas duele.
## Pregunta a StormManager en vez de comparar fases: asi una Tormenta parada para
## siempre (asedio ganado) nunca vuelve a cobrar el 60% por cancelar.
func _storm_cycle_running() -> bool:
	return StormManager.is_cycle_active()

# ══════════════════════════════════════════════════════════════════════
# ── La cola abierta y lo que la Tormenta se lleva ──
# ══════════════════════════════════════════════════════════════════════
# La cola no se bloquea en ninguna fase: vaciar el almacen en procesos y
# entrenamientos es una decision legitima del jugador, y prohibirsela seria
# quitarle la unica palanca que tiene contra el Diezmo.
#
# El agujero que se cierra aqui no era cancelar colas: era llenarlas. El coste de
# un proceso se paga al instante, asi que meter el almacen en la cola hacia que
# los Tasadores auditaran ceros — y como los procesos tienen un margen de 1,5x
# (pagas 20 de madera, recibes 35), esconder ahi no solo salvaba los recursos,
# los multiplicaba. Era la jugada dominante del juego.

## Que fraccion de lo pagado sobrevive a la Tormenta. Cero, y no un porcentaje
## bajo: con cualquier reembolso por encima de cero la cola sigue siendo una caja
## fuerte mas barata que el Diezmo, que como mucho se lleva el 37,5%. El
## escondite solo deja de compensar cuando no devuelve absolutamente nada.
var storm_queue_loss_refund_ratio := 0.0

## Solo la TORMENTA arruina la cola. La Advertencia no cuesta nada y la Ceniza es
## la ultima ventana para decidir: si la Ceniza ya destruyera, el aviso que se da
## durante la Ceniza llegaria tarde por definicion y la regla seria injusta.
func storm_phase_ruins_queue(phase: int) -> bool:
	return phase == StormCycle.Phase.STORM

## Lo que se salva de una cosa en curso cuando rompe la Tormenta. Misma forma que
## `get_cancel_refund` a proposito: perderlo por la Tormenta y cancelarlo a mano
## son la misma operacion con distinto precio, y quien la aplique puede tratarlas
## igual sin preguntar cual de las dos fue.
func get_storm_loss_refund(cost: Dictionary) -> Dictionary:
	var refund := {}
	for res_name in cost:
		var amount := int(floor(float(cost[res_name]) * storm_queue_loss_refund_ratio))
		if amount > 0:
			refund[res_name] = amount
	return refund
# ── La Auditoria Final ──
# ══════════════════════════════════════════════════════════════════════
# El Cuartel General a nivel 3 ya no gana la partida: la convoca. La Regencia
# manda su auditoria definitiva y hay que sobrevivirla — varias oleadas seguidas
# contra la misma guarnicion, sin reentrenar entre medias.
#
# Todos los numeros de aqui se leen contra una sola pregunta: cuanto ejercito hay
# que tener en pie para que la ultima oleada siga siendo ganable despues de que
# las anteriores ya se hayan cobrado lo suyo. La atricion es el balance de
# verdad; estos valores solo deciden cuanto muerde.

## Cuantas oleadas trae el asedio (minimo, maximo). Sale de la semilla, no de una
## eleccion del jugador: convocar es apostar sin saber cuanto dura la noche.
var final_audit_waves := Vector2i(3, 5)

## Cuerpos de la primera oleada, y cuantos suma cada oleada siguiente. El techo
## real lo pone `combat_deploy_cap`: el tablero sigue siendo el mismo de siempre.
var final_audit_base_slots := 3
var final_audit_slots_per_wave := 1

## Multiplicador de HP/ATK por oleada y por era. Cuando los cuerpos ya no caben
## en el tablero, esta escalada es la unica que sigue apretando.
##
## Numeros deliberadamente pequenos, y no por timidez. Medidos con
## `tools/siege_probe.gd`; la tabla entera esta en `docs/17-balance-asedio.md`.
## Con la escalada anterior (0.22 / 0.25 / 1.5) el asedio se perdia SIEMPRE en la
## oleada 2, con la guarnicion maxima que el juego permite y en las 400 semillas
## probadas: el final del juego no se podia terminar. Tres razones:
##   * El multiplicador toca **HP y ATK a la vez**, asi que el poder efectivo va
##     con el cuadrado. Un +0.22 por oleada no es un +22% de dificultad.
##   * No es la unica cuesta. Los cuerpos ya suben solos (3, 4, 5, 6), la
##     formacion ya mete canones en la segunda y blindados en la tercera, y la
##     guarnicion no se cura ni se reentrena entre oleadas. La atricion es el
##     balance de verdad; esto solo decide cuanto muerde.
##   * La era ya entraba dos veces: el 0.25 por era valia +0.50 fijo en TODA
##     oleada, porque el Cuartel General es de era 3 y el asedio no se convoca
##     antes. La oleada de apertura salia ya a x1.5.
var final_audit_scale_per_wave := 0.03
## La era casi no varia aqui —el asedio solo se convoca en la 3— asi que esto es
## en la practica el peso base de la Regencia: +0.10 en todas sus oleadas. Se
## deja viva para que una Regencia que bajase antes lo hiciera mas floja.
var final_audit_scale_per_era := 0.05
## La ultima oleada baja con todo. Es el cierre del juego, no un escalon mas.
## El salto de verdad lo da la formacion (el cierre trae DOS blindados, ver
## `FinalAudit._compose()`); esto es lo que se le suma encima. Un 5% parece poco
## y no lo es: es lo que separa un asedio de 5 oleadas ganable el 44% de las
## veces de uno que no se gana nunca.
var final_audit_last_wave_multiplier := 1.05

## Formacion: un canon por cada N cuerpos, y el blindado no aparece hasta esta
## oleada. Cada oleada tiene que verse distinta antes de verse mas grande, o el
## asedio es la misma pelea cinco veces seguidas.
var final_audit_artillery_share := 3
var final_audit_armour_wave := 2
## La unica moneda al aire del asedio: a veces, un canon de mas.
var final_audit_extra_gun_chance := 0.35

## Unidades vivas en casa que hacen falta para volver a convocar tras perder.
## Perder no acaba la partida, pero tampoco se rifa la victoria: hay que
## reconstruir el ejercito antes de que la Regencia vuelva a bajar.
var final_audit_resummon_min_units := 3

# ══════════════════════════════════════════════════════════════════════
# ── Modos de juego ──
# ══════════════════════════════════════════════════════════════════════
# La tabla de reglas por modo. Lo que un modo no lista lo hereda de "campaign",
# que es el juego de siempre. Quien lee esto es GameMode (scripts/services/
# GameMode.gd); ningun servicio mira el modo directamente. Detalle y motivos en
# docs/20-modos-de-juego.md.
var game_mode_rules := {
	"campaign": {
		"storm": true,
		"tithe": true,
		"audit_on_capstone": true,
		"capstone_wins": false,
		"victory": true,
		"resummon": true,
		"offline": true,
		"random_events": true,
		"danger_events": true,
		"infinite_resources": false,
		"all_unlocked": false,
		"sandbox_tools": false,
		"storm_interval_mult": 1.0,
		"storm_severity_bonus": 0,
		"storm_damage_mult": 1.0,
		"tithe_mult": 1.0,
		"starting_resources_mult": 1.0,
		"starting_resources": {},
		"hidden_tips": [],
	},
	# Relajado: sin Tormenta, sin Diezmo, sin asedio. Los eventos buenos siguen;
	# los danos (tormenta menor, accidente, plaga, bandidos) no salen.
	"builder": {
		"storm": false,
		"tithe": false,
		"audit_on_capstone": false,
		"capstone_wins": true,
		"danger_events": false,
		"hidden_tips": ["storm_incoming", "storm_ash", "storm_started", "tithe", "ruined", "final_audit"],
	},
	# Dificil: tormentas mas seguidas y mas duras, Diezmo mas caro, menos con que
	# empezar, nada de progreso offline y una sola Auditoria.
	"survival": {
		"resummon": false,
		"offline": false,
		"storm_interval_mult": 0.6,
		"storm_severity_bonus": 1,
		"storm_damage_mult": 1.25,
		"tithe_mult": 1.5,
		"starting_resources_mult": 0.75,
	},
	# Creativo / pruebas: todo abierto, recursos que no se acaban, la Tormenta y
	# la Auditoria solo cuando se invocan a mano. Sin victoria.
	"sandbox": {
		"storm": false,
		"audit_on_capstone": false,
		"victory": false,
		"random_events": false,
		"infinite_resources": true,
		"all_unlocked": true,
		"sandbox_tools": true,
		"starting_resources": {"gold": 20000, "steel": 20000, "oil": 20000, "wood": 20000},
		"hidden_tips": ["final_audit"],
	},
}

## Sandbox: la bolsa compartida no se llena nunca en la practica, y cada recurso
## se rellena hasta este suelo cada vez que se gasta.
var sandbox_storage_cap := 1000000
var sandbox_resource_floor := 20000
