extends PanelContainer
## La tarjeta REGIMIENTO del Cuartel (ArmyPanel), autocontenida: la insignia, el
## nombre y las victorias, y un boton CAMBIAR que despliega debajo el nombre
## (con "al azar"), el color, el emblema y la pintura. Solo cosmetico (docs/15
## §12): lo guarda ArmyManager.set_regiment() y se ve en las dos vistas de
## combate 3D y en el tablero 2D.
##
## Cada eleccion se aplica al momento (no hay "guardar"). Lo que el rango aun no
## abre sale apagado con su candado y "Rango N", como en la bandera.
##
## Rendimiento: las miniaturas salen de las caches de RegimentLook/ColonyFlag;
## la galeria solo se construye con la tarjeta abierta, y nada va por frame.

const RegimentLook := preload("res://scripts/ui/RegimentLook.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

const BADGE_PX := 52
## Lado de las fichas de la galeria: tamano dedo (docs/28 §4, 48 dp).
const CHIP := 48

var _badge: TextureRect
var _name_label: Label
var _wins_label: Label
var _edit_btn: Button
var _editor: VBoxContainer
var _name_edit: LineEdit
var _name_warning: Label
var _open := false
## Mientras se rehace la galeria: el LineEdit que se quita suelta el foco y eso
## no debe guardar ni rehacer otra vez a medias.
var _rebuilding := false

func _ready() -> void:
	name = "RegimentCard"
	# Rediseno fase 2 (feat/ui2-ejercito): tarjeta crema con borde de laton.
	var style := CT.card_style("window", false, CT.c("window", "CARD"))
	style.border_color = CT.sem("ACCENT")
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	_build()
	EventBus.regiment_changed.connect(refresh)
	# reset() de una partida nueva avisa con army_changed.
	EventBus.army_changed.connect(refresh)
	EventBus.governor_rank_up.connect(func(_r, _rw): refresh())
	EventBus.colony_identity_changed.connect(func(_n, _s): refresh())
	refresh()

func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	_badge = TextureRect.new()
	_badge.name = "RegimentBadge"
	_badge.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	info.add_child(CT.label(Tr.t("LBL_REGIMENT_TITLE"), "small", CT.text("window", true)))
	_name_label = CT.label("", "button", CT.text("window"))
	_name_label.name = "RegimentName"
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name_label)
	_wins_label = CT.label("", "small", CT.text("window", true))
	_wins_label.name = "RegimentWins"
	_wins_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_wins_label.tooltip_text = Tr.t("LBL_REGIMENT_STARS_HINT") % GameConfig.regiment_star_wins
	info.add_child(_wins_label)

	_edit_btn = Button.new()
	_edit_btn.name = "RegimentEdit"
	_edit_btn.text = Tr.t("BTN_REGIMENT_EDIT")
	_edit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	CT.style_pill(_edit_btn, "secondary", 48 if CT.phone else CT.BTN_SMALL, "window", "settings", "small")
	_edit_btn.pressed.connect(toggle_editor)
	row.add_child(_edit_btn)

	_editor = VBoxContainer.new()
	_editor.name = "RegimentEditor"
	_editor.add_theme_constant_override("separation", 6)
	_editor.visible = false
	col.add_child(_editor)

# ── Estado ──

func is_editor_open() -> bool:
	return _open

func toggle_editor() -> void:
	_open = not _open
	_editor.visible = _open
	refresh()

## Rehace el resumen (barato) y, con la tarjeta abierta, la galeria.
func refresh() -> void:
	if _badge == null or _rebuilding:
		return
	var look := ArmyManager.get_regiment_look()
	_badge.texture = RegimentLook.badge_texture(look)
	_name_label.text = String(look["name"])
	var wins := int(look["wins"])
	var next := RegimentLook.wins_to_next_star(wins)
	# Una cifra corta a la vista; la estrella que falta, al mantener pulsado.
	_wins_label.text = Tr.t("ARMY2_STARS_N") % wins
	_wins_label.tooltip_text = Tr.t("FMT_REGIMENT_WINS") % wins
	if next > 0:
		_wins_label.tooltip_text += " · " + Tr.t("FMT_REGIMENT_NEXT_STAR") % next
	_wins_label.tooltip_text += "
" + Tr.t("LBL_REGIMENT_STARS_HINT") % GameConfig.regiment_star_wins
	_edit_btn.text = Tr.t("BTN_REGIMENT_DONE") if _open else Tr.t("BTN_REGIMENT_EDIT")
	if _open:
		_rebuild_editor(look)

# ── Galeria ──

func _rebuild_editor(look: Dictionary) -> void:
	_rebuilding = true
	_fill_editor(look)
	_rebuilding = false

func _fill_editor(look: Dictionary) -> void:
	var typed := _name_edit.text if _name_edit != null else ""
	var had_focus := _name_edit != null and _name_edit.has_focus()
	for child in _editor.get_children():
		_editor.remove_child(child)
		child.queue_free()
	var saved := ArmyManager.get_regiment()

	# Nombre: texto libre con el filtro del pais, y "al azar".
	_editor.add_child(CT.label(Tr.t("LBL_REGIMENT_NAME"), "small", CT.text("window", true)))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	_editor.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.name = "RegimentNameEdit"
	_name_edit.max_length = GameConfig.COLONY_NAME_MAX
	_name_edit.placeholder_text = Tr.t("REGIMENT_DEFAULT_NAME")
	_name_edit.text = typed if had_focus else String(saved["name"])
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = 48
	var edit_style := CT.well_style("window", 12, 8)
	_name_edit.add_theme_stylebox_override("normal", edit_style)
	_name_edit.add_theme_stylebox_override("focus", CT.box(CT.c("window", "WELL"), CT.sem("ACCENT"), 3, 12, 8))
	_name_edit.add_theme_font_override("font", CT.body_font())
	_name_edit.add_theme_font_size_override("font_size", CT.fs("body"))
	_name_edit.add_theme_color_override("font_color", CT.text("window"))
	# El nombre de serie se lee (antes casi crema sobre crema).
	_name_edit.add_theme_color_override("font_placeholder_color", CT.text("window", true))
	_name_edit.text_submitted.connect(func(t: String): set_name_text(t))
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	name_row.add_child(_name_edit)
	var random_btn := Button.new()
	random_btn.name = "RegimentRandomName"
	random_btn.text = Tr.t("BTN_REGIMENT_RANDOM")
	CT.style_pill(random_btn, "secondary", 48, "window", "", "small")
	random_btn.pressed.connect(randomize_name)
	name_row.add_child(random_btn)
	_name_warning = CT.label(Tr.t("LBL_REGIMENT_NAME_BAD"), "small", CT.tone_color("warning"))
	_name_warning.name = "RegimentNameWarning"
	_name_warning.visible = false
	_editor.add_child(_name_warning)
	if had_focus:
		_name_edit.grab_focus.call_deferred()

	var rank := RankManager.get_rank()
	var all := GameMode.all_unlocked()

	# Color: el de la bandera o uno de los colores de la colonia.
	_editor.add_child(CT.label(Tr.t("LBL_REGIMENT_COLOR"), "small", CT.text("window", true)))
	var colors := _flow("RegimentColors")
	colors.add_child(_flag_chip("color", String(saved["color"]) == ""))
	for color_id in GameConfig.COLONY_COLOR_ORDER:
		var open := RegimentLook.is_open("colors", color_id, rank, all)
		var swatch := CT.piece_swatch(ColonyFlag.color_of(color_id), Vector2(CHIP - 14, CHIP - 14), not open)
		var chip := _chip("Color_" + color_id, swatch, String(saved["color"]) == color_id, open,
			Tr.t("COLONY_COLOR_" + String(color_id).to_upper()), RegimentLook.piece_rank_of("colors", color_id))
		var id := String(color_id)
		chip.pressed.connect(func(): pick("color", id))
		colors.add_child(chip)

	# Emblema: el de la bandera o uno de sus emblemas, en el color de ahora.
	_editor.add_child(CT.label(Tr.t("LBL_REGIMENT_EMBLEM"), "small", CT.text("window", true)))
	var emblems := _flow("RegimentEmblems")
	emblems.add_child(_flag_chip("emblem", String(saved["emblem"]) == ""))
	for emblem in GameConfig.COLONY_EMBLEMS:
		var open := RegimentLook.is_open("emblems", emblem, rank, all)
		# "Ninguno": el simbolo de prohibido, no un disco liso que parece otra pieza.
		var pic: Control = CT.none_piece(Vector2(CHIP - 10, CHIP - 10)) if String(emblem) == "none" 			else _pic(RegimentLook.badge_texture({"color_id": look["color_id"], "emblem": emblem, "stars": 0}, false), open)
		var chip := _chip("Emblem_" + emblem, pic, String(saved["emblem"]) == emblem, open,
			Tr.t("FLAG_EMBLEM_" + String(emblem).to_upper()), RegimentLook.piece_rank_of("emblems", emblem))
		var id := String(emblem)
		chip.pressed.connect(func(): pick("emblem", id))
		emblems.add_child(chip)

	# Pintura: abre con el rango.
	_editor.add_child(CT.label(Tr.t("LBL_REGIMENT_PAINT"), "small", CT.text("window", true)))
	var paints := _flow("RegimentPaints")
	for paint in GameConfig.REGIMENT_PAINTS:
		var open := RegimentLook.is_paint_open(paint, rank, all)
		var chip := _chip("Paint_" + paint, _pic(RegimentLook.paint_texture(paint, look["color_id"]), open),
			String(saved["paint"]) == paint, open, Tr.t("REGIMENT_PAINT_" + String(paint).to_upper()),
			RegimentLook.paint_rank(paint))
		var id := String(paint)
		chip.pressed.connect(func(): pick("paint", id))
		paints.add_child(chip)

	_editor.add_child(CT.label(Tr.t("LBL_REGIMENT_COSMETIC"), "small", CT.text("window", true)))

## Cambia una pieza ("color", "emblem", "paint"; "" = la de la bandera) y deja
## las demas como estan. Devuelve lo que diga ArmyManager.
func pick(kind: String, id: String) -> bool:
	var r := ArmyManager.get_regiment()
	r[kind] = id
	return ArmyManager.set_regiment(String(r["name"]), String(r["color"]), String(r["emblem"]), String(r["paint"]))

## Pone el nombre. Uno que no pasa el filtro no se guarda y se avisa.
func set_name_text(text: String) -> bool:
	var r := ArmyManager.get_regiment()
	var ok := ArmyManager.set_regiment(text, String(r["color"]), String(r["emblem"]), String(r["paint"]))
	if _name_warning != null:
		_name_warning.visible = not ok
	return ok

func _on_name_focus_exited() -> void:
	if _rebuilding or _name_edit == null:
		return
	set_name_text(_name_edit.text)

func randomize_name() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var reg_name := RegimentLook.random_name(rng.randi(), Tr.get_locale())
	if _name_edit != null:
		_name_edit.text = reg_name
	set_name_text(reg_name)

# ── Piezas de la galeria ──

func _flow(node_name: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_editor.add_child(flow)
	return flow

## "Como la bandera": la miniatura de la bandera del pais.
func _flag_chip(kind: String, selected: bool) -> Button:
	var pic := _pic(ColonyFlag.current_small_texture(), true)
	pic.custom_minimum_size = Vector2(CHIP - 8, (CHIP - 8) * 0.66)
	var chip := _chip("Flag_" + kind, pic, selected, true, Tr.t("LBL_REGIMENT_LIKE_FLAG"), 0)
	chip.pressed.connect(func(): pick(kind, ""))
	return chip

## Ficha de la galeria (CartoonTheme.piece_tile): la pieza arriba; cerrada,
## apagada y con la placa [candado] N debajo, nunca encima. Todas miden igual.
func _chip(node_name: String, content: Control, selected: bool, open: bool, tip: String, rank: int) -> Button:
	var btn := CT.piece_tile(content, selected, open, rank if not open and rank > 0 else 0)
	btn.name = node_name
	btn.tooltip_text = tip if open else "%s · %s" % [tip, Tr.t("LBL_RANK_LOCK") % rank]
	return btn

func _pic(tex: Texture2D, open: bool) -> TextureRect:
	var pic := TextureRect.new()
	pic.texture = tex
	pic.custom_minimum_size = Vector2(CHIP - 10, CHIP - 10)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not open:
		pic.modulate = Color(1, 1, 1, 0.45)
	return pic
