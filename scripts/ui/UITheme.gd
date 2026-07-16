class_name UITheme
## Centralized dieselpunk war theme for all UI panels.
## Static utility class — no autoload needed. Use UITheme.method() from any script.

# ══════════════════════════════════════
# COLOR PALETTE — Dieselpunk Military
# ══════════════════════════════════════

# Backgrounds
const BG_DARK := Color(0.05, 0.06, 0.04)
const PANEL_BG := Color(0.1, 0.11, 0.09, 0.95)
const PANEL_BG_LIGHT := Color(0.13, 0.14, 0.11, 0.9)
const CARD_BG := Color(0.12, 0.13, 0.1, 0.9)

# Accent / Border
const ACCENT := Color(0.77, 0.59, 0.16)          # Brass gold
const ACCENT_DIM := Color(0.5, 0.38, 0.12, 0.6)  # Muted brass

# Text
const TEXT := Color(0.91, 0.86, 0.78)             # Parchment
const TEXT_DIM := Color(0.55, 0.49, 0.37)         # Aged brass
const TEXT_BRIGHT := Color(1.0, 0.95, 0.85)       # Highlighted

# Semantic
const POSITIVE := Color(0.29, 0.55, 0.25)         # Military green
const DANGER := Color(0.55, 0.23, 0.16)           # Rust red
const WARNING := Color(0.8, 0.53, 0.13)           # Amber
const INFO := Color(0.29, 0.42, 0.55)             # Steel blue

# Buttons
const BTN := Color(0.15, 0.16, 0.13)
const BTN_HOVER := Color(0.23, 0.24, 0.2)
const BTN_PRESSED := Color(0.29, 0.31, 0.26)
const BTN_DISABLED := Color(0.1, 0.1, 0.09, 0.7)

# Resources
const RES_GOLD := Color(1.0, 0.85, 0.2)
const RES_STEEL := Color(0.7, 0.75, 0.8)
const RES_OIL := Color(0.5, 0.45, 0.55)
const RES_WOOD := Color(0.6, 0.4, 0.2)

# Categories
const CAT_PRODUCTION := Color(0.9, 0.7, 0.2)
const CAT_SUPPORT := Color(0.45, 0.75, 0.4)
const CAT_MILITARY := Color(0.8, 0.35, 0.25)
const CAT_DECORATION := Color(0.6, 0.5, 0.8)

# Tech branches
const BRANCH_INDUSTRIAL := Color(0.9, 0.6, 0.2)
const BRANCH_MILITARY := Color(0.8, 0.3, 0.3)
const BRANCH_LOGISTICS := Color(0.3, 0.7, 0.9)

# ══════════════════════════════════════
# TYPOGRAPHY
# ══════════════════════════════════════

const FONT_TITLE := 20
const FONT_SECTION := 15
const FONT_BODY := 13
const FONT_SMALL := 11
const FONT_BUTTON := 13

# ── Font files (free, OFL-licensed — see assets/fonts/OFL-*.txt) ──
# Black Ops One: military stencil display for titles.
# Rajdhani: condensed industrial sans for everything else.
const FONT_TITLE_PATH := "res://assets/fonts/BlackOpsOne-Regular.ttf"
const FONT_BODY_PATH := "res://assets/fonts/Rajdhani-Medium.ttf"
const FONT_HEAVY_PATH := "res://assets/fonts/Rajdhani-SemiBold.ttf"

static var _font_cache := {}

## Loads a font robustly: the imported resource when available (export-safe),
## otherwise the raw .ttf bytes so it works even before Godot reimports.
static func _load_font(path: String) -> FontFile:
	if _font_cache.has(path):
		return _font_cache[path]
	var f: FontFile = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is FontFile:
			f = res
	if f == null and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			f = FontFile.new()
			f.data = bytes
	_font_cache[path] = f
	return f

static func body_font() -> FontFile:
	return _load_font(FONT_BODY_PATH)

static func heavy_font() -> FontFile:
	return _load_font(FONT_HEAVY_PATH)

## Display font for titles, with Rajdhani as fallback so accented/ñ glyphs
## missing from the stencil face still render.
static func title_font() -> FontFile:
	var f := _load_font(FONT_TITLE_PATH)
	if f and f.fallbacks.is_empty():
		var b := body_font()
		if b:
			f.fallbacks = [b]
	return f

# ══════════════════════════════════════
# SIZING
# ══════════════════════════════════════

const CORNER := 2
const MARGIN := 12
const BORDER := 6
const MIN_BTN_H := 40
const SEPARATION := 8

# ══════════════════════════════════════
# TEXTURED SURFACES (9-patch metal — Kenney UI, CC0)
# ══════════════════════════════════════
# These 9-slice sprites turn flat panels/buttons into brushed-metal plates with
# rivets. Grey source art is tinted warm via modulate_color to read as dieselpunk
# brass/gunmetal. If a texture is missing, callers fall back to a flat StyleBox so
# the UI never breaks.

# Brushed-metal plates composited from the owned Poly Haven metal_plate texture
# (CC0) with a drawn brass frame + corner rivets — see tools/gen_ui_textures.gd.
const TEX_PANEL := "res://assets/textures/ui/panel_metal.png"          # 128² frame+rivets
const TEX_PANEL_INSET := "res://assets/textures/ui/panel_inset_metal.png"  # 96² thin frame
const TEX_BUTTON := "res://assets/textures/ui/button_metal.png"        # 160x56 beveled

static var _tex_cache := {}

static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			t = res
	_tex_cache[path] = t
	return t

## Builds a 9-slice StyleBoxTexture, tinted by `modulate`. Returns null if the
## texture isn't imported yet, so callers can fall back to a flat box.
static func _tex_box(path: String, slice: int, content: int, modulate: Color) -> StyleBoxTexture:
	var tex := _tex(path)
	if tex == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(slice)
	s.set_content_margin_all(content)
	s.modulate_color = modulate
	# Tile the metal grain in the stretchable center/edges so it stays crisp
	# instead of smearing when a panel is much larger than the source texture.
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return s

# ══════════════════════════════════════
# PANEL STYLE
# ══════════════════════════════════════

static func make_panel_style(border: bool = true) -> StyleBox:
	var tex := _tex_box(TEX_PANEL, 20, MARGIN, Color(1, 1, 1))
	if tex != null:
		return tex
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_corner_radius_all(CORNER)
	s.set_content_margin_all(MARGIN)
	if border:
		s.border_color = ACCENT
		s.set_border_width_all(BORDER)
		# Doble borde efecto táctica
		s.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
		s.shadow_size = 4
	return s

static func make_hud_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.05, 0.95)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(12)
	# Borde grueso militar inferior
	s.border_color = ACCENT
	s.border_width_bottom = 4
	return s

## Military tactical panel con decoraciones de esquinas
static func make_war_table_style() -> StyleBox:
	var tex := _tex_box(TEX_PANEL, 20, MARGIN, Color(1.06, 1.02, 0.92))
	if tex != null:
		return tex
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_corner_radius_all(CORNER)
	s.set_content_margin_all(MARGIN)
	s.border_color = ACCENT
	s.set_border_width_all(BORDER)
	s.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3)
	s.shadow_size = 6
	return s

# ══════════════════════════════════════
# BUTTONS
# ══════════════════════════════════════

static func style_button(btn: Button, bg: Color = BTN, font_size: int = FONT_BUTTON) -> void:
	btn.custom_minimum_size.y = maxi(int(btn.custom_minimum_size.y), MIN_BTN_H)

	# Baked metal button, tinted toward `bg`'s hue; falls back to flat if art missing.
	btn.add_theme_stylebox_override("normal", _button_style(_metal_tint(bg, 1.0), bg, ACCENT_DIM, 3))
	btn.add_theme_stylebox_override("hover", _button_style(_metal_tint(bg, 1.32), bg.lightened(0.2), ACCENT, 3))
	btn.add_theme_stylebox_override("pressed", _button_style(_metal_tint(bg, 1.6), bg.lightened(0.4), ACCENT, 4))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.5, 0.5, 0.47), BTN_DISABLED, Color(0.2, 0.2, 0.15), 2))

	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)

static func style_card_button(btn: Button, bg: Color = CARD_BG, left_color: Color = ACCENT) -> void:
	btn.custom_minimum_size.y = maxi(int(btn.custom_minimum_size.y), MIN_BTN_H)

	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(CORNER)
	n.set_content_margin_all(12)
	n.border_color = ACCENT_DIM
	n.set_border_width_all(2)
	n.border_width_left = 6
	n.border_color = left_color
	btn.add_theme_stylebox_override("normal", n)

	var h := StyleBoxFlat.new()
	h.bg_color = bg.lightened(0.15)
	h.set_corner_radius_all(CORNER)
	h.set_content_margin_all(12)
	h.border_color = ACCENT
	h.set_border_width_all(2)
	h.border_width_left = 6
	h.shadow_color = Color(left_color.r, left_color.g, left_color.b, 0.5)
	h.shadow_size = 4
	btn.add_theme_stylebox_override("hover", h)

	var p := StyleBoxFlat.new()
	p.bg_color = bg.lightened(0.25)
	p.set_corner_radius_all(CORNER)
	p.set_content_margin_all(12)
	p.border_color = ACCENT
	p.set_border_width_all(2)
	p.border_width_left = 8
	btn.add_theme_stylebox_override("pressed", p)

	var d := StyleBoxFlat.new()
	d.bg_color = BTN_DISABLED
	d.set_corner_radius_all(CORNER)
	d.set_content_margin_all(12)
	d.border_color = Color(0.15, 0.15, 0.12, 0.4)
	d.set_border_width_all(1)
	d.border_width_left = 3
	btn.add_theme_stylebox_override("disabled", d)

	btn.add_theme_font_size_override("font_size", FONT_BODY)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)

# ══════════════════════════════════════
# LABELS & TEXT
# ══════════════════════════════════════

static func make_label(text: String, size: String = "body", color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	var fs: int
	var font: FontFile
	match size:
		"title":
			fs = FONT_TITLE
			font = title_font()
		"section":
			fs = FONT_SECTION
			font = heavy_font()
		"small":
			fs = FONT_SMALL
			font = body_font()
		_:
			fs = FONT_BODY
			font = body_font()
	label.add_theme_font_size_override("font_size", fs)
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	return label

static func section_header(text: String, color: Color = ACCENT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SECTION)
	var font := heavy_font()
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

# ══════════════════════════════════════
# COMPOSITE COMPONENTS
# ══════════════════════════════════════

static func make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", SEPARATION)
	sep.add_theme_color_override("separator", ACCENT)
	return sep

static func make_progress_bar(fill_color: Color = ACCENT, height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.max_value = 1.0
	bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.05)
	bg.set_corner_radius_all(2)
	bg.border_color = ACCENT_DIM
	bg.set_border_width_all(2)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	fill.shadow_color = Color(fill_color.r, fill_color.g, fill_color.b, 0.5)
	fill.shadow_size = 2
	bar.add_theme_stylebox_override("fill", fill)

	return bar

static func make_close_button(callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(32, 32)
	style_button(btn, DANGER, FONT_BODY)
	btn.pressed.connect(callback)
	return btn

static func make_panel_header(title_text: String, close_callback: Callable) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var title := make_label(title_text, "title", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := make_close_button(close_callback)
	header.add_child(close)

	return header

static func make_backdrop() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.0, 0.0, 0.0, 0.45)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect

## Tactical command panel con bordes gruesos militares y glow
static func make_command_panel_style() -> StyleBox:
	var tex := _tex_box(TEX_PANEL, 20, MARGIN, Color(0.82, 0.82, 0.82))
	if tex != null:
		return tex
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_corner_radius_all(0)  # Ángulos rectos = militar
	s.set_content_margin_all(MARGIN)
	s.border_color = ACCENT
	s.set_border_width_all(BORDER)
	s.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	s.shadow_size = 8
	return s

## Info display con frame de datos
static func make_data_display_style() -> StyleBox:
	var tex := _tex_box(TEX_PANEL_INSET, 10, 8, Color(0.9, 0.9, 0.9))
	if tex != null:
		return tex
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.07)
	s.set_corner_radius_all(1)
	s.set_content_margin_all(8)
	s.border_color = ACCENT_DIM
	s.set_border_width_all(2)
	return s

# ══════════════════════════════════════
# GLOBAL THEME
# ══════════════════════════════════════

## Small StyleBoxFlat factory used to build the global theme.
static func _flat(bg: Color, border: Color, border_w: int, corner: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(corner)
	if margin > 0:
		s.set_content_margin_all(margin)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	return s

## Normalizes a colour to a modulate for the baked metal button: white stays
## neutral (shows the metal as-is), a hue pushes the metal toward that hue, and
## `boost` brightens (hover/pressed). The button texture already bakes in its dark
## tone, so modulates hover around 1.0 rather than the ~0.4 used for flat fills.
static func _metal_tint(base: Color, boost: float) -> Color:
	var m := maxf(maxf(base.r, base.g), maxf(base.b, 0.001))
	return Color(base.r / m * boost, base.g / m * boost, base.b / m * boost)

## Textured brass button for one state, with a flat fallback if art is missing.
static func _button_style(modulate: Color, fb_bg: Color, fb_border: Color, fb_bw: int) -> StyleBox:
	var tex := _tex_box(TEX_BUTTON, 12, 10, modulate)
	if tex != null:
		return tex
	return _flat(fb_bg, fb_border, fb_bw, CORNER, 10)

static func _theme_button(t: Theme, type: String) -> void:
	var n := _button_style(Color(1, 1, 1), BTN, ACCENT_DIM, 3)
	var h := _button_style(Color(1.32, 1.28, 1.15), BTN_HOVER, ACCENT, 3)
	var p := _button_style(Color(1.6, 1.5, 1.3), BTN_PRESSED, ACCENT, 4)
	var d := _button_style(Color(0.5, 0.5, 0.47), BTN_DISABLED, Color(0.2, 0.2, 0.15), 2)
	var focus := _flat(Color(0, 0, 0, 0), ACCENT, 2, CORNER, 10)
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, TEXT_BRIGHT)
	t.set_color("font_pressed_color", type, TEXT_BRIGHT)
	t.set_color("font_disabled_color", type, TEXT_DIM)
	t.set_font_size("font_size", type, FONT_BUTTON)
	var hf := heavy_font()
	if hf:
		t.set_font("font", type, hf)

## Builds a Theme that restyles Godot's built-in controls (buttons, scrollbars,
## sliders, line edits, tooltips, popups, focus rings…) so nothing falls back to
## the default engine look. Applied once to the scene-tree root by UILayoutManager.
## Controls that set their own theme overrides are unaffected (overrides win).
static func build_global_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	# Global font: everything that doesn't override falls back to Rajdhani.
	var bf := body_font()
	if bf:
		t.default_font = bf
	t.set_color("font_color", "Label", TEXT)

	# ── Buttons ──
	_theme_button(t, "Button")
	_theme_button(t, "OptionButton")
	_theme_button(t, "MenuButton")
	for cb in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", cb, TEXT)
		t.set_color("font_hover_color", cb, TEXT_BRIGHT)
		t.set_color("font_pressed_color", cb, TEXT_BRIGHT)
		t.set_font_size("font_size", cb, FONT_BODY)

	# ── LineEdit ──
	t.set_stylebox("normal", "LineEdit", _flat(BG_DARK, ACCENT_DIM, 1, CORNER, 6))
	t.set_stylebox("focus", "LineEdit", _flat(BG_DARK.lightened(0.03), ACCENT, 2, CORNER, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))
	t.set_font_size("font_size", "LineEdit", FONT_BODY)

	# ── Panels ── (textured metal, falls back to flat if art missing)
	t.set_stylebox("panel", "PanelContainer", make_panel_style())
	t.set_stylebox("panel", "Panel", make_panel_style())

	# ── ScrollBars ──
	var clear := Color(0, 0, 0, 0)
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, _flat(Color(0.04, 0.05, 0.03, 0.6), clear, 0, CORNER, 2))
		t.set_stylebox("scroll_focus", sb_type, _flat(Color(0.04, 0.05, 0.03, 0.6), clear, 0, CORNER, 2))
		t.set_stylebox("grabber", sb_type, _flat(ACCENT_DIM, clear, 0, CORNER, 2))
		t.set_stylebox("grabber_highlight", sb_type, _flat(ACCENT, clear, 0, CORNER, 2))
		t.set_stylebox("grabber_pressed", sb_type, _flat(ACCENT.lightened(0.2), clear, 0, CORNER, 2))

	# ── Sliders ──
	for sl in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", sl, _flat(BG_DARK, ACCENT_DIM, 1, CORNER, 0))
		t.set_stylebox("grabber_area", sl, _flat(ACCENT_DIM, clear, 0, CORNER, 0))
		t.set_stylebox("grabber_area_highlight", sl, _flat(ACCENT, clear, 0, CORNER, 0))

	# ── ProgressBar ──
	t.set_stylebox("background", "ProgressBar", _flat(Color(0.06, 0.06, 0.05, 1), ACCENT_DIM, 2, 2, 0))
	t.set_stylebox("fill", "ProgressBar", _flat(ACCENT, clear, 0, 2, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", FONT_SMALL)

	# ── PopupMenu (dropdowns / context menus) ──
	t.set_stylebox("panel", "PopupMenu", make_war_table_style())
	t.set_stylebox("hover", "PopupMenu", _flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), clear, 0, CORNER, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT_BRIGHT)
	t.set_color("font_separator_color", "PopupMenu", ACCENT)
	t.set_font_size("font_size", "PopupMenu", FONT_BODY)

	# ── Tooltip ──
	t.set_stylebox("panel", "TooltipPanel", _flat(Color(0.06, 0.07, 0.05, 0.97), ACCENT, 1, CORNER, 8))
	t.set_color("font_color", "TooltipLabel", TEXT_BRIGHT)
	t.set_font_size("font_size", "TooltipLabel", FONT_SMALL)

	# ── Split containers ──
	for split in ["HSplitContainer", "VSplitContainer"]:
		t.set_constant("separation", split, 8)
		t.set_constant("minimum_grab_thickness", split, 8)

	return t
