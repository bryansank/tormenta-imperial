extends GdUnitTestSuite
## Volverse el Imperio (feat/volverse-imperio, docs/06): el servicio
## EmpireManager. Cuando esta activa la fase (modo y Ataque Final ganado), los
## candados de cada isla, el regreso de una columna de conquista, el tributo que
## entra en la bolsa, las recompensas (decoracion antes de rango, piezas de
## bandera), ¿QUE HACER? y el guardado (incluido el guardado viejo ya ganado).
##
## Toca los autoloads de verdad: cada caso los deja como los encontro.
## Escritas sin correr (regla de Bryan: una sola ronda de pruebas al final).

const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")
const BookScript := preload("res://scripts/empire/Archipelago.gd")
const Gen := preload("res://scripts/empire/ConquestGenerator.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")

var _saved_empire: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_army: Dictionary = {}
var _saved_resources: Dictionary = {}
var _saved_era := 1
var _saved_warehouses := 0
var _saved_mode := 0
var _saved_tier := 0

func before_test() -> void:
	_saved_empire = EmpireManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_army = ArmyManager.get_save_data()
	_saved_mode = GameMode.current
	_saved_tier = GameMode.tier
	_saved_era = ResourceManager.get_era()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	CombatManager.reset()
	EmpireManager.reset()
	ProgressionManager.final_audit = null
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0})
	ResourceManager.set_era(3)
	ResourceManager.set_warehouse_count(5)

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	ArmyManager.load_save_data(_saved_army)
	EmpireManager.load_save_data(_saved_empire)
	GameMode.begin_run(_saved_mode, _saved_tier)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_amounts(_saved_resources)

## Un Ataque Final ya ganado en ProgressionManager y, con el final con eleccion
## (v1.2), el libro FIRMADO (sin pasar por choose_ending: sin avisos ni guardado).
func _win_audit(sign := true) -> void:
	var audit: FinalAudit = FinalAuditScript.create(99, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit
	if sign:
		EmpireManager._ending = EmpireManager.ENDING_SIGN

func _book() -> Archipelago:
	return EmpireManager.get_book()

# ── Cuando hay fase ──────────────────────────────────────────────────

func test_no_phase_before_winning_the_final_attack() -> void:
	assert_bool(EmpireManager.is_active()).is_false()
	assert_str(EmpireManager.lock_reason("gulls")).is_equal("EMP_LOCK_PHASE")
	assert_str(EmpireManager.next_target()).is_equal("")

func test_winning_the_final_attack_opens_the_phase() -> void:
	_win_audit()
	assert_bool(EmpireManager.is_active()).is_true()
	EmpireManager._maybe_start()
	assert_bool(_book().started).is_true()

func test_builder_and_sandbox_have_no_phase() -> void:
	_win_audit()
	GameMode.begin_run(GameMode.Mode.BUILDER)
	assert_bool(EmpireManager.is_active()).is_false()
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(EmpireManager.is_active()).is_false()
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	assert_bool(EmpireManager.is_active()).is_true()

## Final con eleccion (v1.2): un guardado ganado sin clave "empire" vuelve a la
## mesa del libro (no entra solo en la fase); uno de la rama del imperio que ya
## la habia empezado, firmo.
func test_an_old_saved_victory_goes_back_to_the_book_on_load() -> void:
	_win_audit(false)
	EmpireManager.load_save_data({})
	assert_bool(EmpireManager.choice_pending()).is_true()
	EventBus.game_load_completed.emit()
	assert_bool(_book().started).is_false()
	assert_bool(EmpireManager.is_active()).is_false()

func test_an_old_started_empire_save_counts_as_signed() -> void:
	_win_audit(false)
	var data: Dictionary = BookScript.new().to_dict()
	data["started"] = true
	EmpireManager.load_save_data(data)
	assert_str(EmpireManager.ending()).is_equal(EmpireManager.ENDING_SIGN)
	assert_bool(EmpireManager.is_active()).is_true()

# ── Candados ─────────────────────────────────────────────────────────

func test_islands_that_need_others_say_how_many() -> void:
	_win_audit()
	var gated: String = ""
	for id in BookScript.island_ids():
		if BookScript.needs(id) > 0:
			gated = id
			break
	assert_str(EmpireManager.lock_reason(gated)).is_equal("EMP_LOCK_NEEDS")
	assert_str(EmpireManager.lock_text(gated)).is_not_empty()

func test_a_sea_mission_needs_a_shipyard() -> void:
	_win_audit()
	# Gaviotas empieza por mar; sin Astillero no se sale.
	assert_str(EmpireManager.next_domain("gulls")).is_equal("sea")
	if ArmyManager.building_count("shipyard") <= 0:
		assert_str(EmpireManager.lock_reason("gulls")).is_equal("CAMP_LOCK_BUILDING")

func test_a_conquered_island_is_done() -> void:
	_win_audit()
	for m in range(BookScript.total("gulls")):
		_book().finish("gulls", m, true, 0.0, 0.0, 100.0)
	assert_str(EmpireManager.lock_reason("gulls")).is_equal("EMP_DONE")
	assert_str(EmpireManager.next_domain("gulls")).is_equal("")

func test_launch_refuses_a_locked_island() -> void:
	assert_bool(EmpireManager.launch_conquest("gulls", {"torpedo_boat": 2})).is_false()
	assert_bool(CombatManager.has_active_expedition()).is_false()

func test_conquest_party_must_be_of_the_mission_domain() -> void:
	var offer: Dictionary = Gen.offer("gulls", 0, 5, 3)
	var check: Dictionary = CombatManager.can_launch_to({"infantry": 2}, offer)
	# O falta tropa en casa, o la infanteria no va al mar: nunca "ok".
	assert_bool(bool(check.get("ok", false))).is_false()

# ── La columna vuelve ────────────────────────────────────────────────

func test_a_won_conquest_mission_moves_the_island() -> void:
	_win_audit()
	EmpireManager._maybe_start()
	CombatManager._last_result = {"victory": true, "conquest_island": "gulls", "conquest_mission": 0}
	var conquered: Array = []
	var on_conquered := func(id): conquered.append(id)
	EventBus.island_conquered.connect(on_conquered)
	EmpireManager._on_expedition_ended(0, {}, {})
	assert_int(EmpireManager.won("gulls")).is_equal(1)
	CombatManager._last_result = {"victory": true, "conquest_island": "gulls", "conquest_mission": 1}
	EmpireManager._on_expedition_ended(0, {}, {})
	EventBus.island_conquered.disconnect(on_conquered)
	assert_bool(EmpireManager.is_conquered("gulls")).is_true()
	assert_array(conquered).contains(["gulls"])

func test_a_lost_mission_changes_nothing() -> void:
	_win_audit()
	CombatManager._last_result = {"victory": false, "conquest_island": "ember", "conquest_mission": 0}
	EmpireManager._on_expedition_ended(1, {}, {})
	assert_int(EmpireManager.won("ember")).is_equal(0)

func test_other_expeditions_are_ignored() -> void:
	_win_audit()
	CombatManager._last_result = {"victory": true, "campaign_domain": "land", "campaign_mission": 0}
	EmpireManager._on_expedition_ended(0, {}, {})
	for id in BookScript.island_ids():
		assert_int(EmpireManager.won(id)).is_equal(0)

# ── Tributo y recompensas ────────────────────────────────────────────

func test_tribute_goes_into_the_bag() -> void:
	_win_audit()
	var wood_before: int = ResourceManager.get_amount(ResourceManager.Type.WOOD)
	EmpireManager._publish([{"e": "tribute", "amounts": {"wood": 25}}])
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(wood_before + 25)

func test_tribute_text_lists_every_resource() -> void:
	var text: String = EmpireManager.amounts_text({"wood": 80, "gold": 40})
	assert_str(text).contains("80")
	assert_str(text).contains("40")

func test_a_conquered_island_opens_its_decoration_and_flag_pieces() -> void:
	_win_audit()
	var reward: Dictionary = BookScript.reward_of("gulls")
	var building: String = String((reward.get("buildings", []) as Array)[0])
	var before: bool = RankManager.is_building_unlocked(building)
	for m in range(BookScript.total("gulls")):
		_book().finish("gulls", m, true, 0.0, 0.0, 100.0)
	assert_bool(RankManager.is_building_unlocked(building)).is_true()
	if not before:
		assert_bool(EmpireManager.unlocks_building(building)).is_true()
	# Puerto Niebla da el emblema del barco.
	for id in ["ember", "fog"]:
		for m in range(BookScript.total(id)):
			_book().finish(id, m, true, 0.0, 0.0, 100.0)
	assert_bool(EmpireManager.unlocks_piece("emblems", "ship")).is_true()
	assert_bool(ColonyIdentity.is_piece_open("emblems", "ship", 1)).is_true()

func test_reward_lines_are_translated() -> void:
	for id in BookScript.island_ids():
		for line in EmpireManager.reward_lines(id):
			assert_str(String(line)).is_not_empty()
			assert_bool(String(line).begins_with("EMP_")).is_false()

func test_imperial_title_after_the_first_island() -> void:
	_win_audit()
	assert_str(EmpireManager.title_key()).is_equal("")
	for m in range(BookScript.total("gulls")):
		_book().finish("gulls", m, true, 0.0, 0.0, 100.0)
	assert_str(EmpireManager.title_key()).is_equal("EMP_TITLE_PROTECTOR")

# ── ¿QUE HACER? ──────────────────────────────────────────────────────

func test_what_to_do_points_to_a_conquest_after_winning() -> void:
	_win_audit()
	var step: Dictionary = Objectives.empire_step()
	assert_bool(step.is_empty()).is_false()
	assert_bool(String(step["kind"]) in ["conquest", "build", "train"]).is_true()
	var text: Dictionary = Objectives.describe(step)
	assert_str(String(text["title"])).is_not_empty()

func test_what_to_do_is_quiet_before_winning() -> void:
	assert_bool(Objectives.empire_step().is_empty()).is_true()

# ── Guardado ─────────────────────────────────────────────────────────

func test_save_and_load_keep_the_archipelago() -> void:
	_win_audit()
	EmpireManager._maybe_start()
	_book().finish("gulls", 0, true, 0.0, 0.0, 100.0)
	var data: Dictionary = EmpireManager.get_save_data()
	EmpireManager.reset()
	assert_int(EmpireManager.won("gulls")).is_equal(0)
	EmpireManager.load_save_data(data)
	assert_int(EmpireManager.won("gulls")).is_equal(1)
	assert_bool(_book().started).is_true()
	# Cargar dos veces no suma nada.
	EmpireManager.load_save_data(data)
	assert_int(EmpireManager.won("gulls")).is_equal(1)

func test_reset_throws_everything_away() -> void:
	_win_audit()
	EmpireManager._maybe_start()
	for m in range(BookScript.total("gulls")):
		_book().finish("gulls", m, true, 0.0, 0.0, 100.0)
	EmpireManager.reset()
	assert_int(EmpireManager.conquered_count()).is_equal(0)
	assert_bool(_book().started).is_false()

func test_the_three_new_game_paths_reset_the_empire() -> void:
	# CLAUDE.md "Adding Persistent State": reset() en los tres sitios.
	var source: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	assert_int(source.count("EmpireManager.reset()")).is_equal(3)
	assert_bool(source.contains("data[\"empire\"] = EmpireManager.get_save_data()")).is_true()
