extends Node
## Volverse el Imperio (feat/volverse-imperio, docs/06 §Volverse el Imperio).
##
## Tras GANAR el Ataque Final la partida sigue en la misma isla: la Tormenta
## para para siempre y ahora eres tu quien cobra. Este servicio es dueno del
## modelo puro Archipelago (las islas vecinas, sus misiones de conquista y el
## tributo), lo hace avanzar con el tiempo de juego y publica en el EventBus lo
## que devuelve. Las misiones las juega CombatManager como cualquier columna
## (launch_conquest_mission); al volver, este servicio apunta el progreso.
##
## La fase esta activa cuando el modo la tiene (GameMode.empire_enabled:
## Campana y Supervivencia) y el Ataque Final esta GANADO. Un guardado viejo con
## la victoria ya conseguida entra en la fase al cargar (sin la clave "empire",
## nada empezado: el reloj del tributo arranca entonces).
##
## Va el ultimo de los autoloads: usa ProgressionManager, CombatManager,
## ResourceManager, GameManager y RankManager, y nadie lo necesita en su _ready.
##
## Rendimiento: un Timer de 1 s (se para con la pausa) y nada por fotograma. Sin
## la fase activa, cada tic es una comparacion.
##
## Guardado: clave "empire" (GameManager). load_save_data() reemplaza el modelo
## entero (idempotente); reset() lo tira (partida nueva).

const ArchipelagoScript := preload("res://scripts/empire/Archipelago.gd")
const ConquestGen := preload("res://scripts/empire/ConquestGenerator.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## Untyped: Archipelago se usa por preload para que los tests puedan crear uno.
var _book
var _timer: Timer
## Islas que estaban descansando en el tic anterior (para avisar al terminar).
var _resting: Dictionary = {}

func _ready() -> void:
	_book = ArchipelagoScript.new()
	_book.ensure_seed(_new_seed())
	_timer = Timer.new()
	_timer.name = "EmpireClock"
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	# La fase empieza al ganar (victory_achieved llega despues de
	# storm_halted_forever) o al cargar una partida ya ganada.
	EventBus.victory_achieved.connect(func(_stats): _maybe_start())
	EventBus.game_load_completed.connect(_maybe_start)
	EventBus.expedition_ended.connect(_on_expedition_ended)

# ── Consultas ────────────────────────────────────────────────────────

## La fase esta en marcha: el modo la tiene y el Ataque Final esta ganado.
func is_active() -> bool:
	if not GameMode.empire_enabled() or GameMode.is_run_over():
		return false
	var audit = ProgressionManager.final_audit
	return audit != null and audit.is_won()

## El modelo, para leer (la UI y las pruebas). Nadie fuera de aqui lo muta.
func get_book() -> Variant:
	return _book

func island_ids() -> Array:
	return ArchipelagoScript.island_ids()

func is_conquered(island_id: String) -> bool:
	return _book.is_conquered(island_id)

func conquered_count() -> int:
	return _book.conquered_count()

func island_count() -> int:
	return island_ids().size()

func all_conquered() -> bool:
	return _book.all_conquered()

func won(island_id: String) -> int:
	return _book.won(island_id)

func total(island_id: String) -> int:
	return ArchipelagoScript.total(island_id)

## La mision que toca en la isla (-1 si ya es tuya).
func next_mission(island_id: String) -> int:
	return _book.next_mission(island_id)

## El medio de la mision que toca ("" si la isla ya es tuya).
func next_domain(island_id: String) -> String:
	var mission: int = next_mission(island_id)
	return "" if mission < 0 else ArchipelagoScript.mission_domain(island_id, mission)

## La isla que ¿QUE HACER? propone ("" si no queda ninguna o no hay fase).
func next_target() -> String:
	return _book.next_target() if is_active() else ""

## La oferta de la mision que toca, con la era de ahora ({} si ya es tuya).
func conquest_offer(island_id: String) -> Dictionary:
	return _book.offer_for(island_id, ProgressionManager.current_era)

## El titulo imperial por islas conquistadas (clave de Tr, "" si ninguna).
func title_key() -> String:
	return _book.title_key() if is_active() else ""

## Lo que pagan las islas en cada cobro, y cuanto falta para el siguiente.
func tribute_per_cycle() -> Dictionary:
	return _book.tribute_per_cycle()

func tribute_left() -> float:
	return _book.tribute_left(_now())

## ¿Abre una isla conquistada este edificio (una decoracion antes de su rango)?
func unlocks_building(building_id: String) -> bool:
	return _book.unlocks("buildings", building_id)

## ¿Abre una isla conquistada esta pieza de bandera ("patterns", "emblems",
## "colors")?
func unlocks_piece(kind: String, id: String) -> bool:
	return _book.unlocks(kind, id)

func cooldown_left(island_id: String) -> float:
	return _book.cooldown_left(island_id, _now())

## Por que no se puede salir ahora a la mision que toca de `island_id`, como
## clave de Tr (sin cifras), o "" si se puede (falta elegir la tropa, aparte).
##   EMP_LOCK_PHASE      la fase no ha empezado (falta ganar el Ataque Final)
##   EMP_DONE            la isla ya es tuya
##   EMP_LOCK_NEEDS      hacen falta mas islas conquistadas antes
##   CAMP_LOCK_BUILDING  falta el edificio de su medio (Cuartel, Astillero, Aerodromo)
##   EMP_LOCK_REST       la tropa descansa tras la ultima mision de esa isla
##   y los de siempre: columna fuera, tablero abierto.
func lock_reason(island_id: String) -> String:
	if not is_active():
		return "EMP_LOCK_PHASE"
	if not ArchipelagoScript.has_island(island_id):
		return "EMP_LOCK_PHASE"
	if _book.is_conquered(island_id):
		return "EMP_DONE"
	if not _book.needs_met(island_id):
		return "EMP_LOCK_NEEDS"
	var building: String = CombatManager.campaign_building(next_domain(island_id))
	if ArmyManager.building_count(building) <= 0:
		return "CAMP_LOCK_BUILDING"
	if _book.cooldown_left(island_id, _now()) > 0.0:
		return "EMP_LOCK_REST"
	if CombatManager.has_active_expedition():
		return "MSG_EXPEDITION_ACTIVE"
	if CombatManager.is_in_encounter():
		return "MSG_ENCOUNTER_ACTIVE"
	return ""

## El candado en palabras, con su cifra ("" si se puede salir).
func lock_text(island_id: String) -> String:
	var lock: String = lock_reason(island_id)
	match lock:
		"":
			return ""
		"EMP_DONE":
			return Tr.t("EMP_DONE") % Tr.t(ConquestGen.island_name_key(island_id))
		"EMP_LOCK_NEEDS":
			return Tr.t("EMP_LOCK_NEEDS") % [ArchipelagoScript.needs(island_id), _book.conquered_count()]
		"CAMP_LOCK_BUILDING":
			var building: String = CombatManager.campaign_building(next_domain(island_id))
			var data: BuildingData = Rules.load_building_data(building)
			return Tr.t("CAMP_LOCK_BUILDING") % (data.get_display_name() if data != null else building)
		"EMP_LOCK_REST":
			var left: int = ceili(cooldown_left(island_id))
			return Tr.t("CAMP_LOCK_REST") % [left / 60, left % 60]
	return Tr.t(lock)

## Lo que hay en casa que puede ir a la mision que toca (unit_id -> cuantos).
func units_home(island_id: String) -> Dictionary:
	var domain: String = next_domain(island_id)
	if domain == "":
		return {}
	return CombatManager.campaign_units_home(domain)

## Saca la columna a la mision que toca de `island_id`. false si el candado o la
## tropa no lo dejan (la UI dice por que con lock_text / can_launch_to).
func launch_conquest(island_id: String, party: Dictionary) -> bool:
	if lock_reason(island_id) != "":
		return false
	var offer: Dictionary = conquest_offer(island_id)
	if offer.is_empty():
		return false
	return CombatManager.launch_conquest_mission(offer, party)

## La recompensa unica de una isla, en lineas ya traducidas.
func reward_lines(island_id: String) -> Array:
	var reward: Dictionary = ArchipelagoScript.reward_of(island_id)
	var lines: Array = []
	for building_id in reward.get("buildings", []):
		var data: BuildingData = Rules.load_building_data(String(building_id))
		lines.append(Tr.t("EMP_REWARD_BUILDING") % (data.get_display_name() if data != null else String(building_id)))
	for emblem in reward.get("emblems", []):
		lines.append(Tr.t("EMP_REWARD_EMBLEM") % Tr.t("FLAG_EMBLEM_" + String(emblem).to_upper()))
	for pattern in reward.get("patterns", []):
		lines.append(Tr.t("EMP_REWARD_PATTERN") % Tr.t("FLAG_PATTERN_" + String(pattern).to_upper()))
	for color in reward.get("colors", []):
		lines.append(Tr.t("EMP_REWARD_COLOR") % Tr.t("COLONY_COLOR_" + String(color).to_upper()))
	var title: String = String(reward.get("title", ""))
	if title != "":
		lines.append(Tr.t("EMP_REWARD_TITLE") % Tr.t(title))
	return lines

## El tributo de una isla (o el de todas, con `amounts`) en una linea:
## "+80 madera, +40 comida".
static func amounts_text(amounts: Dictionary) -> String:
	var parts: Array = []
	for res in amounts:
		parts.append("+%d %s" % [int(amounts[res]), Tr.res_name(String(res))])
	return ", ".join(parts)

func intro_seen() -> bool:
	return _book.intro_seen

func mark_intro_seen() -> void:
	_book.mark_intro_seen()

# ── El reloj ─────────────────────────────────────────────────────────

func _on_tick() -> void:
	if not GameManager.is_started() or not is_active():
		return
	if not _book.started:
		_maybe_start()
	_publish(_book.tick(_now(), _interval()))
	_check_rest()

## Avisa (empire_changed) cuando una isla termina su descanso, para que el panel
## y ¿QUE HACER? se pongan al dia. Una resta por isla y tic.
func _check_rest() -> void:
	var now: float = _now()
	var changed := false
	for island_id in island_ids():
		var resting: bool = _book.cooldown_left(String(island_id), now) > 0.0
		if bool(_resting.get(island_id, false)) and not resting:
			changed = true
		_resting[island_id] = resting
	if changed:
		EventBus.empire_changed.emit()

## Empieza la fase si toca y aun no empezo (al ganar, o al cargar una partida
## que ya habia ganado).
func _maybe_start() -> void:
	if not is_active() or _book.started:
		return
	_publish(_book.start(_now(), _interval()))

func _on_expedition_ended(_result: int, _rewards: Dictionary, _casualties: Dictionary) -> void:
	var last: Dictionary = CombatManager.get_last_result()
	var island_id: String = String(last.get("conquest_island", ""))
	if island_id == "":
		return
	_publish(_book.finish(island_id, int(last.get("conquest_mission", -1)), bool(last.get("victory", false)),
		_now(), GameConfig.get_duration(GameConfig.empire_mission_cooldown), _interval()))

func _publish(events: Array) -> void:
	for event in events:
		match String(event.get("e", "")):
			"empire_phase_started":
				EventBus.empire_phase_started.emit()
				EventBus.notification_posted.emit(Tr.t("MSG_EMPIRE_BEGINS"), "notice", UITheme.ACCENT)
				if TutorialManager.has_method("offer_tip"):
					TutorialManager.offer_tip("empire")
			"conquest_mission_won":
				EventBus.conquest_mission_won.emit(String(event["island"]), int(event["mission"]), bool(event["conquered"]))
			"island_conquered":
				var island_id: String = String(event["island"])
				EventBus.island_conquered.emit(island_id)
				EventBus.notification_posted.emit(Tr.t("MSG_EMPIRE_ISLAND_CONQUERED") % Tr.t(ConquestGen.island_name_key(island_id)),
					"notice", UITheme.POSITIVE)
			"archipelago_conquered":
				EventBus.archipelago_conquered.emit()
				EventBus.notification_posted.emit(Tr.t("MSG_EMPIRE_ALL_CONQUERED"), "notice", UITheme.ACCENT)
			"tribute":
				var amounts: Dictionary = event.get("amounts", {})
				for res in amounts:
					var type: int = ResourceManager.name_to_type(String(res))
					if type >= 0:
						ResourceManager.add(type, int(amounts[res]))
				EventBus.empire_tribute_paid.emit(amounts.duplicate())
				EventBus.notification_posted.emit(Tr.t("MSG_EMPIRE_TRIBUTE") % amounts_text(amounts), "success", UITheme.POSITIVE)
			"empire_changed":
				EventBus.empire_changed.emit()

func _now() -> float:
	return ProgressionManager.get_played_seconds()

func _interval() -> float:
	return GameConfig.get_duration(GameConfig.empire_tribute_interval)

func _new_seed() -> int:
	var value: int = randi()
	return value if value != 0 else 1

# ── Guardado ─────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return _book.to_dict()

## Idempotente: sustituye el modelo entero. Sin la clave (guardado anterior a
## esta fase) llega {}: nada empezado, semilla nueva. Si ese guardado ya habia
## ganado el Ataque Final, la fase empieza al terminar la carga (_maybe_start).
func load_save_data(data: Dictionary) -> void:
	_book = ArchipelagoScript.from_dict(data)
	_book.ensure_seed(_new_seed())
	_resting.clear()
	EventBus.empire_changed.emit()

## Partida nueva: se tira todo (ni islas ni tributo pasan a la nueva). Sin aviso.
func reset() -> void:
	_book = ArchipelagoScript.new()
	_book.ensure_seed(_new_seed())
	_resting.clear()
