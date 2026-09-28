extends GdUnitTestSuite
## Las tres cosas que hacen que un .exe exportado sea jugable por otra persona y no
## una build de desarrollo. Ver docs/19-exportar.md.
##   1. dev_mode se enciende solo en el editor, nunca en una plantilla de exportación.
##   2. El autoload de Beckett apunta al portero, no al addon (que no viaja).
##   3. El preset de Windows deja fuera todo lo que no es el juego.

const PRESETS_PATH := "res://export_presets.cfg"
const GATE_PATH := "res://scripts/services/BeckettGate.gd"

## Lo que nunca puede acabar dentro del .pck: tests, herramientas, documentación,
## los dos addons de desarrollo y los ficheros locales con tokens (.mcp.json, .env).
const MUST_EXCLUDE := [
	"tests/*", "tools/*", "docs/*", "specs/*", "reports/*",
	"addons/gdUnit4/*", "addons/beckett/*",
	".claude/*", ".specify/*", ".beckett/*", ".mcp.json", ".env*", "build/*", "*.md",
]


func test_dev_mode_is_on_in_the_editor_binary() -> void:
	# Los tests corren con el binario del editor y sin argumentos de usuario.
	assert_bool(OS.has_feature("editor")).is_true()
	assert_bool(GameConfig._resolve_dev_mode()).is_true()


func test_beckett_autoload_points_at_the_gate_not_the_addon() -> void:
	var path := str(ProjectSettings.get_setting("autoload/BeckettRuntime", "")).trim_prefix("*")
	# El editor puede reescribir la ruta como uid:// al guardar project.godot.
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	assert_str(path).is_equal(GATE_PATH)


func test_gate_never_preloads_the_addon() -> void:
	# Un preload metería el addon como dependencia del export, o fallaría sin él.
	var src := FileAccess.get_file_as_string(GATE_PATH)
	assert_str(src).is_not_empty()
	assert_bool(src.contains("preload(")).is_false()
	assert_bool(src.contains("OS.has_feature(\"editor\")")).is_true()


func test_windows_preset_excludes_everything_that_is_not_the_game() -> void:
	var cf := ConfigFile.new()
	assert_int(cf.load(PRESETS_PATH)).is_equal(OK)
	assert_str(str(cf.get_value("preset.0", "name", ""))).is_equal("Windows Desktop")
	var filters := []
	for f in str(cf.get_value("preset.0", "exclude_filter", "")).split(","):
		filters.append(f.strip_edges())
	for must in MUST_EXCLUDE:
		assert_bool(filters.has(must)).override_failure_message("falta excluir %s" % must).is_true()


func test_windows_preset_ships_one_relative_exe() -> void:
	var cf := ConfigFile.new()
	cf.load(PRESETS_PATH)
	var export_path := str(cf.get_value("preset.0", "export_path", ""))
	# Relativa al proyecto: una ruta absoluta filtraría la máquina de quien exporta.
	assert_bool(export_path.is_relative_path()).is_true()
	assert_bool(export_path.begins_with("build/")).is_true()
	assert_bool(bool(cf.get_value("preset.0.options", "binary_format/embed_pck", false))).is_true()
