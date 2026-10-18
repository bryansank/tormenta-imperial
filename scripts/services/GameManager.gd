extends Node
## Orchestrates game lifecycle: new game, save, load, clear.
## Waits for BuildingPlacer and MapGenerator to register before starting.

## Las partidas guardadas: una por archivo en user://partidas/, con su indice
## (docs/09-save-system.md). La que se juega es la activa: save_path().
const SaveSlots := preload("res://scripts/services/SaveSlots.gd")
const NewGameDialogScript := preload("res://scripts/ui/NewGameDialog.gd")
const SavesPanelScript := preload("res://scripts/ui/SavesPanel.gd")
## Una sola copia del juego abierta (InstanceGuard, docs/19 §"Una sola copia").
const InstanceGuard := preload("res://scripts/services/InstanceGuard.gd")
const InstanceDialogScript := preload("res://scripts/ui/InstanceDialog.gd")
## Cuanto se espera a que muera la otra copia tras OS.kill (pasos de 0,25 s).
const INSTANCE_KILL_WAIT_STEPS := 20
## Copias sueltas sin bloqueo (ver _settle_strays): cuantas veces se vuelve a
## mirar y cada cuanto. Tiene que pasar del cierre solo del aviso de la gemela
## (InstanceDialog.AUTO_CLOSE) con margen.
const INSTANCE_SETTLE_ROUNDS := 3
const INSTANCE_SETTLE_WAIT := 3.0
## Cuantas partidas caben en la lista.
const MAX_SAVES := SaveSlots.MAX_SLOTS
## Version del formato del guardado. La 2 (2026-09-28) trae edificios de 2x2 y
## la red de carreteras unida al Nucleo: un guardado de antes no cabe en ella
## (casas de 1x1, nada conectado), asi que se aparta y se empieza de nuevo.
const SAVE_FORMAT := 2

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
## start_new_game() aparto un id nuevo, todavia sin archivo: el proximo _begin
## empieza ahi una partida en vez de abrir la mas reciente.
var _fresh_slot_pending := false
## La proxima carga viene de una recarga interna (cambio de vista 3D/2D, de
## idioma): no es una ausencia y no lleva progresion offline.
var _skip_offline_once := false
## La partida activa nacio sola (no habia ninguna) y el jugador aun no ha
## construido nada en ella: "Nueva partida" la reutiliza en vez de dejarla
## ocupando un hueco de los cinco.
var _auto_fresh := false
## La siguiente partida la pidio el jugador (start_new_game): no nace sola.
var _chosen_new := false
## El jugador borro la partida que esta en memoria: ya no se escribe (se
## resucitaria) hasta abrir otra.
var _active_deleted := false
## Nombre y bandera elegidos en "Nueva partida" (el paso de identidad), para
## ponerlos cuando la partida nueva arranque (_new_game, tras RankManager.reset()).
## Es el unico camino: clear_save() tambien llama a reset() antes de recargar, asi
## que lo elegido no puede vivir en RankManager hasta _new_game.
var _pending_identity: Dictionary = {}
## La partida termino (Supervivencia perdida) y su guardado ya se escribio
## marcado: desde aqui es de solo lectura. Lo levanta cualquier partida nueva.
var _run_sealed := false
## Hay otra copia del juego abierta y se esta preguntando (o avisando): no se
## arranca partida hasta que se resuelva. Lo levanta _check_single_instance().
var _instance_hold := false
## Los PID que se cierran si el jugador dice SI.
var _instance_targets: Array = []

# ── Autosave ──
## Hay algo sin escribir. Se escribe al vencer el debounce, y si en ese momento
## no es seguro (pelea en juego) se queda pendiente hasta que lo sea.
var _save_pending := false
var _save_debounce_left := 0.0
var _autosave_elapsed := 0.0
## Dentro de una tanda de colocacion (los tramos del auto-road) no se guarda por
## tramo: se apunta y se guarda una vez al cerrarla (docs/26 §6.4).
var _batch_depth := 0
var _batch_dirty := false

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
		[EventBus.core_upgrade_started, 1],
		[EventBus.storm_phase_changed, 2],
		[EventBus.production_collected, 2],
		[EventBus.crop_planted, 2],
	]

func _ready() -> void:
	for trigger in _autosave_triggers():
		var sig: Signal = trigger[0]
		var cb: Callable = request_save.unbind(int(trigger[1])) if int(trigger[1]) > 0 else request_save
		sig.connect(cb)
	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.placement_batch_started.connect(_on_placement_batch_started)
	EventBus.placement_batch_finished.connect(_on_placement_batch_finished)
	EventBus.locale_changed.connect(_on_locale_changed)
	EventBus.run_ended.connect(_on_run_ended)
	# El perfil (settings.cfg, no la partida) recuerda las partidas terminadas:
	# es lo que desbloquea Gobernador en el selector.
	EventBus.victory_achieved.connect(_on_victory_for_profile)
	EventBus.final_audit_lost.connect(_on_audit_lost_for_profile)
	# Antes de que la escena registre su placer: si hay otra copia viva, la
	# partida no se carga hasta que el jugador decida.
	_check_single_instance()

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
			InstanceGuard.release()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if OS.has_feature("mobile"):
				_save_now_if_safe()

## Salir por cualquier camino (get_tree().quit() del menu incluido) suelta el
## bloqueo de una sola copia, si es de este proceso.
func _exit_tree() -> void:
	InstanceGuard.release()

# ── Una sola copia abierta ───────────────────────────────────────────

## Mira si ya hay otra copia del juego viva (InstanceGuard). Sin ninguna, se toma
## el bloqueo y se sigue como siempre. Con una, se retiene el arranque y se avisa
## (misma version) o se pregunta (otra version). En el editor, sin ventana, con
## --no-title / --multi y en movil no se mira nada.
func _check_single_instance() -> void:
	if not InstanceGuard.applies_here():
		return
	var my_pid: int = OS.get_process_id()
	var lock: Dictionary = InstanceGuard.read_lock()
	var alive: bool = _lock_is_other_alive(lock)
	var strays: Array = [] if alive else InstanceGuard.stray_pids()
	var action: int = InstanceGuard.decide(lock, alive, strays, my_pid, InstanceGuard.my_version())
	if action == InstanceGuard.Action.RUN:
		InstanceGuard.write_lock()
		return
	_instance_hold = true
	if alive:
		_open_instance_dialog.call_deferred(action, lock, true, [])
		return
	# Solo copias sueltas, sin bloqueo vivo: o es una version de antes del
	# bloqueo, o es una gemela lanzada a la vez (doble clic impaciente) que aun no
	# ha llegado aqui. Se reclama el bloqueo y se espera a que se aclare.
	InstanceGuard.write_lock()
	_settle_strays.call_deferred()

## Si el bloqueo es de otro proceso del juego que sigue vivo.
func _lock_is_other_alive(lock: Dictionary) -> bool:
	var pid: int = int(lock.get("pid", 0))
	return pid > 0 and pid != OS.get_process_id() and InstanceGuard.is_game_alive(pid, str(lock.get("exe", "")))

## Copias sueltas al arrancar. Con el bloqueo ya reclamado, se mira cada
## INSTANCE_SETTLE_WAIT segundos: si otra copia nueva se quedo el bloqueo despues,
## manda el (esta es la que sobra); si las sueltas se van (la gemela vio el bloqueo,
## aviso y salio), se arranca; si siguen tras todas las vueltas, son una version
## antigua y se pregunta.
func _settle_strays() -> void:
	var dialog: Node = _open_instance_dialog(InstanceDialogScript.CHECKING, {}, false, [])
	var my_pid: int = OS.get_process_id()
	var strays: Array = []
	for _round in INSTANCE_SETTLE_ROUNDS:
		await get_tree().create_timer(INSTANCE_SETTLE_WAIT, true).timeout
		var lock: Dictionary = InstanceGuard.read_lock()
		if _lock_is_other_alive(lock):
			_present_instance(dialog, InstanceGuard.decide(lock, true, [], my_pid, InstanceGuard.my_version()), lock, true, [])
			return
		if int(lock.get("pid", 0)) != my_pid:
			InstanceGuard.write_lock()
		strays = InstanceGuard.stray_pids()
		if strays.is_empty():
			_release_instance_hold(dialog)
			return
	_present_instance(dialog, InstanceGuard.Action.OTHER_VERSION, {}, false, strays)

func _open_instance_dialog(action: int, lock: Dictionary, alive: bool, strays: Array) -> Node:
	var dialog: Node = InstanceDialogScript.new()
	dialog.setup(InstanceDialogScript.CHECKING, "", InstanceGuard.my_version())
	dialog.declined.connect(_quit_for_instance)
	dialog.accepted.connect(_on_close_other_instance.bind(dialog))
	add_child(dialog)
	if action != InstanceDialogScript.CHECKING:
		_present_instance(dialog, action, lock, alive, strays)
	return dialog

## Pone en el dialogo el aviso (misma version) o la pregunta (otra version).
func _present_instance(dialog: Node, action: int, lock: Dictionary, alive: bool, strays: Array) -> void:
	var my_pid: int = OS.get_process_id()
	_instance_targets = InstanceGuard.targets(lock, alive, strays, my_pid)
	var other_version: String = str(lock.get("version", "")) if alive else ""
	print("[GameManager] otra copia abierta (pid %s, version '%s'): %s" % [_instance_targets, other_version,
		"aviso" if action == InstanceGuard.Action.ALREADY_OPEN else "pregunta"])
	if action == InstanceGuard.Action.ALREADY_OPEN and not _instance_targets.is_empty():
		InstanceGuard.focus_window(int(_instance_targets[0]))
	dialog.show_action(action, other_version)

## SI: se cierran las otras copias, se espera a que mueran y se arranca esta.
func _on_close_other_instance(dialog: Node) -> void:
	dialog.show_waiting()
	var exe: String = InstanceGuard.my_exe()
	var targets: Array = _instance_targets.duplicate()
	for pid in targets:
		OS.kill(int(pid))
	for _step in INSTANCE_KILL_WAIT_STEPS:
		await get_tree().create_timer(0.25, true).timeout
		var any_alive := false
		for pid in targets:
			if InstanceGuard.is_game_alive(int(pid), exe):
				any_alive = true
				break
		if not any_alive:
			InstanceGuard.write_lock()
			_release_instance_hold(dialog)
			return
	dialog.show_failed()

func _release_instance_hold(dialog: Node) -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
	_instance_targets = []
	_instance_hold = false
	_try_start()

## NO, o el aviso de "ya esta abierto": se sale sin cargar nada ni tocar el
## bloqueo de la otra.
func _quit_for_instance() -> void:
	get_tree().quit()

func _save_now_if_safe() -> void:
	if not _started or not _can_write() or not CombatManager.is_save_safe():
		return
	_save_pending = false
	_write_save()

func _can_write() -> bool:
	return not _run_sealed and not _active_deleted and is_instance_valid(_placer) and is_instance_valid(_map_gen)

# ── Partidas guardadas ───────────────────────────────────────────────

## El id de la partida activa (settings.cfg [partidas] activa).
func active_slot() -> int:
	return GameConfig.saves_active_slot

## La ruta del guardado de la partida activa. Si aun no hay ninguna activa, se
## elige ya (la mas reciente, o un id nuevo) para que siempre haya una ruta.
func save_path() -> String:
	if GameConfig.saves_active_slot <= 0:
		var recent: int = SaveSlots.most_recent_id()
		_set_active_slot(recent if recent > 0 else SaveSlots.next_id())
	return SaveSlots.path_of(GameConfig.saves_active_slot)

func _set_active_slot(id: int) -> void:
	if GameConfig.saves_active_slot == id:
		return
	GameConfig.saves_active_slot = id
	GameConfig.save_user_settings()

## Que partida abre este arranque. Un save_game.json de antes de las partidas
## pasa a ser una mas y es la que se abre. Si no, la activa; si la activa ya no
## existe, la mas reciente; si no hay ninguna, un id nuevo (partida nueva).
func _resolve_active_slot() -> void:
	var migrated: int = SaveSlots.migrate_legacy()
	if migrated > 0:
		_fresh_slot_pending = false
		_set_active_slot(migrated)
		return
	if _fresh_slot_pending:
		_fresh_slot_pending = false
		return
	if SaveSlots.exists(GameConfig.saves_active_slot):
		return
	var recent: int = SaveSlots.most_recent_id()
	_set_active_slot(recent if recent > 0 else SaveSlots.next_id())

## Las partidas para la lista, la mas reciente primero (SaveSlots.list()).
func list_saves() -> Array:
	return SaveSlots.list()

## Ya hay cinco y la activa no es una isla recien nacida que se pueda reutilizar:
## "Nueva partida" pide antes borrar una.
func is_save_list_full() -> bool:
	return SaveSlots.is_full() and not is_current_disposable()

## La partida activa nacio sola y nadie ha construido en ella: no es "una
## partida" que guardar, y la siguiente "Nueva partida" ocupa su sitio.
func is_current_disposable() -> bool:
	return _auto_fresh and _started

## La partida en memoria se borro de la lista (y ya no se escribe).
func is_active_slot_deleted() -> bool:
	return _active_deleted

## Abre la lista de partidas (SavesPanel). `make_room`: la abre "Nueva partida"
## con las cinco ocupadas, para borrar una antes de seguir.
func open_saves_list(make_room: bool = false) -> CanvasLayer:
	var panel: CanvasLayer = SavesPanelScript.new()
	panel.setup(make_room)
	add_child(panel)
	return panel

## Abre la partida `id`. Guarda antes la que se deja. Devuelve false si no se
## puede (no existe, o hay una pelea en juego: el tablero no viaja en el
## guardado).
func load_slot(id: int) -> bool:
	if not SaveSlots.exists(id):
		return false
	if _started and (CombatManager.is_board_open() or not CombatManager.is_save_safe()):
		EventBus.notification_posted.emit(Tr.t("NOTIF_VIEW_AFTER_BATTLE"), "info", UITheme.INFO)
		return false
	title_dismissed = true
	_open_slot(id)
	return true

func _open_slot(id: int) -> void:
	if _started and _can_write():
		_save_pending = false
		_write_save()
	# Volver a abrir la que ya estaba en juego no es una ausencia.
	_skip_offline_once = _started and id == active_slot() and not _active_deleted
	_fresh_slot_pending = false
	_set_active_slot(id)
	clear_save_and_reload_from(SaveSlots.read(id))

## Borra la partida `id`. Si es la que esta en memoria, deja de escribirse (y
## quien borra decide a donde ir: leave_deleted_slot). Con una pelea en juego no
## se borra la activa.
func delete_slot(id: int) -> bool:
	if id == active_slot() and _started:
		if CombatManager.is_board_open() or not CombatManager.is_save_safe():
			return false
		_active_deleted = true
		_save_pending = false
	return SaveSlots.remove(id)

## Se borro la partida en memoria: se abre la mas reciente que quede o, si no
## queda ninguna, una nueva en el modo de ahora.
func leave_deleted_slot() -> void:
	var recent: int = SaveSlots.most_recent_id()
	if recent > 0:
		_open_slot(recent)
		return
	_fresh_slot_pending = true
	_set_active_slot(SaveSlots.next_id())
	clear_save_and_reload_from({})

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
## mismo guardado de la partida activa (el formato es el mismo en las dos
## vistas). No cuenta como ausencia: no aplica progresion offline.
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
	var data: Dictionary = SaveSlots.read(active_slot()) if active_slot() > 0 else {}
	# Recarga interna: la misma partida en la otra vista, no una ausencia.
	_skip_offline_once = _started and not data.is_empty()
	clear_save_and_reload_from(data, scene_path)

func _try_start() -> void:
	if _placer == null or _map_gen == null:
		return
	if _started or _hold_start or _instance_hold:
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
	_resolve_active_slot()
	_active_deleted = false
	var chosen: bool = _chosen_new
	_chosen_new = false
	loaded_from_save = FileAccess.file_exists(save_path())
	if loaded_from_save:
		_load_game()
	else:
		_new_game()
	_skip_offline_once = false
	_auto_fresh = not loaded_from_save and not chosen
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
	GameMode.begin_run(GameMode.current, GameMode.tier)
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
	DayClock.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	RankManager.reset()
	ContractManager.reset()
	EconomyManager.reset()
	_apply_pending_identity()
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
	var file := FileAccess.open(save_path(), FileAccess.READ)
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
		# Un guardado de antes de la comida (2026-10-04) no la trae: carga con un
		# poco para que la gente no pase hambre nada mas abrir la partida.
		if data["resources"] is Dictionary and not (data["resources"] as Dictionary).has("food"):
			ResourceManager.set_amounts({"food": GameConfig.legacy_save_food})

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
				# Restore level. El JSON trae numeros en coma flotante: se pasa a
				# entero y al rango valido. Una mejora pendiente a N (upgrade_to)
				# dice que el edificio esta al menos en N-1 aunque falte la clave.
				var upgrade_to: int = int(entry.get("upgrade_to", 0))
				var level: int = clampi(int(entry.get("level", 1)), 1, GameConfig.max_building_level)
				if upgrade_to > 1:
					level = maxi(level, upgrade_to - 1)
				node.set_meta("level", level)
				if level > 1:
					ProductionManager.apply_level_visual(node, level)
				# Restaurar dano. Sin la clave, el edificio esta entero.
				if entry.has("health"):
					node.set_meta("health", int(entry["health"]))
					BuildingHealth.refresh_visual(node)
				# Register with ProductionManager (restore construction state)
				var constr_remaining := 0.0
				if entry.has("construction_remaining"):
					constr_remaining = float(entry["construction_remaining"])
				# Sin la clave (save anterior) es una construccion, como siempre fue.
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
			var dep: Node = _map_gen.spawn_deposit(entry["id"], Vector2i(entry["cell_x"], entry["cell_y"]), uses, dep_size)
			if dep != null and bool(entry.get("access_ring", false)):
				dep.set_meta("access_ring", true)
		# Una partida de antes del Muelle de pesca no trae bancos de peces: se
		# sortean ahora, con la semilla de su isla (feat/muelle-pesca).
		_map_gen.ensure_shore_deposits()

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

	# Lo acumulado en los edificios, los cultivos y sus relojes (2026-10-04). Sin
	# la clave, guardado anterior: nada que recoger y cada Granja con su cultivo
	# de serie.
	var stock_data: Variant = data.get("stockpiles", [])
	ProductionManager.load_save_data(stock_data if stock_data is Array else [])

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

	# El tablon de salidas, los planos y la rebaja del Diezmo (doc 21 §3). Sin la
	# clave, tablon vacio: las ofertas salen solas en unos segundos.
	var sorties_data: Variant = data.get("sorties", {})
	CombatManager.load_sorties_save_data(sorties_data if sorties_data is Dictionary else {})

	# Las tres campanas (feat/tres-campanas). Sin la clave, ninguna empezada; un
	# Ataque Final ya convocado o ganado en ese guardado sigue tal cual (va en
	# "progression").
	var campaigns_data: Variant = data.get("campaigns", {})
	CombatManager.load_campaigns_save_data(campaigns_data if campaigns_data is Dictionary else {})

	# Restore the storm clock. Same rule: no key means a save from before the
	# storm existed, and the cycle simply starts fresh.
	if data.has("storm"):
		StormManager.load_save_data(data["storm"])

	# La hora del dia. Sin la clave (partida anterior al ciclo) empieza de dia.
	var day_data: Variant = data.get("day", {})
	DayClock.load_save_data(day_data if day_data is Dictionary else {})

	# Que ha visto ya el jugador del tutorial. Sin la clave (partida anterior al
	# tutorial) no ha visto nada, y la intro se le ofrece al terminar la carga.
	if data.has("tutorial"):
		TutorialManager.load_save_data(data["tutorial"])

	# Rango del gobernador. Sin la clave (partida anterior al rango) es XP 0 =
	# rango 1. Va antes del recorte de la bolsa: su bono de almacen cuenta.
	var rank_data: Variant = data.get("rank", {})
	RankManager.load_save_data(rank_data if rank_data is Dictionary else {})

	# El tablon de encargos. Sin la clave (partida anterior a los encargos) es
	# un tablon nuevo, con la primera espera de cada fuente.
	var contracts_data: Variant = data.get("contracts", {})
	ContractManager.load_save_data(contracts_data if contracts_data is Dictionary else {})

	# Economia (feat/edificios-economia): el barco del contrabandista, los planos
	# menores comprados y los relojes de las Centrales y del interes. Sin la
	# clave (partida anterior) es un barco nuevo y sin planos.
	var economy_data: Variant = data.get("economy", {})
	EconomyManager.load_save_data(economy_data if economy_data is Dictionary else {})

	# La bolsa es una sola y su tope depende de la era, de los almacenes y del arbol
	# tecnologico: hasta que los tres no estan restaurados no se sabe cuanto cabe. Por
	# eso el recorte va aqui y no junto a los recursos. Una partida guardada cuando el
	# tope era por recurso puede traer mas de lo que hoy entra; se recorta en proporcion
	# antes de que la progresion offline anada nada encima.
	ResourceManager.set_era(ProgressionManager.current_era)
	ResourceManager.clamp_to_storage()

	# Progresion offline (Supervivencia no tiene: cerrar el juego no produce). Lo
	# producido espera en los edificios, que lo ensenan en el mapa: no hay parte
	# ni aviso (2026-10-12). Una recarga interna (cambio de vista o de idioma) no
	# es una ausencia y no produce nada.
	if not _skip_offline_once and data.has("saved_at") and GameMode.offline_enabled() and not GameMode.is_run_over():
		var saved_at: float = float(data["saved_at"])
		var now := Time.get_unix_time_from_system()
		var elapsed := now - saved_at
		if elapsed > 2.0:
			ProductionManager.apply_offline_progression(elapsed)
			# La obra del Nucleo tambien avanza fuera (1.2, feat/nucleo-y-planos).
			ProgressionManager.apply_offline_core(elapsed)
	_skip_offline_once = false

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
	var backup: String = backup_unreadable_save("v1")
	loaded_from_save = false
	_new_game()
	EventBus.notification_posted.emit(Tr.t("MSG_SAVE_OLD_FORMAT"), "notice", UITheme.INFO)
	if not backup.is_empty():
		print("GameManager: guardado viejo apartado en ", backup)

## Copia el guardado ilegible de la partida activa a
## user://partidas/partida_<id>.<kind>-<fecha>.json ("corrupt", o "v1" para uno
## de formato viejo) y devuelve la ruta, o "" si no habia nada que copiar.
func backup_unreadable_save(kind: String = "corrupt") -> String:
	var source: String = save_path()
	if not FileAccess.file_exists(source):
		return ""
	var path_fmt: String = SaveSlots.backup_fmt(active_slot(), kind)
	var t: Dictionary = Time.get_datetime_dict_from_system()
	var stamp: String = "%04d%02d%02d-%02d%02d%02d" % [
		int(t["year"]), int(t["month"]), int(t["day"]),
		int(t["hour"]), int(t["minute"]), int(t["second"])]
	var path: String = path_fmt % stamp
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = path_fmt % ("%s-%d" % [stamp, n])
	if DirAccess.copy_absolute(source, path) != OK:
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

	# Lo que espera a ser recogido en cada edificio, y los cultivos
	data["stockpiles"] = ProductionManager.get_save_data()

	# Tech tree
	data["tech_tree"] = TechTreeManager.get_save_data()

	# Army
	data["army"] = ArmyManager.get_save_data()
	data["expedition"] = CombatManager.get_save_data()
	data["sorties"] = CombatManager.get_sorties_save_data()
	data["campaigns"] = CombatManager.get_campaigns_save_data()
	data["storm"] = StormManager.get_save_data()
	data["day"] = DayClock.get_save_data()
	data["tutorial"] = TutorialManager.get_save_data()
	data["game_mode"] = GameMode.get_save_data()
	data["rank"] = RankManager.get_save_data()
	data["contracts"] = ContractManager.get_save_data()
	data["economy"] = EconomyManager.get_save_data()

	# Camera
	if _camera and _camera.has_method("get_state"):
		data["camera"] = _camera.get_state()

	var file := FileAccess.open(save_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		SaveSlots.record(active_slot(), _summary_for_index(data))
	# La ultima escritura de una partida terminada: la que la deja marcada.
	if GameMode.is_run_over():
		_run_sealed = true

## La entrada a "Nueva partida" desde cualquier sitio de la UI. Nunca borra
## nada: la partida nueva va a su propio archivo y la que se deja se queda en la
## lista (2026-10-12). Con las cinco ocupadas abre antes la lista para borrar
## una (SavesPanel en modo `make_room`), que luego vuelve aqui.
##
## Abre el selector de modo (NewGameDialog) y devuelve el dialogo para que quien
## lo pide pueda reaccionar a `confirmed` o `canceled`. Se procesa siempre: se
## puede pedir desde el menu principal o el de pausa, con el arbol pausado, y un
## dialogo pausado no recibe clics.
func request_new_game() -> CanvasLayer:
	if is_save_list_full():
		return open_saves_list(true)
	var dialog: CanvasLayer = NewGameDialogScript.new()
	dialog.setup(GameMode.current, GameMode.tier)
	# El dialogo cuelga de este autoload, que sobrevive a la recarga: si no se
	# libera tambien al confirmar, cada "Partida nueva" deja uno huerfano.
	dialog.confirmed.connect(dialog.queue_free)
	dialog.confirmed.connect(func(): start_new_game(dialog.chosen_mode, dialog.effective_tier(), dialog.chosen_identity))
	dialog.canceled.connect(dialog.queue_free)
	# Se borro la partida en memoria para hacer sitio y luego no se empezo
	# otra: se abre la mas reciente que quede.
	dialog.canceled.connect(func():
		if _active_deleted:
			leave_deleted_slot())
	add_child(dialog)
	return dialog

## Empieza una partida nueva en `mode`, en un archivo nuevo: la de ahora se
## guarda y se queda en la lista. Con las cinco ocupadas no hace nada (la UI
## pide antes borrar una: request_new_game). La isla recien nacida que nadie ha
## tocado (is_current_disposable) no ocupa sitio: se reutiliza su hueco.
##
## `identity` ({"name", "spec"}), si llega, es el nombre y la bandera elegidos en
## el paso de identidad; se aplican al arrancar la partida nueva.
func start_new_game(mode: int, tier: int = GameMode.TIER_DEFAULT, identity: Dictionary = {}) -> void:
	if is_save_list_full():
		push_warning("GameManager: ya hay %d partidas; borra una antes de empezar otra" % SaveSlots.MAX_SLOTS)
		return
	# La que se deja, guardada con SU modo: va antes de begin_run.
	if _started and _can_write() and CombatManager.is_save_safe():
		_save_pending = false
		_write_save()
	var reuse: bool = is_current_disposable() and not _active_deleted
	GameMode.begin_run(mode, tier)
	_pending_identity = identity.duplicate(true)
	_chosen_new = true
	title_dismissed = true
	if reuse:
		clear_save()
		return
	_fresh_slot_pending = true
	_set_active_slot(SaveSlots.next_id())
	clear_save_and_reload_from({})

## Nombre y bandera de "Nueva partida" (RankManager.set_colony, con rango 1
## recien puesto). Va tras RankManager.reset(), que ya puso uno al azar: si lo
## elegido no pasa la validacion, se queda el de al azar.
func _apply_pending_identity() -> void:
	if _pending_identity.is_empty():
		return
	var identity: Dictionary = _pending_identity
	_pending_identity = {}
	var spec: Variant = identity.get("spec", {})
	RankManager.set_colony(String(identity.get("name", "")), spec if spec is Dictionary else {})

## El resumen de la partida para el indice. Nombre y bandera salen de
## RankManager (los de la partida en memoria).
func _summary_for_index(data: Dictionary) -> Dictionary:
	var summary: Dictionary = SaveSlots.summary_of(data, active_slot())
	summary["colony_name"] = RankManager.get_colony_name()
	summary["flag_spec"] = RankManager.get_flag_spec()
	summary["sealed"] = GameMode.is_run_over()
	return summary

## Tira la partida activa y empieza otra en su mismo hueco. Es la de la isla
## recien nacida que nadie toco (start_new_game) y la de las pruebas; las demas
## partidas no se tocan.
func clear_save() -> void:
	SaveSlots.remove(active_slot())
	_fresh_slot_pending = true
	# El modo es el que se eligio (start_new_game); se tira el resultado.
	GameMode.begin_run(GameMode.current, GameMode.tier)
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
	DayClock.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	RankManager.reset()
	ContractManager.reset()
	EconomyManager.reset()
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

## Escribe `save_data` en la partida activa y recarga la escena con ella.
## Lo usan CloudSaveManager, abrir otra partida de la lista y las recargas
## internas (cambio de vista y de idioma).
## `scene_path` vacio recarga la escena actual; con ruta abre esa (cambio de vista).
## Un `save_data` vacio no escribe nada: la escena nueva empieza partida.
func clear_save_and_reload_from(save_data: Dictionary, scene_path: String = "") -> void:
	if not save_data.is_empty():
		var file := FileAccess.open(save_path(), FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(save_data, "\t"))
			file.close()
	# El modo del guardado que va a cargarse, antes de los reset (leen reglas).
	# Sin guardado, la escena empieza partida nueva en el modo de ahora.
	var mode_data: Variant = save_data.get("game_mode", {})
	if save_data.is_empty():
		GameMode.begin_run(GameMode.current, GameMode.tier)
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
	DayClock.reset()
	TutorialManager.reset()
	ProductionManager.reset()
	RankManager.reset()
	ContractManager.reset()
	EconomyManager.reset()
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
	# El jugador ya construyo: la isla deja de ser "recien nacida".
	_auto_fresh = false
	if _batch_depth > 0:
		_batch_dirty = true
		return
	save_game()

func _on_placement_batch_started() -> void:
	_batch_depth += 1

## Cierra la tanda: lo que se habria guardado tramo a tramo se guarda una vez,
## en el mismo instante (sin esperar al debounce), con todos los tramos puestos.
func _on_placement_batch_finished(_count: int) -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _batch_dirty:
		_batch_dirty = false
		save_game()

func _on_building_moved(_from: Vector2i, _to: Vector2i) -> void:
	save_game()

func _on_building_renamed(_node: Node, _name: String) -> void:
	save_game()

func _on_building_demolished(_node: Node, _cell: Vector2i) -> void:
	save_game()

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
	var parsed: Dictionary = SaveSlots.read(active_slot())
	if parsed.is_empty():
		return
	# La misma partida en el idioma nuevo: no es una ausencia.
	_skip_offline_once = true
	clear_save_and_reload_from(parsed)

# ── modos-de-juego ──

## La partida termino: se escribe una ultima vez (marcada como terminada) y a
## partir de ahi el guardado es de solo lectura. Si hay una pelea sin saldar,
## queda pendiente como cualquier otro guardado y la escritura que la salda es
## la que sella.
func _on_run_ended(_result: String) -> void:
	GameConfig.record_run_finished(false)
	save_game()

## Ganar (el asedio, o el Cuartel en Constructor) termina la partida para el
## perfil; ganar una Campana, ademas, cuenta como Campana ganada.
func _on_victory_for_profile(_stats: Dictionary) -> void:
	GameConfig.record_run_finished(GameMode.current == GameMode.Mode.CAMPAIGN)

## Perder la Auditoria en la Campana tambien es llegar al final (se puede volver
## a convocar, pero la partida ya se jugo entera). En Supervivencia lo anota
## run_ended, que llega justo despues: no se cuenta dos veces.
func _on_audit_lost_for_profile(_wave: int) -> void:
	if GameMode.resummon_allowed():
		GameConfig.record_run_finished(false)

## El guardado es de una partida terminada y ya no se escribe.
func is_run_sealed() -> bool:
	return _run_sealed
