extends RefCounted
## Obra, andamio de mejora y ruina en 3D (docs/03, "Aspecto en el mapa" y "Obra
## por edificio"), en el idioma de la maqueta: piezas gruesas de color por
## vertice (LotMesh) con los tonos de ToyTones, que son los de ToyPalette. Nada
## de materiales propios: lo quieto usa los dos materiales de la paleta, los
## mismos que los edificios horneados y las parcelas.
##
## Tres fases de obra, las mismas para todos: valla con materiales -> solar con
## cimientos -> estructura a medio levantar. La huella decide el tamano y
## cuantas piezas; el ESTILO del edificio (BuildingLook.site_style) que
## materiales, que valla, que lona y que silueta; y la SEMILLA de la instancia
## (BuildingLook.site_layout) donde va cada cosa.
##
## Para que vaya en un equipo muy modesto (grafica integrada vieja, tableta con
## el renderizador Mobile): todo lo quieto de una obra es UNA malla ("Site",
## una o dos superficies con los materiales compartidos de la paleta), en vez de
## las 30-45 mallas de antes. Lo que se mueve sigue moviendolo un shader
## (SiteFx), sin crear ni destruir nodos: la pluma, el contrapeso y el gancho de
## la grua (mallas con el origen en el eje, cacheadas), el banderin (un quad
## compartido) y las chispas o el polvo (hojas de BuildingFx). Materiales
## compartidos por color para todo el mapa; ninguna luz propia.
##
## Que lleva cada obra queda en metas de la raiz: "site_groups" (los grupos de
## su fase: "Fence"/"Piles", "Foundation", "Frame"/"Scaffold"/"Crane") y
## "site_piles" (las pilas: "Pile_<tipo>", en orden).

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const SiteFxKit := preload("res://scripts/buildings/SiteFx.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")
const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")

## La obra queda sobre la parcela (BuildingLot pone su suelo a 0.012).
const Y_SITE := 0.04
const SLAB_H := 0.22

static var _crane_meshes: Dictionary = {}
static var _flag_mesh: QuadMesh = null

static func _t(role: String) -> Color:
	return Tone.of(role)

static func foot_dims(footprint: Vector2i, cell_size: float) -> Vector2:
	return Vector2(footprint.x * cell_size * 0.9, footprint.y * cell_size * 0.9)

# ── Piezas sobre un LotMesh, con giro ────────────────────────────────

## Caja centrada en `pos`, girada `rot` (Euler, el mismo orden que Node3D).
static func _box(mb, pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	if rot == Vector3.ZERO:
		mb.box(pos, size, col)
		return
	var saved: Transform3D = mb.xf
	mb.xf = saved * Transform3D(Basis.from_euler(rot), pos)
	mb.box(Vector3.ZERO, size, col)
	mb.xf = saved

## Cilindro (o cono, `top_r`) CENTRADO en `pos`, de alto `h`, girado `rot`.
static func _cyl(mb, pos: Vector3, r: float, h: float, col: Color, sides := 6, rot := Vector3.ZERO, top_r := -1.0) -> void:
	var saved: Transform3D = mb.xf
	mb.xf = saved * Transform3D(Basis.from_euler(rot), pos)
	mb.cyl(Vector3(0, -h * 0.5, 0), r, h, col, sides, Vector3.UP, top_r)
	mb.xf = saved

## Aro (anillo de vigas) de radio medio `radius` en el plano XZ de `pos`.
static func _ring(mb, pos: Vector3, radius: float, thick: float, col: Color, segs := 10, rot := Vector3.ZERO) -> void:
	var saved: Transform3D = mb.xf
	mb.xf = saved * Transform3D(Basis.from_euler(rot), pos)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		mb.beam(Vector3(cos(a0), 0, sin(a0)) * radius, Vector3(cos(a1), 0, sin(a1)) * radius, thick, col)
	mb.xf = saved

## Una malla con nombre colgada de `parent`, con lo que lleve `mb`.
static func _mesh_node(parent: Node, node_name: String, mb, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.commit() if mb != null else null
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _new_mb():
	return MeshKit.new()

# ── Obra ─────────────────────────────────────────────────────────────

## Fase de obra `phase` (0, 1, 2) para una parcela de `footprint` celdas, con el
## estilo de `building_id` ("" = el de por defecto) y la disposicion de la
## semilla `seed_val` (BuildingLook.seed_of). Misma entrada, misma obra.
## Raiz "ConstructionPhase<N>": primero "Site" (todo lo quieto en una malla)
## y luego lo animado ("SiteFlag", "CraneJib"/"CraneWeight"/"CraneHook",
## "SiteFx_<tipo>"). Null si la fase no existe.
static func construction_phase(footprint: Vector2i, phase: int, cell_size: float, building_id: String = "", seed_val: int = 0) -> Node3D:
	if phase < 0 or phase > 2:
		return null
	var d := foot_dims(footprint, cell_size)
	var n := clampi(maxi(footprint.x, footprint.y), 1, 3)
	var style := LookRule.site_style(building_id)
	var layout := LookRule.site_layout(seed_val, style, n)
	var root := Node3D.new()
	root.name = "ConstructionPhase%d" % phase
	root.set_meta("site_seed", seed_val)
	root.set_meta("site_frame", String(style["frame"]))
	root.set_meta("site_piles", [])
	var mb = _new_mb()
	_ground(mb, d.x, d.y, style, phase > 0, int(layout["seed"]))
	match phase:
		0:
			root.set_meta("site_groups", ["Fence", "Piles"])
			_phase_fence(root, mb, d.x, d.y, n, style, layout)
		1:
			root.set_meta("site_groups", ["Foundation"])
			_phase_foundation(root, mb, d.x, d.y, n, style, layout)
		2:
			var groups := ["Frame", "Scaffold"]
			if n >= 2:
				groups.append("Crane")
			root.set_meta("site_groups", groups)
			_phase_frame(root, mb, d.x, d.y, n, style, layout)
	var site := _mesh_node(root, "Site", mb)
	root.move_child(site, 0)
	return root

## De fracciones de la huella (marco sin girar) a la parcela 3D.
static func _at(frac: Vector2, sx: float, sz: float, y: float = 0.0) -> Vector3:
	return Vector3(frac.x * sx, y, frac.y * sz)

## El suelo de la obra: tierra removida con terrones y, desde la fase 1, la losa
## (de piedra en los edificios de piedra) con su canto mas oscuro.
static func _ground(mb, sx: float, sz: float, style: Dictionary, slab: bool, seed_val: int) -> void:
	mb.box(Vector3(0, Y_SITE * 0.5, 0), Vector3(sx, Y_SITE, sz), _t("dirt"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ 0x5EED
	for k in 5:
		var p := Vector3(rng.randf_range(-0.42, 0.42) * sx, Y_SITE, rng.randf_range(-0.42, 0.42) * sz)
		mb.cyl(p, rng.randf_range(0.1, 0.18), 0.06, _t("soil"), 6, Vector3.UP, 0.04)
	if slab:
		var stone := String(style.get("frame_mat", "")) == "stone"
		var top := _t("stone_light" if stone else "concrete")
		mb.box(Vector3(0, SLAB_H * 0.5, 0), Vector3(sx * 0.86, SLAB_H, sz * 0.86), _t("stone_dark" if stone else "concrete_dark"))
		mb.box(Vector3(0, SLAB_H + 0.005, 0), Vector3(sx * 0.82, 0.01, sz * 0.82), top)

## Fase 0: tierra removida, valla con su puerta (en el lado que diga la
## semilla) y las pilas del estilo, una lona sobre alguna y algo de desorden.
static func _phase_fence(root: Node3D, mb, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	var kind := String(style["fence"])
	var post_col := _t({"dark_planks": "wood_dark", "sheet": "steel"}.get(kind, "wood"))
	var rail_col: Color
	match kind:
		"dark_planks": rail_col = _t("wood_dark").lightened(0.08)
		"sheet": rail_col = _t("sheet")
		"canvas": rail_col = Tone.snap(style["tarp"])
		_: rail_col = _t("wood_light")
	var post_h := 0.8
	var gate := int(layout["gate_side"])
	var step := float(layout["post_step"])
	for side in 4:
		var nrm := LookRule.side_normal(side)
		var along := Vector2(-nrm.y, nrm.x)
		var length := sx if nrm.x == 0.0 else sz
		var half := (sz if nrm.x == 0.0 else sx) * 0.5
		var mid := nrm * half
		var yaw := 0.0 if nrm.x == 0.0 else PI * 0.5
		var posts := maxi(2, int(length / step) + 1)
		for i in posts:
			var t := lerpf(-length * 0.5, length * 0.5, float(i) / float(posts - 1))
			if side == gate and absf(t) < length * 0.18:
				continue
			var p := mid + along * t
			mb.box(Vector3(p.x, post_h * 0.5, p.y), Vector3(0.13, post_h, 0.13), post_col)
			# Remate del poste: un taco claro, como en una maqueta.
			mb.box(Vector3(p.x, post_h + 0.03, p.y), Vector3(0.16, 0.06, 0.16), post_col.lightened(0.15))
		var segs := [[0.0, length]]
		if side == gate:
			var seg := length * 0.32
			segs = [[-(length * 0.5 - seg * 0.5), seg], [length * 0.5 - seg * 0.5, seg]]
		for s in segs:
			var c: Vector2 = mid + along * float(s[0])
			if kind == "sheet" or kind == "canvas":
				_box(mb, Vector3(c.x, 0.4, c.y), Vector3(float(s[1]), 0.6, 0.07), rail_col, Vector3(0, yaw, 0))
				# Franja de color en lo alto del panel.
				_box(mb, Vector3(c.x, 0.66, c.y), Vector3(float(s[1]), 0.08, 0.09), _t("brass") if kind == "sheet" else rail_col.darkened(0.2), Vector3(0, yaw, 0))
			else:
				for h in [0.3, 0.6]:
					_box(mb, Vector3(c.x, h, c.y), Vector3(float(s[1]), 0.12, 0.08), rail_col, Vector3(0, yaw, 0))
	# Cinta de peligro sobre la puerta (a franjas) y el banderin en uno de sus postes.
	var gn := LookRule.side_normal(gate)
	var glen := sx if gn.x == 0.0 else sz
	var ghalf := (sz if gn.x == 0.0 else sx) * 0.5
	var gyaw := 0.0 if gn.x == 0.0 else PI * 0.5
	var gal := Vector2(-gn.y, gn.x)
	var stripes := 6
	for i in stripes:
		var t := lerpf(-glen * 0.18, glen * 0.18, (float(i) + 0.5) / float(stripes))
		var p := gn * ghalf + gal * t
		_box(mb, Vector3(p.x, post_h - 0.02, p.y), Vector3(glen * 0.36 / stripes + 0.005, 0.09, 0.09), _t("hazard") if i % 2 == 0 else _t("iron"), Vector3(0, gyaw, 0))
	var flag_at := gn * ghalf + gal * glen * 0.2 * float(layout["flag_post"])
	_add_flag(root, mb, Vector3(flag_at.x, 0, flag_at.y), 1.2, style["flag"])
	# Las pilas del estilo, donde diga la semilla (y la lona sobre una).
	var names: Array = root.get_meta("site_piles")
	var list: Array = layout["piles"]
	for k in list.size():
		var p: Dictionary = list[k]
		names.append("Pile_" + String(p["kind"]))
		mb.xf = Transform3D(Basis(Vector3.UP, float(p["yaw"])).scaled(Vector3.ONE * float(p["scale"])), _at(p["pos"], sx, sz, Y_SITE))
		_pile(mb, String(p["kind"]), n)
		if k == int(layout["tarp_pile"]):
			_box(mb, Vector3(0.12, 0.38, 0.0), Vector3(0.8, 0.06, 0.64), Tone.snap(style["tarp"]), Vector3(0, 0, 0.25))
		mb.xf = Transform3D.IDENTITY
	_clutter(mb, sx, sz, layout)
	_add_site_fx(root, SiteFxKit.fx_for(style, 0), _at(layout["fx_spot"], sx, sz, 0.35), 1.1 + 0.2 * n)

## Una pila de material centrada en el origen de `mb.xf` (ya girada y escalada).
static func _pile(mb, kind: String, n: int) -> void:
	match kind:
		"planks":
			for layer in 3:
				for j in 3:
					var col := _t("wood_light") if (layer + j) % 2 == 0 else _t("wood")
					var off := (j - 1) * 0.2
					if layer % 2 == 1:
						_box(mb, Vector3(off, 0.06 + layer * 0.12, 0.0), Vector3(0.9 + 0.15 * n, 0.11, 0.17), col, Vector3(0, PI * 0.5, 0))
					else:
						mb.box(Vector3(0.0, 0.06 + layer * 0.12, off), Vector3(0.9 + 0.15 * n, 0.11, 0.17), col)
		"beams":
			for j in 3:
				var y := 0.08 + (0.15 if j == 2 else 0.0)
				var z := (-0.11 + 0.22 * (j % 2)) if j < 2 else 0.0
				mb.box(Vector3(0, y, z), Vector3(1.0 + 0.2 * n, 0.15, 0.15), _t("steel") if j != 2 else _t("red"))
			mb.box(Vector3(0, 0.04, 0), Vector3(0.14, 0.08, 0.5), _t("wood_dark"))
		"bricks":
			mb.box(Vector3(0, 0.05, 0), Vector3(0.7, 0.1, 0.54), _t("wood"))
			mb.box(Vector3(0, 0.32, 0), Vector3(0.62, 0.44, 0.46), _t("brick"))
			for y in [0.2, 0.36]:
				mb.box(Vector3(0, y, 0), Vector3(0.64, 0.03, 0.48), _t("stone_light"))
		"logs":
			var rows := [[-0.22, 0.0, 0.22], [-0.11, 0.11], [0.0]]
			var length := 1.0 + 0.15 * n
			for r in rows.size():
				for z in rows[r]:
					var base := Vector3(-length * 0.5, 0.12 + r * 0.19, float(z))
					mb.cyl(base, 0.11, length, _t("log"), 7, Vector3.RIGHT)
					mb.cyl(base - Vector3(0.01, 0, 0), 0.08, 0.02, _t("log_end"), 7, Vector3.LEFT)
		"sawdust":
			mb.cyl(Vector3.ZERO, 0.44, 0.3, _t("sawdust"), 8, Vector3.UP, 0.08)
		"gravel":
			mb.cyl(Vector3.ZERO, 0.46, 0.36, _t("gravel"), 8, Vector3.UP, 0.07)
			for g in [Vector3(-0.3, 0.06, 0.25), Vector3(0.32, 0.05, -0.18)]:
				mb.ball(g, 0.08, _t("stone_dark"))
		"soil":
			mb.cyl(Vector3.ZERO, 0.44, 0.28, _t("soil"), 8, Vector3.UP, 0.1)
		"rivets":
			mb.box(Vector3(0.2, 0.14, 0), Vector3(0.32, 0.28, 0.32), _t("crate"))
			mb.box(Vector3(0.2, 0.14, 0), Vector3(0.34, 0.06, 0.34), _t("wood_dark"))
			for j in 3:
				mb.cyl(Vector3(-0.2 + 0.05 * j, 0, -0.18 + 0.18 * j), 0.1, 0.24, _t("rust"), 6)
		"pipes":
			var rows := [[-0.17, 0.0, 0.17], [-0.085, 0.085]]
			var length := 1.1 + 0.15 * n
			for r in rows.size():
				for z in rows[r]:
					var base := Vector3(-length * 0.5, 0.08 + r * 0.14, float(z))
					mb.cyl(base, 0.08, length, _t("copper"), 6, Vector3.RIGHT)
			mb.box(Vector3(0, 0.05, 0), Vector3(0.12, 0.1, 0.5), _t("wood_dark"))
		"drums":
			var cols := [_t("drum"), _t("sky"), _t("drum")]
			var spots := [Vector2(-0.15, -0.14), Vector2(0.14, -0.12), Vector2(0.0, 0.14)]
			for i in 3:
				var o: Vector2 = spots[i]
				mb.cyl(Vector3(o.x, 0, o.y), 0.14, 0.38, cols[i], 8)
				mb.cyl(Vector3(o.x, 0.12, o.y), 0.15, 0.04, _t("iron"), 8)
			_cyl(mb, Vector3(0.34, 0.14, 0.2), 0.14, 0.38, _t("sky"), 8, Vector3(PI * 0.5, 0, 0))
		"sacks", "sandbags":
			var sack := _t("sack" if kind == "sacks" else "sandbag")
			var per := 3 if kind == "sacks" else 4
			for layer in 2:
				for j in per - layer:
					var col := sack if (j + layer) % 2 == 0 else sack.darkened(0.08)
					mb.ball(Vector3((j - (per - layer - 1) * 0.5) * 0.25, 0.09 + layer * 0.14, 0.0), 0.15, col, Vector3(1.0, 0.6, 0.78))
		"stone":
			var blocks := [[Vector3(-0.2, 0.13, -0.1), Vector3(0.38, 0.26, 0.3)], [Vector3(0.2, 0.11, 0.08), Vector3(0.34, 0.22, 0.34)],
				[Vector3(-0.05, 0.36, 0.0), Vector3(0.3, 0.22, 0.26)]]
			for b in blocks.size():
				_box(mb, blocks[b][0], blocks[b][1], _t("stone_light") if b % 2 == 0 else _t("stone"), Vector3(0, 0.2 * b, 0))
		"crates":
			mb.box(Vector3(-0.17, 0.16, 0), Vector3(0.32, 0.32, 0.32), _t("crate"))
			mb.box(Vector3(0.17, 0.16, 0.03), Vector3(0.32, 0.32, 0.32), _t("wood"))
			for x in [-0.17, 0.17]:
				mb.box(Vector3(x, 0.16, 0.0), Vector3(0.34, 0.06, 0.34), _t("wood_dark"))
			_box(mb, Vector3(0.0, 0.45, 0.0), Vector3(0.28, 0.26, 0.28), _t("crate"), Vector3(0, 0.4, 0))
		_:
			mb.box(Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.4), _t("concrete_dark"))

## El pequeno desorden de la semilla: un bidon, una caja, un cono sueltos.
static func _clutter(mb, sx: float, sz: float, layout: Dictionary) -> void:
	for c in layout["clutter"]:
		var p := _at(c["pos"], sx, sz, Y_SITE)
		match String(c["kind"]):
			"barrel":
				mb.cyl(p, 0.11, 0.26, _t("drum"), 7)
				mb.cyl(p + Vector3(0, 0.18, 0), 0.115, 0.04, _t("iron"), 7)
			"crate":
				mb.box(p + Vector3(0, 0.12, 0), Vector3(0.24, 0.24, 0.24), _t("crate"))
			_:
				_cone(mb, p)

## Cono de obra: naranja de teja con banda clara, y su base cuadrada.
static func _cone(mb, p: Vector3) -> void:
	mb.box(p + Vector3(0, 0.02, 0), Vector3(0.22, 0.04, 0.22), _t("iron"))
	mb.cyl(p + Vector3(0, 0.04, 0), 0.1, 0.32, _t("terracotta"), 6, Vector3.UP, 0.025)
	mb.cyl(p + Vector3(0, 0.16, 0), 0.072, 0.06, _t("cream"), 6, Vector3.UP, 0.06)

## Fase 1: solar despejado con la losa (de piedra en los edificios de piedra),
## zapatas, esperas de ferralla (o estacas de madera), conos en dos esquinas de
## la semilla y lo que sobro de la primera pila en otra.
static func _phase_foundation(root: Node3D, mb, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	var dark := _t("stone_dark" if style["frame_mat"] == "stone" else "concrete_dark")
	var wood := String(style["frame_mat"]) == "wood"
	for p in _frame_points(sx * 0.8, sz * 0.8, n, String(style["frame"])):
		mb.box(Vector3(p.x, SLAB_H + 0.03, p.y), Vector3(0.4, 0.07, 0.4), dark)
		if wood:
			mb.box(Vector3(p.x, SLAB_H + 0.28, p.y), Vector3(0.14, 0.5, 0.14), _t("wood"))
			mb.box(Vector3(p.x, SLAB_H + 0.55, p.y), Vector3(0.16, 0.05, 0.16), _t("terracotta"))
		else:
			for o in [Vector2(-0.09, -0.09), Vector2(0.09, 0.09)]:
				mb.box(Vector3(p.x + o.x, SLAB_H + 0.32, p.y + o.y), Vector3(0.05, 0.6, 0.05), _t("rust"))
	_foundation_hint(mb, sx, sz, SLAB_H, style, layout)
	for s in layout["cone_corners"]:
		_cone(mb, Vector3(s.x * sx * 0.47, Y_SITE, s.y * sz * 0.47))
	var left: Vector2 = layout["leftover_corner"]
	var piles: Array = layout["piles"]
	if not piles.is_empty():
		# Lo que sobro de la primera pila, mas pequeno, en otra esquina.
		(root.get_meta("site_piles") as Array).append("Pile_" + String(piles[0]["kind"]))
		mb.xf = Transform3D(Basis(Vector3.UP, float(piles[0]["yaw"])).scaled(Vector3.ONE * 0.7), Vector3(left.x * sx * 0.36, SLAB_H, left.y * sz * 0.36))
		_pile(mb, String(piles[0]["kind"]), n)
		mb.xf = Transform3D.IDENTITY
	var cc: Vector2 = layout["cone_corners"][1]
	_add_flag(root, mb, Vector3(cc.x * sx * 0.4, SLAB_H, cc.y * sz * 0.4), 1.0, style["flag"])
	_add_site_fx(root, SiteFxKit.fx_for(style, 1), _at(layout["fx_spot"], sx, sz, SLAB_H + 0.4), 1.0 + 0.2 * n)

## Lo que ya asoma en los cimientos de cada silueta: la base redonda de la
## chimenea, los anillos de los depositos o la cupula, la zapata de la torre,
## el primer escalon del pedestal, los bancales, las durmientes de madera...
static func _foundation_hint(mb, sx: float, sz: float, y: float, style: Dictionary, layout: Dictionary) -> void:
	var cc: Vector2 = layout["crane_corner"]
	var dark := _t("concrete_dark")
	match String(style["frame"]):
		"chimney":
			mb.cyl(Vector3(-cc.x * sx * 0.26, y, -cc.y * sz * 0.26), 0.38, 0.18, _t("brick"), 8)
		"tanks":
			for side in [-1.0, 1.0]:
				mb.cyl(Vector3(side * sx * 0.22, y, 0), minf(sx, sz) * 0.2, 0.1, dark, 10)
		"dome", "basin":
			var r := minf(sx, sz) * 0.38
			_ring(mb, Vector3(0, y + 0.06, 0), r, 0.16, _t("stone" if style["frame_mat"] == "stone" else "concrete_dark"), 14)
		"tower":
			mb.box(Vector3(0, y + 0.08, 0), Vector3(sx * 0.6, 0.16, sz * 0.6), dark)
		"plinth":
			mb.box(Vector3(0, y + 0.12, 0), Vector3(sx * 0.8, 0.24, sz * 0.8), _t("stone_light"))
		"low":
			for zs in [-1.0, 1.0]:
				mb.box(Vector3(0, y + 0.06, zs * sz * 0.18), Vector3(sx * 0.6, 0.12, sz * 0.18), _t("soil"))
				mb.box(Vector3(0, y + 0.13, zs * sz * 0.18), Vector3(sx * 0.5, 0.03, sz * 0.08), _t("leaf"))
		"headframe":
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					mb.box(Vector3(xs * sx * 0.35, y + 0.08, zs * sz * 0.18), Vector3(0.42, 0.16, 0.42), dark)
		"gable", "hall":
			var sill := _t("wood_dark" if style["frame_mat"] == "wood" else "steel")
			mb.box(Vector3(0, y + 0.07, -sz * 0.4), Vector3(sx * 0.82, 0.14, 0.16), sill)
			mb.box(Vector3(0, y + 0.07, sz * 0.4), Vector3(sx * 0.82, 0.14, 0.16), sill)
			mb.box(Vector3(-sx * 0.4, y + 0.07, 0), Vector3(0.16, 0.14, sz * 0.82), sill)
			mb.box(Vector3(sx * 0.4, y + 0.07, 0), Vector3(0.16, 0.14, sz * 0.82), sill)
		"mast":
			mb.cyl(Vector3(0, y, 0), 0.26, 0.2, dark, 8)

## Fase 2: losa, la estructura con la silueta del edificio ("Frame"), andamio
## en el lado de la semilla y, desde 2x2, grua en la esquina de la semilla,
## girando. Banderin en lo alto y chispas o polvo.
static func _phase_frame(root: Node3D, mb, sx: float, sz: float, n: int, style: Dictionary, layout: Dictionary) -> void:
	var h := 1.3 + 0.45 * n
	var top := _frame_shape(mb, sx, sz, n, h, style, layout)
	_scaffold_side(mb, sx, sz, h, int(layout["scaffold_side"]))
	var cc: Vector2 = layout["crane_corner"]
	if n >= 2:
		var yaw := atan2(-cc.y, cc.x) + (float(layout["crane_yaw"]) / TAU - 0.5) * 1.2
		_add_crane(root, mb, Vector3(cc.x * sx * 0.42, 0, cc.y * sz * 0.42), maxf(h, top) + 1.2, sx * 0.7, yaw, style["crane"])
	if String(style["frame"]) != "mast":
		var fc := -cc
		_add_flag(root, mb, Vector3(fc.x * sx * 0.4, SLAB_H, fc.y * sz * 0.4), h + 0.7, style["flag"])
	else:
		_add_flag(root, mb, Vector3(0, SLAB_H + h * 2.2 - 0.7, 0), 0.7, style["flag"])
	var fx := SiteFxKit.fx_for(style, 2)
	_add_site_fx(root, fx, _at(layout["fx_spot"], sx, sz, (SLAB_H + h * 0.6) if fx == "sparks" else 0.5), 1.0 + 0.25 * n)

## Puntos de pilar: esquinas para la clase 1, rejilla 3x3 para la 2 y 4x4 para la 3.
static func _grid_points(w: float, d: float, n: int) -> Array:
	var per := n + 1
	var pts: Array = []
	for i in per:
		for j in per:
			pts.append(Vector2(lerpf(-w * 0.5, w * 0.5, float(i) / float(per - 1)), lerpf(-d * 0.5, d * 0.5, float(j) / float(per - 1))))
	return pts

## Los apoyos de cada silueta: en rejilla, o en anillo para las redondas
## (cupula, depositos, pilon).
static func _frame_points(w: float, d: float, n: int, shape: String) -> Array:
	if shape in ["dome", "basin", "tanks"]:
		var pts: Array = []
		var count := 4 + 2 * n
		for k in count:
			var a := TAU * k / count
			pts.append(Vector2(cos(a) * w * 0.48, sin(a) * d * 0.48))
		return pts
	return _grid_points(w, d, n)

## La silueta de la fase 2, que insinua el edificio terminado. Devuelve la
## altura de su punto mas alto (para que la grua quede por encima).
static func _frame_shape(mb, sx: float, sz: float, n: int, h: float, style: Dictionary, layout: Dictionary) -> float:
	var shape := String(style["frame"])
	var col := _t({"wood": "wood", "stone": "stone_light"}.get(String(style["frame_mat"]), "steel"))
	var steel := _t("steel")
	var base := SLAB_H
	var top := base + h
	var cc: Vector2 = layout["crane_corner"]
	match shape:
		"chimney":
			_pillars(mb, sx, sz, n, h * 0.8, col, true)
			var c := Vector3(-cc.x * sx * 0.26, 0, -cc.y * sz * 0.26)
			var ch := h * 1.9
			mb.cyl(c + Vector3(0, base, 0), 0.34, ch, _t("brick"), 8, Vector3.UP, 0.28)
			for y in [0.45, 0.8]:
				_ring(mb, c + Vector3(0, base + ch * y, 0), lerpf(0.34, 0.28, y) + 0.04, 0.09, _t("iron"), 8)
			# La boca aun sin tapa, y la banda roja que llevara la chimenea.
			mb.cyl(c + Vector3(0, base + ch * 0.62, 0), 0.33, 0.14, _t("red"), 8)
			top = base + ch
		"gable", "hall":
			var hall := shape == "hall"
			_pillars(mb, sx, sz, n, h, col, false)
			var roof := sz * (0.2 if hall else 0.36)
			var count := n + 2
			for i in count:
				var x := lerpf(-sx * 0.4, sx * 0.4, float(i) / float(count - 1))
				var apex := Vector3(x, base + h + roof, 0)
				mb.beam(Vector3(x, base + h, sz * 0.42), apex, 0.11, col)
				mb.beam(Vector3(x, base + h, -sz * 0.42), apex, 0.11, col)
				if hall:
					mb.box(Vector3(x, base + h, 0), Vector3(0.1, 0.1, sz * 0.84), col)
			mb.box(Vector3(0, base + h + roof, 0), Vector3(sx * 0.84, 0.12, 0.12), col)
			# Media cubierta de tejas ya puesta: lo que dira "casa" de lejos.
			var tile := _t("terracotta") if not hall else _t("sheet")
			var slope := atan2(roof, sz * 0.42)
			var run := sqrt(roof * roof + sz * sz * 0.42 * 0.42)
			_box(mb, Vector3(-sx * 0.2, base + h + roof * 0.5 + 0.06, sz * 0.21), Vector3(sx * 0.44, 0.06, run), tile, Vector3(slope, 0, 0))
			top = base + h + roof
		"tower":
			var th := h * 1.75
			var w := 0.3
			var feet := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for k in 4:
				var a: Vector2 = feet[k]
				var b: Vector2 = feet[(k + 1) % 4]
				mb.beam(Vector3(a.x * sx * w, base, a.y * sz * w), Vector3(a.x * sx * w * 0.6, base + th, a.y * sz * w * 0.6), 0.16, col)
				# Riostra en aspa por cara: la celosia de una torre.
				mb.beam(Vector3(a.x * sx * w, base, a.y * sz * w), Vector3(b.x * sx * w * 0.8, base + th * 0.5, b.y * sz * w * 0.8), 0.08, col)
			for lv in [0.5, 1.0]:
				var s := lerpf(1.0, 0.6, lv)
				mb.box(Vector3(0, base + th * lv, 0), Vector3(sx * w * 2.0 * s + 0.18, 0.1, sz * w * 2.0 * s + 0.18), _t("wood") if lv == 1.0 else col)
			top = base + th
		"tanks":
			var r := minf(sx, sz) * 0.2
			for side in [-1.0, 1.0]:
				var c := Vector3(side * sx * 0.22, 0, 0)
				for y in [0.3, 0.65, 0.95]:
					_ring(mb, c + Vector3(0, base + h * y, 0), r, 0.07, col, 10)
				for k in 6:
					var a := TAU * k / 6.0
					mb.box(c + Vector3(cos(a) * r, base + h * 0.5, sin(a) * r), Vector3(0.08, h, 0.08), col)
			# Uno ya medio chapado (en el color de la refineria) y una tuberia que los une.
			mb.cyl(Vector3(sx * 0.22, base, 0), r, h * 0.4, _t("cream"), 10)
			mb.cyl(Vector3(sx * 0.22, base + h * 0.3, 0), r + 0.01, 0.08, _t("red"), 10)
			_cyl(mb, Vector3(0, base + h * 0.35, sz * 0.12), 0.08, sx * 0.44, _t("copper"), 6, Vector3(0, 0, PI * 0.5))
		"dome":
			var R := minf(sx, sz) * 0.4
			var ring_h := h * 0.55
			for p in _frame_points(sx * 0.8, sz * 0.8, n, shape):
				mb.box(Vector3(p.x, base + ring_h * 0.5, p.y), Vector3(0.16, ring_h, 0.16), col)
			_ring(mb, Vector3(0, base + ring_h, 0), R, 0.14, col, 14)
			# Nervios de la cupula: cuartos de arco, tres tramos cada uno.
			for k in 6:
				var saved: Transform3D = mb.xf
				mb.xf = saved * Transform3D(Basis(Vector3.UP, TAU * k / 6.0), Vector3.ZERO)
				var prev := Vector3(R, base + ring_h, 0)
				for s in range(1, 4):
					var phi := PI * 0.5 * s / 3.0
					var next := Vector3(R * cos(phi), base + ring_h + R * 0.9 * sin(phi), 0)
					mb.beam(prev, next, 0.1, steel if k % 2 == 0 else col)
					prev = next
				mb.xf = saved
			mb.ball(Vector3(0, base + ring_h + R * 0.9, 0), 0.14, _t("brass"))
			top = base + ring_h + R * 0.9
		"plinth":
			for i in 3:
				var s := 0.8 - 0.18 * i
				mb.box(Vector3(0, base + 0.12 + 0.24 * i, 0), Vector3(sx * s, 0.24, sz * s), _t("stone_light") if i % 2 == 0 else _t("stone"))
			# La figura, aun tapada con la lona, y los pies de un andamio de madera.
			var fig_h := h * 0.9
			var tarp := Tone.snap(style["tarp"])
			mb.box(Vector3(0, base + 0.72 + fig_h * 0.5, 0), Vector3(0.5, fig_h, 0.44), tarp)
			mb.ball(Vector3(0, base + 0.72 + fig_h + 0.12, 0), 0.24, tarp)
			mb.box(Vector3(0, base + 0.72 + fig_h * 0.55, 0), Vector3(0.54, 0.06, 0.48), _t("red"))
			for s in LookRule.CORNERS:
				mb.box(Vector3(s.x * sx * 0.3, base + h * 0.6, s.y * sz * 0.3), Vector3(0.08, h * 1.2, 0.08), _t("wood_dark"))
			top = base + 0.72 + fig_h + 0.3
		"basin":
			var count := 10 + 2 * n
			for k in count:
				if k % 5 == 4:
					continue   # huecos: el pilon aun no esta cerrado
				var a := TAU * k / count
				_box(mb, Vector3(cos(a) * sx * 0.38, base + 0.18, sin(a) * sz * 0.38), Vector3(0.38, 0.36, 0.24),
					_t("stone_light") if k % 2 == 0 else _t("stone"), Vector3(0, -a + PI * 0.5, 0))
			mb.cyl(Vector3(0, base, 0), 0.09, 1.0, _t("copper"), 6)
			# Cabria de tres patas sobre el centro, para subir la pila.
			var apex := Vector3(0, base + h * 1.1, 0)
			for k in 3:
				var a := TAU * k / 3.0 + 0.3
				mb.beam(Vector3(cos(a) * sx * 0.32, base, sin(a) * sz * 0.32), apex, 0.1, _t("wood_dark"))
			mb.box(apex, Vector3(0.2, 0.2, 0.2), _t("iron"))
			top = apex.y
		"headframe":
			_pillars(mb, sx, sz, 1, h * 0.45, col, true)
			var apex_h := h * 1.7
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					mb.beam(Vector3(xs * sx * 0.35, base, zs * sz * 0.18), Vector3(0, base + apex_h, zs * sz * 0.1), 0.13, col)
			# La rueda del castillete, exagerada y en rojo: se lee de lejos.
			_ring(mb, Vector3(0, base + apex_h + 0.3, 0), 0.34, 0.1, _t("red"), 10, Vector3(PI * 0.5, 0, 0))
			_cyl(mb, Vector3(0, base + apex_h + 0.3, 0), 0.08, sz * 0.28, _t("iron"), 6, Vector3(PI * 0.5, 0, 0))
			top = base + apex_h + 0.65
		"low":
			# Pergola de madera y bancales: lo que sera el jardin.
			for s in LookRule.CORNERS:
				mb.box(Vector3(s.x * sx * 0.32, base + h * 0.4, s.y * sz * 0.32), Vector3(0.13, h * 0.8, 0.13), col)
			for i in 4:
				var x := lerpf(-sx * 0.32, sx * 0.32, float(i) / 3.0)
				mb.box(Vector3(x, base + h * 0.8, 0), Vector3(0.09, 0.09, sz * 0.7), col)
			for zs in [-1.0, 1.0]:
				mb.box(Vector3(0, base + h * 0.8, zs * sz * 0.32), Vector3(sx * 0.7, 0.11, 0.11), col)
				mb.box(Vector3(0, base + 0.08, zs * sz * 0.18), Vector3(sx * 0.6, 0.14, sz * 0.18), _t("soil"))
				for k in 4:
					mb.ball(Vector3(lerpf(-sx * 0.24, sx * 0.24, k / 3.0), base + 0.2, zs * sz * 0.18), 0.1, _t("leaf"))
			top = base + h * 0.8
		"mast":
			_pillars(mb, sx, sz, n, h, col, true)
			var mh := h * 2.2
			mb.cyl(Vector3(0, base, 0), 0.09, mh, steel, 6)
			mb.ball(Vector3(0, base + mh, 0), 0.12, _t("brass"))
			top = base + mh
		_:
			_pillars(mb, sx, sz, n, h, col, true)
	return top

## Pilares en rejilla, medio forjado detras y (si `ring`) vigas de coronacion.
static func _pillars(mb, sx: float, sz: float, n: int, h: float, col: Color, ring: bool) -> void:
	var base := SLAB_H
	for p in _grid_points(sx * 0.8, sz * 0.8, n):
		mb.box(Vector3(p.x, base + h * 0.5, p.y), Vector3(0.2, h, 0.2), col)
	mb.box(Vector3(0, base + h * 0.5, -sz * 0.2), Vector3(sx * 0.82, 0.14, sz * 0.42), _t("concrete"))
	if not ring:
		return
	var top := base + h
	mb.box(Vector3(0, top, -sz * 0.4), Vector3(sx * 0.82, 0.14, 0.14), col)
	mb.box(Vector3(0, top, sz * 0.4), Vector3(sx * 0.82, 0.14, 0.14), col)
	mb.box(Vector3(-sx * 0.4, top, 0), Vector3(0.14, 0.14, sz * 0.82), col)
	mb.box(Vector3(sx * 0.4, top, 0), Vector3(0.14, 0.14, sz * 0.82), col)

## Andamio en el lado `side` (0 delante +Z, 1 +X, 2 detras, 3 -X): pies
## derechos, plataformas de tabla y una riostra en aspa por tramo.
static func _scaffold_side(mb, sx: float, sz: float, h: float, side: int = 0) -> void:
	var nrm := LookRule.side_normal(side)
	var length := sx if nrm.x == 0.0 else sz
	var off := (sz if nrm.x == 0.0 else sx) * 0.5
	var along := Vector2(-nrm.y, nrm.x)
	var yaw := 0.0 if nrm.x == 0.0 else PI * 0.5
	var feet: Array = []
	for i in 3:
		var p := nrm * off + along * lerpf(-length * 0.42, length * 0.42, float(i) / 2.0)
		feet.append(p)
		mb.box(Vector3(p.x, (h + 0.2) * 0.5, p.y), Vector3(0.08, h + 0.2, 0.08), _t("wood_dark"))
	for i in 2:
		var a: Vector2 = feet[i]
		var b: Vector2 = feet[i + 1]
		mb.beam(Vector3(a.x, 0.2, a.y), Vector3(b.x, h * 0.9, b.y), 0.05, _t("wood_dark").lightened(0.1))
	var level := 0.7
	var k := 0
	while level < h:
		_box(mb, Vector3(nrm.x * off, level, nrm.y * off), Vector3(length * 0.86, 0.07, 0.32), _t("wood_light") if k % 2 == 0 else _t("wood"), Vector3(0, yaw, 0))
		level += 0.75
		k += 1

## Grua: mastil fijo (en la malla de la obra) y, en lo alto, pluma + contrapeso + cable con
## gancho (tres mallas con el origen en el eje) que gira el shader de SiteFx,
## cada grua a su ritmo; el gancho sube y baja. `yaw`: hacia donde apunta en reposo.
static func _add_crane(root: Node3D, mb, base: Vector3, height: float, jib: float, yaw: float = 0.0, color: Color = Color(0.95, 0.72, 0.1)) -> void:
	var col := Tone.snap(color)
	# Mastil de celosia: cuatro montantes y riostras, en el color de la grua.
	var w := 0.13
	for s in LookRule.CORNERS:
		mb.box(base + Vector3(s.x * w, height * 0.5, s.y * w), Vector3(0.07, height, 0.07), col)
	var y := 0.4
	while y < height - 0.4:
		mb.beam(base + Vector3(-w, y, w), base + Vector3(w, y + 0.45, w), 0.04, col.darkened(0.15))
		mb.beam(base + Vector3(w, y, -w), base + Vector3(-w, y + 0.45, -w), 0.04, col.darkened(0.15))
		y += 0.45
	mb.box(base + Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.5), _t("concrete_dark"))
	# Cabina en lo alto.
	mb.box(base + Vector3(0, height - 0.22, 0), Vector3(0.36, 0.32, 0.36), _t("cream"))
	mb.box(base + Vector3(0, height - 0.2, 0.17), Vector3(0.24, 0.14, 0.04), _t("sky"))
	var pivot := base + Vector3(0, height, 0)
	var parts := crane_meshes(jib, col)
	_shader_mesh(root, "CraneJib", parts[0], SiteFxKit.crane_material_3d(Color.WHITE), pivot, yaw)
	_shader_mesh(root, "CraneWeight", parts[1], SiteFxKit.crane_material_3d(Color.WHITE), pivot, yaw)
	_shader_mesh(root, "CraneHook", parts[2], SiteFxKit.crane_material_3d(Color.WHITE, 0.55), pivot, yaw)

## [pluma, contrapeso, gancho] con el origen en el eje, color por vertice.
## Cacheadas por largo de pluma y color.
static func crane_meshes(jib: float, col: Color) -> Array:
	var key := "%.2f:%s" % [jib, col.to_html()]
	if _crane_meshes.has(key):
		return _crane_meshes[key]
	var arm = _new_mb()
	arm.box(Vector3(-jib * 0.4, 0, 0), Vector3(jib, 0.16, 0.16), col)
	arm.box(Vector3(-jib * 0.4, 0.1, 0), Vector3(jib, 0.04, 0.2), col.darkened(0.15))
	arm.box(Vector3(-jib * 0.75, -0.08, 0), Vector3(0.2, 0.1, 0.18), _t("iron"))
	var weight = _new_mb()
	weight.box(Vector3(jib * 0.18, -0.14, 0), Vector3(0.36, 0.28, 0.3), _t("concrete_dark"))
	weight.box(Vector3(jib * 0.18, -0.14, 0), Vector3(0.38, 0.06, 0.32), _t("hazard"))
	var hook = _new_mb()
	hook.box(Vector3(-jib * 0.75, -0.5, 0), Vector3(0.035, 1.0, 0.035), _t("iron"))
	hook.box(Vector3(-jib * 0.75, -1.04, 0), Vector3(0.18, 0.14, 0.18), _t("red"))
	var out := [arm.commit(), weight.commit(), hook.commit()]
	_crane_meshes[key] = out
	return out

static func _shader_mesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, pos: Vector3, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

## Banderin en su palo: el palo va en la malla de la obra y la tela
## ("SiteFlag", un quad compartido) la ondea el shader de SiteFx.
static func _add_flag(root: Node3D, mb, foot: Vector3, pole_h: float, color: Color) -> void:
	mb.cyl(foot, 0.045, pole_h, _t("wood_dark"), 6)
	mb.ball(foot + Vector3(0, pole_h, 0), 0.06, _t("brass"))
	var mi := _shader_mesh(root, "SiteFlag", flag_mesh(), SiteFxKit.flag_material_3d(Tone.snap(color)), foot + Vector3(0.03, pole_h - 0.16, 0), 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## La tela del banderin: un rectangulo partido en 4 tiras (UV.x de 0 en el
## palo a 1 en la punta: el shader ondea mas cuanto mas lejos del palo).
static func flag_mesh() -> QuadMesh:
	if _flag_mesh != null:
		return _flag_mesh
	_flag_mesh = QuadMesh.new()
	_flag_mesh.size = Vector2(0.48, 0.28)
	_flag_mesh.subdivide_width = 4
	_flag_mesh.center_offset = Vector3(0.24, 0, 0)
	return _flag_mesh

## Chispas o polvo de obra (hoja animada de BuildingFx). "" = nada.
static func _add_site_fx(root: Node3D, kind: String, pos: Vector3, size: float) -> void:
	if kind == "":
		return
	var q := Fx.quad_3d(kind, size, "site" if kind == "dust" else "")
	q.name = "SiteFx_" + kind
	q.position = pos + Vector3(0, size * 0.3, 0)
	root.add_child(q)

# ── Mejora ───────────────────────────────────────────────────────────

## Andamio alrededor de un edificio que se esta MEJORANDO: el edificio sigue a
## la vista y el andamio dice que hay obra. Raiz "UpgradeScaffold" con una
## malla ("Scaffold"), una lona de obra en un lado y polvo de obra animado.
static func scaffold(footprint: Vector2i, cell_size: float, height: float) -> Node3D:
	var d := foot_dims(footprint, cell_size)
	var root := Node3D.new()
	root.name = "UpgradeScaffold"
	var h := maxf(1.0, height)
	var mb = _new_mb()
	var spots := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 1), Vector2(0, -1)]
	for s in spots:
		mb.box(Vector3(s.x * d.x * 0.52, h * 0.5, s.y * d.y * 0.52), Vector3(0.08, h, 0.08), _t("wood_dark"))
	# Riostras en aspa delante y detras: se lee "andamio" de lejos.
	for zs in [-1.0, 1.0]:
		for xs in [-1.0, 1.0]:
			mb.beam(Vector3(xs * d.x * 0.52, 0.2, zs * d.y * 0.52), Vector3(0, h * 0.85, zs * d.y * 0.52), 0.05, _t("wood_dark").lightened(0.1))
	var level := 0.8
	var k := 0
	while level < h:
		for zs in [-1.0, 1.0]:
			mb.box(Vector3(0, level, zs * d.y * 0.52), Vector3(d.x * 1.06, 0.07, 0.26), _t("wood_light") if k % 2 == 0 else _t("wood"))
		level += 0.9
		k += 1
	# Barandilla de senal a franjas en lo alto del frente.
	var stripes := 8
	for i in stripes:
		var x := lerpf(-d.x * 0.5, d.x * 0.5, (float(i) + 0.5) / float(stripes))
		mb.box(Vector3(x, h * 0.5, d.y * 0.54), Vector3(d.x / stripes + 0.005, 0.1, 0.05), _t("hazard") if i % 2 == 0 else _t("iron"))
	# Una lona de obra colgada en un costado.
	mb.box(Vector3(d.x * 0.53, h * 0.45, 0), Vector3(0.04, h * 0.6, d.y * 0.7), _t("canvas"))
	_mesh_node(root, "Scaffold", mb)
	_add_site_fx(root, "dust", Vector3(d.x * 0.25, 0.3, d.y * 0.45), 1.0 + 0.2 * LookRule.footprint_class(footprint))
	return root

# ── Ruina ────────────────────────────────────────────────────────────

## Escombros de una ruina, alrededor del modelo hundido y tiznado: suelo
## quemado, montones de cascote, un muro roto de ladrillo, vigas carbonizadas
## al aire y unas brasas que aun brillan (sin luz: se leen en la Tormenta).
## Determinista por `seed_val`: la misma ruina se ve igual tras cargar.
## Raiz "RuinOverlay" con una malla ("Rubble").
static func ruin_overlay(footprint: Vector2i, cell_size: float, seed_val: int = 0) -> Node3D:
	var d := foot_dims(footprint, cell_size)
	var n := clampi(maxi(footprint.x, footprint.y), 1, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var root := Node3D.new()
	root.name = "RuinOverlay"
	var mb = _new_mb()
	mb.box(Vector3(0, 0.015, 0), Vector3(d.x * 1.05, 0.03, d.y * 1.05), _t("scorch"))
	# Cascotes: piedra y pizarra a medio quemar.
	mb.burnt = 0.35
	for k in 3 + n * 2:
		var p := Vector3(rng.randf_range(-0.45, 0.45) * d.x, 0.0, rng.randf_range(-0.45, 0.45) * d.y)
		var s := Vector3(rng.randf_range(0.28, 0.6), rng.randf_range(0.14, 0.35), rng.randf_range(0.28, 0.6)) * (0.8 + 0.2 * n)
		var rot := Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		_box(mb, p + Vector3(0, s.y * 0.4, 0), s, _t("stone") if k % 2 == 0 else _t("steel"), rot)
	# Muro roto: tres trozos de ladrillo de altura decreciente en el lado de atras.
	mb.burnt = 0.45
	var wall_h := [1.1, 0.7, 0.35]
	for i in 3:
		var w := d.x * 0.26
		var hh: float = float(wall_h[i]) * (0.8 + 0.25 * n)
		var x := -d.x * 0.33 + i * w
		mb.box(Vector3(x, hh * 0.5, -d.y * 0.45), Vector3(w * 0.92, hh, 0.2), _t("brick"))
		# Diente de ladrillo suelto en lo alto: el borde no queda recto.
		mb.box(Vector3(x - w * 0.2, hh + 0.08, -d.y * 0.45), Vector3(w * 0.4, 0.16, 0.2), _t("brick").darkened(0.1))
	# Vigas carbonizadas clavadas en angulo: la silueta que se lee de lejos.
	mb.burnt = 0.75
	var embers: Array = []
	for k in 2 + n:
		var p := Vector3(rng.randf_range(-0.3, 0.3) * d.x, 0.6, rng.randf_range(-0.3, 0.3) * d.y)
		var rot := Vector3(rng.randf_range(0.4, 0.9) * (1.0 if k % 2 == 0 else -1.0), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		_box(mb, p, Vector3(0.16, 1.4 + 0.3 * n, 0.16), _t("wood"), rot)
		embers.append(Vector3(p.x, 0.05, p.z))
	mb.burnt = 0.0
	# Brasas al pie de las vigas.
	for e in embers:
		mb.ball(e + Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15)), 0.09, _t("ember"), Vector3(1.0, 0.5, 1.0), true)
	_mesh_node(root, "Rubble", mb)
	return root
