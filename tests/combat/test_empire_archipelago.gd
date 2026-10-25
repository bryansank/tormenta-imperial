extends GdUnitTestSuite
## Volverse el Imperio (feat/volverse-imperio, docs/06): el modelo puro
## Archipelago (islas, misiones, tributo, recompensas, guardado) y las misiones
## de conquista de ConquestGenerator (oferta, mapa de dominio puro, botin).
## Escritas sin correr (regla de Bryan: una sola ronda de pruebas al final).

const BookScript := preload("res://scripts/empire/Archipelago.gd")
const Gen := preload("res://scripts/empire/ConquestGenerator.gd")
const ExpGen := preload("res://scripts/combat/ExpeditionGenerator.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")

const SEA_UNITS := ["torpedo_boat", "gunboat", "dreadnought"]
const AIR_UNITS := ["fighter", "airship", "bomber"]

func _book() -> Archipelago:
	var book: Archipelago = BookScript.new()
	book.ensure_seed(777)
	return book

## Gana todas las misiones de una isla. Devuelve los eventos.
func _conquer(book: Archipelago, island_id: String, now: float = 0.0) -> Array:
	var all: Array = []
	for m in range(BookScript.total(island_id)):
		all.append_array(book.finish(island_id, m, true, now, 0.0, 100.0))
	return all

func _names(events: Array) -> Array:
	var out: Array = []
	for e in events:
		out.append(String(e.get("e", "")))
	return out

# ── Las islas (GameConfig.empire_islands) ────────────────────────────

func test_there_are_five_to_seven_islands_with_unique_ids() -> void:
	var ids: Array = BookScript.island_ids()
	assert_int(ids.size()).is_between(5, 7)
	var seen := {}
	for id in ids:
		assert_bool(seen.has(id)).override_failure_message("isla repetida: %s" % id).is_false()
		seen[id] = true

func test_each_island_has_missions_tribute_crest_and_reward() -> void:
	for id in BookScript.island_ids():
		var def: Dictionary = BookScript.island_def(id)
		assert_int(BookScript.total(id)).override_failure_message("%s sin misiones" % id).is_greater_equal(1)
		assert_bool(BookScript.tribute_of(id).is_empty()).override_failure_message("%s sin tributo" % id).is_false()
		assert_bool(BookScript.reward_of(id).is_empty()).override_failure_message("%s sin premio" % id).is_false()
		var crest: Dictionary = def.get("crest", {})
		assert_bool(GameConfig.COLONY_PATTERNS.has(String(crest.get("pattern", "")))).is_true()
		assert_bool(GameConfig.COLONY_EMBLEMS.has(String(crest.get("emblem", "")))).is_true()
		for c in crest.get("colors", []):
			assert_bool(GameConfig.colony_colors.has(String(c))).override_failure_message("%s color %s" % [id, c]).is_true()
		for m in BookScript.missions_of(id):
			assert_bool(String(m.get("domain", "")) in ["land", "sea", "air"]).is_true()
			assert_int(int(m.get("fights", 0))).is_between(1, 3)

func test_tribute_and_reward_ids_are_real() -> void:
	for id in BookScript.island_ids():
		for res in BookScript.tribute_of(id):
			assert_int(ResourceManager.name_to_type(String(res))).override_failure_message("%s: %s" % [id, res]).is_not_equal(-1)
		var reward: Dictionary = BookScript.reward_of(id)
		for b in reward.get("buildings", []):
			assert_bool(FileAccess.file_exists("res://data/buildings/%s.tres" % b)).override_failure_message(String(b)).is_true()
		for e in reward.get("emblems", []):
			assert_bool(GameConfig.COLONY_EMBLEMS.has(String(e))).is_true()
		for p in reward.get("patterns", []):
			assert_bool(GameConfig.COLONY_PATTERNS.has(String(p))).is_true()
		for c in reward.get("colors", []):
			assert_bool(GameConfig.colony_colors.has(String(c))).is_true()

func test_every_island_and_mission_is_translated_in_both_languages() -> void:
	var before: String = Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in BookScript.island_ids():
			for key in [Gen.island_name_key(id), "EMP_ISLE_%s_DESC" % id.to_upper()]:
				assert_str(Tr.t(key)).override_failure_message("%s %s" % [locale, key]).is_not_equal(key)
			for m in range(BookScript.total(id)):
				var mk: String = Gen.mission_name_key(id, m)
				assert_str(Tr.t(mk)).override_failure_message("%s %s" % [locale, mk]).is_not_equal(mk)
		for entry in GameConfig.empire_titles:
			assert_str(Tr.t(String(entry["key"]))).is_not_equal(String(entry["key"]))
	Tr.set_locale(before)

func test_at_least_one_island_is_open_from_the_start_and_one_has_a_boss() -> void:
	var open := 0
	var bosses := 0
	for id in BookScript.island_ids():
		if BookScript.needs(id) == 0:
			open += 1
		for m in range(BookScript.total(id)):
			if Gen.is_boss_mission(id, m):
				bosses += 1
				assert_bool(Gen.is_final(id, m)).override_failure_message("el jefe va al final").is_true()
		# Nadie pide mas islas de las que hay sin ella.
		assert_int(BookScript.needs(id)).is_less(BookScript.island_ids().size())
	assert_int(open).is_greater_equal(1)
	assert_int(bosses).is_greater_equal(1)

# ── El modelo ────────────────────────────────────────────────────────

func test_a_new_archipelago_has_nothing_conquered() -> void:
	var book := _book()
	assert_bool(book.started).is_false()
	assert_int(book.conquered_count()).is_equal(0)
	assert_bool(book.all_conquered()).is_false()
	assert_str(book.title_key()).is_equal("")
	assert_bool(book.tribute_per_cycle().is_empty()).is_true()
	var target: String = book.next_target()
	assert_str(target).is_not_empty()
	assert_int(BookScript.needs(target)).is_equal(0)

func test_only_the_next_won_mission_moves_an_island() -> void:
	var book := _book()
	var id: String = "gulls"
	book.finish(id, 0, false, 5.0, 60.0, 100.0)
	assert_int(book.won(id)).is_equal(0)
	assert_int(int(book.setbacks[id])).is_equal(1)
	book.finish(id, 1, true, 5.0, 60.0, 100.0)
	assert_int(book.won(id)).override_failure_message("no se salta misiones").is_equal(0)
	var events: Array = book.finish(id, 0, true, 5.0, 60.0, 100.0)
	assert_int(book.won(id)).is_equal(1)
	assert_str(String(events[0]["e"])).is_equal("conquest_mission_won")
	assert_bool(bool(events[0]["conquered"])).is_false()
	assert_float(book.cooldown_left(id, 35.0)).is_equal(30.0)
	assert_float(book.cooldown_left(id, 100.0)).is_equal(0.0)

func test_winning_the_last_mission_conquers_the_island() -> void:
	var book := _book()
	var names: Array = _names(_conquer(book, "gulls", 50.0))
	assert_bool(book.is_conquered("gulls")).is_true()
	assert_int(book.next_mission("gulls")).is_equal(-1)
	assert_int(names.count("island_conquered")).is_equal(1)
	assert_float(float(book.conquered_at["gulls"])).is_equal(50.0)
	# Ya es tuya: otra mision no cuenta.
	book.finish("gulls", 0, true, 60.0, 0.0, 100.0)
	assert_int(book.won("gulls")).is_equal(BookScript.total("gulls"))

func test_islands_that_need_others_wait() -> void:
	var book := _book()
	var gated: String = ""
	for id in BookScript.island_ids():
		if BookScript.needs(id) >= 1:
			gated = id
			break
	assert_str(gated).is_not_empty()
	assert_bool(book.needs_met(gated)).is_false()
	var conquered := 0
	for id in BookScript.island_ids():
		if conquered >= BookScript.needs(gated):
			break
		if BookScript.needs(id) == 0 and id != gated:
			_conquer(book, id)
			conquered += 1
	if conquered >= BookScript.needs(gated):
		assert_bool(book.needs_met(gated)).is_true()

func test_conquering_everything_says_so_once() -> void:
	var book := _book()
	var names: Array = []
	# En orden de "needs": las que piden menos primero.
	var ids: Array = BookScript.island_ids().duplicate()
	ids.sort_custom(func(a, b): return BookScript.needs(a) < BookScript.needs(b))
	for id in ids:
		names.append_array(_names(_conquer(book, id)))
	assert_bool(book.all_conquered()).is_true()
	assert_int(names.count("archipelago_conquered")).is_equal(1)
	assert_str(book.next_target()).is_equal("")
	assert_str(book.title_key()).is_equal("EMP_TITLE_LORD")

func test_title_climbs_with_islands() -> void:
	var book := _book()
	_conquer(book, "gulls")
	assert_str(book.title_key()).is_equal("EMP_TITLE_PROTECTOR")

# ── El tributo ───────────────────────────────────────────────────────

func test_start_happens_once_and_arms_the_clock() -> void:
	var book := _book()
	var events: Array = book.start(10.0, 100.0)
	assert_bool(book.started).is_true()
	assert_bool(_names(events).has("empire_phase_started")).is_true()
	assert_array(book.start(20.0, 100.0)).is_empty()
	assert_float(book.tribute_next_at).is_equal(110.0)

func test_no_tribute_without_islands() -> void:
	var book := _book()
	book.start(0.0, 100.0)
	assert_array(book.tick(500.0, 100.0)).is_empty()
	assert_int(book.tributes_paid).is_equal(0)

func test_tribute_pays_every_interval_and_never_piles_up() -> void:
	var book := _book()
	book.start(0.0, 100.0)
	_conquer(book, "gulls", 10.0)
	# La primera isla pone el cobro un intervalo despues de tomarla.
	assert_float(book.tribute_next_at).is_equal(110.0)
	assert_array(book.tick(50.0, 100.0)).is_empty()
	var events: Array = book.tick(1000.0, 100.0)
	assert_str(String(events[0]["e"])).is_equal("tribute")
	assert_dict(events[0]["amounts"]).is_equal(BookScript.tribute_of("gulls"))
	assert_int(book.tributes_paid).is_equal(1)
	# Una pausa larga no amontona cobros: el siguiente, un intervalo despues.
	assert_array(book.tick(1001.0, 100.0)).is_empty()
	assert_float(book.tribute_next_at).is_equal(1100.0)

func test_tribute_adds_up_islands() -> void:
	var book := _book()
	book.start(0.0, 10.0)
	_conquer(book, "gulls")
	_conquer(book, "ember")
	var total: Dictionary = book.tribute_per_cycle()
	for id in ["gulls", "ember"]:
		var t: Dictionary = BookScript.tribute_of(id)
		for res in t:
			assert_int(int(total[res])).is_greater_equal(int(t[res]))

# ── Recompensas ──────────────────────────────────────────────────────

func test_rewards_unlock_only_once_conquered() -> void:
	var book := _book()
	var reward: Dictionary = BookScript.reward_of("gulls")
	var building: String = String((reward.get("buildings", [""]) as Array)[0])
	assert_bool(book.unlocks("buildings", building)).is_false()
	_conquer(book, "gulls")
	assert_bool(book.unlocks("buildings", building)).is_true()
	assert_bool(book.unlocks("buildings", "house")).is_false()

# ── Guardado ─────────────────────────────────────────────────────────

func test_save_round_trip_is_idempotent() -> void:
	var book := _book()
	book.start(5.0, 100.0)
	_conquer(book, "gulls", 20.0)
	book.finish("ember", 0, true, 30.0, 60.0, 100.0)
	book.finish("ember", 1, false, 31.0, 60.0, 100.0)
	book.tick(500.0, 100.0)
	book.mark_intro_seen()
	var data: Dictionary = book.to_dict()
	var again: Archipelago = BookScript.from_dict(data)
	assert_dict(again.to_dict()).is_equal(data)
	assert_dict(BookScript.from_dict(again.to_dict()).to_dict()).is_equal(data)
	assert_bool(again.is_conquered("gulls")).is_true()
	assert_int(again.won("ember")).is_equal(1)
	assert_bool(again.intro_seen).is_true()

func test_an_old_save_without_the_key_is_a_fresh_archipelago() -> void:
	var book: Archipelago = BookScript.from_dict({})
	assert_bool(book.started).is_false()
	assert_int(book.conquered_count()).is_equal(0)

func test_load_clamps_and_ignores_unknown_islands() -> void:
	var book: Archipelago = BookScript.from_dict({"seed": 9, "progress": {"gulls": 99, "atlantis": 3}})
	assert_int(book.won("gulls")).is_equal(BookScript.total("gulls"))
	assert_bool(book.progress.has("atlantis")).is_false()

# ── Las misiones (ConquestGenerator) ─────────────────────────────────

func test_the_same_offer_gives_the_same_map() -> void:
	var offer: Dictionary = Gen.offer("fog", 1, 777, 3)
	assert_str(String(offer["kind"])).is_equal(ExpGen.KIND_CONQUEST)
	assert_str(String(offer["domain"])).is_equal(BookScript.mission_domain("fog", 1))
	var a: Array = Gen.mission_map(offer)
	var b: Array = ExpGen.sortie_map(offer)
	assert_int(a.size()).is_greater(0)
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))

func test_missions_never_come_below_the_minimum_era() -> void:
	var offer: Dictionary = Gen.offer("gulls", 0, 777, 1)
	assert_int(int(offer["era"])).is_greater_equal(GameConfig.empire_min_era)

func test_missions_are_pure_domain() -> void:
	for id in BookScript.island_ids():
		for m in range(BookScript.total(id)):
			var offer: Dictionary = Gen.offer(id, m, 777, 3)
			var domain: String = String(offer["domain"])
			for node in Gen.mission_map(offer):
				assert_str(String(node.get("conquest_island", ""))).is_equal(id)
				for unit_id in node.get("enemy_roster", {}):
					var u: String = String(unit_id)
					match domain:
						"sea":
							assert_bool(SEA_UNITS.has(u)).override_failure_message("%s m%d: %s" % [id, m, u]).is_true()
						"air":
							assert_bool(AIR_UNITS.has(u)).override_failure_message("%s m%d: %s" % [id, m, u]).is_true()
						_:
							assert_bool(SEA_UNITS.has(u) or AIR_UNITS.has(u)).is_false()
				if domain == "sea":
					assert_str(String(node.get("terrain_kind", ""))).is_equal(ExpGen.TERRAIN_KIND_SEA)

func test_only_the_last_fight_pays() -> void:
	var offer: Dictionary = Gen.offer("iron", 0, 777, 3)
	var map: Array = Gen.mission_map(offer)
	var paying := 0
	for node in map:
		if not (node.get("rewards", {}) as Dictionary).is_empty():
			paying += 1
			assert_bool(bool(node.get("conquest_final", false))).is_true()
	assert_int(paying).is_equal(1)

func test_the_citadel_boss_is_on_its_last_fight() -> void:
	var last: int = BookScript.total("ash") - 1
	assert_bool(Gen.is_boss_mission("ash", last)).is_true()
	var map: Array = Gen.mission_map(Gen.offer("ash", last, 777, 3))
	var bosses := 0
	for node in map:
		if bool(node.get("conquest_boss", false)):
			bosses += 1
	assert_int(bosses).is_equal(1)

func test_offer_name_key_is_the_mission_name() -> void:
	var offer: Dictionary = Gen.offer("wind", 2, 777, 3)
	assert_str(ExpGen.offer_name_key(offer)).is_equal(Gen.mission_name_key("wind", 2))

# ── La oferta en Expedition ──────────────────────────────────────────

func test_an_expedition_knows_it_is_a_conquest_and_rebuilds_on_load() -> void:
	var offer: Dictionary = Gen.offer("ember", 1, 777, 3)
	var run: Expedition = ExpeditionScript.create_sortie(3, offer, {"infantry": 3}, 70.0)
	assert_bool(run.is_conquest()).is_true()
	assert_bool(run.is_campaign()).is_false()
	assert_str(run.conquest_island()).is_equal("ember")
	assert_int(run.conquest_mission()).is_equal(1)
	assert_float(run.heal_between_pct()).is_equal(GameConfig.empire_heal_between)
	var back: Expedition = ExpeditionScript.from_dict(run.to_dict(), 3)
	assert_str(JSON.stringify(back.map)).is_equal(JSON.stringify(run.map))
	assert_str(back.conquest_island()).is_equal("ember")
