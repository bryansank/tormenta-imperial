extends CanvasLayer
## La victoria: una ventana crema con la cinta verde, la bandera y el nombre del
## pais, una frase y las cifras de la partida como icono + numero (el nombre
## debajo, en pequeno). Sin animacion: sale de golpe (docs/28 §0.6).
##
##   [bandera] Monte Biela
##   ( VICTORIA IMPERIAL )
##   La Regencia bajo a cobrar y se fue sin nada...
##   [reloj] 3 h 05   [casa] 30   [mercado] 12   [estrella] 9
##   [tormenta] 11    [check] 9   [misiones] 2
##   [ EL LIBRO > ]  [ Nueva partida ]        (Campana / Supervivencia)
##   [ SEGUIR JUGANDO ]  [ Nueva partida ]    (Constructor)
##
## Final con eleccion (v1.2, decision de Bryan 2026-10-25): donde el modo tiene
## la fase del imperio (GameMode.empire_enabled), EL LIBRO lleva a la mesa: el
## libro del Impuesto, y dos tarjetas con lo que dicen los instructores:
##   FIRMAR  (Sargento Bombarda) -> "AHORA FIRMAS TU": el archipielago.
##   QUEMAR  (Capitana Remache)  -> "LA ISLA ES LIBRE": seguir sin cobros.
## La eleccion la guarda EmpireManager (choose_ending). Si se sale sin elegir,
## la mesa vuelve a salir al cargar la partida (choice_pending).
##
## Esta pantalla tambien monta ArchipelagoPanel como hermano (lo crea al
## arrancar, en las dos vistas): asi lo encuentran por nombre MISIONES y la
## tarjeta de la colonia, sin tocar Main.tscn ni Main2D.tscn.

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const ArchipelagoPanelScript := preload("res://scripts/ui/ArchipelagoPanel.gd")
const Face := preload("res://scripts/ui/InstructorFace.gd")
const Bust := preload("res://scripts/ui/InstructorBust.gd")

## Tope de la ventana en PC/tablet.
const WINDOW_MAX := Vector2(720, 560)
## La mesa del libro: dos tarjetas lado a lado (poco alto: no queda hueco).
const CHOICE_MAX := Vector2(860, 400)
## Los dos finales: una frase, el instructor y los botones.
const ENDING_MAX := Vector2(720, 470)

## Que se ve: "victory" (las cifras), "choice" (la mesa del libro) o el final
## elegido ("sign" / "burn"). "" = nada.
var _step: String = ""
var _backdrop: ColorRect
var _window: Control

func _ready() -> void:
	layer = 20
	# Mientras se ve, los avisos esperan (NotificationPanel.is_busy).
	add_to_group("modal_screen")
	EventBus.victory_achieved.connect(_on_victory_achieved)
	# Una partida ganada que se guardo con el libro aun en la mesa: al cargarla,
	# se vuelve a preguntar.
	EventBus.game_load_completed.connect(func(): _offer_pending_choice.call_deferred())
	_mount_archipelago.call_deferred()

## Pone el ArchipelagoPanel de hermano (una vez). Oculto y sin _process hasta
## que se abre: no cuesta nada mientras no se usa.
func _mount_archipelago() -> void:
	var parent: Node = get_parent()
	if parent == null or parent.get_node_or_null(ArchipelagoPanelScript.NODE_NAME) != null:
		return
	var archipelago: CanvasLayer = ArchipelagoPanelScript.new()
	archipelago.name = ArchipelagoPanelScript.NODE_NAME
	parent.add_child(archipelago)

## Cierra la pantalla (SEGUIR, VER EL ARCHIPIELAGO).
func dismiss() -> void:
	_close()

## VER EL ARCHIPIELAGO: cierra la victoria y abre el mapa de las islas.
func open_archipelago() -> void:
	dismiss()
	_mount_archipelago()
	var archipelago: Node = get_parent().get_node_or_null(ArchipelagoPanelScript.NODE_NAME) if get_parent() != null else null
	if archipelago != null and archipelago.has_method("open"):
		archipelago.open()

func _on_victory_achieved(stats: Dictionary) -> void:
	_show_victory(stats)

## Esta la pantalla en pantalla. Para pruebas y para quien tenga que esperarla.
func is_showing() -> bool:
	return _backdrop != null and is_instance_valid(_backdrop) and not _backdrop.is_queued_for_deletion()

## El paso que se ve ("victory", "choice", "sign", "burn" o "").
func current_step() -> String:
	return _step if is_showing() else ""

## Hay que elegir que hacer con el libro (modo con la fase y Ataque Final
## ganado, sin eleccion todavia).
static func choice_due() -> bool:
	return EmpireManager.choice_pending()

func _offer_pending_choice() -> void:
	if is_showing() or not choice_due() or not GameManager.is_started():
		return
	show_choice()

# ── Paso 1: la victoria ──────────────────────────────────────────────

func _show_victory(stats: Dictionary) -> void:
	_clear()
	_step = "victory"
	var small := CT.is_phone()
	# Constructor gana sin asedio: su victoria no habla de la Tormenta.
	var builder: bool = GameMode.capstone_wins()
	var book: bool = not builder and choice_due()
	var title := Tr.t("LBL_VICTORY_TITLE_BUILDER" if builder else "LBL_VICTORY_TITLE")
	var vbox := _open_window(title, CT.sem("POSITIVE"), "VictoryWindow", WINDOW_MAX)

	# El pais que gana: su bandera y su nombre.
	var byline := ColonyByline.new("section", CT.text("window"), Vector2(60, 40) if small else Vector2(72, 48))
	byline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(byline)

	# El sello oficial: la Auditoria superada (o la capital en pie, Constructor).
	var seal := CT.stamp(Tr.t("STAMP_VICTORY_BUILDER" if builder else "STAMP_VICTORY_AUDIT"), CT.sem("POSITIVE"))
	seal.name = "VictoryStamp"
	vbox.add_child(seal)

	# Una frase.
	var subtitle := CT.para(Tr.t("LBL_VICTORY_SUBTITLE_BUILDER" if builder else "LBL_VICTORY_SUBTITLE_AUDIT"), "window")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Las cifras: icono + numero, el nombre debajo.
	var grid := HFlowContainer.new()
	grid.name = "Stats"
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	var time_played: float = stats.get("time_played", 0.0)
	_add_stat(grid, "game", Tr.t("LBL_STAT_MODE"), GameMode.display_name(GameMode.from_key(String(stats.get("mode", GameMode.current_key())))))
	_add_stat(grid, "clock", Tr.t("LBL_STAT_TIME"), _format_time(time_played))
	_add_stat(grid, "build", Tr.t("LBL_STAT_BUILDINGS"), str(stats.get("buildings_built", 0)))
	_add_stat(grid, "market", Tr.t("LBL_STAT_TRADES"), str(stats.get("trades_completed", 0)))
	_add_stat(grid, "star", Tr.t("LBL_STAT_MILESTONES"), str(stats.get("milestones", 0)))
	# Lo que de verdad cuenta la partida: cuantas veces volvio la Tormenta, cuantas
	# se les echo, y a la cuantas se gano el asedio. Constructor gana sin Tormenta,
	# sin Diezmo y sin asedio: ahi esas tres serian ceros que no dicen nada.
	if not builder:
		_add_stat(grid, "storm", Tr.t("LBL_STAT_STORMS"), "%d" % int(stats.get("storms_survived", 0)))
		_add_stat(grid, "check", Tr.t("LBL_STAT_TITHES_REPELLED"), "%d" % int(stats.get("tithes_repelled", 0)))
		_add_stat(grid, "missions", Tr.t("LBL_STAT_SUMMONS"), "%d" % int(stats.get("audit_summons", 1)))
		# Con el libro en la mesa, la coda es la pregunta; sin el, seguir jugando.
		var coda := CT.para(Tr.t("END_BOOK_TEASER" if book else "LBL_VICTORY_CODA"), "window", true, "small")
		coda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(coda)

	# Botones: lo principal en verde (el libro, o seguir); partida nueva, crema.
	var row := _button_row()
	if book:
		var book_btn := CT.text_button(Tr.t("BTN_END_BOOK"), "next", "primary", CT.menu_h("btn"))
		book_btn.name = "BookButton"
		book_btn.pressed.connect(show_choice)
		row.add_child(book_btn)
	else:
		var continue_btn := CT.text_button(Tr.t("BTN_CONTINUE"), "next", "primary", CT.menu_h("btn"))
		continue_btn.name = "ContinueButton"
		continue_btn.pressed.connect(_close)
		row.add_child(continue_btn)
	row.add_child(_new_game_button())

# ── Paso 2: la mesa del libro ────────────────────────────────────────

## La mesa: el libro del Impuesto y las dos salidas, cada una con lo que dice
## su instructor. Publica para las pruebas y para la carga de una partida que
## se guardo antes de elegir.
func show_choice() -> void:
	_clear()
	_step = "choice"
	var small := CT.is_phone()
	var vbox := _open_window(Tr.t("END_BOOK_RIBBON"), CT.sem("ACCENT"), "BookWindow", CHOICE_MAX)
	var intro := CT.para(Tr.t("END_BOOK_INTRO"), "window")
	intro.name = "BookIntro"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(intro)
	# Dos tarjetas lado a lado (en telefono apaisado tambien caben: son cortas).
	var cards := HBoxContainer.new()
	cards.name = "Choices"
	cards.add_theme_constant_override("separation", 8 if small else 14)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(cards)
	cards.add_child(_choice_card(EmpireManager.ENDING_SIGN, Bust.COMBAT, "salute",
		"END_SIGN_WHO", "END_SIGN_SAYS", "END_SIGN_WHAT", "BTN_END_SIGN", "accent", "upgrade"))
	cards.add_child(_choice_card(EmpireManager.ENDING_BURN, Bust.COLONY, "point",
		"END_BURN_WHO", "END_BURN_SAYS", "END_BURN_WHAT", "BTN_END_BURN", "warning", "sun"))

func _choice_card(choice: String, who: String, mood: String, who_key: String, says_key: String,
		what_key: String, btn_key: String, kind: String, glyph: String) -> PanelContainer:
	var small := CT.is_phone()
	var card := PanelContainer.new()
	card.name = "Choice_" + choice
	var st := CT.card_style("window")
	st.set_content_margin_all(6 if small else 12)
	card.add_theme_stylebox_override("panel", st)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4 if small else 8)
	card.add_child(box)
	# Quien habla: su cara y su nombre; lo que dice, entre comillas.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var face := Face.make(who, mood, 40 if small else 56)
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(face)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	head.add_child(words)
	words.add_child(CT.label(Tr.t(who_key), "small", CT.text("window", true)))
	var says := CT.para(Tr.t(says_key), "window", false, "small" if small else "body")
	says.name = "Says"
	words.add_child(says)
	box.add_child(head)
	# Lo que pasa, en una frase (gris).
	var what := CT.para(Tr.t(what_key), "window", true, "small")
	what.name = "What"
	box.add_child(what)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var btn := CT.text_button(Tr.t(btn_key), glyph, kind, CT.menu_h("btn"))
	btn.name = "Choose_" + choice
	btn.pressed.connect(choose.bind(choice))
	box.add_child(btn)
	return card

## FIRMAR o QUEMAR (los botones de la mesa; publica para las pruebas).
func choose(choice: String) -> void:
	if not EmpireManager.choose_ending(choice):
		return
	show_ending(choice)

# ── Paso 3: el final elegido ─────────────────────────────────────────

## La pantalla de cierre de cada final, con lo que dice el OTRO instructor.
func show_ending(choice: String) -> void:
	_clear()
	_step = choice
	var small := CT.is_phone()
	var sign: bool = choice == EmpireManager.ENDING_SIGN
	var vbox := _open_window(Tr.t("END_SIGN_RIBBON" if sign else "END_BURN_RIBBON"),
		CT.sem("ACCENT") if sign else CT.sem("POSITIVE"), "EndingWindow", ENDING_MAX)
	var byline := ColonyByline.new("section", CT.text("window"), Vector2(60, 40) if small else Vector2(72, 48))
	byline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(byline)
	var body := CT.para(Tr.t("END_SIGN_BODY" if sign else "END_BURN_BODY"), "window")
	body.name = "EndingBody"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)
	# El otro instructor dice la ultima palabra.
	var reply := HBoxContainer.new()
	reply.name = "EndingReply"
	reply.alignment = BoxContainer.ALIGNMENT_CENTER
	reply.add_theme_constant_override("separation", 8)
	var face := Face.make(Bust.COLONY if sign else Bust.COMBAT, "worried" if sign else "happy", 40 if small else 52)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reply.add_child(face)
	var reply_text := CT.para(Tr.t("END_SIGN_REPLY" if sign else "END_BURN_REPLY"), "window", false, "small")
	reply_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reply.add_child(reply_text)
	vbox.add_child(reply)
	# Quemar: el premio (el emblema del sol) a la vista.
	if not sign:
		var reward := CT.icon_line("sun", Tr.t("END_BURN_REWARD"), "positive")
		reward.name = "EndingReward"
		reward.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(reward)
	var coda := CT.para(Tr.t("END_SIGN_CODA" if sign else "END_BURN_CODA"), "window", true, "small")
	coda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(coda)
	var row := _button_row()
	if sign:
		var arch := CT.text_button(Tr.t("BTN_VIEW_ARCHIPELAGO"), "anchor", "primary", CT.menu_h("btn"))
		arch.name = "ArchipelagoButton"
		arch.pressed.connect(open_archipelago)
		row.add_child(arch)
		var later := CT.text_button(Tr.t("BTN_CONTINUE"), "", "secondary", CT.menu_h("btn"))
		later.name = "ContinueButton"
		later.pressed.connect(_close)
		row.add_child(later)
	else:
		var keep := CT.text_button(Tr.t("BTN_CONTINUE"), "next", "primary", CT.menu_h("btn"))
		keep.name = "ContinueButton"
		keep.pressed.connect(_close)
		row.add_child(keep)
		row.add_child(_new_game_button())

# ── Piezas ───────────────────────────────────────────────────────────

## Velo + ventana con cinta; devuelve la columna (dentro de un scroll) y deja
## la fila de botones para _button_row(), fuera del scroll.
var _body: VBoxContainer
var _max := WINDOW_MAX

func _open_window(title: String, fill: Color, node_name: String, max_size: Vector2) -> VBoxContainer:
	var small := CT.is_phone()
	_backdrop = CT.veil()
	add_child(_backdrop)
	var w := CT.menu_window(title, fill, small, false)
	_window = w["root"]
	_window.name = node_name
	add_child(_window)
	_body = w["body"]
	_max = max_size
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6 if small else 12)
	scroll.add_child(vbox)
	_place.call_deferred()
	_set_menu_button_hidden(true)
	return vbox

## Uno debajo del otro si no caben (telefono en vertical: salian 33 px por la
## derecha).
func _button_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Buttons"
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 8)
	_body.add_child(row)
	return row

func _new_game_button() -> Button:
	var new_btn := CT.text_button(Tr.t("BTN_NEW_GAME"), "plus", "secondary", CT.menu_h("btn"))
	new_btn.name = "NewGameButton"
	# Ya no borra nada: abre el selector de modo y crea otra partida.
	new_btn.pressed.connect(func(): GameManager.request_new_game())
	return new_btn

func _place() -> void:
	if _window == null or not is_instance_valid(_window):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var max_size := Vector2(_max.x, minf(_max.y, vp.y - 32.0))
	CT.place_window(_window, vp, max_size, CT.is_phone())

## Quita la ventana de ahora sin devolver el ☰ (se va a abrir otra).
func _clear() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
	_backdrop = null
	_window = null

func _close() -> void:
	_clear()
	_step = ""
	_set_menu_button_hidden(false)

## El ☰ (capa 30) caia sobre la esquina de la ventana, que no tiene X que
## apartar: mientras se ve la Victoria, el ☰ se esconde. Lo que se escondio aqui
## es lo unico que se vuelve a mostrar.
func _set_menu_button_hidden(hide_it: bool) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("hud_menu_button"):
		var c := n as Control
		if c == null or not is_instance_valid(c):
			continue
		if hide_it and c.visible:
			c.visible = false
			c.set_meta("hidden_by_victory", true)
		elif not hide_it and c.has_meta("hidden_by_victory"):
			c.remove_meta("hidden_by_victory")
			c.visible = true

## Una cifra: [icono] valor, y debajo el nombre (sin los dos puntos del texto
## de siempre). El nombre entero, al mantener pulsado.
func _add_stat(parent: Container, glyph: String, label_text: String, value_text: String) -> void:
	var chip := PanelContainer.new()
	var st := CT.card_style("window")
	st.set_content_margin_all(8)
	st.content_margin_left = 12
	st.content_margin_right = 14
	chip.add_theme_stylebox_override("panel", st)
	chip.tooltip_text = label_text
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var ic := CT.make_glyph(glyph, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(CT.label(value_text, "number", CT.text("window")))
	col.add_child(CT.label(label_text.trim_suffix(":"), "small", CT.text("window", true)))
	parent.add_child(chip)

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
