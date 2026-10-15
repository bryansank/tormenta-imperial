extends WorldEnvironment
## La luz y el ambiente del mapa 3D (docs/21 §12): el aire de maqueta.
##
## Direccion de arte (2026-10-05): diorama de juguete, colores calidos y
## saturados, luz suave con sombras marcadas. El cielo, la luz ambiental, el
## tonemapping y el sol estan en Main.tscn; este script solo decide lo que cuesta
## GPU y no existe en todos los renderizadores:
##
## - **SSAO**: solo Forward+ (Mobile y Compatibility no lo tienen).
## - **Glow**: Forward+ y Mobile; en Compatibility (APK de QA) se apaga.
## - **Sombras del sol**: cuatro cortes en alta con Forward+, dos con Mobile,
##   uno en baja. Su distancia sigue al zoom de la camara: de cerca, la sombra
##   usa toda su resolucion en lo que se ve; de lejos, alcanza el borde.
## - **Radiancia del cielo**: pequena (la cambia la Tormenta mientras funde).
## - **Isla sencilla** (`island_simple`, en baja y minima): los shaders de la isla
##   se saltan las ondas del agua, las lineas de espuma y el grano del cesped
##   (uniform `simple`, el mismo valor en todo el material: la rama no cuesta).
## - **Minima** ("minimal", 2026-10-12; en Ajustes desde 2026-10-14): para "una
##   papa" (grafica integrada vieja, tablet barata). Sin sombras, sin SSAO, sin
##   glow, sin MSAA, isla sencilla y el 3D a `MINIMAL_SCALE` de la resolucion
##   (`MINIMAL_SCALE_MOBILE` en Android; `scaling_3d_scale`, la UI no se escala).
##   Lo que no es del mundo (humo, rejilla, caminantes, FPS, renderizador) lo
##   pone GraphicsQuality.
##
## La calidad la elige el jugador en Ajustes -> Interfaz ("auto", "high",
## "low", "minimal"; GameConfig.ui_graphics_quality en settings.cfg), o la
## deteccion del primer arranque (DeviceProfile, docs/26 §7.2). "auto" es baja con
## Mobile o Compatibility. No toca colores ni energias: eso es de StormSky,
## que los guarda limpios y los oscurece por fase.

## La sombra cubre la distancia de la camara a su objetivo por esto, mas un
## margen fijo, entre estos topes (unidades de mundo).
const SHADOW_DISTANCE_FACTOR := 1.6
const SHADOW_DISTANCE_PAD := 18.0
const SHADOW_DISTANCE_MIN := 30.0
const SHADOW_DISTANCE_MAX := 200.0
## Resolucion del 3D en calidad minima (fraccion de la de la ventana).
const MINIMAL_SCALE := 0.7
## La misma en movil y tablet (pantallas densas: 0,6 se sigue viendo bien).
const MINIMAL_SCALE_MOBILE := 0.6
const QUALITIES := ["high", "low", "minimal"]
## Los nodos de la isla (IslandGenerator.NODE_NAMES) con el uniform `simple`.
const ISLAND_NODES := ["Ground", "Cliff", "Shore", "Foam", "Water"]

var _sun: DirectionalLight3D = null
var _quality := "high"

func _ready() -> void:
	_sun = get_parent().get_node_or_null("DirectionalLight") as DirectionalLight3D
	EventBus.graphics_quality_changed.connect(func(_q: String): apply())
	apply()

## Aplica la calidad de GameConfig al entorno y al sol de esta escena.
func apply() -> void:
	var renderer := RenderingServer.get_current_rendering_method()
	_quality = effective_quality(GameConfig.ui_graphics_quality, renderer)
	var s := settings_for(_quality, renderer)
	configure(environment, _sun, s, get_viewport())
	paint_island(get_parent(), bool(s["island_simple"]))

func get_quality() -> String:
	return _quality

## Si la isla de esta escena va en version sencilla. IslandGenerator lo lee al
## crear sus materiales; los ya creados los repinta `apply()`.
func island_simple() -> bool:
	return bool(settings_for(_quality, RenderingServer.get_current_rendering_method())["island_simple"])

## Pone `simple` en los materiales de la isla 3D bajo `scene`. Solo al cambiar
## de calidad: nada por frame.
static func paint_island(scene: Node, simple: bool) -> void:
	if scene == null:
		return
	for node_name in ISLAND_NODES:
		var mesh := scene.get_node_or_null(node_name) as MeshInstance3D
		if mesh == null:
			continue
		var mat := mesh.get_surface_override_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("simple", simple)

func _process(_delta: float) -> void:
	if _sun == null or not is_instance_valid(_sun) or not _sun.shadow_enabled:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.has_method("get_state"):
		return
	var want := shadow_distance_for(float(cam.get_state().get("distance", 30.0)))
	if absf(_sun.directional_shadow_max_distance - want) > 1.0:
		_sun.directional_shadow_max_distance = want

# ── Reglas puras (los tests las fijan sin escena) ─────────────────────

## "auto" -> alta solo con Forward+ (PC); Mobile y Compatibility, baja.
static func effective_quality(pref: String, renderer: String) -> String:
	if pref in QUALITIES:
		return pref
	return "high" if renderer == "forward_plus" else "low"

## Que se enciende con cada calidad en cada renderizador. `platform`: "mobile",
## "pc" o "" (el de este equipo).
static func settings_for(quality: String, renderer: String, platform: String = "") -> Dictionary:
	var high := quality == "high"
	var minimal := quality == "minimal"
	var mobile := platform == "mobile"
	if platform == "":
		mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var shadow_mode := DirectionalLight3D.SHADOW_ORTHOGONAL
	if high:
		shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if renderer == "forward_plus" \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Fuera de Minima, la de project.godot (rendering/scaling_3d/scale: 0,75
	# en movil con su variante .mobile, 1,0 en PC).
	var scale_3d := float(ProjectSettings.get_setting_with_override("rendering/scaling_3d/scale"))
	if minimal:
		scale_3d = MINIMAL_SCALE_MOBILE if mobile else MINIMAL_SCALE
	return {
		"ssao": high and renderer == "forward_plus",
		"glow": high and renderer != "gl_compatibility",
		"shadow_mode": shadow_mode,
		"radiance_size": Sky.RADIANCE_SIZE_64 if high else Sky.RADIANCE_SIZE_32,
		"shadows": not minimal,
		"island_simple": not high,
		"scale_3d": scale_3d,
		"msaa": not minimal,
	}

## Distancia de sombra del sol para una camara a `cam_distance` de su objetivo.
static func shadow_distance_for(cam_distance: float) -> float:
	return clampf(cam_distance * SHADOW_DISTANCE_FACTOR + SHADOW_DISTANCE_PAD,
		SHADOW_DISTANCE_MIN, SHADOW_DISTANCE_MAX)

static func configure(env: Environment, sun: DirectionalLight3D, s: Dictionary, viewport: Viewport = null) -> void:
	if env != null:
		env.ssao_enabled = bool(s["ssao"])
		env.glow_enabled = bool(s["glow"])
		if env.sky != null:
			env.sky.radiance_size = int(s["radiance_size"])
	if sun != null:
		sun.shadow_enabled = bool(s["shadows"])
		sun.directional_shadow_mode = int(s["shadow_mode"])
	if viewport != null:
		viewport.scaling_3d_scale = float(s["scale_3d"])
		# Sin MSAA en Minima: el reescalado bilineal ya suaviza. Con las demas,
		# el de project.godot (con su variante .mobile).
		var msaa: int = Viewport.MSAA_DISABLED
		if bool(s.get("msaa", true)):
			msaa = int(ProjectSettings.get_setting_with_override("rendering/anti_aliasing/quality/msaa_3d"))
		viewport.msaa_3d = msaa as Viewport.MSAA

