extends Node
## Sonda de rendimiento (docs/26-rendimiento.md). La lanza tools/perf_probe.gd,
## que explica el uso y los argumentos.
##
## Un escenario por ejecucion:
##   1. siembra una partida fija por semilla (user://save_game.json, con la
##      partida que hubiera aparcada y devuelta al final);
##   2. la abre en Main (3D) o Main2D, cierra el menu de titulo y las ayudas;
##   3. calienta `warmup` segundos y mide `seconds` segundos: tiempo de
##      fotograma (media, mediana, p99, 1 % bajo), tiempo de proceso y fisica,
##      CPU y GPU del render, draw calls, objetos y primitivas, nodos, objetos,
##      memoria estatica, de video y del proceso;
##   4. perfila `profile` segundos el `_process` / `_physics_process` de cada
##      script (autoloads incluidos) llamandolo a mano con un cronometro;
##   5. escribe reports/perf/<tag>_<escenario>.json y .png y anade una fila a
##      reports/perf/perf_runs.csv.
## Imprime "perf_probe: ..." y una tabla.

const SAVE_PATH := "user://save_game.json"
const SaveParking := preload("res://tests/save/save_parking.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")
const BACKUP_PATH := "user://save_game.perf_probe.bak"
const OUT_DIR := "res://reports/perf"
const CSV_NAME := "perf_runs.csv"

## Celdas entre dos calles de la cuadricula: manzanas de 4x4 por dentro, que
## caben cuatro edificios 2x2 y todos tocan la calle (o un Nucleo 3x3).
const BLOCK := 5

var options: Dictionary = {}

var _saved_view := "3d"
var _saved_quality := "auto"
var _seeded := {}            # lo que se sembro: edificios por tipo, carreteras, era...
var _rng := RandomNumberGenerator.new()

# Perfil por script
var _profiling := false
var _targets: Array = []     # {node, label, kind}
var _cost: Dictionary = {}   # label -> {"us": int, "calls": int, "kind": String}
var _rescan_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	process_physics_priority = -1000
	_run.call_deferred()

# ── Guion ─────────────────────────────────────────────────────────────

func _run() -> void:
	var scenario: String = options.get("scenario", "grande")
	var view: String = options.get("view", "3d")
	var quality: String = options.get("quality", "auto")
	DisplayServer.window_set_size(options.get("size", Vector2i(1280, 720)))
	if not bool(options.get("vsync", false)):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Sin tope tampoco al perder el foco ni en pausa: en una maquina compartida
		# otra ventana roba el foco y DeviceProfile bajaria a fps_background (10),
		# que es lo que salio en el combate de la tanda de tablet del 2026-10-25.
		GameConfig.ui_fps_cap = "unlimited"
		GameConfig.fps_background = 0
		GameConfig.fps_paused = 0
		Engine.max_fps = 0
	await _frames(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Tiempos reales: dev_mode acelera todo x5 y adelanta los eventos.
	GameConfig.dev_mode = false
	SaveParking.park(BACKUP_PATH)
	_saved_view = GameConfig.ui_view_mode
	_saved_quality = GameConfig.ui_graphics_quality
	GameConfig.ui_graphics_quality = "low" if quality == "minima" else quality
	# --device=phone|tablet|pc: el perfil manda en la escala de la interfaz y en el
	# tope de caminantes. apply_all() pone el tope de FPS del perfil: se quita otra vez.
	if String(options.get("device", "")) != "":
		GameConfig.ui_device_profile = String(options["device"])
		DeviceProfile.apply_all()
		if not bool(options.get("vsync", false)):
			Engine.max_fps = 0
	ViewMode.set_preference(view)
	_rng.seed = int(options.get("seed", 1)) * 7919 + 17
	_write_save(scenario)
	get_tree().change_scene_to_file(ViewMode.scene_for(view))
	await _frames(90)
	_dismiss_overlays()
	if scenario == "combate":
		var party := {"infantry": 4, "artillery": 2}
		var ok: bool = CombatManager.start_skirmish(party, int(options.get("seed", 1)))
		print("perf_probe: tablero abierto=%s" % ok)
		await _frames(30)
	if quality == "minima":
		_apply_minima(view)
	elif quality == "minimal":
		# La Minima de verdad del juego (Ajustes): WorldLook ya la leyo al cargar la
		# escena; lo que va fuera de el (humo, rejilla, caminantes) se aplica aqui
		# como lo haria DeviceProfile al cambiarla.
		preload("res://scripts/services/GraphicsQuality.gd").apply_runtime(get_tree())
		var walkers := _walkers()
		if walkers and walkers.has_method("reconcile"):
			walkers.reconcile()
	_set_camera(scenario, view)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _seconds(float(options.get("warmup", 6.0)))
	_dismiss_overlays()
	if quality == "minima":
		_hide_fx()
	# El perfil (o la Minima de PC) puede haber vuelto a poner su tope de FPS.
	# Cambiar el vsync recrea la swapchain (en Vulkan, un fotograma de ~250 ms):
	# solo si alguien lo volvio a encender, y con un segundo de margen.
	if not bool(options.get("vsync", false)):
		Engine.max_fps = 0
		if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			await _seconds(1.0)
	var m := await _measure(float(options.get("seconds", 15.0)), rid)
	var prof: Array = []
	if float(options.get("profile", 4.0)) > 0.0:
		prof = await _profile(float(options.get("profile", 4.0)))
	var shot := ""
	if bool(options.get("shot", true)):
		shot = await _shot(scenario)
	var report := _report(scenario, view, quality, m, prof, shot)
	_write_outputs(report)
	_print_table(report)
	_finish(0)

# ── Medida ────────────────────────────────────────────────────────────

func _measure(seconds: float, rid: RID) -> Dictionary:
	var frame_ms: Array = []
	var sums := {"proc": 0.0, "phys": 0.0, "draw": 0.0, "obj": 0.0, "prim": 0.0, "gpu": 0.0, "cpu_r": 0.0}
	var maxs := {"proc": 0.0, "phys": 0.0, "draw": 0.0, "obj": 0.0, "prim": 0.0, "gpu": 0.0, "cpu_r": 0.0}
	var walkers := _walkers()
	var walk_sum := 0.0
	var start := Time.get_ticks_usec()
	var prev := start
	var end_at := start + int(seconds * 1000000.0)
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - prev) / 1000.0)
		prev = now
		var s := {
			"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"obj": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"prim": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"gpu": RenderingServer.viewport_get_measured_render_time_gpu(rid),
			"cpu_r": RenderingServer.viewport_get_measured_render_time_cpu(rid),
		}
		for k in s:
			sums[k] += float(s[k])
			maxs[k] = maxf(maxs[k], float(s[k]))
		if walkers and walkers.has_method("walker_count"):
			walk_sum += walkers.walker_count()
		if now >= end_at:
			break
	var n := frame_ms.size()
	var elapsed_s := float(prev - start) / 1000000.0
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var worst_n := maxi(1, int(ceil(n * 0.01)))
	var worst_sum := 0.0
	for i in worst_n:
		worst_sum += float(sorted[n - 1 - i])
	var mean := {}
	for k in sums:
		mean[k] = sums[k] / maxf(1.0, float(n))
	# Tirones: fotogramas largos y en que segundo de la medida caen (un pico
	# periodico, como un guardado o un tick, sale con el mismo intervalo).
	var hitches: Array = []
	var over_50 := 0
	var acc := 0.0
	for ms in frame_ms:
		acc += float(ms)
		if float(ms) > 50.0:
			over_50 += 1
		if float(ms) > 100.0 and hitches.size() < 20:
			hitches.append([snappedf(acc / 1000.0, 0.1), snappedf(float(ms), 0.1)])
	return {
		"frames": n,
		"frames_over_50ms": over_50,
		"hitches_over_100ms": hitches,
		"seconds": elapsed_s,
		"fps_mean": float(n) / maxf(0.001, elapsed_s),
		"frame_ms_mean": elapsed_s * 1000.0 / maxf(1.0, float(n)),
		"frame_ms_p50": float(sorted[n / 2]),
		"frame_ms_p99": float(sorted[clampi(int(n * 0.99), 0, n - 1)]),
		"frame_ms_max": float(sorted[n - 1]),
		"fps_1pct_low": 1000.0 / (worst_sum / worst_n),
		# TIME_PROCESS / TIME_PHYSICS_PROCESS son el PICO del ultimo segundo (el
		# motor los publica una vez por segundo), no la media del fotograma.
		"process_peak_ms": mean["proc"], "process_peak_ms_max": maxs["proc"],
		"physics_peak_ms": mean["phys"], "physics_peak_ms_max": maxs["phys"],
		# Lo que queda del fotograma fuera del render en CPU: scripts, senales,
		# temporizadores, tweens, interfaz y la espera a la GPU.
		"cpu_other_ms": elapsed_s * 1000.0 / maxf(1.0, float(n)) - mean["cpu_r"],
		"render_cpu_ms": mean["cpu_r"], "render_gpu_ms": mean["gpu"], "render_gpu_ms_max": maxs["gpu"],
		"draw_calls": mean["draw"], "draw_calls_max": maxs["draw"],
		"objects_in_frame": mean["obj"], "primitives_in_frame": mean["prim"],
		"walkers_on_street": walk_sum / maxf(1.0, float(n)),
		"walker_actors": walkers.actor_count() if walkers and walkers.has_method("actor_count") else 0,
	}

# ── Perfil por script ─────────────────────────────────────────────────
#
# Se apaga el proceso de cada nodo con script que tenga _process o
# _physics_process y la sonda lo llama a mano entre dos marcas de tiempo. Es una
# aproximacion: el orden de proceso cambia y un nodo que se apaga a si mismo
# (set_process(false)) sigue recibiendo llamadas mientras dura el perfil. Por eso
# va DESPUES de la medida limpia y no la toca.

func _profile(seconds: float) -> Array:
	_cost.clear()
	_targets.clear()
	_scan_targets()
	_profiling = true
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var end_at := t0 + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end_at:
		await get_tree().process_frame
		frames += 1
	_profiling = false
	var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	for t in _targets:
		var node: Node = t["node"]
		if is_instance_valid(node):
			if t["kind"] == "process":
				node.set_process(true)
			else:
				node.set_physics_process(true)
	_targets.clear()
	var rows: Array = []
	for label in _cost:
		var c: Dictionary = _cost[label]
		rows.append({
			"script": label, "kind": c["kind"], "nodes": c["nodes"].size(),
			"us_per_frame": float(c["us"]) / maxf(1.0, float(frames)),
			"calls_per_frame": float(c["calls"]) / maxf(1.0, float(frames)),
		})
	rows.sort_custom(func(a, b): return a["us_per_frame"] > b["us_per_frame"])
	print("perf_probe: perfil %d fotogramas (%.2f ms de media durante el perfil)" % [frames, total_ms / maxf(1.0, frames)])
	return rows

func _scan_targets() -> void:
	_rescan_at = Time.get_ticks_msec() + 1000
	var known := {}
	for t in _targets:
		known[str(t["node"].get_instance_id()) + t["kind"]] = true
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node == self or node.get_script() == null:
			continue
		var label := _label_for(node)
		if node.is_processing() and node.has_method("_process") and not known.has(str(node.get_instance_id()) + "process"):
			node.set_process(false)
			_targets.append({"node": node, "label": label, "kind": "process"})
		if node.is_physics_processing() and node.has_method("_physics_process") and not known.has(str(node.get_instance_id()) + "physics"):
			node.set_physics_process(false)
			_targets.append({"node": node, "label": label, "kind": "physics"})

func _label_for(node: Node) -> String:
	var script: Script = node.get_script()
	var file := script.resource_path.get_file() if script else node.get_class()
	if node.get_parent() == get_tree().root and node != get_tree().current_scene:
		return "autoload " + str(node.name)
	return file

func _process(delta: float) -> void:
	if _profiling:
		_run_targets("process", delta)

func _physics_process(delta: float) -> void:
	if _profiling:
		_run_targets("physics", delta)

func _run_targets(kind: String, delta: float) -> void:
	if Time.get_ticks_msec() >= _rescan_at:
		_scan_targets()
	for t in _targets:
		if t["kind"] != kind:
			continue
		var node: Node = t["node"]
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.can_process():
			continue
		# Se ha vuelto a encender solo: el motor ya lo llama, no se duplica.
		if (kind == "process" and node.is_processing()) or (kind == "physics" and node.is_physics_processing()):
			continue
		var t0 := Time.get_ticks_usec()
		if kind == "process":
			node.call("_process", delta)
		else:
			node.call("_physics_process", delta)
		var us := Time.get_ticks_usec() - t0
		var label: String = t["label"] + ("" if kind == "process" else " (fisica)")
		if not _cost.has(label):
			_cost[label] = {"us": 0, "calls": 0, "kind": kind, "nodes": {}}
		_cost[label]["us"] += us
		_cost[label]["calls"] += 1
		_cost[label]["nodes"][node.get_instance_id()] = true

# ── Calidad "Minima" (propuesta de docs/26, emulada aqui) ─────────────

func _apply_minima(view: String) -> void:
	var scene := get_tree().current_scene
	var env_node := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment:
		var env := env_node.environment
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.glow_enabled = false
		env.sdfgi_enabled = false
		env.ssr_enabled = false
	var sun := scene.get_node_or_null("DirectionalLight") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = false
	for l in scene.find_children("*", "Light3D", true, false):
		(l as Light3D).shadow_enabled = false
	if view == "3d":
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 0.6
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	GameConfig.life_figure_cap = {"pc": 16, "tablet": 12, "phone": 8}
	var walkers := _walkers()
	if walkers and walkers.has_method("reconcile"):
		walkers.reconcile()
	_hide_fx()

func _hide_fx() -> void:
	for n in get_tree().get_nodes_in_group("building_fx"):
		(n as Node).set("visible", false)
	for n in get_tree().current_scene.find_children("Fx_*", "CanvasItem", true, false):
		(n as CanvasItem).visible = false

# ── Siembra ───────────────────────────────────────────────────────────

func _write_save(scenario: String) -> void:
	var data := {}
	match scenario:
		"inicio":
			data = _seed_start()
		"media", "combate":
			data = _seed_medium(scenario == "combate")
		_:
			data = _seed_large(scenario == "tormenta")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _base_save(width: int, era: int, buildings: Array, deposits: Array, population: int, resources: Dictionary) -> Dictionary:
	var milestones := {}
	for m in GameConfig.milestone_definitions:
		var mid: String = m["id"]
		if mid == "hq_max":
			continue
		if int(m.get("era", 0)) <= era and era >= 2:
			milestones[mid] = true
	if era == 1:
		milestones = {}
	return {
		# Sin "saved_at": no hay progresion offline ni su cartel encima.
		"format": 2,
		"grid": {"width": width, "height": width, "island_seed": int(options.get("seed", 1))},
		"resources": resources,
		"unlocked_resources": {"gold": true, "wood": true, "steel": era >= 2, "oil": era >= 3},
		"buildings": buildings,
		"deposits": deposits,
		"population": {"population": population, "morale": 75},
		"progression": {"current_era": era, "current_phase": GameConfig.Phase.EXPANSION if era >= 2 else GameConfig.Phase.FOUNDATION,
			"milestones": milestones, "played_seconds": 3600.0 * era},
		# Sin eventos al azar durante la medida: el siguiente queda muy lejos.
		"random_events": {"events_triggered": 0, "timer": 0.0, "next_event_time": 99999.0},
		"storm": {"v": 2, "phase": 0, "seconds_left": 99999.0, "severity": 1, "first": false,
			"armed": era >= 2, "trial_done": true},
		"camera": {"target_x": 0.0, "target_y": 0.0, "yaw": 0.0, "distance": 32.0},
		"tutorial": {"intro_seen": true, "tips_seen": [], "helps_seen": ["quick_guide"], "guide_state": "done"},
	}

## Inicio: el Nucleo con su acera y los yacimientos sueltos de la semilla.
func _seed_start() -> Dictionary:
	var w := 40
	var core := Vector2i(w / 2 - 1, w / 2 - 1)
	var buildings: Array = [{"id": "nucleo", "cell_x": core.x, "cell_y": core.y}]
	var occupied := {}
	for x in range(core.x - 1, core.x + 4):
		for y in range(core.y - 1, core.y + 4):
			occupied[Vector2i(x, y)] = true
			var ring := x == core.x - 1 or x == core.x + 3 or y == core.y - 1 or y == core.y + 3
			if ring:
				buildings.append({"id": "road", "cell_x": x, "cell_y": y})
	var deposits := _loose_deposits(w, occupied, 4)
	_seeded = {"buildings": 1, "roads": buildings.size() - 1, "deposits": deposits.size(), "grid": w, "era": 1, "population": 5}
	return _base_save(w, 1, buildings, deposits, 5, {"gold": 300, "wood": 200, "steel": 0, "oil": 0})

## Colonia media (era 2): 3x3 manzanas.
func _seed_medium(with_army: bool) -> Dictionary:
	var plan := [
		{"extract": "sawmill", "dep": "forest", "n": 2},
		{"extract": "gold_mine", "dep": "gold_vein", "n": 2},
		{"extract": "foundry", "dep": "iron_deposit", "n": 1},
	]
	var slots := ["house", "house", "house", "house", "warehouse", "warehouse", "market",
		"laboratory", "barracks", "garden", "garden", "tower"]
	var data := _city(44, 3, plan, slots, 2)
	if with_army:
		data["army"] = {"units": {"infantry": 4, "artillery": 2}, "training": []}
	return data

## Colonia grande de final (era 3): todos los edificios con su limite, 5x5
## manzanas, gente andando. `storm` la mete en plena Tormenta.
func _seed_large(storm: bool) -> Dictionary:
	var plan := [
		{"extract": "sawmill", "dep": "forest", "n": 2},
		{"extract": "sawmill", "dep": "forest", "n": 2},
		{"extract": "sawmill", "dep": "forest", "n": 1},
		{"extract": "gold_mine", "dep": "gold_vein", "n": 2},
		{"extract": "gold_mine", "dep": "gold_vein", "n": 2},
		{"extract": "foundry", "dep": "iron_deposit", "n": 2},
		{"extract": "foundry", "dep": "iron_deposit", "n": 1},
	]
	var slots: Array = []
	for id in GameConfig.building_limits:
		var lim: int = int(GameConfig.building_limits[id])
		if id in ["sawmill", "gold_mine", "foundry", "road"]:
			continue
		if id == "barracks":
			lim = 5  # sin tope desde 2026-10-18: los cinco del tope de antes
		elif lim < 0:
			lim = 15  # jardines: sin limite, quince
		for i in lim:
			slots.append(id)
	var data := _city(48, 5, plan, slots, 3)
	data["army"] = {"units": {"infantry": 8, "artillery": 6, "vehicle": 4}, "training": []}
	if storm:
		data["storm"] = {"v": 2, "phase": 3, "seconds_left": 99999.0, "severity": 2, "first": false,
			"armed": true, "trial_done": true}
	return data

## Cuadricula de `blocks` x `blocks` manzanas centrada en la rejilla. La del
## centro lleva el Nucleo; `plan` son manzanas de extractores (dos arriba y su
## yacimiento de 4x2 debajo); `slots`, edificios 2x2 en las esquinas del resto.
func _city(width: int, blocks: int, plan: Array, slots: Array, era: int) -> Dictionary:
	var base := width / 2 - (blocks * BLOCK) / 2
	var span := blocks * BLOCK
	var buildings: Array = []
	var deposits: Array = []
	var occupied := {}
	var roads := {}
	for k in blocks + 1:
		var a := base + k * BLOCK
		for b in range(base, base + span + 1):
			roads[Vector2i(a, b)] = true
			roads[Vector2i(b, a)] = true
	for x in range(base - 1, base + span + 2):
		for y in range(base - 1, base + span + 2):
			occupied[Vector2i(x, y)] = true
	var center := blocks / 2
	var order: Array = []
	for j in blocks:
		for i in blocks:
			if i != center or j != center:
				order.append(Vector2i(i, j))
	_shuffle(order)
	slots = slots.duplicate()
	_shuffle(slots)
	var core_o := Vector2i(base + center * BLOCK + 1, base + center * BLOCK + 1)
	buildings.append({"id": "nucleo", "cell_x": core_o.x, "cell_y": core_o.y})
	var bi := 0
	var counts := {}
	for p in plan:
		var o := _block_origin(base, order[bi])
		bi += 1
		for k in int(p["n"]):
			var c := o + Vector2i(2 * k, 0)
			buildings.append({"id": p["extract"], "cell_x": c.x, "cell_y": c.y})
			counts[p["extract"]] = int(counts.get(p["extract"], 0)) + 1
		deposits.append({"id": p["dep"], "cell_x": o.x, "cell_y": o.y + 2, "size_x": 4, "size_y": 2})
	var si := 0
	while si < slots.size() and bi < order.size():
		var o := _block_origin(base, order[bi])
		bi += 1
		for off in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
			if si >= slots.size():
				break
			var id: String = slots[si]
			si += 1
			var c: Vector2i = o + off
			var entry := {"id": id, "cell_x": c.x, "cell_y": c.y}
			if id == "house":
				entry["level"] = 2
			buildings.append(entry)
			counts[id] = int(counts.get(id, 0)) + 1
	for c in roads:
		buildings.append({"id": "road", "cell_x": c.x, "cell_y": c.y})
	deposits.append_array(_loose_deposits(width, occupied, 3))
	var houses := int(counts.get("house", 0))
	var room := 5 + houses * (9 if era >= 2 else 6)
	# Muy por debajo del tope de la bolsa: sin el aviso de "bolsa llena" encima.
	var resources := {"gold": 900, "wood": 600, "steel": 300, "oil": 150} if era >= 3 		else {"gold": 400, "wood": 300, "steel": 150, "oil": 0}
	_seeded = {"buildings": buildings.size() - roads.size(), "roads": roads.size(), "deposits": deposits.size(),
		"grid": width, "era": era, "population": room, "by_type": counts}
	var data := _base_save(width, era, buildings, deposits, room, resources)
	data["camera"] = {"target_x": 0.0, "target_y": 0.0, "yaw": 0.0, "distance": 40.0 + blocks * 4.0}
	return data

func _block_origin(base: int, b: Vector2i) -> Vector2i:
	return Vector2i(base + b.x * BLOCK + 1, base + b.y * BLOCK + 1)

## `per_type` yacimientos de cada tipo fuera de la ciudad, sin solaparse.
func _loose_deposits(width: int, occupied: Dictionary, per_type: int) -> Array:
	var out: Array = []
	var margin := 4
	for id in ["forest", "gold_vein", "iron_deposit", "oil_well"]:
		var placed := 0
		var tries := 0
		while placed < per_type and tries < 400:
			tries += 1
			var size := Vector2i(_rng.randi_range(2, 3), _rng.randi_range(2, 3))
			var cell := Vector2i(_rng.randi_range(margin, width - margin - size.x), _rng.randi_range(margin, width - margin - size.y))
			var free := true
			for x in range(cell.x - 1, cell.x + size.x + 1):
				for y in range(cell.y - 1, cell.y + size.y + 1):
					if occupied.has(Vector2i(x, y)):
						free = false
			if not free:
				continue
			for x in range(cell.x, cell.x + size.x):
				for y in range(cell.y, cell.y + size.y):
					occupied[Vector2i(x, y)] = true
			out.append({"id": id, "cell_x": cell.x, "cell_y": cell.y, "size_x": size.x, "size_y": size.y})
			placed += 1
	return out

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ── Escena ────────────────────────────────────────────────────────────

func _dismiss_overlays() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var title := scene.get_node_or_null("TitleMenu")
	if title and title.has_method("is_open") and title.is_open():
		title.close_menu()
	for panel_name in ["TutorialPanel", "HelperPanel"]:
		var p := scene.get_node_or_null(panel_name)
		if p is CanvasLayer:
			(p as CanvasLayer).visible = false
	get_tree().paused = false

func _set_camera(scenario: String, view: String) -> void:
	var d := 32.0
	match scenario:
		"media", "combate":
			d = 52.0
		"grande", "tormenta", "grande_2d":
			d = 60.0
	var scene := get_tree().current_scene
	if view == "2d":
		var cam2 := scene.get_node_or_null("Camera2D")
		if cam2 and cam2.has_method("look_at_world"):
			cam2.look_at_world(Vector2.ZERO, d)
	else:
		var cam := scene.get_node_or_null("MonumentalCamera")
		if cam and cam.has_method("set_state"):
			cam.set_state({"target_x": 0.0, "target_y": 0.0, "yaw": 0.0, "distance": d})

func _walkers() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("BuildingPlacer/WorkerWalkers") if scene else null

# ── Informe ───────────────────────────────────────────────────────────

func _report(scenario: String, view: String, quality: String, m: Dictionary, prof: Array, shot: String) -> Dictionary:
	var scene := get_tree().current_scene
	var classes := {}
	var processing := 0
	var physics := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var cls := node.get_class()
		classes[cls] = int(classes.get(cls, 0)) + 1
		if node.get_script() != null:
			if node.is_processing() and node.has_method("_process"):
				processing += 1
			if node.is_physics_processing() and node.has_method("_physics_process"):
				physics += 1
	var top_classes: Array = []
	for c in classes:
		top_classes.append({"class": c, "count": classes[c]})
	top_classes.sort_custom(func(a, b): return a["count"] > b["count"])
	var world_look := scene.get_node_or_null("WorldEnvironment") if scene else null
	var effective: String = world_look.get_quality() if world_look and world_look.has_method("get_quality") else ""
	var mem := OS.get_memory_info()
	var tag: String = options.get("tag", "")
	if tag == "":
		tag = "%s_%s" % [RenderingServer.get_current_rendering_method(), quality]
	return {
		"when": Time.get_datetime_string_from_system(),
		"tag": tag,
		"scenario": scenario,
		"view": view,
		"quality": quality,
		"quality_effective": effective if quality != "minima" else "minima (low + extra)",
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(),
		"cpu_threads": OS.get_processor_count(),
		"system_ram_mb": int(mem.get("physical", 0)) / 1048576,
		"godot": Engine.get_version_info().get("string", ""),
		"window": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"scaling_3d": get_viewport().scaling_3d_scale,
		"vsync": bool(options.get("vsync", false)),
		"seed": int(options.get("seed", 1)),
		"seeded": _seeded,
		"metrics": m,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"static_mem_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"process_mem_mb": _process_memory_mb(),
		"scripts_processing": processing,
		"scripts_physics": physics,
		"node_classes": top_classes.slice(0, 25),
		"profile": prof,
		"shot": shot,
	}

## Memoria del proceso (working set y privada) en MB. Windows por PowerShell,
## Linux/Android por /proc; si no se puede, -1.
func _process_memory_mb() -> Dictionary:
	var pid := OS.get_process_id()
	if OS.get_name() == "Windows":
		var out: Array = []
		# Sin comillas: Windows se las come al pasar el argumento. Dos lineas.
		# Tercera linea: cuantos Godot hay corriendo (este, su consola y los ajenos),
		# para saber si la medida compartio la maquina con otros.
		var cmd := "$p=Get-Process -Id %d; $p.WorkingSet64; $p.PrivateMemorySize64; @(Get-Process Godot*).Count" % pid
		var code := OS.execute("powershell", ["-NoProfile", "-Command", cmd], out, true)
		if code == 0 and out.size() > 0:
			var parts := str(out[0]).strip_edges().replace("\r", "").replace("\n", " ").split(" ", false)
			if parts.size() >= 2:
				return {"working_set": float(parts[0]) / 1048576.0, "private": float(parts[1]) / 1048576.0,
					"godot_processes": int(parts[2]) if parts.size() >= 3 else -1}
		print("perf_probe: no se pudo leer la memoria del proceso (codigo %d): %s" % [code, str(out)])
	elif FileAccess.file_exists("/proc/self/status"):
		var txt := FileAccess.get_file_as_string("/proc/self/status")
		for line in txt.split("\n"):
			if line.begins_with("VmRSS:"):
				return {"working_set": float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0, "private": -1.0}
	return {"working_set": -1.0, "private": -1.0}

func _write_outputs(r: Dictionary) -> void:
	var base := "%s/%s_%s" % [OUT_DIR, r["tag"], r["scenario"]]
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(r, "\t"))
	f.close()
	var csv_path := "%s/%s" % [OUT_DIR, CSV_NAME]
	var header := "when,tag,scenario,view,quality,renderer,gpu,window,scaling_3d,fps_mean,fps_1pct_low,frame_ms_p50,frame_ms_p99,frame_ms_max,process_peak_ms,physics_peak_ms,render_cpu_ms,cpu_other_ms,render_gpu_ms,draw_calls,objects_in_frame,primitives_in_frame,nodes,objects,static_mem_mb,video_mem_mb,texture_mem_mb,working_set_mb,walkers,buildings,roads"
	var is_new := not FileAccess.file_exists(csv_path)
	var c := FileAccess.open(csv_path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if is_new:
		c.store_line(header)
	else:
		c.seek_end()
	var m: Dictionary = r["metrics"]
	var row := [r["when"], r["tag"], r["scenario"], r["view"], r["quality"], r["renderer"], "\"%s\"" % r["gpu"], r["window"],
		"%.2f" % r["scaling_3d"], "%.1f" % m["fps_mean"], "%.1f" % m["fps_1pct_low"], "%.2f" % m["frame_ms_p50"],
		"%.2f" % m["frame_ms_p99"], "%.2f" % m["frame_ms_max"], "%.3f" % m["process_peak_ms"], "%.3f" % m["physics_peak_ms"],
		"%.3f" % m["render_cpu_ms"], "%.3f" % m["cpu_other_ms"], "%.3f" % m["render_gpu_ms"], "%.0f" % m["draw_calls"], "%.0f" % m["objects_in_frame"],
		"%.0f" % m["primitives_in_frame"], "%d" % int(r["nodes"]), "%d" % int(r["objects"]), "%.1f" % r["static_mem_mb"],
		"%.1f" % r["video_mem_mb"], "%.1f" % r["texture_mem_mb"], "%.0f" % float(r["process_mem_mb"].get("working_set", -1.0)),
		"%.1f" % m["walkers_on_street"], str(_seeded.get("buildings", 0)), str(_seeded.get("roads", 0))]
	c.store_line(",".join(PackedStringArray(row.map(func(v): return str(v)))))
	c.close()
	print("perf_probe: ", ProjectSettings.globalize_path(base + ".json"))

func _print_table(r: Dictionary) -> void:
	var m: Dictionary = r["metrics"]
	print("perf_probe: GPU '%s' (%s), %s / %s, calidad %s -> %s, ventana %s, scaling_3d %.2f" % [
		r["gpu"], r["gpu_vendor"], r["renderer"], r["driver"], r["quality"], r["quality_effective"], r["window"], r["scaling_3d"]])
	print("perf_probe: sembrado %s" % JSON.stringify(r["seeded"]))
	print("| escenario | fps | 1 % bajo | p99 ms | pico proceso ms | pico fisica ms | render CPU ms | resto CPU ms | GPU ms | draw calls | objetos | primitivas | nodos | memoria est. MB | video MB | proceso MB |")
	print("| %s | %.0f | %.0f | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.0f | %.0f | %.0f | %d | %.0f | %.0f | %.0f |" % [
		r["scenario"], m["fps_mean"], m["fps_1pct_low"], m["frame_ms_p99"], m["process_peak_ms"], m["physics_peak_ms"],
		m["render_cpu_ms"], m["cpu_other_ms"], m["render_gpu_ms"], m["draw_calls"], m["objects_in_frame"], m["primitives_in_frame"],
		int(r["nodes"]), r["static_mem_mb"], r["video_mem_mb"], float(r["process_mem_mb"].get("working_set", -1.0))])
	print("perf_probe: caminantes en la calle %.1f de %d, scripts con _process %d, con _physics_process %d" % [
		m["walkers_on_street"], m["walker_actors"], r["scripts_processing"], r["scripts_physics"]])
	var prof: Array = r["profile"]
	if not prof.is_empty():
		print("perf_probe: perfil por script (us por fotograma, nodos):")
		for i in mini(15, prof.size()):
			var p: Dictionary = prof[i]
			print("perf_probe:   %8.1f us  %3d nodos  %s" % [p["us_per_frame"], p["nodes"], p["script"]])

func _shot(scenario: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var tag: String = options.get("tag", "")
	if tag == "":
		tag = "%s_%s" % [RenderingServer.get_current_rendering_method(), options.get("quality", "auto")]
	var path := ProjectSettings.globalize_path("%s/%s_%s.png" % [OUT_DIR, tag, scenario])
	img.save_png(path)
	return path

func _finish(code: int) -> void:
	GameConfig.ui_graphics_quality = _saved_quality
	ViewMode.set_preference(_saved_view)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit(code)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _seconds(s: float) -> void:
	var end_at := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end_at:
		await get_tree().process_frame
