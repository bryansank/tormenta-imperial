extends Node
## Sonda del prologo, el tutorial guiado y las ayudas (docs/23-onboarding.md).
## Arranca una partida NUEVA con el menu principal delante y recorre lo que ve
## un jugador que empieza, sacando capturas:
##
##   title            menu principal: el prologo NO esta detras
##   prologue_first   primer folio (tras soltar el menu)
##   prologue_middle  folio 3, al que se llega deslizando el dedo (tactil) o con Siguiente
##   prologue_last    ultimo folio, con Atras activo y el tampon
##   guide_1..3       tres pasos del tutorial: CONSTRUIR, Aserradero, junto al bosque
##   callout          un globo con ✕ y la barra de tiempo (tras saltar el tutorial)
##   tip              una tarjeta de consejo
##   help_index       el indice de AYUDA
##
## Con ventana (headless no pinta). Argumentos tras `--`:
##   --shot-size=WxH   ventana (1280x800 tablet, 1280x720 PC)
##   --view=2d         la vista 2D (por defecto 3D)
##   --profile=tablet  perfil forzado (pc, tablet, phone)
##   --mode=builder    modo de la partida (campaign, builder, survival, sandbox)
##   --tag=nombre      sufijo de los archivos
##
## Capturas en docs/media/dev/onboarding/ (ignorada por git). Correla SIEMPRE
## con un override.cfg que de una carpeta de usuario propia. Aun asi aparca el
## guardado y los ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const BACKUP_PATH := "user://save_game.onboarding_probe.bak"
const OUT_DIR := "res://docs/media/dev/onboarding"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray
var _touch := false

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
	GameConfig.dev_mode = true
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	DeviceProfile.apply_all()
	_touch = DeviceProfile.input_style() == "touch"
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%dx%d_%s%s" % [_arg("view", "3d"), win.x, win.y, DeviceProfile.current(),
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("onboarding_probe: window=", win, " canvas=", get_tree().root.get_visible_rect().size,
		" profile=", DeviceProfile.current(), " input=", DeviceProfile.input_style())

	# Partida nueva de verdad: sin guardado, en el modo pedido, menu principal delante.
	GameMode.begin_run(GameMode.from_key(_arg("mode", "campaign")))
	GameManager.title_dismissed = false
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	var main := get_tree().current_scene
	var tut: Node = main.get_node("TutorialPanel")
	var title: Node = main.get_node_or_null("TitleMenu")
	var offline: Variant = GameManager.get("_offline_canvas")
	if offline != null and is_instance_valid(offline):
		(offline as Node).queue_free()
	await _frames(10)
	print("onboarding_probe: title open=", title != null and title.call("is_open"),
		" prologue open behind title=", tut.call("is_intro_open"),
		" pending=", TutorialManager.is_prologue_pending())
	await _shot("title")

	# Soltar el menu (lo que hace Continuar / elegir modo): sale el prologo.
	if title != null:
		title.call("close_menu")
	await _frames(20)
	var pro: Node = tut.call("prologue")
	print("onboarding_probe: prologue open after title=", pro.call("is_open"), " variant=", pro.call("variant"),
		" layer=", pro.get("layer"))
	await _frames(90)
	pro.call("_finish_typing")
	await _frames(5)
	await _shot("prologue_first")
	# Al folio 3: con el dedo, deslizando; con raton, Siguiente.
	for i in 2:
		if _touch:
			await _swipe(Vector2(900, 400), Vector2(500, 410))
		else:
			(pro.call("next_button") as Button).pressed.emit()
			await _frames(2)
			(pro.call("next_button") as Button).pressed.emit()
		await _frames(8)
	print("onboarding_probe: folio tras deslizar/siguiente=", pro.call("current_page"))
	await _frames(20)
	await _shot("prologue_middle")
	pro.call("go_to_page", int(pro.call("page_count")) - 1)
	await _frames(30)
	await _shot("prologue_last")
	# Atras funciona.
	(pro.call("back_button") as Button).pressed.emit()
	await _frames(4)
	print("onboarding_probe: tras Atras folio=", pro.call("current_page"))
	pro.call("close")
	await _frames(20)

	# ── Tutorial guiado ──
	print("onboarding_probe: guia=", TutorialManager.guide_state, " paso=", TutorialManager.current_step())
	await _frames(20)
	await _shot("guide_1")
	# Abrir CONSTRUIR: si no esta a la vista, primero el ☰ (como el jugador).
	var build: Control = HelpTargetsRef.control(get_tree(), "build_button")
	if build == null:
		var menu_btn: Control = HelpTargetsRef.control(get_tree(), "menu_button")
		if menu_btn is Button:
			await _tap_control(menu_btn)
			await _frames(10)
		build = HelpTargetsRef.control(get_tree(), "build_button")
	if build is Button:
		await _tap_control(build)
	await _frames(40)
	print("onboarding_probe: paso tras CONSTRUIR=", TutorialManager.current_step())
	await _shot("guide_2")
	var card: Control = HelpTargetsRef.control(get_tree(), "card:sawmill")
	print("onboarding_probe: tarjeta aserradero=", card != null)
	var sawmill: Resource = load("res://data/buildings/sawmill.tres")
	var cm: Node = main.get_node("ConstructionMenu")
	if cm.has_method("_select_building"):
		cm.call("_select_building", sawmill)
	await _frames(5)
	if cm.has_method("_on_build_pressed"):
		cm.call("_on_build_pressed")
	await _frames(30)
	print("onboarding_probe: paso colocando=", TutorialManager.current_step())
	await _shot("guide_3")
	EventBus.building_placement_cancelled.emit()
	await _frames(10)
	TutorialManager.skip_guide()
	await _frames(20)

	# ── Ayudas: un globo con ✕ y reloj ──
	# El jugador cierra la columna ☰ (la abrio para llegar a CONSTRUIR).
	var market: Node = main.get_node_or_null("MarketPanel")
	if market != null and bool(market.get("_sidebar_visible")):
		market.call("_toggle_sidebar")
	await _frames(5)
	var helper: Node = main.get_node("HelperPanel")
	helper.call("skip_gap")
	await _frames(40)
	print("onboarding_probe: ayuda en pantalla=", helper.call("current_help"), " visibles=", helper.call("visible_help_count"),
		" cola=", helper.call("queued_ids"))
	print("onboarding_probe: debug paused=", get_tree().paused, " placing=", helper.get("_placing"), " storm=", helper.get("_storm_silenced"),
		" window=", UIManager.is_any_window_open(), " helper_on=", GameConfig.ui_helper_visible, " gap=", helper.get("_gap"),
		" narrow=", UILayoutManager.is_narrow(), " colnarrow=", UILayoutManager.is_column_narrow(), " sidebar=", helper.get("_sidebar_visible"))
	await _shot("callout")
	# Una tarjeta de consejo, por delante de la cola.
	TutorialManager.offer_tip("overflow")
	var box: Control = helper.call("current_box")
	if box != null:
		box.call("finish", "close")
	helper.call("skip_gap")
	await _frames(40)
	print("onboarding_probe: consejo=", helper.call("current_help"), " visibles=", helper.call("visible_help_count"))
	await _shot("tip")
	var idx: Node = get_tree().get_first_node_in_group("help_index")
	if idx != null:
		idx.call("open")
	await _frames(20)
	await _shot("help_index")
	if idx != null:
		var c: Control = idx.get("_card")
		print("onboarding_probe: indice card=", c.get_global_rect(), " min=", c.get_combined_minimum_size())
	if idx != null:
		idx.call("close")
	# Reabrir una ayuda concreta desde el indice.
	TutorialManager.reopen_help("callout_resources")
	await _frames(30)
	print("onboarding_probe: reabierta=", helper.call("current_help"))
	await _shot("reopened")
	_finish()

const HelpTargetsRef := preload("res://scripts/ui/HelpTargets.gd")

## Un toque de verdad (o un clic) en el centro de un control.
func _tap_control(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	var screen: Vector2 = get_viewport().get_final_transform() * p
	if _touch:
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.position = screen
		down.pressed = true
		Input.parse_input_event(down)
		await _frames(3)
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.position = screen
		up.pressed = false
		Input.parse_input_event(up)
	else:
		var mv := InputEventMouseMotion.new()
		mv.position = screen
		Input.parse_input_event(mv)
		await _frames(2)
		for pressed in [true, false]:
			var b := InputEventMouseButton.new()
			b.button_index = MOUSE_BUTTON_LEFT
			b.position = screen
			b.pressed = pressed
			Input.parse_input_event(b)
			await _frames(2)
	await _frames(3)

## Un deslizamiento de dedo de `from` a `to` (lienzo logico).
func _swipe(from: Vector2, to: Vector2) -> void:
	var xf := get_viewport().get_final_transform()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = xf * from
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	for i in range(1, 6):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = xf * from.lerp(to, i / 5.0)
		Input.parse_input_event(d)
		await _frames(1)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = xf * to
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("onboarding_probe: ", ProjectSettings.globalize_path(path), " ", img.get_size())

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().paused = false
	get_tree().quit()
