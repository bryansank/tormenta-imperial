extends RefCounted
## La calidad grafica fuera del mundo 3D (docs/26 §7, docs/21 §12). Estatico, sin
## nodos: se usa con `preload` (como WorldLook en los paneles).
##
## WorldLook pinta el sol, el entorno, la isla y la resolucion del 3D. Esto se
## ocupa de lo demas que cambia con la calidad "minimal" (Minima):
##   - humo, serrin, farol y chispas (BuildingFx) ocultos: grupo FX_GROUP;
##   - banderines de obra quietos (SiteFx);
##   - la rejilla "siempre visible" no se pinta (solo al construir);
##   - tope de caminantes GameConfig.life_figure_cap_minimal;
##   - tope de FPS de 30 en PC (DeviceProfile.auto_fps);
##   - en PC, el renderizador Mobile desde el siguiente arranque (RENDERER_OVERRIDE_PATH).
## Y las reglas puras de la deteccion del primer arranque (§7.2), que DeviceProfile
## ejecuta.
##
## Una sola puerta para cambiar la calidad: set_quality(). Guarda, avisa con
## EventBus.graphics_quality_changed y pone o quita el override del renderizador.

const WorldLook := preload("res://scripts/map/WorldLook.gd")
const SiteFx := preload("res://scripts/buildings/SiteFx.gd")
const BuildingFx := preload("res://scripts/buildings/BuildingFx.gd")

## Los quads y sprites animados de BuildingFx (no sus contenedores: esos los
## enciende y apaga el aspecto del edificio).
const FX_GROUP := BuildingFx.FX_GROUP

## Archivo de ajustes del proyecto que el motor lee al arrancar
## (project.godot: application/config/project_settings_override). Vive en el
## user dir: se puede escribir en un .exe instalado en Program Files y no toca
## la instalacion. Solo lleva el renderizador; sin archivo, el de project.godot.
## El editor no lo lee (solo el juego), asi que no puede colarse en project.godot.
const RENDERER_OVERRIDE_PATH := "user://renderer_override.cfg"

# ── Consultas ─────────────────────────────────────────────────────────

## La calidad que vale ahora ("high", "low" o "minimal"), con "auto" resuelto.
static func current() -> String:
	return WorldLook.effective_quality(GameConfig.ui_graphics_quality,
		RenderingServer.get_current_rendering_method())

static func is_minimal() -> bool:
	return current() == "minimal"

## Si se ven el humo, el serrin, el farol y las chispas.
static func fx_enabled() -> bool:
	return not is_minimal()

## Si ondean los banderines de obra.
static func flags_wave() -> bool:
	return not is_minimal()

## La rejilla "siempre visible" de Ajustes, con la calidad aplicada: en Minima
## solo se ve al construir.
static func grid_always_visible() -> bool:
	return GameConfig.ui_grid_visible and not is_minimal()

static func is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

# ── Cambiar la calidad ────────────────────────────────────────────────

## Pone la calidad, la guarda en settings.cfg y la aplica. Devuelve true si
## ademas hace falta reiniciar para que cambie el renderizador (PC: entrar en
## Minima o salir de ella).
static func set_quality(quality: String) -> bool:
	if not quality in GameConfig.GRAPHICS_QUALITY_MODES:
		return false
	GameConfig.ui_graphics_quality = quality
	GameConfig.save_user_settings()
	EventBus.graphics_quality_changed.emit(quality)
	return sync_renderer_override()

## Lo que no es del mundo 3D: caminantes, efectos, banderines y rejilla. Lo
## llama DeviceProfile al arrancar y con cada graphics_quality_changed.
static func apply_runtime(tree: SceneTree) -> void:
	var minimal := is_minimal()
	GameConfig.life_figure_cap_quality = int(GameConfig.life_figure_cap_minimal) if minimal else -1
	SiteFx.set_flags_wave(not minimal)
	BuildingFx.anim_visible = not minimal
	if tree != null:
		tree.call_group(FX_GROUP, "set_visible", not minimal)
		# El mismo aviso que el interruptor de Ajustes: la rejilla de las dos
		# vistas se pone como diga la preferencia con la calidad aplicada.
		EventBus.grid_overlay_toggled.emit(grid_always_visible())

# ── Renderizador (PC) ─────────────────────────────────────────────────

## El renderizador que deberia arrancar con esta calidad, o "" para el de
## project.godot. Puro. Solo en PC y solo para Minima. Si hoy va en
## Compatibility (sin Vulkan ni D3D12, o forzado), no se pide Mobile: no
## arrancaria mejor.
static func renderer_for(quality: String, mobile_platform: bool, current_renderer: String) -> String:
	if mobile_platform or quality != "minimal":
		return ""
	if current_renderer == "gl_compatibility":
		return ""
	return "mobile"

## El renderizador que pide el archivo de override, o "".
static func renderer_override() -> String:
	var cf := ConfigFile.new()
	if cf.load(RENDERER_OVERRIDE_PATH) != OK:
		return ""
	return str(cf.get_value("rendering", "renderer/rendering_method", ""))

## Escribe o borra el override segun la calidad elegida. Devuelve true si el
## renderizador del proximo arranque no es el de ahora (hay que reiniciar).
static func sync_renderer_override() -> bool:
	# Sin pantalla (tests, sondas headless) no hay renderizador que cambiar.
	if DisplayServer.get_name() == "headless":
		return false
	var current_renderer := RenderingServer.get_current_rendering_method()
	var want := renderer_for(GameConfig.ui_graphics_quality, is_mobile_platform(), current_renderer)
	if want == "":
		if FileAccess.file_exists(RENDERER_OVERRIDE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_OVERRIDE_PATH))
	else:
		var cf := ConfigFile.new()
		cf.set_value("rendering", "renderer/rendering_method", want)
		if cf.save(RENDERER_OVERRIDE_PATH) != OK:
			push_warning("[GraphicsQuality] no se pudo escribir %s" % RENDERER_OVERRIDE_PATH)
			return false
	var next := want if want != "" else default_renderer()
	return next != current_renderer

## El renderizador de project.godot para esta plataforma, sin el override. Va
## escrito aqui y no leido: con el override cargado, ProjectSettings ya devuelve
## el del override. Si cambia project.godot, cambia esto.
const DEFAULT_RENDERER_PC := "forward_plus"
const DEFAULT_RENDERER_MOBILE := "mobile"

static func default_renderer() -> String:
	return DEFAULT_RENDERER_MOBILE if is_mobile_platform() else DEFAULT_RENDERER_PC

# ── Deteccion del primer arranque (reglas puras, docs/26 §7.2) ────────

## Paso 1: senales estaticas. `info`: renderer, adapter_type (RenderingDevice.
## DeviceType), adapter_name, ram_mb (-1 si no se sabe), threads, profile
## ("pc"/"tablet"/"phone"), mobile (bool). Devuelve {"quality": "minimal" o "",
## "reason": String}. "" = no decide: toca medir.
static func static_verdict(info: Dictionary) -> Dictionary:
	var renderer := str(info.get("renderer", ""))
	if renderer == "gl_compatibility":
		return {"quality": "minimal", "reason": "renderer=gl_compatibility"}
	var gpu_name := str(info.get("adapter_name", ""))
	if gpu_name_is_weak(gpu_name):
		return {"quality": "minimal", "reason": "gpu=" + gpu_name}
	var ram := int(info.get("ram_mb", -1))
	var threads := int(info.get("threads", 0))
	var weak_ram := ram > 0 and ram <= int(GameConfig.quality_weak_ram_mb)
	var weak_cpu := threads > 0 and threads <= int(GameConfig.quality_weak_threads)
	if weak_ram:
		return {"quality": "minimal", "reason": "ram_mb=%d" % ram}
	if weak_cpu:
		return {"quality": "minimal", "reason": "threads=%d" % threads}
	if str(info.get("profile", "")) == "phone" and ram > 0 and ram <= int(GameConfig.quality_phone_ram_mb):
		return {"quality": "minimal", "reason": "phone ram_mb=%d" % ram}
	# Integrada sin mas senales: no basta (una Iris Xe o una 780M mueven Alta).
	return {"quality": "", "reason": ""}

## Si el nombre de la GPU esta en la lista de flojas (GameConfig.quality_weak_gpu_patterns,
## expresiones regulares sin distinguir mayusculas).
static func gpu_name_is_weak(adapter_name: String) -> bool:
	if adapter_name == "":
		return false
	for pattern in GameConfig.quality_weak_gpu_patterns:
		var re := RegEx.new()
		if re.compile("(?i)" + str(pattern)) != OK:
			continue
		if re.search(adapter_name) != null:
			return true
	return false

## Paso 2: veredicto de la medida. `frame_ms`: tiempos de fotograma en ms;
## `measured_quality`: la calidad con la que se midio; `refresh_hz`: el refresco
## de la pantalla (con vsync la medida no baja de 1000/refresco: un monitor de 50
## Hz da 20 ms aunque sobre equipo, y eso no es "flojo"). "minimal", "low" o ""
## (se queda como esta).
static func measure_verdict(frame_ms: Array, measured_quality: String, refresh_hz: float = 60.0) -> String:
	if frame_ms.size() < 10:
		return ""
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var median := float(sorted[sorted.size() / 2])
	var p95 := float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])
	if median > float(GameConfig.quality_detect_median_ms) or p95 > float(GameConfig.quality_detect_p95_ms):
		return "minimal"
	var low_ms := float(GameConfig.quality_detect_low_ms)
	if refresh_hz > 0.0:
		low_ms = maxf(low_ms, 1000.0 / refresh_hz * 1.1)
	if measured_quality == "high" and median > low_ms:
		return "low"
	return ""
