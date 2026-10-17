extends CanvasLayer
## El tutorial guiado, sobre la interfaz de verdad (coach marks), y la casa del
## prologo (PrologueScreen, que vive como hija de este panel para no tocar las
## escenas Main.tscn y Main2D.tscn).
##
## Un paso del tutorial es:
##   - un velo que oscurece la pantalla menos el control del que se habla (el
##     boton CONSTRUIR, la tarjeta del Aserradero...), con un marco de laton;
##   - una flecha que lo senala;
##   - una tarjeta con UNA linea: que hacer ahora, las cifras del edificio con
##     iconos (TutorialManager.building_facts) y debajo lo que falta si algo lo
##     impide (trabajadores, recursos) y como conseguirlo (step_how). Sin
##     "Saltar tutorial" (2026-10-04) ni forma de cerrarla; solo el repaso pedido
##     desde AYUDA tiene "Terminar repaso". Las tarjetas de leer (la meta, el
##     Nucleo) se cumplen con su boton (2026-10-16).
## El velo no se come nada (MOUSE_FILTER_IGNORE): el jugador puede tocar lo que
## quiera, tambien fuera de orden. El paso no avanza con "Siguiente": avanza
## cuando TutorialManager ve que se hizo (derive_step), asi que da igual el
## orden en que haga las cosas.
##
## Estilo laton sobre metal (el del HUD): es la voz de "que tocar". El lore es
## papel (PrologueScreen) y la ayuda azul acero (HelperPanel).

const PrologueScene := preload("res://scenes/ui/PrologueScreen.tscn")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const CoachArrow := preload("res://scripts/ui/CoachArrow.gd")
const TypeCircleScript := preload("res://scripts/ui/TypeCircle.gd")

## Encima de las ventanas de UIManager (12+) y del texto de colocar (15), para
## poder senalar una tarjeta dentro de la lista de CONSTRUIR. El tablero (18) lo
## esconde: el tutorial no habla durante una pelea.
const COACH_LAYER := 19
## Holgura del hueco del velo alrededor del control.
const HOLE_PAD := 8.0
const CARD_WIDTH := 460.0
const EDGE := 16.0
## Segundos del "listo" final antes de cerrarse solo (lleva la meta: se lee).
const DONE_SECONDS := 25.0
## Hueco entre lo senalado y la tarjeta: ahi va la flecha.
const ARROW_GAP := 56.0

var _prologue: CanvasLayer
var _coach: Control
var _dim: Array[ColorRect] = []
var _frame: Panel
var _arrow: Control
var _ring: Control
var _card: PanelContainer
var _badge: Label
var _text: Label
## Las cifras del edificio del paso, con iconos (building_facts).
var _facts: HBoxContainer
var _facts_for := "-"
var _end_replay_btn: Button
var _ok_btn: Button
var _step := ""
var _quick_guide: CanvasLayer = null
const QuickGuideScript := preload("res://scripts/ui/QuickGuide.gd")
const QUICK_GUIDE_ID := "quick_guide"
var _done_left := 0.0
var _pulse := 0.0
## Lo caro del paso (que control senala, su texto con lo que falta, que bosque)
## se busca cada RESOLVE_SECONDS, no en cada fotograma (docs/26 §6.9). Cada
## fotograma solo lee el rectangulo del control ya encontrado y proyecta la
## celda: asi sigue a la camara y a la lista de CONSTRUIR sin retraso.
const RESOLVE_SECONDS := 0.25
var _resolve_left := 0.0
var _res_text := ""
var _res_hint := ""
var _res_how := ""
var _res_control: Control = null
var _res_cell := Vector2i(-1, -1)
var _res_cell_size := Vector2i.ONE
var _res_card_id := ""
var _res_picked := false
## El alto de la tarjeta solo cambia con el texto o el ancho.
var _card_key := ""
var _card_h := 0.0

## Combate guiado (docs/23 §2.4): el paso de TutorialManager.COMBAT_STEPS en
## pantalla, o "". Usa el mismo velo, flecha, aro y tarjeta que la colonia, pero
## sobre el tablero (capa 19, por encima de BattleScreen, 18) y sin oscurecer:
## lo que se ensena es el tablero entero.
var _cstep := ""
var _circle: Control
var _combat_ok_btn: Button

func _ready() -> void:
	layer = COACH_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tutorial_panel")
	_prologue = PrologueScene.instantiate()
	_prologue.name = "PrologueScreen"
	add_child(_prologue)
	_prologue.closed.connect(_on_prologue_closed)
	_quick_guide = QuickGuideScript.new()
	_quick_guide.name = "QuickGuide"
	add_child(_quick_guide)
	_quick_guide.closed.connect(func(): TutorialManager.mark_help_seen(QUICK_GUIDE_ID))
	_build_coach()
	EventBus.tutorial_intro_requested.connect(_open_intro)
	EventBus.tutorial_step_changed.connect(_on_step_changed)
	EventBus.tutorial_guide_finished.connect(func(_skipped): _on_step_changed(""))
	EventBus.combat_lesson_step_changed.connect(_on_combat_step_changed)
	# Si el tutorial ya estaba en marcha (cambio de vista 3D/2D recarga la escena),
	# se recoge el paso actual.
	_on_step_changed.call_deferred(TutorialManager.current_step())

# ══════════════════════════════════════════════════════════════════════
# ── Prologo ──
# ══════════════════════════════════════════════════════════════════════

func _open_intro() -> void:
	_prologue.open(TutorialManager.requested_variant())

func _on_prologue_closed() -> void:
	EventBus.tutorial_intro_closed.emit()
	# La guia rapida ya no sale sola al cerrar el prologo (Bryan, 14-10: la
	# ventana "Como funciona Tormenta Imperial" sobraba al empezar). Sus cuatro
	# bloques siguen en AYUDA (`guide_qg_*`). Un `quick_guide` visto en una
	# partida vieja se carga igual y no cambia nada.

## La guia rapida (Como funciona). Ya no se abre sola; queda para quien la pida.
func quick_guide() -> CanvasLayer:
	return _quick_guide

func open_quick_guide() -> void:
	_quick_guide.open()

func prologue() -> CanvasLayer:
	return _prologue

## Nombres de la intro vieja, para quien ya los usaba (PauseMenu, sondas).
func is_intro_open() -> bool:
	return _prologue != null and _prologue.is_open()

func _close() -> void:
	if is_intro_open():
		_prologue.close()

func current_page() -> int:
	return _prologue.current_page()

func page_count() -> int:
	return _prologue.page_count()

func go_to_page(index: int) -> void:
	_prologue.go_to_page(index)

# ══════════════════════════════════════════════════════════════════════
# ── Coach marks ──
# ══════════════════════════════════════════════════════════════════════

func _build_coach() -> void:
	_coach = Control.new()
	_coach.name = "Coach"
	_coach.set_anchors_preset(Control.PRESET_FULL_RECT)
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.visible = false
	add_child(_coach)

	for i in 4:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0, 0.55)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_coach.add_child(r)
		_dim.append(r)

	_frame = Panel.new()
	_frame.name = "Highlight"
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0)
	fs.border_color = UITheme.ACCENT
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(6)
	fs.shadow_color = Color(UITheme.ACCENT, 0.45)
	fs.shadow_size = 8
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.add_child(_frame)

	# Un aro para senalar un punto del mapa (el bosque, la obra).
	_ring = Panel.new()
	_ring.name = "Ring"
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(UITheme.ACCENT, 0.12)
	rs.border_color = UITheme.ACCENT
	rs.set_border_width_all(3)
	rs.set_corner_radius_all(40)
	_ring.add_theme_stylebox_override("panel", rs)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(80, 80)
	_ring.pivot_offset = Vector2(40, 40)
	_coach.add_child(_ring)

	_arrow = CoachArrow.new()
	_arrow.name = "Arrow"
	_arrow.set("color", UITheme.ACCENT)
	_coach.add_child(_arrow)

	_card = PanelContainer.new()
	_card.name = "CoachCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT, 2, true))
	_coach.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)

	_badge = UITheme.make_label("", "small", UITheme.ACCENT)
	_badge.name = "Badge"
	col.add_child(_badge)
	_text = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_text.name = "Instruction"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	# Las cifras del edificio: [madera] +6 cada 12 s  [trabajadores] 2 trabajan.
	_facts = HBoxContainer.new()
	_facts.name = "Facts"
	_facts.add_theme_constant_override("separation", 14)
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_facts.visible = false
	col.add_child(_facts)
	# El circulo de ventajas: solo en el paso 7 del combate guiado.
	_circle = TypeCircleScript.new()
	_circle.name = "TypeCircle"
	_circle.visible = false
	col.add_child(_circle)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	# Sin "Saltar tutorial" (decision de Bryan, 2026-10-04): el tutorial de una
	# partida nueva se hace entero. Solo el repaso que se pide desde AYUDA se
	# puede dejar a medias.
	_end_replay_btn = Button.new()
	_end_replay_btn.name = "EndReplay"
	_end_replay_btn.text = Tr.t("BTN_GUIDE_END_REPLAY")
	_end_replay_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	_end_replay_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_end_replay_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_end_replay_btn.pressed.connect(func(): TutorialManager.stop_replay())
	_end_replay_btn.visible = false
	row.add_child(_end_replay_btn)
	_ok_btn = Button.new()
	_ok_btn.name = "GuideOk"
	_ok_btn.text = Tr.t("BTN_GUIDE_OK")
	_ok_btn.custom_minimum_size = Vector2(140, UITheme.MIN_BTN_H)
	_ok_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_ok_btn, UITheme.ACCENT.darkened(0.2), UITheme.FONT_BUTTON)
	_ok_btn.pressed.connect(_on_ok_pressed)
	_ok_btn.visible = false
	row.add_child(_ok_btn)
	# Combate guiado: solo "Entendido" (el circulo). Sin "Saltar" (2026-10-16).
	_combat_ok_btn = Button.new()
	_combat_ok_btn.name = "CombatOk"
	_combat_ok_btn.text = Tr.t("BTN_CGUIDE_OK")
	_combat_ok_btn.custom_minimum_size = Vector2(140, UITheme.MIN_BTN_H)
	_combat_ok_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_combat_ok_btn, UITheme.ACCENT.darkened(0.2), UITheme.FONT_BUTTON)
	_combat_ok_btn.pressed.connect(func(): TutorialManager.close_combat_step(_cstep))
	_combat_ok_btn.visible = false
	row.add_child(_combat_ok_btn)

## El boton de la tarjeta: en el "listo" final cierra el tutorial; en una
## tarjeta de leer (la meta, el Nucleo) la da por leida y sigue.
func _on_ok_pressed() -> void:
	if _step == "done":
		TutorialManager.finish_guide()
	else:
		TutorialManager.confirm_step(_step)

func _on_step_changed(step_id: String) -> void:
	_step = step_id
	# Paso nuevo: su destino se busca en el siguiente fotograma. Sin paso el
	# panel no trabaja (antes corria cada fotograma aunque no hubiera tutorial).
	_resolve_left = 0.0
	_res_control = null
	_res_cell = Vector2i(-1, -1)
	set_process(step_id != "" or _cstep != "")
	if step_id == "":
		_coach.visible = false
	_done_left = DONE_SECONDS if step_id == "done" else 0.0
	var reading: bool = TutorialManager.step_has_ok(step_id)
	_ok_btn.visible = step_id == "done" or reading
	_ok_btn.text = TutorialManager.step_ok_text(step_id) if reading else Tr.t("BTN_GUIDE_OK")
	_end_replay_btn.visible = step_id != "done" and TutorialManager.is_replay()
	# El paso de reparar ensena lo que cuesta reparar (no un edificio de datos).
	_render_facts("__repair__" if step_id == TutorialManager.REPAIR_STEP \
		else TutorialManager.step_building(step_id))
	_render_text()

func _render_text() -> void:
	# Con una marca de combate en pantalla, la tarjeta es suya.
	if _step == "" or _cstep != "":
		return
	var n := TutorialManager.step_number(_step)
	if _step == "done":
		_badge.text = Tr.t("LBL_GUIDE_DONE_BADGE")
	elif _step == "goal":
		_badge.text = Tr.t("LBL_GUIDE_GOAL_BADGE") % [n, TutorialManager.GUIDE_TOTAL]
	elif _step == TutorialManager.REPAIR_STEP:
		_badge.text = Tr.t("LBL_GUIDE_REPAIR_BADGE")
	else:
		_badge.text = Tr.t("LBL_GUIDE_STEP") % [n, TutorialManager.GUIDE_TOTAL]
	_text.text = TutorialManager.step_text(_step)

## Pinta la fila de cifras con iconos de `building_id` ("" la esconde). Solo
## rehace los nodos si cambia el edificio.
func _render_facts(building_id: String) -> void:
	if building_id == _facts_for:
		return
	_facts_for = building_id
	for c in _facts.get_children():
		_facts.remove_child(c)
		c.queue_free()
	var facts: Array = TutorialManager.repair_facts() if _step == TutorialManager.REPAIR_STEP \
		else TutorialManager.building_facts(building_id)
	for f in facts:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if String(f["icon"]) != "":
			chip.add_child(UITheme.make_icon(String(f["icon"]), 24))
		var l := UITheme.make_label(String(f["text"]), "small", UITheme.TEXT_BRIGHT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
		_facts.add_child(chip)
	_facts.visible = not facts.is_empty()

## Las cifras en pantalla, como texto (pruebas).
func facts_text() -> String:
	var parts: Array = []
	for chip in _facts.get_children():
		for c in chip.get_children():
			if c is Label:
				parts.append((c as Label).text)
	return "  ".join(parts)

func current_step() -> String:
	return _step

func is_coach_visible() -> bool:
	return _coach.visible

func coach_text() -> String:
	return _text.text

## El "Terminar repaso" (solo visible en un repaso pedido desde AYUDA).
func end_replay_button() -> Button:
	return _end_replay_btn

## El rectangulo resaltado ahora (vacio si no hay control).
func highlight_rect() -> Rect2:
	return Rect2(_frame.position, _frame.size) if _frame.visible else Rect2()

## Algo mas importante esta en pantalla: el prologo, la pausa o el menu
## principal (el arbol en pausa), o una pelea.
func _should_hide() -> bool:
	if _step == "" or not TutorialManager.is_coach_active():
		return true
	if is_intro_open() or get_tree().paused:
		return true
	if _quick_guide != null and _quick_guide.is_open():
		return true
	# Otra ventana encima (Tecnologia, Mercado...): la marca del tutorial no la
	# tapa. CONSTRUIR si deja verla: los pasos del tutorial ocurren ahi dentro.
	# La ficha del edificio tambien, en los pasos que ocurren en ella (mover,
	# derribar, reparar: 2026-10-16).
	for w in UIManager.open_windows():
		if not is_instance_valid(w):
			continue
		var wname := String(w.name)
		if wname == "ConstructionMenu":
			continue
		if wname == "BuildingInfoPanel" and _step in TutorialManager.INFO_PANEL_STEPS:
			continue
		return true
	if CombatManager.is_board_open():
		return true
	return false

func _process(delta: float) -> void:
	if _cstep != "" and CombatManager.is_board_open():
		_layout_combat(delta)
		return
	if _should_hide():
		_coach.visible = false
		# Al volver a verse, el destino se busca de nuevo en ese fotograma.
		_resolve_left = 0.0
		return
	_coach.visible = true
	_pulse += delta
	if _step == "done":
		_done_left -= delta
		if _done_left <= 0.0:
			TutorialManager.finish_guide()
			return
	_resolve_left -= delta
	# El control encontrado se fue (la lista se cerro, la tarjeta se recreo): se
	# busca otra vez ya, sin esperar al reloj.
	# Igual si el jugador acaba de elegir (o soltar) la tarjeta que pide el paso:
	# la marca salta al CONSTRUIR del detalle en ese mismo fotograma.
	if _resolve_left <= 0.0 or (_res_control != null \
			and (not is_instance_valid(_res_control) or not _res_control.is_visible_in_tree())) \
			or (_res_card_id != "" and _card_already_picked(_res_card_id) != _res_picked):
		_resolve_step()
	_layout_step()

## Lo caro del paso, cada RESOLVE_SECONDS: el texto, lo que falta, el control
## que se senala y la celda del mapa (el bosque mas cercano al centro, la obra).
func _resolve_step() -> void:
	_resolve_left = RESOLVE_SECONDS
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var target := TutorialManager.step_target(_step)
	var text := TutorialManager.step_text(_step)
	# El edificio que pide el paso ya esta elegido en la lista: la marca esta en
	# CONSTRUIR (HelpTargets.card_or_build) y el texto deja de pedir que se elija.
	_res_card_id = target.substr(5) if target.begins_with("card:") else ""
	_res_picked = _res_card_id != "" and _card_already_picked(_res_card_id)
	if _res_picked:
		text = Tr.ti("GUIDE_PRESS_BUILD")
	_res_text = text
	_res_control = null
	_res_cell = Vector2i(-1, -1)
	# CONSTRUIR es un boton grande siempre visible abajo (menu unico, #31): el
	# paso 1 lo senala a el directamente (grupo hud_build_button).
	# "a|b": el primero que se encuentre (el boton MOVER de la ficha si esta
	# abierta; si no, la casa en el mapa).
	var site := {}
	for t in target.split("|", false):
		site = _target_site(vp, t)
		if not site.is_empty():
			break
		if not (t in ["forest", "core", "practice_road", "damaged"] or t.begins_with("deposit:") \
				or t.begins_with("building:") or t.begins_with("built:")):
			_res_control = HelpTargets.control(get_tree(), t)
			if _res_control != null:
				break
	if not site.is_empty():
		_res_cell = site["cell"]
		_res_cell_size = site["size"]
	# Lo que falta para este paso (trabajadores, recursos) y como conseguirlo: el
	# tutorial no se salta, asi que tiene que decir por que no se puede seguir y
	# que hacer.
	_res_hint = TutorialManager.step_hint(_step)
	_res_how = TutorialManager.step_how(_step)

## Una celda del mapa que senalar para `t`, o {} si `t` no es de celda (o no hay).
func _target_site(vp: Vector2, t: String) -> Dictionary:
	if t == "forest":
		return _deposit_cell(vp, "forest")
	if t.begins_with("deposit:"):
		return _deposit_cell(vp, t.substr(8))
	if t == "core":
		return _core_cell()
	if t.begins_with("building:"):
		return _building_cell(t.substr(9))
	if t.begins_with("built:"):
		return _built_cell(t.substr(6))
	if t == "practice_road":
		var c: Vector2i = TutorialManager.practice_road_cell
		return {} if c.x < 0 else {"cell": c, "size": Vector2i.ONE}
	if t == "damaged":
		return _node_cell(TutorialManager.repair_target())
	return {}

## Coloca velo, marco, flecha y tarjeta para el paso actual. Se repite cada
## frame: los controles se mueven (la lista de CONSTRUIR se abre, la camara se
## desplaza) y el foco tiene que seguirlos. Que se senala y con que texto lo
## deja _resolve_step; aqui solo se mide y se coloca.
func _layout_step() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var text := _res_text
	var rect := Rect2()
	var point := {}
	if _res_cell.x >= 0:
		point = HelpTargets.cell_screen_point(get_viewport(), _res_cell, _res_cell_size)
	elif _res_control != null and is_instance_valid(_res_control) and _res_control.is_visible_in_tree():
		rect = _res_control.get_global_rect()
	if not point.is_empty() and not bool(point.get("ok", true)):
		text += "\n" + Tr.ti("GUIDE_MOVE_CAMERA")
	if _res_hint != "":
		text += "\n" + _res_hint
	if _res_how != "":
		text += "\n" + _res_how
	if _text.text != text:
		_text.text = text

	var has_rect := rect.size.x > 1.0 and rect.size.y > 1.0
	if has_rect:
		rect = rect.grow(HOLE_PAD)
	_place_dim(vp, rect if has_rect else Rect2())
	_frame.visible = has_rect
	if has_rect:
		_frame.position = rect.position
		_frame.size = rect.size
		_frame.modulate.a = 0.65 + 0.35 * sin(_pulse * 4.0)

	# La tarjeta, junto a lo senalado (debajo si cabe, si no encima), sin taparlo.
	var w: float = minf(CARD_WIDTH, vp.x - EDGE * 2.0)
	# Medir la tarjeta (reset_size + tamano minimo) solo si cambia su texto, su
	# ancho o los botones; cada fotograma era trabajo de maquetado para nada.
	var key := "%s|%s|%d|%s|%s|%s" % [_badge.text, text, int(w), _ok_btn.visible, _end_replay_btn.visible, _facts_for]
	var ch: float = _fit_card(w, key)
	var focus := Rect2()
	if has_rect:
		focus = rect
	elif not point.is_empty():
		focus = Rect2(point["point"] - Vector2(40, 40), Vector2(80, 80))
	# Colocando con el dedo, el fantasma y su ✓ CONSTRUIR AQUI (#34) tampoco se
	# tapan: la tarjeta se aparta de los dos juntos.
	focus = with_confirm(focus, _confirm_rect())
	_card.position = card_position(vp, Vector2(w, ch), focus)

	# Flecha y aro.
	_ring.visible = false
	_arrow.visible = false
	if has_rect:
		var above := _card.position.y < rect.position.y
		var tip := Vector2(rect.get_center().x, rect.position.y - 4.0) if above \
			else Vector2(rect.get_center().x, rect.end.y + 4.0)
		_arrow.visible = true
		_arrow.point_at(tip, Vector2.DOWN if above else Vector2.UP)
	elif not point.is_empty():
		var p: Vector2 = point["point"]
		if bool(point.get("ok", true)):
			_ring.visible = true
			var s := 1.0 + 0.12 * sin(_pulse * 4.0)
			_ring.scale = Vector2(s, s)
			_ring.position = p - _ring.size * 0.5
			_arrow.visible = true
			_arrow.point_at(p - Vector2(0, 44), Vector2.DOWN)
		else:
			# Fuera de pantalla: la flecha en el borde, hacia donde esta.
			var c := vp * 0.5
			var dir := (p - c).normalized()
			var edge := _edge_point(c, dir, vp, 60.0)
			_arrow.visible = true
			_arrow.point_at(edge, dir)

## Ajusta la tarjeta a `w` de ancho y al alto de su texto, y devuelve ese alto.
## Solo se re-maqueta si cambia `key` (texto, ancho, botones) o si el tamano
## minimo ya no es el alto que tiene: la etiqueta con autowrap se mide primero
## sin ancho (una palabra por linea, una tarjeta de arriba abajo, captura de
## Bryan 14-10) y encoge un fotograma despues, cuando el VBox le da su ancho.
## Medir solo al cambiar el texto se quedaba con esa primera medida para
## siempre. get_combined_minimum_size() va cacheado: comprobarlo cada
## fotograma no cuesta.
func _fit_card(w: float, key: String) -> float:
	var min_h: float = _card.get_combined_minimum_size().y
	if key != _card_key or absf(_card.size.x - w) > 0.5 or absf(_card.size.y - min_h) > 0.5:
		_card_key = key
		_card.custom_minimum_size = Vector2(w, 0)
		_card.size = Vector2(w, 0)
		_card.reset_size()
		min_h = _card.get_combined_minimum_size().y
	_card_h = min_h
	return min_h

func _card_already_picked(building_id: String) -> bool:
	var scene := get_tree().current_scene
	var menu: Node = scene.get_node_or_null("ConstructionMenu") if scene != null else null
	return menu != null and menu.has_method("selected_building_id") \
		and menu.selected_building_id() == building_id

## El ✓ de colocar con el dedo, si esta a la vista (Rect2() si no).
func _confirm_rect() -> Rect2:
	var c := get_tree().get_first_node_in_group("placement_confirm") as Control
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()

## El foco agrandado para que tambien cubra el ✓. Publica para las pruebas.
static func with_confirm(focus: Rect2, confirm: Rect2) -> Rect2:
	if confirm.size == Vector2.ZERO:
		return focus
	if focus.size == Vector2.ZERO:
		return confirm
	return focus.merge(confirm)

## Donde va la tarjeta de `size` para senalar `focus`: debajo, a ARROW_GAP, si
## cabe; si no, encima; y centrada en horizontal sobre el foco, sin salirse. Sin
## foco, abajo al centro (por encima de CONSTRUIR). Publica para las pruebas.
static func card_position(vp: Vector2, size: Vector2, focus: Rect2) -> Vector2:
	if focus.size == Vector2.ZERO:
		return Vector2((vp.x - size.x) * 0.5, vp.y - size.y - 110.0)
	var x := clampf(focus.get_center().x - size.x * 0.5, EDGE, vp.x - size.x - EDGE)
	var below := focus.end.y + ARROW_GAP
	if below + size.y <= vp.y - EDGE:
		return Vector2(x, below)
	var above := focus.position.y - ARROW_GAP - size.y
	return Vector2(x, maxf(EDGE, above))

func _place_dim(vp: Vector2, hole: Rect2) -> void:
	if hole.size == Vector2.ZERO:
		# Sin control que resaltar no se oscurece nada: el mapa es el objetivo.
		for r in _dim:
			r.visible = false
		return
	var top := clampf(hole.position.y, 0.0, vp.y)
	var bottom := clampf(hole.end.y, 0.0, vp.y)
	var left := clampf(hole.position.x, 0.0, vp.x)
	var right := clampf(hole.end.x, 0.0, vp.x)
	var rects := [
		Rect2(0, 0, vp.x, top),
		Rect2(0, bottom, vp.x, vp.y - bottom),
		Rect2(0, top, left, bottom - top),
		Rect2(right, top, vp.x - right, bottom - top),
	]
	for i in 4:
		_dim[i].visible = true
		_dim[i].position = rects[i].position
		_dim[i].size = rects[i].size

func _edge_point(c: Vector2, dir: Vector2, vp: Vector2, margin: float) -> Vector2:
	var half := vp * 0.5 - Vector2(margin, margin)
	var tx: float = INF if absf(dir.x) < 0.001 else half.x / absf(dir.x)
	var ty: float = INF if absf(dir.y) < 0.001 else half.y / absf(dir.y)
	return c + dir * minf(tx, ty)

## El bosque que toca senalar (ver _deposit_cell). Nombre de siempre.
func _forest_cell(vp: Vector2) -> Dictionary:
	return _deposit_cell(vp, "forest")

## El yacimiento `deposit_id` ("forest", "gold_vein") que toca senalar: el mas
## cercano al centro de la pantalla, o al Nucleo si ninguno se ve, como
## {"cell", "size"}. {} si no hay mapa (pruebas).
func _deposit_cell(vp: Vector2, deposit_id: String) -> Dictionary:
	# El registrado en GameManager vale en 3D y en 2D (MapGenerator2D hereda);
	# el de la escena, por si aun no se registro.
	var gen: Node = GameManager.map_generator()
	if gen == null:
		gen = _scene_node("MapGenerator")
	if gen == null or not gen.has_method("get_all_deposits"):
		return {}
	var best := {}
	var best_d := INF
	var center := vp * 0.5
	for dep in gen.get_all_deposits():
		if String(dep.get("id", "")) != deposit_id:
			continue
		var cell := Vector2i(int(dep["cell_x"]), int(dep["cell_y"]))
		var sz := Vector2i(int(dep.get("size_x", 2)), int(dep.get("size_y", 2)))
		var sp := HelpTargets.cell_screen_point(get_viewport(), cell, sz)
		var p: Vector2 = sp["point"]
		var d: float = p.distance_to(center) + (0.0 if bool(sp["ok"]) else 100000.0)
		if d < best_d:
			best_d = d
			best = {"cell": cell, "size": sz}
	return best

## El punto en pantalla de ese bosque ({"ok", "point"}), o {}. Para las pruebas.
func _forest_point(vp: Vector2) -> Dictionary:
	var f := _forest_cell(vp)
	return {} if f.is_empty() else HelpTargets.cell_screen_point(get_viewport(), f["cell"], f["size"])

## El Nucleo, como {"cell", "size"}, o {} (escenas de prueba sin Nucleo).
func _core_cell() -> Dictionary:
	for info in GridManager.get_all_buildings():
		var data: Resource = info.get("data")
		if data != null and bool(data.get("is_core")):
			return {"cell": info.get("origin_cell", Vector2i.ZERO), "size": data.get("grid_size")}
	return {}

## Un `building_id` ya terminado (el primero), como {"cell", "size"}, o {}.
func _built_cell(building_id: String) -> Dictionary:
	for info in GridManager.get_all_buildings():
		var data: Resource = info.get("data")
		if data == null or String(data.get("id")) != building_id:
			continue
		var node: Node = info.get("node")
		if node != null and node.has_meta("under_construction"):
			continue
		return {"cell": info.get("origin_cell", Vector2i.ZERO), "size": data.get("grid_size")}
	return {}

## La celda de un edificio concreto, como {"cell", "size"}, o {}.
func _node_cell(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var info := GridManager.get_building_info(node)
	if info.is_empty() or info.get("data") == null:
		return {}
	return {"cell": info.get("origin_cell", Vector2i.ZERO), "size": info["data"].get("grid_size")}

## La obra de `building_id`, como {"cell", "size"}, o {}.
func _building_cell(building_id: String) -> Dictionary:
	for info in GridManager.get_all_buildings():
		var data: Resource = info.get("data")
		if data == null or String(data.get("id")) != building_id:
			continue
		var node: Node = info.get("node")
		if node != null and not node.has_meta("under_construction"):
			continue
		return {"cell": info.get("origin_cell", Vector2i.ZERO), "size": data.get("grid_size")}
	return {}

func _scene_node(node_name: String) -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var n := scene.get_node_or_null(node_name)
		if n != null:
			return n
	return null

# ══════════════════════════════════════════════════════════════════════
# ── Combate guiado (docs/23 §2.4) ──
# ══════════════════════════════════════════════════════════════════════

func _on_combat_step_changed(step_id: String) -> void:
	_cstep = step_id
	var combat := step_id != ""
	_circle.visible = combat and TutorialManager.combat_step_has_circle(step_id)
	_combat_ok_btn.visible = combat and TutorialManager.combat_step_has_ok(step_id)
	if combat:
		_ok_btn.visible = false
		_end_replay_btn.visible = false
		_facts.visible = false
		_facts_for = "-"
		_badge.text = Tr.t("LBL_CGUIDE_STEP") % [TutorialManager.combat_step_number(step_id), TutorialManager.COMBAT_TOTAL]
		_text.text = TutorialManager.combat_step_text(step_id)
		set_process(true)
	else:
		_coach.visible = false
		# Vuelve lo de la colonia, si habia un paso (se esconde igual mientras
		# el tablero siga abierto).
		_on_step_changed(_step)

## El paso de combate en pantalla (pruebas).
func combat_step() -> String:
	return _cstep

func combat_ok_button() -> Button:
	return _combat_ok_btn

func type_circle() -> Control:
	return _circle

## La tarjeta, la flecha y el aro sobre el tablero. Cada fotograma solo pregunta
## a BattleScreen donde esta lo que se senala (sigue a la camara y a la pieza).
func _layout_combat(delta: float) -> void:
	if get_tree().paused:
		_coach.visible = false
		return
	var bs: Node = get_tree().get_first_node_in_group("battle_screen")
	var anchor := {}
	if bs != null and bs.has_method("coach_anchor"):
		anchor = bs.coach_anchor(TutorialManager.combat_step_target(_cstep))
	# La maqueta aun cuenta lo que paso: la marca espera a que se vea.
	if bool(anchor.get("busy", false)):
		_coach.visible = false
		return
	_coach.visible = true
	_pulse += delta
	# El circulo ya no se cierra solo (2026-10-16): se cierra con "Entendido".
	for r in _dim:
		r.visible = false
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = anchor.get("rect", Rect2())
	var has_rect := rect.size.x > 1.0 and rect.size.y > 1.0
	var has_point := anchor.has("point")
	if has_rect:
		rect = rect.grow(HOLE_PAD)
	_frame.visible = has_rect
	if has_rect:
		_frame.position = rect.position
		_frame.size = rect.size
		_frame.modulate.a = 0.65 + 0.35 * sin(_pulse * 4.0)

	var w: float = minf(CARD_WIDTH, vp.x - EDGE * 2.0)
	var key := "%s|%s|%d|%s|%s" % [_badge.text, _text.text, int(w), _combat_ok_btn.visible, _circle.visible]
	_fit_card(w, key)
	var focus := Rect2()
	if has_rect:
		focus = rect
	elif has_point:
		focus = Rect2(Vector2(anchor["point"]) - Vector2(40, 40), Vector2(80, 80))
	_card.position = combat_card_position(vp, Vector2(w, _card_h), focus)

	_ring.visible = false
	_arrow.visible = false
	if has_rect:
		var above := _card.position.y < rect.position.y
		var tip := Vector2(rect.get_center().x, rect.position.y - 4.0) if above \
			else Vector2(rect.get_center().x, rect.end.y + 4.0)
		_arrow.visible = true
		_arrow.point_at(tip, Vector2.DOWN if above else Vector2.UP)
	elif has_point:
		var pt: Vector2 = anchor["point"]
		_ring.visible = true
		var sc := 1.0 + 0.12 * sin(_pulse * 4.0)
		_ring.scale = Vector2(sc, sc)
		_ring.position = pt - _ring.size * 0.5
		_arrow.visible = true
		_arrow.point_at(pt - Vector2(0, 44), Vector2.DOWN)

## Donde va la tarjeta en el combate: junto a lo senalado como en la colonia;
## sin nada que senalar (el circulo), arriba al centro, lejos de los botones de
## abajo. Publica para las pruebas.
static func combat_card_position(vp: Vector2, size: Vector2, focus: Rect2) -> Vector2:
	if focus.size == Vector2.ZERO:
		return Vector2((vp.x - size.x) * 0.5, maxf(EDGE, vp.y * 0.16))
	return card_position(vp, size, focus)
