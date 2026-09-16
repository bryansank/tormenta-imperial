extends SceneTree
## Sonda de balance de la Auditoria Final. Juega asedios enteros en memoria
## —FinalAudit + Encounter + AutoResolver, la misma IA a los dos lados— sobre
## cientos de semillas y saca tasas de victoria por configuracion de guarnicion.
##
## No abre tablero, no toca CombatManager y no emite una sola senal: replica
## exactamente lo que hace `CombatManager._on_final_audit_wave_ready()`
## (guarnicion viva + dotaciones de las torres en pie, sin relevos, con la
## atricion arrastrandose de una oleada a la siguiente).
##
## Uso:
##   godot --headless --path . -s tools/siege_probe.gd -- --seeds=200
##   godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --spw=0.12 --last=1.25
##
## Argumentos (todos opcionales):
##   --seeds=N        semillas por configuracion (100 por defecto)
##   --era=N          era de la guarnicion (3)
##   --morale=F       moral congelada (100)
##   --towers=N       torres en pie (2)
##   --spw --spe --last --base --per --gun --armour --chance --waves=min,max
##                    pisan los `final_audit_*` correspondientes
##   --only=etiqueta  una sola configuracion de guarnicion
##   --detail=1       desglose por longitud de asedio (3, 4 y 5 oleadas)
##
## Nota: siendo el script de arranque (`-s`) no puede nombrar los autoloads en
## tiempo de compilacion —todavia no existen—, asi que GameConfig se resuelve a
## mano desde `root`. Los scripts precargados si los ven con normalidad.
##
## Hermana de tools/battle_probe.gd y tools/storm_probe.gd.

## Nada de `preload` aqui: el script de arranque se compila antes de que existan
## los autoloads, y cualquier script del combate que nombre GameConfig se caeria
## con el. Cargados a mano en _initialize() ya los ven.
var FinalAuditScript: GDScript = null
var EncounterScript: GDScript = null
var AutoResolverScript: GDScript = null
var CombatUnitScript: GDScript = null
var Rules: GDScript = null
## La sonda de combate, instanciada suelta (nunca entra en el arbol, asi que su
## `_ready` no corre). De ella se reutiliza la conversion de rondas a minutos
## —formula y constantes— para no tener dos cuentas del reloj que puedan
## discrepar. Ver docs/16-balance-combate.md, seccion 3.
var _clock: Object = null

## Guarniciones de referencia, de la minima que permite reconvocar a la maxima
## que el juego llega a permitir (el tope de despliegue en la unidad de mas
## poder). Ninguna pasa de `combat_deploy_cap`.
const CONFIGS := [
	{"label": "min 3 infanteria", "roster": {"infantry": 3}},
	{"label": "min 3 vehiculos", "roster": {"vehicle": 3}},
	{"label": "4 vehiculos", "roster": {"vehicle": 4}},
	{"label": "5 vehiculos", "roster": {"vehicle": 5}},
	{"label": "6 infanteria", "roster": {"infantry": 6}},
	{"label": "mixta 3+2+1", "roster": {"infantry": 3, "artillery": 2, "vehicle": 1}},
	{"label": "mixta 2+2+2", "roster": {"infantry": 2, "artillery": 2, "vehicle": 2}},
	{"label": "MAX 6 vehiculos", "roster": {"vehicle": 6}},
]

var _cfg: Node = null
var _seeds := 100
var _era := 3
var _morale := 100.0
var _towers := 2
var _only := ""
var _detail := false
var _pending: Dictionary = {}

func _initialize() -> void:
	_cfg = root.get_node("GameConfig")
	FinalAuditScript = load("res://scripts/combat/FinalAudit.gd")
	EncounterScript = load("res://scripts/combat/Encounter.gd")
	AutoResolverScript = load("res://scripts/combat/AutoResolver.gd")
	CombatUnitScript = load("res://scripts/combat/CombatUnit.gd")
	Rules = load("res://scripts/combat/CombatRules.gd")
	_clock = load("res://tools/balance_probe.gd").new()
	_parse_args()
	_apply_overrides()
	print("=== sonda de asedio ===")
	print("semillas=%d era=%d moral=%.0f torres=%d" % [_seeds, _era, _morale, _towers])
	print("oleadas=%s cuerpos=%d+%d/oleada | escala: oleada=%.3f era=%.3f final=%.3f | canon=1/%d blindado>=%d" % [
		str(_cfg.final_audit_waves),
		_cfg.final_audit_base_slots,
		_cfg.final_audit_slots_per_wave,
		_cfg.final_audit_scale_per_wave,
		_cfg.final_audit_scale_per_era,
		_cfg.final_audit_last_wave_multiplier,
		_cfg.final_audit_artillery_share,
		_cfg.final_audit_armour_wave])
	print("")
	print("%-18s %7s  %11s %7s %11s %8s %8s" % [
		"guarnicion", "gana%", "oleadas", "vivos", "vivos|gana", "rondas", "minutos"])
	for config in CONFIGS:
		if _only != "" and String(config["label"]) != _only:
			continue
		_run_config(config)
	_clock.free()
	quit()

func _run_config(config: Dictionary) -> void:
	var roster: Dictionary = config["roster"]
	var wins := 0
	var cleared_total := 0
	var waves_total := 0
	var survivors_total := 0
	var survivors_on_win := 0
	var rounds_total := 0
	var minutes_total := 0.0
	var by_length: Dictionary = {}
	for s in range(_seeds):
		var outcome: Dictionary = _play(s + 1, roster)
		rounds_total += int(outcome["rounds"])
		minutes_total += float(outcome["minutes"])
		var length: int = int(outcome["waves"])
		if not by_length.has(length):
			by_length[length] = [0, 0]
		by_length[length][1] += 1
		if bool(outcome["won"]):
			wins += 1
			survivors_on_win += int(outcome["survivors"])
			by_length[length][0] += 1
		cleared_total += int(outcome["cleared"])
		waves_total += length
		survivors_total += int(outcome["survivors"])
	var mean_win_survivors := 0.0
	if wins > 0:
		mean_win_survivors = float(survivors_on_win) / float(wins)
	print("%-18s %6.1f%%  %5.2f/%.2f %7.2f %11.2f %8.1f %8.1f" % [
		String(config["label"]),
		100.0 * float(wins) / float(_seeds),
		float(cleared_total) / float(_seeds),
		float(waves_total) / float(_seeds),
		float(survivors_total) / float(_seeds),
		mean_win_survivors,
		float(rounds_total) / float(_seeds),
		minutes_total / float(_seeds)])
	if _detail:
		var lengths: Array = by_length.keys()
		lengths.sort()
		for length in lengths:
			var pair: Array = by_length[length]
			print("    %d oleadas: %5.1f%% (%d de %d)" % [
				length, 100.0 * float(pair[0]) / float(pair[1]), pair[0], pair[1]])

## Un asedio entero, oleada tras oleada, con el mismo cableado que
## CombatManager._on_final_audit_wave_ready().
func _play(seed_value: int, roster: Dictionary) -> Dictionary:
	var audit = FinalAuditScript.create(seed_value, roster, _era, _morale)
	audit.begin()
	var crew_losses := 0
	var crews: Array = []
	var attack_mod: float = Rules.morale_attack_mod(_morale)
	var initiative_bonus: int = Rules.morale_initiative_bonus(_morale)
	var rounds := 0
	var minutes := 0.0
	var guard := 0
	while audit.is_active() and guard < 16:
		guard += 1
		var defenders: Array = audit.living_garrison().duplicate()
		# Las torres vuelven a mandar gente cada oleada, pero las dotaciones que
		# ya cayeron no se reponen: la atricion tambien les toca a ellas.
		if audit.current_wave > 0:
			for crew in crews:
				if not crew.is_alive():
					crew_losses += 1
		var wanted: int = _cfg.get_tower_garrison(_towers, defenders.size()) - crew_losses
		crews = []
		var crew_uids: Array = []
		for i in range(maxi(0, wanted)):
			var crew = CombatUnitScript.create(
				audit.next_uid(), _cfg.storm_tower_garrison_unit, FinalAuditScript.PLAYER, 1.0)
			crew.morale_attack_mod = attack_mod
			crew.morale_initiative_bonus = initiative_bonus
			crews.append(crew)
			crew_uids.append(crew.uid)
		if defenders.is_empty() and crews.is_empty():
			audit.lose()
			break

		var units: Array = defenders.duplicate()
		units.append_array(crews)
		units.append_array(audit.build_enemy_units())
		var encounter = EncounterScript.create(units, 0, false, true, crew_uids)
		var outcome: Dictionary = AutoResolverScript.resolve(encounter)
		rounds += int(outcome["rounds"])
		minutes += float(_clock._minutes(_clock._timing_of(outcome["events"], units), 5.0))
		if bool(outcome["victory"]):
			audit.clear_wave()
		else:
			audit.lose()

	return {
		"won": audit.is_won(),
		"cleared": audit.waves_cleared(),
		"waves": audit.wave_count(),
		"survivors": audit.living_garrison().size(),
		"rounds": rounds,
		"minutes": minutes,
	}

# ── Argumentos ───────────────────────────────────────────────────────

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = String(arg).lstrip("-").split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"seeds": _seeds = maxi(1, int(parts[1]))
			"era": _era = maxi(1, int(parts[1]))
			"morale": _morale = float(parts[1])
			"towers": _towers = maxi(0, int(parts[1]))
			"only": _only = parts[1]
			"detail": _detail = parts[1] != "0"
			_: _pending[parts[0]] = parts[1]

func _apply_overrides() -> void:
	for key in _pending:
		var value: String = String(_pending[key])
		match key:
			"spw": _cfg.final_audit_scale_per_wave = float(value)
			"spe": _cfg.final_audit_scale_per_era = float(value)
			"last": _cfg.final_audit_last_wave_multiplier = float(value)
			"base": _cfg.final_audit_base_slots = int(value)
			"per": _cfg.final_audit_slots_per_wave = int(value)
			"gun": _cfg.final_audit_artillery_share = int(value)
			"armour": _cfg.final_audit_armour_wave = int(value)
			"chance": _cfg.final_audit_extra_gun_chance = float(value)
			"waves":
				var pair: PackedStringArray = value.split(",")
				if pair.size() == 2:
					_cfg.final_audit_waves = Vector2i(int(pair[0]), int(pair[1]))
			_: push_warning("[sonda] argumento desconocido: %s" % key)
