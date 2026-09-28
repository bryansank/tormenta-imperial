extends Node
## Dev tool: audita la tipografia de la interfaz. Siembra una partida creible,
## abre cada panel y lo fotografia a la resolucion real de la ventana.
##
## Uso: registrar temporalmente como autoload y arrancar el juego.
##   project.godot -> [autoload] -> UIAudit="*res://tools/ui_audit.gd"
##   godot --path . --resolution 1920x1080 -- antes
## El argumento tras "--" es el prefijo de los archivos.
## Salida: res://docs/media/dev/<prefijo>_<panel>.png  (ignorado por git)
##
## Hermano de tools/ui_tour.gd (audita desde partida vacia) y
## tools/showcase_shots.gd (fotos de prensa).

const OUT_DIR := "res://docs/media/dev"
const SETTLE := 2.0
const STEP := 0.4

const LAYOUT := [
	["gold_mine", Vector2i(15, 15)],
	["sawmill",   Vector2i(25, 15)],
	["foundry",   Vector2i(15, 24)],
	["barracks",  Vector2i(25, 24)],
	["warehouse", Vector2i(27, 21)],
	["house",     Vector2i(17, 16)],
	["house",     Vector2i(19, 16)],
	["house",     Vector2i(21, 16)],
]

## Paneles a fotografiar: nodo en Main, propiedad con su modal, nombre de archivo.
const PANELS := [
	{"node": "ConstructionMenu",  "prop": "_modal", "file": "construccion"},
	{"node": "MarketPanel",       "prop": "_panel", "file": "mercado"},
	{"node": "TechTreePanel",     "prop": "_panel", "file": "tecnologia"},
	{"node": "ArmyPanel",         "prop": "_panel", "file": "ejercito"},
	{"node": "ProgressPanel",     "prop": "_panel", "file": "progreso"},
	{"node": "SettingsPanel",     "prop": "_panel", "file": "ajustes"},
	{"node": "ObjectivePanel",    "prop": "_panel", "file": "objetivos"},
	{"node": "SkirmishPanel",     "prop": "_panel", "file": "escaramuza"},
	{"node": "BuildingInfoPanel", "prop": "_panel", "file": "edificio"},
]

var _prefix := "shot"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = String(args[0])
	var w := get_window()
	print("[ui_audit] ventana=%s viewport=%s content_scale_factor=%s oversampling=%s override=%s" % [
		w.size, get_viewport().get_visible_rect().size, w.content_scale_factor, w.oversampling, w.oversampling_override])
	if args.size() > 1 and String(args[1]) == "nooversampling":
		w.oversampling = false
		print("[ui_audit] oversampling desactivado a proposito")
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main := get_tree().current_scene
	if main == null:
		push_warning("[ui_audit] no hay escena actual")
		get_tree().quit()
		return

	var placer: Node = main.get_node_or_null("BuildingPlacer")
	_seed_economy()
	if placer != null:
		_build_base(placer)
	_announce(main)

	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper != null:
		helper.visible = false

	await get_tree().create_timer(2.5).timeout
	_top_up()
	await _shot("hud")

	# Los globos del tutorial, apilados bajo los paneles que explican: la unica
	# forma de ver que siguen al HUD y no a coordenadas fijas.
	if helper != null:
		var was_helper: bool = GameConfig.ui_helper_visible
		GameConfig.ui_helper_visible = true
		helper.visible = true
		if helper.has_method("_refresh_callouts"):
			helper._refresh_callouts()
		await _shot("ayuda")
		GameConfig.ui_helper_visible = was_helper
		if helper.has_method("_refresh_callouts"):
			helper._refresh_callouts()
		helper.visible = false

	# Menu ☰ desplegado con el panel de edificio abierto: el panel tiene que
	# nacer debajo del ultimo boton, no detras de ellos.
	var market: Node = main.get_node_or_null("MarketPanel")
	var info: Node = main.get_node_or_null("BuildingInfoPanel")
	if market != null and market.has_method("_toggle_sidebar"):
		market._toggle_sidebar()
		var info_modal: Variant = info.get("_panel") if info != null else null
		if info_modal is CanvasItem:
			info_modal.visible = true
		await _shot("menu")
		if info_modal is CanvasItem:
			info_modal.visible = false
		market._toggle_sidebar()

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

	print("[ui_audit] listo (%s) en %s" % [_prefix, OUT_DIR])
	get_tree().quit()

func _seed_economy() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false})
	ResourceManager.set_warehouse_count(1)
	_top_up()
	ProgressionManager.current_era = 2
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 84
	ArmyManager._units = {"infantry": 6, "artillery": 3}
	var seen := {}
	for tech in GameConfig.tech_definitions:
		var branch: String = String(tech.get("branch", ""))
		if branch != "" and not seen.has(branch):
			seen[branch] = true
			TechTreeManager._researched[String(tech["id"])] = true

func _top_up() -> void:
	ResourceManager.set_amounts({"gold": 2480, "wood": 1165, "steel": 640, "oil": 0})

func _announce(main: Node) -> void:
	EventBus.resource_unlocked.emit("steel")
	EventBus.era_advanced.emit(ProgressionManager.current_era)
	EventBus.army_changed.emit()
	var tech: Node = main.get_node_or_null("TechTreePanel")
	if tech != null and tech.has_method("_refresh_tech_states"):
		tech._refresh_tech_states()

func _build_base(placer: Node) -> void:
	for entry in LAYOUT:
		_plant(placer, String(entry[0]), entry[1] as Vector2i)
	PopulationManager._recalculate_all()

func _plant(placer: Node, id: String, wanted: Vector2i) -> void:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	if data == null:
		return
	var cell := _find_spot(wanted, data.grid_size)
	if cell.x < 0:
		return
	var node: Node3D = placer.place_building_at(data, cell)
	if node == null:
		return
	ProductionManager.register_building(node, data, 0.0)

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
	var err := image.save_png("%s/%s_%s.png" % [OUT_DIR, _prefix, file_name])
	print("[ui_audit] %s_%s.png (%dx%d, err %d)" % [_prefix, file_name, image.get_width(), image.get_height(), err])
