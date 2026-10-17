extends CanvasLayer
## "Nueva partida": el selector de modo. Sustituye al ConfirmationDialog con el
## tema por defecto de Godot (en el emulador de Android salia gris y diminuto).
##
##   Paso 1  una tarjeta por modo ofrecido (GameMode.OFFERED: hoy solo la
##           Campana; las de los modos apartados se crean pero no se ven), con
##           nombre, dificultad, una linea y lo que pide el modo elegido. Tocar
##           una tarjeta la elige; EMPEZAR sigue.
##           Con la Campana elegida, debajo, el NIVEL: Colono (el de siempre)
##           o Gobernador (el complejo). Gobernador sale con candado y la
##           condicion hasta que el perfil lo abre (GameMode.governor_unlocked;
##           en dev_mode, siempre abierto).
##   Paso 2  nombre y bandera (ColonyIdentityPanel): se abre con open("new") y
##           su `confirmed(name, spec)` sigue (queda en `chosen_identity`, que
##           GameManager.start_new_game pone tras el reset); su `cancelled`
##           vuelve al paso 1.
##
## Ya no hay paso de "se borrara tu partida" (2026-10-12): una partida nueva va
## a su propio archivo y no borra ninguna. Emite `confirmed` con `chosen_mode`
## puesto, o `canceled`, y quien lo abrio (GameManager.request_new_game) decide. Lo crea
## GameManager y cuelga de el, asi que sobrevive a la recarga de escena y
## funciona igual en la vista 3D y en la 2D.
##
## Tactil primero: cada tarjeta es un boton de 44 px o mas, y la rejilla pasa de
## 4 columnas a 2 y a 1 segun el ancho (1280x800, 1024x768, movil en vertical).

signal confirmed
signal canceled

const LAYER := 40
const MAX_WIDTH := 1000.0
## El paso de nombre y bandera.
const IdentityPanel := preload("res://scripts/ui/ColonyIdentityPanel.gd")
const CARD_MIN_H := 150.0
const WIDE := 900.0
const MEDIUM := 520.0

## El modo elegido. Lo lee quien escucha `confirmed`.
var chosen_mode: int = GameMode.DEFAULT
## El nivel elegido (GameMode.Tier). Solo cuenta si el modo admite niveles.
var chosen_tier: int = GameMode.TIER_DEFAULT
## Nombre y bandera del paso 2 ({"name", "spec"}), o {} si no se paso por el.
var chosen_identity: Dictionary = {}

var _current_mode: int = GameMode.DEFAULT
## El paso de nombre y bandera abierto encima, si lo hay.
var _identity: Node = null

var _root: Control
var _card: PanelContainer
var _pick_box: VBoxContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _goal_label: Label
var _start_btn: Button
var _cards: Dictionary = {}   ## mode -> Button
var _current_tier: int = GameMode.TIER_DEFAULT
var _tier_box: VBoxContainer
var _tier_cards: Dictionary = {}   ## tier -> Button
var _tier_lock_label: Label

const TIER_CARD_MIN_H := 84.0

## Antes de add_child. `current_mode` es el de la partida en curso: se ofrece el
## mismo de entrada.
func setup(current_mode: int, current_tier: int = GameMode.TIER_DEFAULT) -> void:
	_current_mode = current_mode
	_current_tier = current_tier
	# Se repite el nivel de la partida que se deja, si sigue abierto.
	chosen_tier = current_tier if (current_tier == GameMode.TIER_DEFAULT or GameMode.governor_unlocked()) \
		else GameMode.TIER_DEFAULT
	# Una partida en un modo apartado (Sandbox de antes) no deja elegido un modo
	# que ya no se ve: se empieza en el de siempre.
	chosen_mode = current_mode if GameMode.is_offered(current_mode) else GameMode.DEFAULT

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	_select(chosen_mode)
	_show_pick()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	# Con un solo modo ofrecido y el nivel Gobernador aun cerrado no hay nada
	# que elegir: se va directo a nombre y bandera (ronda de pruebas 1.0).
	if skips_pick():
		_on_start()

## No hay nada que elegir en el paso 1: un solo modo y un solo nivel abierto.
func skips_pick() -> bool:
	return GameMode.OFFERED.size() <= 1 and is_governor_locked()

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(ModalKit.make_backdrop(0.85))

	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	# ── Paso 1: elegir modo ──
	_pick_box = VBoxContainer.new()
	_pick_box.add_theme_constant_override("separation", 10)
	column.add_child(_pick_box)
	_pick_box.add_child(ModalKit.make_text(Tr.t("BTN_NEW_GAME"), "title", UITheme.ACCENT))
	_pick_box.add_child(ModalKit.make_text(Tr.t("LBL_MODE_PICK"), "small", UITheme.TEXT_DIM))
	_pick_box.add_child(UITheme.make_separator())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_pick_box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	for mode in GameMode.ORDER:
		var btn := _make_mode_card(mode)
		btn.visible = GameMode.is_offered(mode)
		_cards[mode] = btn
		_grid.add_child(btn)

	# ── Nivel de la Campana: Colono / Gobernador ──
	_tier_box = VBoxContainer.new()
	_tier_box.name = "TierBox"
	_tier_box.add_theme_constant_override("separation", 6)
	_pick_box.add_child(_tier_box)
	_tier_box.add_child(ModalKit.make_text(Tr.t("LBL_TIER_PICK"), "small", UITheme.TEXT_DIM))
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 10)
	_tier_box.add_child(tier_row)
	for t in [GameMode.Tier.COLONIST, GameMode.Tier.GOVERNOR]:
		var tbtn := _make_tier_card(t)
		_tier_cards[t] = tbtn
		tier_row.add_child(tbtn)
	_tier_lock_label = ModalKit.make_text(Tr.t("TIER_GOVERNOR_LOCKED"), "small", UITheme.WARNING)
	_tier_lock_label.name = "TierLockLabel"
	_tier_box.add_child(_tier_lock_label)
	_tier_lock_label.visible = not GameMode.governor_unlocked()

	_goal_label = ModalKit.make_text("", "body", UITheme.TEXT)
	_pick_box.add_child(_goal_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_pick_box.add_child(row)
	row.add_child(ModalKit.make_menu_button(Tr.t("BTN_CANCEL"), UITheme.BTN, cancel))
	_start_btn = ModalKit.make_menu_button(Tr.t("BTN_MODE_START"), UITheme.POSITIVE, _on_start)
	row.add_child(_start_btn)

## Una tarjeta: boton alto, con nombre, etiqueta de dificultad y una linea.
func _make_mode_card(mode: int) -> Button:
	var color: Color = mode_color(mode)
	var btn := Button.new()
	btn.name = "Mode_%s" % GameMode.key_of(mode)
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_contents = true
	btn.custom_minimum_size = Vector2(0, CARD_MIN_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_card_button(btn, UITheme.CARD_BG, color)
	btn.pressed.connect(_select.bind(mode))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var name_label := UITheme.make_label(Tr.t(GameMode.name_key(mode)), "section", UITheme.TEXT_BRIGHT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var tag := UITheme.make_label(Tr.t(GameMode.tag_key(mode)).to_upper(), "small", color.lightened(0.35))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	var desc := UITheme.make_label(Tr.t(GameMode.desc_key(mode)), "small", UITheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	# El boton no crece con sus hijos: se le pasa el alto que pide el texto.
	box.minimum_size_changed.connect(func():
		btn.custom_minimum_size.y = maxf(CARD_MIN_H, box.get_combined_minimum_size().y + 20.0))
	return btn

## Una tarjeta de nivel, mas baja que la de modo. Gobernador cerrado: apagada,
## con un candado dibujado (las fuentes no garantizan el emoji) y sin seleccion.
func _make_tier_card(t: int) -> Button:
	var color: Color = UITheme.ACCENT if t == GameMode.TIER_DEFAULT else UITheme.DANGER
	var locked: bool = t != GameMode.TIER_DEFAULT and not GameMode.governor_unlocked()
	var btn := Button.new()
	btn.name = "Tier_%s" % GameMode.tier_key_of(t)
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_contents = true
	btn.disabled = locked
	btn.custom_minimum_size = Vector2(0, TIER_CARD_MIN_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_card_button(btn, UITheme.CARD_BG, UITheme.TEXT_DIM if locked else color)
	btn.pressed.connect(pick_tier.bind(t))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -10
	box.offset_top = 8
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	if locked:
		var lock := make_lock_icon()
		lock.name = "Lock"
		head.add_child(lock)
	var name_label := UITheme.make_label(Tr.t(GameMode.tier_name_key(t)), "section",
		UITheme.TEXT_DIM if locked else UITheme.TEXT_BRIGHT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_label)
	var desc := UITheme.make_label(Tr.t(GameMode.tier_desc_key(t)), "small", UITheme.TEXT_DIM if locked else UITheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	box.minimum_size_changed.connect(func():
		btn.custom_minimum_size.y = maxf(TIER_CARD_MIN_H, box.get_combined_minimum_size().y + 16.0))
	return btn

## Un candado: arco y cuerpo, del color del texto apagado.
static func make_lock_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(16, 20)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var col: Color = UITheme.TEXT_DIM
		c.draw_arc(Vector2(8, 9), 5.0, PI, TAU, 12, col, 2.0)
		c.draw_line(Vector2(3, 9), Vector2(3, 11), col, 2.0)
		c.draw_line(Vector2(13, 9), Vector2(13, 11), col, 2.0)
		c.draw_rect(Rect2(1, 10, 14, 10), col))
	return c

## El color de cada modo: el de su dificultad.
static func mode_color(mode: int) -> Color:
	match mode:
		GameMode.Mode.BUILDER:
			return UITheme.POSITIVE
		GameMode.Mode.SURVIVAL:
			return UITheme.DANGER
		GameMode.Mode.SANDBOX:
			return UITheme.INFO
		_:
			return UITheme.ACCENT

# ── Colocacion ───────────────────────────────────────────────────────

## Columnas de tarjetas para un ancho de tarjeta dado: 4 en una tableta o PC en
## horizontal (1024 px o mas), 2 en una pantalla estrecha, 1 en un movil en
## vertical.
static func columns_for(card_width: float) -> int:
	if card_width >= WIDE:
		return 4
	if card_width >= MEDIUM:
		return 2
	return 1

func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ModalKit.fit_center(_card, MAX_WIDTH, vp)
	var shown: int = maxi(1, GameMode.OFFERED.size())
	_grid.columns = mini(columns_for(_card.custom_minimum_size.x), shown)
	# Lo que no quepa en alto se desplaza: el resto de la tarjeta (titulo,
	# objetivo, botones) necesita unos 300 px.
	var rows: int = ceili(float(shown) / float(_grid.columns))
	var wanted: float = float(rows) * (CARD_MIN_H + 10.0) + 30.0
	_scroll.custom_minimum_size = Vector2(0, clampf(wanted, CARD_MIN_H, maxf(CARD_MIN_H, vp.y - 320.0)))

# ── Pasos ────────────────────────────────────────────────────────────

func _select(mode: int) -> void:
	chosen_mode = mode
	for m in _cards:
		(_cards[m] as Button).set_pressed_no_signal(m == mode)
	_goal_label.text = Tr.t(GameMode.goal_key(mode))
	_tier_box.visible = GameMode.tier_allowed(mode)
	_refresh_tiers()

## Elige nivel. Gobernador cerrado no se deja elegir: devuelve false.
func pick_tier(t: int) -> bool:
	if t != GameMode.TIER_DEFAULT and not GameMode.governor_unlocked():
		_refresh_tiers()
		return false
	chosen_tier = t
	_refresh_tiers()
	return true

func _refresh_tiers() -> void:
	for t in _tier_cards:
		(_tier_cards[t] as Button).set_pressed_no_signal(t == chosen_tier)

## El nivel con el que empezara la partida: el elegido si el modo los admite.
func effective_tier() -> int:
	return chosen_tier if GameMode.tier_allowed(chosen_mode) else GameMode.TIER_DEFAULT

func tier_card(t: int) -> Button:
	return _tier_cards.get(t, null)

func is_governor_locked() -> bool:
	return (_tier_cards[GameMode.Tier.GOVERNOR] as Button).disabled

func _show_pick() -> void:
	_close_identity()
	_card.visible = true
	_pick_box.visible = true
	_relayout()
	(_cards.get(chosen_mode, _start_btn) as Control).grab_focus.call_deferred()

## EMPEZAR: abre el paso de nombre y bandera.
func _on_start() -> void:
	_open_identity()

func _open_identity() -> void:
	var panel = IdentityPanel.new()
	_identity = panel
	panel.confirmed.connect(_on_identity_confirmed)
	# Sin paso 1 (skips_pick), volver atras es cerrar el dialogo.
	panel.cancelled.connect(func(): cancel() if skips_pick() else _show_pick())
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)
	_card.visible = false
	panel.open("new")

func _on_identity_confirmed(colony_name: Variant = "", spec: Variant = {}) -> void:
	chosen_identity = {"name": str(colony_name), "spec": (spec as Dictionary).duplicate(true) if spec is Dictionary else {}}
	_close_identity()
	confirm()

func _close_identity() -> void:
	if _identity != null and is_instance_valid(_identity):
		_identity.queue_free()
	_identity = null

## El paso de nombre y bandera esta abierto.
func is_naming() -> bool:
	return _identity != null and is_instance_valid(_identity)

## Elige y sigue. Publicos para las pruebas y para quien quiera saltarse la UI.
func pick(mode: int) -> void:
	_select(mode)
	_on_start()

func confirm() -> void:
	confirmed.emit()

func cancel() -> void:
	canceled.emit()

func mode_card(mode: int) -> Button:
	return _cards.get(mode, null)

## `_input` y no `_unhandled_input`: el dialogo cuelga de un autoload, y el
## menu principal (en la escena) se come el ESC antes que cualquier autoload.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_naming() and not skips_pick():
			_show_pick()
		else:
			cancel()
		get_viewport().set_input_as_handled()
