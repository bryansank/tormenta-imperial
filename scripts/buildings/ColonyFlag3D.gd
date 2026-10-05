extends Node3D
## El mastil con la bandera de la colonia sobre el Nucleo (vista 3D). Lo cuelga
## BuildingPlacer del Nucleo y se repinta solo al oir colony_cosmetics_changed:
## ningun servicio sabe que existe.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

## Alto del mastil por encima del Nucleo y tamano de la bandera (unidades).
const POLE_EXTRA := 2.4
const FLAG_W := 2.1

var _sprite: Sprite3D = null

## `footprint` en unidades de mundo (ancho, fondo); `top` = alto del Nucleo.
func setup(footprint: Vector2, top: float) -> void:
	name = "ColonyFlag"
	var height := top + POLE_EXTRA
	# En la esquina trasera derecha: no tapa la cupula ni el rotulo.
	position = Vector3(footprint.x * 0.38, 0.0, -footprint.y * 0.38)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = height
	pole.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.25)
	mat.metallic = 0.7
	mat.roughness = 0.4
	pole.material_override = mat
	pole.position.y = height * 0.5
	add_child(pole)
	_sprite = Sprite3D.new()
	_sprite.name = "Flag"
	_sprite.pixel_size = FLAG_W / float(ColonyFlag.W)
	_sprite.double_sided = true
	_sprite.shaded = false
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	# El borde izquierdo de la bandera, pegado al mastil, en lo alto.
	_sprite.position = Vector3(FLAG_W * 0.5 + 0.05, height - FLAG_W * float(ColonyFlag.H) / float(ColonyFlag.W) * 0.5, 0.0)
	add_child(_sprite)
	refresh()

func _ready() -> void:
	EventBus.colony_cosmetics_changed.connect(func(_f, _c): refresh())

func refresh() -> void:
	if _sprite != null:
		_sprite.texture = ColonyFlag.current_texture()

func flag_texture() -> Texture2D:
	return _sprite.texture if _sprite != null else null
