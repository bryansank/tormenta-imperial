extends Node
## Las amenazas de costa (feat/amenazas-costa, 1.2, docs/15 §14): dueno del
## modelo puro ThreatBoard, lo hace avanzar con los segundos jugados y vuelca al
## EventBus lo que devuelve.
##
## Decision de Bryan (2026-10-18): SOLO BOTIN OPCIONAL. Saqueadores, avanzadilla
## de la Regencia y pecios aparecen en la orilla cada cierto tiempo, se ven en el
## mapa (3D y 2D), duran un rato y SE VAN SOLAS sin hacer ningun dano. Atacarlas
## (un combate de dominio puro) o explorar el pecio con trabajadores da botin.
## No bloquean la linea principal ni ¿QUE HACER?: como mucho la sugerencia de
## MISIONES (CombatManager.sortie_reason -> "THREAT_WHY_EASY").
##
## Lo que hace aqui y no en otro sitio:
##   - buscar casillas libres en la costa (solo cuando toca una marca nueva);
##   - lanzar la columna contra una amenaza (CombatManager.launch_threat_offer)
##     y cerrarla al oir expedition_ended;
##   - mandar trabajadores al pecio y pagar lo que traen;
##   - los avisos (una noticia al aparecer; irse y echarla, al registro).
##
## Va el ultimo de los autoloads: usa GridManager, CombatManager, ArmyManager,
## PopulationManager, ProgressionManager, TutorialManager y RankManager, y nadie
## lo necesita durante su _ready. Sin _process: un Timer de
## GameConfig.threat_check_interval segundos reales (pausable).
##
## Guardado: clave "threats" (GameManager). load_save_data() sustituye el tablero
## entero (idempotente); sin clave, orilla vacia. reset() lo tira sin avisar.

const BoardScript := preload("res://scripts/combat/ThreatBoard.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

var _board: ThreatBoard = BoardScript.new()
var _timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_timer = Timer.new()
	_timer.wait_time = maxf(0.5, GameConfig.threat_check_interval)
	_timer.autostart = true
	_timer.timeout.connect(tick)
	add_child(_timer)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.game_load_completed.connect(_on_game_load_completed)
	# Una marca de tierra sobre la que se construye se va (sin botin): nunca se
	# pinta encima de un edificio.
	EventBus.building_placed.connect(func(_d, _c): _check_covered())

# ── El reloj ─────────────────────────────────────────────────────────

## Un paso del reloj. Lo llama el Timer; los tests, a mano.
func tick() -> void:
	if not GameManager.is_started():
		return
	var now: float = _now()
	var ctx: Dictionary = context()
	var spots: Dictionary = {}
	# Lo caro (recorrer la rejilla) solo cuando toca una marca nueva.
	if _board.spawn_due(now, ctx):
		spots = free_spots()
	_publish(_board.refresh(now, ctx, spots, _new_seed()))

## Lo que el modelo necesita saber de la partida.
func context() -> Dictionary:
	var era: int = clampi(ProgressionManager.current_era, 1, 3)
	var lifetimes: Dictionary = {}
	for threat_type in GameConfig.threat_lifetime:
		lifetimes[threat_type] = GameConfig.get_duration(float(GameConfig.threat_lifetime[threat_type]))
	var interval: Vector2 = GameConfig.threat_spawn_interval
	return {
		"enabled": is_open(),
		"era": era,
		"sea_ok": ArmyManager.building_count("shipyard") > 0,
		"max": GameConfig.threat_max_active,
		"first_delay": GameConfig.get_duration(GameConfig.threat_first_delay),
		"interval": Vector2(GameConfig.get_duration(interval.x), GameConfig.get_duration(interval.y)),
		"lifetimes": lifetimes,
		"weights": GameConfig.threat_weights.get(era, {}),
		"sea_chance": GameConfig.threat_sea_chance,
		"spacing": GameConfig.threat_spacing,
	}

## ¿Salen amenazas ahora? Con un edificio militar, la primera escaramuza ganada
## (hasta entonces cada salida es la facil) y sin el asedio final convocado.
func is_open() -> bool:
	if not GameConfig.threats_enabled or GameMode.is_run_over():
		return false
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return false
	return ArmyManager.has_military_building() and TutorialManager.is_first_sortie_done()

## Las casillas donde puede caer una marca: "land" = tierra libre que toca el agua
## (la playa), "sea" = agua de la rejilla libre que toca tierra. Las dos lejos de
## la acera del Nucleo. Una pasada por la rejilla (8 vecinos por casilla), solo
## cuando toca una marca nueva.
func free_spots() -> Dictionary:
	var land: Array = []
	var sea: Array = []
	var w: int = GridManager.grid_width
	var h: int = GridManager.grid_height
	var core := Rect2i(Vector2i(w / 2, h / 2), Vector2i(3, 3)).grow(1 + maxi(0, GameConfig.threat_core_gap))
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			if core.has_point(c) or GridManager.get_building_at(c) != null:
				continue
			var land_here: bool = GridManager.is_land_cell(c)
			var touches_water := false
			var touches_land := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if GridManager.is_land_cell(c + Vector2i(dx, dy)):
						touches_land = true
					else:
						touches_water = true
			if land_here and touches_water:
				land.append(c)
			elif not land_here and touches_land:
				sea.append(c)
	return {"land": land, "sea": sea}

# ── Consultas (la UI lee de aqui) ────────────────────────────────────

func get_board() -> ThreatBoard:
	return _board

## Copias de las amenazas a la vista.
func get_threats() -> Array:
	return _board.threats.duplicate(true)

func get_threat(threat_id: int) -> Dictionary:
	return _board.get_threat(threat_id).duplicate(true)

func seconds_left(threat_id: int) -> float:
	return _board.seconds_left(threat_id, _now())

## La amenaza en `cell` (o pegada a ella). 0 si ninguna. La llaman los placers.
func threat_at_cell(cell: Vector2i, radius: int = 1) -> int:
	return _board.threat_at(cell, radius)

## Las que se pueden atacar ahora (libres y de combate), como ofertas para la
## lista de ATAQUES RAPIDOS de MISIONES.
func get_attack_offers() -> Array:
	var out: Array = []
	for threat in _board.threats:
		if String(threat.get("state", "")) != ThreatBoard.STATE_IDLE:
			continue
		if not Generator.threat_is_fight(String(threat.get("type", ""))):
			continue
		out.append(ThreatBoard.offer_for(threat))
	return out

## Los pecios a la vista (libres o explorandose).
func get_wrecks() -> Array:
	var out: Array = []
	for threat in _board.threats:
		if String(threat.get("type", "")) == Generator.THREAT_WRECK:
			out.append(threat.duplicate(true))
	return out

## Oro/madera/acero de una amenaza (lo mismo que paga su combate o el pecio).
func rewards_of(threat_id: int) -> Dictionary:
	return Generator.threat_rewards(ThreatBoard.offer_for(_board.get_threat(threat_id)))

## Repuestos y material de una amenaza.
func loot_of(threat_id: int) -> Dictionary:
	return Generator.threat_loot(ThreatBoard.offer_for(_board.get_threat(threat_id)))

## Por que no se puede atacar esta amenaza ahora, como clave de Tr, o "".
func attack_block_reason(threat_id: int) -> String:
	var threat: Dictionary = _board.get_threat(threat_id)
	if threat.is_empty():
		return "THREAT_GONE"
	if String(threat.get("state", "")) == ThreatBoard.STATE_ENGAGED:
		return "THREAT_ENGAGED"
	if not ArmyManager.has_military_building():
		return "THREAT_NEED_BARRACKS"
	if CombatManager.has_active_expedition():
		return "MSG_EXPEDITION_ACTIVE"
	if CombatManager.is_in_encounter():
		return "MSG_ENCOUNTER_ACTIVE"
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return "MSG_AUDIT_BLOCKS_EXPEDITION"
	var domain: String = "sea" if bool(threat.get("water", false)) else "land"
	if CombatManager.campaign_units_home(domain).is_empty():
		return "THREAT_NEED_SHIPS" if domain == "sea" else "THREAT_NEED_TROOPS"
	return ""

## Por que no se puede explorar este pecio ahora, como clave de Tr, o "".
func explore_block_reason(threat_id: int) -> String:
	var threat: Dictionary = _board.get_threat(threat_id)
	if threat.is_empty():
		return "THREAT_GONE"
	if String(threat.get("state", "")) == ThreatBoard.STATE_EXPLORING:
		return "THREAT_EXPLORING"
	if PopulationManager.get_free_workers() < GameConfig.threat_wreck_workers:
		return "THREAT_NEED_WORKERS"
	return ""

## Hay una marca sin mirar con botin facil: un pecio con trabajadores libres, o
## una pelea "Favorable" con lo que hay en casa de su medio. La sugerencia de
## MISIONES / ¿QUE HACER? (una sola, se apaga al mirarla).
func has_easy_unseen() -> bool:
	for threat in _board.threats:
		if bool(threat.get("seen", false)) or String(threat.get("state", "")) != ThreatBoard.STATE_IDLE:
			continue
		var id: int = int(threat["id"])
		if String(threat.get("type", "")) == Generator.THREAT_WRECK:
			if explore_block_reason(id) == "":
				return true
			continue
		if attack_block_reason(id) != "":
			continue
		if is_easy(id):
			return true
	return false

## ¿Ganaria con lo mejor que hay en casa de su medio? (Favorable.)
func is_easy(threat_id: int) -> bool:
	var offer: Dictionary = ThreatBoard.offer_for(_board.get_threat(threat_id))
	if offer.is_empty():
		return false
	var map: Array = Generator.threat_map(offer)
	if map.is_empty():
		return false
	var enemy: float = Generator.hardest_node_power(map, int(offer.get("era", 1)))
	var party: Dictionary = best_party(String(offer.get("domain", "land")))
	return Rules.odds_label(Generator.roster_power(party), enemy) == "favorable"

## Lo mas fuerte que hay en casa de `domain`, hasta el tope de despliegue.
func best_party(domain: String) -> Dictionary:
	var home: Dictionary = CombatManager.campaign_units_home(domain)
	var ids: Array = home.keys()
	ids.sort_custom(func(a, b): return int(GameConfig.get_unit_def(String(a)).get("power", 0)) > int(GameConfig.get_unit_def(String(b)).get("power", 0)))
	var party: Dictionary = {}
	var left: int = GameConfig.combat_deploy_cap
	for unit_id in ids:
		if left <= 0:
			break
		var n: int = mini(int(home[unit_id]), left)
		if n > 0:
			party[String(unit_id)] = n
			left -= n
	return party

## Trabajadores fuera, explorando pecios (PopulationManager los descuenta).
func busy_workers() -> int:
	return _board.exploring_count() * maxi(0, GameConfig.threat_wreck_workers)

# ── Ordenes ──────────────────────────────────────────────────────────

## ¡AL ATAQUE! La columna `party` sale contra la amenaza. `auto_resolve`: de un
## tiron (solo si la fuerza lo permite). false si no se pudo (nada cambia).
func launch(threat_id: int, party: Dictionary, auto_resolve: bool = false) -> bool:
	if attack_block_reason(threat_id) != "":
		return false
	# Se marca ANTES de lanzar: "resolver solo" acaba la columna dentro de la
	# misma llamada, y expedition_ended tiene que encontrarla atacada.
	var offer: Dictionary = _board.engage(threat_id)
	if offer.is_empty():
		return false
	if not CombatManager.launch_threat_offer(offer, party, auto_resolve):
		_board.release_engaged()
		return false
	_publish([{"e": "changed"}])
	return true

## Manda trabajadores al pecio. false si no se puede (nada cambia).
func explore(threat_id: int) -> bool:
	if explore_block_reason(threat_id) != "":
		return false
	var events: Array = _board.start_explore(threat_id, _now(),
		GameConfig.get_duration(GameConfig.threat_wreck_explore_seconds))
	if events.is_empty():
		return false
	_publish(events)
	return true

func mark_seen(threat_id: int) -> void:
	_publish(_board.mark_seen(threat_id))

func mark_all_seen() -> void:
	_publish(_board.mark_all_seen())

# ── Lo que llega de fuera ────────────────────────────────────────────

## La columna volvio. Si era contra una amenaza: ganada, se va (el botin ya lo
## cobro CombatManager); perdida o abandonada, sigue en la orilla.
func _on_expedition_ended(result: int, _rewards: Dictionary, _lost: Dictionary) -> void:
	if _board.engaged_id() == 0:
		return
	_publish(_board.finish_engagement(result == Expedition.RESULT_WON, _now()))

## Un guardado con una amenaza atacada pero sin columna fuera (no deberia pasar):
## la amenaza vuelve a estar libre.
func _on_game_load_completed() -> void:
	if _board.engaged_id() != 0 and not CombatManager.has_active_expedition():
		_publish(_board.release_engaged())

func _check_covered() -> void:
	for threat in _board.threats.duplicate():
		if bool(threat.get("water", false)):
			continue
		if GridManager.get_building_at(threat.get("cell", Vector2i(-1, -1))) != null:
			_publish(_board.dismiss(int(threat["id"])))

# ── Publicar ─────────────────────────────────────────────────────────

func _publish(events: Array) -> void:
	if events.is_empty():
		return
	var changed := false
	for event in events:
		var id: int = int(event.get("id", 0))
		var threat_type: String = String(event.get("type", ""))
		match String(event.get("e", "")):
			"appeared":
				EventBus.threat_appeared.emit(id, threat_type, bool(event.get("water", false)))
				# Una noticia por marca nueva (sin spam: como mucho cada 2,5 min).
				EventBus.notification_posted.emit(Tr.t("THREAT_NOTIF_" + threat_type.to_upper()), "notice", UITheme.ACCENT)
			"left":
				EventBus.threat_left.emit(id, threat_type)
				# Irse no es noticia: solo al registro.
				EventBus.notification_posted.emit(Tr.t("THREAT_NOTIF_LEFT") % Tr.t(Generator.threat_name_key(threat_type)), "info", UITheme.TEXT_DIM)
			"cleared":
				EventBus.threat_cleared.emit(id, threat_type)
				EventBus.notification_posted.emit(Tr.t("THREAT_NOTIF_CLEARED") % Tr.t(Generator.threat_name_key(threat_type)), "success", UITheme.POSITIVE)
			"explored":
				_pay_wreck(id, event.get("offer", {}))
			"changed", "explore_started":
				changed = true
	EventBus.threats_changed.emit()
	# MISIONES (boton, punto rojo, panel) y ¿QUE HACER? ya repintan con esta.
	EventBus.sortie_offers_changed.emit()
	if changed:
		GameManager.request_save()

## Lo que traen los trabajadores del pecio: oro/madera a la bolsa, repuestos y
## material fuera de ella, y un poco de rango.
func _pay_wreck(threat_id: int, offer: Dictionary) -> void:
	var rewards: Dictionary = Generator.threat_rewards(offer)
	var loot: Dictionary = Generator.threat_loot(offer)
	for res_name in rewards:
		var type: int = ResourceManager.name_to_type(String(res_name))
		if type >= 0:
			ResourceManager.add(type, int(rewards[res_name]))
	for key in loot:
		var amount: int = int(loot[key])
		var material_type: int = ResourceManager.name_to_type(String(key))
		if amount <= 0 or material_type < 0:
			continue
		ResourceManager.unlock(material_type)
		ResourceManager.add(material_type, amount)
	if RankManager.has_method("add_xp"):
		RankManager.add_xp(GameConfig.threat_wreck_rank_xp)
	EventBus.wreck_explored.emit(threat_id, rewards.duplicate(), loot.duplicate())
	var all: Dictionary = rewards.duplicate()
	for key in loot:
		all[key] = int(all.get(key, 0)) + int(loot[key])
	EventBus.notification_posted.emit(Tr.t("THREAT_NOTIF_EXPLORED") % Tr.amount_list(all), "notice", UITheme.POSITIVE)

func _now() -> float:
	return ProgressionManager.get_played_seconds()

func _new_seed() -> int:
	var value: int = randi()
	return value if value != 0 else 1

# ── Guardado ─────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return _board.to_dict()

## Idempotente: el tablero entero sale de lo guardado. Sin clave (guardado
## anterior a las amenazas) = orilla vacia.
func load_save_data(data: Dictionary) -> void:
	_board = BoardScript.from_dict(data)
	EventBus.threats_changed.emit()

## Tira las marcas de la partida anterior. Sin avisos.
func reset() -> void:
	_board = BoardScript.new()
	EventBus.threats_changed.emit()
