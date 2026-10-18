extends RefCounted
## El Nucleo con niveles 1-5 (1.2, feat/nucleo-y-planos; doc 21 §6.1): las
## reglas y los textos. Sin estado y sin senales, como PlacementRules y
## Objectives: el nivel y la obra en curso los guarda ProgressionManager
## (core_level, start_core_upgrade()); aqui solo se pregunta.
##
## Subir el Nucleo sube el tope de cada edificio (GameConfig.core_level_limits)
## y abre edificios nuevos (GameConfig.core_level_unlocks). Cada nivel pide algo
## antes (una era y unos edificios: core_level_requirements), cuesta recursos,
## materiales y, el 4 y el 5, repuestos (core_level_costs), y tarda
## (core_level_durations). El Nucleo sigue funcionando mientras sube.
##
## Ningun numero va escrito a mano en los textos: todo sale de GameConfig.
## Lenguaje para 10-15 anos: frases cortas, sin jerga.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const ERA_NAME_KEYS := {1: "ERA_FRONTIER", 2: "ERA_INDUSTRIAL", 3: "ERA_PETROLEUM"}

# ── Consultas ────────────────────────────────────────────────────────

## El nivel de ahora (1..5).
static func level() -> int:
	return GameConfig.current_core_level()

static func max_level() -> int:
	return GameConfig.core_level_max

static func is_max() -> bool:
	return level() >= max_level()

## El nivel al que subiria ahora (o el maximo si ya esta).
static func next_level() -> int:
	return mini(level() + 1, max_level())

## Esta en obras para subir.
static func is_upgrading() -> bool:
	return ProgressionManager.is_core_upgrading()

## Lo que cuesta llegar a `to_level`, por ResourceManager.Type.
static func cost(to_level: int) -> Dictionary:
	return GameConfig.get_core_upgrade_cost(to_level)

## Lo que pide `to_level` y aun falta, en frases. [] si se cumple. No mira el
## coste (eso va aparte) ni si ya hay obra.
static func missing_requirements(to_level: int) -> Array:
	var out: Array = []
	var req: Dictionary = GameConfig.core_level_requirements.get(to_level, {})
	if req.is_empty():
		return out
	var era: int = int(req.get("era", 1))
	if ProgressionManager.current_era < era:
		out.append(Tr.t("CORE_NEED_ERA") % [era, Tr.t(String(ERA_NAME_KEYS.get(era, "")))])
	var names: Array = []
	for id in req.get("buildings", []):
		if Rules.count_building(String(id)) < 1:
			var data := Rules.load_building_data(String(id))
			names.append(data.get_display_name() if data != null else String(id))
	if not names.is_empty():
		out.append(Tr.t("CORE_NEED_BUILDINGS") % " + ".join(names))
	return out

## Se cumple lo que pide `to_level` (era y edificios; el coste aparte).
static func requirements_met(to_level: int) -> bool:
	return missing_requirements(to_level).is_empty()

## Por que no se puede empezar a subir AHORA, una cosa por linea. [] si se
## puede. Mismo orden que ProgressionManager.start_core_upgrade: maximo, obra,
## requisitos, bolsa y coste.
static func block_lines() -> Array:
	var out: Array = []
	if is_max():
		out.append(Tr.t("CORE_MAX"))
		return out
	if is_upgrading():
		out.append(Tr.t("CORE_BUSY"))
		return out
	var to := next_level()
	out.append_array(missing_requirements(to))
	var c := cost(to)
	# ¿Cabe en la bolsa? Los materiales y los repuestos van aparte.
	var bag := 0
	for type in c:
		if not ResourceManager.is_material(type):
			bag += int(c[type])
	var cap: int = ResourceManager.get_storage_cap()
	if bag > cap:
		out.append(Tr.t("TOPE_BAG_SMALL") % [bag, cap])
	var missing := {}
	var how: Array = []
	for type in c:
		var short: int = int(c[type]) - ResourceManager.get_amount(type)
		if short <= 0:
			continue
		var rid: String = ResourceManager.get_type_name(type)
		missing[rid] = short
		if rid == "parts":
			how.append(Tr.t("TOPE_HOW_PARTS"))
		elif GameConfig.get_material_source(rid) != "":
			var src := Rules.load_building_data(GameConfig.get_material_source(rid))
			how.append(Tr.t("TOPE_HOW_MATERIAL") % [Tr.res_cap(rid),
				src.get_display_name() if src != null else GameConfig.get_material_source(rid)])
	if not missing.is_empty():
		var parts: Array = []
		for rid in missing:
			parts.append("%d %s" % [int(missing[rid]), Tr.res_name(String(rid))])
		out.append(Tr.t("OBJ_MISSING") % ", ".join(parts))
		out.append_array(how)
	return out

## Se puede empezar a subir ahora mismo (todo lo de block_lines()).
static func can_start() -> bool:
	return block_lines().is_empty()

## Se puede subir en cuanto se junte el precio: no esta al maximo ni en obras y
## se cumple lo que pide el siguiente nivel. Lo usa ¿QUE HACER? para no pedir
## un nivel que aun no se puede.
static func can_aim() -> bool:
	return not is_max() and not is_upgrading() and requirements_met(next_level())

## Lo que da llegar a `to_level`, en frases: los topes que suben ("Aserradero:
## hasta 5 (ahora 4)") y lo que abre ("Abre: Taberna, Carpintería"). Solo los
## edificios que existen (.tres). Sin rango ni modo: es la tabla.
static func gains_lines(to_level: int) -> Array:
	var out: Array = []
	var from := maxi(1, to_level - 1)
	for data in BuildingData.load_all():
		var d: BuildingData = data
		if d.is_core or d.is_decoration:
			continue
		if GameConfig.core_level_unlock(d.id) > from:
			continue
		var now := GameConfig.base_building_limit(d.id, from)
		var later := GameConfig.base_building_limit(d.id, to_level)
		if now >= 0 and later > now:
			out.append(Tr.t("CORE_GAIN_LIMIT") % [d.get_display_name(), later, now])
	out.sort()
	var opens := opened_names(to_level)
	if opens != "":
		out.append(Tr.t("CORE_GAIN_OPENS") % opens)
	return out

## Los edificios que abre el nivel `to_level`, con su nombre ("" si ninguno).
## Solo los que existen.
static func opened_names(to_level: int) -> String:
	var names: Array = []
	for id in GameConfig.core_unlocks_at(to_level):
		var data := Rules.load_building_data(String(id))
		if data != null:
			names.append(data.get_display_name())
	return ", ".join(names)

## Subir el Nucleo levantaria el tope de `building_id`: hay un nivel mas alto
## con mas sitio. Para "Sube el Núcleo a N" en CONSTRUIR y en ¿QUE HACER?.
static func raises_limit(building_id: String) -> bool:
	return not GameConfig.next_building_limit(building_id).is_empty()

## "Nivel 2 de 5".
static func level_text(lv: int = -1) -> String:
	return Tr.t("TOPE_LEVEL_OF") % [lv if lv > 0 else level(), max_level()]

## "Subiendo a nivel 3: 45 % · faltan 1:10 min" mientras hay obra; "" si no.
static func upgrading_text() -> String:
	if not is_upgrading():
		return ""
	return Tr.t("CORE_UPGRADING") % [ProgressionManager.core_upgrade_target(),
		int(ProgressionManager.core_upgrade_progress() * 100.0),
		ProductionManager.eta_text(ProgressionManager.core_upgrade_remaining())]

# ── Partidas viejas ──────────────────────────────────────────────────

## El nivel del Nucleo para una partida guardada antes de que el Nucleo tuviera
## niveles: el mas alto cuyos requisitos (era y edificios) ya cumple, hasta el
## 4 (el 5 hay que ganarlo: pide repuestos y el Cuartel General). Una partida en
## la era 3 queda en el 4, con los topes de la era 3 de antes; una de la era 1
## con la Fundicion a punto, en el 2.
static func derive_level() -> int:
	var lv := 1
	for to in range(2, mini(4, max_level()) + 1):
		if not requirements_met(to):
			break
		lv = to
	return lv
