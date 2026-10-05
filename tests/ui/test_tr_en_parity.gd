extends GdUnitTestSuite
## Ninguna clave de Tr.gd se queda sin ingles (rama feat/menos-texto: cada texto
## recortado o nuevo se escribe en ES y EN). Y las dos versiones llevan los
## mismos huecos de formato: un %d que falta en una revienta el panel en ese
## idioma.

const FORMAT := "%[+0-9.]*[dsf%]"

func _specs(text: String) -> Array:
	var rx := RegEx.new()
	rx.compile(FORMAT)
	var out: Array = []
	for m in rx.search_all(text):
		out.append(m.get_string())
	return out

func test_every_spanish_key_has_english() -> void:
	var es: Dictionary = Tr._STRINGS["es"]
	var en: Dictionary = Tr._STRINGS["en"]
	var missing: Array = []
	for key in es:
		if not en.has(key):
			missing.append(key)
	assert_array(missing).override_failure_message("Sin ingles: %s" % [missing]).is_empty()

func test_every_english_key_has_spanish() -> void:
	var es: Dictionary = Tr._STRINGS["es"]
	var en: Dictionary = Tr._STRINGS["en"]
	var missing: Array = []
	for key in en:
		if not es.has(key):
			missing.append(key)
	assert_array(missing).override_failure_message("Sin espanol: %s" % [missing]).is_empty()

func test_both_languages_take_the_same_format_arguments() -> void:
	var es: Dictionary = Tr._STRINGS["es"]
	var en: Dictionary = Tr._STRINGS["en"]
	var bad: Array = []
	for key in es:
		if en.has(key) and _specs(String(es[key])) != _specs(String(en[key])):
			bad.append(key)
	assert_array(bad).override_failure_message("Huecos distintos: %s" % [bad]).is_empty()
