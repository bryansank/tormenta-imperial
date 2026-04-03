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

# ══════════════════════════════════════
# SIZING
# ══════════════════════════════════════

const CORNER := 2
const MARGIN := 12
const BORDER := 6
const MIN_BTN_H := 40
const SEPARATION := 8

# ══════════════════════════════════════
# PANEL STYLE
# ══════════════════════════════════════

static func make_panel_style(border: bool = true) -> StyleBoxFlat:
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
static func make_war_table_style() -> StyleBoxFlat:
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

	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(CORNER)
	n.set_content_margin_all(10)
	n.border_color = ACCENT_DIM
	n.set_border_width_all(3)
	btn.add_theme_stylebox_override("normal", n)

	var h := StyleBoxFlat.new()
	h.bg_color = bg.lightened(0.2)
	h.set_corner_radius_all(CORNER)
	h.set_content_margin_all(10)
	h.border_color = ACCENT
	h.set_border_width_all(3)
	h.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.4)
	h.shadow_size = 3
	btn.add_theme_stylebox_override("hover", h)

	var p := StyleBoxFlat.new()
	p.bg_color = bg.lightened(0.4)
	p.set_corner_radius_all(CORNER)
	p.set_content_margin_all(10)
	p.border_color = ACCENT
	p.set_border_width_all(4)
	btn.add_theme_stylebox_override("pressed", p)

	var d := StyleBoxFlat.new()
	d.bg_color = BTN_DISABLED
	d.set_corner_radius_all(CORNER)
	d.set_content_margin_all(10)
	d.border_color = Color(0.2, 0.2, 0.15)
	d.set_border_width_all(2)
	btn.add_theme_stylebox_override("disabled", d)

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
	match size:
		"title": fs = FONT_TITLE
		"section": fs = FONT_SECTION
		"small": fs = FONT_SMALL
		_: fs = FONT_BODY
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_color_override("font_color", color)
	return label

static func section_header(text: String, color: Color = ACCENT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SECTION)
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
static func make_command_panel_style() -> StyleBoxFlat:
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
static func make_data_display_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.07)
	s.set_corner_radius_all(1)
	s.set_content_margin_all(8)
	s.border_color = ACCENT_DIM
	s.set_border_width_all(2)
	return s
