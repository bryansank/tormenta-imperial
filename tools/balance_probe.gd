extends Node
## Dev tool: mide el balance del combate en vez de adivinarlo (T046).
##
## `AutoResolver` resuelve un `Encounter` entero con la misma IA a los dos lados,
## en memoria y al instante. Esta sonda lo usa para barrer el espacio de
## dificultad y contar lo unico que importa: cuanto se gana, cuanto dura y cuanto
## cuesta. Ningun numero de `docs/16-balance-combate.md` sale de jugar a ojo.
##
## Uso: registrar temporalmente como autoload y arrancar el juego headless.
##   project.godot -> [autoload] -> BalanceProbe="*res://tools/balance_probe.gd"
##   godot --headless --path .
## Quitar la linea al terminar (la sonda cierra el juego sola).
##
## Hermana de tools/storm_probe.gd y tools/battle_probe.gd.
##
## AVISO sobre el modelo: `Encounter`, `CombatRules` y `CombatAI` no tiran dados.
## Con la misma plantilla y el mismo roster, el encuentro sale identico siempre.
## La unica variedad de un barrido de encuentros viene de lo que sortea
## `ExpeditionGenerator` (composicion del roster) y de la plantilla que elige la
## sonda. En era 1, donde solo hay infanteria, el resultado es una funcion
## escalon: 0% o 100%, sin dispersion. Eso no es un fallo de la sonda; es como
## esta hecho el combate, y conviene tenerlo delante al leer las tablas.

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

# ── Parametros del barrido ───────────────────────────────────────────

## Semillas por celda del barrido de encuentros.
const SEEDS := 200
## Semillas por tamano de plantilla en el barrido de expediciones completas.
const EXPEDITION_SEEDS := 200
const SEED_BASE := 1_000_003

const ERAS := [1, 2, 3]
const DEPTHS := [0, 1, 2, 3, 4, 5, 6]
const RISKS := [0, 1, 2]
const PARTY_SIZES := [3, 4, 6]

## Moral de la base cuando la columna sale. Es el valor de arranque del juego
## (`GameConfig.morale_start`), o sea el caso normal, no el mejor ni el peor.
const MORALE := 75.0

# ── Rondas a minutos ─────────────────────────────────────────────────
#
# Formula:
#   segundos = pasos_enemigos * combat_ai_step_delay
#            + turnos_jugador  * PLAYER_SECONDS_PER_TURN
#            + (turnos_jugador + turnos_enemigos) * TURN_OVERHEAD_SECONDS
#
# Los pasos enemigos se cuentan de verdad (cada `unit_moved` / `unit_attacked` /
# `unit_defended` de una unidad enemiga), porque `CombatManager._run_enemy_turn()`
# espera `combat_ai_step_delay` ANTES de cada paso del plan. Lo que se supone, y
# se supone a proposito, es el lado del jugador: no hay reloj en el codigo que
# mida cuanto tarda una persona en mirar el tablero, tocar una unidad, tocar la
# casilla y tocar el objetivo.
#
# PLAYER_SECONDS_PER_TURN = 5 s por unidad y turno es la cifra de un jugador que
# ya conoce el tablero en un movil: ~1 s de lectura, tres toques con su
# animacion. Un novato tarda mas y un veterano menos; multiplicar o dividir por
# dos esa constante mueve el resultado, asi que la tabla publica tambien el
# numero de turnos de jugador para que cualquiera rehaga la cuenta con la suya.
const PLAYER_SECONDS_PER_TURN := 5.0
## Sensibilidad: la misma cuenta con un jugador rapido y con uno lento. Si la
## conclusion cambia de signo entre estas dos columnas, la conclusion no es del
## balance, es de la constante.
const PLAYER_SECONDS_FAST := 3.0
const PLAYER_SECONDS_SLOW := 8.0
## Camara y animacion entre turno y turno, los dos bandos.
const TURN_OVERHEAD_SECONDS := 0.3

## Ventana de diseno de la tarea, en minutos.
const TARGET_MINUTES := Vector2(3.0, 5.0)

func _ready() -> void:
	# Los autoloads tambien arrancan cuando Godot corre un script con `-s`, y la
	# suite de gdUnit es exactamente eso. Una sonda que cierra el juego al acabar
	# se llevaria por delante la ejecucion de los tests, asi que aqui se aparta.
	if _running_a_tool_script():
		return
	# Un frame para que los autoloads terminen de arrancar antes de leer config.
	await get_tree().process_frame
	_run()
	get_tree().quit()

func _running_a_tool_script() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "-s" or arg == "--script":
			return true
	return false

func _run() -> void:
	print("")
	print("==============================================================")
	print(" SONDA DE BALANCE DE COMBATE — %d semillas/celda" % SEEDS)
	print("==============================================================")
	_print_config()
	_sweep_encounters()
	_sweep_expeditions()
	print("")

func _print_config() -> void:
	print("")
	print("-- Valores combat_* leidos --")
	print("  turn_limit=%d  enemy_base_slots=%d  deploy_cap=%d  board=%s" % [
		GameConfig.combat_turn_limit, GameConfig.combat_enemy_base_slots,
		GameConfig.combat_deploy_cap, str(GameConfig.combat_board_size),
	])
	print("  scale_per_depth=%.2f  scale_per_era=%.2f  risk_enemy_scale=%.2f  boss_mult=%.2f" % [
		GameConfig.combat_enemy_scale_per_depth, GameConfig.combat_enemy_scale_per_era,
		GameConfig.combat_risk_enemy_scale, GameConfig.combat_boss_multiplier,
	])
	print("  ai_step_delay=%.2f  map_depth=%s  draft_options=%d" % [
		GameConfig.combat_ai_step_delay, str(GameConfig.combat_map_depth),
		GameConfig.combat_draft_options,
	])
	for unit_id in ["infantry", "artillery", "vehicle"]:
		print("  %-10s %s" % [unit_id, str(GameConfig.combat_unit_stats.get(unit_id, {}))])

# ── Barrido de encuentros sueltos ────────────────────────────────────

func _sweep_encounters() -> void:
	print("")
	print("-- BARRIDO DE ENCUENTROS (era x profundidad x riesgo x plantilla) --")
	print("era  prof  riesgo  party  n    victoria  rondas(sd)   tope%%  bajas  turnJ  min   (3s/8s)     enem")
	var by_era_party: Dictionary = {}
	for era in ERAS:
		for depth in DEPTHS:
			for risk in RISKS:
				for size in PARTY_SIZES:
					var cell: Dictionary = _measure_cell(era, depth, risk, size)
					print("%-4d %-5d %-7s %-6d %-4d %-9s %-12s %-6s %-6.2f %-6.1f %-5.1f %-11s %s" % [
						era, depth, _risk_name(risk), size, cell["n"],
						"%.0f%%" % (100.0 * cell["win_rate"]),
						"%.1f (%.1f)" % [cell["rounds_mean"], cell["rounds_sd"]],
						"%.0f%%" % (100.0 * cell["timeout_rate"]),
						cell["casualties_mean"], cell["player_turns"], cell["minutes_mean"],
						"(%.1f/%.1f)" % [cell["minutes_fast"], cell["minutes_slow"]],
						cell["roster"],
					])
					var key: String = "e%d/p%d" % [era, size]
					if not by_era_party.has(key):
						by_era_party[key] = []
					by_era_party[key].append(cell)

	print("")
	print("-- RESUMEN POR ERA Y PLANTILLA (media sobre profundidades y riesgos) --")
	print("celda      victoria  rondas  tope%%  bajas  minutos  (3s/8s)")
	for key in by_era_party.keys():
		var cells: Array = by_era_party[key]
		print("%-10s %-9s %-7.1f %-6s %-6.2f %-8.1f (%.1f/%.1f)" % [
			key,
			"%.0f%%" % (100.0 * _avg(cells, "win_rate")),
			_avg(cells, "rounds_mean"),
			"%.0f%%" % (100.0 * _avg(cells, "timeout_rate")),
			_avg(cells, "casualties_mean"),
			_avg(cells, "minutes_mean"),
			_avg(cells, "minutes_fast"), _avg(cells, "minutes_slow"),
		])

	print("")
	print("-- DURACION frente al objetivo %.0f-%.0f min --" % [TARGET_MINUTES.x, TARGET_MINUTES.y])
	var total: int = 0
	var inside: int = 0
	var below: int = 0
	var above: int = 0
	for key in by_era_party.keys():
		for cell in by_era_party[key]:
			total += 1
			var m: float = cell["minutes_mean"]
			if m < TARGET_MINUTES.x:
				below += 1
			elif m > TARGET_MINUTES.y:
				above += 1
			else:
				inside += 1
	print("  celdas=%d  dentro=%d (%.0f%%)  cortas=%d  largas=%d" % [
		total, inside, 100.0 * float(inside) / float(maxi(1, total)), below, above,
	])

## Memoria del barrido de encuentros. El modelo no tira dados: con la misma
## plantilla, el mismo roster y la misma escala el encuentro sale identico, asi
## que simularlo 200 veces es tirar 200 veces la misma cuenta. La sonda sigue
## sacando sus `SEEDS` muestras — la media, la dispersion y los porcentajes se
## calculan sobre las 200 —, pero solo juega las combinaciones distintas. En era
## 1, donde solo hay infanteria, eso es UNA partida en lugar de doscientas.
var _plays: Dictionary = {}

## Juega (o recuerda) un encuentro entre esa plantilla y ese roster.
func _play(counts: Dictionary, roster: Dictionary, scale: float, index: int) -> Dictionary:
	var key: String = "%s#%s#%.4f#%d" % [
		_counts_label(counts), _roster_label(roster), scale, index,
	]
	if _plays.has(key):
		return _plays[key]

	var units: Array = _make_party(counts)
	units.append_array(_make_enemies(roster, scale))
	var encounter: Encounter = Encounter.create(units, index, false)
	var result: Dictionary = AutoResolver.resolve(encounter)
	var outcome: Dictionary = {
		"victory": bool(result["victory"]),
		"timeout": encounter.state == Encounter.State.TIMEOUT,
		"rounds": int(result["rounds"]),
		"casualties": encounter.casualties(Encounter.PLAYER).size(),
		"timing": _timing_of(result["events"], units),
	}
	_plays[key] = outcome
	return outcome

## Una celda del barrido: misma era, profundidad, riesgo y tamano de plantilla,
## `SEEDS` semillas.
func _measure_cell(era: int, depth: int, risk: int, size: int) -> Dictionary:
	var wins: int = 0
	var timeouts: int = 0
	var rounds_sum: float = 0.0
	var rounds_sq: float = 0.0
	var casualties_sum: float = 0.0
	var timing_sum: Dictionary = {}
	var roster_seen: Dictionary = {}

	for s in range(SEEDS):
		var rng: RandomNumberGenerator = Generator.make_rng(SEED_BASE + s)
		var counts: Dictionary = _party_counts(rng, era, size)
		var roster: Dictionary = Generator.enemy_roster(rng, depth, era, risk)
		var scale: float = Generator.enemy_scale(depth, era, risk, false)
		roster_seen[_roster_label(roster)] = true

		var outcome: Dictionary = _play(counts, roster, scale, depth)
		if bool(outcome["victory"]):
			wins += 1
		if bool(outcome["timeout"]):
			timeouts += 1
		var rounds: float = float(outcome["rounds"])
		rounds_sum += rounds
		rounds_sq += rounds * rounds
		casualties_sum += float(outcome["casualties"])
		_add_timing(timing_sum, outcome["timing"])

	var n: float = float(SEEDS)
	var mean: float = rounds_sum / n
	var variance: float = maxf(0.0, rounds_sq / n - mean * mean)
	var labels: Array = roster_seen.keys()
	labels.sort()
	var avg_timing: Dictionary = {}
	for key in timing_sum:
		avg_timing[key] = float(timing_sum[key]) / n
	return {
		"era": era, "depth": depth, "risk": risk, "size": size, "n": SEEDS,
		"win_rate": float(wins) / n,
		"timeout_rate": float(timeouts) / n,
		"rounds_mean": mean,
		"rounds_sd": sqrt(variance),
		"casualties_mean": casualties_sum / n,
		"player_turns": float(avg_timing.get("player_turns", 0.0)),
		"minutes_mean": _minutes(avg_timing, PLAYER_SECONDS_PER_TURN),
		"minutes_fast": _minutes(avg_timing, PLAYER_SECONDS_FAST),
		"minutes_slow": _minutes(avg_timing, PLAYER_SECONDS_SLOW),
		"roster": "|".join(labels),
	}

# ── Barrido de expediciones completas ────────────────────────────────

func _sweep_expeditions() -> void:
	print("")
	print("-- EXPEDICIONES COMPLETAS (mapa entero hasta el jefe, atricion real) --")
	print("era  party  modo   n    ganadas  nodos  prof.muerte  bajas  min/exped")
	var rows: Dictionary = {}
	for era in ERAS:
		for size in PARTY_SIZES:
			for played in [false, true]:
				var row: Dictionary = _measure_expeditions(era, size, played)
				rows["e%d/p%d/%s" % [era, size, "jug" if played else "azar"]] = row
				print("%-4d %-6d %-6s %-4d %-8s %-6.2f %-12s %-6.2f %.1f" % [
					era, size, "jugado" if played else "azar", row["n"],
					"%.0f%%" % (100.0 * row["win_rate"]),
					row["nodes_mean"],
					("%.2f" % row["death_depth_mean"]) if row["deaths"] > 0 else "-",
					row["casualties_mean"], row["minutes_mean"],
				])

	print("")
	print("-- DESGASTE: %% del deposito de vida que le queda a la columna al salir de cada nodo --")
	print("(era 1; el deposito es la suma de HP de toda la plantilla inicial, viva o muerta)")
	for size in PARTY_SIZES:
		for mode in ["azar", "jug"]:
			var row: Dictionary = rows["e1/p%d/%s" % [size, mode]]
			var pool: Array = row["pool_by_depth"]
			var parts: Array = []
			for d in range(pool.size()):
				var entry: Dictionary = pool[d]
				if int(entry["n"]) == 0:
					continue
				parts.append("d%d:%.0f%%" % [d, 100.0 * float(entry["sum"]) / float(entry["n"])])
			print("  party=%d %-5s %s" % [size, mode, " ".join(parts)])

	print("")
	print("-- DONDE MUERE LA COLUMNA (era 1, histograma por profundidad) --")
	for size in PARTY_SIZES:
		for mode in ["azar", "jug"]:
			var row: Dictionary = rows["e1/p%d/%s" % [size, mode]]
			var hist: Dictionary = row["death_hist"]
			var keys: Array = hist.keys()
			keys.sort()
			var parts: Array = []
			for k in keys:
				parts.append("d%d:%d" % [int(k), int(hist[k])])
			print("  party=%d %-5s derrotas=%d/%d  %s" % [
				size, mode, row["deaths"], row["n"], " ".join(parts),
			])

## `played` = false reproduce el enunciado de la tarea (draft al azar, ruta al
## azar): es la cota inferior, un jugador que no mira. `played` = true modela a
## uno que si: cura cuando alguien esta tocado, si no sube ataque o defensa, y
## elige siempre la salida de menos riesgo. "Ganable" se mide con esta segunda.
func _measure_expeditions(era: int, size: int, played: bool = false) -> Dictionary:
	var wins: int = 0
	var deaths: int = 0
	var nodes_sum: float = 0.0
	var casualties_sum: float = 0.0
	var minutes_sum: float = 0.0
	var death_depth_sum: float = 0.0
	var death_hist: Dictionary = {}
	var pool_by_depth: Array = []
	for d in range(16):
		pool_by_depth.append({"sum": 0.0, "n": 0})

	for s in range(EXPEDITION_SEEDS):
		var rng: RandomNumberGenerator = Generator.make_rng(SEED_BASE + 31 * s + 7)
		var counts: Dictionary = _party_counts(rng, era, size)
		var run: Expedition = Expedition.create(s, SEED_BASE + s, counts, MORALE, era)
		var minutes: float = 0.0

		while run.is_active():
			var units: Array = run.build_encounter_units()
			var encounter: Encounter = Encounter.create(units, run.current_node, run.at_boss())
			var result: Dictionary = AutoResolver.resolve(encounter)
			minutes += _minutes(_timing_of(result["events"], units), PLAYER_SECONDS_PER_TURN)
			encounter.release_survivors()
			if not bool(result["victory"]):
				var depth: int = int(run.current_node_data().get("depth", 0))
				death_depth_sum += float(depth)
				death_hist[depth] = int(death_hist.get(depth, 0)) + 1
				deaths += 1
				run.mark_defeated()
				break
			var depth_now: int = clampi(int(run.current_node_data().get("depth", 0)), 0, pool_by_depth.size() - 1)
			var entry: Dictionary = pool_by_depth[depth_now]
			entry["sum"] = float(entry["sum"]) + _pool_fraction(run)
			entry["n"] = int(entry["n"]) + 1
			run.mark_cleared()
			if not run.is_active():
				break
			var options: Array = run.draft_options()
			if not options.is_empty():
				var pick: int = _choose_draft(options, run.living_party()) if played \
					else rng.randi_range(0, options.size() - 1)
				run.apply_draft(options[pick])
			var exits: Array = run.current_exits()
			if exits.is_empty():
				break
			var next_node: int = _choose_exit(run, exits) if played \
				else int(exits[rng.randi_range(0, exits.size() - 1)])
			run.select_node(next_node)

		if run.boss_defeated():
			wins += 1
		nodes_sum += float(run.nodes_cleared())
		casualties_sum += float(run.casualties().size())
		minutes_sum += minutes

	var n: float = float(EXPEDITION_SEEDS)
	return {
		"n": EXPEDITION_SEEDS,
		"win_rate": float(wins) / n,
		"nodes_mean": nodes_sum / n,
		"casualties_mean": casualties_sum / n,
		"minutes_mean": minutes_sum / n,
		"deaths": deaths,
		"death_depth_mean": death_depth_sum / float(maxi(1, deaths)),
		"death_hist": death_hist,
		"pool_by_depth": pool_by_depth,
	}

## Vida que le queda a la columna sobre el total con el que salio: los muertos
## cuentan como cero, asi que este numero mezcla las dos formas de desgaste.
func _pool_fraction(run: Expedition) -> float:
	var total: float = 0.0
	var left: float = 0.0
	for unit in run.party:
		total += float(unit.max_hp)
		left += float(maxi(0, unit.hp))
	return left / maxf(1.0, total)

## El criterio del jugador competente ante las cartas: primero curar si la
## columna llega tocada (es la unica sanacion que hay en toda la run), luego
## ataque, luego defensa. Lo demas es relleno.
func _choose_draft(options: Array, living: Array) -> int:
	var current: float = 0.0
	var full: float = 0.0
	for unit in living:
		current += float(unit.hp)
		full += float(unit.max_hp)
	# La curacion se reparte entre los vivos y se pierde lo que desborde, asi que
	# el momento de cogerla es cuando la columna ya ha encajado algo, no cuando
	# esta a punto de caer: para entonces ya hay muertos, y a esos no los levanta.
	var hurt: bool = current < 0.85 * maxf(1.0, full)
	# Defensa antes que ataque: el dano es `atk - def`, asi que cada punto de
	# defensa vale lo mismo que uno de ataque en la cuenta, pero se aplica a
	# todos los golpes que recibe la unidad en vez de a los que da.
	var order: Array = ["draft_hp_heal", "draft_def", "draft_atk", "draft_init", "draft_move"] \
		if hurt else ["draft_def", "draft_atk", "draft_hp_heal", "draft_init", "draft_move"]
	for wanted in order:
		for i in range(options.size()):
			if String(options[i].get("id", "")) == wanted:
				return i
	return 0

## Y ante el mapa: la salida de menos riesgo. El riesgo paga mas, pero una
## columna sin repuestos no esta para apostar.
func _choose_exit(run: Expedition, exits: Array) -> int:
	var best: int = int(exits[0])
	var best_risk: int = 99
	for index in exits:
		var risk: int = int(run.node_at(int(index)).get("risk", 0))
		if risk < best_risk:
			best_risk = risk
			best = int(index)
	return best

# ── Plantillas y rosters ─────────────────────────────────────────────

## Composicion de la plantilla del jugador para esa era. Reparto uniforme entre
## lo que la era permite, con al menos una infanteria: una columna sin linea no
## es una plantilla que nadie llevaria.
func _party_counts(rng: RandomNumberGenerator, era: int, size: int) -> Dictionary:
	var available: Array = []
	for unit_id in GameConfig.get_unit_ids():
		if era >= int(GameConfig.get_unit_def(unit_id).get("era", 1)):
			available.append(String(unit_id))
	available.sort()
	var counts: Dictionary = {"infantry": 1}
	for i in range(size - 1):
		var pick: String = String(available[rng.randi_range(0, available.size() - 1)])
		counts[pick] = int(counts.get(pick, 0)) + 1
	return counts

func _make_party(counts: Dictionary) -> Array:
	var attack_mod: float = Rules.morale_attack_mod(MORALE)
	var initiative_bonus: int = Rules.morale_initiative_bonus(MORALE)
	var party: Array = []
	var uid: int = 1
	for unit_id in counts.keys():
		for i in range(int(counts[unit_id])):
			var unit: CombatUnit = CombatUnit.create(uid, String(unit_id), Encounter.PLAYER, 1.0)
			unit.morale_attack_mod = attack_mod
			unit.morale_initiative_bonus = initiative_bonus
			party.append(unit)
			uid += 1
	return party

func _make_enemies(roster: Dictionary, scale: float) -> Array:
	var units: Array = []
	var uid: int = 1000
	for unit_id in roster.keys():
		for i in range(int(roster[unit_id])):
			units.append(CombatUnit.create(uid, String(unit_id), Encounter.ENEMY, scale))
			uid += 1
	return units

func _counts_label(counts: Dictionary) -> String:
	return _roster_label(counts)

func _roster_label(roster: Dictionary) -> String:
	var keys: Array = roster.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s%d" % [String(k).substr(0, 3), int(roster[k])])
	return "".join(parts)

# ── Rondas a minutos ─────────────────────────────────────────────────

## Cuenta lo unico que el modelo sabe del reloj: pasos de la IA enemiga (cada uno
## cuesta `combat_ai_step_delay`) y turnos de cada bando.
func _timing_of(events: Array, units: Array) -> Dictionary:
	var side_of: Dictionary = {}
	for unit in units:
		side_of[unit.uid] = unit.side

	var enemy_steps: int = 0
	var player_turns: int = 0
	var enemy_turns: int = 0
	for event in events:
		match String(event.get("e", "")):
			"turn_started":
				if int(event.get("side", 0)) == Encounter.PLAYER:
					player_turns += 1
				else:
					enemy_turns += 1
			"unit_moved", "unit_defended":
				if int(side_of.get(int(event.get("uid", -1)), 0)) == Encounter.ENEMY:
					enemy_steps += 1
			"unit_attacked":
				if int(side_of.get(int(event.get("attacker", -1)), 0)) == Encounter.ENEMY:
					enemy_steps += 1

	return {"enemy_steps": enemy_steps, "player_turns": player_turns, "enemy_turns": enemy_turns}

## Traduce el recuento a minutos de reloj. Ver el bloque de constantes para la
## formula y lo que supone del jugador.
func _minutes(timing: Dictionary, seconds_per_player_turn: float) -> float:
	var seconds: float = float(timing["enemy_steps"]) * GameConfig.combat_ai_step_delay \
		+ float(timing["player_turns"]) * seconds_per_player_turn \
		+ float(int(timing["player_turns"]) + int(timing["enemy_turns"])) * TURN_OVERHEAD_SECONDS
	return seconds / 60.0

func _add_timing(into: Dictionary, timing: Dictionary) -> void:
	for key in timing:
		into[key] = int(into.get(key, 0)) + int(timing[key])

# ── Utilidades ───────────────────────────────────────────────────────

func _risk_name(risk: int) -> String:
	match risk:
		0: return "bajo"
		1: return "medio"
		_: return "alto"

func _avg(cells: Array, key: String) -> float:
	if cells.is_empty():
		return 0.0
	var total: float = 0.0
	for cell in cells:
		total += float(cell[key])
	return total / float(cells.size())
