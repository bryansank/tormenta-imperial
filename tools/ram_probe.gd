extends SceneTree
## Sonda de memoria, HEADLESS (docs/26 §4.8). Arranca Main.tscn sin ventana, deja
## que GameManager monte la partida y hace inventario de lo que queda en memoria:
## memoria estatica del motor por etapas, y los recursos unicos colgados del arbol
## (texturas, mallas, materiales/shaders, audio, fuentes) ordenados por MB
## estimados. Sin GPU (headless usa el servidor de render "dummy"), asi que la
## memoria de video se ESTIMA por tamano: ancho x alto x bytes por pixel, y
## vertices x stride.
##
## SIEMPRE con un override.cfg de carpeta de usuario propia (monta una partida y
## GameManager la guarda):
##     [application]
##     config/use_custom_user_dir=true
##     config/custom_user_dir_name="TI_ram"
##
##     godot --headless --path . -s tools/ram_probe.gd -- --no-title --no-dev
##     godot --headless --path . -s tools/ram_probe.gd -- --no-title --no-dev --view=2d
##     ... -- --frames=240 --top=40
##
## Lo que dice: cuanto cuesta cada cosa en RAM del motor (estatica) y una
## estimacion de su copia en GPU. No mide el driver ni los render targets: eso
## solo en el dispositivo (`--ram-log` + `dumpsys meminfo`).

const MB := 1048576.0

var _frames := 180
var _top := 40
var _stage := 0
var _count := 0
var _marks: Array = []

func _initialize() -> void:
	var dir := OS.get_user_data_dir().replace("\\", "/")
	if dir.ends_with("app_userdata/Tormenta Imperial") or dir.ends_with("/TormentaImperial"):
		printerr("[ram_probe] sin override.cfg propio: se niega a correr en la carpeta del jugador (%s)" % dir)
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--top="):
			_top = int(a.get_slice("=", 1))
	_mark("autoloads")
	var main: PackedScene = load("res://scenes/main/Main.tscn")
	_mark("Main.tscn cargada")
	node_added.connect(_on_node_added)
	root.add_child.call_deferred(main.instantiate())

## Memoria estatica al quedar listo cada hijo directo de Main: la diferencia con
## el anterior es lo que cuesta ese panel/nodo (su subarbol y su _ready).
var _main: Node = null
var _last_static := 0.0
var _per_child: Array = []

func _on_node_added(n: Node) -> void:
	if _main == null and n.get_parent() == root and n.scene_file_path.ends_with("Main.tscn") or (_main == null and n.get_parent() == root and n.name.begins_with("Main")):
		_main = n
		_last_static = Performance.get_monitor(Performance.MEMORY_STATIC)
	elif _main != null and n.get_parent() == _main:
		n.ready.connect(_on_child_ready.bind(n), CONNECT_ONE_SHOT)

func _on_child_ready(n: Node) -> void:
	var now := Performance.get_monitor(Performance.MEMORY_STATIC)
	_per_child.append([(now - _last_static) / MB, String(n.name), n.get_class()])
	_last_static = now

func _process(_delta: float) -> bool:
	_count += 1
	if _stage == 0 and _count == 2:
		_mark("Main en el arbol")
		_stage = 1
	elif _stage == 1 and _count >= _frames:
		_mark("tras %d fotogramas" % _frames)
		_report()
		return true
	return false

func _mark(tag: String) -> void:
	_marks.append([tag, Performance.get_monitor(Performance.MEMORY_STATIC) / MB,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])

# ── Inventario ──

var _seen := {}
var _rows: Array = []   # [mb_estimado, clase, ruta/nombre, detalle]
var _shaders := {}
var _materials := 0
var _class_count := {}

func _report() -> void:
	var gm: Node = root.get_node_or_null("GameManager")
	var gs: Node = root.get_node_or_null("GridManager")
	print("\n=== ram_probe: partida empezada=%s rejilla=%sx%s ===" % [
		gm.call("is_started") if gm != null and gm.has_method("is_started") else "?",
		gs.get("grid_width") if gs != null else "?", gs.get("grid_height") if gs != null else "?"])
	print("\n=== ram_probe: etapas (memoria estatica del motor) ===")
	for m in _marks:
		print("  %-28s static=%7.1f MB  objetos=%d recursos=%d nodos=%d" % m)
	_per_child.sort_custom(func(a, b): return a[0] > b[0])
	print("
=== coste por hijo de Main (estatica al quedar listo) ===")
	for c in _per_child:
		if absf(c[0]) >= 0.2:
			var node: Node = _main.get_node_or_null(NodePath(c[1])) if _main != null else null
			var counts := _subtree_counts(node) if node != null else [0, 0]
			print("  %7.2f MB  %-22s nodos=%5d  textos=%4d  (%s)" % [c[0], c[1], counts[0], counts[1], c[2]])
	# Desglose de los tres mas caros: sus subarboles de 30+ nodos.
	for i in mini(3, _per_child.size()):
		var top: Node = _main.get_node_or_null(NodePath(_per_child[i][1])) if _main != null else null
		if top != null:
			_print_heavy(top, "    ", 0)
	_walk(root)
	if ThemeDB.fallback_font != null:
		_scan_resource(ThemeDB.fallback_font, 0)
	if ThemeDB.get_project_theme() != null:
		_scan_resource(ThemeDB.get_project_theme(), 0)
	_walk_static_caches()
	_rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0.0
	var by_class := {}
	for r in _rows:
		total += r[0]
		by_class[r[1]] = by_class.get(r[1], 0.0) + r[0]
	print("\n=== recursos unicos en el arbol: %d, %.1f MB estimados ===" % [_rows.size(), total])
	var classes := by_class.keys()
	classes.sort_custom(func(a, b): return by_class[a] > by_class[b])
	for c in classes:
		print("  %-22s %7.2f MB" % [c, by_class[c]])
	print("\n=== los %d mas gordos ===" % _top)
	for i in mini(_top, _rows.size()):
		var r: Array = _rows[i]
		print("  %7.2f MB  %-18s %s  %s" % [r[0], r[1], r[2], r[3]])
	print("\n=== materiales: %d unicos, shaders distintos: %d ===" % [_materials, _shaders.size()])
	var nodes := _class_count.keys()
	nodes.sort_custom(func(a, b): return _class_count[a] > _class_count[b])
	print("\n=== nodos por clase (top 25) ===")
	for i in mini(25, nodes.size()):
		print("  %6d  %s" % [_class_count[nodes[i]], nodes[i]])

func _print_heavy(n: Node, indent: String, depth: int) -> void:
	if depth > 4:
		return
	for c in n.get_children(true):
		var k := _subtree_counts(c)
		if k[0] >= 30:
			print("%s%5d nodos %4d textos  %s (%s)" % [indent, k[0], k[1], c.name, c.get_class()])
			_print_heavy(c, indent + "  ", depth + 1)

func _subtree_counts(n: Node) -> Array:
	var total := 1
	var texts := 1 if (n is Label or n is Button or n is RichTextLabel) else 0
	for c in n.get_children(true):
		var sub := _subtree_counts(c)
		total += sub[0]
		texts += sub[1]
	return [total, texts]

func _walk(n: Node) -> void:
	_class_count[n.get_class()] = _class_count.get(n.get_class(), 0) + 1
	_scan_object(n, 0)
	for c in n.get_children(true):
		_walk(c)

## Los atlas de glifos de cada fuente (TextServer): una textura por tamano y
## contorno, con copia en CPU (para seguir rellenandola) y en GPU.
var _font_rids := {}

func _walk_static_caches() -> void:
	var ts := TextServerManager.get_primary_interface()
	var total := 0.0
	var caches := 0
	var textures := 0
	for rid in _font_rids:
		var name: String = _font_rids[rid]
		var fb := 0.0
		var sizes: Array = ts.font_get_size_cache_list(rid)
		for sz in sizes:
			caches += 1
			for t in ts.font_get_texture_count(rid, sz):
				var img: Image = ts.font_get_texture_image(rid, sz, t)
				if img != null:
					textures += 1
					fb += img.get_data_size() / MB
		if fb > 0.0:
			_rows.append([fb, "GlyphAtlas", name, "%d tamanos %s" % [sizes.size(), str(sizes.slice(0, 8))]])
		total += fb
	print("
=== atlas de glifos: %d fuentes(rid), %d tamanos, %d texturas, %.2f MB (x2: CPU y GPU) ===" % [_font_rids.size(), caches, textures, total])

func _scan_object(o: Object, depth: int) -> void:
	if depth > 4 or o == null:
		return
	for p in o.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE) and not (p.usage & PROPERTY_USAGE_EDITOR):
			continue
		var v: Variant = o.get(p.name)
		if v is Resource:
			_scan_resource(v, depth + 1)
		elif v is Array:
			for e in v:
				if e is Resource:
					_scan_resource(e, depth + 1)

func _scan_resource(r: Resource, depth: int) -> void:
	var id := r.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	var name := r.resource_path if r.resource_path != "" else ("<%s %s>" % [r.get_class(), r.resource_name])
	if r is Texture2D:
		var t := r as Texture2D
		var bpp := 4.0
		var fmt := ""
		var img: Image = null
		if t is ImageTexture or t is CompressedTexture2D or t is NoiseTexture2D or t is GradientTexture2D:
			img = t.get_image()
		var mip := 1.0
		if img != null:
			fmt = "fmt%d%s" % [img.get_format(), "+mip" if img.has_mipmaps() else ""]
			bpp = float(img.get_data_size()) / maxf(1.0, float(t.get_width() * t.get_height()))
			mip = 1.0
		var mb := t.get_width() * t.get_height() * bpp * mip / MB
		_rows.append([mb, r.get_class(), name, "%dx%d %s" % [t.get_width(), t.get_height(), fmt]])
	elif r is Mesh:
		var m := r as Mesh
		var bytes := 0
		var verts := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arr[Mesh.ARRAY_VERTEX] != null else 0
			verts += vc
			var stride := 12
			if arr[Mesh.ARRAY_NORMAL] != null: stride += 4
			if arr[Mesh.ARRAY_TANGENT] != null: stride += 4
			if arr[Mesh.ARRAY_COLOR] != null: stride += 4
			if arr[Mesh.ARRAY_TEX_UV] != null: stride += 8
			if arr[Mesh.ARRAY_TEX_UV2] != null: stride += 8
			var ic: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else 0
			bytes += vc * stride + ic * (2 if vc < 65536 else 4)
			var mat := m.surface_get_material(s)
			if mat != null:
				_scan_resource(mat, depth + 1)
		_rows.append([bytes / MB, r.get_class(), name, "%d vertices, %d superficies" % [verts, m.get_surface_count()]])
	elif r is Material:
		_materials += 1
		if r is ShaderMaterial and (r as ShaderMaterial).shader != null:
			_shaders[(r as ShaderMaterial).shader.get_instance_id()] = (r as ShaderMaterial).shader.resource_path
		elif r is BaseMaterial3D:
			_shaders["std_" + str(_std_key(r as BaseMaterial3D))] = "StandardMaterial3D"
		_scan_object(r, depth)
	elif r is AudioStream:
		var bytes := 0
		if r is AudioStreamWAV:
			bytes = (r as AudioStreamWAV).data.size()
		elif r is AudioStreamOggVorbis:
			bytes = FileAccess.get_file_as_bytes(r.resource_path).size() if r.resource_path != "" else 0
		_rows.append([bytes / MB, r.get_class(), name, ""])
	if r is Font:
		for rid in (r as Font).get_rids():
			_font_rids[rid] = name
	if r is FontFile:
		_rows.append([(r as FontFile).data.size() / MB, "FontFile", name, "msdf=%s oversampling=%s" % [(r as FontFile).multichannel_signed_distance_field, (r as FontFile).oversampling]])
	elif r is MultiMesh:
		var mm := r as MultiMesh
		_rows.append([mm.instance_count * 64 / MB, "MultiMesh", name, "%d instancias" % mm.instance_count])
		if mm.mesh != null:
			_scan_resource(mm.mesh, depth + 1)
	else:
		_scan_object(r, depth)

func _std_key(m: BaseMaterial3D) -> String:
	return "%d%d%d%d%d" % [m.transparency, m.shading_mode, int(m.vertex_color_use_as_albedo), int(m.albedo_texture != null), int(m.normal_enabled)]
