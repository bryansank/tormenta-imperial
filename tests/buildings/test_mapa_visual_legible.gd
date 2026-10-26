extends GdUnitTestSuite
## Fallos visuales del mapa (QA 28 punto 5, QA 30 punto 4 y texto flotante):
## rotulo de estado legible en Minima, texto flotante con tamano por perfil y
## sin rafaga de ceniza con el arbol en pausa.

const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

func test_font_size_buckets_are_legible() -> void:
	assert_int(Badge.font_size_for_scale(1.0)).is_equal(Badge.FONT_SIZE)
	assert_int(Badge.font_size_for_scale(0.1)).is_equal(16)
	assert_int(Badge.font_size_for_scale(0.5)).is_equal(20)
	for i in range(1, 11):
		assert_int(Badge.font_size_for_scale(i / 10.0)).is_greater_equal(16)

func test_floating_text_grows_on_small_screens() -> void:
	assert_float(FloatingText.size_factor("pc")).is_equal(1.0)
	assert_float(FloatingText.size_factor("tablet")).is_greater(1.0)
	assert_float(FloatingText.size_factor("phone")).is_greater(FloatingText.size_factor("tablet"))
