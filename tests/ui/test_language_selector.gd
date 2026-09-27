extends GdUnitTestSuite
## El idioma se elige en Ajustes, se guarda en user://settings.cfg (no en la
## partida) y se aplica al arrancar. Cambiarlo avisa por EventBus.locale_changed.
##
## Estas pruebas escriben el settings.cfg de verdad: se copia antes y se deja
## exactamente como estaba despues.

const SettingsPanelScene := preload("res://scenes/ui/SettingsPanel.tscn")

var _had_file := false
var _file_bytes := PackedByteArray()
var _saved_locale := "es"
var _saved_tr_locale := "es"
var _announced: Array = []
var _panel: CanvasLayer

func before_test() -> void:
	_had_file = FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH)
	if _had_file:
		_file_bytes = FileAccess.get_file_as_bytes(GameConfig.USER_SETTINGS_PATH)
	_saved_locale = GameConfig.ui_locale
	_saved_tr_locale = Tr.get_locale()
	GameConfig.ui_locale = "es"
	Tr.set_locale("es")
	_announced.clear()
	EventBus.locale_changed.connect(_on_locale_changed)

func after_test() -> void:
	if EventBus.locale_changed.is_connected(_on_locale_changed):
		EventBus.locale_changed.disconnect(_on_locale_changed)
	if _panel and is_instance_valid(_panel):
		remove_child(_panel)
		_panel.free()
	_panel = null
	if _had_file:
		var f := FileAccess.open(GameConfig.USER_SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_file_bytes)
		f.close()
	elif FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH):
		DirAccess.remove_absolute(GameConfig.USER_SETTINGS_PATH)
	GameConfig.ui_locale = _saved_locale
	Tr.set_locale(_saved_tr_locale)

func _on_locale_changed(locale: String) -> void:
	_announced.append(locale)

func _stored_locale() -> String:
	var cf := ConfigFile.new()
	if cf.load(GameConfig.USER_SETTINGS_PATH) != OK:
		return ""
	return str(cf.get_value("ui", "locale", ""))

func test_choosing_a_language_applies_saves_and_announces_it() -> void:
	GameConfig.set_locale("en")
	assert_str(Tr.get_locale()).is_equal("en")
	assert_str(GameConfig.ui_locale).is_equal("en")
	assert_str(_stored_locale()).is_equal("en")
	assert_array(_announced).is_equal(["en"])

func test_choosing_the_current_language_does_nothing() -> void:
	GameConfig.set_locale("es")
	assert_array(_announced).is_empty()

func test_an_unknown_language_is_ignored() -> void:
	GameConfig.set_locale("fr")
	assert_str(Tr.get_locale()).is_equal("es")
	assert_array(_announced).is_empty()

func test_the_saved_language_is_applied_on_load() -> void:
	GameConfig.set_locale("en")
	GameConfig.ui_locale = "es"
	Tr.set_locale("es")
	GameConfig.load_user_settings()
	assert_str(Tr.get_locale()).is_equal("en")

func test_a_garbage_language_in_the_file_keeps_the_current_one() -> void:
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	cf.set_value("ui", "locale", "klingon")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_str(Tr.get_locale()).is_equal("es")
	assert_str(GameConfig.ui_locale).is_equal("es")

func test_the_settings_panel_offers_both_languages_and_switches() -> void:
	_panel = SettingsPanelScene.instantiate()
	add_child(_panel)
	var row: Node = _panel.find_child("LanguageRow", true, false)
	assert_object(row).is_not_null()
	var en_btn := row.get_node("Locale_en") as Button
	var es_btn := row.get_node("Locale_es") as Button
	assert_object(en_btn).is_not_null()
	assert_object(es_btn).is_not_null()
	assert_str(en_btn.text).is_equal("English")
	en_btn.pressed.emit()
	assert_str(Tr.get_locale()).is_equal("en")
	assert_array(_announced).is_equal(["en"])
