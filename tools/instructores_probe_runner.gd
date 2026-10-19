extends Node
## Sonda de los instructores (docs/23 Â§9): la Capitana Remache y el Sargento
## Bombarda. La lanza tools/instructores_probe.gd. Capturas (ignoradas por git)
## en docs/media/dev/instructores/<vista>_<perfil>_<WxH>_<toma>.png:
##
##   caras            las 6 caras de los dos, a tamano de serie y pequeno
##   consejo_tormenta_escribiendo / consejo_tormenta    el Sargento (storm_incoming)
##   consejo_economia_escribiendo / consejo_economia    la Capitana (market)
##
## Las tomas "_escribiendo" se sacan a media frase: la tarjeta tiene que medir
## lo mismo que la entera (el texto escrito poco a poco no la hace saltar); la
## sonda imprime los dos tamanos. Argumentos tras `--`: --shot-size=WxH,
## --profile=pc|tablet|phone, --view=2d, --tag=nombre. Aparca guardado y
## ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const InstructorBust := preload("res://scripts/ui/InstructorBust.gd")
const BACKUP_PATH := "user://save_game.instructores_probe.bak"
const OUT_DIR := "res://docs/media/dev/instructores"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _arg(key: String, fallback: String = "") -> String:
	for a in _args:
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
		if a == "--" + key:
			return "true"
	return fallback

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	SaveParking.park(BACKUP_PATH)
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	GameConfig.ui_instructors_visible = true
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]

	# â”€â”€ Partida sembrada â”€â”€
	(load("res://tools/view2d_probe_runner.gd").new() as Node)._write_seeded_save()
	GameManager.title_dismissed = true
	get_tree().change_scene_to_file("res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn")
	await _frames(60)
	var main := get_tree().current_scene
	_quiet(main)
	await _seconds(1.0)
	_quiet(main)

	# â”€â”€ Las 6 caras de los dos â”€â”€
	var layer := CanvasLayer.new()
	layer.layer = 90
	main.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.12, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var vp := get_tree().root.get_visible_rect().size
	var base := InstructorBust.base_size_for(vp)
	var col_w := vp.x / 6.0
	var scale := minf(1.0, (col_w - 8.0) / base.x)
	var sz := base * scale
	var y := 12.0
	for who in InstructorBust.WHO:
		for i in InstructorBust.EXPRESSIONS.size():
			var b: Control = InstructorBust.new()
			layer.add_child(b)
			b.custom_minimum_size = Vector2.ZERO
			b.size = sz
			b.position = Vector2(col_w * i + (col_w - sz.x) * 0.5, y)
			b.call("show_as", who, InstructorBust.EXPRESSIONS[i], 1 if i % 2 == 0 else -1)
			var l := Label.new()
			l.text = InstructorBust.EXPRESSIONS[i]
			l.position = Vector2(col_w * i + 6.0, y + sz.y + 2.0)
			layer.add_child(l)
		y += sz.y + 30.0
	await _frames(5)
	await _shot("caras")
	layer.queue_free()
	await _frames(5)

	# â”€â”€ Consejos: el Sargento (Tormenta) y la Capitana (economia) â”€â”€
	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper:
		(helper as CanvasLayer).visible = true
		for pair in [["storm_incoming", "consejo_tormenta"], ["market", "consejo_economia"]]:
			helper.call("show_help", pair[0])
			await _frames(12)
			var box: Control = helper.call("current_box")
			var s1 := box.size if box else Vector2.ZERO
			await _shot(pair[1] + "_escribiendo")
			await _seconds(3.0)
			var s2 := box.size if box else Vector2.ZERO
			print("instructores_probe: ", pair[0], " en pantalla=", helper.call("current_help"),
				" tarjeta escribiendo=", s1, " entera=", s2, " salta=", not s1.is_equal_approx(s2))
			await _shot(pair[1])
			if box:
				box.call("finish", "probe")
			await _seconds(1.0)
	_finish()

func _quiet(main: Node) -> void:
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")
	for guide in get_tree().get_nodes_in_group("quick_guide"):
		if guide.has_method("is_open") and guide.is_open():
			guide.close()
	for panel_name in ["TutorialPanel", "TitleMenu"]:
		var p: Node = main.get_node_or_null(panel_name)
		if p and p is CanvasLayer:
			(p as CanvasLayer).visible = false
	if TutorialManager.has_method("finish_guide"):
		TutorialManager.finish_guide()
	get_tree().paused = false

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("instructores_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
