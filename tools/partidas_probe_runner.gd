extends Node
## Sonda de las partidas guardadas (docs/09). Arranca sin partidas (nace la 1),
## siembra otras tres (una con nombre de pais, una Supervivencia sellada) y
## captura:
##
##   title        el menu principal con "PARTIDAS 4/5"
##   list         la lista desde el menu principal
##   list_ask     la misma lista preguntando "¿Borrar para siempre?"
##   make_room    "Nueva partida" con las cinco ocupadas
##   game_menu    ☰ MENÚ con la entrada PARTIDAS
##
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone, --view=2d.
## Capturas en docs/media/dev/partidas/ (ignorada por git). Aparca partidas y
## ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const Slots := preload("res://scripts/services/SaveSlots.gd")
const BACKUP_PATH := "user://save_game.partidas_probe.bak"
const OUT_DIR := "res://docs/media/dev/partidas"

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
	GameConfig.saves_active_slot = 0
	GameConfig.dev_mode = false
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y]

	GameManager.title_dismissed = false
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	var now := Time.get_unix_time_from_system()
	_seed(2, now - 86400.0 * 2, 1, 1500.0, {"colony_name": "Valdoria"}, {})
	_seed(3, now - 86400.0 * 5, 3, 4 * 3600.0 + 720.0, {}, {"mode": "survival", "result": "defeat", "tier": "colonist"})
	_seed(4, now - 3600.0 * 3, 2, 2 * 3600.0, {"color": "crimson"}, {"mode": "campaign", "result": "", "tier": "governor"})
	var main := get_tree().current_scene
	var title: Node = main.get_node_or_null("TitleMenu")
	if title != null and not title.is_open():
		title.open_menu()
	title._refresh_buttons()
	await _frames(10)
	await _shot("title")
	title._on_saves()
	await _frames(10)
	await _shot("list")
	var panel: Node = _panel()
	panel._ask_delete(2)
	await _frames(6)
	await _shot("list_ask")
	panel.close()
	await _frames(4)

	_seed(5, now - 86400.0 * 9, 1, 300.0, {}, {})
	GameManager._auto_fresh = false
	GameManager.request_new_game()
	await _frames(10)
	await _shot("make_room")
	_panel().close()
	await _frames(4)

	title.close_menu()
	await _frames(20)
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")
	await _frames(10)
	# La guia rapida sale tras el prologo y taparia el menu.
	for n in get_tree().get_nodes_in_group("quick_guide"):
		n.queue_free()
	await _frames(10)
	var menu: Node = main.get_node_or_null("PauseMenu")
	menu.menu_button().pressed.emit()
	await _frames(10)
	await _shot("game_menu")
	menu.resume()
	_finish()

func _panel() -> Node:
	for child in GameManager.get_children():
		if child.get_script() == GameManager.SavesPanelScript and not child.is_queued_for_deletion():
			return child
	return null

func _seed(id: int, saved_at: float, era: int, played: float, rank: Dictionary, mode: Dictionary) -> void:
	var data := {
		"format": GameManager.SAVE_FORMAT,
		"saved_at": saved_at,
		"progression": {"current_era": era, "played_seconds": played},
		"rank": rank,
		"game_mode": mode if not mode.is_empty() else {"mode": "campaign", "result": "", "tier": "colonist"},
	}
	var f := FileAccess.open(Slots.path_of(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	Slots.record(id, Slots.summary_of(data, id))

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("partidas_probe: ", ProjectSettings.globalize_path(path), " ", img.get_size())

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
