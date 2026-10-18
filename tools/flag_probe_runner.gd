extends Node
## Sonda de la bandera y el nombre del pais. Arranca una partida NUEVA en la
## vista pedida, pone junto al Nucleo un Cuartel General (sin bandera) y dos
## Cuarteles (con ella): uno derecho y otro girado 90 grados entre vecinos
## (Casa, Aserradero, Almacen), y captura:
##
##   hud              la insignia con el nombre
##   map              los mastiles del Nucleo y de los Cuarteles; el CG sin mastil
##   barracks         de cerca, los dos Cuarteles (derecho y girado con vecinos)
##   card             la tarjeta COLONIA de ☰ MENU
##   editor_patterns / editor_emblems / editor_colors   el editor (ColonyIdentityPanel)
##   editor_new       el paso de Nueva partida (rango 1, con "Saltar")
##   map_rank18       los mastiles con una bandera de rango 18
##   report           un parte del Diezmo firmado por el pais
##   gallery.png      todas las piezas en una lamina (imagen generada)
##
## Argumentos tras `--`: --shot-size=WxH, --view=2d, --profile=pc|tablet|phone.
## Capturas en docs/media/dev/flag/ (ignorada por git). Aparca guardado y ajustes.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const BACKUP_PATH := "user://save_game.flag_probe.bak"
const OUT_DIR := "res://docs/media/dev/flag"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray
var _barracks_cell := Vector2i.ZERO

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
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_game.json"))
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_helper_visible = false  # sin globos de ayuda tapando el mapa
	GameConfig.ui_layout = {}
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y]
	_gallery()

	GameManager.title_dismissed = false
	var view2d := _arg("view") == "2d"
	get_tree().change_scene_to_file("res://scenes/main/Main2D.tscn" if view2d else "res://scenes/main/Main.tscn")
	await _frames(60)
	var main := get_tree().current_scene
	var title: Node = main.get_node_or_null("TitleMenu")
	if title != null and title.is_open():
		title.close_menu()
	await _frames(20)
	_close_intro(main)
	await _frames(10)
	RankManager.set_colony("República de Puerto Hierro",
		{"pattern": "bands_h", "emblem": "anchor", "colors": ["steel", "ivory", "crimson"]})

	# El Cuartel General al lado del Nucleo, ya terminado.
	var placer: Node = main.get_node("BuildingPlacer")
	var hq: BuildingData = load("res://data/buildings/headquarters.tres")
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var hq_cell := center + Vector2i(3, -4)
	var hq_node: Node = placer.place_building_at(hq, hq_cell)
	print("flag_probe: hq=", hq_node)
	# Dos Cuarteles: uno derecho y otro girado 90 grados entre vecinos, en un
	# hueco libre de 6x6 (el mapa sale distinto cada partida).
	var bar: BuildingData = load("res://data/buildings/barracks.tres")
	var spot := _free_block(center, Vector2i(6, 6), [hq_cell])
	var b1: Node = placer.place_building_at(bar, _free_block(center, Vector2i(2, 2), [hq_cell, spot]))
	var b2: Node = placer.place_building_at(bar, spot + Vector2i(2, 2), 1)
	for n in [["house", Vector2i(0, 2)], ["sawmill", Vector2i(4, 2)],
			["warehouse", Vector2i(2, 4)], ["house", Vector2i(2, 0)]]:
		placer.place_building_at(load("res://data/buildings/%s.tres" % n[0]), spot + n[1])
	_barracks_cell = spot + Vector2i(3, 3)
	print("flag_probe: barracks=", b1, " ", b2, " spot=", spot)
	await _frames(20)
	await _shot("hud")
	_focus(main, center + Vector2i(0, -1), view2d)
	await _frames(40)
	await _shot("map")
	_focus(main, _barracks_cell, view2d, 18.0)
	await _frames(40)
	await _shot("barracks")
	_focus(main, _barracks_cell, view2d, 18.0, 135.0)
	await _frames(40)
	await _shot("barracks_yaw")
	_focus(main, center + Vector2i(3, -2), view2d)
	await _frames(20)

	var panel: Node = main.get_node("RankPanel")
	panel.open()
	await _frames(10)
	await _shot("card")
	panel.open_editor()
	await _frames(10)
	var editor: Node = panel.editor()
	await _shot("editor_patterns")
	editor.select_tab("emblems")
	await _frames(6)
	await _shot("editor_emblems")
	editor.select_tab("colors")
	await _frames(6)
	await _shot("editor_colors")
	editor.cancel()
	panel._close()
	await _frames(6)

	var fresh: CanvasLayer = load("res://scripts/ui/ColonyIdentityPanel.gd").new()
	main.add_child(fresh)
	fresh.open("new")
	await _frames(10)
	await _shot("editor_new")
	fresh.cancel()
	await _frames(6)

	RankManager.add_xp(RankManager.xp_for_rank(18))
	RankManager.set_colony("Liga de Vaporia",
		{"pattern": "checks", "emblem": "airship", "colors": ["crimson", "gold", "ivory"]})
	_focus(main, center + Vector2i(3, -2), view2d)
	await _frames(30)
	await _shot("map_rank18")

	EventBus.tithe_resolved.emit(true, {})
	await _frames(20)
	await _shot("report")
	_finish()

## El hueco libre de `size` mas cercano a `center` (busca en anillos) que no
## pise ninguna de las esquinas de `avoid` (2 celdas de margen alrededor).
func _free_block(center: Vector2i, size: Vector2i, avoid: Array) -> Vector2i:
	for r in range(3, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := center + Vector2i(dx, dy)
				var clash := false
				for a in avoid:
					if Rect2i(c - Vector2i(2, 2), size + Vector2i(4, 4)).intersects(Rect2i(a, Vector2i(6, 6))):
						clash = true
				if not clash and GridManager.can_place(c, size):
					return c
	return center + Vector2i(-6, 3)

## yaw en grados (como MonumentalCamera).
func _focus(main: Node, cell: Vector2i, view2d: bool, distance: float = 34.0, yaw: float = 0.0) -> void:
	var world := GridManager.cell_to_world(cell)
	# Las dos camaras guardan el estado en el mismo formato (mundo x/z, yaw, distancia).
	var cam3: Node = main.get_node_or_null("Camera2D" if view2d else "MonumentalCamera")
	if cam3 != null:
		cam3.set_state({"target_x": world.x, "target_y": world.z, "yaw": yaw, "distance": distance})

## Todas las piezas en una lamina: cada fondo, cada emblema y unas al azar.
func _gallery() -> void:
	var cols := 7
	var cw := ColonyFlag.W + 8
	var ch := ColonyFlag.H + 8
	var items: Array = []
	for p in GameConfig.COLONY_PATTERNS:
		items.append({"pattern": p, "emblem": "none", "colors": ["steel", "ivory", "soot"]})
	for e in GameConfig.COLONY_EMBLEMS:
		items.append({"pattern": "plain", "emblem": e, "colors": ["crimson", "ivory", "gold"]})
	for s in 15:
		items.append(ColonyIdentity.random_spec(s * 31 + 7, 18))
	var rows := ceili(float(items.size()) / cols)
	var sheet := Image.create(cols * cw, rows * ch, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.11, 0.1))
	for i in items.size():
		var img := ColonyFlag.make_image(items[i])
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cw + 4, (i / cols) * ch + 4))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(ProjectSettings.globalize_path("%s/gallery.png" % OUT_DIR))

func _close_intro(main: Node) -> void:
	var tut: Node = main.get_node_or_null("TutorialPanel")
	if tut and tut.has_method("is_intro_open") and tut.call("is_intro_open"):
		tut.call("_close")
	for g in get_tree().get_nodes_in_group("quick_guide"):
		if g.has_method("close"):
			g.call("close")
	# Sin la tarjeta del tutorial guiado, que tapa el centro del mapa
	# (skip_guide solo vale en dev_mode).
	var dev := GameConfig.dev_mode
	GameConfig.dev_mode = true
	TutorialManager.skip_guide()
	GameConfig.dev_mode = dev

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("flag_probe: ", ProjectSettings.globalize_path(path))

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().quit()
