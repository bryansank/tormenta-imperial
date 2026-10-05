extends GdUnitTestSuite
## Sistema de escalas de iconos (24 / 42 / 60 / 96 px): los generadores
## (tools/gen_resource_icons.gd, tools/gen_unit_icons.gd) trazan cada icono a
## cada escala y UITheme sirve la que toca para la medida pedida.

func test_scale_for_picks_the_smallest_that_fits() -> void:
	assert_int(UITheme.icon_scale_for(16)).is_equal(24)
	assert_int(UITheme.icon_scale_for(24)).is_equal(24)
	assert_int(UITheme.icon_scale_for(26)).is_equal(42)
	assert_int(UITheme.icon_scale_for(52)).is_equal(60)
	assert_int(UITheme.icon_scale_for(96)).is_equal(96)
	assert_int(UITheme.icon_scale_for(300)).is_equal(96)

func test_paths_carry_the_scale() -> void:
	assert_str(UITheme.icon_path("gold")).ends_with("icons/gold.png")
	assert_str(UITheme.icon_path("gold", 20)).ends_with("icons/gold_24.png")
	assert_str(UITheme.unit_icon_path("infantry", 50)).ends_with("units/infantry_60.png")
	assert_str(UITheme.unit_icon_path("infantry")).ends_with("units/infantry.png")

func test_every_resource_icon_exists_at_every_scale_with_its_size() -> void:
	for id in ["gold", "wood", "steel", "oil", "move"]:
		for s in UITheme.ICON_SCALES:
			var tex := UITheme.icon_texture(id, int(s))
			assert_object(tex).is_not_null()
			assert_int(tex.get_width()).is_equal(int(s))

func test_every_unit_icon_exists_at_every_scale_with_its_size() -> void:
	for id in ["infantry", "artillery", "vehicle"]:
		for s in UITheme.ICON_SCALES:
			var tex := UITheme.unit_icon(id, int(s))
			assert_object(tex).is_not_null()
			assert_int(tex.get_width()).is_equal(int(s))

func test_a_missing_scale_falls_back_to_the_plain_icon() -> void:
	assert_object(UITheme.icon_texture("no_such_icon", 24)).is_null()
	# Sin medida, el de siempre.
	assert_object(UITheme.icon_texture("gold")).is_not_null()
	assert_object(UITheme.unit_icon("infantry")).is_not_null()

func test_make_icon_uses_the_scaled_texture() -> void:
	var rect: TextureRect = auto_free(UITheme.make_icon("gold", 20))
	assert_int(rect.texture.get_width()).is_equal(24)
