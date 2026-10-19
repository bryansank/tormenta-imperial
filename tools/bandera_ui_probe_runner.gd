extends Node
## Sonda de las rejillas de piezas: PAIS Y BANDERA (ColonyIdentityPanel, sus
## pestanas Fondo / Emblema / Colores) y la tarjeta REGIMIENTO abierta dentro
## del Cuartel (ArmyPanel). Sin partida: un fondo liso y los paneles encima, con
## un rango a medias para que salgan piezas abiertas y cerradas.
##
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone,
## --rank=N (5 por defecto), --tag=texto (p. ej. antes / despues).
## Capturas en docs/media/dev/bandera/ (ignorada por git). Aparca ajustes.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const OUT_DIR := "res://docs/media/dev/bandera"

var _args: PackedStringArray
var _tag := ""
var _settings_snap: Dictionary

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
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_helper_visible = false
	GameConfig.ui_layout = {}
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d" % [_arg("tag", "shot"), DeviceProfile.current(), win.x, win.y]

	RankManager.reset()
	var rank := int(_arg("rank", "5"))
	if rank > 1:
		RankManager.add_xp(RankManager.xp_for_rank(rank))
	RankManager.set_colony("Monte Biela",
		{"pattern": "bands_h", "emblem": "gear", "colors": ["steel", "ivory", "crimson"]})

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = 0
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.46, 0.38)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	var editor: CanvasLayer = load("res://scripts/ui/ColonyIdentityPanel.gd").new()
	editor.auto_free = false
	add_child(editor)
	await _frames(2)
	editor.open("edit")
	await _frames(10)
	await _shot("patterns")
	await _scroll_end(editor, "PieceScroll")
	await _shot("patterns_end")
	editor.select_tab("emblems")
	await _frames(6)
	await _shot("emblems")
	editor.select_tab("colors")
	await _frames(6)
	await _shot("colors")
	await _scroll_end(editor, "PieceScroll")
	await _shot("colors_end")
	editor.cancel()
	editor.queue_free()
	await _frames(4)

	var army: CanvasLayer = load("res://scenes/ui/ArmyPanel.tscn").instantiate()
	add_child(army)
	await _frames(4)
	army.open()
	await _frames(6)
	var card: Node = army.find_child("RegimentCard", true, false)
	if card != null:
		card.toggle_editor()
		await _frames(6)
		var scroll := _scroll_of(card)
		if scroll != null:
			scroll.ensure_control_visible(card)
		await _frames(4)
		await _shot("regiment")
		if scroll != null:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _frames(4)
		await _shot("regiment_end")
	_finish()

func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	return p as ScrollContainer

func _scroll_end(host: Node, scroll_name: String) -> void:
	var s: ScrollContainer = host.find_child(scroll_name, true, false)
	await _frames(3)
	if s != null:
		s.scroll_vertical = int(s.get_v_scroll_bar().max_value)
	await _frames(3)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("bandera_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	get_tree().quit()
