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
## Estilo nuevo (fase 2, docs/28 y la maqueta): la tarjeta es un BOCADILLO crema
## con tinta gruesa y su piquito hacia el busto de la Capitana (colonia) o del
## Sargento (combate). Arriba la pastilla "Paso N de M"; luego UNA frase grande
## (lo que hay que hacer) y, si algo lo impide, lo que falta en pequeno debajo.
## Botones por intencion (docs/28 §5): verde la accion principal, crema "Terminar
## repaso". Sin animaciones: el marco y el aro no laten y el texto sale entero.

const PrologueScene := preload("res://scenes/ui/PrologueScreen.tscn")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const CoachArrow := preload("res://scripts/ui/CoachArrow.gd")
const TypeCircleScript := preload("res://scripts/ui/TypeCircle.gd")
const InstructorBust := preload("res://scripts/ui/InstructorBust.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

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
## La franja de arriba con el HUD (recursos, rango, ☰ MENÚ): una tarjeta que
## solo cabe encima de su objetivo metiendose ahi se pone a su lado.
const TOP_HUD := 72.0
## Lineas de texto como mucho en la tarjeta (sin el rotulo), compose_card_text.
const CARD_MAX_LINES := 5
## Hueco entre la tarjeta del combate guiado y los avisos que aparta.
const AVOID_GAP := 12.0
## Pasos de espera (2026-10-19, queja de Bryan: "no es mi culpa no tener los
## recursos"): los que solo esperan recursos, produccion, obra o trabajadores
## (need_<id> y wait_<id>). Se ven FOLD_SECONDS y se pliegan a un recordatorio
## pequeno (la cara + "lo que falta"), sin flecha, aro ni velo, sin bloquear
## nada. Tocarlo los vuelve a abrir. Tras IDLE_REMIND_SECONDS sin cambios, el
## recordatorio se resalta (sin animacion ni sonido); nunca vuelve la tarjeta
## grande sola. Al cumplirse, el paso cambia y la tarjeta sale con su flecha.
const FOLD_SECONDS := 4.0
const IDLE_REMIND_SECONDS := 90.0
## La primera vez, un texto largo se ve algo mas (fold_seconds), hasta 8 s; y
## abierta a mano desde el recordatorio, REOPEN_SECONDS antes de replegarse.
const FOLD_SECONDS_MAX := 8.0
const FOLD_CHARS_PER_SECOND := 18.0
const REOPEN_SECONDS := 8.0
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _prologue: CanvasLayer
var _coach: Control
var _dim: Array[ColorRect] = []
var _frame: Panel
var _arrow: Control
var _ring: Control
var _card: PanelContainer
var _badge: Label
var _text: Label
## Lo que falta y como conseguirlo (las lineas 2+ de compose_card_text), en
## pequeno bajo la frase del paso.
var _detail: Label
## El piquito del bocadillo hacia el busto.
var _tail: Control
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
## Lo caro del paso (que control senala, su texto con lo que falta, que bosque)
## se busca cada RESOLVE_SECONDS, no en cada fotograma (docs/26 §6.9). Cada
## fotograma solo lee el rectangulo del control ya encontrado y proyecta la
## celda: asi sigue a la camara y a la lista de CONSTRUIR sin retraso.
const RESOLVE_SECONDS := 0.25
var _resolve_left := 0.0
var _res_text := ""
var _res_hint := ""
var _res_how := ""
## Solo falta otra Casa (TutorialManager.needs_house_only): sin hint ni how.
var _res_house_only := false
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
## El instructor que habla (feat/instructores, docs/23 §9): la Capitana
## Remache en la colonia, el Sargento Bombarda en el combate guiado. Pegado a
## la tarjeta (InstructorBust.dock_to); se encoge o se oculta si no cabe sin
## tapar lo senalado.
var _bust: Control
## El recordatorio plegado de un paso de espera.
var _chip: Button
var _chip_text: Label
var _later_btn: Button
var _folded := false
var _fold_left := 0.0
var _chip_idle := 0.0
var _chip_last := ""
var _chip_hot := false
## Pasos de espera cuya tarjeta ya salio una vez: si se vuelve a ellos (los
## recursos bajan y suben alrededor del coste), salen ya plegados.
var _seen_wait: Dictionary = {}
## La tarjeta de ahora es el "¡Ya puedes!" que sigue a una espera; y los pasos
## que ya lo tuvieron (sale UNA vez por paso).
var _ready_card := false
var _ready_done: Dictionary = {}
## El paso de ahora esperaba en el fotograma anterior (recoger cambia sin
## cambiar de paso: en cuanto hay madera).
var _was_waiting := false
var _step_before := ""

func _ready() -> void:
	layer = COACH_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tutorial_panel")
	_prologue = PrologueScene.instantiate()
	_prologue.name = "PrologueScreen"
	add_child(_prologue)
	_prologue.closed.connect(_on_prologue_closed)
	# La guia rapida se crea al pedirla (AYUDA > COMO FUNCIONA), no al arrancar:
	# ya no sale sola y casi nadie la abre (feat/topes-mejoras-ayuda).
	_build_coach()
	EventBus.tutorial_intro_requested.connect(_open_intro)
	EventBus.tutorial_step_changed.connect(_on_step_changed)
	EventBus.tutorial_guide_finished.connect(func(_skipped): _on_step_changed(""))
	EventBus.combat_lesson_step_changed.connect(_on_combat_step_changed)
	EventBus.instructors_visibility_changed.connect(func(on: bool):
		if not on:
			_bust.visible = false)
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

## La guia rapida (Como funciona). Ya no se abre sola; la abre el boton COMO
## FUNCIONA del indice de AYUDA (HelpIndexPanel). Se crea la primera vez.
func quick_guide() -> CanvasLayer:
	if _quick_guide == null:
		_quick_guide = QuickGuideScript.new()
		_quick_guide.name = "QuickGuide"
		add_child(_quick_guide)
		_quick_guide.closed.connect(func(): TutorialManager.mark_help_seen(QUICK_GUIDE_ID))
	return _quick_guide

func open_quick_guide() -> void:
	quick_guide().open()

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
	fs.border_color = CT.sem("ACCENT")
	fs.set_border_width_all(4)
	fs.set_corner_radius_all(12)
	fs.shadow_color = Color(CT.INK, 0.5)
	fs.shadow_size = 2
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.add_child(_frame)

	# Un aro para senalar un punto del mapa (el bosque, la obra).
	_ring = Panel.new()
	_ring.name = "Ring"
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(CT.sem("ACCENT"), 0.15)
	rs.border_color = CT.sem("ACCENT")
	rs.set_border_width_all(4)
	rs.set_corner_radius_all(40)
	_ring.add_theme_stylebox_override("panel", rs)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(80, 80)
	_ring.pivot_offset = Vector2(40, 40)
	_coach.add_child(_ring)

	_arrow = CoachArrow.new()
	_arrow.name = "Arrow"
	_arrow.set("color", CT.sem("ACCENT"))
	_coach.add_child(_arrow)

	_card = PanelContainer.new()
	_card.name = "CoachCard"
	# Los avisos (NotificationPanel) esperan si la tarjeta cae sobre su columna.
	_card.add_to_group("alert_blocker")
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", CT.bubble_style())
	_coach.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)

	# "Paso 3 de 9": una pastilla de laton pequena.
	var pill := PanelContainer.new()
	pill.name = "BadgePill"
	var ps := CT.box(CT.sem("ACCENT"), CT.INK, 2, 12, 0)
	ps.content_margin_left = 10
	ps.content_margin_right = 10
	ps.content_margin_top = 0
	ps.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", ps)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pill)
	_badge = CT.label("", "small", CT.INK)
	_badge.name = "Badge"
	pill.add_child(_badge)
	_text = CT.para("", "window", false, "title")
	_text.name = "Instruction"
	col.add_child(_text)
	_detail = CT.para("", "window", true, "small")
	_detail.name = "Detail"
	_detail.visible = false
	col.add_child(_detail)
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
	_end_replay_btn = CT.text_button(Tr.t("BTN_GUIDE_END_REPLAY"), "", "secondary", CT.menu_h("small"), "body")
	_end_replay_btn.name = "EndReplay"
	_end_replay_btn.focus_mode = Control.FOCUS_NONE
	_end_replay_btn.pressed.connect(func(): TutorialManager.stop_replay())
	_end_replay_btn.visible = false
	row.add_child(_end_replay_btn)
	# La accion de la tarjeta: verde (docs/28 §5).
	_ok_btn = CT.text_button(Tr.t("BTN_GUIDE_OK"), "check", "primary", CT.menu_h("btn"))
	_ok_btn.name = "GuideOk"
	_ok_btn.focus_mode = Control.FOCUS_NONE
	_ok_btn.pressed.connect(_on_ok_pressed)
	_ok_btn.visible = false
	row.add_child(_ok_btn)
	# Combate guiado: solo "Entendido" (el circulo). Sin "Saltar" (2026-10-16).
	_combat_ok_btn = CT.text_button(Tr.t("BTN_CGUIDE_OK"), "check", "primary", CT.menu_h("btn"))
	_combat_ok_btn.name = "CombatOk"
	_combat_ok_btn.focus_mode = Control.FOCUS_NONE
	_combat_ok_btn.pressed.connect(func(): TutorialManager.close_combat_step(_cstep))
	_combat_ok_btn.visible = false
	row.add_child(_combat_ok_btn)

	# "Mas tarde": pliega ya un paso de espera.
	_later_btn = CT.text_button(Tr.t("BTN_GUIDE_LATER"), "", "secondary", CT.menu_h("small"), "body")
	_later_btn.name = "GuideLater"
	_later_btn.focus_mode = Control.FOCUS_NONE
	_later_btn.pressed.connect(func(): set_folded(true))
	_later_btn.visible = false
	row.add_child(_later_btn)
	row.move_child(_later_btn, 0)

	_build_chip()

	_bust = InstructorBust.new()
	_bust.name = "Instructor"
	_bust.visible = GameConfig.ui_instructors_visible
	_coach.add_child(_bust)
	_tail = CT.Tail.new()
	_tail.name = "Tail"
	_tail.visible = false
	_coach.add_child(_tail)

## El recordatorio: [cara] "Junta 120 oro · 45/120". Un boton: tocarlo abre.
func _build_chip() -> void:
	_chip = Button.new()
	_chip.name = "GuideReminder"
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.visible = false
	_chip.tooltip_text = Tr.t("LBL_GUIDE_REMINDER_TIP")
	_chip.pressed.connect(func(): set_folded(false))
	_coach.add_child(_chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var face := CT.captain_face(34 if CT.is_phone() else 42)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)
	_chip_text = CT.label("", "body", CT.text("hud"))
	_chip_text.name = "ReminderText"
	_chip_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_text.clip_text = true
	_chip_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_chip_text)
	CT.fit_button_content(_chip, row, 6.0)
	_style_chip(false)

func _style_chip(hot: bool) -> void:
	_chip_hot = hot
	var st := CT.hud_style(CT.sem("ACCENT") if hot else Color(0, 0, 0, 0))
	if hot:
		st.set_border_width_all(4)
	for s in ["normal", "hover", "pressed", "focus"]:
		_chip.add_theme_stylebox_override(s, st)

## Si el paso solo espera (recursos, produccion, obra, trabajadores).
static func is_waiting_step(step_id: String) -> bool:
	return TutorialManager.is_need_step(step_id) or step_id.begins_with("wait_")

## Si el paso de ahora solo espera, mirando tambien lo que hay: recoger es un
## paso de espera mientras el Aserradero aun no ha cortado nada (no hay icono
## que tocar); en cuanto tiene madera, es un paso de accion (feat/ui3-tutorial).
func is_waiting_now() -> bool:
	if is_waiting_step(_step):
		return true
	return _step == "collect" and not _sawmill_has_wood()

func _sawmill_has_wood() -> bool:
	for info in GridManager.buildings_view():
		var d: Resource = info.get("data")
		var node: Node = info.get("node")
		if d == null or node == null or String(d.get("id")) != "sawmill":
			continue
		if int(ProductionManager.get_stock(node).get("wood", 0)) > 0:
			return true
	return false

## Se puede plegar ahora: un paso de espera, o el "¡Ya puedes!" que lo sigue.
func can_fold() -> bool:
	return is_waiting_now() or _ready_card

## Pliega (true) o abre (false) la tarjeta de un paso de espera.
func set_folded(folded: bool) -> void:
	if folded and not can_fold():
		return
	if not folded and _folded:
		# Abierta a mano desde el recordatorio: un rato mas para leerla.
		_fold_left = REOPEN_SECONDS
	_folded = folded
	if folded:
		_seen_wait[_step] = true
	_chip_idle = 0.0
	_style_chip(false)

func is_folded() -> bool:
	return _folded

## La tarjeta es el "¡Ya puedes!" que sigue a una espera (sale una vez).
func is_ready_card() -> bool:
	return _ready_card

func reminder() -> Button:
	return _chip

func reminder_text() -> String:
	return _chip_text.text if _chip_text != null else ""

## Lo que dice el recordatorio, en UNA linea corta: el paso de ahora de la
## lista ("Junta oro 45/80"), la obra ("Obra: Aserradero 40 %"), "Aserradero
## cortando madera..." o, tras la espera, "¡Ya puedes! Pulsa CONSTRUIR".
func _reminder_line() -> String:
	if _ready_card:
		var what := "TUT3_READY_DO"
		if _step == "collect":
			what = "TUT3_READY_COLLECT"
		elif TutorialManager.step_target(_step) == "build_button":
			what = "TUT3_READY_BUILD"
		return Tr.t("TUT3_CHIP_READY") % Tr.t(what)
	if TutorialManager.is_need_step(_step):
		var cur: Dictionary = TutorialManager.need_plan(TutorialManager.step_building(_step)).get("current", {})
		var short := String(cur.get("short", cur.get("text", "")))
		if short != "":
			return short
		return TutorialManager.step_text(_step)
	if _step.begins_with("wait_"):
		var b := _step.substr(5)
		var data := Rules.load_building_data(b)
		var bname: String = data.get_display_name() if data != null else b
		for info in GridManager.buildings_view():
			var d: Resource = info.get("data")
			var node: Node = info.get("node")
			if d != null and node != null and String(d.get("id")) == b and ProductionManager.is_constructing(node):
				return Tr.t("TUT3_CHIP_WORK") % [bname, roundi(ProductionManager.get_construction_progress(node) * 100.0)]
		return Tr.t("TUT3_CHIP_WORK_WAIT") % bname
	if _step == "collect":
		var saw := Rules.load_building_data("sawmill")
		return Tr.t("TUT3_CHIP_COLLECT_WAIT") % (saw.get_display_name() if saw != null else "sawmill")
	var main := _res_text.split("
", false)
	return String(main[0]) if not main.is_empty() else ""

## Cuanto se ve la tarjeta de un paso de espera la primera vez antes de
## plegarse: FOLD_SECONDS, algo mas si su texto es largo (la carretera de la
## obra del Aserradero), nunca mas de FOLD_SECONDS_MAX. Pura.
static func fold_seconds(text_s: String) -> float:
	return clampf(float(text_s.length()) / FOLD_CHARS_PER_SECOND, FOLD_SECONDS, FOLD_SECONDS_MAX)

## Coloca el recordatorio donde vive la linea del siguiente paso (que se oculta
## con el tutorial en marcha) y esconde todo lo demas.
func _layout_folded(delta: float) -> void:
	for r in _dim:
		r.visible = false
	_frame.visible = false
	_arrow.visible = false
	_ring.visible = false
	_card.visible = false
	_tail.visible = false
	_bust.visible = false
	# Con CONSTRUIR (o cualquier ventana) abierto, el recordatorio no se pone
	# encima de su lista: espera a que se cierre.
	_chip.visible = UIManager.open_windows().is_empty()
	var line := _reminder_line()
	if line != _chip_last:
		_chip_last = line
		_chip_idle = 0.0
		if _chip_hot:
			_style_chip(false)
	if _chip_text.text != line:
		_chip_text.text = line
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w := minf(_chip_text.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_chip_text.get_theme_font_size("font_size")).x + 2.0, vp.x * 0.5)
	if absf(_chip_text.custom_minimum_size.x - w) > 0.5:
		_chip_text.custom_minimum_size.x = w
		_chip.reset_size()
	var m: Dictionary = UILayoutManager.get_slot("next_step").get("margin", {})
	var left := float(m.get("left", 12.0))
	var bottom := float(m.get("bottom", 90.0))
	_chip.position = Vector2(left, vp.y - bottom - _chip.size.y)
	_chip_idle += delta
	if _chip_idle >= IDLE_REMIND_SECONDS and not _chip_hot:
		_style_chip(true)

## La tarjeta del paso de accion que sigue a una espera: se abre UNA vez con
## su flecha y el rotulo "¡Ya puedes!".
func _enter_ready() -> void:
	_ready_card = true
	_folded = false
	_ready_done[_step] = true
	_update_later_btn()
	_render_text()

func _update_later_btn() -> void:
	if _later_btn != null:
		_later_btn.visible = _step != "" and can_fold()

## Cambia el texto de una pastilla (su etiqueta y la meta "text").
static func set_button_text(b: Button, text_s: String) -> void:
	b.set_meta("text", text_s)
	for l in b.find_children("*", "Label", true, false):
		(l as Label).text = text_s
		return

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
	# Paso de espera: se ve un rato y se pliega; si ya salio una vez, sale
	# plegado. Paso de accion: abierto; el primero tras una espera es el
	# "¡Ya puedes!" (una vez por paso), que tambien se puede plegar.
	var came_from_wait := _was_waiting and _step_before != "" and _step_before != step_id
	_step_before = step_id
	_ready_card = false
	_folded = false
	_was_waiting = is_waiting_now() if step_id != "" else false
	if step_id == "" or step_id == "done":
		_seen_wait.clear()
		_ready_done.clear()
	elif _was_waiting:
		_folded = bool(_seen_wait.get(step_id, false))
	elif came_from_wait and not bool(_ready_done.get(step_id, false)):
		_enter_ready()
	_fold_left = fold_seconds(TutorialManager.step_text(step_id))
	_chip_idle = 0.0
	if _chip != null:
		_style_chip(false)
		_chip.visible = false
	_update_later_btn()
	var reading: bool = TutorialManager.step_has_ok(step_id)
	_ok_btn.visible = step_id == "done" or reading
	set_button_text(_ok_btn, TutorialManager.step_ok_text(step_id) if reading else Tr.t("BTN_GUIDE_OK"))
	_end_replay_btn.visible = step_id != "done" and TutorialManager.is_replay()
	# El paso de reparar ensena lo que cuesta reparar (no un edificio de datos).
	# En "consigue lo que falta" no van las cifras del edificio: la tarjeta habla
	# de lo que falta y asi no pasa de unas cinco lineas (feat/hud-y-tutorial).
	var facts_for := TutorialManager.step_building(step_id)
	if step_id == TutorialManager.REPAIR_STEP:
		facts_for = "__repair__"
	elif TutorialManager.is_need_step(step_id):
		facts_for = ""
	_render_facts(facts_for)
	_render_text()
	# La Capitana lo dice: su cara del paso. El texto sale entero (docs/28 §0.6).
	if step_id != "" and _cstep == "":
		_bust.show_as(InstructorBust.COLONY, InstructorBust.expression_for_step(step_id), _bust.facing)

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
		if _ready_card:
			_badge.text = Tr.t("TUT3_READY_BADGE") + _badge.text
	_set_card_text(TutorialManager.step_text(_step))

## La frase del paso (la primera linea) en grande y el resto (lo que falta y como
## conseguirlo) en pequeno debajo.
func _set_card_text(full: String) -> void:
	var lines := full.split("\n", false)
	var main := String(lines[0]) if not lines.is_empty() else ""
	var rest := "\n".join(lines.slice(1)) if lines.size() > 1 else ""
	if _text.text != main:
		_text.text = main
	if _detail.text != rest:
		_detail.text = rest
	_detail.visible = rest != ""

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
		var l := CT.label(String(f["text"]), "small", CT.text("window"))
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

## El texto entero de la tarjeta: la frase y lo que falta debajo.
func coach_text() -> String:
	if _detail != null and _detail.text != "":
		return _text.text + "\n" + _detail.text
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
	if _step == "done":
		_done_left -= delta
		if _done_left <= 0.0:
			TutorialManager.finish_guide()
			return
	_resolve_left -= delta
	var waiting := is_waiting_now()
	if waiting != _was_waiting:
		_was_waiting = waiting
		# Recoger: el Aserradero ya tiene madera. Mismo paso, ya es de accion.
		if not waiting and not bool(_ready_done.get(_step, false)):
			_enter_ready()
		elif not waiting:
			_folded = false
		_update_later_btn()
	if waiting and not _folded:
		_fold_left -= delta
		if _fold_left <= 0.0:
			set_folded(true)
	if _folded:
		if _resolve_left <= 0.0:
			_resolve_step()
		_layout_folded(delta)
		return
	_chip.visible = false
	_card.visible = true
	_bust.visible = GameConfig.ui_instructors_visible
	for r in _dim:
		r.visible = true
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
	# "Deja de colocar" solo si aun lleva la carretera en la mano (ronda 1.0).
	if _step == "demolish" and TutorialManager.is_placing():
		text = Tr.ti("GUIDE_DEMOLISH_STOP") + " " + text
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
	# Desde 2026-10-19 la otra Casa es un paso de la lista (step_hint): nada
	# que callar.
	_res_house_only = false

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
	if not point.is_empty() and bool(point.get("ok", true)) and _under_hud(point["point"]):
		point = point.duplicate()
		point["ok"] = false
	var camera := not point.is_empty() and not bool(point.get("ok", true))
	var hint := _res_hint
	var how := _res_how
	# Solo falta otra Casa: la frase del paso ya lo dice todo (GUIDE_NEED_HOUSE).
	if _res_house_only:
		hint = ""
		how = ""
	text = compose_card_text(text, hint, how, camera)
	_set_card_text(text)

	var has_rect := rect.size.x > 1.0 and rect.size.y > 1.0
	if has_rect:
		rect = rect.grow(HOLE_PAD)
	_place_dim(vp, rect if has_rect else Rect2())
	_frame.visible = has_rect
	if has_rect:
		_frame.position = rect.position
		_frame.size = rect.size

	# La tarjeta, junto a lo senalado (debajo si cabe, si no encima), sin taparlo.
	var w: float = minf(CARD_WIDTH, vp.x - EDGE * 2.0)
	# Medir la tarjeta (reset_size + tamano minimo) solo si cambia su texto, su
	# ancho o los botones; cada fotograma era trabajo de maquetado para nada.
	var key := "%s|%s|%d|%s|%s|%s" % [_badge.text, text, int(w), _ok_btn.visible, _end_replay_btn.visible, _facts_for]
	var ch: float = _fit_card(w, key)
	var focus := Rect2()
	if has_rect:
		focus = rect
	elif not point.is_empty() and bool(point.get("ok", true)):
		# Fuera de pantalla no hay foco: la tarjeta va a su sitio de siempre y
		# la flecha del borde senala hacia alli (antes se iba por debajo).
		focus = Rect2(point["point"] - Vector2(40, 40), Vector2(80, 80))
	# Colocando con el dedo, el fantasma y su ✓ CONSTRUIR AQUI (#34) tampoco se
	# tapan: la tarjeta se aparta de los dos juntos.
	focus = with_confirm(focus, _confirm_rect())
	_card.position = card_position(vp, Vector2(w, ch), focus, _step in TutorialManager.INFO_PANEL_STEPS and has_rect)
	if focus.size == Vector2.ZERO:
		# Sin foco va centrada abajo: que no tape la orden de la Regencia cuando
		# la Tormenta baja a la columna izquierda (tablet 4:3, movil; ronda
		# visual de la 1.1). Se corre a la derecha lo que haga falta y quepa.
		var storm := _storm_rect()
		_card.position.x += InstructorBust.centered_card_shift(vp, w, storm, _card.position.y)
	_bust.dock_to(vp, Rect2(_card.position, Vector2(w, ch)), [focus, _storm_rect()], TOP_HUD)
	CT.place_tail(_tail, Rect2(_card.position, Vector2(w, ch)), _bust)

	# Flecha y aro.
	_ring.visible = false
	_arrow.visible = false
	if has_rect:
		var above := _card.position.y < rect.position.y
		var tip := Vector2(rect.get_center().x, rect.position.y - 4.0) if above \
			else Vector2(rect.get_center().x, rect.end.y + 4.0)
		var dir := Vector2.DOWN if above else Vector2.UP
		# La tarjeta al lado (card_position, junto al HUD de arriba): flecha de lado.
		if _card.position.x + _card.size.x <= rect.position.x:
			tip = Vector2(rect.position.x - 4.0, rect.get_center().y)
			dir = Vector2.RIGHT
		elif _card.position.x >= rect.end.x:
			tip = Vector2(rect.end.x + 4.0, rect.get_center().y)
			dir = Vector2.LEFT
		_arrow.visible = true
		_arrow.point_at(tip, dir)
	elif not point.is_empty():
		var p: Vector2 = point["point"]
		if bool(point.get("ok", true)):
			_ring.visible = true
			_ring.position = p - _ring.size * 0.5
			_arrow.visible = true
			_arrow.point_at(p - Vector2(0, 44), Vector2.DOWN)
		else:
			# Fuera de pantalla: la flecha en el borde, hacia donde esta.
			var c := vp * 0.5
			var dir := (p - c).normalized()
			var edge := _edge_point(c, dir, vp, 60.0)
			# Nunca encima de la barra de abajo (en telefono caia junto a Ejercito)
			# ni del HUD de arriba.
			var bar := get_tree().get_first_node_in_group("bottom_bar")
			var bar_top := vp.y - (float(CT.bar_round()) + 40.0)
			if bar != null and bar.get("_dock") is Control and (bar.get("_dock") as Control).is_visible_in_tree():
				bar_top = minf(bar_top, (bar.get("_dock") as Control).get_global_rect().position.y - 16.0)
			edge.y = clampf(edge.y, TOP_HUD + 16.0, maxf(TOP_HUD + 16.0, bar_top))
			_arrow.visible = true
			_arrow.point_at(edge, dir)

## El texto de la tarjeta: la frase del paso, lo que falta (hint), como
## conseguirlo (how) y, si lo senalado no se ve, "arrastra el mapa hacia la
## flecha" AL FINAL (antes salia en medio, ronda 1.0). Como mucho
## CARD_MAX_LINES lineas (sin contar el rotulo PASO N DE M): las de "como
## conseguirlo" que no quepan se quedan fuera (siempre queda al menos una).
## Publica y pura para las pruebas.
static func compose_card_text(main: String, hint: String, how: String, camera: bool) -> String:
	var lines: Array = [main]
	lines.append_array(hint.split("\n", false))
	var how_lines: PackedStringArray = how.split("\n", false)
	if not how_lines.is_empty():
		var room := CARD_MAX_LINES - lines.size() - (1 if camera else 0)
		lines.append_array(Array(how_lines).slice(0, maxi(1, room)))
	if camera:
		lines.append(Tr.ti("GUIDE_MOVE_CAMERA"))
	return "\n".join(lines)

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

## `p` cae debajo de la tarjeta de recursos o del rango (arriba): lo que se
## senala ahi no se ve (feat/ui3-tutorial).
func _under_hud(p: Vector2) -> bool:
	for id in ["ResourceHUD", "RankPanel"]:
		var c: Control = HudRegistry.control_of(id)
		if c != null and is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(24.0).has_point(p):
			return true
	return false

## La Tormenta (y su orden) a la vista, o Rect2() si no.
func _storm_rect() -> Rect2:
	var c: Control = HudRegistry.control_of("StormHUD")
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()

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
static func card_position(vp: Vector2, size: Vector2, focus: Rect2, prefer_side: bool = false) -> Vector2:
	if focus.size == Vector2.ZERO:
		# Nunca por encima del borde: en un telefono la tarjeta alta de reparar
		# subia hasta cortar su rotulo (ronda visual de la 1.1).
		return Vector2((vp.x - size.x) * 0.5, maxf(EDGE, vp.y - size.y - 110.0))
	var x := clampf(focus.get_center().x - size.x * 0.5, EDGE, vp.x - size.x - EDGE)
	var side_y := clampf(focus.get_center().y - size.y * 0.5, TOP_HUD, maxf(TOP_HUD, vp.y - size.y - EDGE))
	var left := Vector2(focus.position.x - ARROW_GAP - size.x, side_y)
	var right := Vector2(focus.end.x + ARROW_GAP, side_y)
	var below := Vector2(x, focus.end.y + ARROW_GAP)
	var above := Vector2(x, focus.position.y - ARROW_GAP - size.y)
	# Encima, pegada a la franja del HUD si hace falta (nunca sobre ella: tapaba
	# el nombre del pais y ☰ MENÚ, ronda de pruebas 1.0).
	var above_hud := Vector2(x, maxf(above.y, TOP_HUD))
	# Orden de preferencia: debajo, encima, a un lado. En una ficha (mover,
	# derribar, reparar: `prefer_side`) primero al lado: debajo, la flecha caia
	# sobre el boton siguiente (MOVER señalaba Demoler).
	var order: Array = [below, above, left, right]
	if prefer_side:
		order = [left, right, below, above]
	var screen := Rect2(Vector2(EDGE, EDGE), vp - Vector2(EDGE, EDGE) * 2.0)
	for p in order:
		var r := Rect2(p, size)
		if screen.encloses(r) and r.position.y >= (TOP_HUD if p != below else EDGE):
			return p
	# Nada cabe entero: encima sin pisar el HUD si no tapa lo señalado; si no,
	# donde menos lo tape.
	if not Rect2(above_hud, size).intersects(focus) and above_hud.y + size.y <= vp.y - EDGE:
		return above_hud
	var best := Vector2(x, clampf(above.y, EDGE, maxf(EDGE, vp.y - size.y - EDGE)))
	var best_area := INF
	for p in [above_hud, below, left, right]:
		var c := Vector2(clampf(p.x, EDGE, maxf(EDGE, vp.x - size.x - EDGE)), clampf(p.y, EDGE, maxf(EDGE, vp.y - size.y - EDGE)))
		var inter := Rect2(c, size).intersection(focus)
		var area := inter.get_area() if Rect2(c, size).intersects(focus) else 0.0
		if area < best_area:
			best_area = area
			best = c
	return best

func _place_dim(vp: Vector2, hole: Rect2) -> void:
	if hole.size == Vector2.ZERO:
		# Sin control que resaltar no se oscurece nada: el mapa es el objetivo.
		for r in _dim:
			r.visible = false
		return
	# Los bordes, en unidades enteras del lienzo: los controles se pegan a la
	# rejilla al colocarse (snap_controls_to_pixels) pero su tamano no, y con
	# bordes fraccionarios dos rectangulos que se tocan dejaban una raya de un
	# pixel a lo ancho de toda la pantalla (ronda de pruebas 1.0).
	var top := roundf(clampf(hole.position.y, 0.0, vp.y))
	var bottom := roundf(clampf(hole.end.y, 0.0, vp.y))
	var left := roundf(clampf(hole.position.x, 0.0, vp.x))
	var right := roundf(clampf(hole.end.x, 0.0, vp.x))
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
		# Uno escondido bajo el HUD de arriba (recursos, rango) cuenta casi como
		# fuera de pantalla: el aro y la flecha caian encima de los numeros.
		var hidden := bool(sp["ok"]) and _under_hud(p)
		var d: float = p.distance_to(center) + (0.0 if bool(sp["ok"]) else 100000.0) + (50000.0 if hidden else 0.0)
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
		_set_card_text(TutorialManager.combat_step_text(step_id))
		# El Sargento Bombarda lleva el combate guiado.
		_bust.show_as(InstructorBust.COMBAT, InstructorBust.expression_for_combat_step(step_id), _bust.facing)
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

## El busto del instructor (pruebas).
func instructor() -> Control:
	return _bust

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

	var w: float = minf(CARD_WIDTH, vp.x - EDGE * 2.0)
	var key := "%s|%s|%d|%s|%s" % [_badge.text, _text.text, int(w), _combat_ok_btn.visible, _circle.visible]
	var focus := Rect2()
	if has_rect:
		focus = rect
	elif has_point:
		focus = Rect2(Vector2(anchor["point"]) - Vector2(40, 40), Vector2(80, 80))
	var avoid := _combat_avoid_rects(bs)
	var lay: Dictionary = bs.coach_layout() if bs != null and bs.has_method("coach_layout") else {}
	# La cabecera, la franja de turnos y los botones tampoco se tapan.
	avoid.append_array(lay.get("keep", []))
	# Fuera del tablero si hay sitio (a un lado, encima o debajo, mas estrecha
	# si hace falta); si no, junto a lo senalado sin tapar las piezas.
	var spot := _combat_spot(vp, lay, focus, avoid, key)
	if not spot.is_empty():
		w = float(spot["w"])
		_fit_card(w, key + "|%d" % int(w))
		_card.position = spot["pos"]
	else:
		_fit_card(w, key)
		var keep_clear: Array = avoid.duplicate()
		keep_clear.append_array(lay.get("units", []))
		_card.position = clear_of(combat_card_position(vp, Vector2(w, _card_h), focus),
			Vector2(w, _card_h), keep_clear, vp, focus)
	avoid.append(focus)
	if lay.has("board") and (lay["board"] as Rect2).size.x > 1.0 and not spot.is_empty():
		# El busto tampoco se pone encima del tablero (si no cabe, no sale).
		avoid.append(lay["board"])
	_bust.dock_to(vp, Rect2(_card.position, Vector2(w, _card_h)), avoid)
	CT.place_tail(_tail, Rect2(_card.position, Vector2(w, _card_h)), _bust)

	_ring.visible = false
	_arrow.visible = false
	if has_rect:
		var above := _card.position.y < rect.position.y
		var tip := Vector2(rect.get_center().x, rect.position.y - 4.0) if above \
			else Vector2(rect.get_center().x, rect.end.y + 4.0)
		var dir := Vector2.DOWN if above else Vector2.UP
		# La tarjeta al lado (card_position, junto al HUD de arriba): flecha de lado.
		if _card.position.x + _card.size.x <= rect.position.x:
			tip = Vector2(rect.position.x - 4.0, rect.get_center().y)
			dir = Vector2.RIGHT
		elif _card.position.x >= rect.end.x:
			tip = Vector2(rect.end.x + 4.0, rect.get_center().y)
			dir = Vector2.LEFT
		_arrow.visible = true
		_arrow.point_at(tip, dir)
	elif has_point:
		var pt: Vector2 = anchor["point"]
		_ring.visible = true
		_ring.position = pt - _ring.size * 0.5
		_arrow.visible = true
		_arrow.point_at(pt - Vector2(0, 44), Vector2.DOWN)

## La tarjeta del combate guiado no tapa el tablero (QA de tablet, 2026-10-26:
## a 1280x800 el Sargento cubria las filas 2-5, enemigos incluidos). Busca, en
## este orden, un sitio fuera de `lay["board"]` y entre la fila de turnos y los
## botones: a un lado (el del foco primero, con el ancho que quepa y no menos
## de COMBAT_SIDE_MIN_W), encima o debajo del tablero (a lo ancho). Ninguno de
## `avoid` (avisos, ficha de la unidad). {"pos", "w"}, o {} si no hay sitio
## (vista Frente, tablero a toda pantalla): entonces se coloca junto al foco.
## Se recuerda mientras no cambie nada (medir la tarjeta a otro ancho la
## reordena: no se hace cada fotograma).
const COMBAT_SIDE_MIN_W := 200.0
var _spot_key := ""
var _spot: Dictionary = {}

func _combat_spot(vp: Vector2, lay: Dictionary, focus: Rect2, avoid: Array, text_key: String) -> Dictionary:
	var board: Rect2 = lay.get("board", Rect2())
	if board.size.x <= 1.0 or board.size.y <= 1.0:
		return {}
	var top: float = maxf(EDGE, float(lay.get("top", 0.0)) + 4.0)
	var bottom: float = minf(vp.y - EDGE, float(lay.get("bottom", vp.y)) - 4.0)
	var skey := "%s|%s|%s|%s|%d|%d|%s" % [text_key, str(vp.round()), str(board.position.round()), str(board.size.round()),
		int(top), int(bottom), str(focus.get_center().round())]
	for r in avoid:
		skey += str((r as Rect2).position.round())
	if skey == _spot_key:
		return _spot
	_spot_key = skey
	_spot = combat_spot_off_board(vp, board, top, bottom, focus, avoid,
		func(width: float) -> float: return _fit_card(width, text_key + "|%d" % int(width)))
	return _spot

## Pura salvo por `height_for` (ancho -> alto de la tarjeta a ese ancho), para
## las pruebas. Ver _combat_spot.
static func combat_spot_off_board(vp: Vector2, board: Rect2, top: float, bottom: float, focus: Rect2,
		avoid: Array, height_for: Callable) -> Dictionary:
	var grown: Array = []
	for r in avoid:
		if (r as Rect2).size.x > 1.0 and (r as Rect2).size.y > 1.0:
			grown.append((r as Rect2).grow(AVOID_GAP))
	var clear := func(card: Rect2) -> bool:
		if card.position.x < EDGE - 0.5 or card.end.x > vp.x - EDGE + 0.5:
			return false
		if card.position.y < top - 0.5 or card.end.y > bottom + 0.5:
			return false
		if card.intersects(board.grow(AVOID_GAP - 0.5)):
			return false
		for g in grown:
			if card.intersects(g):
				return false
		return true
	var fy: float = focus.get_center().y if focus.size != Vector2.ZERO else (top + bottom) * 0.5
	var fx: float = focus.get_center().x if focus.size != Vector2.ZERO else vp.x * 0.5
	# A un lado: primero el mas cercano al foco.
	var left_room: float = board.position.x - AVOID_GAP - EDGE
	var right_room: float = vp.x - EDGE - board.end.x - AVOID_GAP
	var sides := [["left", left_room], ["right", right_room]]
	if fx > board.get_center().x:
		sides.reverse()
	for s in sides:
		var w: float = minf(CARD_WIDTH, float(s[1]))
		if w < COMBAT_SIDE_MIN_W:
			continue
		var h: float = float(height_for.call(w))
		var x: float = board.position.x - AVOID_GAP - w if s[0] == "left" else board.end.x + AVOID_GAP
		var y: float = clampf(fy - h * 0.5, top, maxf(top, bottom - h))
		var card := Rect2(x, y, w, h)
		if clear.call(card):
			return {"pos": card.position, "w": w}
		# La ficha de la unidad (o un aviso) en ese lado: arriba o abajo del hueco.
		for yy in [top, bottom - h]:
			card.position.y = yy
			if clear.call(card):
				return {"pos": card.position, "w": w}
	# Encima o debajo, a lo ancho (centrada sobre el foco).
	var wide: float = minf(CARD_WIDTH, vp.x - EDGE * 2.0)
	var hw: float = float(height_for.call(wide))
	var cx: float = clampf(fx - wide * 0.5, EDGE, maxf(EDGE, vp.x - wide - EDGE))
	for y in [board.position.y - AVOID_GAP - hw, board.end.y + AVOID_GAP]:
		var card := Rect2(cx, y, wide, hw)
		if clear.call(card):
			return {"pos": card.position, "w": wide}
	return {}

## Lo que la tarjeta del combate guiado no debe tapar, a la izquierda del
## tablero: los avisos (NotificationPanel, capa 19 como esta) y la ficha de la
## unidad tocada (BattleScreen). Solo si se ven y tienen algo dentro.
func _combat_avoid_rects(bs: Node) -> Array:
	var out: Array = []
	var toasts := HudRegistry.control_of("NotificationPanel.toasts")
	if toasts != null and toasts.is_visible_in_tree():
		for t in toasts.get_children():
			if t is Control and (t as Control).visible and not t.is_queued_for_deletion():
				out.append(toasts.get_global_rect())
				break
	if bs != null and bs.has_method("unit_card"):
		var uc: Control = bs.unit_card()
		if uc != null and uc.is_visible_in_tree():
			out.append(uc.get_global_rect())
	return out

## `pos` movida para que la tarjeta de `size` no pise ninguno de `avoid`: a su
## derecha (los avisos y la ficha van a la izquierda), encima o debajo; la
## primera que cabe en pantalla sin tapar `focus` ni otro aviso. Si ninguna
## cabe, se queda donde estaba (lo senalado manda). Publica para las pruebas.
static func clear_of(pos: Vector2, size: Vector2, avoid: Array, vp: Vector2, focus: Rect2) -> Vector2:
	var grown: Array = []
	for r in avoid:
		if (r as Rect2).size.x > 1.0 and (r as Rect2).size.y > 1.0:
			grown.append((r as Rect2).grow(AVOID_GAP))
	var screen := Rect2(Vector2(EDGE, EDGE), vp - Vector2(EDGE, EDGE) * 2.0)
	var fits := func(p: Vector2) -> bool:
		var card := Rect2(p, size)
		if not screen.encloses(card):
			return false
		if focus.size != Vector2.ZERO and card.intersects(focus):
			return false
		for g in grown:
			if card.intersects(g):
				return false
		return true
	var card_now := Rect2(pos, size)
	var hit := false
	for g in grown:
		if card_now.intersects(g):
			hit = true
			break
	if not hit:
		return pos
	for g in grown:
		var r: Rect2 = g
		for p in [Vector2(r.end.x, pos.y), Vector2(pos.x, r.position.y - size.y), Vector2(pos.x, r.end.y),
				Vector2(r.end.x, clampf(pos.y, EDGE, maxf(EDGE, vp.y - size.y - EDGE)))]:
			if fits.call(p):
				return p
	return pos

## Donde va la tarjeta en el combate: junto a lo senalado como en la colonia;
## sin nada que senalar (el circulo), arriba al centro, lejos de los botones de
## abajo. Publica para las pruebas.
static func combat_card_position(vp: Vector2, size: Vector2, focus: Rect2) -> Vector2:
	if focus.size == Vector2.ZERO:
		return Vector2((vp.x - size.x) * 0.5, maxf(EDGE, vp.y * 0.16))
	return card_position(vp, size, focus)
