extends Node
## Todo lo que el juego le cuenta al jugador nuevo, en tres piezas que no se
## mezclan (docs/23-onboarding.md):
##
##   1. PROLOGO   el lore, como un expediente de la Regencia (PrologueScreen).
##                Una vez por partida, DESPUES de soltar el menu principal.
##   2. TUTORIAL  pasos guiados sobre la interfaz de verdad (TutorialPanel):
##                "Pulsa CONSTRUIR" -> "Elige el Aserradero" -> "Junto a un
##                bosque" -> "Espera la obra" -> "Una casa". Avanza cuando el
##                jugador HACE la cosa, no cuando pulsa "Siguiente". No se
##                salta (2026-10-04); a cambio, ningun paso puede atascarse: lo
##                imposible se pasa de largo y lo que falta se dice.
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

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## Las METAS del tutorial guiado, en orden. Cada meta es algo que el jugador
## tiene que tener en la isla; el paso que toca sale de la primera meta sin
## cumplir (derive_step). Dos clases:
##
##   - "build": un edificio. Pasos `open` (CONSTRUIR), `pick` (su tarjeta),
##     `place` (en el mapa) y, si tiene `wait`, esperar a que acabe la obra.
##   - "fact":  algo que no es un edificio (recoger la produccion...). Se cumple
##     con TutorialManager.note_guide_fact(<fact>), que llama quien lo vea.
##     `needs` (opcional): la meta sin la que no se puede cumplir; si esa se pasa
##     de largo (imposible en esta isla), esta tambien.
##
## Recoger lo producido y la Granja (rama feat/comida-granja-recoger, 2026-10-04)
## van entre el aserradero y la casa: lo que hace un edificio se queda en el y la
## gente come comida, y las dos cosas se ensenan en el orden en que pasan al
## arrancar. La Granja no espera a su obra (se cultiva sola al terminar).
## El orden de esta lista es el orden del tutorial.
const GUIDE_GOALS := [
	{"goal": "sawmill", "kind": "build", "building": "sawmill",
		"steps": {"open": "open_build", "pick": "pick_sawmill", "place": "place_sawmill", "wait": "wait_sawmill"}},
	{"goal": "collect", "kind": "fact", "fact": "collected", "step": "collect", "needs": "sawmill"},
	{"goal": "farm", "kind": "build", "building": "farm",
		"steps": {"open": "open_farm", "pick": "pick_farm", "place": "place_farm"}},
	{"goal": "house", "kind": "build", "building": "house",
		"steps": {"open": "open_house", "pick": "pick_house", "place": "place_house"}},
]

## Los pasos, con lo que ve el jugador. `n` es el numero de "PASO n DE
## GUIDE_TOTAL": abrir, elegir y colocar la casa son el mismo paso 7.
const GUIDE_STEPS := {
	"open_build":    {"n": 1, "text": "GUIDE_OPEN_BUILD",    "target": "build_button"},
	"pick_sawmill":  {"n": 2, "text": "GUIDE_PICK_SAWMILL",  "target": "card:sawmill"},
	"place_sawmill": {"n": 3, "text": "GUIDE_PLACE_SAWMILL", "target": "forest"},
	"wait_sawmill":  {"n": 4, "text": "GUIDE_WAIT_SAWMILL",  "target": "building:sawmill"},
	"collect":       {"n": 5, "text": "GUIDE_COLLECT",       "target": "building:sawmill"},
	"open_farm":     {"n": 6, "text": "GUIDE_OPEN_FARM",     "target": "build_button"},
	"pick_farm":     {"n": 6, "text": "GUIDE_PICK_FARM",     "target": "card:farm"},
	"place_farm":    {"n": 6, "text": "GUIDE_PLACE_FARM",    "target": ""},
	"open_house":    {"n": 7, "text": "GUIDE_OPEN_HOUSE",    "target": "build_button"},
	"pick_house":    {"n": 7, "text": "GUIDE_PICK_HOUSE",    "target": "card:house"},
	"place_house":   {"n": 7, "text": "GUIDE_PLACE_HOUSE",   "target": ""},
	"done":          {"n": 7, "text": "GUIDE_DONE",          "target": "objective"},
}
## El mayor `n` de GUIDE_STEPS (una prueba lo comprueba: al insertar pasos, se sube).
const GUIDE_TOTAL := 7
## Cada cuanto se repasa si una meta se ha vuelto imposible (segundos).
const GUIDE_CHECK_SECONDS := 1.0

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
## Metas "fact" del tutorial ya cumplidas (GUIDE_GOALS). Van en la partida.
var guide_flags: Dictionary = {}

## El prologo esta pedido y espera a que no haya nada encima (menu principal,
## pausa, selector de modo).
var _prologue_pending := false
var _step := ""
var _menu_open := false
var _placing_id := ""
var _last_scan := 0.0
var _last_check := 0.0
## Metas que no se pueden cumplir en esta isla ahora mismo (sin bosque al que
## llegar, tope de edificios): el tutorial las pasa de largo.
var _blocked_goals: Array = []

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
	# Los tramos del auto-road: la guia se rederiva una vez al final, no por tramo.
	EventBus.placement_batch_started.connect(func(): _batch_depth += 1)
	EventBus.placement_batch_finished.connect(_on_placement_batch_finished)
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
	EventBus.production_collected.connect(_on_production_collected)
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
	# Con el tutorial en marcha, cada segundo: una meta pudo volverse imposible
	# (se agoto el bosque, se tapo el ultimo hueco) y el paso no puede quedarse
	# pidiendola para siempre.
	if guide_state == GUIDE_ACTIVE:
		_last_check += delta
		if _last_check >= GUIDE_CHECK_SECONDS:
			_last_check = 0.0
			_update_blocked_goals()
			_refresh_guide()
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
		_update_blocked_goals()
		_refresh_guide()

## Empieza el tutorial. `from_scratch` (Repetir tutorial) toma lo que ya hay
## como punto de partida; si no, cuenta desde cero, y una isla que ya tiene
## aserradero y casa lo da por hecho sin ensenar nada.
func start_guide(from_scratch: bool = true) -> void:
	guide_baseline = _counts() if from_scratch else {}
	if from_scratch:
		guide_flags = {}
	guide_state = GUIDE_ACTIVE
	_step = ""
	_last_check = 0.0
	_update_blocked_goals()
	var facts := guide_facts()
	# Una isla que ya tiene aserradero y casa es una partida jugada (vieja, sin
	# la marca): no se le ensena nada, tampoco recoger ni la Granja, que llegaron
	# despues (2026-10-04).
	facts["collected"] = true
	facts["farms"] = maxi(1, int(facts.get("farms", 0)))
	if not from_scratch and derive_step(facts) == "done":
		# Nada que ensenar: ya se hizo todo (partida vieja sin la marca).
		guide_state = GUIDE_DONE
		EventBus.tutorial_guide_finished.emit(false)
		return
	_refresh_guide()

## "Repetir tutorial" del indice de AYUDA. Con el tutorial de verdad aun en
## marcha no hace nada: si no, repetirlo seria la forma de saltarlo.
func replay_guide() -> void:
	if guide_state == GUIDE_ACTIVE:
		return
	start_guide(true)

## Es un repaso pedido desde AYUDA, y no el tutorial obligatorio? El repaso
## guarda su punto de partida (`guide_baseline`); el obligatorio cuenta desde cero.
func is_replay() -> bool:
	return guide_state == GUIDE_ACTIVE and not guide_baseline.is_empty()

## El repaso se puede dejar a medias (lo pidio el jugador); el tutorial
## obligatorio no.
func stop_replay() -> void:
	if is_replay():
		finish_guide()

## API interna, para sondas y pruebas: el jugador ya no tiene "Saltar tutorial"
## (decision de Bryan, 2026-10-04). Fuera del modo dev no hace nada. Los
## guardados con el tutorial ya saltado siguen cargando como "skipped".
func skip_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	if not GameConfig.dev_mode:
		push_warning("TutorialManager.skip_guide(): solo en modo dev")
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
##
## Hechos: `<edificio>s` (en pie o en obra), `<edificio>s_built` (obra acabada),
## una clave por cada meta "fact", `menu_open`, `placing` (el id en la mano) y
## `skip` (metas imposibles en esta isla, que se pasan de largo).
static func derive_step(f: Dictionary, goals: Array = GUIDE_GOALS) -> String:
	var placing := String(f.get("placing", ""))
	var menu := bool(f.get("menu_open", false))
	var skip: Array = f["skip"] if f.get("skip") is Array else []
	for g in goals:
		if String(g["goal"]) in skip:
			continue
		if String(g.get("kind", "build")) == "fact":
			if not bool(f.get(String(g["fact"]), false)):
				return String(g["step"])
			continue
		var b := String(g["building"])
		var steps: Dictionary = g["steps"]
		if int(f.get(b + "s", 0)) <= 0:
			if placing == b:
				return String(steps["place"])
			return String(steps["pick"]) if menu else String(steps["open"])
		if steps.has("wait") and int(f.get(b + "s_built", 0)) <= 0:
			return String(steps["wait"])
	return "done"

## Lo que hay ahora, menos lo que ya habia al empezar.
func guide_facts() -> Dictionary:
	var now := _counts()
	var f := {
		"menu_open": _menu_open,
		"placing": _placing_id,
		"skip": _blocked_goals.duplicate(),
	}
	for key in now:
		f[key] = int(now[key]) - int(guide_baseline.get(key, 0))
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) == "fact":
			f[String(g["fact"])] = bool(guide_flags.get(String(g["fact"]), false))
	return f

## Una meta "fact" se cumplio (la llama quien lo ve: p. ej. al recoger la
## produccion). Vale aunque el tutorial aun no haya llegado a ese paso.
func note_guide_fact(fact: String) -> void:
	if fact == "" or bool(guide_flags.get(fact, false)):
		return
	guide_flags[fact] = true
	_refresh_guide()

## Los edificios que cuentan las metas "build".
static func _goal_buildings() -> Array:
	var out: Array = []
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) == "build" and not String(g["building"]) in out:
			out.append(String(g["building"]))
	return out

## Cuantos hay de cada edificio de las metas: `<id>s` y `<id>s_built`.
func _counts() -> Dictionary:
	var out := {}
	for b in _goal_buildings():
		out[b + "s"] = 0
		out[b + "s_built"] = 0
	for info in GridManager.buildings_view():
		var data: Resource = info.get("data")
		if data == null:
			continue
		var id := String(data.get("id"))
		if not out.has(id + "s"):
			continue
		out[id + "s"] += 1
		var node: Node = info.get("node")
		if node != null and not node.has_meta("under_construction"):
			out[id + "s_built"] += 1
	return out

func _refresh_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	var step := derive_step(guide_facts())
	if step == _step:
		return
	_step = step
	EventBus.tutorial_step_changed.emit(step)

## Recoger cualquier produccion cumple la meta "collected" del tutorial.
func _on_production_collected(_node: Node, _collected: Dictionary) -> void:
	note_guide_fact("collected")

# ── Que ningun paso se atasque ───────────────────────────────────────

## Repasa que metas son imposibles ahora en esta isla.
func _update_blocked_goals() -> void:
	var blocked: Array = []
	var now := _counts()
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) != "build":
			continue
		var b := String(g["building"])
		# Ya cumplida: nada que comprobar (y la comprobacion del bosque cuesta).
		if int(now[b + "s"]) - int(guide_baseline.get(b + "s", 0)) > 0:
			continue
		if goal_impossible_reason(b) != "":
			blocked.append(String(g["goal"]))
	# Una meta "fact" que necesita otra que se pasa de largo, tambien: recoger lo
	# del aserradero no se puede si no hay aserradero.
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) == "fact" and String(g.get("needs", "")) in blocked:
			blocked.append(String(g["goal"]))
	_blocked_goals = blocked

## Las metas que el tutorial pasa de largo ahora mismo (para pruebas y sondas).
func blocked_goals() -> Array:
	return _blocked_goals.duplicate()

## Por que no se puede levantar otro `building_id` en esta isla, pase lo que
## pase con los recursos: "limit" (tope alcanzado), "prereq" (le falta un
## edificio que el tutorial no pide), "deposit" (ningun yacimiento al que llegar),
## "missing" (no existe) o "" si se puede. Faltar recursos u obreros NO es
## imposible: se arregla esperando o en el Mercado, y lo dice step_hint().
func goal_impossible_reason(building_id: String) -> String:
	var data := Rules.load_building_data(building_id)
	if data == null:
		return "missing"
	if not Rules.check_building_limit(building_id):
		return "limit"
	if not Rules.check_prerequisites(building_id):
		return "prereq"
	if not has_reachable_deposit(data, GameManager.map_generator()):
		return "deposit"
	return ""

## Hay al menos un sitio donde `data` toca su yacimiento y llega a la red (con
## carretera automatica), en cualquiera de sus dos giros? Para que no tenga regla
## de yacimiento, si. Sin generador o sin ningun yacimiento sorteado aun el mapa
## no esta listo: tambien si, para no pasar nada de largo a ciegas.
static func has_reachable_deposit(data: BuildingData, map_gen: Node) -> bool:
	if data == null:
		return true
	var rule: Dictionary = GameConfig.get_deposit_rule(data.id)
	if rule.is_empty() or map_gen == null or not map_gen.has_method("get_all_deposits"):
		return true
	var deposits: Array = map_gen.get_all_deposits()
	if deposits.is_empty():
		return true
	var reach := int(rule["reach"])
	var sizes: Array = [data.grid_size]
	if data.grid_size.x != data.grid_size.y:
		sizes.append(Vector2i(data.grid_size.y, data.grid_size.x))
	for dep in deposits:
		if String(dep.get("id", "")) != String(rule["deposit"]):
			continue
		var dx := int(dep["cell_x"])
		var dy := int(dep["cell_y"])
		var dw := int(dep.get("size_x", 2))
		var dh := int(dep.get("size_y", 2))
		for size in sizes:
			for ox in range(dx - size.x - reach + 1, dx + dw + reach):
				for oy in range(dy - size.y - reach + 1, dy + dh + reach):
					var origin := Vector2i(ox, oy)
					if not GridManager.is_valid_cell(origin):
						continue
					if Rules.evaluate_placement(data.id, origin, size, map_gen)["ok"]:
						return true
	return false

## Lo que le falta al jugador para el paso de ahora, en una linea corta, o "".
## Solo en los pasos de construir (abrir, elegir, colocar): obreros o recursos.
static func step_hint(step_id: String) -> String:
	var b := building_for_step(step_id)
	if b == "":
		return ""
	var data := Rules.load_building_data(b)
	if data == null:
		return ""
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		return Tr.t("GUIDE_NEED_WORKERS")
	var short := Rules.missing_cost(data)
	if not short.is_empty():
		return Tr.t("OBJ_MISSING") % Tr.amount_list(short)
	return ""

## El edificio de un paso de construir (abrir, elegir o colocar), o "".
static func building_for_step(step_id: String) -> String:
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) != "build":
			continue
		var steps: Dictionary = g["steps"]
		for k in ["open", "pick", "place"]:
			if String(steps.get(k, "")) == step_id:
				return String(g["building"])
	return ""

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

var _batch_depth := 0

func _on_building_placed(data: Resource, _cell: Vector2i) -> void:
	if data != null and String(data.get("id")) == "barracks":
		offer_tip("barracks")
	_placing_id = ""
	if _batch_depth > 0:
		return
	_refresh_guide()

func _on_placement_batch_finished(_count: int) -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0:
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
		"guide_flags": guide_flags.duplicate(),
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
		# Las claves de los edificios de las metas de hoy (`<id>s`, `<id>s_built`).
		# Una meta nueva sin clave en un guardado viejo cuenta desde cero.
		for b in _goal_buildings():
			for k in [b + "s", b + "s_built"]:
				if gb.has(k):
					guide_baseline[k] = int(gb[k])
	guide_flags = {}
	var gf: Variant = data.get("guide_flags", {})
	if gf is Dictionary:
		for k in gf:
			if k is String and gf[k] is bool and gf[k]:
				guide_flags[k] = true
	# Sin la clave es un guardado de antes de la primera escaramuza: si ya vio el
	# consejo del mapa, ya salio de expedicion y no se le vuelve a pedir.
	var fs: Variant = data.get("first_sortie_done", null)
	if fs is bool:
		first_sortie_done = fs
	else:
		first_sortie_done = "expedition_map" in tips_seen
	# Guardado de antes de las metas "fact" (rama comida): traia `guide_collected`.
	# Sin ninguna de las dos claves: si el tutorial ya acabo da igual; si va a
	# medias, se pide recoger una vez.
	if not data.has("guide_flags"):
		var gc: Variant = data.get("guide_collected", null)
		if (gc is bool and gc) or (not (gc is bool) and guide_state != GUIDE_ACTIVE):
			guide_flags["collected"] = true
	_blocked_goals = []
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
	guide_flags = {}
	_blocked_goals = []
	_last_check = 0.0
	_prologue_pending = false
	_step = ""
	_menu_open = false
	_placing_id = ""
