class_name BugReport
## El texto de "Informar de un fallo" (☰ MENÚ > PARTIDA): un bloque corto, listo
## para pegar en WhatsApp o en un issue de GitHub. Se copia al portapapeles y
## nada mas: no se envia a ningun sitio (docs/19 §7).
##
## Lleva lo que hace falta para reproducir (version, sistema, video, interfaz,
## partida) y las ultimas lineas del registro (ErrorLog). Sin datos personales:
## las rutas con el nombre de usuario pasan a "~" y ni el pais ni el nombre de
## la colonia salen (si aparecen en el registro, se tapan).

const LOG_LINES := 40
const WorldLookScript := preload("res://scripts/map/WorldLook.gd")

## Construye el informe (ya limpio). `lines` es el registro a incluir; por
## defecto, las ultimas LOG_LINES de ErrorLog.
static func build(lines: Variant = null) -> String:
	var log_lines: PackedStringArray = ErrorLog.recent_lines(LOG_LINES) if lines == null else PackedStringArray(lines)
	var out: PackedStringArray = []
	out.append("%s · %s %s" % [Tr.t("REPORT_TITLE"), "Tormenta Imperial",
		str(ProjectSettings.get_setting("application/config/version", "?"))])
	out.append("%s: %s" % [Tr.t("REPORT_SYSTEM"), _system_line()])
	out.append("%s: %s" % [Tr.t("REPORT_VIDEO"), _video_line()])
	out.append("%s: %s" % [Tr.t("REPORT_SCREEN"), _screen_line()])
	out.append("%s: %s" % [Tr.t("REPORT_GAME"), _game_line()])
	out.append("%s:" % Tr.t("REPORT_LOG"))
	out.append("```")
	out.append_array(log_lines)
	out.append("```")
	return sanitize("\n".join(out))

## Copia el informe al portapapeles y lo devuelve.
static func copy_to_clipboard() -> String:
	# Lo pendiente del registro, al disco antes: si el juego cae justo despues,
	# lo copiado y el archivo dicen lo mismo.
	ErrorLog.flush_now()
	var text := build()
	DisplayServer.clipboard_set(text)
	return text

# ── Lineas ───────────────────────────────────────────────────────────

static func _system_line() -> String:
	var parts: PackedStringArray = [OS.get_name(), OS.get_version()]
	if OS.get_name() == "Android":
		parts.append(OS.get_model_name())
	parts.append("dev" if GameConfig.dev_mode else "release")
	return " · ".join(parts)

static func _video_line() -> String:
	var adapter := RenderingServer.get_video_adapter_name()
	var api := RenderingServer.get_video_adapter_api_version()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	return "%s · %s %s · %s" % [adapter if adapter != "" else "?", driver, api, method]

static func _screen_line() -> String:
	var profile := "?"
	var dp: Node = Engine.get_main_loop().root.get_node_or_null("/root/DeviceProfile") if Engine.get_main_loop() is SceneTree else null
	if dp != null and dp.has_method("current"):
		profile = str(dp.current())
	var quality := GameConfig.ui_graphics_quality
	var effective: String = WorldLookScript.effective_quality(quality, RenderingServer.get_current_rendering_method())
	var win := DisplayServer.window_get_size()
	return "%s · %s %s (%s) · %s · %s · %dx%d" % [profile, Tr.t("REPORT_QUALITY"), quality, effective,
		GameConfig.ui_view_mode.to_upper(), GameConfig.ui_locale, win.x, win.y]

static func _game_line() -> String:
	if not GameManager.is_started():
		return Tr.t("REPORT_NO_GAME")
	var played := int(ProgressionManager.get_played_seconds())
	return "%s/%s · %s %d · %d min · x%d" % [GameMode.current_key(), GameMode.tier_key_of(GameMode.tier),
		Tr.t("REPORT_ERA"), ProgressionManager.current_era, played / 60, int(GameConfig.game_speed)]

# ── Limpieza ─────────────────────────────────────────────────────────

## Quita lo personal: rutas de la carpeta del usuario (Windows, macOS, Linux y
## la propia del user dir) pasan a "~"; el nombre de la colonia (lo elige el
## jugador, a menudo con su nombre o su pais) pasa a "<colonia>".
static func sanitize(text: String) -> String:
	var out := text
	for home in _home_dirs():
		out = out.replace(home, "~")
		out = out.replace(home.replace("\\", "/"), "~")
		out = out.replace(home.replace("/", "\\"), "~")
	var re := RegEx.new()
	# C:\Users\Nombre, C:/Users/Nombre, /Users/Nombre, /home/Nombre.
	re.compile("(?i)(?:[a-z]:)?[\\\\/]+(?:users|home)[\\\\/]+[^\\\\/\\s\"':]+")
	out = re.sub(out, "~", true)
	var colony := _colony_name()
	if colony.length() >= 3:
		out = out.replace(colony, "<colonia>")
	return out

static func _home_dirs() -> PackedStringArray:
	var dirs: PackedStringArray = []
	for key in ["USERPROFILE", "HOME"]:
		var v := OS.get_environment(key).strip_edges()
		# Una raiz ("/", "C:\") no es una carpeta personal: no se toca todo.
		if v.length() > 3:
			dirs.append(v.trim_suffix("\\").trim_suffix("/"))
	return dirs

static func _colony_name() -> String:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return ""
	var rank: Node = (loop as SceneTree).root.get_node_or_null("/root/RankManager")
	if rank != null and rank.has_method("get_colony_name"):
		return str(rank.get_colony_name()).strip_edges()
	return ""
