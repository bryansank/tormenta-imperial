extends GdUnitTestSuite
## Nombres de GPU que el primer arranque toma por flojas (docs/26 §7.2, paso 1).
## Los drivers de Intel de 2020 en adelante nombran la UHD 630 sin numero.

const GraphicsQuality := preload("res://scripts/services/GraphicsQuality.gd")

func test_an_intel_uhd_without_number_is_weak() -> void:
	assert_bool(GraphicsQuality.gpu_name_is_weak("Intel(R) UHD Graphics")).is_true()

func test_the_numbered_intel_names_are_still_weak() -> void:
	assert_bool(GraphicsQuality.gpu_name_is_weak("Intel(R) UHD Graphics 620")).is_true()
	assert_bool(GraphicsQuality.gpu_name_is_weak("Intel(R) HD Graphics 520")).is_true()

func test_iris_xe_and_discrete_cards_are_not_weak() -> void:
	assert_bool(GraphicsQuality.gpu_name_is_weak("Intel(R) Iris(R) Xe Graphics")).is_false()
	assert_bool(GraphicsQuality.gpu_name_is_weak("NVIDIA GeForce RTX 3060 Laptop GPU")).is_false()