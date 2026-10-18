extends Node
## Todo lo que el juego le cuenta al jugador nuevo, en tres piezas que no se
## mezclan (docs/23-onboarding.md):
##
##   1. PROLOGO   el lore, como un expediente de la Regencia (PrologueScreen).
##                Una vez por partida, DESPUES de soltar el menu principal.
##   2. TUTORIAL  pasos guiados sobre la interfaz de verdad (TutorialPanel):
##                la meta -> el Nucleo -> "Pulsa CONSTRUIR" -> "Elige el
##                Aserradero" -> "Junto a un bosque" -> recoger -> el Cuartel
##                (2026-10-17) -> ... -> el Laboratorio ->
##                la meta otra vez. Avanza cuando el jugador HACE la cosa, no
##                cuando pulsa "Siguiente". No se salta ni se cierra (2026-10-04,
##                y el combate guiado desde 2026-10-16); a cambio, ningun paso
##                puede atascarse: lo imposible se pasa de largo, y lo que falta
##                se dice junto con como conseguirlo.
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
const TextKitScript := preload("res://scripts/ui/TextKit.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

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
##
## Tutorial claro (rama feat/tutorial-claro, 2026-10-16): delante, dos tarjetas
## de LEER (la meta de la partida y el Nucleo), que se cumplen con su boton; y
## detras de la casa, el resto de edificios del principio (Mina de oro, Mercado,
## Almacen y Laboratorio), cada uno con una frase de para que sirve y sus cifras
## (TutorialPanel las pinta con iconos, building_facts()). La carretera se
## explica en la espera de la obra del aserradero, que es cuando se ve tenderse.
## Y tres manejos (mismo dia): GIRAR al colocar la casa, MOVER la casa (gratis,
## no pierde nada) y DERRIBAR un tramo de carretera puesto para eso (1 oro).
##
## Una meta "fact" puede tener sus propios pasos segun lo que hace el jugador:
## `menu_step` con la lista de CONSTRUIR abierta, y `placing_step` mientras lleva
## en la mano `placing` ("*": cualquier cosa). `building`: el edificio del que se
## dicen el coste que falta y las cifras.
## El orden de esta lista es el orden del tutorial.
const GUIDE_GOALS := [
	{"goal": "goal", "kind": "fact", "fact": "goal_seen", "step": "goal"},
	{"goal": "core", "kind": "fact", "fact": "core_seen", "step": "core"},
	{"goal": "sawmill", "kind": "build", "building": "sawmill",
		"steps": {"open": "open_build", "pick": "pick_sawmill", "place": "place_sawmill", "wait": "wait_sawmill"}},
	{"goal": "collect", "kind": "fact", "fact": "collected", "step": "collect", "needs": "sawmill"},
	# Cuartel temprano (2026-10-17, feat/cuartel-temprano): "solo anadir el
	# Cuartel", justo despues de la madera. Sus tablones salen del Aserradero (el
	# paso need_barracks dice "toca tu Aserradero y pulsa Serrar tablones"); sin
	# Aserradero (bosque imposible) su requisito falla y se pasa de largo (prereq).
	{"goal": "barracks", "kind": "build", "building": "barracks",
		"steps": {"open": "open_barracks", "pick": "pick_barracks", "place": "place_barracks", "wait": "wait_barracks"}},
	{"goal": "farm", "kind": "build", "building": "farm",
		"steps": {"open": "open_farm", "pick": "pick_farm", "place": "place_farm"}},
	{"goal": "rotate", "kind": "fact", "fact": "rotated", "step": "rotate", "menu_step": "rotate_pick",
		"placing": "*", "placing_step": "rotate_now", "building": "house"},
	{"goal": "house", "kind": "build", "building": "house",
		"steps": {"open": "open_house", "pick": "pick_house", "place": "place_house"}},
	{"goal": "move", "kind": "fact", "fact": "moved", "step": "move",
		"placing": "__move__", "placing_step": "move_place"},
	{"goal": "practice_road", "kind": "fact", "fact": "road_placed", "step": "road_open",
		"menu_step": "road_pick", "placing": "road", "placing_step": "road_place", "building": "road"},
	{"goal": "demolish", "kind": "fact", "fact": "demolished", "step": "demolish"},
	{"goal": "gold_mine", "kind": "build", "building": "gold_mine",
		"steps": {"open": "open_gold_mine", "pick": "pick_gold_mine", "place": "place_gold_mine"}},
	{"goal": "market", "kind": "build", "building": "market",
		"steps": {"open": "open_market", "pick": "pick_market", "place": "place_market"}},
	{"goal": "warehouse", "kind": "build", "building": "warehouse",
		"steps": {"open": "open_warehouse", "pick": "pick_warehouse", "place": "place_warehouse"}},
	{"goal": "laboratory", "kind": "build", "building": "laboratory",
		"steps": {"open": "open_laboratory", "pick": "pick_laboratory", "place": "place_laboratory"}},
]

## Las metas que tenia el tutorial antes de 2026-10-16: una partida vieja sin la
## marca que ya las tiene hechas no repite nada (start_guide).
const LEGACY_GOALS := ["sawmill", "house"]

## Los pasos, con lo que ve el jugador. `n` es el numero de "PASO n DE
## GUIDE_TOTAL": un paso por edificio (abrir, elegir y colocar la casa son el 7).
## `ok`: tarjeta de leer, con un boton (esa clave de Tr) que cumple su `fact`.
## `building`: el edificio cuyas cifras salen con iconos en la tarjeta.
const GUIDE_STEPS := {
	"goal":             {"n": 1,  "text": "GUIDE_GOAL",            "target": "", "ok": "BTN_GUIDE_GOAL_OK", "fact": "goal_seen"},
	"core":             {"n": 2,  "text": "GUIDE_CORE",            "target": "core", "ok": "BTN_GUIDE_OK", "fact": "core_seen", "building": "nucleo"},
	"open_build":       {"n": 3,  "text": "GUIDE_OPEN_BUILD",      "target": "build_button", "building": "sawmill"},
	"pick_sawmill":     {"n": 3,  "text": "GUIDE_PICK_SAWMILL",    "target": "card:sawmill", "building": "sawmill"},
	"place_sawmill":    {"n": 3,  "text": "GUIDE_PLACE_SAWMILL",   "target": "forest", "building": "sawmill"},
	"wait_sawmill":     {"n": 3,  "text": "GUIDE_WAIT_SAWMILL",    "target": "building:sawmill"},
	"collect":          {"n": 4,  "text": "GUIDE_COLLECT",         "target": "building:sawmill"},
	# El Cuartel (2026-10-17): abrir, elegir, colocar y esperar la obra.
	"open_barracks":    {"n": 5,  "text": "GUIDE_OPEN_BARRACKS",   "target": "build_button", "building": "barracks"},
	"pick_barracks":    {"n": 5,  "text": "GUIDE_PICK_BARRACKS",   "target": "card:barracks", "building": "barracks"},
	"place_barracks":   {"n": 5,  "text": "GUIDE_PLACE_BARRACKS",  "target": "", "building": "barracks"},
	"wait_barracks":    {"n": 5,  "text": "GUIDE_WAIT_BARRACKS",   "target": "building:barracks", "building": "barracks"},
	"open_farm":        {"n": 6,  "text": "GUIDE_OPEN_FARM",       "target": "build_button", "building": "farm"},
	"pick_farm":        {"n": 6,  "text": "GUIDE_PICK_FARM",       "target": "card:farm", "building": "farm"},
	"place_farm":       {"n": 6,  "text": "GUIDE_PLACE_FARM",      "target": "", "building": "farm"},
	# Girar: con la Casa en la mano, antes de colocarla.
	"rotate":           {"n": 7,  "text": "GUIDE_ROTATE",          "target": "build_button", "building": "house"},
	"rotate_pick":      {"n": 7,  "text": "GUIDE_ROTATE_PICK",     "target": "card:house", "building": "house"},
	"rotate_now":       {"n": 7,  "text": "GUIDE_ROTATE_NOW",      "target": "rotate_button", "building": "house"},
	"open_house":       {"n": 7,  "text": "GUIDE_OPEN_HOUSE",      "target": "build_button", "building": "house"},
	"pick_house":       {"n": 7,  "text": "GUIDE_PICK_HOUSE",      "target": "card:house", "building": "house"},
	"place_house":      {"n": 7,  "text": "GUIDE_PLACE_HOUSE",     "target": "", "building": "house"},
	# Mover: la ficha de un edificio, MOVER, y otro sitio. Gratis.
	"move":             {"n": 8,  "text": "GUIDE_MOVE",            "target": "info_move|built:house"},
	"move_place":       {"n": 8,  "text": "GUIDE_MOVE_PLACE",      "target": ""},
	# Derribar: un tramo de carretera puesto para eso, y DEMOLER en su ficha.
	"road_open":        {"n": 9,  "text": "GUIDE_ROAD_OPEN",       "target": "build_button", "building": "road"},
	"road_pick":        {"n": 9,  "text": "GUIDE_ROAD_PICK",       "target": "card:road", "building": "road"},
	"road_place":       {"n": 9,  "text": "GUIDE_ROAD_PLACE",      "target": "", "building": "road"},
	"demolish":         {"n": 9,  "text": "GUIDE_DEMOLISH",        "target": "info_demolish_confirm|info_demolish|practice_road"},
	"open_gold_mine":   {"n": 10, "text": "GUIDE_OPEN_GOLD_MINE",  "target": "build_button", "building": "gold_mine"},
	"pick_gold_mine":   {"n": 10, "text": "GUIDE_PICK_GOLD_MINE",  "target": "card:gold_mine", "building": "gold_mine"},
	"place_gold_mine":  {"n": 10, "text": "GUIDE_PLACE_GOLD_MINE", "target": "deposit:gold_vein", "building": "gold_mine"},
	"open_market":      {"n": 11, "text": "GUIDE_OPEN_MARKET",     "target": "build_button", "building": "market"},
	"pick_market":      {"n": 11, "text": "GUIDE_PICK_MARKET",     "target": "card:market", "building": "market"},
	"place_market":     {"n": 11, "text": "GUIDE_PLACE_ANYWHERE",  "target": "", "building": "market"},
	"open_warehouse":   {"n": 12, "text": "GUIDE_OPEN_WAREHOUSE",  "target": "build_button", "building": "warehouse"},
	"pick_warehouse":   {"n": 12, "text": "GUIDE_PICK_WAREHOUSE",  "target": "card:warehouse", "building": "warehouse"},
	"place_warehouse":  {"n": 12, "text": "GUIDE_PLACE_ANYWHERE",  "target": "", "building": "warehouse"},
	"open_laboratory":  {"n": 13, "text": "GUIDE_OPEN_LABORATORY", "target": "build_button", "building": "laboratory"},
	"pick_laboratory":  {"n": 13, "text": "GUIDE_PICK_LABORATORY", "target": "card:laboratory", "building": "laboratory"},
	"place_laboratory": {"n": 13, "text": "GUIDE_PLACE_ANYWHERE",  "target": "", "building": "laboratory"},
	"done":             {"n": 13, "text": "GUIDE_DONE",            "target": "objective"},
	# Consigue lo que falta (2026-10-17, fix/tutorial-materiales): el paso de un
	# edificio que aun no se puede pagar (recursos, material del taller o
	# trabajadores). En vez de "Toca CONSTRUIR" con el boton apagado, dice que
	# falta y como conseguirlo, y senala donde (need_target). Al tenerlo todo,
	# vuelve solo al paso de construir. `need`: el texto lleva el nombre.
	"need_sawmill":     {"n": 3,  "text": "GUIDE_NEED", "target": "", "building": "sawmill", "need": true},
	"need_barracks":    {"n": 5,  "text": "GUIDE_NEED", "target": "", "building": "barracks", "need": true},
	"need_farm":        {"n": 6,  "text": "GUIDE_NEED", "target": "", "building": "farm", "need": true},
	"need_house":       {"n": 7,  "text": "GUIDE_NEED", "target": "", "building": "house", "need": true},
	"need_road":        {"n": 9,  "text": "GUIDE_NEED", "target": "", "building": "road", "need": true},
	"need_gold_mine":   {"n": 10, "text": "GUIDE_NEED", "target": "", "building": "gold_mine", "need": true},
	"need_market":      {"n": 11, "text": "GUIDE_NEED", "target": "", "building": "market", "need": true},
	"need_warehouse":   {"n": 12, "text": "GUIDE_NEED", "target": "", "building": "warehouse", "need": true},
	"need_laboratory":  {"n": 13, "text": "GUIDE_NEED", "target": "", "building": "laboratory", "need": true},
}
## Prefijo de los pasos "consigue lo que falta": "need_" + id del edificio.
const NEED_PREFIX := "need_"
## El mayor `n` de GUIDE_STEPS (una prueba lo comprueba: al insertar pasos, se sube).
const GUIDE_TOTAL := 13

## Los pasos en los que el tutorial deja ver la ficha de un edificio
## (BuildingInfoPanel) sin esconderse: lo que ensenan ocurre dentro de ella.
const INFO_PANEL_STEPS := ["move", "demolish", "repair"]

## La leccion de reparar (2026-10-16): una tarjeta de leer que sale la primera
## vez que la Tormenta o un asedio dana un edificio, aparte del tutorial guiado
## (llega cuando el tutorial ya acabo, o espera a que acabe). Senala el edificio
## danado; se cierra con Entendido o al repararlo.
const REPAIR_STEP := "repair"
const REPAIR_STEP_DEF := {"n": 0, "text": "GUIDE_REPAIR", "target": "info_repair|damaged", "ok": "BTN_GUIDE_OK"}
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
## Lecciones de combate ya dadas en esta partida ("basics", "artillery"; docs/23
## §2.4). Van en la partida, como el resto del tutorial.
var combat_lessons_done: Array[String] = []

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
	# Aire y mar (feat/aire-mar-reglas): al levantar el Astillero o el Aerodromo.
	"air_sea":        {"title": "HELP_T_AIR_SEA",         "body": "HELP_B_AIR_SEA"},
	"market":         {"title": "TUT_TIP_MARKET_TITLE",   "body": "TUT_TIP_MARKET_BODY"},
	"tech_tree":      {"title": "TUT_TIP_TECH_TITLE",     "body": "TUT_TIP_TECH_BODY"},
	"expedition_map": {"title": "TUT_TIP_MAP_TITLE",      "body": "TUT_TIP_MAP_BODY"},
	"first_sortie":   {"title": "TUT_TIP_FIRST_SORTIE_TITLE", "body": "TUT_TIP_FIRST_SORTIE_BODY"},
	"upkeep":         {"title": "TUT_TIP_UPKEEP_TITLE",   "body": "TUT_TIP_UPKEEP_BODY"},
	"consumption":    {"title": "TUT_TIP_CONSUMPTION_TITLE", "body": "HELP_TIP_CONSUMPTION_BODY"},
	"final_audit":    {"title": "TUT_TIP_AUDIT_TITLE",    "body": "HELP_TIP_AUDIT_BODY"},
	# Tres campanas (feat/tres-campanas): al abrirse la de Tierra (primera
	# escaramuza ganada) y lo que pide el Ataque Final (era 3, o el CG a nivel 3
	# sin las campanas: ProgressionManager._announce_audit_waiting).
	"campaigns":      {"title": "HELP_T_CAMPAIGNS",       "body": "HELP_B_CAMPAIGNS"},
	"final_gate":     {"title": "HELP_T_FINAL_GATE",      "body": "HELP_B_FINAL_GATE"},
	# ── Ayudas de las novedades (2026-10-14): disparadores en _connect_news() ──
	"saves":          {"title": "HELP_T_SAVES",     "body": "HELP_B_SAVES"},
	"rank":           {"title": "HELP_T_RANK",      "body": "HELP_B_RANK"},
	"flag":           {"title": "HELP_T_FLAG",      "body": "HELP_B_FLAG"},
	"bug_report":     {"title": "HELP_T_BUG",       "body": "HELP_B_BUG"},
	"night":          {"title": "HELP_T_NIGHT",     "body": "HELP_B_NIGHT"},
	"farm":           {"title": "HELP_T_FARM",      "body": "HELP_B_FARM"},
	"collect_full":   {"title": "HELP_T_COLLECT",   "body": "HELP_B_COLLECT"},
	"fishing_dock":   {"title": "HELP_T_FISHING_DOCK", "body": "HELP_B_FISHING_DOCK"},
	# Edificios militares (feat/edificios-militares).
	"infirmary":      {"title": "HELP_T_INFIRMARY", "body": "HELP_B_INFIRMARY"},
	"smithy":         {"title": "HELP_T_SMITHY", "body": "HELP_B_SMITHY"},
	"firing_range":   {"title": "HELP_T_FIRING_RANGE", "body": "HELP_B_FIRING_RANGE"},
	"island":         {"title": "HELP_T_ISLAND",    "body": "HELP_B_ISLAND"},
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
	# Tres campanas: en la era 3 se cuenta que pide el Ataque Final.
	EventBus.era_advanced.connect(func(era: int):
		if era >= 3 and GameMode.audit_needs_campaigns() and ProgressionManager.final_audit == null:
			offer_tip("final_gate"))
	UIManager.window_opened.connect(_on_window_opened)
	UIManager.window_closed.connect(_on_window_closed)

	# El tutorial guiado mira lo que el jugador hace.
	EventBus.building_selected_for_placement.connect(_on_placement_started)
	EventBus.request_move_building.connect(func(_b): _set_placing("__move__"))
	EventBus.building_placement_cancelled.connect(func(): _set_placing(""))
	EventBus.building_moved.connect(func(_f, _t): _set_placing(""))
	EventBus.construction_completed.connect(func(_n): _recheck_guide())
	EventBus.production_collected.connect(_on_production_collected)
	EventBus.building_demolished.connect(_on_building_demolished)
	# Los manejos del tutorial (2026-10-16): girar, mover y derribar.
	EventBus.building_rotate_requested.connect(_on_rotate_requested)
	EventBus.building_moved.connect(_on_building_moved)
	# La leccion de reparar.
	EventBus.building_damaged.connect(_on_building_damaged)
	EventBus.building_repaired.connect(_on_building_repaired)
	EventBus.tutorial_guide_finished.connect(func(_skipped): _show_pending_repair.call_deferred())
	_connect_news()
	_connect_combat_lessons()

# ══════════════════════════════════════════════════════════════════════
# ── Prologo ──
# ══════════════════════════════════════════════════════════════════════

func _on_game_started() -> void:
	_menu_open = false
	_placing_id = ""
	if not repair_lesson_done and _extra_step == "":
		_repair_node = _first_damaged()
		_repair_pending = _repair_node != null
		if _repair_pending and intro_seen and not (guide_state in [GUIDE_ACTIVE, GUIDE_PENDING]):
			_show_pending_repair.call_deferred()
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

## Nombre antiguo de show_prologue(), para quien ya lo llamaba (pruebas, sondas).
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
	# Una isla que ya tiene aserradero y casa es una partida jugada (vieja, sin
	# la marca): no se le ensena nada, tampoco recoger, la Granja ni los
	# edificios que llegaron despues al tutorial (2026-10-04, 2026-10-16).
	var legacy: Array = GUIDE_GOALS.filter(func(g): return String(g["goal"]) in LEGACY_GOALS)
	if not from_scratch and derive_step(guide_facts(), legacy) == "done":
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
	if guide_state == GUIDE_ACTIVE:
		return _step
	return _extra_step

## Hay algo del tutorial que ensenar ahora: el tutorial guiado o una leccion
## suelta (reparar). TutorialPanel se esconde si no.
func is_coach_active() -> bool:
	return guide_state == GUIDE_ACTIVE or _extra_step != ""

## El paso que toca con estos hechos. Pura, para poder probarla sin escena, y es
## la que hace el tutorial robusto: no importa en que orden haga las cosas el
## jugador ni que cargue a medias; el paso sale de lo que hay.
##
## Hechos: `<edificio>s` (en pie o en obra), `<edificio>s_built` (obra acabada),
## una clave por cada meta "fact", `menu_open`, `placing` (el id en la mano),
## `skip` (metas imposibles en esta isla, que se pasan de largo) y `short` (los
## edificios de las metas que aun no se pueden pagar: el paso es entonces
## "consigue lo que falta", need_<id>, y no "Toca CONSTRUIR").
static func derive_step(f: Dictionary, goals: Array = GUIDE_GOALS) -> String:
	var placing := String(f.get("placing", ""))
	var menu := bool(f.get("menu_open", false))
	var skip: Array = f["skip"] if f.get("skip") is Array else []
	var short: Array = f["short"] if f.get("short") is Array else []
	for g in goals:
		if String(g["goal"]) in skip:
			continue
		if String(g.get("kind", "build")) == "fact":
			if not bool(f.get(String(g["fact"]), false)):
				var want := String(g.get("placing", ""))
				if g.has("placing_step") and placing != "" and (want == "*" or want == placing):
					return String(g["placing_step"])
				# Una meta que se cumple eligiendo un edificio en CONSTRUIR (girar
				# la Casa, poner un tramo): sin poder pagarlo, antes conseguirlo.
				if g.has("menu_step") and String(g.get("building", "")) in short:
					return NEED_PREFIX + String(g["building"])
				if g.has("menu_step") and menu:
					return String(g["menu_step"])
				return String(g["step"])
			continue
		var b := String(g["building"])
		var steps: Dictionary = g["steps"]
		if int(f.get(b + "s", 0)) <= 0:
			if placing == b:
				return String(steps["place"])
			# Sin poder pagarlo no se pide abrir CONSTRUIR: el boton estaria
			# apagado y el tutorial no diria nada util (bug de la 1.0, 2026-10-17).
			if b in short:
				return NEED_PREFIX + b
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
		"short": short_goals(),
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
	# La meta siguiente puede ser imposible en esta isla: se mira ya, no dentro
	# de un segundo (si no, la tarjeta pediria un instante algo que no se puede).
	if guide_state == GUIDE_ACTIVE:
		_update_blocked_goals()
	_refresh_guide()

## Los edificios de las metas que se eligen en CONSTRUIR (las "build" y las
## "fact" con `menu_step`) y que ahora no se pueden pagar (can_pay_now).
static func short_goals() -> Array:
	var out: Array = []
	for g in GUIDE_GOALS:
		var b := String(g.get("building", ""))
		if b == "" or b in out:
			continue
		if String(g.get("kind", "build")) == "fact" and not g.has("menu_step"):
			continue
		if not can_pay_now(b):
			out.append(b)
	return out

## Se puede pagar `building_id` ahora: trabajadores libres y todo su coste
## (recursos y materiales del taller). El tope, los requisitos y el rango no
## cuentan: eso lo pasa de largo goal_impossible_reason().
static func can_pay_now(building_id: String) -> bool:
	var data := Rules.load_building_data(building_id)
	if data == null:
		return true
	return workers_short(data) <= 0 and Rules.missing_cost(data).is_empty()

## Cuantos trabajadores libres le faltan a `data` (0 si ninguno).
static func workers_short(data: BuildingData) -> int:
	if data == null or data.workers_required <= 0:
		return 0
	return maxi(0, data.workers_required - PopulationManager.get_free_workers())

## Que senalar en un paso need_<id>: donde se consigue lo primero que falta.
## Un recurso, su productor (o el bosque / la veta a mano); un material, el
## edificio que lo fabrica; trabajadores sin sitio en las casas, CONSTRUIR (otra
## Casa). "" si no hay nada que senalar (esperar a que llegue la gente).
static func need_target(building_id: String) -> String:
	var data := Rules.load_building_data(building_id)
	if data == null:
		return ""
	for res in Rules.missing_cost(data):
		var t := _target_for_resource(String(res))
		if t != "":
			return t
	if workers_short(data) > 0 \
			and PopulationManager.get_population() >= PopulationManager.get_max_population():
		return "build_button"
	return ""

static func _target_for_resource(res: String) -> String:
	var source := ""
	if ResourceManager.is_material_name(res):
		source = GameConfig.get_material_source(res)
	elif not ResourceManager.is_unlocked_by_name(res):
		return ""
	else:
		source = String(Objectives.PRODUCER_OF.get(res, ""))
	if source == "":
		return ""
	if Rules.count_building(source) > 0:
		# Terminado, o su obra si aun se esta levantando.
		return "built:%s|building:%s" % [source, source]
	if res == "wood":
		return "forest"
	if res == "gold":
		return "deposit:gold_vein"
	return "build_button"

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

## Repasa las metas imposibles y despues el paso: tras algo que cumple una meta.
func _recheck_guide() -> void:
	if guide_state != GUIDE_ACTIVE:
		return
	_update_blocked_goals()
	_refresh_guide()

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
	# En orden, y solo hasta la meta que toca: las de detras se miran al llegar a
	# ellas. Buscar sitio junto a un yacimiento cuesta (evaluate_placement por
	# casilla), y con diez metas no se paga cada segundo por las que aun no tocan.
	var blocked: Array = []
	var now := _counts()
	for g in GUIDE_GOALS:
		var goal := String(g["goal"])
		if String(g.get("kind", "build")) == "fact":
			# Una meta "fact" que necesita otra que se pasa de largo, tambien:
			# recoger lo del aserradero no se puede si no hay aserradero.
			if String(g.get("needs", "")) in blocked:
				blocked.append(goal)
				continue
			if bool(guide_flags.get(String(g["fact"]), false)):
				continue
			break
		var b := String(g["building"])
		# Ya cumplida: nada que comprobar (y la comprobacion del bosque cuesta).
		if int(now[b + "s"]) - int(guide_baseline.get(b + "s", 0)) > 0:
			if g["steps"].has("wait") and int(now[b + "s_built"]) - int(guide_baseline.get(b + "s_built", 0)) <= 0:
				break
			continue
		var why := goal_impossible_reason(b)
		if why != "":
			blocked.append(goal)
			_notice_skipped(goal, b, why)
			continue
		break
	_blocked_goals = blocked

## Las metas que el tutorial ya dijo que se saltaba en esta sesion. Transitorio:
## al cargar se puede volver a decir una vez, que no molesta.
var _skip_noticed: Array = []

## Una meta de edificio se pasa de largo: se dice una vez y en una linea por que,
## para que el jugador no vea saltar el tutorial sin entenderlo (2026-10-17). En
## un repaso no: ahi el tope o el requisito son cosa del repaso, no del jugador.
func _notice_skipped(goal: String, building_id: String, why: String) -> void:
	if goal in _skip_noticed or guide_state != GUIDE_ACTIVE or is_replay():
		return
	_skip_noticed.append(goal)
	var key := String(SKIP_NOTICE_KEYS.get(why, ""))
	if key == "":
		return
	var data := Rules.load_building_data(building_id)
	var bname: String = data.get_display_name() if data != null else building_id
	EventBus.notification_posted.emit(Tr.t(key) % bname, "notice", UITheme.ACCENT)

## Por que se salta una meta -> la frase que lo dice (con el nombre del edificio).
const SKIP_NOTICE_KEYS := {
	"deposit": "GUIDE_SKIP_DEPOSIT",
	"limit": "GUIDE_SKIP_LIMIT",
	"prereq": "GUIDE_SKIP_PREREQ",
	"rank": "GUIDE_SKIP_RANK",
}

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
	# Un edificio cerrado por rango no se puede pedir: el rango no se sube
	# esperando en el tutorial (hoy ninguno de los del principio lo esta).
	if not Rules.check_rank(building_id):
		return "rank"
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

## Lo que le falta al jugador para el paso de ahora, o "": una linea corta por
## cosa (trabajadores; recursos y materiales del taller juntos). Solo en los
## pasos de construir (abrir, elegir, colocar, conseguir). Antes, con pocos
## trabajadores, se callaba lo que faltaba de recursos (2026-10-17).
static func step_hint(step_id: String) -> String:
	var b := building_for_step(step_id)
	if b == "":
		return ""
	var data := Rules.load_building_data(b)
	if data == null:
		return ""
	var lines: Array = []
	var hands := workers_short(data)
	if hands > 0:
		lines.append(Tr.t("GUIDE_NEED_WORKERS") % hands)
	var short := Rules.missing_cost(data)
	if not short.is_empty():
		lines.append(Tr.t("OBJ_MISSING") % Tr.amount_list(short))
	return "\n".join(lines)

## COMO conseguir lo que falta para el paso de ahora, en una linea, o "". Va
## debajo de step_hint(): ese dice QUE falta; este, que hacer para tenerlo, para
## que ningun paso deje al jugador sin saber como seguir (el tutorial no se salta).
static func step_how(step_id: String) -> String:
	if step_id == "collect":
		# Recoger pide que el aserradero produzca. Parado (sin trabajadores, sin
		# carretera, retirado), no producira nunca: se dice por que mirar.
		for info in GridManager.buildings_view():
			var d: Resource = info.get("data")
			var node: Node = info.get("node")
			if d == null or String(d.get("id")) != "sawmill" or node == null:
				continue
			if node.has_meta("under_construction"):
				continue
			if node.has_meta("staffed") and not bool(node.get_meta("staffed")):
				return Tr.t("GUIDE_HOW_STOPPED")
		return ""
	var b := building_for_step(step_id)
	if b == "":
		return ""
	var data := Rules.load_building_data(b)
	if data == null:
		return ""
	var lines: Array = []
	if workers_short(data) > 0:
		# Con sitio libre en las casas, la gente llega sola; sin sitio, otra Casa.
		if PopulationManager.get_population() < PopulationManager.get_max_population():
			lines.append(Tr.t("GUIDE_HOW_WORKERS_WAIT"))
		else:
			lines.append(Tr.ti("GUIDE_HOW_WORKERS_HOUSE"))
	# Una linea por recurso o material que falta (Objectives.how_to_get, la
	# misma que usa ¿QUE HACER?): madera, oro, comida, acero, petroleo y los
	# materiales del taller (tablones, lingotes, vigas, combustible).
	lines.append_array(Objectives.how_lines(Rules.missing_cost(data)))
	return "\n".join(lines)

## El edificio de un paso de construir (abrir, elegir o colocar), o "".
static func building_for_step(step_id: String) -> String:
	var e: Dictionary = GUIDE_STEPS.get(step_id, {})
	if bool(e.get("need", false)):
		return String(e["building"])
	for g in GUIDE_GOALS:
		if String(g.get("kind", "build")) == "fact":
			if g.has("building") and step_id in [String(g["step"]), String(g.get("menu_step", "")),
					String(g.get("placing_step", ""))]:
				return String(g["building"])
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
static func _step_def(step_id: String) -> Dictionary:
	if step_id == REPAIR_STEP:
		return REPAIR_STEP_DEF
	return GUIDE_STEPS.get(step_id, {})

static func step_text(step_id: String) -> String:
	var e: Dictionary = _step_def(step_id)
	if e.is_empty():
		return ""
	var text := Tr.ti(String(e.get("text", "")))
	if bool(e.get("need", false)):
		var data := Rules.load_building_data(String(e["building"]))
		var shown_name: String = data.get_display_name() if data != null else String(e["building"])
		# Solo faltan manos y las casas estan llenas (el Laboratorio, casi
		# siempre: el Cuartel temprano se llevo el trabajador que sobraba). En vez
		# de "aun no puedes construirlo" + lista, una frase que lo cuenta como el
		# paso natural que es: primero otra Casa (feat/hud-y-tutorial).
		if needs_house_only(String(e["building"])):
			var house := Rules.load_building_data("house")
			var room: int = house.population_capacity if house != null else 0
			return Tr.ti("GUIDE_NEED_HOUSE") % [shown_name, room]
		text = text % shown_name
	return text

## A `building_id` solo le faltan trabajadores (los recursos ya estan) y en las
## casas no cabe nadie mas: lo unico que lo arregla es otra Casa.
static func needs_house_only(building_id: String) -> bool:
	var data := Rules.load_building_data(building_id)
	if data == null or workers_short(data) <= 0:
		return false
	if not Rules.missing_cost(data).is_empty():
		return false
	return PopulationManager.get_population() >= PopulationManager.get_max_population()

## Es un paso "consigue lo que falta" (need_<id>).
static func is_need_step(step_id: String) -> bool:
	return bool(GUIDE_STEPS.get(step_id, {}).get("need", false))

## Lleva algo en la mano para colocar (el paso de derribar pide antes soltarlo).
func is_placing() -> bool:
	return _placing_id != ""

static func step_number(step_id: String) -> int:
	return int(GUIDE_STEPS.get(step_id, {}).get("n", 0))

static func step_target(step_id: String) -> String:
	var e: Dictionary = _step_def(step_id)
	if bool(e.get("need", false)):
		return need_target(String(e["building"]))
	return String(e.get("target", ""))

## El paso es una tarjeta de leer (la meta, el Nucleo, reparar), con boton.
static func step_has_ok(step_id: String) -> bool:
	return _step_def(step_id).has("ok")

## El texto del boton de una tarjeta de leer.
static func step_ok_text(step_id: String) -> String:
	return Tr.t(String(_step_def(step_id).get("ok", "BTN_GUIDE_OK")))

## El edificio cuyas cifras se ensenan en la tarjeta del paso, o "".
static func step_building(step_id: String) -> String:
	return String(GUIDE_STEPS.get(step_id, {}).get("building", ""))

## El jugador pulso el boton de una tarjeta de leer: su meta queda cumplida.
## Solo vale para el paso que esta en pantalla (un boton viejo no adelanta nada).
func confirm_step(step_id: String) -> void:
	if step_id == REPAIR_STEP:
		if _extra_step == REPAIR_STEP:
			_finish_repair_lesson()
		return
	if guide_state != GUIDE_ACTIVE or step_id == "" or step_id != _step:
		return
	var fact := String(GUIDE_STEPS.get(step_id, {}).get("fact", ""))
	if fact != "":
		note_guide_fact(fact)

## Lo que da y lo que pide un edificio, para pintarlo con iconos en la tarjeta
## ("iconos y cifras antes que frases"): [{"icon", "text"}]. `icon` es un id de
## UITheme.icon_texture ("wood", "workers"...) o "" (solo texto). Sale de los
## datos del juego (BuildingData, GameConfig): si cambia el balance, cambia sola.
static func building_facts(building_id: String) -> Array:
	var out: Array = []
	if building_id == "":
		return out
	var data := Rules.load_building_data(building_id)
	if data == null:
		return out
	var prod: Dictionary = data.get_production()
	for res in prod:
		out.append({"icon": String(res), "text": Tr.t("GUIDE_FACT_PRODUCES") % [int(prod[res]),
			TextKitScript.short_time(data.production_interval)]})
	if data.population_capacity > 0:
		out.append({"icon": "workers", "text": Tr.t("GUIDE_FACT_ROOM") % data.population_capacity})
	if data.workers_required > 0:
		out.append({"icon": "workers", "text": Tr.t("GUIDE_FACT_WORKERS") % data.workers_required})
	if building_id == "warehouse":
		out.append({"icon": "", "text": Tr.t("GUIDE_FACT_STORAGE") % GameConfig.warehouse_storage_bonus})
	if building_id == "barracks":
		# Cuartel temprano (2026-10-17): sitio para soldados.
		# Lo que suma el PROXIMO: +8 los primeros, menos despues, nada en el techo.
		var gain := GameConfig.army_capacity_gain(ArmyManager.barracks_count())
		if gain > 0:
			out.append({"icon": "", "text": Tr.t("GUIDE_FACT_ARMY") % gain})
	return out

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
	# Con una leccion de combate en marcha, la tarjeta del tablero sobra: lo
	# cuentan las marcas. Se da por vista para que este en el indice de AYUDA.
	if _begin_combat_lesson():
		if not "encounter" in tips_seen:
			tips_seen.append("encounter")
		return
	offer_tip("encounter")

var _batch_depth := 0

func _on_building_placed(data: Resource, cell: Vector2i) -> void:
	if data != null and String(data.get("id")) == "barracks":
		offer_tip("barracks")
	# Aire y mar: el primer Astillero o Aerodromo explica los medios y quien gana
	# a quien entre ellos.
	if data != null and String(data.get("id")) in ["shipyard", "aerodrome"]:
		offer_tip("air_sea")
	# El tramo de carretera para practicar el derribo: puesto a mano, con la
	# carretera en la mano (no un tramo de la carretera automatica de otro
	# edificio), en su paso.
	if data != null and String(data.get("id")) == "road" and _placing_id == "road" \
			and guide_state == GUIDE_ACTIVE and _step in ["road_open", "road_pick", "road_place"]:
		practice_road_cell = cell
		_placing_id = ""
		note_guide_fact("road_placed")
		return
	_placing_id = ""
	if _batch_depth > 0:
		return
	# Una meta cumplida deja paso a la siguiente, que puede ser imposible: se
	# mira ya. Solo con los edificios de las metas (no con cada tramo de
	# carretera pintado a mano: la busqueda de sitio cuesta).
	if data != null and String(data.get("id")) in _goal_buildings():
		_recheck_guide()
	else:
		_refresh_guide()

func _on_placement_batch_finished(_count: int) -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0:
		_recheck_guide()

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
		# Tres campanas: con la primera escaramuza ganada se abre la de Tierra.
		if GameMode.tithe_enabled() or GameMode.audit_enabled():
			offer_tip("campaigns")

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

# ── Girar, mover y derribar (2026-10-16) ─────────────────────────────

## La celda del tramo de carretera puesto para practicar el derribo, o (-1, -1).
## Transitorio: si se carga a medias, la marca senala la ficha y no la celda.
var practice_road_cell := Vector2i(-1, -1)

## R (teclado) o ↻ (en pantalla) con algo en la mano: ya sabe girar.
func _on_rotate_requested() -> void:
	if guide_state == GUIDE_ACTIVE and _placing_id != "":
		note_guide_fact("rotated")

## Cualquier edificio cambiado de sitio cumple la meta de mover.
func _on_building_moved(_from: Vector2i, _to: Vector2i) -> void:
	if guide_state == GUIDE_ACTIVE:
		note_guide_fact("moved")

func _on_building_demolished(node: Node, _cell: Vector2i) -> void:
	# Derribar cualquier cosa ensena lo mismo (el Nucleo no se puede). Si derriba
	# algo de las metas, el paso sale de lo que queda: lo vuelve a pedir.
	if guide_state == GUIDE_ACTIVE and _step == "demolish":
		practice_road_cell = Vector2i(-1, -1)
		note_guide_fact("demolished")
	if node == _repair_node:
		_repair_node = null
	_recheck_guide()

# ── La leccion de reparar (2026-10-16) ───────────────────────────────

## Ya se ensenó a reparar en esta partida. Va en la partida.
var repair_lesson_done := false
## La leccion suelta en pantalla ("repair") o "".
var _extra_step := ""
## El edificio danado que senala, y si espera a que acabe el tutorial guiado.
var _repair_node: Node = null
var _repair_pending := false

func _on_building_damaged(node: Node, _health: int, _max_health: int) -> void:
	if repair_lesson_done or _extra_step != "" or node == null:
		return
	_repair_node = node
	# Con el tutorial guiado en marcha (o sin empezar aun), espera a que acabe.
	if guide_state in [GUIDE_ACTIVE, GUIDE_PENDING]:
		_repair_pending = true
		return
	_show_repair()

func _on_building_repaired(node: Node) -> void:
	if _extra_step == REPAIR_STEP and (node == _repair_node or not _any_damaged()):
		_finish_repair_lesson()

func _show_pending_repair() -> void:
	if not _repair_pending or repair_lesson_done or guide_state in [GUIDE_ACTIVE, GUIDE_PENDING]:
		return
	_repair_pending = false
	if _repair_node == null or not is_instance_valid(_repair_node) or not BuildingHealth.is_damaged(_repair_node):
		_repair_node = _first_damaged()
	if _repair_node != null:
		_show_repair()

func _show_repair() -> void:
	_extra_step = REPAIR_STEP
	EventBus.tutorial_step_changed.emit(REPAIR_STEP)

func _finish_repair_lesson() -> void:
	repair_lesson_done = true
	_repair_pending = false
	_repair_node = null
	if _extra_step != "":
		_extra_step = ""
		EventBus.tutorial_step_changed.emit("")
	GameManager.request_save()

## El edificio que senala la leccion de reparar (otro danado si ese ya no esta).
func repair_target() -> Node:
	if _repair_node == null or not is_instance_valid(_repair_node) or not BuildingHealth.is_damaged(_repair_node):
		_repair_node = _first_damaged()
	return _repair_node

func _first_damaged() -> Node:
	for info in GridManager.buildings_view():
		var node: Node = info.get("node")
		if node != null and is_instance_valid(node) and not BuildingHealth.is_immune(node) \
				and BuildingHealth.is_damaged(node):
			return node
	return null

func _any_damaged() -> bool:
	return _first_damaged() != null

## Lo que cuesta reparar ahora el edificio senalado, para la fila de cifras:
## [{"icon", "text"}]. Sale de BuildingHealth.repair_cost (en proporcion al dano).
func repair_facts() -> Array:
	var out: Array = []
	var node := repair_target()
	if node == null:
		return out
	var cost: Dictionary = BuildingHealth.repair_cost(node)
	if cost.is_empty():
		return out
	out.append({"icon": "", "text": Tr.t("GUIDE_FACT_REPAIR_COST")})
	for type in cost:
		out.append({"icon": ResourceManager.get_type_name(type), "text": str(int(cost[type]))})
	return out

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
		"combat_lessons_done": combat_lessons_done.duplicate(),
		"repair_lesson_done": repair_lesson_done,
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
	# Lecciones de combate. Sin la clave (guardado de antes, 2026-10-14): quien ya
	# gano su primera escaramuza no repite la de lo basico; la de artilleria si
	# le sale, una vez, porque explica algo que antes no se contaba.
	combat_lessons_done.clear()
	var cl: Variant = data.get("combat_lessons_done", null)
	if cl is Array:
		for l in cl:
			if l is String and l in COMBAT_LESSONS and not l in combat_lessons_done:
				combat_lessons_done.append(l)
	elif first_sortie_done:
		combat_lessons_done.append(LESSON_BASICS)
	_clear_combat_lesson(false)
	# La leccion de reparar. Sin la clave (guardado de antes): no se ha dado.
	var rl: Variant = data.get("repair_lesson_done", false)
	repair_lesson_done = rl is bool and rl
	_extra_step = ""
	_repair_node = null
	_repair_pending = false
	practice_road_cell = Vector2i(-1, -1)
	_blocked_goals = []
	_skip_noticed = []
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
	combat_lessons_done.clear()
	_clear_combat_lesson(false)
	repair_lesson_done = false
	_extra_step = ""
	_repair_node = null
	_repair_pending = false
	practice_road_cell = Vector2i(-1, -1)
	_blocked_goals = []
	_skip_noticed = []
	_last_check = 0.0
	_prologue_pending = false
	_step = ""
	_menu_open = false
	_placing_id = ""

# ══════════════════════════════════════════════════════════════════════
# ── Ayudas de las novedades (2026-10-14, docs/23 §3) ──
# ══════════════════════════════════════════════════════════════════════
# Cada una sale una vez, cuando el jugador se encuentra con lo que explica. La de la isla
# la piden los colocadores al rechazar agua; la del informe de fallo, PauseMenu.

func _connect_news() -> void:
	EventBus.tutorial_guide_finished.connect(func(_skipped): offer_tip("saves"))
	EventBus.governor_rank_up.connect(_on_news_rank_up)
	EventBus.day_phase_changed.connect(_on_news_day_phase)
	EventBus.construction_completed.connect(_on_news_construction)
	EventBus.building_stock_changed.connect(_on_news_stock)

## El primer ascenso: que da la XP y, detras, que la bandera tiene piezas nuevas.
func _on_news_rank_up(_rank: int, _rewards: Dictionary) -> void:
	offer_tip("rank")
	offer_tip("flag")

## Al anochecer por primera vez (solo luz: nada cambia en la economia).
func _on_news_day_phase(phase: int, _hour: float) -> void:
	if phase == DayCycle.Phase.DUSK or phase == DayCycle.Phase.NIGHT:
		offer_tip("night")

## La primera Granja terminada: los cultivos y sus cifras. El primer Muelle de
## pesca: donde va y su proceso (feat/muelle-pesca).
func _on_news_construction(node: Node) -> void:
	if node == null:
		return
	var info := GridManager.get_building_info(node)
	if info.is_empty() or info["data"] == null:
		return
	match String(info["data"].id):
		"farm":
			if not has_seen_tip("farm"):
				offer_tip("farm")
		"fishing_dock":
			if not has_seen_tip("fishing_dock"):
				offer_tip("fishing_dock")
		# Edificios militares (feat/edificios-militares): el primero de cada uno.
		"infirmary", "smithy", "firing_range":
			var tip_id := String(info["data"].id)
			if not has_seen_tip(tip_id):
				offer_tip(tip_id)

## Un edificio se lleno sin recoger: para hasta que se recoge.
func _on_news_stock(node: Node, _stock: Dictionary) -> void:
	if has_seen_tip("collect_full") or node == null:
		return
	if ProductionManager.is_full(node):
		offer_tip("collect_full")

# ══════════════════════════════════════════════════════════════════════
# ── Combate guiado (2026-10-14, docs/23 §2.4, docs/15 §3) ──
# ══════════════════════════════════════════════════════════════════════
# Dos lecciones con marcas sobre el tablero de verdad, en las dos vistas (frente
# y tablero) y en el tablero 2D:
#
#   "basics"     la primera pelea con el tablero abierto (normalmente la primera
#                escaramuza: un infante contra uno debil). Pasos 1-5: tocar tu
#                unidad, moverte, atacar, mirar el turno enemigo, defender (solo
#                si te han dado).
#   "artillery"  la primera pelea con artilleria propia, ya hecha la de lo
#                basico. Pasos 6-7: el alcance minimo y el circulo de ventajas.
#
# Como el tutorial de la colonia: el paso SALE de lo que ha pasado
# (derive_combat_step, pura), no de un "Siguiente"; cada marca se cierra sola al
# hacer lo que pide. Ningun paso tiene "Saltar" (los 1-3 desde el 04-10; los
# 4-7 desde el 16-10, rama feat/tutorial-claro). Lo que se guarda es solo que
# lecciones se dieron: una pelea no se guarda nunca (CombatManager), asi que lo
# de dentro de la leccion es transitorio.
#
# No conoce a ningun panel: emite EventBus.combat_lesson_step_changed. Quien
# pinta es TutorialPanel; a donde senala, BattleScreen.coach_anchor().

const LESSON_BASICS := "basics"
const LESSON_ARTILLERY := "artillery"
const COMBAT_LESSONS := [LESSON_BASICS, LESSON_ARTILLERY]

## Los pasos de combate. `n`: el numero de "COMBATE · PASO n DE COMBAT_TOTAL".
## `target`: lo que senala BattleScreen.coach_anchor(). Ninguno tiene "Saltar"
## (2026-10-16: el combate guiado tampoco se salta). `ok`: tiene "Entendido" (un
## paso que solo se lee, y que solo se cierra con el). `circle`: dibuja el
## circulo de ventajas (TypeCircle) en la tarjeta.
const COMBAT_STEPS := {
	"c_select":      {"n": 1, "text": "CGUIDE_SELECT",      "target": "active_unit"},
	"c_move":        {"n": 2, "text": "CGUIDE_MOVE",        "target": "move_cell"},
	"c_attack":      {"n": 3, "text": "CGUIDE_ATTACK",      "target": "target_unit"},
	"c_attack_far":  {"n": 3, "text": "CGUIDE_ATTACK_FAR",  "target": "end_turn_button"},
	"c_enemy_turn":  {"n": 4, "text": "CGUIDE_ENEMY_TURN",  "target": "threat_button"},
	"c_defend":      {"n": 5, "text": "CGUIDE_DEFEND",      "target": "defend_button"},
	"c_art_range":   {"n": 6, "text": "CGUIDE_ART_RANGE",   "target": "active_unit"},
	"c_type_circle": {"n": 7, "text": "CGUIDE_TYPE_CIRCLE", "target": "", "ok": true, "circle": true},
}
const COMBAT_TOTAL := 7

## La leccion en marcha ("" ninguna), su paso y lo que ha pasado en ella.
var _lesson := ""
var _combat_step := ""
var _lesson_facts: Dictionary = {}

func _connect_combat_lessons() -> void:
	EventBus.turn_started.connect(_on_lesson_turn_started)
	EventBus.unit_moved.connect(func(uid, _f, _t): _on_lesson_action(uid, "moved"))
	EventBus.unit_attacked.connect(func(uid, _t, _d): _on_lesson_action(uid, "attacked"))
	EventBus.unit_defended.connect(func(uid): _on_lesson_action(uid, "defended"))
	EventBus.unit_died.connect(func(_uid, _side): _refresh_combat_step())
	EventBus.encounter_ended.connect(_on_lesson_encounter_ended)
	EventBus.encounter_closed.connect(func(): _clear_combat_lesson(true))

## Que leccion toca en el tablero que se acaba de abrir, o "". Pura: `player_units`
## son los ids de tipo de las unidades propias del tablero.
static func lesson_for(done: Array, player_units: Array) -> String:
	if not LESSON_BASICS in done:
		return LESSON_BASICS if not player_units.is_empty() else ""
	if not LESSON_ARTILLERY in done and player_units.has("artillery"):
		return LESSON_ARTILLERY
	return ""

## Empieza la leccion que toque en este tablero. true si empezo una.
func _begin_combat_lesson() -> bool:
	_clear_combat_lesson(true)
	if not CombatManager.is_board_open():
		return false
	var mine: Array = []
	for u in CombatManager.get_units():
		if u.side == 0 and u.is_alive():
			mine.append(u.unit_id)
	var lesson := lesson_for(combat_lessons_done, mine)
	if lesson == "":
		return false
	_lesson = lesson
	_lesson_facts = {}
	# El primer turno llega justo despues (turn_started): ahi se calcula el paso.
	return true

## La leccion en marcha, o "".
func combat_lesson() -> String:
	return _lesson

## El paso de combate en pantalla, o "".
func combat_step() -> String:
	return _combat_step

func is_combat_lesson_done(lesson: String) -> bool:
	return lesson in combat_lessons_done

static func combat_step_text(step_id: String) -> String:
	var e: Dictionary = COMBAT_STEPS.get(step_id, {})
	return Tr.ti(String(e.get("text", ""))) if not e.is_empty() else ""

static func combat_step_number(step_id: String) -> int:
	return int(COMBAT_STEPS.get(step_id, {}).get("n", 0))

static func combat_step_target(step_id: String) -> String:
	return String(COMBAT_STEPS.get(step_id, {}).get("target", ""))

static func combat_step_skippable(step_id: String) -> bool:
	return bool(COMBAT_STEPS.get(step_id, {}).get("skip", false))

static func combat_step_has_ok(step_id: String) -> bool:
	return bool(COMBAT_STEPS.get(step_id, {}).get("ok", false))

static func combat_step_has_circle(step_id: String) -> bool:
	return bool(COMBAT_STEPS.get(step_id, {}).get("circle", false))

static func _fact(f: Dictionary, key: String) -> bool:
	return bool(f.get(key, false))

## El paso que toca con estos hechos. Pura (las pruebas la llaman sin tablero).
##
## Hechos de la leccion (se quedan puestos): selected, moved, attacked,
## enemy_seen (un turno nuestro llego despues de uno enemigo), defend_closed,
## art_shown, circle_closed. Hechos del momento: player_turn, enemy_turn,
## can_move, has_targets, hurt (alguna nuestra ha perdido vida), art_active (le
## toca a una artilleria nuestra). Devuelve un paso, "" (nada que senalar ahora:
## esperar) o "done" (leccion acabada).
static func derive_combat_step(lesson: String, f: Dictionary) -> String:
	match lesson:
		LESSON_BASICS:
			if _fact(f, "enemy_turn"):
				return "" if _fact(f, "enemy_seen") else "c_enemy_turn"
			if not _fact(f, "player_turn"):
				return ""
			var acted: bool = _fact(f, "moved") or _fact(f, "attacked")
			if not (_fact(f, "selected") or acted):
				return "c_select"
			if not acted and _fact(f, "can_move"):
				return "c_move"
			if not _fact(f, "attacked"):
				return "c_attack" if _fact(f, "has_targets") else "c_attack_far"
			if not _fact(f, "enemy_seen"):
				return ""
			if _fact(f, "hurt") and not _fact(f, "defend_closed"):
				return "c_defend"
			return "done"
		LESSON_ARTILLERY:
			if not _fact(f, "art_shown"):
				return "c_art_range" if _fact(f, "player_turn") and _fact(f, "art_active") else ""
			if not _fact(f, "circle_closed"):
				return "c_type_circle"
			return "done"
	return "done"

## Los hechos de ahora: los de la leccion mas lo que dice el tablero.
func combat_facts() -> Dictionary:
	var f := _lesson_facts.duplicate()
	var active: CombatUnit = CombatManager.get_active_unit()
	var player_turn: bool = active != null and active.side == 0 and CombatManager.is_player_turn()
	f["player_turn"] = player_turn
	f["enemy_turn"] = active != null and active.side != 0 and CombatManager.is_in_encounter()
	f["can_move"] = player_turn and not CombatManager.get_valid_moves(active.uid).is_empty()
	f["has_targets"] = player_turn and not CombatManager.get_valid_targets(active.uid).is_empty()
	f["art_active"] = player_turn and active.unit_id == "artillery"
	var hurt := false
	for u in CombatManager.get_units():
		if u.side == 0 and u.is_alive() and u.hp < u.max_hp:
			hurt = true
			break
	f["hurt"] = hurt
	return f

## Un hecho de la leccion que ve la interfaz (BattleScreen: "selected" al tocar
## una pieza propia). Vale aunque la leccion aun no haya llegado a ese paso.
func note_combat_fact(fact: String) -> void:
	if _lesson == "" or fact == "":
		return
	_lesson_facts[fact] = true
	_refresh_combat_step()

## "Entendido" (y el reloj) del paso que solo se lee: el circulo.
func close_combat_step(step_id: String) -> void:
	if step_id == "" or step_id != _combat_step:
		return
	if step_id == "c_type_circle":
		note_combat_fact("circle_closed")

## API interna para sondas y pruebas: da por vistas esta leccion y las que
## queden. El jugador ya no tiene "Saltar" (2026-10-16); fuera del modo dev no
## hace nada, como skip_guide().
func skip_combat_lessons() -> void:
	if _lesson == "":
		return
	if not GameConfig.dev_mode:
		push_warning("TutorialManager.skip_combat_lessons(): solo en modo dev")
		return
	for l in COMBAT_LESSONS:
		if not l in combat_lessons_done:
			combat_lessons_done.append(l)
	_clear_combat_lesson(true)
	GameManager.request_save()

## "Repetir combate guiado" (indice de AYUDA): la proxima pelea vuelve a
## ensenar todo. Con un tablero abierto no hace nada (empezaria a media pelea).
func replay_combat_lessons() -> void:
	if CombatManager.is_board_open():
		return
	combat_lessons_done.clear()
	_clear_combat_lesson(false)

func _on_lesson_turn_started(side: int, _uid: int) -> void:
	if _lesson == "":
		return
	if side == 0:
		if _fact(_lesson_facts, "_enemy_turn_seen"):
			_lesson_facts["enemy_seen"] = true
	else:
		_lesson_facts["_enemy_turn_seen"] = true
	# Pasar el turno (ESPERAR, TERMINAR) tambien cierra lo que se leia.
	_close_reading_steps()
	_refresh_combat_step()

func _on_lesson_action(uid: int, what: String) -> void:
	if _lesson == "":
		return
	var u: CombatUnit = CombatManager.get_unit(uid)
	if u != null and u.side == 0:
		_lesson_facts[what] = true
		_close_reading_steps()
	_refresh_combat_step()

## Los pasos que se cierran con cualquier accion nuestra: "defender" (era un
## aviso) y la zona de tiro de la artilleria (se cierra al actuar ella).
func _close_reading_steps() -> void:
	match _combat_step:
		"c_defend":
			_lesson_facts["defend_closed"] = true
		"c_art_range":
			_lesson_facts["art_shown"] = true

func _on_lesson_encounter_ended(_victory: bool, _turns: int) -> void:
	if _lesson == "":
		return
	# La pelea acabo. Lo basico cuenta como dado si el jugador llego a atacar
	# (lo demas esta en AYUDA): abandonar o perder antes de hacerlo no la gasta,
	# vuelve en la proxima pelea (2026-10-16: no se salta huyendo). La de
	# artilleria solo si llego a ensenar su alcance; si la pieza ni actuo, espera
	# a la proxima pelea con artilleria.
	var basics_done: bool = _lesson == LESSON_BASICS and _fact(_lesson_facts, "attacked")
	var artillery_done: bool = _lesson == LESSON_ARTILLERY and _fact(_lesson_facts, "art_shown")
	if basics_done or artillery_done:
		_finish_lesson()
	else:
		_clear_combat_lesson(false)
	_set_combat_step("")

func _refresh_combat_step() -> void:
	if _lesson == "":
		return
	var step := derive_combat_step(_lesson, combat_facts())
	if step == "done":
		_finish_lesson()
		step = ""
	_set_combat_step(step)

func _finish_lesson() -> void:
	if _lesson != "" and not _lesson in combat_lessons_done:
		combat_lessons_done.append(_lesson)
		# La leccion va en la partida aunque la pelea no se guarde.
		GameManager.request_save()
	_lesson = ""
	_lesson_facts = {}

func _set_combat_step(step: String) -> void:
	if step == _combat_step:
		return
	_combat_step = step
	EventBus.combat_lesson_step_changed.emit(step)

## Tira la leccion en marcha sin darla por hecha. `notify`: avisa al panel.
func _clear_combat_lesson(notify: bool) -> void:
	_lesson = ""
	_lesson_facts = {}
	if notify:
		_set_combat_step("")
	else:
		_combat_step = ""
