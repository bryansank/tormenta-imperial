extends "res://tools/revision_probe_runner.gd"
## Sonda de la 1.2 (integracion/v1.2b): las pantallas nuevas con ventana, en la
## colonia grande de la sonda de arte. CONSTRUIR con los edificios nuevos, la
## tarjeta de una amenaza de costa, ATAQUES RAPIDOS con amenazas y pecio, el
## barco del contrabandista, y el final con eleccion (victoria, la mesa del
## libro, QUEMAR, FIRMAR, el archipielago y la pestana IMPERIO). Capturas
## (ignoradas por git) en docs/media/dev/v12/<vista>_<perfil>_<WxH>_<toma>.png.
## Argumentos tras `--`: --shot-size=WxH, --profile=pc|tablet|phone, --view=2d.

const V12_OUT := "res://docs/media/dev/v12"
const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")

func _run() -> void:
	_args = OS.get_cmdline_user_args()
	var shot := _arg("shot-size")
	if shot != "":
		var wh := shot.split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await _frames(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(V12_OUT))
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
	GameConfig.ui_touch_controls = "auto"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y]
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"

	# ── Colonia grande ──────────────────────────────────────────────────
	GameManager.title_dismissed = true
	var seeder: Node = ArteRunner.new()
	seeder._write_seeded_save()
	_add_military_lots(String(seeder.SAVE_PATH))
	seeder.free()
	GameManager.clear_save_and_reload_from(SaveSlotsRef.read(GameManager.active_slot()), scene)
	await _frames(60)
	_quiet()
	await _seconds(4.0)
	_quiet()
	var main := get_tree().current_scene
	TutorialManager.first_sortie_done = true
	ArmyManager._units = {"infantry": 6, "artillery": 3, "vehicle": 1}
	EventBus.army_changed.emit()
	ResourceManager.set_amounts({"gold": 2400, "wood": 900, "steel": 300, "oil": 120})

	# CONSTRUIR: los edificios de la 1.2 (Casa de cambio con su candado de rango).
	var build: Node = main.get_node_or_null("ConstructionMenu")
	if build:
		build._open()
		await _frames(12)
		build._select_building(load("res://data/buildings/exchange.tres"))
		await _frames(10)
		await _shot("construir_casa_de_cambio")
		build._select_building(load("res://data/buildings/bastion.tres"))
		await _frames(10)
		await _shot("construir_bastion")
		build._close()
		await _frames(5)

	# Amenazas de costa: dos marcas (avanzadilla en la playa y un pecio).
	var spots: Dictionary = ThreatManager.free_spots()
	var land: Array = spots.get("land", [])
	var threats: Array = []
	if land.size() > 2:
		var a: Vector2i = land[0]
		var b: Vector2i = land[land.size() / 2]
		threats.append({"id": 1, "type": "vanguard", "x": a.x, "y": a.y, "water": false, "seed": 5, "era": 3,
			"born": 0.0, "ends": 99999.0, "state": "idle", "explore_ends": 0.0, "seen": false})
		threats.append({"id": 2, "type": "wreck", "x": b.x, "y": b.y, "water": false, "seed": 6, "era": 3,
			"born": 0.0, "ends": 99999.0, "state": "idle", "explore_ends": 0.0, "seen": false})
	ThreatManager.load_save_data({"threats": threats, "next_spawn_at": 99999.0, "next_id": 3})
	await _frames(10)
	EventBus.threat_clicked.emit(1)
	await _frames(15)
	await _shot("amenaza_tarjeta")
	var card := main.find_child("ThreatCard", true, false)
	if card and card.has_method("close"):
		card.close()
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	if skirmish:
		skirmish.open_threat(1)
		await _frames(15)
		await _shot("misiones_amenazas")
		skirmish._close()
		await _frames(5)

	# El barco del contrabandista, atracado con sus tres ofertas.
	var offers := [
		{"kind": "parts", "give": {"parts": 3}, "price": 180, "sold": false},
		{"kind": "material", "give": {"beams": 6}, "price": 312, "sold": false},
		{"kind": "buy", "ask": {"wood": 60}, "pay": 230, "sold": false},
	]
	EconomyManager.load_save_data({"ship": {"wait_left": 300.0, "docked_left": 80.0, "offers": offers, "visits": 1}})
	var smuggler = load("res://scripts/ui/SmugglerPanel.gd").open_in(get_tree())
	await _frames(15)
	await _shot("barco_contrabandista")
	if smuggler:
		smuggler.close()
	await _frames(5)

	# ── Final con eleccion ──────────────────────────────────────────────
	EmpireManager.reset()
	var audit = FinalAuditScript.create(5, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit
	var victory: Node = main.get_node_or_null("VictoryScreen")
	if victory:
		victory._on_victory_achieved({"time_played": 11100.0, "buildings_built": 64, "trades_completed": 12,
			"milestones": 9, "storms_survived": 11, "tithes_repelled": 9, "audit_summons": 1, "mode": "campaign"})
		await _frames(20)
		await _shot("final_1_victoria")
		victory.show_choice()
		await _frames(20)
		await _shot("final_2_el_libro")
		victory.choose("burn")
		await _frames(20)
		await _shot("final_3_quemar")
		victory.dismiss()
		await _frames(5)
		# Y la otra rama: firmar.
		EmpireManager.reset()
		victory.show_choice()
		await _frames(10)
		victory.choose("sign")
		await _frames(20)
		await _shot("final_4_firmar")
		victory.open_archipelago()
		await _frames(25)
		await _shot("final_5_archipielago")
		var arch := main.get_node_or_null("ArchipelagoPanel")
		if arch and arch.has_method("close"):
			arch.close()
		await _frames(5)
	if skirmish:
		skirmish.open_conquest("gulls")
		await _frames(15)
		await _shot("final_6_misiones_imperio")
		skirmish._close()
	_finish()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [V12_OUT, _tag, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("v12_probe: ", ProjectSettings.globalize_path(path))
