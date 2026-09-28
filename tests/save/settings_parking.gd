extends RefCounted
## Aparta user://settings.cfg (byte a byte) y el estado de interfaz de
## GameConfig mientras una suite toca preferencias, y lo devuelve despues.
## Mismo espiritu que save_parking.gd: reescribir el archivo con
## save_user_settings() le anadiria claves que el jugador no tenia.
##
##   var _parked := SettingsParking.park()   # before_test
##   SettingsParking.restore(_parked)        # after_test

const PATH := "user://settings.cfg"

## Campos de GameConfig que las suites de interfaz tocan.
const FIELDS := ["ui_device_profile", "ui_scale_pct", "ui_text_size", "ui_palette",
	"ui_high_contrast", "ui_panel_opacity", "ui_hud_hidden", "ui_layout",
	"ui_helper_visible", "ui_touch_controls", "ui_grid_visible", "ui_touch_controls_opacity"]

static func park() -> Dictionary:
	var snap := {"had": FileAccess.file_exists(PATH), "bytes": PackedByteArray(), "fields": {}}
	if snap["had"]:
		snap["bytes"] = FileAccess.get_file_as_bytes(PATH)
	for f in FIELDS:
		var v: Variant = GameConfig.get(f)
		snap["fields"][f] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return snap

static func restore(snap: Dictionary) -> void:
	if bool(snap.get("had", false)):
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(snap["bytes"])
			file.close()
	elif FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var fields: Dictionary = snap.get("fields", {})
	for f in fields:
		GameConfig.set(f, fields[f])
	# Los tokens de UITheme vuelven a los de la preferencia restaurada.
	UITheme.configure()
