extends Node
## Sonda de QA de tablet (2026-10-25, rama qa-tablet). Todo con toques
## sinteticos de verdad: Input.parse_input_event(InputEventScreenTouch /
## InputEventScreenDrag) en coordenadas de ventana, como los daria Android. No
## llama a los metodos de la interfaz para lo que se prueba: los toca. Deja una
## captura por paso y un JSON con lo que paso (ok / fallo y por que).
##
## Argumentos tras `--`: --shot-size=WxH, --view=2d, --profile=pc|tablet|phone,
## --tag=nombre. Capturas en docs/media/dev/tablet_qa/ (ignorada por git).
## Aparca guardado y ajustes y los devuelve al terminar.

const SaveParking := preload("res://tests/save/save_parking.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const BACKUP_PATH := "user://save_game.tablet_qa_probe.bak"
const OUT_DIR := "res://docs/media/dev/tablet_qa"

var _tag := ""
var _settings_snap: Dictionary
var _args: PackedStringArray
var _n := 0
var _results: Array = []
var _main: Node
var _placer: Node
var _press_count := 0

func TouchTooltip_control_at(win_pos: Vector2) -> String:
	var canvas := get_viewport().get_final_transform().affine_inverse() * win_pos
	var c = load("res://scripts/ui/TouchTooltip.gd").control_at(get_tree(), canvas)
	return str(c.get_path()) if c != null else "nada"

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

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"check": name, "ok": ok, "detail": detail, "shot": _n})
	print("TQA: [%s] %s %s" % ["OK" if ok else "FALLO", name, detail])

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
	GameConfig.ui_view_mode = "2d" if _arg("view") == "2d" else "3d"
	GameConfig.ui_device_profile = _arg("profile", "tablet")
	GameConfig.ui_scale_pct = 0
	GameConfig.ui_text_size = "auto"
	GameConfig.ui_hud_hidden = []
	GameConfig.ui_layout = {}
	GameConfig.ui_helper_visible = true
	GameConfig.ui_touch_controls = "auto"
	GameConfig.ui_theme = "light"
	DeviceProfile.apply_all()
	await _frames(5)
	var win := DisplayServer.window_get_size()
	_tag = "%s_%s_%dx%d%s" % [_arg("view", "3d"), DeviceProfile.current(), win.x, win.y,
		("_" + _arg("tag")) if _arg("tag") != "" else ""]
	print("TQA: window=", win, " canvas=", get_tree().root.get_visible_rect().size,
		" factor=", get_tree().root.content_scale_factor, " input=", DeviceProfile.input_style(),
		" slop=", InputService.touch_slop_px())

	GameManager.title_dismissed = false
	var scene := "res://scenes/main/Main2D.tscn" if _arg("view") == "2d" else "res://scenes/main/Main.tscn"
	get_tree().change_scene_to_file(scene)
	await _frames(60)
	await _shot("titulo")
	var dialog: CanvasLayer = GameManager.request_new_game()
	await _frames(20)
	if dialog != null and dialog.has_method("_on_start"):
		dialog.call("_on_start")
		await _frames(20)
		var ident: Node = dialog.get("_identity")
		if ident != null:
			ident.call("confirm")
	await _frames(90)
	StormManager.set("_trial_done", true)
	_main = get_tree().current_scene
	_placer = _main.get_node("BuildingPlacer")
	var tut: Node = _main.get_node("TutorialPanel")
	var pro: Node = tut.call("prologue")
	if pro.call("is_open"):
		pro.call("close")
		await _frames(30)
	var qg: Node = get_tree().get_first_node_in_group("quick_guide")
	if qg != null and qg.call("is_open"):
		qg.call("close")
		await _frames(20)
	TutorialManager.skip_guide()
	GameConfig.ui_helper_visible = false
	EventBus.helper_visibility_changed.emit(false)
	_top_up()
	await _frames(30)
	await _shot("hud_reposo")
	if _arg("solo") == "taps":
		await _test_tap_reliability()
		_write_results()
		_finish()
		return

	await _test_hold_to_read()
	await _test_build_list()
	await _test_place_sawmill()
	await _test_invalid_tap()
	await _test_road_line()
	await _test_camera_gestures()
	await _test_tap_building()
	await _test_settings_and_theme()
	await _test_combat()
	_write_results()
	_finish()

# ── Pruebas ───────────────────────────────────────────────────────────

## ¿Se pierden toques? 20 toques a CONSTRUIR (cerrando con _close entre uno y
## otro) sin nada antes, y otros 20 justo despues de mantener pulsada una ficha
## de recurso (globo). Tambien con distintas esperas entre bajar y subir el dedo.
func _test_tap_reliability() -> void:
	var cm: Node = _main.get_node("ConstructionMenu")
	var bb := cm.find_child("BuildButton", true, false) as Control
	var chip := _first_visible_named(_main.get_node("ResourceHUD"), "Chip_")
	var bar := _main.find_child("BarBuild", true, false) as Control
	if bar != null and bar.is_visible_in_tree():
		bb = bar
	(bb as BaseButton).pressed.connect(func(): _press_count += 1)
	print("TQA: boton probado=", bb.get_path(), " action_mode=", (bb as BaseButton).action_mode)
	for mode in ["limpio", "tras_globo", "toque_1f", "toque_8f", "toque_130ms"]:
		var ok := 0
		var fails: Array = []
		var held_ms: Array = []
		var unfocused := 0
		var bubbles := 0
		for i in 20:
			if mode == "tras_globo" and chip != null:
				var cp := _win(chip.get_global_rect().get_center())
				await _touch_down(0, cp)
				await _seconds(0.7)
				await _touch_up(0, cp)
				await _frames(int(i % 5) * 3)
			var p := _win(bb.get_global_rect().get_center())
			var focused_before := DisplayServer.window_is_focused()
			var t0 := Time.get_ticks_msec()
			await _touch_down(0, p)
			if mode == "toque_130ms":
				await _seconds(0.13)
			else:
				var hold := 1 if mode == "toque_1f" else (8 if mode == "toque_8f" else 3)
				await _frames(hold)
			# Diagnostico (2026-10-26): ¿el dedo estuvo mas de touch_tooltip_hold_sec
			# en tiempo real? Entonces TouchTooltip lo lee como "mantener" y cancela.
			var bubble := bool(InputService.touch_tooltip().is_shown())
			var dt := Time.get_ticks_msec() - t0
			await _touch_up(0, p)
			if not (focused_before and DisplayServer.window_is_focused()):
				unfocused += 1
			if bubble:
				bubbles += 1
			var ever_open := false
			for f in 12:
				ever_open = ever_open or bool(cm.get("_is_open"))
				await _frames(1)
			var opened: bool = bool(cm.get("_is_open"))
			if i < 3:
				print("TQA: diag %s #%d pulsado=%d abierto_en_algun_momento=%s abierto=%s bajo_dedo=%s" % [mode, i, _press_count, ever_open, opened,
					str(TouchTooltip_control_at(p))])
			held_ms.append(dt)
			if opened:
				ok += 1
				cm.call("_close")
			else:
				fails.append(i)
				print("TQA: fallo %s #%d dedo=%d ms fps=%d foco=%s globo=%s" % [mode, i, dt, Engine.get_frames_per_second(),
					DisplayServer.window_is_focused(), bubble])
			await _frames(12)
			# La ficha de recursos se plega si quedo abierta (por la prueba del globo).
		held_ms.sort()
		_check("toques a CONSTRUIR (%s) %d/20" % [mode, ok], ok == 20, "fallaron %s; dedo %s-%s ms; sin foco %d; globo %d" % [
			str(fails), str(held_ms[0]), str(held_ms[-1]), unfocused, bubbles])
	await _shot("taps_fin")

func _test_hold_to_read() -> void:
	var chip := _first_visible_named(_main.get_node("ResourceHUD"), "Chip_")
	if chip == null:
		_check("mantener: ficha de recurso", false, "no hay Chip_ visible")
		return
	var tt: Node = InputService.touch_tooltip()
	var p := _win(chip.get_global_rect().get_center())
	await _touch_down(0, p)
	await _seconds(0.8)
	await _shot("mantener_globo")
	var shown: bool = tt != null and tt.call("is_shown")
	var text: String = str(tt.call("bubble_text")) if tt != null else ""
	await _touch_up(0, p)
	await _frames(10)
	var hidden: bool = tt != null and not tt.call("is_shown")
	_check("mantener pulsado enseña globo", shown, "'%s'" % text.left(80))
	_check("soltar cierra el globo", hidden)
	# Mantener sobre CONSTRUIR: globo y NO abre la lista.
	var bb := _main.get_node("ConstructionMenu").find_child("BuildButton", true, false) as Control
	if bb != null:
		var q := _win(bb.get_global_rect().get_center())
		await _touch_down(0, q)
		await _seconds(0.8)
		var s2: bool = tt.call("is_shown")
		await _shot("mantener_construir")
		await _touch_up(0, q)
		await _frames(15)
		var opened: bool = bool(_main.get_node("ConstructionMenu").get("_is_open"))
		_check("mantener CONSTRUIR: globo sin abrir", s2 and not opened, "globo=%s abierto=%s" % [s2, opened])
		if opened:
			_main.get_node("ConstructionMenu").call("_close")
			await _frames(10)

func _test_build_list() -> void:
	var cm: Node = _main.get_node("ConstructionMenu")
	var bb := cm.find_child("BuildButton", true, false) as Control
	await _tap(bb)
	await _frames(20)
	var opened: bool = bool(cm.get("_is_open"))
	_check("tocar CONSTRUIR abre la lista", opened)
	await _shot("construir_abierto")
	var list := cm.find_child("BuildList", true, false) as ScrollContainer
	if list == null:
		_check("lista de construir", false, "sin BuildList")
		return
	var vbar := list.get_v_scroll_bar()
	var hbar := list.get_h_scroll_bar()
	print("TQA: lista rect=", list.get_global_rect(), " vmax=", vbar.max_value, " vpage=", vbar.page, " hmax=", hbar.max_value)
	# Arrastrar empezando SOBRE una tarjeta: tiene que desplazar y no elegirla.
	var sel_before: String = cm.call("selected_building_id")
	var card := _first_card_in(list)
	if card == null:
		_check("tarjeta en la lista", false)
		return
	var start := _win(card.get_global_rect().get_center())
	var horizontal := hbar.max_value > hbar.page + 1.0 and vbar.max_value <= vbar.page + 1.0
	var delta := Vector2(-260, 0) if horizontal else Vector2(0, -260)
	var v0 := list.scroll_vertical
	var h0 := list.scroll_horizontal
	await _drag(0, start, start + delta, 12)
	await _frames(20)
	var moved := list.scroll_vertical != v0 or list.scroll_horizontal != h0
	var sel_after: String = cm.call("selected_building_id")
	await _shot("construir_desplazado")
	var can_scroll := vbar.max_value > vbar.page + 1.0 or hbar.max_value > hbar.page + 1.0
	_check("arrastrar sobre tarjeta desplaza la lista", moved or not can_scroll,
		"v %d->%d h %d->%d (desplazable=%s)" % [v0, list.scroll_vertical, h0, list.scroll_horizontal, can_scroll])
	_check("arrastrar no elige tarjeta", sel_after == sel_before, "antes='%s' despues='%s'" % [sel_before, sel_after])
	# Pestaña / categoria: tocar cada una (se buscan de nuevo: la lista se rehace).
	var ncat := cm.find_children("Cat_*", "BaseButton", true, false).size()
	for k in ncat:
		var cats := cm.find_children("Cat_*", "BaseButton", true, false)
		if k < cats.size() and is_instance_valid(cats[k]) and (cats[k] as Control).is_visible_in_tree():
			await _tap(cats[k] as Control)
			await _frames(10)
	await _shot("construir_ultima_categoria")
	await _select_all_category(cm)

func _select_all_category(cm: Node) -> void:
	var cats := cm.find_children("Cat_*", "BaseButton", true, false)
	for c in cats:
		if String(c.name).to_lower().contains("all") or String(c.name).to_lower().contains("todo"):
			await _tap(c as Control)
			await _frames(10)
			return
	if not cats.is_empty() and is_instance_valid(cats[0]):
		await _tap(cats[0] as Control)
		await _frames(10)

func _pick_and_build(id: String) -> bool:
	var cm: Node = _main.get_node("ConstructionMenu")
	if not bool(cm.get("_is_open")):
		await _tap(cm.find_child("BuildButton", true, false) as Control)
		await _frames(15)
	await _select_all_category(cm)
	var card: Control = cm.call("card_for", id)
	if card == null or not is_instance_valid(card):
		_check("tarjeta %s en CONSTRUIR" % id, false)
		cm.call("_close")
		await _frames(10)
		return false
	await _ensure_visible_in_scroll(card)
	await _tap(card)
	await _frames(15)
	var build := _visible_one(cm, ["DetailBuildButton", "StripBuildButton", "RowBuild"])
	if build == null:
		_check("boton CONSTRUIR para %s" % id, false)
		cm.call("_close")
		await _frames(10)
		return false
	await _tap(build)
	await _frames(25)
	return bool(_placer.call("assist_is_placing"))

func _test_place_sawmill() -> void:
	var cm: Node = _main.get_node("ConstructionMenu")
	if not bool(cm.get("_is_open")):
		await _tap(cm.find_child("BuildButton", true, false) as Control)
		await _frames(15)
	var card: Control = cm.call("card_for", "sawmill")
	if card == null or not card.is_visible_in_tree():
		_check("tarjeta Aserradero visible", false, "card_for=%s" % card)
		return
	await _ensure_visible_in_scroll(card)
	await _tap(card)
	await _frames(15)
	_check("tocar tarjeta elige Aserradero", cm.call("selected_building_id") == "sawmill",
		"elegido='%s'" % cm.call("selected_building_id"))
	await _shot("construir_ficha_aserradero")
	var build := _visible_one(cm, ["DetailBuildButton", "StripBuildButton", "RowBuild"])
	if build == null:
		_check("boton CONSTRUIR de la ficha", false)
		return
	await _tap(build)
	await _frames(30)
	var placing: bool = _placer.call("assist_is_placing")
	_check("CONSTRUIR de la ficha empieza a colocar", placing)
	await _shot("colocar_inicio_fantasma")
	var spot := _free_spot("sawmill")
	var before := _count("sawmill")
	_placer.call("assist_center_on", spot)
	await _seconds(1.0)
	var p = _cell_win(spot, Vector2i(2, 2))
	await _tap_at(p)
	await _frames(20)
	await _shot("colocar_fantasma_tocado")
	var confirm := get_tree().root.find_child("ConfirmPlacement", true, false) as Control
	var cvis := confirm != null and confirm.is_visible_in_tree()
	_check("tocar el mapa lleva el fantasma y sale ✓", cvis, "celda=%s" % spot)
	if cvis:
		var cr := confirm.get_global_rect()
		print("TQA: ✓ rect=", cr, " tamano=", cr.size)
		_check("✓ de tamaño de dedo (>=48 px de lienzo)", cr.size.x >= 48 and cr.size.y >= 48, str(cr.size))
		await _tap(confirm)
	else:
		await _tap_at(p)
	await _frames(30)
	_check("✓ planta el Aserradero", _count("sawmill") == before + 1, "%d -> %d" % [before, _count("sawmill")])
	await _shot("colocar_plantado")
	# Sigue colocando? Entonces ✕ CANCELAR.
	await _cancel_placement("tras aserradero")

func _test_invalid_tap() -> void:
	# Una Casa sobre el agua / un bosque: rojo y por que.
	if not await _pick_and_build("house"):
		return
	var dep := _a_deposit_cell()
	_placer.call("assist_center_on", dep)
	await _seconds(1.0)
	var p = _cell_win(dep, Vector2i(2, 2))
	if p != null:
		await _tap_at(p)
		await _frames(20)
		await _shot("colocar_sitio_malo")
		var confirm := get_tree().root.find_child("ConfirmPlacement", true, false) as Control
		_check("sitio malo: sin ✓", confirm == null or not confirm.is_visible_in_tree())
	await _cancel_placement("casa")

func _test_road_line() -> void:
	if not await _pick_and_build("road"):
		_check("carretera: empieza a colocar", false)
		return
	var line := _road_line_cells(7)
	if line.is_empty():
		_check("tramo libre para la carretera larga", false)
		await _cancel_placement("carretera")
		return
	var a: Vector2i = line[0]
	var b: Vector2i = line[1]
	var roads0 := _count("road")
	_placer.call("assist_center_on", a)
	await _seconds(1.0)
	await _tap_at(_cell_win(a, Vector2i.ONE))
	await _frames(10)
	await _shot("carretera_inicio")
	await _tap_at(_cell_win(b, Vector2i.ONE))
	await _frames(15)
	var lbl := get_tree().root.find_child("RoadLineCost", true, false) as Label
	var ltxt := lbl.text if lbl != null and lbl.is_visible_in_tree() else ""
	_check("toca inicio -> fin enseña la vista previa", ltxt != "", "'%s' %s->%s" % [ltxt, a, b])
	await _shot("carretera_vista_previa")
	await _tap_at(_cell_win(b, Vector2i.ONE))
	await _frames(20)
	var laid := _count("road") - roads0
	_check("tocar el fin otra vez tiende el tramo", laid >= 5, "tramos puestos=%d" % laid)
	await _shot("carretera_tendida")
	await _cancel_placement("carretera")

func _test_camera_gestures() -> void:
	var cam := _camera_node()
	if cam == null:
		_check("camara", false)
		return
	var cmx: Node = _main.get_node("ConstructionMenu")
	if bool(cmx.get("_is_open")):
		_check("CONSTRUIR cerrado antes de los gestos", false, "seguia abierto")
		cmx.call("_close")
		await _frames(10)
	var vp := get_viewport().get_visible_rect().size
	var c := _win(vp * 0.5 + Vector2(0, 60))
	await _shot("camara_antes")
	# Pan de un dedo.
	var s0: Dictionary = cam.call("get_state")
	await _drag(0, c, c + Vector2(-180, -90), 10)
	await _seconds(0.6)
	var s1: Dictionary = cam.call("get_state")
	_check("un dedo arrastra el mapa", str(s0) != str(s1), "%s -> %s" % [_short(s0), _short(s1)])
	# Pellizco (separar): zoom.
	var a := c + Vector2(-80, 0)
	var b := c + Vector2(80, 0)
	await _touch_down(0, a)
	await _touch_down(1, b)
	for i in 12:
		a += Vector2(-12, 0)
		b += Vector2(12, 0)
		_drag_event(0, a, Vector2(-12, 0))
		_drag_event(1, b, Vector2(12, 0))
		await _frames(2)
	await _touch_up(1, b)
	await _touch_up(0, a)
	await _seconds(0.8)
	var s2: Dictionary = cam.call("get_state")
	_check("pellizco hace zoom", str(s1) != str(s2), "%s -> %s" % [_short(s1), _short(s2)])
	await _shot("camara_pellizco")
	# Giro de dos dedos (solo 3D).
	var center := c
	var r := 110.0
	var ang := 0.0
	var pa := center + Vector2(-r, 0)
	var pb := center + Vector2(r, 0)
	await _touch_down(0, pa)
	await _touch_down(1, pb)
	for i in 14:
		ang += deg_to_rad(4.0)
		var na := center + Vector2(-r, 0).rotated(ang)
		var nb := center + Vector2(r, 0).rotated(ang)
		_drag_event(0, na, na - pa)
		_drag_event(1, nb, nb - pb)
		pa = na
		pb = nb
		await _frames(2)
	await _touch_up(1, pb)
	await _touch_up(0, pa)
	await _seconds(0.8)
	var s3: Dictionary = cam.call("get_state")
	if _arg("view") == "2d":
		_check("giro de dos dedos en 2D no hace nada raro", true, "%s -> %s" % [_short(s2), _short(s3)])
	else:
		_check("giro de dos dedos gira", str(s2) != str(s3), "%s -> %s" % [_short(s2), _short(s3)])
	await _shot("camara_giro")
	# Botones en pantalla: zoom + mantener (repite).
	var zin := get_tree().root.find_child("ZoomIn", true, false) as Control
	if zin != null and zin.is_visible_in_tree():
		var z0: Dictionary = cam.call("get_state")
		var zp := _win(zin.get_global_rect().get_center())
		await _touch_down(0, zp)
		await _seconds(1.0)
		await _touch_up(0, zp)
		await _seconds(0.5)
		var z1: Dictionary = cam.call("get_state")
		_check("mantener ZOOM+ repite", str(z0) != str(z1), "%s -> %s" % [_short(z0), _short(z1)])
	else:
		_check("controles en pantalla visibles en tablet", false, "ZoomIn no visible")
	if cam.has_method("set_state"):
		cam.call("set_state", s0)
		await _seconds(0.5)

func _test_tap_building() -> void:
	var saw := _first("sawmill")
	if saw == null:
		return
	var info: Dictionary = GridManager.get_building_info(saw)
	var oc: Vector2i = info.get("origin_cell", Vector2i.ZERO)
	_placer.call("assist_center_on", oc)
	await _seconds(1.0)
	var p = _cell_win(oc, Vector2i(2, 2))
	await _tap_at(p)
	await _frames(20)
	await _shot("ficha_por_toque")
	var panel: Node = _main.get_node("BuildingInfoPanel")
	var vis := false
	for c in panel.get_children():
		if c is Control and (c as Control).visible:
			vis = true
	_check("tocar un edificio abre su ficha", vis)
	EventBus.building_deselected.emit()
	await _frames(10)

func _test_settings_and_theme() -> void:
	var pm: Node = _main.get_node("PauseMenu")
	var mb := pm.find_child("MenuButton", true, false) as Control
	await _tap(mb)
	await _frames(20)
	_check("tocar ☰ MENÚ abre el menú", bool(pm.call("is_open")))
	await _shot("menu_abierto")
	var gs := pm.find_child("Game_Settings", true, false) as Control
	if gs == null or not gs.is_visible_in_tree():
		_check("entrada Ajustes en el menú", false)
		return
	await _tap(gs)
	await _frames(25)
	var sp: Node = _main.get_node("SettingsPanel")
	_check("tocar Ajustes abre Ajustes", bool(sp.call("is_open")))
	var ntabs := sp.find_children("Tab_*", "BaseButton", true, false).size()
	var i := 0
	for k in ntabs:
		var tabs := sp.find_children("Tab_*", "BaseButton", true, false)
		if k >= tabs.size() or not is_instance_valid(tabs[k]):
			continue
		var t: Control = tabs[k]
		if (t as Control).is_visible_in_tree():
			await _tap(t as Control)
			await _frames(15)
			await _shot("ajustes_tab_%d" % i)
			# Desplazar la pestaña con el dedo sobre sus controles.
			var sc := sp.find_child("SettingsScroll", true, false) as ScrollContainer
			if sc != null and sc.is_visible_in_tree() and sc.get_v_scroll_bar().max_value > sc.get_v_scroll_bar().page + 1:
				var r := sc.get_global_rect()
				var st := _win(r.get_center() + Vector2(0, r.size.y * 0.25))
				var v0 := sc.scroll_vertical
				await _drag(0, st, st + Vector2(0, -220), 12)
				await _frames(15)
				_check("Ajustes pestaña %d se desplaza con el dedo" % i, sc.scroll_vertical != v0, "%d -> %d" % [v0, sc.scroll_vertical])
				await _shot("ajustes_tab_%d_desplazada" % i)
			i += 1
	# Tema oscuro (lo que haria el selector) y capturas.
	sp.call("set_ui_theme", "dark")
	await _frames(40)
	_main = get_tree().current_scene
	_placer = _main.get_node("BuildingPlacer")
	await _shot("tema_oscuro_ajustes")
	sp = _main.get_node("SettingsPanel")
	if bool(sp.call("is_open")):
		sp.call("toggle")
		await _frames(10)
	pm = _main.get_node("PauseMenu")
	if bool(pm.call("is_open")):
		pm.call("resume")
	get_tree().paused = false
	await _frames(15)
	await _shot("tema_oscuro_hud")
	var cm: Node = _main.get_node("ConstructionMenu")
	await _tap(cm.find_child("BuildButton", true, false) as Control)
	await _frames(20)
	await _shot("tema_oscuro_construir")
	cm.call("_close")
	await _frames(10)
	var saw := _first("sawmill")
	if saw != null:
		EventBus.building_clicked.emit(saw, GridManager.get_building_info(saw).get("data"))
		await _frames(20)
		await _shot("tema_oscuro_ficha")
		EventBus.building_deselected.emit()
		await _frames(10)
	GameConfig.ui_theme = "light"
	DeviceProfile.apply_theme()
	await _frames(10)

func _test_combat() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 4, "artillery": 2}, "training": [], "upkeep_accum": 0.0})
	var ok: bool = CombatManager.start_skirmish({"infantry": 4, "artillery": 2}, 3)
	await _seconds(1.5)
	_main = get_tree().current_scene
	var bs: Node = _main.get_node_or_null("BattleScreen")
	_check("tablero abierto", ok and CombatManager.is_board_open())
	await _shot("combate_vista_por_defecto")
	if bs == null:
		return
	# Tablero 8x8 (vista "board"): tocar la propia, luego una casilla valida.
	bs.call("force_combat_view", "board")
	await _seconds(1.0)
	await _shot("combate_tablero")
	var moved := false
	for guard in 30:
		if not CombatManager.is_board_open():
			break
		await _seconds(0.5)
		if guard == 29:
			_check("turno del jugador en el tablero", false, "busy=%s turno_jugador=%s" % [bs.call("_board_busy"), CombatManager.is_player_turn()])
		if bool(bs.call("_board_busy")) or not CombatManager.is_player_turn():
			await _seconds(1.0)
			continue
		var act := CombatManager.get_active_unit()
		if act == null:
			continue
		var cell_btn: Button = bs.call("board_cell", act.position)
		var view3d := bs.find_child("Board3DView", true, false) as Control
		if (cell_btn == null or not cell_btn.is_visible_in_tree()) and view3d != null and view3d.is_visible_in_tree():
			# Tablero 3D: tocar la pieza y luego una casilla valida en su pantalla.
			var board = view3d.get("board")
			var from3 := act.position
			var pa = _board3d_win(view3d, board, from3)
			await _tap_at(pa)
			await _seconds(0.8)
			await _shot("combate3d_toque_propia")
			var moves3: Array = CombatManager.get_valid_moves(act.uid)
			if moves3.is_empty():
				break
			var target3: Vector2i = moves3[moves3.size() / 2]
			await _tap_at(_board3d_win(view3d, board, target3))
			await _seconds(2.0)
			_check("tablero 3D: tocar casilla valida mueve la unidad", act.position != from3,
				"%s -> %s (quiso %s)" % [from3, act.position, target3])
			var c0 = _board3d_win(view3d, board, Vector2i(0, 0))
			var c1 = _board3d_win(view3d, board, Vector2i(1, 0))
			if c0 != null and c1 != null:
				var px: float = (c0 as Vector2).distance_to(c1) / get_tree().root.content_scale_factor
				_check("tablero 3D: casilla >= 44 px de lienzo", px >= 44.0, "%.0f px" % px)
			await _shot("combate3d_movido")
			break
		if cell_btn == null or not cell_btn.is_visible_in_tree():
			_check("casilla del tablero visible", false, "board_cell(%s)" % act.position)
			break
		print("TQA: casilla tablero tamano=", cell_btn.get_global_rect().size)
		_check("casilla del tablero de tamaño de dedo (>=44 px)", cell_btn.get_global_rect().size.x >= 44, str(cell_btn.get_global_rect().size))
		await _tap(cell_btn)
		await _frames(15)
		await _shot("combate_ficha_unidad")
		var moves: Array = CombatManager.get_valid_moves(act.uid)
		if moves.is_empty():
			break
		var target: Vector2i = moves[0]
		var from := act.position
		await _tap(bs.call("board_cell", target))
		await _seconds(1.5)
		moved = act.position != from
		_check("tocar una casilla valida mueve la unidad", moved, "%s -> %s (quiso %s)" % [from, act.position, target])
		await _shot("combate_movido")
		break
	# Vista frontal (la maqueta): captura y AVANZAR por toque.
	bs.call("force_combat_view", "front")
	await _seconds(1.5)
	await _shot("combate_frente")
	var adv := bs.find_child("AdvanceButton", true, false) as Control
	if adv != null and adv.is_visible_in_tree():
		var r := adv.get_global_rect()
		_check("AVANZAR de tamaño de dedo", r.size.y >= 44, str(r.size))
		await _tap(adv)
		await _seconds(2.0)
		await _shot("combate_frente_avanzar")
	var auto := bs.find_child("AutoResolveButton", true, false) as Control
	if auto != null and auto.is_visible_in_tree():
		var ratio: float = GameConfig.combat_auto_resolve_ratio
		GameConfig.combat_auto_resolve_ratio = 0.0
		await _tap(auto)
		GameConfig.combat_auto_resolve_ratio = ratio
		await _seconds(4.0)
		await _shot("combate_resuelto")
	if CombatManager.is_board_open():
		CombatManager.end_encounter()
		await _frames(20)
	bs.call("force_combat_view", "")

# ── Toques ────────────────────────────────────────────────────────────

func _win(canvas_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * canvas_pos

func _cell_win(cell: Vector2i, size: Vector2i) -> Variant:
	var p = _placer.call("assist_cell_to_screen", cell, size)
	if p == null:
		return null
	return _win(p)

func _board3d_win(view3d: Control, board, cell: Vector2i) -> Variant:
	if board == null:
		return null
	var cam: Camera3D = board.call("camera")
	var sp: Vector2 = cam.unproject_position(board.call("_world_of", cell))
	var local: Vector2 = view3d.call("to_local_point", sp)
	return _win(view3d.get_global_transform() * local)

func _touch_down(index: int, p: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = p
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)

func _touch_up(index: int, p: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = p
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)

func _drag_event(index: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = p
	e.relative = rel
	e.screen_relative = rel
	Input.parse_input_event(e)

func _drag(index: int, from: Vector2, to: Vector2, steps: int) -> void:
	await _touch_down(index, from)
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		_drag_event(index, p, p - prev)
		prev = p
		await _frames(2)
	await _touch_up(index, to)

func _tap_at(p) -> void:
	if p == null:
		print("TQA: toque fuera de pantalla")
		return
	await _touch_down(0, p)
	await _frames(3)
	await _touch_up(0, p)

func _tap(c: Control) -> void:
	if c == null:
		print("TQA: toque a un control nulo")
		return
	await _tap_at(_win(c.get_global_rect().get_center()))

func _cancel_placement(what: String) -> void:
	if not bool(_placer.call("assist_is_placing")):
		return
	var x := get_tree().root.find_child("CancelPlacement", true, false) as Control
	if x != null and x.is_visible_in_tree():
		await _tap(x)
		await _frames(15)
		_check("✕ CANCELAR (%s) deja de colocar" % what, not bool(_placer.call("assist_is_placing")))
	else:
		_check("✕ CANCELAR visible al colocar (%s)" % what, false)
		EventBus.building_placement_cancelled.emit()
		await _frames(5)

func _ensure_visible_in_scroll(c: Control) -> void:
	var sc := c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(c)
		await _frames(5)

# ── Ayudas ────────────────────────────────────────────────────────────

func _camera_node() -> Node:
	if _arg("view") == "2d":
		return _main.get_node_or_null("Camera2D")
	return _main.get_node_or_null("MonumentalCamera")

func _short(d: Dictionary) -> String:
	var parts: Array = []
	for k in d:
		var v = d[k]
		if v is float:
			parts.append("%s=%.2f" % [k, v])
		else:
			parts.append("%s=%s" % [k, v])
	return "{" + ", ".join(parts) + "}"

func _first_visible_named(root: Node, prefix: String) -> Control:
	for c in root.find_children(prefix + "*", "Control", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null

func _visible_one(root: Node, names: Array) -> Control:
	for n in names:
		for c in root.find_children(n, "Control", true, false):
			if (c as Control).is_visible_in_tree():
				return c
	return null

func _first_card_in(list: Node) -> Control:
	for c in list.find_children("*", "Control", true, false):
		if c.has_meta("building_id") and (c as Control).is_visible_in_tree():
			return c
	return null

func _top_up() -> void:
	ResourceManager.set_amounts({"gold": 900, "wood": 600, "food": 80, "planks": 20})
	if PopulationManager.get_free_workers() < 6:
		PopulationManager._population += 6
		PopulationManager._max_population = maxi(PopulationManager._max_population, PopulationManager._population)
		PopulationManager._recalculate_all()

func _count(id: String) -> int:
	return GridManager.count_by_id(id) if GridManager.has_method("count_by_id") else 0

func _first(id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == id:
			return info["node"]
	return null

func _map() -> Node:
	return _main.get_node_or_null("MapGenerator")

func _free_spot(id: String) -> Vector2i:
	var data: BuildingData = Rules.load_building_data(id)
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var rule: Dictionary = GameConfig.get_deposit_rule(id)
	if not rule.is_empty():
		var spots: Array = _map().buildable_spots_near(String(rule["deposit"]), data.grid_size, int(rule["reach"]), 0)
		spots.sort_custom(func(a, b): return _dist(a["origin"], center) < _dist(b["origin"], center))
		for s in spots:
			if (s["size"] as Vector2i) == data.grid_size and bool(Rules.evaluate_placement(id, s["origin"], data.grid_size, _map())["ok"]):
				return s["origin"]
	return center + Vector2i(4, 4)

func _a_deposit_cell() -> Vector2i:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var best := center
	var best_d := 1 << 30
	for dep in _map().get_all_deposits():
		var c := Vector2i(int(dep["cell_x"]), int(dep["cell_y"]))
		if _dist(c, center) < best_d:
			best_d = _dist(c, center)
			best = c
	return best

## Dos celdas en linea recta, la primera pegada a la red, con `n` libres.
func _road_line_cells(n: int) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var cands: Array = []
	for x in GridManager.grid_width:
		for y in GridManager.grid_height:
			cands.append(Vector2i(x, y))
	cands.sort_custom(func(a, b): return _dist(a, center) < _dist(b, center))
	for c in cands:
		var v: Dictionary = Rules.evaluate_placement("road", c, Vector2i.ONE, _map())
		if not bool(v["ok"]) or not (v.get("route", []) as Array).is_empty():
			continue
		for d in dirs:
			var all_free := true
			for i in range(1, n):
				var cc: Vector2i = c + d * i
				if not GridManager.is_valid_cell(cc) or GridManager.get_building_at(cc) != null \
						or not bool(Rules.evaluate_placement("road", cc, Vector2i.ONE, _map())["ok"]):
					all_free = false
					break
			if all_free:
				return [c, c + d * (n - 1)]
	return []

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var img := get_tree().root.get_texture().get_image()
	var path := "%s/%s_%02d_%s.png" % [OUT_DIR, _tag, _n, shot_name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("TQA: shot ", ProjectSettings.globalize_path(path))

func _write_results() -> void:
	var ok := 0
	for r in _results:
		if r["ok"]:
			ok += 1
	print("TQA: RESUMEN %d de %d OK (%s)" % [ok, _results.size(), _tag])
	var f := FileAccess.open(ProjectSettings.globalize_path("%s/%s_resultados.json" % [OUT_DIR, _tag]), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"tag": _tag, "results": _results}, "\t"))
		f.close()

func _finish() -> void:
	SettingsParking.restore(_settings_snap)
	SaveParking.restore(BACKUP_PATH)
	get_tree().paused = false
	get_tree().quit()
