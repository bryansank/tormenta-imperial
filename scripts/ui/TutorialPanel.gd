extends CanvasLayer
## El tutorial guiado, sobre la interfaz de verdad (coach marks), y la casa del
## prologo (PrologueScreen, que vive como hija de este panel para no tocar las
## escenas Main.tscn y Main2D.tscn).
##
## Un paso del tutorial es:
##   - un velo que oscurece la pantalla menos el control del que se habla (el
##     boton CONSTRUIR, la tarjeta del Aserradero...), con un marco de laton;
##   - una flecha que lo senala;
##   - una tarjeta con UNA linea: que hacer ahora. Y "Saltar tutorial".
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

## Encima de las ventanas de UIManager (12+) y del texto de colocar (15), para
## poder senalar una tarjeta dentro de la lista de CONSTRUIR. El tablero (18) lo
## esconde: el tutorial no habla durante una pelea.
const COACH_LAYER := 19
## Holgura del hueco del velo alrededor del control.
const HOLE_PAD := 8.0
const CARD_WIDTH := 460.0
const EDGE := 16.0
## Segundos del "listo" final antes de cerrarse solo.
const DONE_SECONDS := 10.0
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
var _skip_btn: Button
var _ok_btn: Button
var _step := ""
var _done_left := 0.0
var _pulse := 0.0

func _ready() -> void:
	layer = COACH_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tutorial_panel")
	_prologue = PrologueScene.instantiate()
	_prologue.name = "PrologueScreen"
	add_child(_prologue)
	_prologue.closed.connect(_on_prologue_closed)
	_build_coach()
	EventBus.tutorial_intro_requested.connect(_open_intro)
	EventBus.tutorial_step_changed.connect(_on_step_changed)
	EventBus.tutorial_guide_finished.connect(func(_skipped): _on_step_changed(""))
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

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_skip_btn = Button.new()
	_skip_btn.name = "SkipTutorial"
	_skip_btn.text = Tr.t("BTN_GUIDE_SKIP")
	_skip_btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	_skip_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_skip_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_skip_btn.pressed.connect(func(): TutorialManager.skip_guide())
	row.add_child(_skip_btn)
	_ok_btn = Button.new()
	_ok_btn.name = "GuideOk"
	_ok_btn.text = Tr.t("BTN_GUIDE_OK")
	_ok_btn.custom_minimum_size = Vector2(140, UITheme.MIN_BTN_H)
	_ok_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_ok_btn, UITheme.ACCENT.darkened(0.2), UITheme.FONT_BUTTON)
	_ok_btn.pressed.connect(func(): TutorialManager.finish_guide())
	_ok_btn.visible = false
	row.add_child(_ok_btn)

func _on_step_changed(step_id: String) -> void:
	_step = step_id
	_done_left = DONE_SECONDS if step_id == "done" else 0.0
	_ok_btn.visible = step_id == "done"
	_skip_btn.visible = step_id != "done"
	_render_text()

func _render_text() -> void:
	if _step == "":
		return
	var n := TutorialManager.step_number(_step)
	_badge.text = Tr.t("LBL_GUIDE_DONE_BADGE") if _step == "done" \
		else Tr.t("LBL_GUIDE_STEP") % [n, TutorialManager.GUIDE_TOTAL]
	_text.text = TutorialManager.step_text(_step)

func current_step() -> String:
	return _step

func is_coach_visible() -> bool:
	return _coach.visible

func coach_text() -> String:
	return _text.text

func skip_button() -> Button:
	return _skip_btn

## El rectangulo resaltado ahora (vacio si no hay control).
func highlight_rect() -> Rect2:
	return Rect2(_frame.position, _frame.size) if _frame.visible else Rect2()

## Algo mas importante esta en pantalla: el prologo, la pausa o el menu
## principal (el arbol en pausa), o una pelea.
func _should_hide() -> bool:
	if _step == "" or not TutorialManager.is_guide_active():
		return true
	if is_intro_open() or get_tree().paused:
		return true
	if CombatManager.is_board_open():
		return true
	return false

func _process(delta: float) -> void:
	if _should_hide():
		_coach.visible = false
		return
	_coach.visible = true
	_pulse += delta
	if _step == "done":
		_done_left -= delta
		if _done_left <= 0.0:
			TutorialManager.finish_guide()
			return
	_layout_step()

## Coloca velo, marco, flecha y tarjeta para el paso actual. Se repite cada
## frame: los controles se mueven (la lista de CONSTRUIR se abre, la camara se
## desplaza) y el foco tiene que seguirlos.
func _layout_step() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var target := TutorialManager.step_target(_step)
	var text := TutorialManager.step_text(_step)
	var rect := Rect2()
	var point := {}
	# CONSTRUIR es un boton grande siempre visible abajo (menu unico, #31): el
	# paso 1 lo senala a el directamente (grupo hud_build_button).
	if target == "forest":
		point = _forest_point(vp)
	elif target.begins_with("building:"):
		point = _building_point(target.substr(9))
	elif target != "":
		rect = HelpTargets.rect(get_tree(), target)
	if not point.is_empty() and not bool(point.get("ok", true)):
		text += "\n" + Tr.ti("GUIDE_MOVE_CAMERA")
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
	_card.custom_minimum_size = Vector2(w, 0)
	_card.size = Vector2(w, 0)
	_card.reset_size()
	var ch: float = _card.get_combined_minimum_size().y
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

## El bosque que toca senalar: el mas cercano al centro de la pantalla, o al
## Nucleo si ninguno se ve. {} si no hay mapa (pruebas).
func _forest_point(vp: Vector2) -> Dictionary:
	var gen := _scene_node("MapGenerator")
	if gen == null or not gen.has_method("get_all_deposits"):
		return {}
	var best := {}
	var best_d := INF
	var center := vp * 0.5
	for dep in gen.get_all_deposits():
		if String(dep.get("id", "")) != "forest":
			continue
		var cell := Vector2i(int(dep["cell_x"]), int(dep["cell_y"]))
		var sz := Vector2i(int(dep.get("size_x", 2)), int(dep.get("size_y", 2)))
		var sp := HelpTargets.cell_screen_point(get_viewport(), cell, sz)
		var p: Vector2 = sp["point"]
		var d: float = p.distance_to(center) + (0.0 if bool(sp["ok"]) else 100000.0)
		if d < best_d:
			best_d = d
			best = sp
	return best

func _building_point(building_id: String) -> Dictionary:
	for info in GridManager.get_all_buildings():
		var data: Resource = info.get("data")
		if data == null or String(data.get("id")) != building_id:
			continue
		var node: Node = info.get("node")
		if node != null and not node.has_meta("under_construction"):
			continue
		return HelpTargets.cell_screen_point(get_viewport(), info.get("origin_cell", Vector2i.ZERO), data.get("grid_size"))
	return {}

func _scene_node(node_name: String) -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var n := scene.get_node_or_null(node_name)
		if n != null:
			return n
	return null
