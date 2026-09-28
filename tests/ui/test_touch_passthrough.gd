extends GdUnitTestSuite
## El dedo arrastra el mapa casi en cualquier sitio (bug 8).
##
## El GUI entrega un InputEventScreenTouch a CUALQUIER Control no-IGNORE que haya
## bajo el dedo y lo da por manejado; un Container vale PASS por defecto. La fila
## inferior de OnScreenControls (un HBox de lado a lado) se comia asi el 26 % de
## la pantalla en reposo y el 44-47 % al colocar, y InputService, que descarta
## ademas el toque si hay un control "hovered", no llegaba a enterarse.
##
## Aqui se monta el HUD que queda encima del mapa a 1280x800 con el perfil
## tablet y se barre la pantalla con toques de verdad (Viewport.push_input): el
## raton emulado primero y luego el toque, como en Android. Cuenta como "mapa"
## todo punto que no cae sobre un control de verdad (boton, deslizador o panel
## con fondo); de esos, al menos el 90 % tiene que llegar a InputService (o al
## colocador, si agarra el fantasma). En reposo y colocando.

const Placer2D := preload("res://scripts/view2d/BuildingPlacer2D.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const BACKUP_PATH := "user://save_game.touch_passthrough.bak"
const SCENES := ["OnScreenControls", "ResourceHUD", "NotificationPanel", "StormHUD",
	"ObjectivePanel", "HelperPanel", "MarketPanel"]
const STEP := 24.0

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _layers: Array = []
var _placer: Node = null
var _map: Node = null
var _saved := {}
var _hidden: Array = []

func _is_ours(n: Node) -> bool:
	for owner_node in _layers + [_placer]:
		if n == owner_node or owner_node.is_ancestor_of(n):
			return true
	return false

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	var root := get_tree().root
	_saved = {"size": root.size, "csf": root.content_scale_factor,
		"profile": GameConfig.ui_device_profile, "touch": GameConfig.ui_touch_controls,
		"placer": GameManager._placer, "map": GameManager._map_gen, "hold": GameManager._hold_start,
		"started": GameManager._started}
	GameManager._started = false
	GameManager.hold_start()
	GridManager.clear_all()
	# Tablet de 1280x800 con la escala de su perfil (1,15): 1113x696 logicos.
	GameConfig.ui_device_profile = "tablet"
	GameConfig.ui_touch_controls = "auto"
	root.size = Vector2i(1280, 800)
	root.content_scale_factor = float(DeviceProfile.DEFAULTS["tablet"]["ui_scale"])
	UILayoutManager.refresh_viewport()
	_map = MapGen2D.new()
	_map.name = "MapGenerator"
	add_child(_map)
	_placer = Placer2D.new()
	_placer.name = "BuildingPlacer"
	add_child(_placer)
	_map.spawn_deposit("forest", Vector2i(20, 20), -1, Vector2i(2, 2))
	for scene_name in SCENES:
		var layer: Node = load("res://scenes/ui/%s.tscn" % scene_name).instantiate()
		add_child(layer)
		_layers.append(layer)
	# Lo que no es el HUD del mapa (un dialogo que GameManager tenga colgado de
	# otra suite, la capa de gdUnit) se aparta: aqui se mide el HUD.
	# Una capa oculta sigue cogiendo toques en el GUI, asi que se sacan del arbol
	# las que no son de este HUD (dialogos que GameManager tenga colgados de otra
	# suite) y se devuelven al terminar.
	_hidden = []
	EventBus.touch_controls_changed.emit(GameConfig.touch_controls_enabled())
	await await_idle_frame()
	await await_idle_frame()

func after_test() -> void:
	for pair in _hidden:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):
			(pair[1] as Node).add_child(pair[0])
	_hidden = []
	EventBus.building_placement_cancelled.emit()
	for layer in _layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_layers.clear()
	if is_instance_valid(_placer):
		_placer.clear_all_buildings()
		_placer.queue_free()
	if is_instance_valid(_map):
		_map.clear_all_deposits()
		_map.queue_free()
	GridManager.clear_all()
	InputService._purge_touch_state()
	var root := get_tree().root
	root.size = _saved["size"]
	root.content_scale_factor = _saved["csf"]
	GameConfig.ui_device_profile = _saved["profile"]
	GameConfig.ui_touch_controls = _saved["touch"]
	UILayoutManager.refresh_viewport()
	GameManager._placer = _saved["placer"] if is_instance_valid(_saved["placer"]) else null
	GameManager._map_gen = _saved["map"] if is_instance_valid(_saved["map"]) else null
	GameManager._hold_start = _saved["hold"]
	GameManager._started = _saved["started"]
	SaveParking.restore(BACKUP_PATH)

# ── Barrido ──

## Toque real en `p` (coordenadas del lienzo). Devuelve si llego al mundo.
func _probe(p: Vector2) -> bool:
	var root := get_tree().root
	var to_win := root.get_final_transform()
	var m := InputEventMouseMotion.new()
	m.device = InputEvent.DEVICE_ID_EMULATION
	m.position = to_win * p
	root.push_input(m)
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = to_win * p
	t.pressed = true
	root.push_input(t)
	var got: bool = InputService.is_touch_gesture_active() or _placer.get_assist()._finger == 0
	# Se suelta como gesto cancelado: medir sin pulsar ni colocar nada.
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.position = to_win * p
	r.pressed = false
	r.canceled = true
	root.push_input(r)
	InputService._purge_touch_state()
	return got

## Un control "de verdad" bajo `p`: boton, deslizador, campo o panel con fondo.
## Esos pueden quedarse el dedo; lo demas (contenedores, huecos) no.
func _real_control_at(p: Vector2) -> bool:
	for layer in _layers + [_placer]:
		for n in _all(layer):
			if not (n is Control):
				continue
			var c := n as Control
			if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			if not c.get_global_rect().has_point(p):
				continue
			if c is BaseButton or c is Range or c is LineEdit:
				return true
			if c is PanelContainer or c is Panel:
				var sb: StyleBox = c.get_theme_stylebox("panel")
				if sb != null and not (sb is StyleBoxEmpty):
					return true
	return false

func _all(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out

## Saca del arbol las capas que GameManager cuelga por su cuenta (el parte
## offline o el dialogo de partida que deja otra suite al registrar el colocador,
## que llega diferido): no son el HUD del mapa.
func _park_foreign() -> void:
	await await_idle_frame()
	for n in GameManager.get_children(true):
		if n is CanvasLayer:
			_hidden.append([n, GameManager])
			GameManager.remove_child(n)
	# Un boton que otra suite dejo pulsado conserva el foco de raton del GUI, y
	# con foco el GUI no recalcula el control bajo el cursor: se suelta aqui.
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(-10, -10)
	get_tree().root.push_input(rel)

func _sweep(label: String) -> Dictionary:
	await _park_foreign()
	var vp := get_viewport().get_visible_rect().size
	var total := 0
	var eligible := 0
	var reached := 0
	var blocked: Array = []
	var y := STEP * 0.5
	while y < vp.y:
		var x := STEP * 0.5
		while x < vp.x:
			var p := Vector2(x, y)
			total += 1
			# Encima de un control de verdad no se toca: pulsaria botones (el de
			# borrar partida del modo desarrollo, el menu...). Cuenta como tapado.
			if _real_control_at(p):
				x += STEP
				continue
			eligible += 1
			if _probe(p):
				reached += 1
			elif blocked.size() < 12:
				_probe(p)
				var h := get_viewport().gui_get_hovered_control()
				blocked.append("%s:%s" % [p, h.get_path() if h else "none"])
			x += STEP
		y += STEP
	var reached_all := reached
	var r := {"total": total, "eligible": eligible, "reached": reached, "reached_all": reached_all, "blocked": blocked}
	print("[passthrough] %s vp=%s: %d/%d map points reach the world (%.1f %%); full screen %.1f %%; first blocked %s" % [
		label, vp, reached, eligible, 100.0 * reached / maxi(eligible, 1), 100.0 * reached_all / maxi(total, 1), blocked])
	return r

func _assert_sweep(r: Dictionary) -> void:
	# El "mapa" es la mayor parte de la pantalla: si no, el test no mide nada.
	assert_float(float(r["eligible"]) / r["total"]).is_greater(0.75)
	assert_float(float(r["reached"]) / r["eligible"]).is_greater_equal(0.9)
	# Y la pantalla entera, botones incluidos, ya no pierde un tercio.
	assert_float(float(r["reached_all"]) / r["total"]).is_greater(0.8)

func test_the_controls_are_on_screen_for_this_sweep() -> void:
	var osc: CanvasLayer = _layers[0]
	assert_bool(osc.visible).is_true()
	assert_vector(get_viewport().get_visible_rect().size).is_equal_approx(Vector2(1113.04, 695.65), Vector2(1, 1))

func test_idle_the_finger_reaches_the_map_almost_everywhere() -> void:
	_assert_sweep(await _sweep("idle"))

func test_placing_the_finger_reaches_the_map_almost_everywhere() -> void:
	EventBus.building_selected_for_placement.emit(load("res://data/buildings/sawmill.tres"))
	await await_idle_frame()
	assert_bool((_layers[0] as CanvasLayer).is_placing_shown()).is_true()
	_assert_sweep(await _sweep("placing"))

func test_the_old_dead_strip_is_map_again() -> void:
	# Los puntos del diagnostico (s1_strip.log) en el lienzo de 1280x720, llevados
	# al de la tablet: la franja inferior entre la cruceta y la columna derecha.
	EventBus.building_selected_for_placement.emit(load("res://data/buildings/sawmill.tres"))
	await await_idle_frame()
	await _park_foreign()
	var vp := get_viewport().get_visible_rect().size
	for p in [Vector2(380, 470), Vector2(380, 600), Vector2(900, 600)]:
		var q: Vector2 = p * Vector2(vp.x / 1280.0, vp.y / 720.0)
		assert_bool(_probe(q)).override_failure_message("toque en %s no llega al mapa" % q).is_true()
