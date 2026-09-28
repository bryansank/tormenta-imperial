extends RefCounted
## El catalogo de todas las ayudas del juego: los globos que apuntan al HUD, las
## tarjetas de consejo que salen la primera vez que pasa algo y las guias basicas
## (lo que antes eran las paginas "Como se juega" de la intro).
##
## Existe para que el indice de AYUDA (HelpIndexPanel) y quien las ensena
## (HelperPanel) hablen de lo mismo con un solo id. Solo datos y lecturas: ni
## nodos ni senales. Quien decide CUANDO sale cada una es HelperPanel; que se ha
## visto lo guarda TutorialManager en la partida.
##
## Tipos:
##   callout  globo junto a un control del HUD (su hueco lo pone UILayoutConfig)
##   tip      tarjeta de consejo (TutorialManager.TIPS): sale una vez, por evento
##   guide    guia basica: siempre en el indice, nunca sale sola
##
## Para anadir una: una entrada aqui, sus claves Tr (ES y EN) y, si es un
## consejo, su disparador en TutorialManager.

const CAT_BASICS := "basics"
const CAT_ECONOMY := "economy"
const CAT_STORM := "storm"
const CAT_ARMY := "army"
## Orden de las categorias en el indice.
const CATEGORIES := [CAT_BASICS, CAT_ECONOMY, CAT_STORM, CAT_ARMY]
const CATEGORY_KEYS := {
	CAT_BASICS: "HELP_CAT_BASICS",
	CAT_ECONOMY: "HELP_CAT_ECONOMY",
	CAT_STORM: "HELP_CAT_STORM",
	CAT_ARMY: "HELP_CAT_ARMY",
}

## id -> entrada. `title`/`body` son claves de Tr; el cuerpo se lee con Tr.ti,
## asi que una variante `_TOUCH` habla de dedos en tablet. `target` es el control
## al que apunta (ver HelpTargets). `basic`: sale en el indice aunque no se haya
## visto. `needs`: regla de modo que la esconde (GameMode.tip_allowed del id que
## se nombra), para que Constructor no ensene la Tormenta.
const ENTRIES := {
	# ── Globos del HUD ──
	"callout_build": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_BUILD", "body": "HELP_B_BUILD", "target": "build_button"},
	"callout_objective": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_OBJECTIVE", "body": "HELP_B_OBJECTIVE", "target": "objective"},
	"callout_resources": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_RESOURCES", "body": "LBL_HELP_RESOURCES_POOL", "target": "resources"},
	"callout_camera": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_CAMERA", "body": "LBL_HELP_CAMERA_DESKTOP", "target": ""},
	"callout_zoom": {"kind": "callout", "cat": CAT_BASICS, "basic": false,
		"title": "HELP_T_ZOOM", "body": "LBL_HELP_ZOOM", "target": "", "touch_only": true},
	"callout_menus": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_MENUS", "body": "HELP_B_MENUS", "target": "menu_button"},
	"callout_skirmish": {"kind": "callout", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_SKIRMISH", "body": "LBL_HELP_SKIRMISH", "target": ""},
	# ── Guias basicas (las antiguas paginas "Como se juega") ──
	"guide_first_steps": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "TUT_PLAY_1_TITLE", "body": "HELP_B_FIRST_STEPS", "target": "build_button"},
	"guide_pool": {"kind": "guide", "cat": CAT_ECONOMY, "basic": true,
		"title": "TUT_PLAY_2_TITLE", "body": "TUT_PLAY_2_BODY", "target": "resources"},
	"guide_storm": {"kind": "guide", "cat": CAT_STORM, "basic": true,
		"title": "TUT_PLAY_3_TITLE", "body": "HELP_B_STORM", "target": "storm", "needs": "storm_started"},
	"guide_army": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "TUT_PLAY_4_TITLE", "body": "HELP_B_ARMY", "target": ""},
	# ── Consejos de TutorialManager.TIPS ──
	"overflow": {"kind": "tip", "cat": CAT_ECONOMY, "basic": false,
		"title": "TUT_TIP_OVERFLOW_TITLE", "body": "TUT_TIP_OVERFLOW_BODY", "target": "resources"},
	"consumption": {"kind": "tip", "cat": CAT_ECONOMY, "basic": false,
		"title": "TUT_TIP_CONSUMPTION_TITLE", "body": "HELP_TIP_CONSUMPTION_BODY", "target": "status"},
	"market": {"kind": "tip", "cat": CAT_ECONOMY, "basic": false,
		"title": "TUT_TIP_MARKET_TITLE", "body": "TUT_TIP_MARKET_BODY", "target": ""},
	"tech_tree": {"kind": "tip", "cat": CAT_ECONOMY, "basic": false,
		"title": "TUT_TIP_TECH_TITLE", "body": "TUT_TIP_TECH_BODY", "target": ""},
	"storm_incoming": {"kind": "tip", "cat": CAT_STORM, "basic": false,
		"title": "TUT_TIP_INCOMING_TITLE", "body": "TUT_TIP_INCOMING_BODY", "target": "storm"},
	"storm_ash": {"kind": "tip", "cat": CAT_STORM, "basic": false,
		"title": "TUT_TIP_ASH_TITLE", "body": "TUT_TIP_ASH_BODY", "target": "storm"},
	"storm_started": {"kind": "tip", "cat": CAT_STORM, "basic": false,
		"title": "TUT_TIP_STORM_TITLE", "body": "TUT_TIP_STORM_BODY", "target": "storm"},
	"tithe": {"kind": "tip", "cat": CAT_STORM, "basic": false,
		"title": "TUT_TIP_TITHE_TITLE", "body": "HELP_TIP_TITHE_BODY", "target": "storm"},
	"ruined": {"kind": "tip", "cat": CAT_STORM, "basic": false,
		"title": "TUT_TIP_RUINED_TITLE", "body": "TUT_TIP_RUINED_BODY", "target": ""},
	"barracks": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_BARRACKS_TITLE", "body": "HELP_TIP_BARRACKS_BODY", "target": ""},
	"upkeep": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_UPKEEP_TITLE", "body": "TUT_TIP_UPKEEP_BODY", "target": ""},
	"encounter": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_BOARD_TITLE", "body": "TUT_TIP_BOARD_BODY", "target": ""},
	"expedition_map": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_MAP_TITLE", "body": "TUT_TIP_MAP_BODY", "target": ""},
	"final_audit": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_AUDIT_TITLE", "body": "HELP_TIP_AUDIT_BODY", "target": ""},
}

## Prioridad de los globos que salen solos: mayor sale antes. Los consejos van
## siempre por delante (TIP_PRIORITY): explican algo que acaba de pasar.
const TIP_PRIORITY := 100
const PRIORITY := {
	"callout_skirmish": 60,
	"callout_build": 50,
	"callout_objective": 40,
	"callout_resources": 30,
	"callout_camera": 20,
	"callout_zoom": 15,
	"callout_menus": 10,
}

## Segundos que dura una ayuda en pantalla antes de cerrarse sola: de 6 a 12,
## segun lo que haya que leer (unos 25 caracteres por segundo, y 6 de base).
const AUTO_CLOSE_MIN := 6.0
const AUTO_CLOSE_MAX := 12.0
const READ_CHARS_PER_SEC := 25.0

static func has(id: String) -> bool:
	return ENTRIES.has(id)

static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})

static func kind(id: String) -> String:
	return String(entry(id).get("kind", ""))

static func category(id: String) -> String:
	return String(entry(id).get("cat", CAT_BASICS))

static func is_basic(id: String) -> bool:
	return bool(entry(id).get("basic", false))

static func target(id: String) -> String:
	return String(entry(id).get("target", ""))

static func title(id: String) -> String:
	var key := String(entry(id).get("title", ""))
	return Tr.t(key) if key != "" else id

## El texto, con la variante tactil si toca. El globo de camara cambia de texto
## segun haya flechas en pantalla o no: con flechas habla de ellas.
static func body(id: String) -> String:
	if id == "callout_camera" and GameConfig.touch_controls_enabled():
		return Tr.ti("LBL_HELP_CAMERA")
	var key := String(entry(id).get("body", ""))
	return Tr.ti(key) if key != "" else ""

static func priority(id: String) -> int:
	if kind(id) == "tip":
		return TIP_PRIORITY
	return int(PRIORITY.get(id, 0))

## Cuanto dura en pantalla un texto de esta longitud.
static func auto_close_seconds(text: String) -> float:
	return clampf(AUTO_CLOSE_MIN + float(text.length()) / READ_CHARS_PER_SEC, AUTO_CLOSE_MIN, AUTO_CLOSE_MAX)

## El modo de juego la permite. Un consejo lo decide GameMode.tip_allowed; una
## guia, por el consejo que nombra en `needs`.
static func allowed(id: String) -> bool:
	var e := entry(id)
	if e.is_empty():
		return false
	if String(e.get("kind", "")) == "tip":
		return GameMode.tip_allowed(id)
	var needs := String(e.get("needs", ""))
	if needs != "":
		return GameMode.tip_allowed(needs)
	return true

static func ids_in(cat: String) -> Array:
	var out: Array = []
	for id in ENTRIES:
		if category(id) == cat:
			out.append(id)
	return out
