extends Node
## El tutorial del juego: una intro paginada al empezar (el lore entero, y luego
## como se juega) y un consejo la primera vez que pasa cada cosa.
##
## Existe porque el lore y la guia estaban escritos fuera del juego y dentro no
## habia nada que dijera quien eres ni que hacer: la primera Tormenta se sintio
## como ruido. La regla es una: cada texto sale UNA vez por partida. Repetir un
## consejo lo convierte en mobiliario, y el jugador deja de leerlo.
##
## Estado persistido EN LA PARTIDA, no en las preferencias: una partida nueva es
## un jugador que no sabe nada otra vez. `reset()` en los tres sitios de
## GameManager, guardado y cargado con el resto de servicios.
##
## No conoce a ningun panel: emite en EventBus y TutorialPanel escucha.

var intro_seen: bool = false
var tips_seen: Array[String] = []

## Consejos contextuales: id -> claves de Tr. El disparador vive en _ready().
## Los ids son los que se guardan en la partida, asi que no se renombran a la
## ligera: un id cambiado hace que el consejo vuelva a salir en partidas viejas.
const TIPS := {
	"storm_incoming": {"title": "TUT_TIP_INCOMING_TITLE", "body": "TUT_TIP_INCOMING_BODY"},
	"storm_ash":      {"title": "TUT_TIP_ASH_TITLE",      "body": "TUT_TIP_ASH_BODY"},
	"storm_started":  {"title": "TUT_TIP_STORM_TITLE",    "body": "TUT_TIP_STORM_BODY"},
	"tithe":          {"title": "TUT_TIP_TITHE_TITLE",    "body": "TUT_TIP_TITHE_BODY"},
	"ruined":         {"title": "TUT_TIP_RUINED_TITLE",   "body": "TUT_TIP_RUINED_BODY"},
	"overflow":       {"title": "TUT_TIP_OVERFLOW_TITLE", "body": "TUT_TIP_OVERFLOW_BODY"},
	"encounter":      {"title": "TUT_TIP_BOARD_TITLE",    "body": "TUT_TIP_BOARD_BODY"},
}

func _ready() -> void:
	EventBus.game_new_started.connect(_on_game_started)
	# Tambien al cargar: una partida guardada antes de que existiera el tutorial
	# no tiene la intro vista, y ese jugador es justo el que se quejo de no
	# entender nada. Con la marca puesta no hace nada.
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

# ── Intro ────────────────────────────────────────────────────────────

func _on_game_started() -> void:
	if intro_seen:
		return
	# Diferido a proposito: game_new_started se emite mientras la escena aun
	# esta en _ready (BuildingPlacer y MapGenerator registran desde el suyo) y
	# TutorialPanel es el ultimo nodo de Main.tscn. Emitir ahora seria hablarle
	# a un panel que todavia no escucha.
	show_intro.call_deferred()

## Publico: vuelve a abrir el lore. Pensado para un futuro boton "HISTORIA".
## No toca `intro_seen`: eso lo decide el cierre, no la apertura.
func show_intro() -> void:
	EventBus.tutorial_intro_requested.emit()

func _on_intro_closed() -> void:
	intro_seen = true

# ── Consejos ─────────────────────────────────────────────────────────

## Ensena `tip_id` si no se habia ensenado en esta partida. Se marca al emitir,
## no al pulsar "Entendido": si el jugador lo ignora, ya lo vio.
func offer_tip(tip_id: String) -> void:
	if tip_id in tips_seen:
		return
	if not TIPS.has(tip_id):
		push_warning("TutorialManager: consejo desconocido '%s'" % tip_id)
		return
	tips_seen.append(tip_id)
	var keys: Dictionary = TIPS[tip_id]
	EventBus.tutorial_tip_requested.emit(tip_id, Tr.t(keys["title"]), Tr.t(keys["body"]))

func has_seen_tip(tip_id: String) -> bool:
	return tip_id in tips_seen

func _on_storm_incoming(_seconds: float) -> void:
	offer_tip("storm_incoming")

func _on_storm_ash_started() -> void:
	offer_tip("storm_ash")

func _on_storm_started(_severity: int) -> void:
	offer_tip("storm_started")

func _on_tithe_demanded(_severity: int) -> void:
	offer_tip("tithe")

func _on_building_ruined(_node: Node3D) -> void:
	offer_tip("ruined")

func _on_storage_overflow(_resource: String, _lost: int, _cap: int) -> void:
	offer_tip("overflow")

func _on_encounter_started(_index: int, _is_boss: bool) -> void:
	offer_tip("encounter")

# ── Persistencia ─────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"intro_seen": intro_seen,
		"tips_seen": tips_seen.duplicate(),
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
	for tip in data.get("tips_seen", []):
		if tip is String and not tip in tips_seen:
			tips_seen.append(tip)

## Partida nueva: nadie sabe nada otra vez. Tira el estado, no notifica: la
## intro la pide game_new_started, que llega despues.
func reset() -> void:
	intro_seen = false
	tips_seen.clear()
