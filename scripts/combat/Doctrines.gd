extends RefCounted
## Doctrinas de la Herreria militar (feat/edificios-militares, doc 21 §5.2,
## docs/15 §14). Modelo PURO: sin nodos, sin senales, sin azar. Lee la tabla
## GameConfig.combat_doctrines y la aplica a una CombatUnit al nacer.
##
## Una doctrina toca un tipo de unidad (`units`) o un medio entero (`domain`).
## Sus `mods` son pequenos y siempre cambian algo por algo:
##   "atk", "def", "move", "range", "initiative" — se suman a la estadistica;
##   "atk_pct", "hp_pct" — fraccion (-0.1 = -10 %);
##   "defend_mult" — defender multiplica la defensa por esto (en vez de 2).
## Solo el bando del jugador. Quien decide cual esta activa es ArmyManager
## (GameConfig.combat_active_doctrine); aqui solo se calcula.
##
## No nombra el tipo CombatUnit para que CombatUnit pueda precargar este
## archivo sin ciclo.

const PLAYER := 0

## La fila de la tabla, o {} si no existe.
static func get_def(doctrine_id: String) -> Dictionary:
	return GameConfig.combat_doctrines.get(doctrine_id, {})

static func exists(doctrine_id: String) -> bool:
	return GameConfig.combat_doctrines.has(doctrine_id)

## Las doctrinas en el orden de la ficha (las que no esten en el orden, al final).
static func ids() -> Array:
	var out: Array = []
	for id in GameConfig.combat_doctrine_order:
		if exists(String(id)):
			out.append(String(id))
	for id in GameConfig.combat_doctrines.keys():
		if not out.has(String(id)):
			out.append(String(id))
	return out

## ¿Toca esta doctrina a `unit_id`? Por su tipo o por su medio.
static func applies_to(doctrine_id: String, unit_id: String) -> bool:
	var def := get_def(doctrine_id)
	if def.is_empty():
		return false
	var units: Array = def.get("units", [])
	if units.has(unit_id):
		return true
	var domain := String(def.get("domain", ""))
	if domain == "":
		return false
	var stats: Dictionary = GameConfig.get_combat_stats(unit_id)
	return String(stats.get("domain", "land")) == domain

## Los mods que `doctrine_id` le pone a `unit_id`; {} si no le toca.
static func mods_for(doctrine_id: String, unit_id: String) -> Dictionary:
	if not applies_to(doctrine_id, unit_id):
		return {}
	return (get_def(doctrine_id).get("mods", {}) as Dictionary).duplicate()

## Las unidades a las que toca (para la ficha): tipos de `units` y, con
## `domain`, todos los tipos de ese medio, en el orden de combat_unit_stats.
static func affected_units(doctrine_id: String) -> Array:
	var out: Array = []
	for unit_id in GameConfig.combat_unit_stats.keys():
		if applies_to(doctrine_id, String(unit_id)):
			out.append(String(unit_id))
	return out

## Se la pone a una unidad recien creada: guarda el id, deja los mods y, si
## cambia la vida, ajusta max_hp y la deja entera. Solo al nacer (create): una
## unidad que vuelve de un guardado ya trae su max_hp (ver restore()).
## Enemigos y doctrinas que no le tocan: no hace nada.
static func apply(unit, doctrine_id: String) -> void:
	if unit == null or int(unit.side) != PLAYER or doctrine_id == "":
		return
	var mods := mods_for(doctrine_id, String(unit.unit_id))
	if mods.is_empty():
		return
	unit.doctrine = doctrine_id
	unit.doctrine_mods = mods
	var hp_pct := float(mods.get("hp_pct", 0.0))
	if hp_pct != 0.0:
		unit.max_hp = maxi(1, roundi(float(unit.max_hp) * (1.0 + hp_pct)))
		unit.hp = unit.max_hp

## Al cargar: los mods salen otra vez de la tabla (la vida ya viene guardada).
## Una doctrina que ya no existe se olvida.
static func restore(unit, doctrine_id: String) -> void:
	if unit == null or doctrine_id == "":
		return
	var mods := mods_for(doctrine_id, String(unit.unit_id))
	if mods.is_empty():
		return
	unit.doctrine = doctrine_id
	unit.doctrine_mods = mods

## Para la ficha: [[clave_tr, delta_texto, es_bueno], ...] en orden fijo.
## "atk_pct"/"hp_pct" en %, "defend_mult" como "x3".
static func effect_rows(doctrine_id: String) -> Array:
	var mods: Dictionary = get_def(doctrine_id).get("mods", {})
	var rows: Array = []
	for key in ["atk", "atk_pct", "def", "defend_mult", "move", "range", "initiative", "hp_pct"]:
		if not mods.has(key):
			continue
		var v: float = float(mods[key])
		var text := ""
		var good := v > 0.0
		match key:
			"atk_pct", "hp_pct":
				text = "%+d %%" % roundi(v * 100.0)
			"defend_mult":
				text = "x%d" % roundi(v)
				good = v >= 2.0
			_:
				text = "%+d" % roundi(v)
		rows.append(["DOC_STAT_" + String(key).to_upper(), text, good])
	return rows
