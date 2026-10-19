extends "res://tools/revision_probe_runner.gd"
## Sonda de CONSTRUIR (feat/ui3-construir): la ventana a pantalla completa en
## cada pestana, con lo bloqueado, lo lleno y el detalle; el globo de una fila;
## y la guia de edificios de AYUDA. Colonia temprana y la grande de la sonda de
## arte. Capturas (ignoradas por git) en docs/media/dev/construir/.
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone, --view=2d.

const C_OUT := "res://docs/media/dev/construir"

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(C_OUT))
	SaveParking.park(BACKUP_PATH)
	_settings_snap = SettingsParking.park()
	GameConfig.dev_mode = false
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
	GameConfig.ui_device_profile = _arg("profile", "auto")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = false
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"

	GameManager.title_dismissed = true
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	_quiet()
	await _seconds(3.0)
	_quiet()
	var main := get_tree().current_scene
	var build: Node = main.get_node_or_null("ConstructionMenu")
	build.open()
	await _frames(15)
	await _shot("t_todos")
	build._select_building(load("res://data/buildings/barracks.tres"))
	await _frames(10)
	await _shot("t_cuartel_bloqueado")
	build._close()
	await _frames(5)

	# Colonia grande: rojos, candados, Al maximo.
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(4.0)
	_quiet()
	main = get_tree().current_scene
	ResourceManager.set_amounts({"gold": 160, "wood": 60, "steel": 10, "oil": 0})
	build = main.get_node_or_null("ConstructionMenu")
	build.open()
	await _frames(12)
	for cat in build.CATEGORIES:
		build._select_category(cat)
		await _frames(10)
		await _shot("g_%s" % cat)
	build._select_category("all")
	await _frames(5)
	# Uno lleno (Al maximo) elegido, y otro bloqueado.
	var full_id := ""
	for d in build._all_buildings:
		if build.HelpText.is_full(d.id):
			full_id = d.id
			break
	if full_id != "":
		build._select_building(build._data_by_id(full_id))
		await _frames(10)
		await _shot("g_lleno_%s" % full_id)
	for d in build._all_buildings:
		if build.lock_reason(d) != "":
			build._select_building(d)
			await _frames(10)
			await _shot("g_bloqueado_%s" % d.id)
			break
	# El globo de una fila (mantener pulsado).
	var card: Control = build.card_for("fuel_depot")
	if card == null:
		card = build.card_for("house")
	var tt: Node = InputService.touch_tooltip() if InputService.has_method("touch_tooltip") else InputService.get_node_or_null("TouchTooltip")
	if card != null and tt != null:
		tt.show_bubble(card.tooltip_text, card.get_global_rect().get_center())
		await _frames(6)
		await _shot("g_globo")
		if tt.has_method("hide_bubble"):
			tt.hide_bubble()
		elif tt.get("_bubble") != null:
			tt._bubble.visible = false
	build._close()
	await _frames(5)

	# Guia de edificios de AYUDA.
	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper:
		(helper as CanvasLayer).visible = true
		helper.open_building_guide()
		await _frames(15)
		await _shot("ayuda_guia")
	_finish()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [C_OUT, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("construir_probe: ", ProjectSettings.globalize_path(path))
