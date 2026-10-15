extends RefCounted
## Los bancales de la Granja como malla aparte (docs/03, "La Granja"): los tres
## cultivos y el rotor del molino, horneados juntos en UNA malla con UNA
## superficie y el material compartido `assets/models/toy/toy_crops.tres`
## (shader `toy_crops.gdshader`). El crecimiento lo hace el shader con
## parametros por instancia (FarmCrops3D): nada de nodos ni mallas por frame.
##
## Cada planta se monta con un LotMesh alrededor de su base (0, 0, 0) y se
## anade con `add()`. Por vertice queda:
## - CUSTOM0 = (desplazamiento desde la base, variante): 0 lechuga, 1 patata,
##   2 trigo, 3 rotor del molino;
## - UV = (matiz de luz de la cara, parte): parte 0 hoja/tallo, 1 cabeza
##   (cogollo, flor, espiga), la que cambia de color al madurar;
## - VERTEX = la base mas el desplazamiento SOLO en la lechuga y el rotor; las
##   otras variantes quedan plegadas en su base. Sin el shader (el fantasma de
##   colocar le pone otro material) se ve un huerto de lechugas y el molino, no
##   tres cultivos encima uno de otro.
## - COLOR: el color de paleta (sRGB) para el rotor y lo que se ve sin shader.
##
## Solo para el horneado (tools/build_toy_models.gd): el juego carga lo horneado.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")

enum Variant { LETTUCE, POTATO, WHEAT, ROTOR }

## El gris con que se pintan las plantas: el LotMesh lo aclara u oscurece por
## cara y ese matiz (color / GRAY) es lo que guarda UV.x.
const GRAY := 0.8

var _base := PackedVector3Array()
var _off := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _var := PackedInt32Array()

## Un LotMesh vacio para montar una pieza alrededor de su base.
static func kit() -> RefCounted:
	return MeshKit.new()

## El gris de las plantas (con el que se pinta en el LotMesh de una planta).
static func gray() -> Color:
	return Color(GRAY, GRAY, GRAY)

func is_empty() -> bool:
	return _off.is_empty()

## Anade lo que lleve `mk` (su superficie solida) como pieza `variant` con base
## en `base` (marco de la receta). `part`: 0 hoja, 1 cabeza.
func add(base: Vector3, variant: int, mk, part := 0.0) -> void:
	var v: PackedVector3Array = mk._sv
	var n: PackedVector3Array = mk._sn
	var c: PackedColorArray = mk._sc
	for i in v.size():
		_base.append(base)
		_off.append(v[i])
		_n.append(n[i])
		_var.append(variant)
		if variant == Variant.ROTOR:
			_c.append(c[i])
			_uv.append(Vector2(1.0, 0.0))
		else:
			var shade := c[i].r / GRAY
			_c.append(Palette.color(Palette.Slot.GREEN) * Color(shade, shade, shade))
			_uv.append(Vector2(shade, part))

## La malla: las bases pasan por `fit` (el mismo encaje en planta que el resto
## del modelo); los desplazamientos no, para que el rotor gire redondo.
func commit(fit: Transform3D, material: Material) -> ArrayMesh:
	if is_empty():
		return null
	var verts := PackedVector3Array()
	var custom := PackedFloat32Array()
	verts.resize(_off.size())
	custom.resize(_off.size() * 4)
	for i in _off.size():
		var b := fit * _base[i]
		var o := _off[i]
		var shown := _var[i] == Variant.LETTUCE or _var[i] == Variant.ROTOR
		verts[i] = b + o if shown else b
		custom[i * 4] = o.x
		custom[i * 4 + 1] = o.y
		custom[i * 4 + 2] = o.z
		custom[i * 4 + 3] = float(_var[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, material)
	mesh.surface_set_name(0, "crops")
	return mesh

## Triangulos (para el informe del horneado).
func tri_count() -> int:
	return _off.size() / 3
