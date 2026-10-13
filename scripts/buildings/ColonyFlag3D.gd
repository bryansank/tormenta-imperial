extends Node3D
## El mastil con la bandera del pais (vista 3D), sobre el Nucleo y sobre el
## Cuartel General. Lo cuelga BuildingPlacer y se repinta solo al oir
## colony_identity_changed: ningun servicio sabe que existe.
##
## Barato a proposito ("debe ir en una papa"): la bandera es un plano de 6x1
## tramos con la textura de ColonyFlag (generada una vez por receta, cacheada) y
## el ondeo lo hace el shader de vertice con TIME, sin nada por frame en GDScript.
## Con la calidad grafica baja (WorldLook) no ondea.
##
## En el Cuartel General no se ve mientras esta en obra.
##
## Mastil del modelo: si el modelo horneado del edificio trae un Marker3D
## "FlagAnchor" (lo alto de su mastil, contrato con los modelos toy), la
## bandera se cuelga de ahi y este nodo no pone mastil propio. Sin marcador, el
## mastil propio en la esquina trasera derecha (reserva). En el Cuartel General
## la bandera va grande (`big`).

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const WorldLook := preload("res://scripts/map/WorldLook.gd")

## Alto del mastil por encima del edificio y ancho de la bandera (unidades).
const POLE_EXTRA := 2.4
const FLAG_W := 2.1
const WAVE_AMPLITUDE := 0.16
## Escala de la bandera grande (Cuartel General).
const BIG_SCALE := 1.6
const ANCHOR_NAME := "FlagAnchor"

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D flag_tex : source_color, filter_linear;
uniform float wave = 0.16;
void vertex() {
	// UV.x = 0 en el mastil (quieto), 1 en la punta (lo que mas se mueve).
	float t = TIME * 2.4 - UV.x * 5.5;
	VERTEX.z += sin(t) * wave * UV.x;
	VERTEX.y += sin(t * 0.7 + 1.3) * wave * 0.25 * UV.x;
}
void fragment() {
	vec4 c = texture(flag_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

static var _shader: Shader = null

static func flies_over(data: BuildingData) -> bool:
	return ColonyFlag.flies_over(data)

var _flag: MeshInstance3D = null
var _material: ShaderMaterial = null
var _owner_node: Node = null
var _anchored := false

## `footprint` en unidades de mundo (ancho, fondo); `top` = alto del edificio.
## `building` = el nodo del edificio (para esconderse mientras esta en obra).
func setup(footprint: Vector2, top: float, building: Node = null, big: bool = false) -> void:
	name = "ColonyFlag"
	_owner_node = building
	var height := top + POLE_EXTRA
	var flag_w := FLAG_W * (BIG_SCALE if big else 1.0)
	var flag_h := flag_w * float(ColonyFlag.H) / float(ColonyFlag.W)
	var anchor: Variant = find_anchor(building, self)
	_anchored = anchor != null
	# En la esquina trasera derecha: no tapa la cupula ni el rotulo.
	position = Vector3(footprint.x * 0.38, 0.0, -footprint.y * 0.38)
	if _anchored:
		# Lo alto del mastil del modelo: el origen de este nodo es ese punto.
		position = anchor
		height = 0.0
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = height
	cyl.radial_segments = 8
	cyl.rings = 1
	pole.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.25)
	mat.metallic = 0.7
	mat.roughness = 0.4
	pole.material_override = mat
	pole.position.y = height * 0.5
	pole.visible = not _anchored
	add_child(pole)
	var knob := MeshInstance3D.new()
	knob.name = "Knob"
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 8
	sphere.rings = 4
	knob.mesh = sphere
	knob.material_override = mat
	knob.position.y = height + 0.05
	knob.visible = not _anchored
	add_child(knob)

	var quad := PlaneMesh.new()
	quad.size = Vector2(flag_w, flag_h)
	quad.orientation = PlaneMesh.FACE_Z
	quad.subdivide_width = 5
	quad.subdivide_depth = 0
	_flag = MeshInstance3D.new()
	_flag.name = "Flag"
	_flag.mesh = quad
	_flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_flag.material_override = _material
	# El borde izquierdo de la bandera, pegado al mastil, en lo alto.
	_flag.position = Vector3(flag_w * 0.5 + 0.06, height - flag_h * 0.5 - 0.05, 0.0)
	add_child(_flag)
	refresh()
	_apply_quality()
	_sync_visible.call_deferred()

func _ready() -> void:
	EventBus.colony_identity_changed.connect(func(_n, _s): refresh())
	EventBus.graphics_quality_changed.connect(func(_q): _apply_quality())
	EventBus.construction_completed.connect(func(_b): _sync_visible.call_deferred())
	EventBus.construction_started.connect(func(_b): _sync_visible.call_deferred())
	EventBus.game_load_completed.connect(func(): _sync_visible.call_deferred())

func refresh() -> void:
	if _material != null:
		_material.set_shader_parameter("flag_tex", ColonyFlag.current_texture())

func _apply_quality() -> void:
	if _material == null:
		return
	var q := WorldLook.effective_quality(GameConfig.ui_graphics_quality, RenderingServer.get_current_rendering_method())
	_material.set_shader_parameter("wave", WAVE_AMPLITUDE if q == "high" else 0.0)

## En obra no ondea nada: la bandera sale al terminar (una mejora no la quita).
func _sync_visible() -> void:
	if _owner_node != null and is_instance_valid(_owner_node):
		visible = not is_hidden_by_works(_owner_node)

static func is_hidden_by_works(building: Node) -> bool:
	return building.has_meta("under_construction") and ProductionManager.get_upgrade_target(building) == 0

## El punto "FlagAnchor" del modelo del edificio, en el espacio del edificio, o
## null. El modelo es el primer hijo Node3D del edificio (como el FxAnchor de
## BuildingLookVisual).
static func find_anchor(building: Node, skip: Node = null) -> Variant:
	if building == null:
		return null
	var model: Node3D = null
	for child in building.get_children():
		if child == skip or not (child is Node3D):
			continue
		if child is Label3D or child is Sprite3D or child.is_in_group("building_fx"):
			continue
		if child.name in ["ConstructionBar", "LevelPlate", "LookVisual", "ColonyFlag"]:
			continue
		model = child
		break
	if model == null:
		return null
	var marker := model.find_child(ANCHOR_NAME, true, false) as Node3D
	if marker == null:
		return null
	var xf := Transform3D.IDENTITY
	var n: Node = marker
	while n != null and n != building:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin

func is_anchored() -> bool:
	return _anchored

func flag_texture() -> Texture2D:
	return _material.get_shader_parameter("flag_tex") if _material != null else null

func wave_amplitude() -> float:
	return float(_material.get_shader_parameter("wave")) if _material != null else 0.0
