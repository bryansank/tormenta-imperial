extends GdUnitTestSuite
## Colores y contraste configurables (docs/21): paletas para daltonismo, alto
## contraste, opacidad de paneles y tamano de texto, todo por tokens de UITheme.
##
## Las paletas se comprueban simulando la vision de cada deficiencia con las
## matrices de Machado, Oliveira y Fernandes (2009, severidad 1.0) en RGB
## lineal: aliado/bueno, enemigo/malo y aviso tienen que seguir separados para
## quien ve con esa deficiencia, y mas que con la paleta de serie.
## Cada prueba deja UITheme como lo encontro (UITheme.configure()).

const PROTAN := [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
const DEUTAN := [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
const TRITAN := [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]

## Separacion minima (distancia euclidea en sRGB simulado, 0..1.73).
const MIN_SEPARATION := 0.5

func after_test() -> void:
	UITheme.configure()

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

static func _unlin(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055

static func _simulate(c: Color, m: Array) -> Vector3:
	var l := [_lin(c.r), _lin(c.g), _lin(c.b)]
	var out := Vector3()
	for i in 3:
		out[i] = _unlin(m[i][0] * l[0] + m[i][1] * l[1] + m[i][2] * l[2])
	return out

static func _min_separation(tokens: Dictionary, m: Array) -> float:
	var keys := ["POSITIVE", "DANGER", "WARNING"]
	var best := 99.0
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			best = minf(best, _simulate(tokens[keys[i]], m).distance_to(_simulate(tokens[keys[j]], m)))
	return best

func test_the_red_green_palette_separates_for_protanopia_and_deuteranopia() -> void:
	var base := UITheme.resolve_tokens("default", false, 1.0)
	var rg := UITheme.resolve_tokens("red_green", false, 1.0)
	for m in [PROTAN, DEUTAN]:
		assert_float(_min_separation(rg, m)).is_greater(MIN_SEPARATION)
		assert_float(_min_separation(rg, m)).is_greater(_min_separation(base, m))

func test_the_tritan_palette_separates_for_tritanopia() -> void:
	var base := UITheme.resolve_tokens("default", false, 1.0)
	var tri := UITheme.resolve_tokens("tritan", false, 1.0)
	assert_float(_min_separation(tri, TRITAN)).is_greater(MIN_SEPARATION)
	assert_float(_min_separation(tri, TRITAN)).is_greater(_min_separation(base, TRITAN))

func test_the_board_highlights_stay_apart_from_both_sides() -> void:
	for pal in UITheme.PALETTES:
		var t := UITheme.resolve_tokens(pal, false, 1.0)
		for m in [PROTAN, DEUTAN, TRITAN]:
			var move := _simulate(t["BOARD_MOVE"], m)
			var target := _simulate(t["BOARD_TARGET"], m)
			assert_float(move.distance_to(target)).override_failure_message("%s: mover y objetivo se confunden" % pal).is_greater(0.08)

func test_configure_rewrites_the_semantic_tokens() -> void:
	var default_positive := UITheme.POSITIVE
	UITheme.configure("red_green")
	assert_str(UITheme.palette).is_equal("red_green")
	assert_bool(UITheme.POSITIVE.is_equal_approx(default_positive)).is_false()
	assert_bool(UITheme.POSITIVE.is_equal_approx(UITheme._PALETTE_TOKENS["red_green"]["POSITIVE"])).is_true()
	# Lo que usa el tablero y el HUD sale de ahi.
	assert_bool(UITheme.unit_icon_tint(true).is_equal_approx(UITheme.POSITIVE.lightened(0.62))).is_true()
	UITheme.configure()
	assert_bool(UITheme.POSITIVE.is_equal_approx(default_positive)).is_true()

func test_an_unknown_palette_is_the_default() -> void:
	UITheme.configure("arcoiris")
	assert_str(UITheme.palette).is_equal("default")

func test_every_palette_defines_only_known_tokens() -> void:
	for pal in UITheme._PALETTE_TOKENS:
		for key in UITheme._PALETTE_TOKENS[pal]:
			assert_bool(UITheme._BASE.has(key)).override_failure_message("%s.%s" % [pal, key]).is_true()
	for key in UITheme._HIGH_CONTRAST:
		assert_bool(UITheme._BASE.has(key)).is_true()

# ── Paleta pequena (docs/24-paleta.md) ──────────────────────────────

func test_the_palette_has_ten_named_colours() -> void:
	assert_int(UITheme.PALETTE_NAMES.size()).is_equal(10)
	for key in UITheme.PALETTE_NAMES:
		assert_bool(UITheme._BASE.has(key)).override_failure_message(key).is_true()

## Categorias, ramas y botones no traen colores propios: son tonos de la paleta.
func test_categories_branches_and_buttons_come_from_the_palette() -> void:
	for pal in UITheme.PALETTES:
		for hc in [false, true]:
			var t := UITheme.resolve_tokens(pal, hc, 1.0)
			var palette_colours: Array = []
			for key in UITheme.PALETTE_NAMES:
				palette_colours.append(t[key])
			for key in ["CAT_PRODUCTION", "CAT_SUPPORT", "CAT_MILITARY", "CAT_DECORATION",
					"BRANCH_INDUSTRIAL", "BRANCH_MILITARY", "BRANCH_LOGISTICS", "BTN"]:
				assert_bool(palette_colours.has(t[key])).override_failure_message("%s/%s: %s" % [pal, hc, key]).is_true()

## El texto se lee sobre el fondo en todas las paletas, con y sin alto contraste.
func test_text_tokens_meet_the_minimum_contrast_on_the_surface() -> void:
	for pal in UITheme.PALETTES:
		for hc in [false, true]:
			var t := UITheme.resolve_tokens(pal, hc, 1.0)
			var need := 7.0 if hc else 4.5
			for key in ["TEXT", "TEXT_DIM", "TEXT_BRIGHT"]:
				for bg in [UITheme.UI_BG_REFERENCE, t["SURFACE"], t["HUD_BG"]]:
					assert_float(UITheme.contrast_ratio(t[key], bg)) \
						.override_failure_message("%s/%s: %s" % [pal, hc, key]).is_greater_equal(need)

# ── Alto contraste ───────────────────────────────────────────────────

func test_high_contrast_has_no_low_contrast_secondary_text() -> void:
	UITheme.configure("default", true)
	assert_float(UITheme.MIN_CONTRAST).is_equal(7.0)
	assert_float(UITheme.contrast_ratio(UITheme.TEXT_DIM, UITheme.UI_BG_REFERENCE)).is_greater_equal(7.0)
	# Y cualquier color que un panel pida sale legible a 7:1.
	var label := UITheme.make_label("x", "small", Color(0.3, 0.2, 0.1))
	var shown: Color = label.get_theme_color("font_color")
	assert_float(UITheme.contrast_ratio(shown, UITheme.UI_BG_REFERENCE)).is_greater_equal(7.0)
	label.free()

func test_high_contrast_panels_are_opaque_flat_boxes_with_a_clear_border() -> void:
	UITheme.configure("default", true)
	var style := UITheme.make_panel_style()
	assert_object(style).is_instanceof(StyleBoxFlat)
	assert_float((style as StyleBoxFlat).bg_color.a).is_equal(1.0)
	var card := UITheme.make_hud_card_style(UITheme.ACCENT, 2)
	assert_int(card.border_width_top).is_equal(3)
	assert_float(card.bg_color.a).is_equal(1.0)

## Sin placas de metal (2026-09-28): el texto se lee sobre una caja lisa.
func test_panels_and_buttons_are_flat_boxes() -> void:
	UITheme.configure()
	assert_object(UITheme.make_panel_style()).is_instanceof(StyleBoxFlat)
	var btn := Button.new()
	UITheme.style_button(btn)
	assert_object(btn.get_theme_stylebox("normal")).is_instanceof(StyleBoxFlat)
	btn.free()

# ── Opacidad ─────────────────────────────────────────────────────────

func test_panel_opacity_fades_hud_cards_and_panels() -> void:
	UITheme.configure("default", false, 0.5)
	assert_float(UITheme.HUD_BG.a).is_equal_approx(0.46, 0.001)
	assert_float(UITheme.make_hud_card_style().bg_color.a).is_equal_approx(0.46, 0.001)
	var panel := UITheme.make_panel_style() as StyleBoxFlat
	assert_float(panel.bg_color.a).is_less(0.95)
	UITheme.configure()

func test_opacity_is_clamped() -> void:
	UITheme.configure("default", false, 0.0)
	assert_float(UITheme.panel_opacity).is_equal(UITheme.OPACITY_MIN)

# ── Texto y lado tactil ──────────────────────────────────────────────

func test_text_sizes_scale_every_font_and_keep_the_hierarchy() -> void:
	var sizes := {}
	for size in UITheme.TEXT_SIZES:
		UITheme.configure("default", false, 1.0, size)
		sizes[size] = [UITheme.FONT_TITLE, UITheme.FONT_SECTION, UITheme.FONT_BODY, UITheme.FONT_SMALL]
		assert_int(UITheme.FONT_TITLE).is_greater(UITheme.FONT_SECTION)
		assert_int(UITheme.FONT_SECTION).is_greater(UITheme.FONT_BODY)
		assert_int(UITheme.FONT_BODY).is_greater(UITheme.FONT_SMALL)
	assert_array(sizes["normal"]).is_equal([26, 20, 17, 15])
	assert_int(sizes["large"][2]).is_equal(20)
	assert_int(sizes["xlarge"][2]).is_equal(23)
	assert_int(sizes["small"][3]).is_greater_equal(11)

func test_labels_and_the_global_theme_use_the_chosen_size() -> void:
	UITheme.configure("default", false, 1.0, "large")
	var label := UITheme.make_label("x", "body")
	assert_int(label.get_theme_font_size("font_size")).is_equal(20)
	label.free()
	var theme := UITheme.build_global_theme()
	assert_int(theme.default_font_size).is_equal(20)

func test_the_touch_target_raises_the_minimum_button() -> void:
	UITheme.configure("default", false, 1.0, "normal", 52)
	var btn := Button.new()
	UITheme.style_button(btn)
	assert_float(btn.custom_minimum_size.y).is_equal(52.0)
	btn.free()
	# Nunca por debajo del minimo de serie.
	UITheme.configure("default", false, 1.0, "normal", 20)
	assert_int(UITheme.MIN_BTN_H).is_equal(44)

func test_resource_colours_for_floating_text_follow_the_palette() -> void:
	var saved: Dictionary = GameConfig.resource_colors.duplicate()
	var prev := GameConfig.ui_palette
	GameConfig.ui_palette = "red_green"
	DeviceProfile.apply_theme()
	var wood: Color = GameConfig.resource_colors["wood"]
	GameConfig.ui_palette = prev
	DeviceProfile.apply_theme()
	GameConfig.resource_colors = saved
	assert_bool(wood.is_equal_approx(UITheme._PALETTE_TOKENS["red_green"]["RES_WOOD"])).is_true()
