extends RefCounted
## Las unidades de juguete horneadas (tools/build_toy_models.gd -- --units,
## assets/models/toy/units/) y el unico material que la vista les anade: el del
## color del bando, compartido por todas las piezas de ese color.
##
## Cada unidad es UNA malla con color por vertice y los dos materiales comunes
## de la maqueta (ToyPalette); las del jugador traen ademas una superficie
## "team" en grises que aqui se pinta con el color de la colonia
## (RankManager.get_color()). Las de la Regencia llevan su morado ya horneado.
## Asi una pelea entera son, como mucho, tres materiales: solido, brillo y
## colonia. Nada de materiales por unidad ni luces propias.
##
## El regimiento (docs/15 §12, solo cosmetico) cambia el color de esa superficie
## y le puede poner una pintura (rayas, manchas...): con pintura, el material es
## un ShaderMaterial de regiment_paint.gdshader, uno por color y pintura, y
## sigue siendo compartido por todas las piezas que lo llevan.

const Palette := preload("res://scripts/buildings/ToyPalette.gd")

const DIR := "res://assets/models/toy/units/"
const BOSS_MARK := DIR + "boss_mark.tscn"
const CREW_NEST := DIR + "crew_nest.tscn"
const TEAM_SURFACE := "team"
const PAINT_SHADER := preload("res://scripts/combat_view/regiment_paint.gdshader")

static var _scenes: Dictionary = {}
static var _team_mats: Dictionary = {}

## La escena de una unidad para un bando (0 jugador, 1 enemigo), o "" si no hay
## modelo horneado para ese tipo (una unidad futura sin receta todavia).
static func scene_path(unit_id: String, side: int) -> String:
	var path := "%s%s_%s.tscn" % [DIR, unit_id, "player" if side == 0 else "regency"]
	return path if ResourceLoader.exists(path) else ""

static func load_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]

## Instancia el modelo de una unidad. Sin modelo, una caja de juguete del color
## del bando: una unidad nueva nunca se queda sin cuerpo en el tablero.
## `paint`: la pintura del regimiento (GameConfig.REGIMENT_PAINTS), solo para
## las nuestras; "plain" = el material de siempre.
static func instantiate(unit_id: String, side: int, team_color: Color, paint: String = "plain") -> Node3D:
	var scene := load_scene(scene_path(unit_id, side))
	if scene == null:
		return _fallback(team_color)
	var node: Node3D = scene.instantiate()
	paint_team(node, team_color, paint)
	return node

static func instantiate_prop(path: String) -> Node3D:
	var scene := load_scene(path)
	return scene.instantiate() if scene != null else null

## Pone el material del color del bando en la superficie "team" de la malla.
static func paint_team(node: Node, color: Color, paint: String = "plain") -> void:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var idx: int = mi.mesh.surface_find_by_name(TEAM_SURFACE)
	if idx >= 0:
		mi.set_surface_override_material(idx, team_material(color, paint))

## Un material por color y pintura (no por unidad): el mismo para las seis
## piezas. Liso = el StandardMaterial de la maqueta, como antes del regimiento.
static func team_material(color: Color, paint: String = "plain") -> Material:
	var plain := paint == "plain" or not (paint in GameConfig.REGIMENT_PAINTS)
	var key := color.to_html(false) if plain else "%s|%s" % [color.to_html(false), paint]
	if not _team_mats.has(key):
		if plain:
			var m: StandardMaterial3D = Palette.make_solid()
			m.albedo_color = color
			_team_mats[key] = m
		else:
			var sm := ShaderMaterial.new()
			sm.shader = PAINT_SHADER
			sm.set_shader_parameter("team_color", color)
			sm.set_shader_parameter("paint", GameConfig.REGIMENT_PAINTS.find(paint))
			_team_mats[key] = sm
	return _team_mats[key]

static func _fallback(color: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.7, 0.9)
	mi.mesh = box
	mi.position.y = 0.35
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	var root := Node3D.new()
	root.add_child(mi)
	return root

## Triangulos de una malla (pruebas: el presupuesto de <= 800 por unidad).
static func tri_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var t := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
