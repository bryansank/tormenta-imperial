extends Node
## Todo lo que el juego le cuenta al jugador nuevo, en tres piezas que no se
## mezclan (docs/23-onboarding.md):
##
##   1. PROLOGO   el lore, como un expediente de la Regencia (PrologueScreen).
##                Una vez por partida, DESPUES de soltar el menu principal.
##   2. TUTORIAL  pasos guiados sobre la interfaz de verdad (TutorialPanel):
##                "Pulsa CONSTRUIR" -> "Elige el Aserradero" -> "Junto a un
##                bosque" -> "Espera la obra" -> "Una casa". Avanza cuando el
##                jugador HACE la cosa, no cuando pulsa "Siguiente".
##   3. AYUDAS    consejos la primera vez que pasa cada cosa, y globos del HUD
##                (HelperPanel). Aqui solo se decide que consejo toca y se
##                recuerda que ya se vio.
##
## Estado persistido EN LA PARTIDA, no en las preferencias: una partida nueva es
## un jugador que no sabe nada otra vez. `reset()` en los tres sitios de
## GameManager, guardado y cargado con el resto de servicios, y re-derivado al
## cargar (el paso del tutorial se deduce de lo construido, no se cree a ciegas).
##
## No conoce a ningun panel: emite en EventBus y los paneles escuchan.

const GUIDE_PENDING := "pending"
const GUIDE_ACTIVE := "active"
const GUIDE_DONE := "done"
const GUIDE_SKIPPED := "skipped"

## Los pasos del tutorial guiado, en orden. `n` es el numero que ve el jugador
## (de GUIDE_TOTAL): abrir, elegir y colocar la casa son el mismo paso 5.
const GUIDE_STEPS := {
	"open_build":    {"n": 1, "text": "GUIDE_OPEN_BUILD",    "target": "build_button"},
	"pick_sawmill":  {"n": 2, "text": "GUIDE_PICK_SAWMILL",  "target": "card:sawmill"},
	"place_sawmill": {"n": 3, "text": "GUIDE_PLACE_SAWMILL", "target": "forest"},
	"wait_sawmill":  {"n": 4, "text": "GUIDE_WAIT_SAWMILL",  "target": "building:sawmill"},
	"open_house":    {"n": 5, "text": "GUIDE_OPEN_HOUSE",    "target": "build_button"},
	"pick_house":    {"n": 5, "text": "GUIDE_PICK_HOUSE",    "target": "card:house"},
	"place_house":   {"n": 5, "text": "GUIDE_PLACE_HOUSE",   "target": ""},
	"done":          {"n": 5, "text": "GUIDE_DONE",          "target": "objective"},
}
const GUIDE_TOTAL := 5

var intro_seen: bool = false
var tips_seen: Array[String] = []
## Ayudas (globos, consejos, guias) que el jugador cerro o dejo agotarse. El
## indice de AYUDA las lista; HelperPanel no las vuelve a sacar solas.
var helps_seen: Array[String] = []
var guide_state: String = GUIDE_PENDING
## Lo que ya habia cuando empezo el tutorial. Repetirlo con una isla hecha pide
## un aserradero MAS, no dar el paso por hecho.
var guide_baseline: Dictionary = {}
## La partida ya gano su primera escaramuza (docs/15-combat.md §4). Hasta
## entonces ¿QUE HACER? la pide en cuanto hay una unidad en casa, el consejo
## `first_sortie` la senala al salir la primera unidad, y cada salida es el nodo
## facil en vez del mapa. Perderla o abandonarla no la gasta.
var first_sortie_done: bool = false

## El prologo esta pedido y espera a que no haya nada encima (menu principal,
## pausa, selector de modo).
var _prologue_pending := false
var _step := ""
var _menu_open := false
var _placing_id := ""
var _last_scan := 0.0

## Consejos contextuales: id -> claves de Tr. El disparador vive en _ready().
## Los ids son los que se guardan en la partida, asi que no se renombran a la
## ligera: un id cambiado hace que el consejo vuelva a salir en partidas viejas.
const TIPS := {
	"storm_incoming": {"title": "TUT_TIP_INCOMING_TITLE", "body": "TUT_TIP_INCOMING_BODY"},
	"storm_ash":      {"title": "TUT_TIP_ASH_TITLE",      "body": "TUT_TIP_ASH_BODY"},
	"storm_started":  {"title": "TUT_TIP_STORM_TITLE",    "body": "TUT_TIP_STORM_BODY"},
	"tithe":          {"title": "TUT_TIP_TITHE_TITLE",    "body": "HELP_TIP_TITHE_BODY"},
	"ruined":         {"title": "TUT_TIP_RUINED_TITLE",   "body": "TUT_TIP_RUINED_BODY"},
	"overflow":       {"title": "TUT_TIP_OVERFLOW_TITLE", "body": "TUT_TIP_OVERFLOW_BODY"},
	"encounter":      {"title": "TUT_TIP_BOARD_TITLE",    "body": "TUT_TIP_BOARD_BODY"},
	"barracks":       {"title": "TUT_TIP_BARRACKS_TITLE", "body": "HELP_TIP_BARRACKS_BODY"},
	"market":         {"title": "TUT_TIP_MARKET_TITLE",   "body": "TUT_TIP_MARKET_BODY"},
	"tech_tree":      {"title": "TUT_TIP_TECH_TITLE",     "body": "TUT_TIP_TECH_BODY"},
	"expedition_map": {"title": "TUT_TIP_MAP_TITLE",      "body": "TUT_TIP_MAP_BODY"},
	"first_sortie":   {"title": "TUT_TIP_FIRST_SORTIE_TITLE", "body": "TUT_TIP_FIRST_SORTIE_BODY"},
	"upkeep":         {"title": "TUT_TIP_UPKEEP_TITLE",   "body": "TUT_TIP_UPKEEP_BODY"},
	"consumption":    {"title": "TUT_TIP_CONSUMPTION_TITLE", "body": "HELP_TIP_CONSUMPTION_BODY"},
	"final_audit":    {"title": "TUT_TIP_AUDIT_TITLE",    "body": "HELP_TIP_AUDIT_BODY"},
}

## Paneles cuya primera apertura merece un consejo: nombre del nodo en Main.tscn
## -> id del consejo. Se mira el nombre y no la clase porque los paneles no
## tienen class_name, y el nombre es lo que la escena garantiza.
const PANEL_TIPS := {
	"MarketPanel": "market",
	"TechTreePanel": "tech_tree",
}

func _ready() -> void:
	# Corre en pausa: el prologo pendiente tiene que ver cuando se suelta el menu
	# principal, y eso ocurre justo al quitar la pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.game_new_started.connect(_on_game_started)
	# Tambien al cargar: una partida guardada antes de que existiera el tutorial
	# no tiene el prologo visto. Con la marca puesta no hace nada.
	EventBus.game_load_completed.connect(_on_game_started)
	EventBus.tutorial_intro_closed.connect(_on_intro_closed)

	# Disparadores de los consejos. Nombres comprobados en EventBus.gd.
	EventBus.storm_incoming.connect(_on_storm_incoming)
	EventBus.storm_ash_started.connect(_on_storm_ash_started)
	EventBus.storm_started.connect(_on_storm_started)
	EventBus.tithe_demanded.connect(_on_tithe_demanded)
	EventBus.building_ruined.connect(_on_building_ruined)
	EventBus.storage_overflow.connect(_on_storage_overflow)
	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.unit_trained.connect(_on_unit_trained)
	EventBus.army_upkeep_unpaid.connect(_on_upkeep_unpaid)
	EventBus.consumption_failed.connect(_on_consumption_failed)
	EventBus.final_audit_summoned.connect(_on_final_audit_summoned)
	UIManager.window_opened.connect(_on_window_opened)
	UIManager.window_closed.connect(_on_window_closed)

	# El tutorial guiado mira lo que el jugador hace.
	EventBus.building_selected_for_placement.connect(_on_placement_started)
	EventBus.request_move_building.connect(func(_b): _set_placing("__move__"))
	EventBus.building_placement_cancelled.connect(func(): _set_placing(""))
	EventBus.building_moved.connect(func(_f, _t): _set_placing(""))
	EventBus.construction_completed.connect(func(_n): _refresh_guide())
	EventBus.building_demolished.connect(func(_n, _c): _refresh_guide())

# ══════════════════════════════════════════════════════════════════════
# ── Prologo ──
# ══════════════════════════════════════════════════════════════════════

func _on_game_started() -> void:
	_menu_open = false
	_placing_id = ""
	if not intro_seen:
		if prologue_variant() == "none":
			# Sandbox: sin historia. Cuenta como vista para no pedirla al cargar.
			intro_seen = true
		else:
			_prologue_pending = true
	if intro_seen:
		_begin_or_resume_guide.call_deferred()

## Que version del prologo toca en este modo: "full" (Campana, Supervivencia),
## "short" (Constructor: sin Tormenta que contar) o "none" (Sandbox).
func prologue_variant() -> String:
	match GameMode.current:
		GameMode.Mode.BUILDER:
			return "short"
		GameMode.Mode.SANDBOX:
			return "none"
	return "full"

func is_prologue_pending() -> bool:
	return _prologue_pending

## Publico: vuelve a contar el prologo (el "Historia" del menu). No toca
## `intro_seen`: eso lo decide el cierre. Pedido a mano, Sandbox tambien lo ve.
func show_prologue() -> void:
	_prologue_pending = false
	EventBus.tutorial_intro_requested.emit()

## Nombre antiguo de show_prologue(), para quien ya lo llamaba (PauseMenu).
func show_intro() -> void:
	show_prologue()

## La variante que se cuenta ahora (la del modo, o la entera si el modo no
## tiene y se pidio a mano).
func requested_variant() -> String:
	var v := prologue_variant()
	return "full" if v == "none" else v

func _on_intro_closed() -> void:
	intro_seen = true
	_begin_or_resume_guide()

## El prologo pendiente sale en cuanto no hay nada encima. Nunca detras del
## menu principal (docs/07 bug 1): alli quedaba en la capa 17, congelado por la
## pausa, comiendose los toques de Ajustes.
func _process(delta: float) -> void:
	if not _prologue_pending:
		return
	_last_scan += delta
	if _last_scan < 0.1:
		return
	_last_scan = 0.0
	if can_show_prologue_now():
		_prologue_pending = false
		show_prologue()

## No hay menu principal, pausa ni dialogo delante, y existe quien lo pinte.
func can_show_prologue_now() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree.paused:
		return false
	if is_title_menu_open():
		return false
	if tree.get_nodes_in_group("prologue_screen").is_empty():
		return false
	return true

func is_title_menu_open() -> bool:
	for node in _title_menus():
		if node is CanvasLayer and (node as CanvasLayer).visible:
			if not node.has_method("is_open") or node.call("is_open"):
				return true
	return false

func _title_menus() -> Array:
	var out: Array = get_tree().get_nodes_in_group("title_menu")
	if not out.is_empty():
		return out
	var scene := get_tree().current_scene
	if scene != null:
		var t := scene.get_node_or_null("TitleMenu")
		if t != null:
			out.append(t)
	if out.is_empty():
		var any := get_tree().root.find_child("TitleMenu", true, false)
		if any != null:
			out.append(any)
	return out

# ══════════════════════════════════════════════════════════════════════
# ── Tutorial guiado ──
# ══════════════════════════════════════════════════════════════════════

func _begin_or_resume_guide() -> void:
	if guide_state == GUIDE_PENDING:
		start_guide(false)
	elif guide_state == GUIDE_ACTIVE:
		_step = ""
		_refresh_guide()

## Empieza el tutorial. `from_scratch` (Repetir tutorial) toma lo que ya hay
## como punto de partida; si no, cuenta desde cero, y una isla que ya tiene
## aserradero y casa lo da por hecho sin ensenar nada.
func start_guide(from_scratch: bool = true) -> void:
	guide_baseline = _counts() if from_scratch else {}
	guide_state = GUIDE_ACTIVE
	_step = ""
	var facts := guide_facts()
	if not from_scratch and derive_step(facts) == "done":
		# Nada que ensenar: ya se hizo todo (partida vieja sin la marca).
		guide_state = GUIDE_DONE
		EventBus.tutorial_guide_finished.emit(false)
		return
	_refresh_guide()

func skip_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	guide_state = GUIDE_SKIPPED
	_step = ""
	EventBus.tutorial_step_changed.emit("")
	EventBus.tutorial_guide_finished.emit(true)

## El panel lo llama cuando el jugador ya leyo el "listo" final (o lo cerro).
func finish_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	guide_state = GUIDE_DONE
	_step = ""
	EventBus.tutorial_step_changed.emit("")
	EventBus.tutorial_guide_finished.emit(false)

func is_guide_active() -> bool:
	return guide_state == GUIDE_ACTIVE

func current_step() -> String:
	return _step if guide_state == GUIDE_ACTIVE else ""

## El paso que toca con estos hechos. Pura, para poder probarla sin escena, y es
## la que hace el tutorial robusto: no importa en que orden haga las cosas el
## jugador ni que cargue a medias; el paso sale de lo que hay.
static func derive_step(f: Dictionary) -> String:
	var placing := String(f.get("placing", ""))
	var menu := bool(f.get("menu_open", false))
	if int(f.get("sawmills", 0)) <= 0:
		if placing == "sawmill":
			return "place_sawmill"
		return "pick_sawmill" if menu else "open_build"
	if int(f.get("sawmills_built", 0)) <= 0:
		return "wait_sawmill"
	if int(f.get("houses", 0)) <= 0:
		if placing == "house":
			return "place_house"
		return "pick_house" if menu else "open_house"
	return "done"

## Lo que hay ahora, menos lo que ya habia al empezar.
func guide_facts() -> Dictionary:
	var now := _counts()
	return {
		"sawmills": int(now["sawmills"]) - int(guide_baseline.get("sawmills", 0)),
		"sawmills_built": int(now["sawmills_built"]) - int(guide_baseline.get("sawmills_built", 0)),
		"houses": int(now["houses"]) - int(guide_baseline.get("houses", 0)),
		"menu_open": _menu_open,
		"placing": _placing_id,
	}

func _counts() -> Dictionary:
	var sawmills := 0
	var built := 0
	var houses := 0
	for info in GridManager.get_all_buildings():
		var data: Resource = info.get("data")
		if data == null:
			continue
		var id := String(data.get("id"))
		var node: Node = info.get("node")
		if id == "sawmill":
			sawmills += 1
			if node != null and not node.has_meta("under_construction"):
				built += 1
		elif id == "house":
			houses += 1
	return {"sawmills": sawmills, "sawmills_built": built, "houses": houses}

func _refresh_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	var step := derive_step(guide_facts())
	if step == _step:
		return
	_step = step
	EventBus.tutorial_step_changed.emit(step)

func _on_placement_started(data: Resource) -> void:
	_menu_open = false
	_set_placing(String(data.get("id")) if data != null else "")

func _set_placing(id: String) -> void:
	_placing_id = id
	_refresh_guide()

## Texto del paso, con la variante de dedo o de raton.
static func step_text(step_id: String) -> String:
	var e: Dictionary = GUIDE_STEPS.get(step_id, {})
	return Tr.ti(String(e.get("text", ""))) if not e.is_empty() else ""

static func step_number(step_id: String) -> int:
	return int(GUIDE_STEPS.get(step_id, {}).get("n", 0))

static func step_target(step_id: String) -> String:
	return String(GUIDE_STEPS.get(step_id, {}).get("target", ""))

# ══════════════════════════════════════════════════════════════════════
# ── Consejos y ayudas ──
# ══════════════════════════════════════════════════════════════════════

## Ensena `tip_id` si no se habia ensenado en esta partida. Se marca al emitir:
## desde ahi esta en el indice de AYUDA aunque el jugador la cierre sin leerla.
func offer_tip(tip_id: String) -> void:
	if tip_id in tips_seen:
		return
	if not TIPS.has(tip_id):
		push_warning("TutorialManager: consejo desconocido '%s'" % tip_id)
		return
	# Un consejo sobre algo que este modo no tiene (la Tormenta en Constructor)
	# no sale, y no se marca: no se ha visto.
	if not GameMode.tip_allowed(tip_id):
		return
	tips_seen.append(tip_id)
	var keys: Dictionary = TIPS[tip_id]
	EventBus.tutorial_tip_requested.emit(tip_id, Tr.t(keys["title"]), Tr.ti(keys["body"]))

func has_seen_tip(tip_id: String) -> bool:
	return tip_id in tips_seen

## Una ayuda se cerro (✕) o se agoto: vista. No vuelve a salir sola.
func mark_help_seen(help_id: String) -> void:
	if help_id != "" and not help_id in helps_seen:
		helps_seen.append(help_id)

func has_seen_help(help_id: String) -> bool:
	return help_id in helps_seen or help_id in tips_seen

## Vuelve a ensenar una ayuda concreta (desde el indice de AYUDA). Sale aunque
## las ayudas automaticas esten apagadas: la pidio el jugador.
func reopen_help(help_id: String) -> void:
	EventBus.help_reopen_requested.emit(help_id)

func _on_storm_incoming(_seconds: float) -> void:
	offer_tip("storm_incoming")

func _on_storm_ash_started() -> void:
	offer_tip("storm_ash")

func _on_storm_started(_severity: int) -> void:
	offer_tip("storm_started")

func _on_tithe_demanded(_severity: int) -> void:
	offer_tip("tithe")

func _on_building_ruined(_node: Node) -> void:
	offer_tip("ruined")

func _on_storage_overflow(_resource: String, _lost: int, _cap: int) -> void:
	offer_tip("overflow")

func _on_encounter_started(_index: int, _is_boss: bool) -> void:
	offer_tip("encounter")

func _on_building_placed(data: Resource, _cell: Vector2i) -> void:
	if data != null and String(data.get("id")) == "barracks":
		offer_tip("barracks")
	_placing_id = ""
	_refresh_guide()

func _on_expedition_started(_expedition_id: int, _node_count: int) -> void:
	# La primera escaramuza no tiene mapa: el consejo del mapa espera a la
	# primera expedicion de verdad.
	var run: Expedition = CombatManager.get_expedition()
	if run != null and run.first_sortie:
		return
	offer_tip("expedition_map")

## Ganar una salida, la que sea, cumple la primera escaramuza.
func _on_expedition_ended(result: int, _rewards: Dictionary, _casualties: Dictionary) -> void:
	if result == Expedition.RESULT_WON:
		first_sortie_done = true

func is_first_sortie_done() -> bool:
	return first_sortie_done

## El sueldo se explica con la primera unidad, antes de que falte el oro: cuando
## ya no se puede pagar, el consejo llega tarde. Si aun asi falta primero, el
## impago lo dispara (mismo id, sale una vez).
func _on_unit_trained(_unit_id: String) -> void:
	# La primera unidad va a pelear ya: primero donde (☰ MENU > ESCARAMUZAS),
	# despues lo que cobra.
	if not first_sortie_done:
		offer_tip("first_sortie")
	offer_tip("upkeep")

func _on_upkeep_unpaid(_gold_short: int) -> void:
	offer_tip("upkeep")

func _on_consumption_failed(_resource: String) -> void:
	offer_tip("consumption")

func _on_final_audit_summoned(_waves: int, _summons: int) -> void:
	offer_tip("final_audit")

func _on_window_opened(window: CanvasLayer) -> void:
	if window == null:
		return
	var wname := String(window.name)
	var tip_id: String = String(PANEL_TIPS.get(wname, ""))
	if tip_id != "":
		offer_tip(tip_id)
	if wname == "ConstructionMenu":
		_menu_open = true
		_refresh_guide()

func _on_window_closed(window: CanvasLayer) -> void:
	if window != null and String(window.name) == "ConstructionMenu":
		_menu_open = false
		_refresh_guide()

# ══════════════════════════════════════════════════════════════════════
# ── Persistencia ──
# ══════════════════════════════════════════════════════════════════════

func get_save_data() -> Dictionary:
	return {
		"intro_seen": intro_seen,
		"tips_seen": tips_seen.duplicate(),
		"helps_seen": helps_seen.duplicate(),
		"guide_state": guide_state,
		"guide_baseline": guide_baseline.duplicate(),
		"first_sortie_done": first_sortie_done,
	}

func load_save_data(data: Dictionary) -> void:
	# Se exige un bool de verdad: el JSON lo trae asi, y cualquier otra cosa (un
	# guardado editado a mano) cuenta como "no visto", que es lo inocuo. Sin el
	# `is bool`, comparar un String con true revienta en GDScript 4.
	var raw: Variant = data.get("intro_seen", false)
	intro_seen = raw is bool and raw
	tips_seen.clear()
	# El JSON devuelve Array sin tipo; se copia elemento a elemento para que
	# `tips_seen` siga siendo Array[String] y un dato raro no lo rompa.
	for tip in (data.get("tips_seen", []) if data.get("tips_seen", []) is Array else []):
		if tip is String and not tip in tips_seen:
			tips_seen.append(tip)
	helps_seen.clear()
	for h in (data.get("helps_seen", []) if data.get("helps_seen", []) is Array else []):
		if h is String and not h in helps_seen:
			helps_seen.append(h)
	# Sin la clave es un guardado de antes del tutorial guiado: quien ya habia
	# visto la intro vieja (que traia "Como se juega") no lo repite.
	var gs: Variant = data.get("guide_state", null)
	if gs is String and gs in [GUIDE_PENDING, GUIDE_ACTIVE, GUIDE_DONE, GUIDE_SKIPPED]:
		guide_state = gs
	else:
		guide_state = GUIDE_DONE if intro_seen else GUIDE_PENDING
	guide_baseline = {}
	var gb: Variant = data.get("guide_baseline", {})
	if gb is Dictionary:
		for k in ["sawmills", "sawmills_built", "houses"]:
			if gb.has(k):
				guide_baseline[k] = int(gb[k])
	# Sin la clave es un guardado de antes de la primera escaramuza: si ya vio el
	# consejo del mapa, ya salio de expedicion y no se le vuelve a pedir.
	var fs: Variant = data.get("first_sortie_done", null)
	if fs is bool:
		first_sortie_done = fs
	else:
		first_sortie_done = "expedition_map" in tips_seen
	_step = ""
	_prologue_pending = false

## Partida nueva: nadie sabe nada otra vez. Tira el estado, no notifica: el
## prologo lo pide game_new_started, que llega despues.
func reset() -> void:
	intro_seen = false
	tips_seen.clear()
	helps_seen.clear()
	guide_state = GUIDE_PENDING
	guide_baseline = {}
	first_sortie_done = false
	_prologue_pending = false
	_step = ""
	_menu_open = false
	_placing_id = ""
