extends GdUnitTestSuite
## La lista de edificios sale igual en el editor y en un juego exportado.
## En el export cada .tres pasa a llamarse *.tres.remap: el menu CONSTRUIR
## buscaba ".tres" con DirAccess y en el APK y el .exe salia vacio.


func test_every_building_definition_loads() -> void:
	var all := BuildingData.load_all()
	assert_int(all.size()).is_equal(14)
	var ids := {}
	for data in all:
		ids[data.id] = true
	assert_int(ids.size()).is_equal(14)
	assert_bool(ids.has("sawmill")).is_true()
	assert_bool(ids.has("nucleo")).is_true()


func test_exported_names_are_found_once() -> void:
	# Lo que devuelve un directorio exportado: remaps, a veces el original,
	# importaciones y subcarpetas.
	var names := PackedStringArray([
		"sawmill.tres.remap", "house.tres", "house.tres.remap",
		"barracks.res", "icon.png.import", "sub/",
	])
	var got := BuildingData.resource_file_names(names)
	assert_array(Array(got)).contains_exactly(["sawmill.tres", "house.tres", "barracks.res"])


func test_the_build_menu_offers_the_sawmill() -> void:
	var ids: Array = []
	for data in BuildingData.load_all():
		if not data.is_core:
			ids.append(data.id)
	assert_array(ids).contains(["sawmill"])
	assert_array(ids).not_contains(["nucleo"])
