extends GdUnitTestSuite
## Nada se sale por la derecha (fix/desbordes-derecha, ronda de Bryan sobre la
## 1.1: "hay interfaces que se desbordan a la derecha"). Abre las ventanas
## principales en el lienzo de telefono pequeno (640x360) y en el de PC
## (1280x720), con una colonia avanzada (era 3, todo abierto, tropa de tierra,
## mar y aire, campana a medias, poco dinero para que salgan las fichas rojas) y
## falla si algun Control visible pasa del borde derecho del lienzo o del panel
## que lo recorta (tests/ui/overflow_scan.gd). La sonda tools/desborde_probe.gd
## hace lo mismo con ventana, en todas las pantallas y tamanos.

const Scan := preload("res://tests/ui/overflow_scan.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")

## [escena, nombre del nodo, metodo que la abre, pestanas (metodo, valores)].
const WINDOWS := [
	["res://scenes/ui/ConstructionMenu.tscn", "ConstructionMenu", "_open", []],
	["res://scenes/ui/MarketPanel.tscn", "MarketPanel", "open", []],
	["res://scenes/ui/TechTreePanel.tscn", "TechTreePanel", "open", []],
	["res://scenes/ui/ArmyPanel.tscn", "ArmyPanel", "open", ["select_tab", ["land", "sea", "air"]]],
	["res://scenes/ui/SkirmishPanel.tscn", "SkirmishPanel", "open", ["select_tab", ["land", "sea", "air", "raids"]]],
	["res://scenes/ui/SettingsPanel.tscn", "SettingsPanel", "toggle", ["select_tab", [0, 1, 2, 3]]],
	["res://scenes/ui/ContractPanel.tscn", "ContractPanel", "open", []],
	["res://scenes/ui/RankPanel.tscn", "RankPanel", "open", []],
	["res://scenes/ui/HelpIndexPanel.tscn", "HelpIndexPanel", "open", []],
	["res://scenes/ui/PauseMenu.tscn", "PauseMenu", "open_menu", []],
	["res://scenes/ui/ObjectivePanel.tscn", "ObjectivePanel", "toggle", []],
]

## Lo que CONSTRUIR ensena en su ficha: los de coste mas largo.
const BUILD_DETAILS := ["headquarters", "shipyard", "refinery", "statue"]
## Fichas de edificio: el CG (siete cosas para mejorar) y la Fundicion (recoger).
const FICHAS := ["headquarters", "foundry", "barracks", "shipyard"]

var _parked: Dictionary = {}
var _host: Node
var _saved := {}
var _nodes: Array = []

func before_test() -> void:
	_parked = SettingsParking.park()
	get_tree().paused = false
	var root := get_tree().root
	var amounts := {}
	for t in ResourceManager.get_all():
		amounts[ResourceManager.get_type_name(t)] = ResourceManager.get_amount(t)
	_saved = {
		"factor": root.content_scale_factor, "aspect": root.content_scale_aspect,
		"base": root.content_scale_size, "phone": CartoonTheme.phone,
		"first_sortie": TutorialManager.first_sortie_done, "mode": GameMode.current,
		"era": ProgressionManager.current_era, "units": ArmyManager._units.duplicate(),
		"campaigns": CombatManager._campaigns.progress.duplicate(),
		"amounts": amounts, "unlocks": ResourceManager.get_unlock_state(),
		# Colocar edificios da XP (rango, bandera) y abre consejos: se devuelve
		# todo para no colar consejos en las suites de detras.
		"tutorial": TutorialManager.get_save_data(), "rank": RankManager.get_save_data(),
	}
	GridManager.clear_all()
	# Una colonia avanzada: era 3, todo abierto, tropa en los tres frentes y poco
	# dinero (las fichas de lo que falta salen en rojo y son las mas anchas).
	GameMode.current = GameMode.Mode.CAMPAIGN
	TutorialManager.first_sortie_done = true
	ProgressionManager.current_era = 3
	for t in ResourceManager.get_all():
		ResourceManager.unlock(t)
	ResourceManager.set_amounts({"gold": 120, "wood": 60, "steel": 10, "oil": 0})
	ArmyManager._units = {"infantry": 4, "artillery": 3, "vehicle": 2, "torpedo_boat": 2,
		"gunboat": 3, "dreadnought": 1, "fighter": 4, "airship": 1}
	CombatManager._campaigns.progress = {"land": 3, "sea": 1, "air": 0}
	_host = Node.new()
	_host.name = "FakeMain"
	add_child(_host)

func after_test() -> void:
	get_tree().paused = false
	if is_instance_valid(_host):
		_host.free()
	UIManager.reset()
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	var root := get_tree().root
	root.content_scale_factor = _saved["factor"]
	root.content_scale_aspect = _saved["aspect"]
	root.content_scale_size = _saved["base"]
	CartoonTheme.phone = _saved["phone"]
	TutorialManager.first_sortie_done = _saved["first_sortie"]
	GameMode.current = _saved["mode"]
	ProgressionManager.current_era = _saved["era"]
	ArmyManager._units = _saved["units"]
	CombatManager._campaigns.progress = _saved["campaigns"]
	ResourceManager.set_unlock_state(_saved["unlocks"])
	ResourceManager.set_amounts(_saved["amounts"])
	RankManager.load_save_data(_saved["rank"])
	TutorialManager.load_save_data(_saved["tutorial"])
	UILayoutManager.refresh_viewport()
	SettingsParking.restore(_parked)

## Pone el lienzo logico a `size` y las piezas de telefono si toca. En headless
## la ventana mide 64x64: el lienzo se fija con el tamano base y sin proporcion.
func _canvas(size: Vector2) -> void:
	var root := get_tree().root
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = Vector2i(size)
	root.content_scale_factor = 1.0
	CartoonTheme.phone = DeviceProfile.is_phone_canvas(size)
	UILayoutManager.refresh_viewport()

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _right_overflows(panel: Node, label: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in Scan.report(Scan.scan(panel, true)):
		out.append("%s: %s" % [label, line])
	# Que la ventana se abrio de verdad: con lo cerrado no hay nada que mirar.
	if Scan.last_checked < 8:
		out.append("%s: solo %d controles visibles (no se abrio?)" % [label, Scan.last_checked])
	return out

func _add(scene: String, node_name: String) -> Node:
	var panel: Node = load(scene).instantiate()
	panel.name = node_name
	_host.add_child(panel)
	return panel

func _walk_windows(size: Vector2) -> PackedStringArray:
	_canvas(size)
	await _frames(2)
	var vp: Vector2 = get_tree().root.get_visible_rect().size
	assert_float(vp.x).override_failure_message("lienzo %s" % vp).is_equal_approx(size.x, 2.0)
	var found := PackedStringArray()
	for w in WINDOWS:
		var panel := _add(String(w[0]), String(w[1]))
		await _frames(2)
		panel.call(String(w[2]))
		await _frames(4)
		get_tree().paused = false
		var tabs: Array = w[3]
		if tabs.is_empty():
			found.append_array(_right_overflows(panel, "%s %s" % [w[1], size]))
		else:
			for t in tabs[1]:
				panel.call(String(tabs[0]), t)
				await _frames(4)
				found.append_array(_right_overflows(panel, "%s[%s] %s" % [w[1], t, size]))
		UIManager.close_all_windows()
		get_tree().paused = false
		panel.queue_free()
		await _frames(1)
	found.append_array(await _walk_build_details(size))
	found.append_array(await _walk_fichas(size))
	return found

## CONSTRUIR con todo abierto (Sandbox: sin requisitos) y la ficha de lo que mas
## pide: las filas con cinco fichas y el detalle del Cuartel General.
func _walk_build_details(size: Vector2) -> PackedStringArray:
	var found := PackedStringArray()
	GameMode.current = GameMode.Mode.SANDBOX
	var menu := _add("res://scenes/ui/ConstructionMenu.tscn", "ConstructionMenu")
	await _frames(2)
	menu.call("_open")
	await _frames(4)
	for id in BUILD_DETAILS:
		menu.call("_select_building", load("res://data/buildings/%s.tres" % id))
		await _frames(4)
		found.append_array(_right_overflows(menu, "CONSTRUIR %s %s" % [id, size]))
	menu.call("_close")
	UIManager.close_all_windows()
	menu.queue_free()
	GameMode.current = GameMode.Mode.CAMPAIGN
	await _frames(1)
	return found

## La ficha de los edificios de coste largo, con algo para recoger.
func _walk_fichas(size: Vector2) -> PackedStringArray:
	var found := PackedStringArray()
	var panel := _add("res://scenes/ui/BuildingInfoPanel.tscn", "BuildingInfoPanel")
	await _frames(2)
	var i := 0
	for id in FICHAS:
		var data: BuildingData = load("res://data/buildings/%s.tres" % id)
		var n := Node3D.new()
		n.set_meta("level", 1)
		_nodes.append(n)
		assert_bool(GridManager.place_building(Vector2i(2 + i * 6, 2), data, n)).is_true()
		i += 1
		ProductionManager.keep_in_building(n, {"steel": 20, "gold": 11})
		EventBus.building_clicked.emit(n, data)
		await _frames(4)
		found.append_array(_right_overflows(panel, "Ficha %s %s" % [id, size]))
		EventBus.building_deselected.emit()
		await _frames(1)
	panel.queue_free()
	await _frames(1)
	return found

func test_nothing_spills_to_the_right_on_a_small_phone() -> void:
	var found: PackedStringArray = await _walk_windows(Vector2(640, 360))
	assert_array(Array(found)).override_failure_message("\n".join(found)).is_empty()

func test_nothing_spills_to_the_right_on_a_pc() -> void:
	var found: PackedStringArray = await _walk_windows(Vector2(1280, 720))
	assert_array(Array(found)).override_failure_message("\n".join(found)).is_empty()

## La tablet de 1280x800 (escala 115 %): lienzo de 1113x696.
func test_nothing_spills_to_the_right_on_a_tablet() -> void:
	var found: PackedStringArray = await _walk_windows(Vector2(1113, 696))
	assert_array(Array(found)).override_failure_message("
".join(found)).is_empty()

## La comprobacion ve de verdad algo que se sale (si no, el test no prueba nada).
func test_the_scan_catches_a_row_wider_than_the_screen() -> void:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var row := HBoxContainer.new()
	layer.add_child(row)
	var l := Label.new()
	l.text = "x".repeat(400)
	row.add_child(l)
	await _frames(2)
	var hits: Array = Scan.scan(layer, true)
	assert_int(hits.size()).is_equal(1)
	assert_str(String(hits[0]["side"])).is_equal("right")
