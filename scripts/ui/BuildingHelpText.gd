extends RefCounted
## Topes y mejoras explicados al jugador (rama feat/topes-mejoras-ayuda,
## 2026-10-17). Solo textos y lecturas, sin nodos propios ni senales: lo usan
## CONSTRUIR (la tarjeta llena, "Mejorar uno", lo que llega con una era), la
## ficha del edificio (nivel, por que no se mejora, por que el boton esta
## apagado, repuestos), las paginas de AYUDA que llevan numeros y la guia de
## edificios.
##
## Ningun numero va escrito a mano: todo se lee de GameConfig, de los .tres y de
## los topes por era. Si cambia el balance, el texto sigue diciendo la verdad.
## Lenguaje para 10-15 anos: frases cortas, sin jerga.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## El recurso que llega con una era y el edificio que lo trae. La Fundicion abre
## la era 2 (acero) y la Refineria la 3 (petroleo): CLAUDE.md, "3-Era Progression".
const ERA_RESOURCES := {
	"steel": [2, "foundry"],
	"oil": [3, "refinery"],
}
const ERA_NAME_KEYS := {1: "ERA_FRONTIER", 2: "ERA_INDUSTRIAL", 3: "ERA_PETROLEUM"}

## Las paginas de AYUDA que se escriben con numeros de GameConfig
## (HelpCatalog: entradas con "dyn").
const PAGES := ["guide_limits", "guide_upgrades", "guide_eras", "guide_towers", "guide_workshop"]

# ══════════════════════════════════════════════════════════════════════
# ── Topes ──
# ══════════════════════════════════════════════════════════════════════

## Uno y solo uno en todas las eras (Mercado, Laboratorio, Cuartel General).
static func is_unique(building_id: String) -> bool:
	for era in range(1, GameConfig.max_era() + 1):
		if GameConfig.base_building_limit(building_id, era) != 1:
			return false
	return true

## Ya hay tantos como permite el tope de ahora (era + rango). Sin tope, false.
static func is_full(building_id: String) -> bool:
	var limit := GameConfig.get_building_limit(building_id)
	return limit >= 0 and Rules.count_building(building_id) >= limit

## La frase de la tarjeta llena, o "" si aun caben mas:
##   "Solo puede haber uno."                                  (unicos)
##   "Máximo 5 en esta era. En la era 2 podrás tener 8."      (sube con la era)
##   "Ya tienes el máximo: 6."                                (ya no sube)
static func limit_full_text(building_id: String) -> String:
	if not is_full(building_id):
		return ""
	var limit := GameConfig.get_building_limit(building_id)
	if limit == 1 and is_unique(building_id):
		return Tr.t("TOPE_FULL_UNIQUE")
	var next := GameConfig.next_building_limit(building_id)
	if not next.is_empty():
		return Tr.t("TOPE_FULL_NEXT_ERA") % [limit, int(next["era"]), int(next["limit"])]
	return Tr.t("TOPE_FULL_MAX") % limit

## Lo que se puede hacer con la tarjeta llena: mejorar los que hay (si se
## mejoran y queda alguno por subir), o nada si ya estan todos al maximo.
static func limit_full_advice(building_id: String) -> String:
	if not is_full(building_id):
		return ""
	var data := Rules.load_building_data(building_id)
	if data == null or not Rules.upgrade_does_something(data):
		return ""
	if lowest_upgradable(building_id) != null:
		return Tr.t("TOPE_FULL_UPGRADE")
	return Tr.t("TOPE_FULL_ALL_MAX")

## Lo que llega con una era aun no alcanzada: "Llega en la era 2, con la
## Fundición." Y los materiales y repuestos que aun no hay, con donde se hacen.
## [] si nada del coste esta por desbloquear. Lo que ya tienes (del mercado, de
## un evento) no cuenta: solo lo que falta.
static func locked_lines(data: BuildingData) -> Array:
	var out: Array = []
	if data == null:
		return out
	var short := Rules.missing_cost(data)
	var eras_said := {}
	for res_id in short.keys():
		var rid := String(res_id)
		if ResourceManager.is_unlocked_by_name(rid):
			continue
		if ERA_RESOURCES.has(rid):
			var era: int = int(ERA_RESOURCES[rid][0])
			if eras_said.has(era):
				continue
			eras_said[era] = true
			out.append(Tr.t("TOPE_LOCK_ERA") % [era, _building_name(String(ERA_RESOURCES[rid][1]))])
		elif rid == "parts":
			out.append(Tr.t("TOPE_LOCK_PARTS"))
		else:
			var src := GameConfig.get_material_source(rid)
			if src != "":
				out.append(Tr.t("TOPE_LOCK_MATERIAL") % [Tr.res_name(rid), _building_name(src)])
	return out

## El de nivel mas bajo de `building_id` que aun puede subir (terminado, sin
## obras y por debajo del nivel maximo), o null. Para "Mejorar uno".
static func lowest_upgradable(building_id: String) -> Node:
	var best: Node = null
	var best_level := GameConfig.max_building_level
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data == null or data.id != building_id or node == null or not is_instance_valid(node):
			continue
		if ProductionManager.is_constructing(node):
			continue
		var level := int(node.get_meta("level", 1))
		if level < best_level:
			best_level = level
			best = node
	return best

## Lleva la camara al edificio y abre su ficha, como si se hubiera tocado.
## Vale en 3D (MonumentalCamera.get_state/set_state) y en 2D
## (Camera2DController.look_at_world).
static func focus_and_select(viewport: Viewport, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	if viewport != null:
		var cam3 := viewport.get_camera_3d()
		var cam2 := viewport.get_camera_2d()
		if cam3 != null and node is Node3D and cam3.has_method("get_state") and cam3.has_method("set_state"):
			var state: Dictionary = cam3.call("get_state")
			var pos: Vector3 = (node as Node3D).global_position
			state["target_x"] = pos.x
			state["target_y"] = pos.z
			cam3.call("set_state", state)
		elif cam2 != null and node is Node2D and cam2.has_method("look_at_world"):
			cam2.call("look_at_world", (node as Node2D).global_position)
	EventBus.building_clicked.emit(node, info["data"])

# ══════════════════════════════════════════════════════════════════════
# ── Mejoras ──
# ══════════════════════════════════════════════════════════════════════

## "Nivel 1 de 3".
static func level_of_text(level: int) -> String:
	return Tr.t("TOPE_LEVEL_OF") % [level, GameConfig.max_building_level]

## Por que `data` no se mejora, en una frase corta. "" si se mejora.
static func no_upgrade_text(data: BuildingData) -> String:
	if data == null or Rules.upgrade_does_something(data):
		return ""
	var why := "TOPE_NO_UPGRADE_WHY_" + data.id.to_upper()
	var reason := Tr.t(why)
	if reason == why:
		reason = Tr.t("TOPE_NO_UPGRADE_WHY_DEFAULT")
	return Tr.t("TOPE_NO_UPGRADE") % reason

## El aviso de repuestos del siguiente nivel: "El nivel 3 pide 3 repuestos. Solo
## se traen de las MISIONES." "" si ese nivel no los pide.
static func parts_note(data: BuildingData, next_level: int) -> String:
	if data == null:
		return ""
	var cost := GameConfig.get_upgrade_cost(data, next_level)
	var parts := int(cost.get(ResourceManager.Type.PARTS, 0))
	if parts <= 0:
		return ""
	return Tr.t("TOPE_PARTS_NOTE") % [next_level, parts]

## Por que no se puede mejorar `node` ahora mismo, una cosa por linea. [] si se
## puede. Mismo orden que ProductionManager.start_upgrade: nivel, obras, coste.
static func upgrade_block_lines(data: BuildingData, node: Node) -> Array:
	var out: Array = []
	if data == null or node == null or not is_instance_valid(node):
		return out
	if not Rules.upgrade_does_something(data):
		out.append(no_upgrade_text(data))
		return out
	var level := int(node.get_meta("level", 1))
	if level >= GameConfig.max_building_level:
		out.append(Tr.t("TOPE_MAX_LEVEL"))
		return out
	if ProductionManager.is_constructing(node):
		out.append(Tr.t("TOPE_UPGRADING"))
		return out
	var cost := GameConfig.get_upgrade_cost(data, level + 1)
	# Cabe en el almacen? Lo que cuenta es la bolsa compartida (los materiales y
	# los repuestos van aparte). El nivel 3 del Cuartel General pide la bolsa entera.
	var bag := 0
	for type in cost:
		if not ResourceManager.is_material(type):
			bag += int(cost[type])
	var cap: int = ResourceManager.get_storage_cap()
	if bag > cap:
		out.append(Tr.t("TOPE_BAG_SMALL") % [_num(bag), _num(cap)])
	var missing := {}
	var how: Array = []
	for type in cost:
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short <= 0:
			continue
		var rid: String = ResourceManager.get_type_name(type)
		missing[rid] = short
		if rid == "parts":
			how.append(Tr.t("TOPE_HOW_PARTS"))
		elif not ResourceManager.is_unlocked_by_name(rid) and ERA_RESOURCES.has(rid):
			how.append(Tr.t("TOPE_LOCK_ERA") % [int(ERA_RESOURCES[rid][0]), _building_name(String(ERA_RESOURCES[rid][1]))])
		elif GameConfig.get_material_source(rid) != "":
			how.append(Tr.t("TOPE_HOW_MATERIAL") % [Tr.res_cap(rid), _building_name(GameConfig.get_material_source(rid))])
	if not missing.is_empty():
		var parts: Array = []
		for rid in missing:
			parts.append("%d %s" % [int(missing[rid]), Tr.res_name(String(rid))])
		out.append(Tr.t("OBJ_MISSING") % ", ".join(parts))
		out.append_array(how)
	return out

# ══════════════════════════════════════════════════════════════════════
# ── Textos con cifras vivas ──
# ══════════════════════════════════════════════════════════════════════

## Lo que cuesta subir el Cuartel General a `level` en la bolsa compartida (oro,
## acero, petroleo y madera; los materiales van aparte).
static func hq_bag_cost(level: int) -> int:
	var raw: Dictionary = GameConfig.hq_upgrade_costs.get(level, {})
	var total := 0
	for res_id in ["gold", "steel", "oil", "wood"]:
		total += int(raw.get(res_id, 0))
	return total

## Cambia las marcas {HQ2_COST} y {HQ3_COST} de un texto por el coste real del
## Cuartel General. ¿QUE HACER? lo pasa por aqui (OBJ_WHY_HQ_2 / _3): asi la
## cifra no se queda vieja cuando cambia el balance.
static func live_text(text: String) -> String:
	if text.find("{") == -1:
		return text
	return text.replace("{HQ2_COST}", _num(hq_bag_cost(2))).replace("{HQ3_COST}", _num(hq_bag_cost(3)))

## 3500 -> "3.500" en español, "3,500" en inglés.
static func _num(n: int) -> String:
	var sep := "." if Tr.get_locale() == "es" else ","
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## 1.6 -> "1,6" en español.
static func _mult(x: float) -> String:
	var s := ("%.1f" % x).trim_suffix(".0")
	return s.replace(".", ",") if Tr.get_locale() == "es" else s

static func _building_name(building_id: String) -> String:
	var data := Rules.load_building_data(building_id)
	return data.get_display_name() if data != null else building_id

static func _names(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(_building_name(String(id)))
	return ", ".join(names)

## Los edificios que se ven en las paginas: ni el Nucleo ni las decoraciones.
static func _main_buildings() -> Array:
	var out: Array = []
	for data in BuildingData.load_all():
		var d: BuildingData = data
		if d.is_core or d.is_decoration:
			continue
		out.append(d)
	out.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())
	return out

## La era en que se puede construir `data` por lo que pide: con petroleo, la 3;
## con acero, la 2; si no, la 1.
static func build_era(data: BuildingData) -> int:
	if data.cost_oil > 0:
		return 3
	if data.cost_steel > 0:
		return 2
	return 1

# ══════════════════════════════════════════════════════════════════════
# ── Paginas de AYUDA ──
# ══════════════════════════════════════════════════════════════════════

static func is_page(id: String) -> bool:
	return id in PAGES

static func help_body(id: String) -> String:
	match id:
		"guide_limits":
			return limits_page()
		"guide_upgrades":
			return upgrades_page()
		"guide_eras":
			return eras_page()
		"guide_towers":
			return towers_page()
		"guide_workshop":
			return workshop_page()
	return ""

## Topes de edificios: la tabla de GameConfig en palabras.
static func limits_page() -> String:
	var lines: Array = [Tr.t("TOPE_PAGE_LIMITS_INTRO"), ""]
	var fixed: Array = []
	var unique: Array = []
	for data in _main_buildings():
		var d: BuildingData = data
		if d.id == Rules.ROAD_ID:
			continue
		var row: Array = []
		for era in range(1, GameConfig.max_era() + 1):
			row.append(GameConfig.base_building_limit(d.id, era))
		if int(row[0]) < 0:
			continue
		if is_unique(d.id):
			unique.append(d.get_display_name())
		elif row.min() == row.max():
			fixed.append("%s %d" % [d.get_display_name(), int(row[0])])
		else:
			var parts: Array = []
			for v in row:
				parts.append(str(int(v)))
			lines.append("• %s: %s" % [d.get_display_name(), " · ".join(parts)])
	if not fixed.is_empty():
		lines.append(Tr.t("TOPE_PAGE_LIMITS_FIXED") % ", ".join(fixed))
	if not unique.is_empty():
		lines.append(Tr.t("TOPE_PAGE_LIMITS_UNIQUE") % ", ".join(unique))
	lines.append(Tr.t("TOPE_PAGE_LIMITS_FREE"))
	lines.append("")
	lines.append(Tr.t("TOPE_PAGE_LIMITS_RANK"))
	lines.append(Tr.t("TOPE_PAGE_LIMITS_FULL"))
	return "\n".join(lines)

## Mejorar edificios: niveles, que da cada uno con cifras, coste, repuestos y el
## Cuartel General.
static func upgrades_page() -> String:
	var top := GameConfig.max_building_level
	var lines: Array = [Tr.t("TOPE_PAGE_UPG_INTRO") % top, ""]
	var prod: Array = []
	for lv in range(2, top + 1):
		prod.append("×" + _mult(GameConfig.get_production_multiplier(lv)))
	lines.append(Tr.t("TOPE_PAGE_UPG_PRODUCERS") % " / ".join(prod))
	var house := Rules.load_building_data("house")
	if house != null:
		var room: Array = []
		for lv in range(1, top + 1):
			room.append(str(int(house.population_capacity * GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, lv))))
		lines.append(Tr.t("TOPE_PAGE_UPG_HOUSE") % " → ".join(room))
	lines.append(Tr.t("TOPE_PAGE_UPG_WAREHOUSE") % GameConfig.warehouse_level_bonus)
	var morale: Array = []
	for lv in range(2, top + 1):
		morale.append("×" + _mult(GameConfig.level_mult(GameConfig.upgrade_morale_multiplier, lv)))
	lines.append(Tr.t("TOPE_PAGE_UPG_DECOR") % " / ".join(morale))
	lines.append("")
	var price: Array = []
	for lv in range(2, top + 1):
		price.append("×" + _mult(float(GameConfig.upgrade_cost_multiplier[lv - 1])))
	lines.append(Tr.t("TOPE_PAGE_UPG_COST") % " / ".join(price))
	for lv in range(2, top + 1):
		var parts := int(GameConfig.upgrade_parts_cost.get(lv, 0))
		if parts > 0:
			lines.append(Tr.t("TOPE_PAGE_UPG_PARTS") % [lv, parts, _names(GameConfig.upgrade_parts_buildings)])
	var hq := Rules.load_building_data("headquarters")
	if hq != null:
		lines.append(Tr.t("TOPE_PAGE_UPG_HQ") % [hq.get_display_name(), _num(hq_bag_cost(2)), _num(hq_bag_cost(3))])
	var never: Array = []
	for data in _main_buildings():
		var d: BuildingData = data
		if d.id != Rules.ROAD_ID and not Rules.upgrade_does_something(d):
			never.append(d.get_display_name())
	if not never.is_empty():
		lines.append("")
		lines.append(Tr.t("TOPE_PAGE_UPG_NEVER") % ", ".join(never))
	return "\n".join(lines)

## Las eras: que trae cada una, que la abre y que se puede construir.
static func eras_page() -> String:
	var lines: Array = [Tr.t("TOPE_PAGE_ERAS_INTRO"), ""]
	var by_era := {}
	for data in _main_buildings():
		var d: BuildingData = data
		var e := build_era(d)
		if not by_era.has(e):
			by_era[e] = []
		(by_era[e] as Array).append(d.get_display_name())
	var units_by_era := {}
	for unit_id in GameConfig.unit_types:
		var u: Dictionary = GameConfig.unit_types[unit_id]
		var e := int(u.get("era", 1))
		if not units_by_era.has(e):
			units_by_era[e] = []
		(units_by_era[e] as Array).append(Tr.t(String(u.get("name", unit_id))))
	for era in range(1, GameConfig.max_era() + 1):
		var head := "%s %d · %s" % [Tr.t("TOPE_ERA_WORD"), era, Tr.t(String(ERA_NAME_KEYS.get(era, "")))]
		lines.append(head)
		if era == 1:
			lines.append(Tr.t("TOPE_PAGE_ERAS_1"))
		else:
			var opener := ""
			var res_id := ""
			for rid in ERA_RESOURCES:
				if int(ERA_RESOURCES[rid][0]) == era:
					res_id = String(rid)
					opener = String(ERA_RESOURCES[rid][1])
			var reqs := Rules.prerequisite_names(opener) if opener != "" else ""
			lines.append(Tr.t("TOPE_PAGE_ERAS_OPENS") % [_building_name(opener), reqs, Tr.res_name(res_id),
				Tr.res_name(GameConfig.get_material_of(opener))])
		if by_era.has(era):
			lines.append(Tr.t("TOPE_PAGE_ERAS_BUILD") % ", ".join(by_era[era]))
		if units_by_era.has(era):
			lines.append(Tr.t("TOPE_PAGE_ERAS_UNITS") % ", ".join(units_by_era[era]))
		lines.append("")
	var caps: Array = []
	for era in range(1, GameConfig.max_era() + 1):
		caps.append(_num(GameConfig.get_base_storage_cap(era)))
	lines.append(Tr.t("TOPE_PAGE_ERAS_GROW") % " → ".join(caps))
	return "\n".join(lines)

## Torres: mitigacion, dotaciones, cuando cuentan, tope y por que no se mejoran.
static func towers_page() -> String:
	var per := roundi(GameConfig.storm_tower_mitigation * 100.0)
	var cap := roundi(GameConfig.storm_tower_mitigation_max * 100.0)
	var to_cap := ceili(GameConfig.storm_tower_mitigation_max / maxf(GameConfig.storm_tower_mitigation, 0.001))
	var lines: Array = [
		Tr.t("TOPE_PAGE_TOWER_STORM") % [per, cap, to_cap],
		Tr.t("TOPE_PAGE_TOWER_CREW") % [GameConfig.storm_tower_garrison_per_tower, GameConfig.storm_tower_garrison_max],
		Tr.t("TOPE_PAGE_TOWER_ONLY"),
		Tr.t("TOPE_PAGE_TOWER_LOSS") % roundi(GameConfig.storm_tower_crew_loss_damage * 100.0),
		Tr.t("TOPE_PAGE_TOWER_LIMIT") % GameConfig.base_building_limit("tower", 1),
	]
	var reqs := Rules.prerequisite_names("tower")
	if reqs != "":
		lines.append(Tr.t("TOPE_PAGE_TOWER_REQS") % reqs)
	return "\n".join(lines)

## Taller: que material hace cada edificio, con que receta, quien los pide y los
## repuestos (que no se fabrican).
static func workshop_page() -> String:
	var lines: Array = [Tr.t("TOPE_PAGE_SHOP_INTRO") % Tr.t("LBL_ACTIONS").to_upper(), ""]
	for mat in GameConfig.material_sources:
		var src := String(GameConfig.material_sources[mat])
		for proc in GameConfig.building_processes.get(src, []):
			var produces: Dictionary = proc.get("produces", {})
			if not produces.has(mat):
				continue
			var cost: Dictionary = proc.get("cost", {})
			var cost_parts: Array = []
			for rid in cost:
				cost_parts.append("%d %s" % [int(cost[rid]), Tr.res_name(String(rid))])
			lines.append(Tr.t("TOPE_PAGE_SHOP_RECIPE") % [Tr.res_cap(String(mat)), " + ".join(cost_parts),
				int(produces[mat]), _building_name(src)])
			break
	lines.append("")
	lines.append(Tr.t("TOPE_PAGE_SHOP_APART"))
	var users: Array = []
	for data in _main_buildings():
		var d: BuildingData = data
		if d.cost_materials.is_empty():
			continue
		var mats: Array = []
		for m in d.cost_materials:
			mats.append(Tr.res_name(String(m)))
		users.append("%s (%s)" % [d.get_display_name(), ", ".join(mats)])
	if not users.is_empty():
		lines.append(Tr.t("TOPE_PAGE_SHOP_USERS") % ", ".join(users))
	lines.append(Tr.t("TOPE_PAGE_SHOP_PARTS"))
	return "\n".join(lines)

# ══════════════════════════════════════════════════════════════════════
# ── Guia de edificios ──
# ══════════════════════════════════════════════════════════════════════

## La segunda linea de cada edificio en la guia: tope por era, lo que pide
## antes y si se mejora. Sin rango ni modo: es la regla, no tu partida.
static func guide_rules_line(data: BuildingData) -> String:
	var parts: Array = []
	if data.is_core:
		parts.append(Tr.t("TOPE_GUIDE_CORE"))
	elif data.is_decoration or GameConfig.base_building_limit(data.id, 1) < 0:
		parts.append(Tr.t("TOPE_GUIDE_NO_LIMIT"))
	elif is_unique(data.id):
		parts.append(Tr.t("TOPE_GUIDE_UNIQUE"))
	else:
		var row: Array = []
		var texts: Array = []
		for era in range(1, GameConfig.max_era() + 1):
			var v := GameConfig.base_building_limit(data.id, era)
			row.append(v)
			texts.append(str(v))
		if row.min() == row.max():
			parts.append(Tr.t("TOPE_GUIDE_LIMIT_FIXED") % int(row[0]))
		else:
			parts.append(Tr.t("TOPE_GUIDE_LIMIT_ERAS") % " · ".join(texts))
	if not data.is_core and not data.is_decoration:
		parts.append(Tr.t("TOPE_GUIDE_ERA") % build_era(data))
	var reqs := Rules.prerequisite_names(data.id) if not GameConfig.get_prerequisites(data.id).is_empty() else ""
	if reqs != "":
		parts.append(Tr.t("TOPE_GUIDE_NEEDS") % reqs)
	if Rules.upgrade_does_something(data):
		parts.append(Tr.t("TOPE_GUIDE_UPGRADES") % GameConfig.max_building_level)
	elif data.id != Rules.ROAD_ID:
		parts.append(Tr.t("TOPE_GUIDE_NO_UPGRADE"))
	return " · ".join(parts)
