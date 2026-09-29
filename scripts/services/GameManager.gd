extends Node
## Orchestrates game lifecycle: new game, save, load, clear.
## Waits for BuildingPlacer and MapGenerator to register before starting.

const SAVE_PATH := "user://save_game.json"
const NewGameDialogScript := preload("res://scripts/ui/NewGameDialog.gd")
const CORRUPT_PATH_FMT := "user://save_game.corrupt-%s.json"
## Version del formato del guardado. La 2 (2026-09-28) trae edificios de 2x2 y
## la red de carreteras unida al Nucleo: un guardado de antes no cabe en ella
## (casas de 1x1, nada conectado), asi que se aparta y se empieza de nuevo.
const SAVE_FORMAT := 2
const OLD_FORMAT_PATH_FMT := "user://save_game.v1-%s.json"

## El parte de progreso offline se cerro. La pantalla de victoria espera a esta
## senal si el parte sigue en pantalla: las dos usan la capa 20 y no deben
## solaparse nunca.
signal offline_report_closed

var _placer: Node = null
var _map_gen: Node = null
## La camara de la vista activa: cualquier nodo con get_state()/set_state()
## (MonumentalCamera en 3D, Camera2DController en 2D). La 2D se registra; la 3D
## se sigue buscando en el viewport como siempre.
var _camera: Node = null
var _started := false
var _warehouse_count := 0
## La escena que arranca se va a ir a la otra vista (ViewRouter): no se empieza
## partida con su placer, que muere en este mismo frame.
var _hold_start := false
## True si esta sesion arranco cargando una partida guardada, false si arranco
## una nueva porque no habia archivo. El menu principal lo lee para ofrecer
## "Continuar" solo cuando habia algo que continuar: una partida nueva se guarda
## al instante, asi que mirar el archivo despues de arrancar no sirve.
var loaded_from_save := false
## El jugador ya solto el menu principal en esta sesion. Es del TitleMenu, pero
## vive aqui porque un autoload sobrevive a cualquier cambio de escena (nueva
## partida, cambio de vista 3D/2D) sin depender de que el script del menu siga
## cargado. De sesion: no se guarda ni lo limpia ningun reset().
var title_dismissed := false
## La capa del parte offline mientras esta en pantalla.
var _offline_canvas: CanvasLayer = null
## La partida termino (Supervivencia perdida) y su guardado ya se escribio
## marcado: desde aqui es de solo lectura. Lo levanta cualquier partida nueva.
var _run_sealed := false

# ── Autosave ──
## Hay algo sin escribir. Se escribe al vencer el debounce, y si en ese momento
## no es seguro (pelea en juego) se queda pendiente hasta que lo sea.
var _save_pending := false
var _save_debounce_left := 0.0
var _autosave_elapsed := 0.0

## Lo que cambia la partida sin pasar por un edificio. Cada senal con su numero
## de argumentos, para poder desatarlos y llamar a request_save() sin mas.
func _autosave_triggers() -> Array:
	return [
		[EventBus.market_trade_completed, 4],
		[EventBus.unit_training_started, 2],
		[EventBus.unit_trained, 1],
		[EventBus.unit_training_cancelled, 2],
		[EventBus.army_deserted, 2],
		[EventBus.encounter_ended, 2],
		[EventBus.tithe_resolved, 2],
		[EventBus.final_audit_summoned, 2],
		[EventBus.final_audit_wave_cleared, 2],
		[EventBus.final_audit_lost, 1],
		[EventBus.storm_halted_forever, 0],
		[EventBus.victory_achieved, 1],
		[EventBus.expedition_started, 2],
		[EventBus.expedition_node_selected, 1],
		[EventBus.draft_applied, 1],
		[EventBus.expedition_ended, 3],
		[EventBus.process_started, 2],
		[EventBus.process_completed, 2],
		[EventBus.mining_completed, 2],
		[EventBus.process_cancelled, 3],
		[EventBus.construction_completed, 1],
		[EventBus.building_upgrade_started, 2],
		[EventBus.building_upgrade_completed, 2],
		[EventBus.storm_phase_changed, 2],
	]

func _ready() -> void:
	for trigger in _autosave_triggers():
		var sig: Signal = trigger[0]
		var cb: Callable = request_save.unbind(int(trigger[1])) if int(trigger[1]) > 0 else request_save
		sig.connect(cb)
	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.locale_changed.connect(_on_locale_changed)
	EventBus.run_ended.connect(_on_run_ended)

## Pide un guardado. No escribe en el acto: espera `autosave_debounce` para que
## una rafaga de eventos del mismo instante acabe en un solo guardado.
func request_save() -> void:
	if not _started:
		return
	_save_pending = true
	_save_debounce_left = GameConfig.autosave_debounce

func has_pending_save() -> bool:
	return _save_pending

## Escribe lo pendiente si ahora se puede. Devuelve si escribio.
func flush_pending_save() -> bool:
	if not _save_pending:
		return false
	if not _can_write() or not CombatManager.is_save_safe():
		return false
	_save_pending = false
	_write_save()
	return true

func _process(delta: float) -> void:
	if not _started:
		_save_pending = false
		_autosave_elapsed = 0.0
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= GameConfig.autosave_interval:
		_autosave_elapsed = 0.0
		_save_pending = true
		_save_debounce_left = 0.0
	if _save_pending:
		_save_debounce_left -= delta
		if _save_debounce_left <= 0.0:
			flush_pending_save()

## El punto de control de cada pelea: se escribe justo cuando se abre el
## tablero, antes de que nadie mueva. Mientras dure la pelea no se guarda (ver
## CombatManager.is_save_safe), asi que si el juego se cierra a mitad, lo que
## hay en disco es este momento: la pelea se vuelve a jugar desde el principio,
## que es lo que siempre ha dicho el diseño (el tablero no se guarda).
func _on_encounter_started(_index: int, _is_boss: bool) -> void:
	if _started and _can_write():
		_write_save()

## Cerrar la ventana, o que el movil mande la app al fondo (de donde el sistema
## puede matarla sin avisar), guarda lo que haya. Con una pelea en juego no: el
## disco ya tiene el punto de control de cuando se abrio el tablero.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_now_if_safe()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if OS.has_feature("mobile"):
				_save_now_if_safe()

func _save_now_if_safe() -> void:
	if not _started or not _can_write() or not CombatManager.is_save_safe():
		return
	_save_pending = false
	_write_save()

func _can_write() -> bool:
	return not _run_sealed and is_instance_valid(_placer) and is_instance_valid(_map_gen)

func register_placer(placer: Node) -> void:
	_placer = placer
	_try_start()

func register_map_generator(map_gen: Node) -> void:
	_map_gen = map_gen
	_try_start()

## La vista 2D registra su camara (no hay Camera3D que encontrar).
func register_camera(camera: Node) -> void:
	_camera = camera

## ViewRouter: esta escena se abandona por la otra vista antes de empezar.
func hold_start() -> void:
	_hold_start = true

## La escena actual se esta abandonando por la otra vista. El menu principal lo
## mira para no abrirse (y pausar) en una escena que muere este mismo frame.
func is_start_held() -> bool:
	return _hold_start

## ViewRouter: esta escena es la buena. Suelta lo que registro la escena que se
## abandono (nodos que ya no existen) para que la nueva se registre limpia.
func release_start() -> void:
	_hold_start = false
	if not _started:
		_placer = null
		_map_gen = null
		_camera = null

## Cambia de vista (3D <-> 2D) sin perder nada: guarda, suelta los servicios
## como una carga desde la nube y abre la otra escena, que vuelve a cargar el
## mismo save_game.json (el formato es el mismo en las dos vistas).
##
## Con un tablero abierto (o una pelea sin saldar) no se cambia: el tablero no
## viaja en el guardado, igual que al cambiar de idioma. La preferencia ya quedo
## guardada y se aplica en el proximo arranque.
func switch_to_scene(scene_path: String) -> void:
	if _started and (CombatManager.is_board_open() or not CombatManager.is_save_safe()):
		EventBus.notification_posted.emit(Tr.t("NOTIF_VIEW_AFTER_BATTLE"), "info", Color(0.5, 0.7, 1.0))
		return
	if _started:
		save_game()
	var data := {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			data = json.data
	clear_save_and_reload_from(data, scene_path)

func _try_start() -> void:
	if _placer == null or _map_gen == null:
		return
	if _started or _hold_start:
		return
	_started = true
	# El placer y el mapa se registran desde su propio _ready, y en Main.tscn hay
	# trece paneles despues de ellos que todavia no escuchan. Cargar aqui mismo
	# era hablarle a nadie: expedition_resumed, draft_offered y
	# game_load_completed se perdian, y una partida guardada con un draft
	# pendiente volvia con el mapa bloqueado. Se espera a que la escena entera
	# este lista. Si ya lo esta (una escena montada a mano, un test) se arranca
	# en el acto, como siempre.
	var scene_root: Node = _scene_root_of(_map_gen)
	if scene_root != null and not scene_root.is_node_ready():
		scene_root.ready.connect(_begin, CONNECT_ONE_SHOT)
		return
	_begin()

## El nodo de la escena que cuelga directamente de la raiz del arbol.
func _scene_root_of(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	var root: Node = get_tree().root
	var current: Node = node
	while current.get_parent() != null and current.get_parent() != root:
		current = current.get_parent()
	return current

func _begin() -> void:
	# La escena pudo irse entre el registro y su ready (recarga encadenada).
	if not is_instance_valid(_placer) or not is_instance_valid(_map_gen):
		_started = false
		return
	# La vista 2D ya registro su camara (register_camera); la 3D se busca.
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	loaded_from_save = FileAccess.file_exists(SAVE_PATH)
	if loaded_from_save:
		_load_game()
	else:
		_new_game()
	if not EventBus.building_placed.is_connected(_on_building_changed):
		EventBus.building_placed.connect(_on_building_changed)
	if not EventBus.building_moved.is_connected(_on_building_moved):
		EventBus.building_moved.connect(_on_building_moved)
	if not EventBus.building_renamed.is_connected(_on_building_renamed):
		EventBus.building_renamed.connect(_on_building_renamed)
	if not EventBus.building_demolished.is_connected(_on_building_demolished):
		EventBus.building_demolished.connect(_on_building_demolished)

func _new_game() -> void:
	# El modo ya lo eligio quien pidio la partida (start_new_game); aqui solo se
	# tira el resultado de la anterior. Va primero: los reset leen sus reglas.
	GameMode.begin_run(GameMode.current)
	_run_sealed = false
	ResourceManager.reset()
	ProcessManager.reset()
	ProgressionManager.reset()
	MarketManager.reset()
	PopulationManager.reset()
	RandomEventManager.reset()
	TechTreeManager.reset()
	ArmyManager.reset()
	CombatManager.reset()
	StormManager.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	# El tamano de la rejilla y la forma de la isla se sortean aqui, con la
	# rejilla todavia vacia y antes del Nucleo: es el reset de GridManager para
	# una partida nueva (la carga lo pisa con el del guardado).
	GridManager.roll_new_map()
	# Place nucleo at center (no build time for core)
	var nucleo_data := _load_building_data("nucleo")
	if nucleo_data:
		var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
		var node: Node = _placer.place_building_at(nucleo_data, center)
		if node:
			ProductionManager.register_building(node, nucleo_data, 0.0)
			pave_core_ring(center, nucleo_data.grid_size)
	# Sandbox: el arbol entero investigado desde el primer minuto.
	if GameMode.all_unlocked():
		TechTreeManager.unlock_all()
	# Generate random deposits
	_map_gen.generate_new_map()
	save_game()
	EventBus.game_new_started.emit()

## La acera del Nucleo: una carretera en cada celda de alrededor, gratis y ya
## hecha. Es donde nace la red: todo lo demas se construye tocandola.
## El generador de mapa de la escena (3D o 2D), o null. Para las consultas de
## vetas de otros servicios (PopulationManager: sin veta, un extractor se para).
func map_generator() -> Node:
	return _map_gen if is_instance_valid(_map_gen) else null

func pave_core_ring(origin: Vector2i, size: Vector2i) -> void:
	var road := _load_building_data("road")
	if road == null or _placer == null:
		return
	for y in range(origin.y - 1, origin.y + size.y + 1):
		for x in range(origin.x - 1, origin.x + size.x + 1):
			var inside := x >= origin.x and x < origin.x + size.x and y >= origin.y and y < origin.y + size.y
			if inside:
				continue
			var node: Node = _placer.place_building_at(road, Vector2i(x, y))
			if node:
				ProductionManager.register_building(node, road, 0.0)

func _load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		_recover_from_unreadable_save()
		return
	var json := JSON.new()
	var parsed: int = json.parse(file.get_as_text())
	file.close()
	if parsed != OK or not (json.data is Dictionary):
		_recover_from_unreadable_save()
		return
	var data: Dictionary = json.data
	# Un guardado de antes de la red de carreteras no se carga: se aparta con
	# fecha y se empieza una partida nueva, avisando.
	if int(data.get("format", 1)) < SAVE_FORMAT:
		_restart_from_old_format()
		return

	# El modo primero: las cargas de los servicios leen sus reglas. Sin la clave
	# es un guardado de antes de los modos, y eso es Campana.
	var mode_data: Variant = data.get("game_mode", {})
	GameMode.load_save_data(mode_data if mode_data is Dictionary else {})

	# El tamano de la rejilla antes de poner nada: todas las celdas del guardado
	# se refieren a el. Sin la clave es un guardado de 40x40.
	var grid_data: Variant = data.get("grid", {})
	GridManager.load_save_data(grid_data if grid_data is Dictionary else {})

	# Restore resources
	if data.has("resources"):
		ResourceManager.set_amounts(data["resources"])

	# Restore buildings
	if data.has("buildings"):
		for entry in data["buildings"]:
			var building_data := _load_building_data(entry["id"])
			if building_data:
				var rot_steps: int = entry.get("rotation", 0)
				var node: Node = _placer.place_building_at(building_data, Vector2i(entry["cell_x"], entry["cell_y"]), rot_steps)
				if not node:
					continue
				if bool(entry.get("workers_off", false)):
					node.set_meta("workers_off", true)
				# Restore custom name
				if entry.has("custom_name") and entry["custom_name"] != "":
					node.set_meta("custom_name", entry["custom_name"])
					var label: Node = node.get_node_or_null("NameLabel")
					if label and (label is Label3D or label is Label):
						label.text = entry["custom_name"]
				# Restore level
				var level: int = entry.get("level", 1)
				node.set_meta("level", level)
				if level > 1:
					var mesh_inst := node.get_child(0)
					if mesh_inst is MeshInstance3D:
						var s: float = 1.0 + (level - 1) * 0.1
						mesh_inst.scale = Vector3(s, s, s)
				# Restaurar dano. Sin la clave, el edificio esta entero.
				if entry.has("health"):
					node.set_meta("health", int(entry["health"]))
					BuildingHealth.refresh_visual(node)
				# Register with ProductionManager (restore construction state)
				var constr_remaining := 0.0
				if entry.has("construction_remaining"):
					constr_remaining = float(entry["construction_remaining"])
				# Sin la clave (save anterior) es una construccion, como siempre fue.
				var upgrade_to: int = int(entry.get("upgrade_to", 0))
				ProductionManager.register_building(node, building_data, constr_remaining, upgrade_to)
				# Count warehouses
				if building_data.id == "warehouse":
					_warehouse_count += 1

	ResourceManager.set_warehouse_count(_warehouse_count)
	_warehouse_count = 0

	# Restore deposits
	if data.has("deposits"):
		for entry in data["deposits"]:
			var uses: int = entry.get("uses_remaining", -1)
			var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
			_map_gen.spawn_deposit(entry["id"], Vector2i(entry["cell_x"], entry["cell_y"]), uses, dep_size)

	# Restore camera
	if data.has("camera") and _camera and _camera.has_method("set_state"):
		_camera.set_state(data["camera"])

	# Restore progression
	if data.has("progression"):
		ProgressionManager.load_save_data(data["progression"])

	# Restore market
	if data.has("market"):
		MarketManager.load_save_data(data["market"])

	# Restore population
	if data.has("population"):
		PopulationManager.load_save_data(data["population"])

	# Restore random events
	if data.has("random_events"):
		RandomEventManager.load_save_data(data["random_events"])

	# Restore resource unlock state
	if data.has("unlocked_resources"):
		ResourceManager.set_unlock_state(data["unlocked_resources"])

	# Restore active processes
	if data.has("active_processes"):
		ProcessManager.load_save_data(data["active_processes"])

	# Restore tech tree
	if data.has("tech_tree"):
		TechTreeManager.load_save_data(data["tech_tree"])

	# Restore army
	if data.has("army"):
		ArmyManager.load_save_data(data["army"])

	# Restore expedition in progress. A save older than this feature has no key,
	# which simply means "no expedition" — nothing to migrate.
	if data.has("expedition"):
		CombatManager.load_save_data(data["expedition"])

	# Restore the storm clock. Same rule: no key means a save from before the
	# storm existed, and the cycle simply starts fresh.
	if data.has("storm"):
		StormManager.load_save_data(data["storm"])

	# Que ha visto ya el jugador del tutorial. Sin la clave (partida anterior al
	# tutorial) no ha visto nada, y la intro se le ofrece al terminar la carga.
	if data.has("tutorial"):
		TutorialManager.load_save_data(data["tutorial"])

	# La bolsa es una sola y su tope depende de la era, de los almacenes y del arbol
	# tecnologico: hasta que los tres no estan restaurados no se sabe cuanto cabe. Por
	# eso el recorte va aqui y no junto a los recursos. Una partida guardada cuando el
	# tope era por recurso puede traer mas de lo que hoy entra; se recorta en proporcion
	# antes de que la progresion offline anada nada encima.
	ResourceManager.set_era(ProgressionManager.current_era)
	ResourceManager.clamp_to_storage()

	# Apply offline progression (Supervivencia no tiene: cerrar el juego no produce)
	if data.has("saved_at") and GameMode.offline_enabled() and not GameMode.is_run_over():
		var saved_at: float = float(data["saved_at"])
		var now := Time.get_unix_time_from_system()
		var elapsed := now - saved_at
		if elapsed > 2.0:
			var earnings := ProductionManager.apply_offline_progression(elapsed)
			_show_offline_report(elapsed, earnings)

	# Partidas de antes de la Auditoria Final con el Cuartel General ya al maximo:
	# sin esto no hay asedio que ganar. Va despues de todo lo demas porque la
	# guarnicion que lo defiende sale del ejercito ya cargado.
	ProgressionManager.migrate_legacy_capstone()

	# Una partida terminada se abre para verla, no para seguirla: no se vuelve a
	# escribir. La pantalla de derrota la vuelve a ensenar al terminar la carga.
	_run_sealed = GameMode.is_run_over()

	EventBus.game_load_completed.emit()

## La partida esta en marcha (placer y mapa registrados). Sin eso no hay nada
## que guardar: los menus lo preguntan antes de llamar a save_game().
func is_started() -> bool:
	return _started and _placer != null and _map_gen != null

## Un guardado que no se puede leer no se pisa en silencio: _new_game() guarda
## encima, y eso era perder la partida sin enterarse. Se aparta una copia con
## fecha y se avisa de donde quedo.
func _recover_from_unreadable_save() -> void:
	var backup: String = backup_unreadable_save()
	_new_game()
	if not backup.is_empty():
		EventBus.notification_posted.emit(
			Tr.t("MSG_SAVE_CORRUPT") % backup, "danger", UITheme.DANGER)

func _restart_from_old_format() -> void:
	var backup: String = backup_unreadable_save(OLD_FORMAT_PATH_FMT)
	loaded_from_save = false
	_new_game()
	EventBus.notification_posted.emit(Tr.t("MSG_SAVE_OLD_FORMAT"), "notice", UITheme.INFO)
	if not backup.is_empty():
		print("GameManager: guardado viejo apartado en ", backup)

## Copia el guardado ilegible a user://save_game.corrupt-<fecha>.json y devuelve
## la ruta, o "" si no habia nada que copiar.
func backup_unreadable_save(path_fmt: String = CORRUPT_PATH_FMT) -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var t: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = "%04d%02d%02d-%02d%02d%02d" % [
		int(t["year"]), int(t["month"]), int(t["day"]),
		int(t["hour"]), int(t["minute"]), int(t["second"])]
	var path: String = path_fmt % stamp
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = path_fmt % ("%s-%d" % [stamp, n])
	if DirAccess.copy_absolute(SAVE_PATH, path) != OK:
		return ""
	return path

## Guarda ya, salvo que haya una pelea en juego: entonces queda pendiente y se
## escribe en cuanto el tablero lo permita.
func save_game() -> void:
	if not _can_write():
		return
	if not CombatManager.is_save_safe():
		_save_pending = true
		return
	_save_pending = false
	_write_save()

func _write_save() -> void:
	_autosave_elapsed = 0.0
	var data := {}
	data["saved_at"] = Time.get_unix_time_from_system()
	data["format"] = SAVE_FORMAT

	# Tamano de la rejilla y semilla de la isla
	data["grid"] = GridManager.get_save_data()

	# Resources
	var res_all := ResourceManager.get_all()
	var resources := {}
	for type in res_all:
		resources[ResourceManager.get_type_name(type)] = res_all[type]
	data["resources"] = resources

	# Buildings
	data["buildings"] = _placer.get_all_placed_buildings()

	# Deposits
	data["deposits"] = _map_gen.get_all_deposits()

	# Progression
	data["progression"] = ProgressionManager.get_save_data()

	# Market
	data["market"] = MarketManager.get_save_data()

	# Resource unlock state
	data["unlocked_resources"] = ResourceManager.get_unlock_state()

	# Population
	data["population"] = PopulationManager.get_save_data()

	# Random events
	data["random_events"] = RandomEventManager.get_save_data()

	# Active processes
	data["active_processes"] = ProcessManager.get_save_data()

	# Tech tree
	data["tech_tree"] = TechTreeManager.get_save_data()

	# Army
	data["army"] = ArmyManager.get_save_data()
	data["expedition"] = CombatManager.get_save_data()
	data["storm"] = StormManager.get_save_data()
	data["tutorial"] = TutorialManager.get_save_data()
	data["game_mode"] = GameMode.get_save_data()

	# Camera
	if _camera and _camera.has_method("get_state"):
		data["camera"] = _camera.get_state()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
	# La ultima escritura de una partida terminada: la que la deja marcada.
	if GameMode.is_run_over():
		_run_sealed = true

## Asks the player to confirm before wiping the save. Every UI entry point to a
## new game must go through here: clear_save() is irreversible.
##
## Abre el selector de modo (NewGameDialog): cuatro tarjetas y, si hay una
## partida que perder, un segundo paso que lo dice antes de borrar nada.
## `ask_confirm` en false salta ese segundo paso (el menu principal sobre una
## isla recien nacida: no hay nada que perder).
##
## Devuelve el dialogo para que quien lo pide pueda reaccionar a `confirmed` o
## `canceled`. Se procesa siempre: se puede pedir desde el menu principal o el
## de pausa, con el arbol pausado, y un dialogo pausado no recibe clics.
func request_new_game(ask_confirm: bool = true) -> CanvasLayer:
	var dialog: CanvasLayer = NewGameDialogScript.new()
	dialog.setup(ask_confirm, GameMode.current)
	# El dialogo cuelga de este autoload, que sobrevive a la recarga: si no se
	# libera tambien al confirmar, cada "Partida nueva" deja uno huerfano.
	dialog.confirmed.connect(dialog.queue_free)
	dialog.confirmed.connect(func(): start_new_game(dialog.chosen_mode))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog

## Empieza una partida nueva en `mode`, borrando la actual. Irreversible: la UI
## llega aqui solo a traves de request_new_game().
func start_new_game(mode: int) -> void:
	GameMode.begin_run(mode)
	clear_save()

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	# El modo es el que se eligio (start_new_game); se tira el resultado.
	GameMode.begin_run(GameMode.current)
	_run_sealed = false
	GridManager.clear_all()
	ResourceManager.reset()
	ProcessManager.reset()
	ProgressionManager.reset()
	MarketManager.reset()
	PopulationManager.reset()
	RandomEventManager.reset()
	TechTreeManager.reset()
	ArmyManager.reset()
	CombatManager.reset()
	StormManager.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	UIManager.reset()
	_placer = null
	_map_gen = null
	_camera = null
	_started = false
	_warehouse_count = 0
	# Se puede llegar aqui desde el menu de pausa o el principal, con el arbol
	# pausado. La escena recargada heredaria la pausa y arrancaria congelada.
	get_tree().paused = false
	get_tree().reload_current_scene()

## Replaces local save with provided data and reloads the scene.
## Used by CloudSaveManager to apply cloud-downloaded saves.
## `scene_path` vacio recarga la escena actual; con ruta abre esa (cambio de vista).
## Un `save_data` vacio no escribe nada: la escena nueva empieza partida.
func clear_save_and_reload_from(save_data: Dictionary, scene_path: String = "") -> void:
	if not save_data.is_empty():
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data, "\t"))
	# El modo del guardado que va a cargarse, antes de los reset (leen reglas).
	# Sin guardado, la escena empieza partida nueva en el modo de ahora.
	var mode_data: Variant = save_data.get("game_mode", {})
	if save_data.is_empty():
		GameMode.begin_run(GameMode.current)
	else:
		GameMode.load_save_data(mode_data if mode_data is Dictionary else {})
	_run_sealed = false
	GridManager.clear_all()
	ResourceManager.reset()
	ProcessManager.reset()
	ProgressionManager.reset()
	MarketManager.reset()
	PopulationManager.reset()
	RandomEventManager.reset()
	TechTreeManager.reset()
	ArmyManager.reset()
	CombatManager.reset()
	StormManager.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	UIManager.reset()
	_placer = null
	_map_gen = null
	_camera = null
	_started = false
	_warehouse_count = 0
	# Se puede llegar aqui desde el menu de pausa o el principal, con el arbol
	# pausado. La escena recargada heredaria la pausa y arrancaria congelada.
	get_tree().paused = false
	if scene_path != "":
		get_tree().change_scene_to_file(scene_path)
	else:
		get_tree().reload_current_scene()

func _on_building_changed(_data: Resource, _cell: Vector2i) -> void:
	save_game()

func _on_building_moved(_from: Vector2i, _to: Vector2i) -> void:
	save_game()

func _on_building_renamed(_node: Node, _name: String) -> void:
	save_game()

func _on_building_demolished(_node: Node, _cell: Vector2i) -> void:
	save_game()

func _show_offline_report(elapsed: float, earnings: Dictionary) -> void:
	var has_any := false
	for res in earnings:
		if earnings[res] != 0:
			has_any = true
			break
	if not has_any:
		return

	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	_offline_canvas = canvas

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.7, 0.55, 0.15, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = Tr.t("FMT_OFFLINE_TITLE") % _format_elapsed(elapsed)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var res_names: Dictionary = {"gold": Tr.res_cap("gold"), "steel": Tr.res_cap("steel"), "oil": Tr.res_cap("oil"), "wood": Tr.res_cap("wood")}
	for res in earnings:
		if earnings[res] == 0:
			continue
		var lbl := Label.new()
		var amount: int = earnings[res]
		if amount > 0:
			lbl.text = "+%d %s" % [amount, res_names.get(res, res)]
			lbl.add_theme_color_override("font_color", GameConfig.resource_colors.get(res, Color.WHITE))
		else:
			lbl.text = "%d %s" % [amount, res_names.get(res, res)]
			lbl.add_theme_color_override("font_color", Color(0.9, 0.35, 0.3))
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)

	# Close button
	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_CLOSE")
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.7, 0.55, 0.15, 0.8)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(6)
	close_btn.add_theme_stylebox_override("normal", close_style)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.8, 0.65, 0.25, 0.9)
	close_hover.set_corner_radius_all(4)
	close_hover.set_content_margin_all(6)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	close_btn.add_theme_font_size_override("font_size", 14)
	vbox.add_child(close_btn)

	canvas.add_child(panel)

	close_btn.pressed.connect(func():
		var tw := create_tween()
		tw.tween_property(panel, "modulate:a", 0.0, 0.3)
		tw.tween_callback(canvas.queue_free)
		_offline_canvas = null
		offline_report_closed.emit()
	)

## El parte offline sigue en pantalla. Lo pregunta VictoryScreen antes de abrirse.
func is_offline_report_open() -> bool:
	return _offline_canvas != null and is_instance_valid(_offline_canvas)

func _format_elapsed(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	var h := s / 3600
	var m := (s % 3600) / 60
	return "%dh %dm" % [h, m]

func _load_building_data(id: String) -> BuildingData:
	var path := "res://data/buildings/%s.tres" % id
	if ResourceLoader.exists(path):
		return load(path) as BuildingData
	return null

# ── Cambio de idioma ──
#
# Los paneles construyen sus textos una vez, en _ready(). Rehacer a mano cada
# uno para un cambio de idioma seria una lista que se desincroniza sola; lo
# robusto es guardar, recargar la escena y dejar que todo se pinte de nuevo en el
# idioma nuevo. Es el mismo camino que ya usa la carga desde la nube.
# (El listener de locale_changed se conecta en el _ready de arriba.)

func _on_locale_changed(_locale: String) -> void:
	# Sin partida arrancada (arranque, pruebas) no hay nada que recargar.
	if not _started:
		return
	# El tablero no viaja en el guardado: recargar con uno abierto lo perderia.
	# Tampoco se recarga si no es seguro guardar (pelea sin saldar): se perderia
	# lo pendiente. El idioma ya esta puesto y guardado; se vera en la proxima carga.
	if CombatManager.is_board_open() or not CombatManager.is_save_safe():
		EventBus.notification_posted.emit(Tr.t("NOTIF_LOCALE_AFTER_BATTLE"), "info", Color(0.5, 0.7, 1.0))
		return
	# Diferido: quien emite suele ser un boton del panel de ajustes, y recargar
	# dentro de su propia senal liberaria el boton mientras aun se esta pulsando.
	reload_keeping_game.call_deferred()

## Guarda y recarga la escena con la misma partida. No es partida nueva: nada se
## pierde y no se anuncia nada.
func reload_keeping_game() -> void:
	if not _started or not CombatManager.is_save_safe():
		return
	# Una partida terminada no se escribe, pero se puede recargar tal cual esta
	# en disco (cambiar de idioma con la derrota en pantalla).
	if _can_write():
		# Escritura directa: save_game() dejaria el guardado pendiente si no fuera
		# seguro, y aqui se relee el disco justo despues.
		_save_pending = false
		_write_save()
	elif not _run_sealed:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	clear_save_and_reload_from(parsed)

# ── modos-de-juego ──

## La partida termino: se escribe una ultima vez (marcada como terminada) y a
## partir de ahi el guardado es de solo lectura. Si hay una pelea sin saldar,
## queda pendiente como cualquier otro guardado y la escritura que la salda es
## la que sella.
func _on_run_ended(_result: String) -> void:
	save_game()

## El guardado es de una partida terminada y ya no se escribe.
func is_run_sealed() -> bool:
	return _run_sealed
