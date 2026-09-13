extends Node
## Dev tool: opens every UI panel in turn and saves a screenshot of each to
## user://ui_tour/, then quits. Lets an agent (or you) review the whole interface
## without clicking through it by hand.
##
## Usage: register temporarily as an autoload and run the game.
##   project.godot -> [autoload] -> UITour="*res://tools/ui_tour.gd"
## Screenshots land in %APPDATA%/Godot/app_userdata/Tormenta Imperial/ui_tour/
## Remove the autoload line when you are done.

const OUT_DIR := "user://ui_tour"
## Seconds to let the game settle before touring, and between shots.
const SETTLE := 3.0
const STEP := 0.35

## Panels to visit: node name in Main -> the script variable holding its modal.
const TARGETS := [
	{"node": "ConstructionMenu", "prop": "_modal"},
	{"node": "MarketPanel", "prop": "_panel"},
	{"node": "ProgressPanel", "prop": "_panel"},
	{"node": "TechTreePanel", "prop": "_panel"},
	{"node": "ArmyPanel", "prop": "_panel"},
	{"node": "ObjectivePanel", "prop": "_panel"},
	{"node": "SettingsPanel", "prop": "_panel"},
	{"node": "NotificationPanel", "prop": "_panel"},
	{"node": "BuildingInfoPanel", "prop": "_panel"},
]

func _ready() -> void:
	if not GameConfig.dev_mode:
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run_tour()

func _run_tour() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var main := get_tree().current_scene
	if main == null:
		push_warning("[ui_tour] no current scene")
		return

	await _shot("00_base")

	# Hide the helper callouts so they stop covering everything after the first shot.
	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper != null:
		helper.visible = false
		await _shot("01_base_sin_ayuda")

	var index := 2
	for target in TARGETS:
		var panel: Node = main.get_node_or_null(String(target["node"]))
		if panel == null:
			continue
		var modal: Variant = panel.get(String(target["prop"]))
		if modal == null or not (modal is CanvasItem):
			continue
		var was_visible: bool = modal.visible
		modal.visible = true
		await _shot("%02d_%s" % [index, String(target["node"])])
		modal.visible = was_visible
		index += 1

	print("[ui_tour] listo: %d capturas en %s" % [index, OUT_DIR])
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(STEP).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
