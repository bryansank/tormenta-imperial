extends GdUnitTestSuite
## Colono y Gobernador (docs/20, "Colono y Gobernador"): el nivel es una
## dificultad sobre la Campana, fijo para la partida, guardado en `game_mode`;
## se desbloquea por PERFIL (settings.cfg [perfil], nunca la partida); y lo que
## cambia (mercado con calendario, combate mas duro, lo acumulado se estropea)
## solo cambia en Gobernador.
##
## Toca settings.cfg (el perfil): lo aparta con tests/save/settings_parking.gd.

const Parking := preload("res://tests/save/settings_parking.gd")
const DialogScript := preload("res://scripts/ui/NewGameDialog.gd")
const MarketPanelScript := preload("res://scripts/ui/MarketPanel.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")

## La partida activa (user://partidas/partida_<id>.json, docs/09).
var SAVE_PATH: String:
	get:
		return GameManager.save_path()

var _parked: Dictionary = {}
var _dev_mode: bool = true
var _market: Dictionary = {}
var _cycle: StormCycle = null
var _save_existed := false
var _save_bytes := PackedByteArray()

func before_test() -> void:
	_parked = Parking.park()
	_dev_mode = GameConfig.dev_mode
	_market = MarketManager.get_save_data()
	_cycle = StormManager._cycle
	_save_existed = FileAccess.file_exists(SAVE_PATH)
	if _save_existed:
		_save_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
	GameConfig.profile_runs_finished = 0
	GameConfig.profile_campaigns_won = 0

func after_test() -> void:
	GameConfig.dev_mode = _dev_mode
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	MarketManager.reset()
	MarketManager.load_save_data(_market)
	StormManager._cycle = _cycle
	Parking.restore(_parked)

func _dialog(current_mode: int = GameMode.Mode.CAMPAIGN, current_tier: int = GameMode.TIER_DEFAULT) -> CanvasLayer:
	var dialog: CanvasLayer = auto_free(DialogScript.new())
	dialog.setup(current_mode, current_tier)
	add_child(dialog)
	return dialog

func _locked_profile() -> void:
	GameConfig.dev_mode = false
	GameConfig.profile_runs_finished = 0
	GameConfig.profile_campaigns_won = 0

func _storm_phase(phase: int) -> void:
	var cycle := StormCycle.new()
	cycle.phase = phase
	StormManager._cycle = cycle

# ── Reglas por nivel ─────────────────────────────────────────────────

func test_colonist_keeps_every_rule_of_today() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)
	assert_bool(GameMode.spoilage_enabled()).is_false()
	assert_bool(GameMode.market_dynamic()).is_false()
	assert_bool(GameMode.combat_hard()).is_false()
	assert_float(GameMode.expedition_enemy_mult()).is_equal(1.0)
	assert_float(GameMode.tithe_force_mult()).is_equal(1.0)
	assert_float(GameMode.audit_enemy_mult()).is_equal(1.0)

func test_governor_turns_on_the_three_rules() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_bool(GameMode.is_governor()).is_true()
	assert_bool(GameMode.spoilage_enabled()).is_true()
	assert_bool(GameMode.market_dynamic()).is_true()
	assert_bool(GameMode.combat_hard()).is_true()
	assert_float(GameMode.expedition_enemy_mult()).is_greater(1.0)
	assert_float(GameMode.tithe_force_mult()).is_greater(1.0)
	assert_float(GameMode.audit_enemy_mult()).is_greater(1.0)

func test_governor_does_not_touch_the_mode_rules() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_bool(GameMode.storm_enabled()).is_true()
	assert_bool(GameMode.audit_enabled()).is_true()
	assert_float(GameMode.tithe_mult()).is_equal(1.0)

## Gobernador es una dificultad de la Campana: otro modo lo ignora.
func test_tier_only_exists_in_the_campaign() -> void:
	for mode in [GameMode.Mode.BUILDER, GameMode.Mode.SURVIVAL, GameMode.Mode.SANDBOX]:
		GameMode.begin_run(mode, GameMode.Tier.GOVERNOR)
		assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)
		assert_bool(GameMode.market_dynamic()).is_false()

# ── Guardado y reset ─────────────────────────────────────────────────

func test_the_tier_travels_in_game_mode() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	var data := GameMode.get_save_data()
	assert_str(String(data["mode"])).is_equal("campaign")
	assert_str(String(data["tier"])).is_equal("governor")
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GameMode.load_save_data(data)
	assert_int(GameMode.tier).is_equal(GameMode.Tier.GOVERNOR)

func test_an_old_save_without_tier_is_colonist() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	GameMode.load_save_data({"mode": "campaign", "result": ""})
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	GameMode.load_save_data({})
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)

func test_an_unknown_tier_is_colonist() -> void:
	GameMode.load_save_data({"mode": "campaign", "tier": "emperador"})
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)
	GameMode.load_save_data({"mode": "campaign", "tier": 7})
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)

## El reset de una partida nueva sin nivel es Colono; reiniciar la partida en
## curso conserva el suyo (asi lo hace GameManager en sus tres reinicios).
func test_begin_run_resets_the_tier() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	GameMode.begin_run(GameMode.current, GameMode.tier)
	assert_int(GameMode.tier).is_equal(GameMode.Tier.GOVERNOR)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_int(GameMode.tier).is_equal(GameMode.Tier.COLONIST)

func test_market_reset_forgets_the_after_tithe_window() -> void:
	MarketManager._on_tithe_resolved(true, {})
	assert_float(MarketManager.after_tithe_seconds_left()).is_greater(0.0)
	MarketManager.reset()
	assert_float(MarketManager.after_tithe_seconds_left()).is_equal(0.0)

func test_market_after_tithe_window_is_saved_and_old_saves_load() -> void:
	MarketManager._on_tithe_resolved(false, {})
	var data := MarketManager.get_save_data()
	MarketManager.reset()
	MarketManager.load_save_data(data)
	assert_float(MarketManager.after_tithe_seconds_left()).is_equal(GameConfig.market_after_tithe_seconds)
	MarketManager.load_save_data({"price_mods": {"wood": 1.0, "steel": 1.0, "oil": 1.0}})
	assert_float(MarketManager.after_tithe_seconds_left()).is_equal(0.0)

# ── El desbloqueo es del perfil ──────────────────────────────────────

func test_a_fresh_profile_keeps_governor_locked() -> void:
	_locked_profile()
	assert_bool(GameConfig.governor_unlocked_by_profile()).is_false()
	assert_bool(GameMode.governor_unlocked()).is_false()

func test_dev_mode_always_unlocks_governor() -> void:
	_locked_profile()
	GameConfig.dev_mode = true
	assert_bool(GameMode.governor_unlocked()).is_true()

func test_finishing_a_run_unlocks_it_in_settings_not_in_the_save() -> void:
	_locked_profile()
	GameConfig.record_run_finished(false)
	assert_bool(GameMode.governor_unlocked()).is_true()
	# En settings.cfg [perfil]...
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	assert_int(int(cf.get_value("perfil", "runs_finished", 0))).is_equal(1)
	# ...y en ningun sitio de la partida.
	assert_bool(JSON.stringify(GameMode.get_save_data()).contains("runs_finished")).is_false()
	# Y vuelve a leerse al arrancar.
	GameConfig.profile_runs_finished = 0
	GameConfig.load_user_settings()
	assert_int(GameConfig.profile_runs_finished).is_equal(1)

func test_winning_a_campaign_counts_as_won() -> void:
	_locked_profile()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GameManager._on_victory_for_profile({})
	assert_int(GameConfig.profile_runs_finished).is_equal(1)
	assert_int(GameConfig.profile_campaigns_won).is_equal(1)
	assert_bool(GameMode.governor_unlocked()).is_true()

func test_losing_the_audit_in_the_campaign_finishes_the_run() -> void:
	_locked_profile()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GameManager._on_audit_lost_for_profile(2)
	assert_int(GameConfig.profile_runs_finished).is_equal(1)
	assert_int(GameConfig.profile_campaigns_won).is_equal(0)

## En Supervivencia la derrota la anota run_ended: perder la Auditoria no
## cuenta dos veces.
func test_survival_audit_loss_is_not_counted_twice() -> void:
	_locked_profile()
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	GameManager._on_audit_lost_for_profile(1)
	assert_int(GameConfig.profile_runs_finished).is_equal(0)

func test_the_profile_survives_a_new_game() -> void:
	_locked_profile()
	GameConfig.record_run_finished(true)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	MarketManager.reset()
	assert_bool(GameConfig.governor_unlocked_by_profile()).is_true()

# ── El selector ──────────────────────────────────────────────────────

func test_locked_dialog_shows_the_lock_and_the_condition() -> void:
	_locked_profile()
	var dialog := _dialog()
	var card: Button = dialog.tier_card(GameMode.Tier.GOVERNOR)
	assert_object(card).is_not_null()
	assert_bool(card.disabled).is_true()
	assert_object(card.find_child("Lock", true, false)).is_not_null()
	var label: Label = dialog.find_child("TierLockLabel", true, false)
	assert_bool(label.visible).is_true()
	assert_int(label.text.split(" ", false).size()).is_less_equal(8)
	assert_bool(dialog.pick_tier(GameMode.Tier.GOVERNOR)).is_false()
	assert_int(dialog.effective_tier()).is_equal(GameMode.Tier.COLONIST)

func test_unlocked_dialog_lets_you_pick_governor() -> void:
	_locked_profile()
	GameConfig.record_run_finished(false)
	var dialog := _dialog()
	var card: Button = dialog.tier_card(GameMode.Tier.GOVERNOR)
	assert_bool(card.disabled).is_false()
	assert_object(card.find_child("Lock", true, false)).is_null()
	assert_bool((dialog.find_child("TierLockLabel", true, false) as Label).visible).is_false()
	assert_bool(dialog.pick_tier(GameMode.Tier.GOVERNOR)).is_true()
	assert_int(dialog.effective_tier()).is_equal(GameMode.Tier.GOVERNOR)
	assert_bool(card.button_pressed).is_true()

func test_dev_mode_dialog_is_always_unlocked() -> void:
	_locked_profile()
	GameConfig.dev_mode = true
	var dialog := _dialog()
	assert_bool(dialog.is_governor_locked()).is_false()

func test_the_dialog_repeats_the_tier_of_the_run_it_replaces() -> void:
	GameConfig.dev_mode = true
	var dialog := _dialog(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_int(dialog.chosen_tier).is_equal(GameMode.Tier.GOVERNOR)
	_locked_profile()
	var locked := _dialog(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_int(locked.chosen_tier).is_equal(GameMode.Tier.COLONIST)

func test_tier_row_only_shows_for_the_campaign() -> void:
	GameConfig.dev_mode = true
	var dialog := _dialog()
	var box: Control = dialog.find_child("TierBox", true, false)
	assert_bool(box.visible).is_true()
	dialog._select(GameMode.Mode.BUILDER)
	assert_bool(box.visible).is_false()
	dialog.pick_tier(GameMode.Tier.GOVERNOR)
	assert_int(dialog.effective_tier()).is_equal(GameMode.Tier.COLONIST)

# ── Mercado dinamico (solo Gobernador) ───────────────────────────────

func test_the_storm_calendar_is_a_fixed_pattern() -> void:
	var M = MarketManager
	assert_str(M.season_for(StormCycle.Phase.CALM, false)).is_equal("calm")
	assert_str(M.season_for(StormCycle.Phase.WARNING, false)).is_equal("warning")
	assert_str(M.season_for(StormCycle.Phase.ASH, false)).is_equal("warning")
	assert_str(M.season_for(StormCycle.Phase.STORM, false)).is_equal("storm")
	assert_str(M.season_for(StormCycle.Phase.TITHE, false)).is_equal("after_tithe")
	assert_str(M.season_for(StormCycle.Phase.CALM, true)).is_equal("after_tithe")
	assert_float(float(GameConfig.market_calendar["warning"]["wood"])).is_greater(0.0)
	assert_float(float(GameConfig.market_calendar["storm"]["steel"])).is_less(0.0)
	for res in ["wood", "steel", "oil"]:
		assert_float(float(GameConfig.market_calendar["after_tithe"][res])).is_greater(0.0)
	assert_bool((GameConfig.market_calendar["calm"] as Dictionary).is_empty()).is_true()

func test_colonist_market_ignores_the_storm() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	_storm_phase(StormCycle.Phase.WARNING)
	assert_str(MarketManager.season()).is_equal("calm")
	assert_float(MarketManager.target_mod("wood")).is_equal(1.0)
	assert_float(MarketManager.tick_interval()).is_equal(10.0 if GameConfig.dev_mode else GameConfig.market_tick_interval)
	MarketManager.reset()
	for i in range(5):
		MarketManager._apply_mean_reversion()
	assert_float(float(MarketManager._price_mods["wood"])).is_between(0.9, 1.1)

func test_governor_warning_pushes_wood_up() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	_storm_phase(StormCycle.Phase.WARNING)
	MarketManager.reset()
	var before: int = MarketManager.get_buy_price("wood")
	assert_float(MarketManager.get_price_trend("wood")).is_equal(1.0)
	for i in range(6):
		MarketManager._apply_mean_reversion()
	assert_float(float(MarketManager._price_mods["wood"])).is_greater(1.2)
	assert_int(MarketManager.get_buy_price("wood")).is_greater(before)

func test_governor_storm_pushes_steel_down() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	_storm_phase(StormCycle.Phase.STORM)
	MarketManager.reset()
	assert_float(MarketManager.get_price_trend("steel")).is_equal(-1.0)
	for i in range(6):
		MarketManager._apply_mean_reversion()
	assert_float(float(MarketManager._price_mods["steel"])).is_less(0.82)

func test_governor_after_tithe_gold_is_worth_less_then_calm_returns() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	_storm_phase(StormCycle.Phase.CALM)
	MarketManager.reset()
	MarketManager._on_tithe_resolved(true, {})
	assert_str(MarketManager.season()).is_equal("after_tithe")
	for i in range(6):
		MarketManager._apply_mean_reversion()
	for res in ["wood", "steel", "oil"]:
		assert_float(float(MarketManager._price_mods[res])).is_greater(1.08)
	# El reloj se acaba: calma, y todo vuelve a la media.
	MarketManager._after_tithe_left = 0.0
	assert_str(MarketManager.season()).is_equal("calm")
	for i in range(10):
		MarketManager._apply_mean_reversion()
	for res in ["wood", "steel", "oil"]:
		assert_float(float(MarketManager._price_mods[res])).is_between(0.92, 1.08)

func test_governor_market_ticks_faster() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	GameConfig.dev_mode = false
	assert_float(MarketManager.tick_interval()).is_equal(GameConfig.market_dynamic_tick_interval)
	assert_float(MarketManager.tick_interval()).is_less(GameConfig.market_tick_interval)

func test_spread_is_buy_minus_sell() -> void:
	MarketManager.reset()
	assert_int(MarketManager.get_spread("steel")).is_equal(
		MarketManager.get_buy_price("steel") - MarketManager.get_sell_price("steel"))
	assert_int(MarketManager.get_spread("steel")).is_greater(0)

func test_market_panel_shows_spread_and_trend_only_in_governor() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var colonist: CanvasLayer = auto_free(MarketPanelScript.new())
	add_child(colonist)
	assert_object(colonist.find_child("Spread_wood", true, false)).is_null()
	assert_object(colonist.find_child("Trend_wood", true, false)).is_null()
	assert_object(colonist.find_child("SeasonLabel", true, false)).is_null()

	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	_storm_phase(StormCycle.Phase.WARNING)
	MarketManager.reset()
	var governor: CanvasLayer = auto_free(MarketPanelScript.new())
	add_child(governor)
	var spread: Label = governor.find_child("Spread_wood", true, false)
	assert_object(spread).is_not_null()
	assert_str(spread.text).is_equal(str(MarketManager.get_spread("wood")))
	var trend: Control = governor.find_child("Trend_wood", true, false)
	assert_int(int(trend.get_meta("trend"))).is_equal(1)
	governor._update_prices()
	var season: Label = governor.find_child("SeasonLabel", true, false)
	assert_str(season.text).is_equal(Tr.t("MARKET_SEASON_WARNING"))

# ── Combate mas duro (solo Gobernador) ───────────────────────────────

func test_expedition_enemies_are_tougher_only_in_governor() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var base: float = Generator.enemy_scale(2, 2, 1)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	var hard: float = Generator.enemy_scale(2, 2, 1)
	assert_float(hard).is_equal_approx(base * GameMode.expedition_enemy_mult(), 0.0001)
	assert_float(hard).is_greater(base)

func test_the_first_sortie_keeps_its_fixed_scale() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	var node := {"enemy_scale": GameConfig.combat_first_sortie_enemy_scale}
	assert_float(Generator.node_scale(node, 1)).is_equal(GameConfig.combat_first_sortie_enemy_scale)

func test_the_tithe_escort_is_bigger_only_in_governor() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var base: Dictionary = StormManager.assessor_roster(2)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	var hard: Dictionary = StormManager.assessor_roster(2)
	assert_int(_bodies(hard)).is_greater(_bodies(base))
	assert_int(_bodies(hard)).is_less_equal(GameConfig.combat_deploy_cap)

func test_the_final_audit_waves_hit_harder_only_in_governor() -> void:
	var garrison := {"vehicle": 6}
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var base: float = FinalAuditScript.create(7, garrison, 3, 100.0).wave_scale(1, 4)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	var hard: float = FinalAuditScript.create(7, garrison, 3, 100.0).wave_scale(1, 4)
	assert_float(hard).is_equal_approx(base * GameMode.audit_enemy_mult(), 0.0001)
	assert_float(hard).is_greater(base)

## Mismas reglas: Gobernador no toca CombatRules, solo escala al enemigo.
func test_governor_leaves_the_loot_alone() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var base: Dictionary = Generator.node_rewards({"depth": 2, "risk": 1}, 2)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	assert_dict(Generator.node_rewards({"depth": 2, "risk": 1}, 2)).is_equal(base)

func _bodies(roster: Dictionary) -> int:
	var n := 0
	for k in roster:
		n += int(roster[k])
	return n
