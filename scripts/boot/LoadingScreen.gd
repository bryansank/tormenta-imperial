extends CanvasLayer
## La pantalla de carga del arranque (docs/19 §14): logo y titulo, una barra con
## su porcentaje y "Cargando: <etapa>", con etapas de verdad.
##
## La pone Boot.tscn (la escena principal, que no trae nada mas) en la raiz del
## arbol, fuera de la escena: asi sobrevive al cambio a Main / Main2D y sigue
## contando mientras esa escena se monta y GameManager coloca la partida.
##
## Lo que mide es real:
##   - "Preparando la isla" / "Preparando los paneles": las dependencias de la
##     escena de la vista elegida (sus scripts, que es lo que mas cuesta: se
##     compilan al cargarse), una a una con ResourceLoader.load_threaded_request,
##     y al final la escena misma.
##   - "Cargando edificios": data/buildings/*.tres con sus modelos, en paralelo.
##   - "Cargando sonidos": los clips de AudioManager, en paralelo.
##   - "Montando la colonia (n/N)": instanciar la escena y el _ready de cada hijo.
##     Es una sola llamada larga del hilo principal: entre hijo e hijo se fuerza
##     una pintada (RenderingServer.force_draw, como mucho cada FORCE_DRAW_MS) con
##     el 3D apagado, para que la barra se mueva sin pintar el mundo a medias.
##   - "Colocando edificios (n/N)": GameManager emite game_load_progress por cada
##     edificio del guardado; mismo truco de pintar.
##   - "Preparando los graficos": se vuelve a encender el 3D con la pantalla aun
##     puesta; el primer fotograma compila los shaders del mapa (la primera vez
##     en un equipo, varios segundos) y la pantalla se quita despues.
## Cada etapa pesa lo que se midio que tarda (STAGES, ms en el .exe); la barra no
## retrocede nunca.
##
## Si algo falla (un recurso que no carga, o la partida que no arranca en
## START_FAIL_MS) se queda puesta diciendo en que etapa y con que archivo, con
## Reintentar y Salir. Si una pieza tarda mas de STALL_MS lo dice y sigue.
##
## Coste: un CanvasLayer con seis controles. Cada fotograma mira el estado de
## tres cargas como mucho; el texto solo se reescribe cuando cambia.

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")

## Por encima de todo salvo el dialogo de "ya hay otra copia abierta" (100).
const LAYER := 90
const KEYART_PATH := "res://assets/branding/keyart.png"
## Entre dos pintadas forzadas dentro de una llamada larga del hilo principal.
const FORCE_DRAW_MS := 100
## Una pieza que tarda mas que esto se anuncia (sin cortar: sigue esperando).
const STALL_MS := 45000
## Escena montada y la partida sin arrancar en este tiempo (y sin el dialogo de
## otra copia abierta): algo fallo en GameManager. Se dice donde.
const START_FAIL_MS := 30000
## Fotogramas con la pantalla aun puesta tras encender el 3D (shaders del mapa).
const GRAPHICS_FRAMES := 2
const FADE_S := 0.18
const CARD_WIDTH := 560.0

## Etapas en el orden en que se anuncian, con su peso: los ms que tarda cada una
## en el .exe exportado (Windows, i5-10500H, caches calientes; docs/19 §14). La
## de colocar la partida crece con el guardado (GAME_MS_PER_BUILDING).
const STAGES := [
	{"id": "world", "key": "LOAD_STAGE_WORLD", "w": 1250.0},
	{"id": "ui", "key": "LOAD_STAGE_UI", "w": 6300.0},
	# Edificios y sonidos van en paralelo con lo anterior: casi no alargan la
	# carga, pesan poco para que la barra no salte cuando terminan.
	{"id": "buildings", "key": "LOAD_STAGE_BUILDINGS", "w": 150.0},
	{"id": "sounds", "key": "LOAD_STAGE_SOUNDS", "w": 50.0},
	{"id": "mount", "key": "LOAD_STAGE_MOUNT", "w": 900.0},
	{"id": "game", "key": "LOAD_STAGE_GAME", "w": 400.0},
	{"id": "graphics", "key": "LOAD_STAGE_GRAPHICS", "w": 700.0},
]
## Colocar un guardado: 300 ms fijos (leerlo, vetas, servicios) y 1,2 ms por
## edificio (312 edificios: 680 ms medidos).
const GAME_MS_BASE := 300.0
const GAME_MS_PER_BUILDING := 1.2
## Los consejos de debajo de la barra (LOAD_TIP_1..LOAD_TIP_N en Tr).
const TIP_COUNT := 16

## La pantalla viva (o null): para pruebas y sondas.
static var current: CanvasLayer = null

var scene_path := ""

var _weights := {}               # etapa -> peso
var _frac := {}                  # etapa -> 0..1
var _counts := {}                # etapa -> [hechos, total]
var _stage := ""                 # la que se anuncia
var _shown_pct := 0.0
var _last_text := ""

## Cadenas de carga: {"items": [[ruta, etapa]], "i", "requested", "t0", "sub", "hold"}
var _chains: Array = []
var _sounds_chain: Dictionary = {}
var _packed: PackedScene = null
var _phase := "loading"          # loading, mounting, waiting, graphics, done, failed
var _wait_t0 := 0
var _last_draw := 0
var _graphics_left := 0
var _slow_shown := false
var _restore_3d := false

var _root: Control
var _card: PanelContainer
var _stage_label: Label
var _pct_label: Label
var _bar: ProgressBar
var _hint: Label
var _error_box: VBoxContainer
var _error_label: Label
var _tip: Label
var _version: Label
var _title: Label
var _has_art := false

func _init() -> void:
	name = "LoadingScreen"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	current = self
	for s: Dictionary in STAGES:
		_weights[s["id"]] = float(s["w"])
		_frac[s["id"]] = 0.0
	_build_ui()
	get_viewport().size_changed.connect(_relayout)
	EventBus.game_load_progress.connect(_on_game_progress)
	EventBus.game_load_completed.connect(_on_game_ready)
	EventBus.game_new_started.connect(_on_game_ready)
	if scene_path == "":
		scene_path = ViewMode.scene_for(ViewMode.requested())
	_start_chains()
	_set_stage("world")
	BootTrace.mark("pantalla de carga puesta")

func _exit_tree() -> void:
	if current == self:
		current = null

# ── Cargas por hilos ─────────────────────────────────────────────────

func _start_chains() -> void:
	# La escena y sus dependencias: una a una (los scripts se compilan al
	# cargarse y no conviene compilar dos a la vez), primero el mundo, luego los
	# paneles y al final la escena misma.
	var world: Array = []
	var ui: Array = []
	for dep: String in ResourceLoader.get_dependencies(scene_path):
		var p := dep_path(dep)
		if p == "" or ResourceLoader.has_cached(p):
			continue
		if p.begins_with("res://scenes/ui/"):
			ui.append([p, "ui"])
		else:
			world.append([p, "world"])
	ui.append([scene_path, "ui"])
	_counts["world"] = [0, world.size()]
	_counts["ui"] = [0, ui.size()]
	_chains.append(_chain(world + ui))
	# Edificios y sonidos no llevan scripts nuevos: van a la vez, en otros hilos.
	var buildings: Array = []
	for file_name in BuildingData.resource_file_names(ResourceLoader.list_directory(BuildingData.DATA_DIR)):
		buildings.append([BuildingData.DATA_DIR + file_name, "buildings"])
	_counts["buildings"] = [0, buildings.size()]
	_chains.append(_chain(buildings))
	var sounds: Array = []
	for p: String in AudioManager.stream_paths():
		sounds.append([p, "sounds"])
	_counts["sounds"] = [0, sounds.size()]
	_sounds_chain = _chain(sounds)
	_chains.append(_sounds_chain)

func _chain(items: Array) -> Dictionary:
	return {"items": items, "i": 0, "requested": false, "t0": 0, "sub": 0.0, "hold": []}

## La ruta res:// de una linea de ResourceLoader.get_dependencies(), que segun
## la version viene como "res://x", "uid://..::Tipo::res://x" o solo un uid.
static func dep_path(dep: String) -> String:
	var parts := dep.split("::")
	for i in range(parts.size() - 1, -1, -1):
		if parts[i].begins_with("res://"):
			return parts[i]
	if parts.size() > 0 and parts[0].begins_with("uid://"):
		var id := ResourceUID.text_to_id(parts[0])
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return ""

## Avanza una cadena; devuelve true cuando ha terminado.
func _poll_chain(ch: Dictionary) -> bool:
	var items: Array = ch["items"]
	while int(ch["i"]) < items.size():
		var item: Array = items[int(ch["i"])]
		var path: String = item[0]
		if not bool(ch["requested"]):
			var err := ResourceLoader.load_threaded_request(path)
			if err != OK:
				_fail(item[1], path)
				return false
			ch["requested"] = true
			ch["t0"] = Time.get_ticks_msec()
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ch["sub"] = float(progress[0]) if not progress.is_empty() else 0.0
			_count_item(item[1], int(ch["i"]), items, float(ch["sub"]))
			if not _slow_shown and Time.get_ticks_msec() - int(ch["t0"]) > STALL_MS:
				_slow_shown = true
				_show_hint(Tr.t("LOAD_SLOW") % [_stage_text(item[1]), int(STALL_MS / 1000.0)])
			return false
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			_fail(item[1], path)
			return false
		var res: Resource = ResourceLoader.load_threaded_get(path)
		if res == null:
			_fail(item[1], path)
			return false
		if path == scene_path:
			_packed = res as PackedScene
		ch["hold"].append(res)
		ch["i"] = int(ch["i"]) + 1
		ch["requested"] = false
		ch["sub"] = 0.0
		_count_item(item[1], int(ch["i"]), items, 0.0)
	return true

## Cuantas piezas de `stage` van hechas en `items` hasta `index` (mas la parte de
## la que esta en marcha).
func _count_item(stage: String, index: int, items: Array, sub: float) -> void:
	var total: int = _counts[stage][1]
	var done := 0
	for k in range(mini(index, items.size())):
		if items[k][1] == stage:
			done += 1
	_counts[stage][0] = done
	var partial := sub if index < items.size() and items[index][1] == stage else 0.0
	_frac[stage] = 1.0 if total == 0 else clampf((float(done) + partial) / float(total), 0.0, 1.0)

func _process(_delta: float) -> void:
	match _phase:
		"loading":
			var all_done := true
			for ch: Dictionary in _chains:
				if not _poll_chain(ch):
					all_done = false
			if _phase != "loading":
				return
			for id in ["world", "ui", "buildings", "sounds"]:
				if _counts.has(id) and _counts[id][1] == 0:
					_frac[id] = 1.0
			_set_stage(_first_open_stage())
			if all_done:
				_mount()
		"waiting":
			if GameManager.is_started():
				return
			if GameManager.has_method("is_instance_held") and GameManager.is_instance_held():
				_wait_t0 = Time.get_ticks_msec()
				_set_stage("instance")
				return
			if Time.get_ticks_msec() - _wait_t0 > START_FAIL_MS:
				_fail(_stage, "")

func _first_open_stage() -> String:
	for s: Dictionary in STAGES:
		if float(_frac[s["id"]]) < 1.0:
			return s["id"]
	return "mount"

# ── Montar la escena ─────────────────────────────────────────────────

func _mount() -> void:
	_phase = "mounting"
	for id in ["world", "ui", "buildings", "sounds"]:
		_frac[id] = 1.0
	BootTrace.mark("cargas por hilos terminadas")
	# Los clips, ya en memoria, pasan a AudioManager antes de soltar la cadena.
	AudioManager.adopt_streams()
	_set_stage("mount")
	_draw_now()
	if _packed == null:
		_fail("ui", scene_path)
		return
	var main: Node = _packed.instantiate()
	BootTrace.mark("escena instanciada")
	if main == null:
		_fail("mount", scene_path)
		return
	_counts["mount"] = [0, main.get_child_count()]
	for child in main.get_children():
		child.ready.connect(_on_part_ready, CONNECT_ONE_SHOT)
	# Lo cargado se sujeta hasta el final (_release_chains): si se soltara ya, los
	# .tres y sus modelos saldrian de la cache antes de que CONSTRUIR los pida.
	var root := get_tree().root
	_restore_3d = not root.disable_3d
	root.disable_3d = true
	_wait_t0 = Time.get_ticks_msec()
	_phase = "waiting"
	if get_tree().has_method("change_scene_to_node"):
		get_tree().change_scene_to_node(main)
	else:
		main.free()
		get_tree().change_scene_to_packed(_packed)

func _release_chains() -> void:
	_chains.clear()
	_sounds_chain = {}
	_packed = null

func _on_part_ready() -> void:
	if _phase != "waiting":
		return
	_counts["mount"][0] = int(_counts["mount"][0]) + 1
	var total: int = maxi(1, int(_counts["mount"][1]))
	_frac["mount"] = clampf(float(_counts["mount"][0]) / float(total), 0.0, 1.0)
	_refresh()
	_maybe_draw()

func _on_game_progress(done: int, total: int) -> void:
	if _phase != "waiting":
		return
	_frac["mount"] = 1.0
	_weights["game"] = GAME_MS_BASE + GAME_MS_PER_BUILDING * float(total)
	_counts["game"] = [done, total]
	_frac["game"] = 1.0 if total <= 0 else clampf(float(done) / float(total), 0.0, 1.0)
	if _stage != "game":
		_set_stage("game")
	else:
		_refresh()
	_maybe_draw()

func _on_game_ready() -> void:
	if _phase != "waiting":
		return
	_phase = "graphics"
	_frac["mount"] = 1.0
	_frac["game"] = 1.0
	BootTrace.mark("partida colocada; se enciende el 3D")
	_set_stage("graphics")
	if not GameManager.loaded_from_save or not _shader_cache_warm():
		_show_hint(Tr.t("LOAD_HINT_GRAPHICS"))
	_draw_now()
	if _restore_3d:
		get_tree().root.disable_3d = false
	_graphics_left = GRAPHICS_FRAMES
	RenderingServer.frame_post_draw.connect(_on_graphics_frame)

## Hay shaders compilados de otra vez (user://shader_cache): la primera vez en un
## equipo es cuando el primer fotograma tarda segundos.
func _shader_cache_warm() -> bool:
	return DirAccess.dir_exists_absolute("user://shader_cache") or DirAccess.dir_exists_absolute("user://vulkan")

func _on_graphics_frame() -> void:
	_graphics_left -= 1
	_frac["graphics"] = 1.0 - float(_graphics_left) / float(GRAPHICS_FRAMES)
	_refresh()
	if _graphics_left > 0:
		return
	RenderingServer.frame_post_draw.disconnect(_on_graphics_frame)
	_release_chains()
	_finish()

func _finish() -> void:
	_phase = "done"
	BootTrace.mark("pantalla de carga fuera")
	_set_stage("menu")
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(queue_free)

# ── Pintar ───────────────────────────────────────────────────────────

## Pinta ya un fotograma (solo 2D: el 3D esta apagado mientras se monta).
func _draw_now() -> void:
	_last_draw = Time.get_ticks_msec()
	RenderingServer.force_draw(true, 0.0)

func _maybe_draw() -> void:
	if Time.get_ticks_msec() - _last_draw >= FORCE_DRAW_MS:
		_draw_now()

func _set_stage(id: String) -> void:
	if id != _stage:
		if _stage != "":
			BootTrace.mark("etapa: " + id)
		_stage = id
	_refresh()

func _stage_text(id: String) -> String:
	var key := ""
	match id:
		"game":
			key = "LOAD_STAGE_GAME" if GameManager.loaded_from_save else "LOAD_STAGE_NEW_GAME"
		"instance":
			key = "LOAD_STAGE_INSTANCE"
		"menu":
			key = "LOAD_STAGE_MENU"
		_:
			for s: Dictionary in STAGES:
				if s["id"] == id:
					key = s["key"]
	var text := Tr.t(key) if key != "" else id
	# Una partida nueva no cuenta piezas: son dos pasos, no edificios.
	if _counts.has(id) and id != "graphics" and not (id == "game" and not GameManager.loaded_from_save):
		var c: Array = _counts[id]
		if int(c[1]) > 1:
			text = Tr.t("LOAD_COUNT") % [text, mini(int(c[0]) + (0 if int(c[0]) >= int(c[1]) else 1), int(c[1])), int(c[1])]
	return text

## Porcentaje total: cada etapa pesa lo suyo. No baja nunca.
func percent() -> float:
	var total := 0.0
	var done := 0.0
	for s: Dictionary in STAGES:
		var w: float = _weights[s["id"]]
		total += w
		done += w * float(_frac[s["id"]])
	_shown_pct = maxf(_shown_pct, 100.0 * done / maxf(total, 1.0))
	return _shown_pct

func stage() -> String:
	return _stage

func _refresh() -> void:
	if _stage_label == null:
		return
	var pct := percent()
	var text := Tr.t("LOAD_LINE") % _stage_text(_stage)
	if text != _last_text:
		_last_text = text
		_stage_label.text = text
	_bar.value = pct / 100.0
	_pct_label.text = "%d %%" % int(pct)

func _show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""
	_relayout()

# ── Fallos ───────────────────────────────────────────────────────────

func _fail(stage_id: String, path: String) -> void:
	if _phase == "failed":
		return
	_phase = "failed"
	var where := _stage_text(stage_id)
	BootTrace.mark("FALLO en " + where + (" (" + path + ")" if path != "" else ""))
	push_error("[LoadingScreen] la carga fallo en '%s'%s" % [where, (": " + path) if path != "" else ""])
	if _restore_3d:
		get_tree().root.disable_3d = false
	var lines: PackedStringArray = [Tr.t("LOAD_FAILED_AT") % where]
	if path != "":
		lines.append(Tr.t("LOAD_FAILED_FILE") % path)
	lines.append(Tr.t("LOAD_FAILED_LOG") % ProjectSettings.globalize_path("user://logs/godot.log"))
	_error_label.text = "\n".join(lines)
	_stage_label.text = Tr.t("LOAD_FAILED_TITLE")
	_error_box.visible = true
	_hint.visible = false
	_tip.visible = false
	_relayout()

func _on_retry() -> void:
	# Un arranque limpio: lo que quedo a medias (autoloads incluidos) no se arrastra.
	if OS.has_feature("pc"):
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()

func _on_quit() -> void:
	get_tree().quit()

# ── Construccion ─────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = CT.c("hud", "BG")
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(base)

	# La misma ilustracion que el menu principal, para que el paso no salte.
	if ResourceLoader.exists(KEYART_PATH):
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = load(KEYART_PATH)
		_has_art = art.texture != null
		_root.add_child(art)
		var shade := ColorRect.new()
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.color = CT.c("hud", "SHADOW")
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(shade)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.add_theme_stylebox_override("panel", CT.window_style())
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)

	# El nombre ya va pintado abajo en la ilustracion; la tarjeta lo repite solo
	# cuando no se ve (sin ilustracion, o en vertical, que la recorta).
	_title = CT.label(Tr.t("LBL_TITLE_GAME"), "display", CT.text("window"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_stage_label = CT.label("", "body", CT.text("window"))
	_stage_label.name = "Stage"
	_stage_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stage_label.clip_text = true
	column.add_child(_stage_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_bar = CT.progress(0.0, CT.sem("ACCENT"), "window", 18)
	_bar.name = "Bar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_bar)
	_pct_label = CT.label("0 %", "number", CT.text("window"))
	_pct_label.name = "Percent"
	_pct_label.custom_minimum_size = Vector2(64, 0)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct_label)

	_hint = CT.para("", "window", true, "small")
	_hint.name = "Hint"
	_hint.visible = false
	column.add_child(_hint)

	# Un consejo al azar: algo util que leer mientras carga.
	_tip = CT.para(random_tip(), "window", true, "small")
	_tip.name = "Tip"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_tip)

	_error_box = VBoxContainer.new()
	_error_box.name = "Error"
	_error_box.visible = false
	_error_box.add_theme_constant_override("separation", 8)
	column.add_child(_error_box)
	_error_label = CT.para("", "window", false, "small")
	_error_box.add_child(_error_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	_error_box.add_child(buttons)
	var retry := CT.pill_button(Tr.t("LOAD_BTN_RETRY"), "next", "primary", CT.BTN_SMALL)
	retry.name = "RetryButton"
	retry.pressed.connect(_on_retry)
	buttons.add_child(retry)
	var quit := CT.pill_button(Tr.t("BTN_QUIT"), "close", "danger", CT.BTN_SMALL)
	quit.name = "QuitButton"
	quit.pressed.connect(_on_quit)
	buttons.add_child(quit)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	# La version, en la esquina de arriba a la derecha (abajo va la tarjeta, que
	# en un telefono ocupa casi todo el ancho).
	_version = CT.label(version_text(), "small", CT.text("hud", true))
	_version.name = "Version"
	_version.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.offset_left = -200.0
	_version.offset_right = -16.0
	_version.offset_top = 8.0
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_version)
	_relayout()

## Uno de los consejos LOAD_TIP_*, al azar.
static func random_tip() -> String:
	return Tr.t("LOAD_TIP_%d" % randi_range(1, TIP_COUNT))

## "0.9 beta" a partir de application/config/version ("0.9-beta").
static func version_text() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "")).replace("-", " ")

## La tarjeta centrada en lo alto, sobre el cielo de la ilustracion: abajo queda
## el nombre del juego pintado en ella. A lo ancho que quepa con 16 px de margen.
func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var width := minf(CARD_WIDTH, vp.x - 32.0)
	var portrait := vp.x < vp.y
	_title.visible = portrait or not _has_art
	# Los textos que envuelven necesitan su ancho antes de medir la tarjeta (sin
	# el, cada letra iria en su linea).
	var inner := width - 2.0 * float(CT.PAD) - 4.0
	for l: Label in [_hint, _tip, _error_label]:
		l.custom_minimum_size = Vector2(inner, 0)
	# Anclada arriba al centro: crece hacia abajo hasta lo que mida su contenido
	# (el contenedor lo recalcula solo, tambien cuando sale un aviso).
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.offset_left = -width * 0.5
	_card.offset_right = width * 0.5
	var top := clampf(vp.y * 0.12, 16.0, 90.0)
	if portrait:
		top = vp.y * 0.3
	_card.offset_top = top
	_card.offset_bottom = top
