extends GdUnitTestSuite
## Las tres cosas que hacen que un .exe exportado sea jugable por otra persona y no
## una build de desarrollo. Ver docs/19-exportar.md.
##   1. dev_mode se enciende solo en el editor, nunca en una plantilla de exportación.
##   2. El autoload de Beckett apunta al portero, no al addon (que no viaja).
##   3. El preset de Windows deja fuera todo lo que no es el juego.
##   4. El preset de Android igual, sin secretos de firma, y el juego en apaisado
##      con el renderer Mobile en móvil (Forward+ sigue en PC).
##   5. El preset "Android QA (emulador)" (x86_64 + Compatibility, paquete .qa)
##      excluye lo mismo, no lleva secretos y no altera el preset real.
##   6. Las licencias que viajan con el binario existen: LICENSE,
##      THIRD-PARTY-NOTICES.md, licenses/GODOT-COPYRIGHT.txt y la de cada fuente.

const PRESETS_PATH := "res://export_presets.cfg"
const GATE_PATH := "res://scripts/services/BeckettGate.gd"

## Lo que nunca puede acabar dentro del .pck: tests, herramientas, documentación,
## los dos addons de desarrollo, los ficheros locales con tokens (.mcp.json y
## .cursor/mcp.json llevan el token de Beckett; .env, secret.json), la config del
## editor, el override.cfg de desarrollo y las carpetas privadas que .gitignore
## deja fuera del repo pero que siguen en disco (estrategia/, ui_tour/).
const MUST_EXCLUDE := [
	"tests/*", "tools/*", "docs/*", "specs/*", "reports/*",
	"addons/gdUnit4/*", "addons/beckett/*",
	".claude/*", ".specify/*", ".beckett/*", ".cursor/*", ".vscode/*",
	".mcp.json", "secret.json", ".env*", "override.cfg",
	"estrategia/*", "ui_tour/*", "build/*", "*.md",
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


# --- Android ------------------------------------------------------------------
# El preset se busca por plataforma, no por índice, para no depender del orden en
# que el editor reescriba export_presets.cfg.

## Claves del preset cuyo valor es un secreto: tienen que quedar vacías. La firma
## de release sale de GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD} y la de
## depuración, del keystore que el editor guarda en su carpeta de configuración.
const ANDROID_SECRET_KEYS := [
	"keystore/debug", "keystore/debug_user", "keystore/debug_password",
	"keystore/release", "keystore/release_user", "keystore/release_password",
	"apk_expansion/SALT", "apk_expansion/public_key",
]


## El preset real se llama "Android"; hay un segundo preset Android, el de QA en
## el emulador, que no debe confundirse con el que se distribuye.
func _android_section(cf: ConfigFile, preset_name := "Android") -> String:
	for section in cf.get_sections():
		if section.ends_with(".options"):
			continue
		if str(cf.get_value(section, "platform", "")) == "Android" \
				and str(cf.get_value(section, "name", "")) == preset_name:
			return section
	return ""


func test_android_preset_excludes_everything_that_is_not_the_game() -> void:
	var cf := ConfigFile.new()
	assert_int(cf.load(PRESETS_PATH)).is_equal(OK)
	var section := _android_section(cf)
	assert_str(section).override_failure_message("no hay preset Android").is_not_empty()
	var filters := []
	for f in str(cf.get_value(section, "exclude_filter", "")).split(","):
		filters.append(f.strip_edges())
	for must in MUST_EXCLUDE:
		assert_bool(filters.has(must)).override_failure_message("Android: falta excluir %s" % must).is_true()


func test_android_preset_stores_no_keystore_or_password() -> void:
	var cf := ConfigFile.new()
	cf.load(PRESETS_PATH)
	var options := _android_section(cf) + ".options"
	assert_bool(cf.has_section(options)).is_true()
	for key in ANDROID_SECRET_KEYS:
		assert_str(str(cf.get_value(options, key, ""))) \
			.override_failure_message("export_presets.cfg es publico: %s tiene que ir vacio" % key) \
			.is_empty()
	# Ni una ruta a un .keystore/.jks en ningún otro campo del fichero.
	var raw := FileAccess.get_file_as_string(PRESETS_PATH).to_lower()
	assert_bool(raw.contains(".keystore") or raw.contains(".jks")).is_false()


func test_android_preset_is_relative_arm64_prebuilt_and_asks_no_permissions() -> void:
	var cf := ConfigFile.new()
	cf.load(PRESETS_PATH)
	var section := _android_section(cf)
	var options := section + ".options"
	var export_path := str(cf.get_value(section, "export_path", ""))
	assert_bool(export_path.is_relative_path()).is_true()
	assert_bool(export_path.begins_with("build/android/")).is_true()
	assert_bool(bool(cf.get_value(options, "architectures/arm64-v8a", false))).is_true()
	assert_bool(bool(cf.get_value(options, "gradle_build/use_gradle_build", true))).is_false()
	assert_str(str(cf.get_value(options, "package/unique_name", ""))).is_equal("com.bryankey.tormentaimperial")
	# Sin permisos: el juego no usa red, cámara ni almacenamiento externo.
	var custom: PackedStringArray = cf.get_value(options, "permissions/custom_permissions", PackedStringArray())
	assert_int(custom.size()).is_equal(0)
	for key in cf.get_section_keys(options):
		if key.begins_with("permissions/") and key != "permissions/custom_permissions":
			assert_bool(bool(cf.get_value(options, key, false))) \
				.override_failure_message("permiso activado: %s" % key).is_false()


# --- Android QA (emulador) ----------------------------------------------------
# Variante solo para el emulador de Windows (qa/maestro/README.md): el APK real
# es arm64 con Vulkan y en el emulador sale en negro (VkResult error 5). Este es
# x86_64 y arranca con Compatibility/OpenGL por línea de comandos, sin tocar
# project.godot ni el preset real.

const QA_PRESET := "Android QA (emulador)"


func test_android_qa_preset_exists_and_real_preset_is_untouched() -> void:
	var cf := ConfigFile.new()
	assert_int(cf.load(PRESETS_PATH)).is_equal(OK)
	var real := _android_section(cf)
	var qa := _android_section(cf, QA_PRESET)
	assert_str(qa).override_failure_message("no hay preset %s" % QA_PRESET).is_not_empty()
	assert_str(qa).is_not_equal(real)
	# El real sigue siendo arm64, sin argumentos extra y con el renderer del proyecto.
	assert_bool(bool(cf.get_value(real + ".options", "architectures/x86_64", true))).is_false()
	assert_str(str(cf.get_value(real + ".options", "command_line/extra_args", "x"))).is_empty()


func test_android_qa_preset_excludes_the_same_as_the_real_one() -> void:
	var cf := ConfigFile.new()
	cf.load(PRESETS_PATH)
	var qa := _android_section(cf, QA_PRESET)
	var filters := []
	for f in str(cf.get_value(qa, "exclude_filter", "")).split(","):
		filters.append(f.strip_edges())
	for must in MUST_EXCLUDE:
		assert_bool(filters.has(must)).override_failure_message("QA: falta excluir %s" % must).is_true()
	assert_str(str(cf.get_value(qa, "exclude_filter", ""))) \
		.is_equal(str(cf.get_value(_android_section(cf), "exclude_filter", "")))


func test_android_qa_preset_is_x86_64_gl_compat_own_package_and_no_secrets() -> void:
	var cf := ConfigFile.new()
	cf.load(PRESETS_PATH)
	var qa := _android_section(cf, QA_PRESET)
	var options := qa + ".options"
	assert_str(str(cf.get_value(qa, "export_path", ""))).is_equal("build/android/TormentaImperial-qa.apk")
	assert_bool(bool(cf.get_value(options, "architectures/x86_64", false))).is_true()
	for abi in ["armeabi-v7a", "arm64-v8a", "x86"]:
		assert_bool(bool(cf.get_value(options, "architectures/" + abi, true))) \
			.override_failure_message("QA: sobra la ABI %s" % abi).is_false()
	var args := str(cf.get_value(options, "command_line/extra_args", ""))
	assert_bool(args.contains("--rendering-method gl_compatibility")).is_true()
	assert_bool(args.contains("--rendering-driver opengl3")).is_true()
	# Paquete propio: se instala al lado de la app real sin pisar sus datos.
	var real_pkg := str(cf.get_value(_android_section(cf) + ".options", "package/unique_name", ""))
	assert_str(str(cf.get_value(options, "package/unique_name", ""))).is_equal(real_pkg + ".qa")
	for key in ANDROID_SECRET_KEYS:
		assert_str(str(cf.get_value(options, key, ""))) \
			.override_failure_message("QA: %s tiene que ir vacio" % key).is_empty()
	var custom: PackedStringArray = cf.get_value(options, "permissions/custom_permissions", PackedStringArray())
	assert_int(custom.size()).is_equal(0)


func test_handheld_orientation_is_sensor_landscape() -> void:
	# La tableta es el objetivo principal: apaisado siguiendo el sensor. Solo afecta
	# a móvil; en PC no hace nada.
	var orientation := int(ProjectSettings.get_setting("display/window/handheld/orientation", -1))
	assert_int(orientation).is_equal(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


func test_mobile_is_always_fullscreen_whatever_the_preference() -> void:
	# En Android "ventana" deja las barras del sistema encima del juego.
	var fs := DisplayServer.WINDOW_MODE_FULLSCREEN
	assert_int(GameConfig._wanted_window_mode(false, true)).is_equal(fs)
	assert_int(GameConfig._wanted_window_mode(true, true)).is_equal(fs)
	# En PC la preferencia manda.
	assert_int(GameConfig._wanted_window_mode(true, false)).is_equal(fs)
	assert_int(GameConfig._wanted_window_mode(false, false)).is_equal(DisplayServer.WINDOW_MODE_WINDOWED)


func test_mobile_uses_mobile_renderer_and_desktop_keeps_forward_plus() -> void:
	# Se lee el fichero y no ProjectSettings: en el editor de PC get_setting ya
	# resuelve el valor de escritorio y no dejaría ver el override .mobile.
	var cf := ConfigFile.new()
	assert_int(cf.load("res://project.godot")).is_equal(OK)
	assert_str(str(cf.get_value("rendering", "renderer/rendering_method", ""))).is_equal("forward_plus")
	assert_str(str(cf.get_value("rendering", "renderer/rendering_method.mobile", ""))).is_equal("mobile")
	# Android exige las texturas importadas también en ETC2/ASTC o el export se niega.
	assert_bool(bool(cf.get_value("rendering", "textures/vram_compression/import_etc2_astc", false))).is_true()


# --- Licencias que viajan con el binario --------------------------------------
# tools/package_release.{sh,ps1} mete estos ficheros en cada zip para testers. Si
# falta alguno, repartir el juego incumple las licencias de terceros (MIT de Godot,
# Apache de Special Elite, OFL del resto de fuentes). Ver THIRD-PARTY-NOTICES.md.

const FONTS_DIR := "res://assets/fonts/"
const FONT_EXTENSIONS := ["ttf", "otf", "woff", "woff2"]


func test_license_exists_and_is_polyform_strict_with_rights_reserved() -> void:
	assert_bool(FileAccess.file_exists("res://LICENSE")).override_failure_message("falta LICENSE").is_true()
	var text := FileAccess.get_file_as_string("res://LICENSE")
	assert_bool(text.contains("PolyForm Strict License 1.0.0")).is_true()
	assert_bool(text.contains("ALL RIGHTS RESERVED")).is_true()
	assert_bool(text.contains("THIRD-PARTY-NOTICES.md")).is_true()


func test_third_party_notices_exist_with_godot_licence_and_engine_notices() -> void:
	assert_bool(FileAccess.file_exists("res://THIRD-PARTY-NOTICES.md")) \
		.override_failure_message("falta THIRD-PARTY-NOTICES.md").is_true()
	var notices := FileAccess.get_file_as_string("res://THIRD-PARTY-NOTICES.md")
	# La MIT de Godot tiene que ir completa, no solo nombrada; Apache y OFL también.
	assert_bool(notices.contains("Godot Engine contributors")).is_true()
	assert_bool(notices.contains("The above copyright notice and this permission notice shall be included")).is_true()
	assert_bool(notices.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION")).is_true()
	assert_bool(notices.contains("SIL OPEN FONT LICENSE Version 1.1")).is_true()
	# Los avisos de los componentes del motor (FreeType, HarfBuzz...).
	var engine := FileAccess.get_file_as_string("res://licenses/GODOT-COPYRIGHT.txt")
	assert_str(engine).override_failure_message("falta licenses/GODOT-COPYRIGHT.txt (tools/gen_godot_notices.gd)").is_not_empty()
	assert_bool(engine.contains("The FreeType Project")).is_true()
	assert_bool(engine.contains("HarfBuzz")).is_true()


## Cada fuente tiene al lado un .txt de licencia cuyo nombre contiene la familia
## (lo que va antes del primer "-": SpecialElite-Regular.ttf -> LICENSE-SpecialElite.txt)
## y aparece en THIRD-PARTY-NOTICES.md. Es la misma regla que aplica
## tools/package_release antes de crear un zip.
func test_every_font_has_its_licence_file_next_to_it_and_is_listed() -> void:
	var files := DirAccess.get_files_at(FONTS_DIR)
	var licences := []
	for f in files:
		if f.get_extension() == "txt":
			licences.append(f)
	var notices := FileAccess.get_file_as_string("res://THIRD-PARTY-NOTICES.md")
	var fonts := 0
	for f in files:
		if not FONT_EXTENSIONS.has(f.get_extension().to_lower()):
			continue
		fonts += 1
		var family: String = f.get_basename().get_slice("-", 0)
		var found := false
		for lic in licences:
			if str(lic).contains(family):
				found = true
		assert_bool(found) \
			.override_failure_message("la fuente %s no tiene licencia al lado (assets/fonts/*%s*.txt)" % [f, family]) \
			.is_true()
		assert_bool(_mentions_family(notices, family)) \
			.override_failure_message("la fuente %s no aparece en THIRD-PARTY-NOTICES.md" % f).is_true()
	assert_int(fonts).override_failure_message("no hay fuentes en assets/fonts: ¿se movieron?").is_greater(0)


## "SpecialElite" en el nombre del fichero y "Special Elite" en el aviso cuentan
## como la misma familia.
func _mentions_family(text: String, family: String) -> bool:
	if text.contains(family):
		return true
	var spaced := ""
	for i in family.length():
		var ch := family[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			spaced += " "
		spaced += ch
	return text.contains(spaced)
