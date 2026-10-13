extends SceneTree
## Horneado de los modelos "maqueta" de los edificios (docs/03, "Modelos:
## maqueta de juguete"; guia de estilo de edificios).
##
##     godot --headless --path . -s tools/build_toy_models.gd
##     godot --headless --path . -s tools/build_toy_models.gd -- --only=house,sawmill
##     godot --headless --path . -s tools/build_toy_models.gd -- --dump=kk:barrel,kn:chimney-large
##     godot --headless --path . -s tools/build_toy_models.gd -- --dump=all
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

## Los 17 que se hornean (la calzada no: su malla depende de los vecinos).
const IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "market", "laboratory",
	"foundry", "barracks", "refinery", "tower", "headquarters", "garden", "fountain", "statue", "farm"]

## Huella y patio de lo que no tiene .tres en esta rama (la granja llega en otra).
const EXTRA := {"farm": {"grid": Vector2i(2, 2), "yard": 0.1}}

## Oscurecimiento de contacto: lo que queda por debajo de esta altura se
## oscurece hasta AO_DARK en y = 0 (ancla el modelo a la parcela, regla 5).
const AO_HEIGHT := 0.22
const AO_DARK := 0.22

var _kit: Kit = null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var only: Array = []
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
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
	if EXTRA.has(id):
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
	_finish_colors(mk)
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
	var scene := PackedScene.new()
	scene.pack(root)
	err = ResourceSaver.save(scene, OUT + id + ".tscn")
	root.free()
	if err != OK:
		push_error("build_toy_models: no guarda la escena de %s (%d)" % [id, err])
		return false
	var a := mesh.get_aabb()
	print("build_toy_models: %-13s %5d tri  %.2f x %.2f x %.2f (objetivo %.2f x %.2f)%s" % [
		id, Kit.tri_count(mesh), a.size.x, a.size.y, a.size.z, ctx["w"], ctx["d"],
		"  FxAnchor" if out.has("fx") else ""])
	return true

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
