extends Node
## Dev tool: siembra una partida ya desarrollada y captura la interfaz real
## para la documentacion. Nada de mockups: son fotogramas del juego corriendo.
##
## Uso: registrar temporalmente como autoload y arrancar el juego.
##   project.godot -> [autoload] -> ShowcaseShots="*res://tools/showcase_shots.gd"
## Salida: res://docs/media/*.png  (res:// es escribible sin exportar)
## Quitar la linea del autoload al terminar.
##
## Hermano de tools/ui_tour.gd, que audita la interfaz desde una partida vacia.

const OUT_DIR := "res://docs/media"
const SETTLE := 2.5
const STEP := 0.45

## Edificios a plantar: id, celda deseada. Si la celda esta ocupada por un
## deposito, se busca hueco en espiral alrededor.
const LAYOUT := [
	["gold_mine", Vector2i(15, 15)],
	["sawmill",   Vector2i(25, 15)],
	["foundry",   Vector2i(15, 24)],
	["barracks",  Vector2i(25, 24)],
	["warehouse", Vector2i(27, 21)],
	["tower",     Vector2i(14, 19)],
	["tower",     Vector2i(28, 19)],
	["house",     Vector2i(17, 16)],
	["house",     Vector2i(19, 16)],
	["house",     Vector2i(21, 16)],
	["house",     Vector2i(23, 16)],
	["house",     Vector2i(17, 26)],
	["house",     Vector2i(19, 26)],
	["house",     Vector2i(21, 26)],
	["house",     Vector2i(23, 26)],
	["garden",    Vector2i(18, 21)],
	["garden",    Vector2i(18, 22)],
	["fountain",  Vector2i(24, 21)],
	["statue",    Vector2i(24, 22)],
]

## Calzada alrededor del nucleo (20,20 - 22,22) y las dos avenidas.
const ROADS := [
	Vector2i(19, 19), Vector2i(20, 19), Vector2i(21, 19), Vector2i(22, 19), Vector2i(23, 19),
	Vector2i(19, 23), Vector2i(20, 23), Vector2i(21, 23), Vector2i(22, 23), Vector2i(23, 23),
	Vector2i(19, 20), Vector2i(19, 21), Vector2i(19, 22),
	Vector2i(23, 20), Vector2i(23, 21), Vector2i(23, 22),
	Vector2i(24, 19), Vector2i(25, 19), Vector2i(26, 19),
	Vector2i(18, 19), Vector2i(17, 19), Vector2i(16, 19),
]

## Paneles a fotografiar: nombre del nodo en Main, propiedad con su modal, archivo.
const PANELS := [
	{"node": "ConstructionMenu", "prop": "_modal", "file": "02_construccion"},
	{"node": "MarketPanel",      "prop": "_panel", "file": "03_mercado"},
	{"node": "TechTreePanel",    "prop": "_panel", "file": "04_tecnologia"},
	{"node": "ArmyPanel",        "prop": "_panel", "file": "05_ejercito"},
	# ProgressPanel queda fuera a proposito: los hitos se marcan al construir de
	# verdad, y este sembrado los salta. Saldria "0%" junto a un imperio hecho.
]

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[showcase] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main := get_tree().current_scene
	if main == null:
		push_warning("[showcase] no hay escena actual")
		return
	var placer: Node = main.get_node_or_null("BuildingPlacer")
	if placer == null:
		push_warning("[showcase] falta BuildingPlacer")
		return

	_seed_economy()
	_build_base(placer)
	_announce(main)
	_hide_dev_chrome(main)
	_frame_camera(main)
	# Los globos del tutorial tapan el juego: fuera para las fotos.
	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper != null:
		helper.visible = false

	# Margen para que se apaguen los avisos que dispara el sembrado.
	await get_tree().create_timer(3.5).timeout
	_top_up()
	await _shot("01_base")

	var taken := 1
	for p in PANELS:
		var host: Node = main.get_node_or_null(String(p["node"]))
		if host == null:
			continue
		var modal: Variant = host.get(String(p["prop"]))
		if modal == null or not (modal is CanvasItem):
			continue
		var was: bool = modal.visible
		modal.visible = true
		_top_up()
		await _shot(String(p["file"]))
		modal.visible = was
		taken += 1

	print("[showcase] %d capturas en %s" % [taken, OUT_DIR])
	get_tree().quit()

## Una partida creible de mitad de campana: era industrial, gente contenta,
## un ejercito pequeno y las primeras tecnologias.
func _seed_economy() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false})
	ResourceManager.set_warehouse_count(1)
	_top_up()
	ProgressionManager.current_era = 2

	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 84

	ArmyManager._units = {"infantry": 6, "artillery": 3}

	# tech_definitions es un Array de diccionarios, no un mapa por id.
	var seen := {}
	for tech in GameConfig.tech_definitions:
		var branch: String = String(tech.get("branch", ""))
		if branch != "" and not seen.has(branch):
			seen[branch] = true
			TechTreeManager._researched[String(tech["id"])] = true

## La economia corre rapido en dev_mode y se come el oro entre captura y
## captura. Se reponen los valores justo antes de cada foto.
func _top_up() -> void:
	ResourceManager.set_amounts({"gold": 2480, "wood": 1165, "steel": 640, "oil": 0})

## Los paneles se dibujan al arrancar y solo se refrescan por senal: sin esto,
## el sembrado no se ve en pantalla.
func _announce(main: Node) -> void:
	EventBus.resource_unlocked.emit("steel")
	EventBus.era_advanced.emit(ProgressionManager.current_era)
	EventBus.army_changed.emit()
	# El aviso de objetivo es texto de onboarding: con la base ya levantada
	# dice lo contrario de lo que se ve, asi que se retira de las fotos.
	var notif: Node = main.get_node_or_null("NotificationPanel")
	if notif != null:
		var hint: Variant = notif.get("_objective_label")
		if hint is CanvasItem and (hint as Node).get_parent() is CanvasItem:
			((hint as Node).get_parent() as CanvasItem).visible = false
	var tech: Node = main.get_node_or_null("TechTreePanel")
	if tech != null and tech.has_method("_refresh_tech_states"):
		tech._refresh_tech_states()

## Fuera el boton LIMPIAR: solo existe en dev_mode y no es parte del juego.
func _hide_dev_chrome(main: Node) -> void:
	var hud: Node = main.get_node_or_null("ResourceHUD")
	if hud == null:
		return
	for node in _descendants(hud):
		if node is Button and String((node as Button).text) == Tr.t("BTN_CLEAR"):
			(node as Button).visible = false

func _descendants(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out

## Un poco mas de altura para que la base entre entera en el encuadre.
func _frame_camera(main: Node) -> void:
	var cam: Node = main.get_node_or_null("MonumentalCamera")
	if cam == null:
		return
	cam._distance = 30.0
	cam._target_distance = 30.0

func _build_base(placer: Node) -> void:
	for cell in ROADS:
		_plant(placer, "road", cell)
	for entry in LAYOUT:
		_plant(placer, String(entry[0]), entry[1] as Vector2i)
	# Los trabajadores se reparten segun lo que hay construido.
	PopulationManager._recalculate_all()

func _plant(placer: Node, id: String, wanted: Vector2i) -> void:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	if data == null:
		push_warning("[showcase] falta data/buildings/%s.tres" % id)
		return
	var cell := _find_spot(wanted, data.grid_size)
	if cell.x < 0:
		push_warning("[showcase] sin hueco para %s cerca de %s" % [id, wanted])
		return
	var node: Node3D = placer.place_building_at(data, cell)
	if node == null:
		return
	# construction_remaining 0 => entra ya terminado y produciendo.
	ProductionManager.register_building(node, data, 0.0)

## Los depositos se generan al azar y pueden caer sobre la celda pedida.
## Se busca en espiral antes de rendirse.
func _find_spot(wanted: Vector2i, size: Vector2i) -> Vector2i:
	if GridManager.can_place(wanted, size):
		return wanted
	for radius in range(1, 5):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var c := wanted + Vector2i(dx, dy)
				if GridManager.is_valid_cell(c) and GridManager.can_place(c, size):
					return c
	return Vector2i(-1, -1)

func _shot(file_name: String) -> void:
	await get_tree().create_timer(STEP).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, file_name])
	print("[showcase] %s.png (err %d)" % [file_name, err])
