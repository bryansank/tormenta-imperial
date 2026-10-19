extends Node
## Sonda de la carretera larga (feat/carretera-arrastrar): abre la partida, coge
## la carretera, dibuja un tramo en L desde la acera del Nucleo y hace dos
## capturas: la vista previa (verde + "N tramos · N oro") y el tramo ya tendido.
## Luego otra con poco oro (parte verde, parte roja).
##
## El tramo se dibuja con la API de PlacementAssist (line_start / line_to /
## line_commit), la misma que usan el raton y el dedo: asi la sonda no mueve el
## cursor del ordenador. Las capturas van a docs/media/dev/ (ignorada por git).
## SIEMPRE con un override.cfg propio: siembra y guarda una partida.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const OUT_DIR := "res://docs/media/dev"

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/road_line_%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("road_line_probe: ", path)

## Sin prologo, guia rapida ni tutorial: tapan el mapa (y el prologo pausa).
func _quiet_onboarding() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.mark_help_seen("quick_guide")
	if not TutorialManager.tips_seen.has("road_drag"):
		TutorialManager.tips_seen.append("road_drag")
	if TutorialManager.is_guide_active():
		var dev := GameConfig.dev_mode
		GameConfig.dev_mode = true
		TutorialManager.skip_guide()
		GameConfig.dev_mode = dev
	for group in ["prologue_screen", "quick_guide"]:
		for n in get_tree().get_nodes_in_group(group):
			if n.has_method("is_open") and n.is_open():
				n.close()
	get_tree().paused = false

func _hide_overlays(scene: Node) -> void:
	_quiet_onboarding()
	for n in ["TutorialPanel", "HelperPanel", "ObjectivePanel", "NotificationPanel"]:
		var node := scene.get_node_or_null(n)
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	for g in ["quick_guide"]:
		for node in get_tree().get_nodes_in_group(g):
			if node is CanvasLayer:
				(node as CanvasLayer).visible = false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var view := "2d" if OS.get_cmdline_user_args().has("--view=2d") else "3d"
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	var placer: Node = null
	for i in 900:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null:
			placer = scene.get_node_or_null("BuildingPlacer")
		if placer != null and placer.has_method("get_assist") and not Rules.core_cells().is_empty() and i > 60:
			break
	if placer == null or Rules.core_cells().is_empty():
		push_error("road_line_probe: sin colocador o sin Nucleo")
		get_tree().quit(1)
		return
	await _frames(60)
	_hide_overlays(get_tree().current_scene)
	var core: Array = Rules.core_cells()
	var lo: Vector2i = core[0]
	for c in core:
		lo = Vector2i(mini(lo.x, (c as Vector2i).x), mini(lo.y, (c as Vector2i).y))
	# La acera del lado este, en la fila del medio del Nucleo.
	var start := lo + Vector2i(3, 1)
	var end := start + Vector2i(8, 4)
	ResourceManager.set_amounts({"gold": 400})
	var road: BuildingData = load("res://data/buildings/road.tres")
	EventBus.building_selected_for_placement.emit(road)
	await _frames(5)
	_hide_overlays(get_tree().current_scene)
	var assist: Node = placer.get_assist()
	placer.assist_center_on(start + Vector2i(5, 4))
	await _frames(20)
	assist.line_start = start
	assist.line_to(end)
	await _frames(10)
	await _shot("%s_preview" % view)
	assist.line_commit()
	await _frames(20)
	await _shot("%s_laid" % view)
	# Poco oro: 4 tramos pagados (verde) y el resto en rojo.
	ResourceManager.set_amounts({"gold": 4})
	assist.line_start = end
	assist.line_to(end + Vector2i(5, -4))
	await _frames(10)
	await _shot("%s_short_gold" % view)
	EventBus.building_placement_cancelled.emit()
	await _frames(5)
	get_tree().quit()
