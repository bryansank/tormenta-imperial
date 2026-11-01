extends Node
## Logros y estadisticas (feat/logros-estadisticas, docs/29).
##
## Dos cosas distintas, cada una en su sitio:
##   - ESTADISTICAS de la partida: contadores (edificios terminados, combates
##     ganados, Impuestos pagados...). Viajan en el guardado bajo "stats" y se
##     tiran con reset() en una partida nueva.
##   - LOGROS del perfil: "esta estadistica llega a tanto"
##     (GameConfig.achievement_definitions). Se apuntan en settings.cfg
##     [perfil] achievements (GameConfig.record_achievement) y sobreviven a
##     "Nueva partida". En Sandbox no se gana ninguno
##     (GameMode.achievements_enabled()); las estadisticas se cuentan igual.
##
## Todo llega por el EventBus: ningun servicio sabe que esto existe. Sin
## _process: cada contador sube cuando llega su senal y solo entonces se miran
## los logros de ese contador.
##
## Al ganar uno: EventBus.achievement_unlocked (AudioManager toca su sonido) y
## un aviso "achievement" por notification_posted (NotificationPanel: espera si
## hay una ventana o el tablero abiertos, como los hitos y los ascensos).
##
## Va el ultimo de los autoloads: solo lee a los demas.

## Los contadores que se guardan (los demas se ignoran al cargar). "era",
## "rank" y "max_level" son maximos; el resto, sumas.
const STAT_KEYS := [
	"buildings_built", "roads_built", "upgrades", "max_level", "buildings_demolished",
	"resources_collected", "trades", "techs_researched", "contracts_delivered",
	"smuggler_deals", "units_trained", "units_lost", "enemies_defeated",
	"fights_won", "fights_lost", "flawless_wins", "routs", "expeditions_won",
	"campaign_missions", "campaign_land", "campaign_sea", "campaign_air",
	"storms", "tithes_paid", "tithes_repelled", "deserters", "audits_won",
	"ending_sign", "ending_burn", "islands_conquered", "archipelago",
	"governor_wins", "era", "rank",
]
const MAX_KEYS := ["era", "rank", "max_level"]

var _stats: Dictionary = {}
## Unidades propias caidas en el tablero abierto (para "sin un rasguno"). Es de
## la pelea en curso: las peleas no se guardan, asi que esto tampoco.
var _board_losses := 0

func _ready() -> void:
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	EventBus.building_demolished.connect(func(_n, _c): count("buildings_demolished"))
	EventBus.production_collected.connect(_on_collected)
	EventBus.market_trade_completed.connect(func(_r, _a, _b, _p): count("trades"))
	EventBus.milestone_completed.connect(_on_milestone)
	EventBus.contract_delivered.connect(func(_s, _c, _r): count("contracts_delivered"))
	EventBus.smuggler_offer_taken.connect(func(_i, _o): count("smuggler_deals"))
	EventBus.era_advanced.connect(func(era): raise_max("era", era))
	EventBus.governor_xp_changed.connect(func(_xp, rank, _g): raise_max("rank", rank))
	EventBus.unit_trained.connect(func(_u): count("units_trained"))
	EventBus.army_deserted.connect(func(_u, n): count("deserters", maxi(1, int(n))))
	EventBus.encounter_started.connect(func(_i, _b): _board_losses = 0)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.defense_auto_resolved.connect(func(victory, _r, _s): _on_fight(victory))
	EventBus.enemy_routed.connect(func(): count("routs"))
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.campaign_mission_won.connect(func(_d, _m, _b): count("campaign_missions"))
	EventBus.campaign_completed.connect(_on_campaign_completed)
	EventBus.storm_ended.connect(func(_s): count("storms"))
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.storm_halted_forever.connect(func(): count("audits_won"))
	EventBus.victory_achieved.connect(_on_victory)
	EventBus.ending_chosen.connect(_on_ending_chosen)
	EventBus.island_conquered.connect(func(_i): count("islands_conquered"))
	EventBus.archipelago_conquered.connect(func(): count("archipelago"))
	# Al cargar: los maximos que se derivan de la partida y un repaso de todos
	# los logros (uno nuevo de una version posterior puede estar ya cumplido).
	EventBus.game_load_completed.connect(_on_game_load_completed)
	EventBus.game_new_started.connect(_on_game_load_completed)

# ── Contadores ──

## Suma `amount` al contador `stat` y mira sus logros. Publico para los tests y
## por si otro servicio necesitara apuntar algo sin senal propia.
func count(stat: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_stats[stat] = int(_stats.get(stat, 0)) + amount
	_check_stat(stat)

## Sube un maximo (era, rango, nivel) si `value` lo supera.
func raise_max(stat: String, value: int) -> void:
	if value <= int(_stats.get(stat, 0)):
		return
	_stats[stat] = value
	_check_stat(stat)

func get_stat(stat: String) -> int:
	if stat == "played":
		return int(ProgressionManager.get_played_seconds())
	return int(_stats.get(stat, 0))

## Copia de todos los contadores (para la pantalla y los tests).
func get_stats() -> Dictionary:
	return _stats.duplicate()

func _on_construction_completed(node: Node) -> void:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	if data.is_core or data.id == "road":
		return
	count("buildings_built")

func _on_building_placed(data: Resource, _cell: Vector2i) -> void:
	if data is BuildingData and (data as BuildingData).id == "road":
		count("roads_built")

func _on_upgrade_completed(_node: Node, level: int) -> void:
	count("upgrades")
	raise_max("max_level", level)

func _on_collected(_node: Node, collected: Dictionary) -> void:
	var total := 0
	for res in collected:
		total += maxi(0, int(collected[res]))
	count("resources_collected", total)

## Las tecnologias llegan como hitos "tech_<id>" (TechTreeManager).
func _on_milestone(milestone_id: String) -> void:
	if milestone_id.begins_with("tech_"):
		count("techs_researched")

func _on_unit_died(_uid: int, side: int) -> void:
	if side == 0:
		_board_losses += 1
		count("units_lost")
	else:
		count("enemies_defeated")

func _on_encounter_ended(victory: bool, _turns: int) -> void:
	_on_fight(victory)
	if victory and _board_losses == 0:
		count("flawless_wins")
	_board_losses = 0

func _on_fight(victory: bool) -> void:
	count("fights_won" if victory else "fights_lost")

## `result` 0 = victoria (EventBus).
func _on_expedition_ended(result: int, _rewards: Dictionary, _casualties: Dictionary) -> void:
	if result == 0:
		count("expeditions_won")

func _on_campaign_completed(domain: String) -> void:
	if domain in ["land", "sea", "air"]:
		count("campaign_" + domain)

## `repelled` es el primer argumento. Un modo sin Impuesto y el asedio emiten
## (true, {}) sin que nadie haya peleado: eso no cuenta como repelido.
func _on_tithe_resolved(repelled: bool, _taken: Dictionary) -> void:
	if not GameMode.tithe_enabled() or ProgressionManager.is_final_audit_active():
		return
	count("tithes_repelled" if repelled else "tithes_paid")

func _on_victory(_stats_in: Dictionary) -> void:
	if GameMode.is_governor():
		count("governor_wins")

func _on_ending_chosen(choice: String) -> void:
	if choice in ["sign", "burn"]:
		count("ending_" + choice)

func _on_game_load_completed() -> void:
	raise_max("era", ProgressionManager.current_era)
	raise_max("rank", RankManager.get_rank())
	check_all()

# ── Logros ──

func is_unlocked(achievement_id: String) -> bool:
	return GameConfig.profile_achievements.has(achievement_id)

## Hora unix en que se gano (0 si no).
func unlocked_at(achievement_id: String) -> int:
	return int(GameConfig.profile_achievements.get(achievement_id, 0))

func unlocked_count() -> int:
	var n := 0
	for def in GameConfig.achievement_definitions:
		if is_unlocked(String(def["id"])):
			n += 1
	return n

func total_count() -> int:
	return GameConfig.achievement_definitions.size()

## Lo que lleva esta partida hacia un logro: Vector2i(hecho, meta), con
## `hecho` sin pasar de la meta.
func progress(achievement_id: String) -> Vector2i:
	var def := GameConfig.achievement_def(achievement_id)
	if def.is_empty():
		return Vector2i.ZERO
	var goal := maxi(1, int(def.get("goal", 1)))
	return Vector2i(mini(get_stat(String(def["stat"])), goal), goal)

## Mira los logros de un contador.
func _check_stat(stat: String) -> void:
	if not GameMode.achievements_enabled():
		return
	for def in GameConfig.achievement_definitions:
		if String(def.get("stat", "")) == stat:
			_check_def(def)

## Mira todos (al cargar o empezar).
func check_all() -> void:
	if not GameMode.achievements_enabled():
		return
	for def in GameConfig.achievement_definitions:
		_check_def(def)

func _check_def(def: Dictionary) -> void:
	var id := String(def.get("id", ""))
	if is_unlocked(id):
		return
	if get_stat(String(def.get("stat", ""))) >= int(def.get("goal", 1)):
		_unlock(id)

## Apunta el logro en el perfil, lo anuncia y suena. Una vez por dispositivo.
func _unlock(achievement_id: String) -> void:
	if not GameConfig.record_achievement(achievement_id, int(Time.get_unix_time_from_system())):
		return
	EventBus.achievement_unlocked.emit(achievement_id)
	EventBus.notification_posted.emit(
		Tr.t("FMT_ACHIEVEMENT_UNLOCKED") % Tr.t(name_key(achievement_id)),
		"achievement", UITheme.ACCENT)

static func name_key(achievement_id: String) -> String:
	return "ACH_%s_NAME" % achievement_id.to_upper()

static func desc_key(achievement_id: String) -> String:
	return "ACH_%s_DESC" % achievement_id.to_upper()

# ── Guardado (clave "stats") ──

func get_save_data() -> Dictionary:
	return _stats.duplicate()

## Idempotente: los contadores son los guardados, no se suman a los de ahora.
## Sin clave (partida de antes de los logros) todo empieza en 0. Un contador
## desconocido se ignora.
func load_save_data(data: Dictionary) -> void:
	_stats = {}
	for key in data:
		var stat := str(key)
		if stat in STAT_KEYS:
			var value := maxi(0, int(data[key]))
			if value > 0:
				_stats[stat] = value
	_board_losses = 0

## Partida nueva: contadores a cero. Sin avisos. Los logros del perfil no se
## tocan nunca.
func reset() -> void:
	_stats = {}
	_board_losses = 0
