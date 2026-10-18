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

const BuildingHelpText := preload("res://scripts/ui/BuildingHelpText.gd")

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
	# ── La meta y los edificios del principio (2026-10-16, rama feat/tutorial-claro):
	# lo mismo que dicen la primera y la ultima tarjeta del tutorial y sus pasos ──
	"guide_goal": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_GOAL", "body": "HELP_B_GOAL", "target": "objective"},
	"guide_start_buildings": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_START_BUILDINGS", "body": "HELP_B_START_BUILDINGS", "target": "build_button"},
	# Girar, mover y derribar (lo que ensena el tutorial en sus pasos 6-8) y los
	# danos (la leccion de reparar). La de reparar solo donde hay Tormenta.
	"guide_rotate": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_ROTATE", "body": "HELP_B_ROTATE", "target": "build_button"},
	"guide_move": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_MOVE", "body": "HELP_B_MOVE", "target": ""},
	"guide_demolish": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_DEMOLISH", "body": "HELP_B_DEMOLISH", "target": ""},
	"guide_repair": {"kind": "guide", "cat": CAT_STORM, "basic": true,
		"title": "HELP_T_REPAIR", "body": "HELP_B_REPAIR", "target": "", "needs": "storm_started"},
	# ── Guia rapida (2026-09-28): los cuatro bloques de la pantalla del inicio ──
	"guide_qg_resources": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "QG_RESOURCES_T", "body": "QG_RESOURCES_B", "target": "resources"},
	"guide_qg_extract": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "QG_EXTRACT_T", "body": "QG_EXTRACT_B", "target": ""},
	"guide_qg_buildings": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "QG_BUILDINGS_T", "body": "QG_BUILDINGS_B", "target": "build_button"},
	"guide_qg_progress": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "QG_PROGRESS_T", "body": "QG_PROGRESS_B", "target": "objective"},
	# Mantener pulsado para leer (TouchTooltip): el pie de la guia rapida.
	"guide_read": {"kind": "guide", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_READ", "body": "QG_READ_HINT", "target": ""},
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
		"title": "TUT_TIP_CONSUMPTION_TITLE", "body": "HELP_TIP_CONSUMPTION_BODY", "target": "workers"},
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
	# La primera unidad sale del cuartel: ESCARAMUZAS vive en ☰ MENU > COLONIA,
	# asi que el marco senala el boton del menu (docs/15-combat.md §4).
	"first_sortie": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_FIRST_SORTIE_TITLE", "body": "TUT_TIP_FIRST_SORTIE_BODY", "target": "menu_button"},
	"final_audit": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "TUT_TIP_AUDIT_TITLE", "body": "HELP_TIP_AUDIT_BODY", "target": ""},
	# ── Novedades (2026-10-14): basicas, asi estan en el indice desde el principio ──
	"saves": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_SAVES", "body": "HELP_B_SAVES", "target": "menu_button"},
	"callout_speed": {"kind": "callout", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_SPEED", "body": "HELP_B_SPEED", "target": "speed_button"},
	"rank": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_RANK", "body": "HELP_B_RANK", "target": "rank_badge"},
	"flag": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_FLAG", "body": "HELP_B_FLAG", "target": "menu_button"},
	"island": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_ISLAND", "body": "HELP_B_ISLAND", "target": ""},
	"night": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_NIGHT", "body": "HELP_B_NIGHT", "target": ""},
	"bug_report": {"kind": "tip", "cat": CAT_BASICS, "basic": true,
		"title": "HELP_T_BUG", "body": "HELP_B_BUG", "target": "menu_button"},
	"farm": {"kind": "tip", "cat": CAT_ECONOMY, "basic": true,
		"title": "HELP_T_FARM", "body": "HELP_B_FARM", "target": ""},
	"collect_full": {"kind": "tip", "cat": CAT_ECONOMY, "basic": true,
		"title": "HELP_T_COLLECT", "body": "HELP_B_COLLECT", "target": ""},
	# Muelle de pesca (feat/muelle-pesca): sale al terminar el primero.
	"fishing_dock": {"kind": "tip", "cat": CAT_ECONOMY, "basic": true,
		"title": "HELP_T_FISHING_DOCK", "body": "HELP_B_FISHING_DOCK", "target": ""},
	# Edificios militares (feat/edificios-militares): salen al terminar el primero.
	"infirmary": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_INFIRMARY", "body": "HELP_B_INFIRMARY", "target": ""},
	"smithy": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_SMITHY", "body": "HELP_B_SMITHY", "target": ""},
	"firing_range": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_FIRING_RANGE", "body": "HELP_B_FIRING_RANGE", "target": ""},
	# ── Ensenar el combate (2026-10-14, rama feat/ensenar-combate, docs/23 §2.4) ──
	# Guias basicas: siempre en el indice. Lo mismo que cuentan las marcas del
	# combate guiado y la ficha de unidad, para leerlo con calma.
	"guide_combat_units": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_COMBAT_UNITS", "body": "HELP_B_COMBAT_UNITS", "target": ""},
	"guide_combat_move": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_COMBAT_MOVE", "body": "HELP_B_COMBAT_MOVE", "target": ""},
	"guide_type_advantage": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_TYPE_ADVANTAGE", "body": "HELP_B_TYPE_ADVANTAGE", "target": ""},
	"guide_artillery_range": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_ARTILLERY_RANGE", "body": "HELP_B_ARTILLERY_RANGE", "target": ""},
	"guide_combat_previews": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_COMBAT_PREVIEWS", "body": "HELP_B_COMBAT_PREVIEWS", "target": ""},
	"guide_combat_defend": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_COMBAT_DEFEND", "body": "HELP_B_COMBAT_DEFEND", "target": ""},
	# ── Aire y mar (feat/aire-mar-reglas, docs/15 §11) ──
	# El consejo sale al levantar el primer Astillero o Aerodromo; la guia de
	# ventajas esta en el indice desde el principio, junto a "Quien gana a quien".
	"air_sea": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_AIR_SEA", "body": "HELP_B_AIR_SEA", "target": ""},
	"guide_air_sea_advantage": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_AIR_SEA_ADVANTAGE", "body": "HELP_B_AIR_SEA_ADVANTAGE", "target": ""},
	# ── Tres campanas (feat/tres-campanas, docs/15 §13) ──
	# La pagina "Las tres campanas" esta en el indice desde el principio; el
	# consejo sale al ganar la primera escaramuza (se abre la de Tierra). "Que
	# pide el Ataque Final" sale en la era 3 o al llegar el CG a nivel 3 sin las
	# campanas; tambien esta en el indice (solo donde hay asedio).
	"guide_campaigns": {"kind": "guide", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_CAMPAIGNS", "body": "HELP_B_CAMPAIGNS", "target": ""},
	"campaigns": {"kind": "tip", "cat": CAT_ARMY, "basic": false,
		"title": "HELP_T_CAMPAIGNS", "body": "HELP_B_CAMPAIGNS", "target": ""},
	"final_gate": {"kind": "tip", "cat": CAT_ARMY, "basic": true,
		"title": "HELP_T_FINAL_GATE", "body": "HELP_B_FINAL_GATE", "target": "", "needs": "final_audit"},
	# ── Topes y mejoras (2026-10-17, rama feat/topes-mejoras-ayuda) ──
	# Paginas con numeros: `dyn` = el cuerpo lo escribe BuildingHelpText leyendo
	# GameConfig (topes por era, multiplicadores de mejora, repuestos, torres,
	# recetas), no una clave fija; `body` es su resumen de una linea (el tooltip
	# del indice, summary()). El indice las abre como pagina (sin reloj),
	# porque son largas para la tarjeta de abajo.
	"guide_limits": {"kind": "guide", "cat": CAT_BASICS, "basic": true, "dyn": true,
		"title": "HELP_T_LIMITS", "body": "HELP_B_LIMITS", "target": "build_button"},
	"guide_upgrades": {"kind": "guide", "cat": CAT_BASICS, "basic": true, "dyn": true,
		"title": "HELP_T_UPGRADES", "body": "HELP_B_UPGRADES", "target": ""},
	"guide_eras": {"kind": "guide", "cat": CAT_ECONOMY, "basic": true, "dyn": true,
		"title": "HELP_T_ERAS", "body": "HELP_B_ERAS", "target": "objective"},
	"guide_workshop": {"kind": "guide", "cat": CAT_ECONOMY, "basic": true, "dyn": true,
		"title": "HELP_T_WORKSHOP", "body": "HELP_B_WORKSHOP", "target": ""},
	"guide_towers": {"kind": "guide", "cat": CAT_STORM, "basic": true, "dyn": true,
		"title": "HELP_T_TOWERS", "body": "HELP_B_TOWERS", "target": "", "needs": "storm_started"},
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
	if is_page(id):
		return BuildingHelpText.help_body(id)
	var key := String(entry(id).get("body", ""))
	return Tr.ti(key) if key != "" else ""

## Una pagina con numeros vivos (`dyn`): el indice la lee en grande, sin reloj.
static func is_page(id: String) -> bool:
	return bool(entry(id).get("dyn", false))

## El texto corto de una ayuda (su clave `body`): para el tooltip del indice. En
## una pagina es su resumen; en las demas, lo mismo que body().
static func summary(id: String) -> String:
	if not is_page(id):
		return body(id)
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
