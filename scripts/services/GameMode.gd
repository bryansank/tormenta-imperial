class_name GameMode
extends RefCounted
## El modo de la partida en curso y las reglas que de el se siguen. UNICA fuente
## de verdad: ningun servicio pregunta `if mode == ...`; pregunta una regla
## (`storm_enabled()`, `offline_enabled()`...) y la tabla decide.
##
## La tabla vive en `GameConfig.game_mode_rules` (es balance); aqui solo el
## estado y las consultas. No es un autoload a proposito: son dos variables
## estaticas y unas funciones puras, y GameConfig (autoload #2) tiene que poder
## leerlas desde sus getters sin depender del orden de carga.
##
## El modo es fijo para toda la partida: solo lo cambia empezar una nueva
## (`GameManager.start_new_game(mode)`) o cargar un guardado (que lo trae
## escrito). Un guardado sin la clave es de antes de los modos: Campana.
##
## Estado persistido: el modo, el nivel (Colono / Gobernador) y, en
## Supervivencia, si la partida ya termino. Lo guarda y lo restaura GameManager;
## `begin_run()` es su reset.
##
## El NIVEL es una dificultad sobre la Campana, no un modo mas: "Colono" es el
## juego de siempre (para chavales de 10-15 y para cualquiera que empiece) y
## "Gobernador" el complejo, para quien sabe de economia. Se desbloquea por
## perfil (GameConfig.profile_*, en settings.cfg, nunca en la partida) y queda
## fijo para la partida. Sus reglas viven en `GameConfig.game_tier_rules`.

enum Mode { CAMPAIGN, BUILDER, SURVIVAL, SANDBOX }

## Las claves con que viaja en el guardado. Texto y no el entero del enum: un
## guardado se lee a mano, y reordenar el enum no puede cambiar el modo de nadie.
const KEYS := {
	Mode.CAMPAIGN: "campaign",
	Mode.BUILDER: "builder",
	Mode.SURVIVAL: "survival",
	Mode.SANDBOX: "sandbox",
}
const DEFAULT := Mode.CAMPAIGN
## El orden en que el selector los ensena.
const ORDER := [Mode.CAMPAIGN, Mode.BUILDER, Mode.SURVIVAL, Mode.SANDBOX]
## Los que el selector de Nueva partida ofrece hoy. Constructor, Supervivencia y
## Sandbox siguen enteros (reglas, guardado, pruebas, y un guardado viejo en
## esos modos carga igual), pero apartados del selector desde el 2026-09-28: la
## partida normal es la Campana, y los otros tres esperan a que se decida su
## sitio. Para devolver uno, quitarle el comentario.
const OFFERED := [
	Mode.CAMPAIGN,
	# Mode.BUILDER,
	# Mode.SURVIVAL,
	# Mode.SANDBOX,
]

const RESULT_NONE := ""
const RESULT_DEFEAT := "defeat"

## Niveles de la Campana. Ver docs/20-modos-de-juego.md, "Colono y Gobernador".
enum Tier { COLONIST, GOVERNOR }
const TIER_KEYS := {
	Tier.COLONIST: "colonist",
	Tier.GOVERNOR: "governor",
}
const TIER_DEFAULT := Tier.COLONIST

static var current: int = DEFAULT
## El nivel de la partida. Fuera de la Campana siempre es Colono.
static var tier: int = TIER_DEFAULT
## La partida termino y ya no se puede seguir (Supervivencia perdida). El
## guardado se conserva, marcado, y deja de escribirse.
static var run_result: String = RESULT_NONE

# ── Estado ───────────────────────────────────────────────────────────

## Empieza una partida en `mode` (y `run_tier`). Es el reset: tira el resultado
## anterior. Sin nivel, Colono: quien reinicia la partida en curso pasa el suyo
## (`begin_run(current, tier)`).
static func begin_run(mode: int, run_tier: int = TIER_DEFAULT) -> void:
	current = mode if KEYS.has(mode) else DEFAULT
	tier = run_tier if (TIER_KEYS.has(run_tier) and tier_allowed(current)) else TIER_DEFAULT
	run_result = RESULT_NONE

## Gobernador es una dificultad de la Campana; los otros modos no tienen niveles.
static func tier_allowed(mode: int) -> bool:
	return mode == Mode.CAMPAIGN

static func is_governor() -> bool:
	return tier == Tier.GOVERNOR

## Si el selector ofrece Gobernador: lo abre el perfil (haber terminado o ganado
## una partida, GameConfig.governor_unlocked_by_profile) y, en dev_mode, siempre.
static func governor_unlocked() -> bool:
	return GameConfig.dev_mode or GameConfig.governor_unlocked_by_profile()

static func tier_key_of(t: int) -> String:
	return String(TIER_KEYS.get(t, TIER_KEYS[TIER_DEFAULT]))

static func tier_from_key(key: String) -> int:
	for t in TIER_KEYS:
		if TIER_KEYS[t] == key:
			return t
	return TIER_DEFAULT

static func is_offered(mode: int) -> bool:
	return OFFERED.has(mode)

static func is_run_over() -> bool:
	return run_result != RESULT_NONE

## Da la partida por terminada. Solo la llama quien sabe que no hay vuelta atras.
static func finish_run(result: String) -> void:
	run_result = result

static func key_of(mode: int) -> String:
	return String(KEYS.get(mode, KEYS[DEFAULT]))

## Una clave desconocida (guardado tocado a mano, modo de una version futura)
## cae en Campana, que es lo que ese guardado seria sin la clave.
static func from_key(key: String) -> int:
	for mode in KEYS:
		if KEYS[mode] == key:
			return mode
	return DEFAULT

static func current_key() -> String:
	return key_of(current)

# ── Persistencia ─────────────────────────────────────────────────────

static func get_save_data() -> Dictionary:
	return {"mode": current_key(), "result": run_result, "tier": tier_key_of(tier)}

## Sin datos (guardado anterior a los modos) = Campana en curso. Sin "tier"
## (guardado anterior a los niveles) = Colono.
static func load_save_data(data: Dictionary) -> void:
	var tier_raw: Variant = data.get("tier", TIER_KEYS[TIER_DEFAULT])
	begin_run(from_key(String(data.get("mode", KEYS[DEFAULT]))),
		tier_from_key(String(tier_raw)) if tier_raw is String else TIER_DEFAULT)
	var result: Variant = data.get("result", RESULT_NONE)
	run_result = String(result) if result is String else RESULT_NONE

# ── Reglas ───────────────────────────────────────────────────────────

## Una regla del modo en curso (o de `mode`). Lo que un modo no dice lo dice la
## Campana: la tabla solo lista lo que cambia.
static func rule(name: String, mode: int = -1) -> Variant:
	var m: int = current if mode < 0 else mode
	var rules: Dictionary = GameConfig.game_mode_rules
	var own: Dictionary = rules.get(key_of(m), {})
	if own.has(name):
		return own[name]
	return rules.get(key_of(DEFAULT), {}).get(name, null)

static func _flag(name: String) -> bool:
	return bool(rule(name))

static func _num(name: String) -> float:
	var v: Variant = rule(name)
	return float(v) if v != null else 1.0

## El reloj de la Tormenta corre solo. En Constructor y Sandbox no.
static func storm_enabled() -> bool:
	return _flag("storm")

## La tormenta de prueba de la era 1 (sin Diezmo). En Constructor y Sandbox no.
static func storm_trial_enabled() -> bool:
	return _flag("storm_trial")

## Los Tasadores cobran al final de una tormenta.
static func tithe_enabled() -> bool:
	return _flag("tithe")

## El Cuartel General a nivel 3 convoca la Auditoria Final.
static func audit_enabled() -> bool:
	return _flag("audit_on_capstone")

## El Cuartel General a nivel 3 gana la partida sin asedio (Constructor).
static func capstone_wins() -> bool:
	return _flag("capstone_wins")

## Ganar (el asedio o el Cuartel) muestra la victoria. En Sandbox no hay victoria.
static func victory_enabled() -> bool:
	return _flag("victory")

## Perder la Auditoria deja volver a convocarla. En Supervivencia, no: la partida
## termina.
static func resummon_allowed() -> bool:
	return _flag("resummon")

static func offline_enabled() -> bool:
	return _flag("offline")

static func random_events_enabled() -> bool:
	return _flag("random_events")

## Los eventos de categoria "danger" (tormenta menor, plaga, bandidos...).
static func danger_events_enabled() -> bool:
	return _flag("danger_events")

static func infinite_resources() -> bool:
	return _flag("infinite_resources")

## Todas las eras, edificios y tecnologias desde el principio, sin limites.
static func all_unlocked() -> bool:
	return _flag("all_unlocked")

## Las herramientas de Sandbox (invocar tormenta / auditoria a mano).
static func sandbox_tools() -> bool:
	return _flag("sandbox_tools")

static func storm_interval_mult() -> float:
	return _num("storm_interval_mult")

static func storm_severity_bonus() -> int:
	var v: Variant = rule("storm_severity_bonus")
	return int(v) if v != null else 0

static func storm_damage_mult() -> float:
	return _num("storm_damage_mult")

static func tithe_mult() -> float:
	return _num("tithe_mult")

## Los recursos de salida del modo, ya escalados.
static func starting_resources() -> Dictionary:
	var fixed: Variant = rule("starting_resources")
	if fixed is Dictionary and not (fixed as Dictionary).is_empty():
		return (fixed as Dictionary).duplicate()
	var mult: float = _num("starting_resources_mult")
	var out := {}
	for res in GameConfig.starting_resources:
		out[res] = int(round(float(GameConfig.starting_resources[res]) * mult))
	return out

## Los consejos del tutorial que el modo no ensena (hablan de algo que no pasa).
static func tip_allowed(tip_id: String) -> bool:
	var hidden: Variant = rule("hidden_tips")
	return not (hidden is Array and tip_id in hidden)

# ── Reglas del nivel (Colono / Gobernador) ───────────────────────────

## Una regla del nivel en curso (o de `t`). Lo que Gobernador no dice lo dice
## Colono, igual que la tabla de modos.
static func tier_rule(name: String, t: int = -1) -> Variant:
	var which: int = tier if t < 0 else t
	var rules: Dictionary = GameConfig.game_tier_rules
	var own: Dictionary = rules.get(tier_key_of(which), {})
	if own.has(name):
		return own[name]
	return rules.get(tier_key_of(TIER_DEFAULT), {}).get(name, null)

static func _tier_num(name: String) -> float:
	var v: Variant = tier_rule(name)
	return float(v) if v != null else 1.0

## Lo acumulado en un edificio sin recoger se estropea con el tiempo. La
## mecanica la pone feat/comida-granja-recoger; aqui solo la regla.
static func spoilage_enabled() -> bool:
	return bool(tier_rule("spoilage"))

## El mercado sigue el calendario de la Tormenta y ensena el spread y la
## tendencia (MarketManager / MarketPanel).
static func market_dynamic() -> bool:
	return bool(tier_rule("market_dynamic"))

## Enemigos y defensa mas duros: mismas reglas de CombatRules, mas escala.
static func combat_hard() -> bool:
	return bool(tier_rule("combat_hard"))

## Multiplicador de la escala (vida y ataque) de los enemigos de expedicion.
static func expedition_enemy_mult() -> float:
	return _tier_num("expedition_enemy_mult") if combat_hard() else 1.0

## Multiplicador de los cuerpos que bajan a cobrar el Diezmo.
static func tithe_force_mult() -> float:
	return _tier_num("tithe_force_mult") if combat_hard() else 1.0

## Multiplicador de la escala de cada oleada de la Auditoria Final.
static func audit_enemy_mult() -> float:
	return _tier_num("audit_enemy_mult") if combat_hard() else 1.0

# ── Textos ───────────────────────────────────────────────────────────

static func name_key(mode: int = -1) -> String:
	return "MODE_%s_NAME" % key_of(current if mode < 0 else mode).to_upper()

static func desc_key(mode: int = -1) -> String:
	return "MODE_%s_DESC" % key_of(current if mode < 0 else mode).to_upper()

static func tag_key(mode: int = -1) -> String:
	return "MODE_%s_TAG" % key_of(current if mode < 0 else mode).to_upper()

static func goal_key(mode: int = -1) -> String:
	return "MODE_%s_GOAL" % key_of(current if mode < 0 else mode).to_upper()

static func display_name(mode: int = -1) -> String:
	return Tr.t(name_key(mode))

static func tier_name_key(t: int = -1) -> String:
	return "TIER_%s_NAME" % tier_key_of(tier if t < 0 else t).to_upper()

static func tier_desc_key(t: int = -1) -> String:
	return "TIER_%s_DESC" % tier_key_of(tier if t < 0 else t).to_upper()

## "Campana" o "Campana · Gobernador": lo que la confirmacion dice que se pierde.
static func display_name_with_tier(mode: int = -1, t: int = -1) -> String:
	var m: int = current if mode < 0 else mode
	var which: int = tier if t < 0 else t
	if not tier_allowed(m) or which == TIER_DEFAULT:
		return display_name(m)
	return "%s · %s" % [display_name(m), Tr.t(tier_name_key(which))]
