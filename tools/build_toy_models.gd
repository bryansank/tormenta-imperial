extends SceneTree
## Horneado de los modelos "maqueta" de los edificios (docs/03, "Modelos:
## maqueta de juguete"; guia de estilo de edificios).
##
##     godot --headless --path . -s tools/build_toy_models.gd
##     godot --headless --path . -s tools/build_toy_models.gd -- --only=house,sawmill
##     godot --headless --path . -s tools/build_toy_models.gd -- --dump=kk:barrel,kn:chimney-large
##     godot --headless --path . -s tools/build_toy_models.gd -- --dump=all
##     godot --headless --path . -s tools/build_toy_models.gd -- --units
##     godot --headless --path . -s tools/build_toy_models.gd -- --units --only=infantry
##
## `--units` hornea las unidades de combate en vez de los edificios (docs/15
## §3, "El tablero 3D"): recetas en tools/toy_recipes/units/<id>.gd, salida en
## assets/models/toy/units/ (ver `_bake_units()`).
##
## Cada edificio tiene su receta en tools/toy_recipes/<id>.gd: compone piezas
## CC0 (KayKit, Kenney; assets/models/cc0/, solo fuente) pasadas a la paleta
## comun (ToyPalette) y piezas propias (tools/toy_recipes/_parts.gd) en un
## LotMesh. Sale:
##
## - assets/models/toy/<id>_mesh.res: la malla horneada (color por vertice, una
##   superficie solida y, si hay algo encendido, otra de brillo);
## - assets/models/toy/<id>.tscn: un MeshInstance3D con esa malla como raiz y,
##   en los edificios con humo o serrin, un Marker3D "FxAnchor" (de ahi sale el
##   efecto de "trabajando", BuildingLookVisual);
## - en la Granja, ademas, un hijo MeshInstance3D "Crops" con la malla de los
##   bancales (`farm_crops_mesh.res`: los cultivos y el rotor del molino, ver
##   tools/toy_crops.gd), el material compartido `toy_crops.tres` y el script
##   FarmCrops3D, que los hace crecer con parametros por instancia;
## - assets/models/toy/toy_solid.tres / toy_glow.tres: los dos materiales que
##   comparte todo el mapa (solo se crean si faltan: se pueden retocar a mano).
##
## Cada modelo se hornea YA a la medida del rectangulo que le deja su parcela
## (LotPlan.model_rect), con el centro en el origen y la base en y = 0, frente
## hacia +Z: BuildingLot.fit_model() no tiene que escalarlo. No corre en el
## juego: el juego solo carga lo horneado.

const Kit := preload("res://tools/toy_kit.gd")
const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")

const OUT := "res://assets/models/toy/"
const RECIPES := "res://tools/toy_recipes/"
const CELL := 2.0

## Los que se hornean (la calzada no: su malla depende de los vecinos).
const IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "market", "laboratory",
	"foundry", "barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "farm",
	# Edificios utiles de la 1.1 (feat/edificios-utiles-1). Hasta hornearlos, el
	# juego usa su version procedural (scripts/buildings/UtilityToys.gd).
	"windmill", "silo", "tavern", "carpentry", "well", "lighthouse", "fuel_depot",
	# Las diez decoraciones baratas (feat/decoraciones-1); en el juego las carga
	# DecorMesh (<id>_mesh.res) y, sin hornear, usa su version procedural.
	"lamp_post", "park_bench", "hedge", "avenue_tree", "flower_planter",
	"colony_sign", "hay_cart", "bonfire", "flagpole", "palm_trees",
	# Astillero y Aerodromo (1.1, feat/aire-mar-vista); sus .tres (rama de
	# reglas) mandan en la huella, EXTRA solo cubre si faltaran.
	"shipyard", "aerodrome",
	# Muelle de pesca (feat/muelle-pesca).
	"fishing_dock"]

## Presupuesto de triangulos de una decoracion 2x2 (doc 21 §6.6).
const DECOR_TRI_BUDGET := 600

## Huella y patio de lo que aun no tiene .tres (la Granja usa el rectangulo de
## su parcela, GameConfig.building_lot_style["farm"]). Con su .tres, manda el
## .tres y su parcela; EXTRA solo cubre el hueco hasta que llegue.
const EXTRA := {
	"shipyard": {"grid": Vector2i(2, 2), "yard": 0.3},
	"aerodrome": {"grid": Vector2i(2, 2), "yard": 0.3},
}

## La malla de los bancales de la Granja (tools/toy_crops.gd): su material
## compartido y el script que la mueve.
const CROPS_MAT := "res://assets/models/toy/toy_crops.tres"
const CROPS_SCRIPT := "res://scripts/buildings/FarmCrops3D.gd"

## Oscurecimiento de contacto: lo que queda por debajo de esta altura se
## oscurece hasta AO_DARK en y = 0 (ancla el modelo a la parcela, regla 5).
const AO_HEIGHT := 0.22
const AO_DARK := 0.22
## Borde oscuro de contacto (V8): en las paredes, una franja fina de EDGE_HEIGHT
## que se oscurece hasta EDGE_DARK en y = 0, encima del AO. Se lee de lejos,
## en la Tormenta y de noche (LotMesh.contact_edge). Solo en los edificios: las
## unidades siguen con el AO de _finish_colors().
const EDGE_HEIGHT := 0.12
const EDGE_DARK := 0.42

var _kit: Kit = null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var only: Array = []
	var dump := ""
	var units := false
	for a in OS.get_cmdline_user_args():
		if a == "--units":
			units = true
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(",", false))
		elif a.begins_with("--dump="):
			dump = a.substr(7)
	_kit = Kit.new()
	if dump != "":
		_dump(dump)
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_ensure_materials()
	if units:
		var bad := _bake_units(only)
		print("build_toy_models: unidades hechas (%d con error)" % bad)
		quit(1 if bad > 0 else 0)
		return
	var failed := 0
	for id in IDS:
		if not only.is_empty() and not only.has(id):
			continue
		if not _bake(id):
			failed += 1
	print("build_toy_models: hecho (%d con error)" % failed)
	quit(1 if failed > 0 else 0)

# ── Materiales ────────────────────────────────────────────────────────

func _ensure_materials() -> void:
	Palette._solid = _material(Palette.SOLID_PATH, Palette.make_solid())
	Palette._glow = _material(Palette.GLOW_PATH, Palette.make_glow())

func _material(path: String, fresh: Material) -> Material:
	if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		var m: Material = load(path)
		if m != null:
			return m
	ResourceSaver.save(fresh, path, ResourceSaver.FLAG_CHANGE_PATH)
	return fresh

# ── Horneado ──────────────────────────────────────────────────────────

## Rectangulo del modelo en metros: {"w", "d"} (x, z) y la huella.
func _target(id: String) -> Dictionary:
	var grid := Vector2i(2, 2)
	var yard := 0.3
	if EXTRA.has(id) and not ResourceLoader.exists("res://data/buildings/%s.tres" % id):
		grid = EXTRA[id]["grid"]
		yard = float(EXTRA[id]["yard"])
	else:
		var data: Resource = load("res://data/buildings/%s.tres" % id)
		grid = data.grid_size
		var plan_script: GDScript = load("res://scripts/buildings/LotPlan.gd")
		if plan_script.has_lot(id):
			var r: Rect2 = plan_script.model_rect(id, grid)
			return {"w": r.size.x * CELL, "d": r.size.y * CELL, "grid": grid}
		yard = 0.0
	var s := (Vector2(grid) - Vector2(yard, yard) * 2.0) * CELL
	return {"w": s.x, "d": s.y, "grid": grid}

func _bake(id: String) -> bool:
	var path := RECIPES + id + ".gd"
	if not ResourceLoader.exists(path):
		push_error("build_toy_models: falta la receta " + path)
		return false
	var recipe: Object = (load(path) as GDScript).new()
	var mk := MeshKit.new()
	var ctx := _target(id)
	ctx["id"] = id
	var res = recipe.call("build", mk, _kit, ctx)
	var out: Dictionary = res if res is Dictionary else {}
	var fitted := _fit_plan(mk, float(ctx["w"]), float(ctx["d"]))
	if out.has("fx"):
		out["fx"] = fitted * (out["fx"] as Vector3)
	mk.contact_edge(AO_HEIGHT, AO_DARK, EDGE_HEIGHT, EDGE_DARK)
	var mesh := mk.commit()
	if mesh == null:
		push_error("build_toy_models: %s sale vacio" % id)
		return false
	mesh.resource_name = id
	var mesh_path := OUT + id + "_mesh.res"
	var err := ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("build_toy_models: no guarda %s (%d)" % [mesh_path, err])
		return false
	var root := MeshInstance3D.new()
	root.name = "Toy_" + id
	root.mesh = mesh
	if out.has("fx"):
		var anchor := Marker3D.new()
		anchor.name = "FxAnchor"
		anchor.position = out["fx"]
		root.add_child(anchor)
		anchor.owner = root
	var crop_tris := 0
	if out.has("crops"):
		crop_tris = _add_crops(root, id, out["crops"], fitted)
		if crop_tris < 0:
			root.free()
			return false
	# FlagAnchor: donde se cuelga la bandera del pais (feat/bandera-y-pais).
	# "flag" va en el marco de la receta (sigue al encaje); "flag_over_top" es
	# {x, z, alto sobre la cima} en el marco del edificio, para casar con un
	# mastil que no es del modelo (ColonyFlag3D en el Nucleo).
	var flag_at = null
	if out.has("flag"):
		flag_at = fitted * (out["flag"] as Vector3)
	elif out.has("flag_over_top"):
		# La misma cima que mide BuildingPlacer: max(mesh_height, la malla).
		var f: Vector3 = out["flag_over_top"]
		var top := mesh.get_aabb().end.y
		var tres := "res://data/buildings/%s.tres" % id
		if ResourceLoader.exists(tres):
			top = maxf(top, float(load(tres).mesh_height))
		flag_at = Vector3(f.x, top + f.y, f.z)
	if flag_at != null:
		var fa := Marker3D.new()
		fa.name = "FlagAnchor"
		fa.position = flag_at
		root.add_child(fa)
		fa.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	err = ResourceSaver.save(scene, OUT + id + ".tscn")
	root.free()
	if err != OK:
		push_error("build_toy_models: no guarda la escena de %s (%d)" % [id, err])
		return false
	var a := mesh.get_aabb()
	if preload("res://scripts/buildings/DecorMesh.gd").handles(id) and Kit.tri_count(mesh) > DECOR_TRI_BUDGET:
		print("build_toy_models:   ** %s PASA DEL PRESUPUESTO DE DECORACION (%d) **" % [id, DECOR_TRI_BUDGET])
	print("build_toy_models: %-13s %5d tri  %.2f x %.2f x %.2f (objetivo %.2f x %.2f)%s" % [
		id, Kit.tri_count(mesh), a.size.x, a.size.y, a.size.z, ctx["w"], ctx["d"],
		("  FxAnchor" if out.has("fx") else "") + ("  FlagAnchor" if flag_at != null else "")
		+ ("  Crops %d tri" % crop_tris if crop_tris > 0 else "")])
	return true

## Los bancales de la Granja: la malla aparte (`<id>_crops_mesh.res`) colgada
## del modelo como "Crops", con el material compartido y FarmCrops3D. Devuelve
## sus triangulos (-1 si falla).
func _add_crops(root: Node3D, id: String, crops, fitted: Transform3D) -> int:
	var mat: Material = load(CROPS_MAT)
	var mesh: ArrayMesh = crops.commit(fitted, mat)
	if mesh == null:
		return 0
	mesh.resource_name = id + "_crops"
	var path := OUT + id + "_crops_mesh.res"
	var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("build_toy_models: no guarda %s (%d)" % [path, err])
		return -1
	var mi := MeshInstance3D.new()
	mi.name = "Crops"
	mi.mesh = mesh
	mi.set_script(load(CROPS_SCRIPT))
	root.add_child(mi)
	mi.owner = root
	return crops.tri_count()

## Lo mismo que BuildingLot.fit_model(), pero horneado: encoge en planta (nunca
## en altura, nunca agranda) y centra lo que la receta haya dejado salirse de
## su rectangulo. Asi en el juego el modelo ya mide lo que debe. Devuelve la
## transformacion aplicada (para el FxAnchor).
func _fit_plan(mk, w: float, d: float) -> Transform3D:
	var box := AABB()
	var first := true
	for arr in [mk._sv, mk._gv]:
		for p in arr:
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	if first:
		return Transform3D.IDENTITY
	var f := minf(1.0, minf(w / maxf(box.size.x, 0.001), d / maxf(box.size.z, 0.001)))
	var c := box.get_center()
	var xf := Transform3D(Basis.from_scale(Vector3(f, 1.0, f)), Vector3(-c.x * f, 0.0, -c.z * f))
	if is_equal_approx(f, 1.0) and absf(c.x) < 0.005 and absf(c.z) < 0.005:
		return Transform3D.IDENTITY
	for pair in [["_sv", "_sn"], ["_gv", "_gn"]]:
		var v: PackedVector3Array = mk.get(pair[0])
		var n: PackedVector3Array = mk.get(pair[1])
		for i in v.size():
			v[i] = xf * v[i]
			n[i] = Vector3(n[i].x / f, n[i].y, n[i].z / f).normalized()
		mk.set(pair[0], v)
		mk.set(pair[1], n)
	if f < 0.97:
		print("build_toy_models:   (encogido en planta x%.2f para caber)" % f)
	return xf

## Oscurece los vertices solidos pegados al suelo (AO de contacto horneado).
## El color queda en sRGB, como esta escrito en ToyPalette: los dos materiales
## compartidos lo leen asi (`vertex_color_is_srgb`).
func _finish_colors(mk) -> void:
	var v: PackedVector3Array = mk._sv
	var c: PackedColorArray = mk._sc
	for i in v.size():
		var y := v[i].y
		if y < AO_HEIGHT:
			c[i] = c[i].darkened(AO_DARK * (1.0 - maxf(0.0, y) / AO_HEIGHT))
	mk._sc = c

# ── Unidades de combate ───────────────────────────────────────────────
#
# Una unidad por tipo y bando: `<id>_player` y `<id>_regency`, mas dos piezas de
# atrezo que la vista pone encima (`boss_mark`, el estandarte del jefe, y
# `crew_nest`, el nido de sacos de una dotacion de torre). La receta recibe DOS
# LotMesh: `mk` (lo de siempre, con su color) y `team` (lo que lleva el color
# del bando, pintado en grises que multiplican). Con el jugador `team` sale como
# una TERCERA superficie llamada "team", con material `toy_team.tres`: la vista
# le pone encima el color de la colonia (RankManager.get_color()) con un unico
# material compartido por color. Con la Regencia se hornea ya con su paleta
# (REGENCY_COLOR) dentro de la superficie solida: no hay nada que cambiar.
#
# Cada unidad cabe en UNIT_FOOTPRINT (una casilla del tablero mide 2 m), base en
# y = 0, frente hacia +Z. Presupuesto: UNIT_TRI_BUDGET triangulos.

const UNIT_RECIPES := "res://tools/toy_recipes/units/"
const UNIT_OUT := "res://assets/models/toy/units/"
const UNIT_IDS := ["infantry", "artillery", "vehicle",
	# Mar y aire (1.1, feat/aire-mar-vista): docs/15 §11.
	"torpedo_boat", "gunboat", "dreadnought", "fighter", "bomber", "airship"]
const UNIT_SIDES := ["player", "regency"]
const UNIT_PROPS := ["boss_mark", "crew_nest"]
const UNIT_FOOTPRINT := 1.7
const UNIT_TRI_BUDGET := 800
const TEAM_PATH := "res://assets/models/toy/units/toy_team.tres"
## El morado de la Regencia: no lo lleva ninguna colonia (GameConfig.colony_colors),
## asi que el bando enemigo nunca se confunde con el del jugador.
const REGENCY_COLOR := Color8(104, 58, 122)

func _bake_units(only: Array) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UNIT_OUT))
	var team_mat := _material(TEAM_PATH, _make_team_material())
	var failed := 0
	for id in UNIT_IDS:
		if not only.is_empty() and not only.has(id):
			continue
		for side in UNIT_SIDES:
			if not _bake_unit(id, side, team_mat):
				failed += 1
	for id in UNIT_PROPS:
		if not only.is_empty() and not only.has(id):
			continue
		if not _bake_unit(id, "", team_mat):
			failed += 1
	return failed

static func _make_team_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = Palette.make_solid()
	m.albedo_color = Color(1, 1, 1)
	return m

func _bake_unit(id: String, side: String, team_mat: Material) -> bool:
	var path := UNIT_RECIPES + id + ".gd"
	if not ResourceLoader.exists(path):
		push_error("build_toy_models: falta la receta " + path)
		return false
	var recipe: Object = (load(path) as GDScript).new()
	var mk := MeshKit.new()
	var team := MeshKit.new()
	var ctx := {"id": id, "side": side, "footprint": UNIT_FOOTPRINT}
	var res = recipe.call("build", mk, team, ctx)
	var out: Dictionary = res if res is Dictionary else {}
	var name := id if side == "" else "%s_%s" % [id, side]
	# La Regencia lleva su color horneado: el gris del equipo pasa a morado.
	if side != "player" and not team._sv.is_empty():
		var tc: PackedColorArray = team._sc
		for i in tc.size():
			var g: float = tc[i].r
			tc[i] = Color(REGENCY_COLOR.r * g, REGENCY_COLOR.g * g, REGENCY_COLOR.b * g)
		mk.append(team._sv, team._sn, tc, false)
		team = MeshKit.new()
	_finish_colors(mk)
	var mesh := mk.commit()
	if mesh == null:
		mesh = ArrayMesh.new()
	if not team._sv.is_empty():
		_finish_colors(team)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = team._sv
		arrays[Mesh.ARRAY_NORMAL] = team._sn
		arrays[Mesh.ARRAY_COLOR] = team._sc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_material(idx, team_mat)
		mesh.surface_set_name(idx, "team")
	if mesh.get_surface_count() == 0:
		push_error("build_toy_models: %s sale vacio" % name)
		return false
	mesh.resource_name = name
	var mesh_path := UNIT_OUT + name + "_mesh.res"
	var err := ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("build_toy_models: no guarda %s (%d)" % [mesh_path, err])
		return false
	var root := MeshInstance3D.new()
	root.name = "Toy_" + name
	root.mesh = mesh
	# Marcadores que lee la vista: de donde sale el disparo y hasta donde llega
	# la unidad (la barra de vida va encima).
	for key in ["muzzle", "top"]:
		if out.has(key):
			var m := Marker3D.new()
			m.name = key.capitalize()
			m.position = out[key]
			root.add_child(m)
			m.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	err = ResourceSaver.save(scene, UNIT_OUT + name + ".tscn")
	root.free()
	if err != OK:
		push_error("build_toy_models: no guarda la escena de %s (%d)" % [name, err])
		return false
	var a := mesh.get_aabb()
	var tris := Kit.tri_count(mesh)
	var warn := "" if tris <= UNIT_TRI_BUDGET else "  ** PASA DEL PRESUPUESTO (%d) **" % UNIT_TRI_BUDGET
	print("build_toy_models: %-18s %5d tri  %.2f x %.2f x %.2f%s" % [name, tris, a.size.x, a.size.y, a.size.z, warn])
	return true

# ── Inspeccion de piezas ──────────────────────────────────────────────

func _dump(list: String) -> void:
	var names: Array = []
	if list == "all":
		for pack in Kit.PACKS:
			var dir := ProjectSettings.globalize_path(Kit.PACKS[pack])
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".gltf") or f.ends_with(".glb"):
					names.append("%s:%s" % [pack, f.get_basename()])
	else:
		names = Array(list.split(",", false))
	for n in names:
		var a := _kit.aabb(n)
		var tris := int(_kit.piece(n)["v"].size() / 3)
		print("%-36s %5d tri  pos %s  size %s  %s" % [n, tris, _v(a.position), _v(a.size), _kit.histogram(n)])

static func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]
