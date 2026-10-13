extends Node3D
## Los efectos del tablero 3D: fogonazo, trazadora, obus en parabola, polvo del
## impacto, numero de dano flotante, crater donde cae una unidad y la etiqueta
## de "quien es" al tocar una pieza.
##
## Particulas minimas por regla del dueno ("tiene que ir en una papa"): nada de
## GPUParticles. Cada efecto son una o pocas mallas diminutas con un material
## sin luz compartido, movidas con un tween y liberadas al acabar. En calidad
## sencilla (`simple`) se quita el polvo, que es lo unico que se multiplica.

var simple := false

static var _spark_mesh: Mesh = null
static var _dust_mesh: Mesh = null
static var _crater_mesh: Mesh = null
static var _mats: Dictionary = {}

const DUST_PIECES := 5

# ── Disparos ─────────────────────────────────────────────────────────

func muzzle_flash(at: Vector3, size := 0.5) -> Tween:
	var mi := _spark(_mat("flash", Color(1.0, 0.84, 0.42)))
	mi.position = at
	mi.scale = Vector3.ONE * 0.05
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.05).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.02, 0.1).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	return tw

## Una bala trazadora recta (infanteria, blindado): rapida, se ve como un trazo.
func tracer(from: Vector3, to: Vector3, time := 0.09) -> Tween:
	var mi := _spark(_mat("tracer", Color(1.0, 0.93, 0.6)))
	mi.position = from
	mi.scale = Vector3(0.12, 0.12, 0.12)
	var tw := mi.create_tween()
	tw.tween_property(mi, "position", to, time)
	tw.tween_callback(mi.queue_free)
	return tw

## El obus de la artilleria: sube y cae en parabola, para que se vea que
## dispara POR ENCIMA de la linea (su alcance minimo es la gracia de la pieza).
func shell(from: Vector3, to: Vector3, time := 0.36, apex := 2.4) -> Tween:
	var mi := _spark(_mat("shell", Color(0.16, 0.13, 0.12)))
	mi.position = from
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween()
	tw.tween_method(func(t: float): mi.position = from.lerp(to, t) + Vector3(0, sin(PI * t) * apex, 0), 0.0, 1.0, time)
	tw.tween_callback(mi.queue_free)
	return tw

## Polvo del impacto: unos pocos tacos que saltan y se encogen.
func puff(at: Vector3, color := Color(0.78, 0.68, 0.5)) -> void:
	if simple:
		return
	for k in DUST_PIECES:
		var mi := MeshInstance3D.new()
		mi.mesh = _dust()
		mi.material_override = _mat("dust_%s" % color.to_html(false), color)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = at
		var a := TAU * float(k) / float(DUST_PIECES) + randf() * 0.6
		var out := at + Vector3(cos(a) * 0.7, 0.35 + randf() * 0.5, sin(a) * 0.7)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "position", out, 0.32).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.32).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

# ── Numeros y etiquetas ──────────────────────────────────────────────

## El numero de dano: salta desde la unidad, sube y se apaga.
func damage_number(at: Vector3, amount: int) -> Label3D:
	var label := _label("-%d" % amount, UITheme.DANGER.lightened(0.35), 96)
	label.position = at
	label.scale = Vector3.ONE * 0.4
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE * 1.15, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector3.ONE, 0.08)
	tw.parallel().tween_property(label, "position:y", at.y + 1.3, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.tween_callback(label.queue_free)
	return label

## "Infanteria 80/100": lo que dice una pieza al tocarla (con el dedo no hay
## tooltip). Se va sola.
func info_label(at: Vector3, text: String, color: Color, time := 1.8) -> Label3D:
	var label := _label(text, color, 56)
	label.position = at
	label.name = "InfoLabel"
	var tw := label.create_tween()
	tw.tween_interval(time)
	tw.tween_property(label, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.3)
	tw.tween_callback(label.queue_free)
	return label

func _label(text: String, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.012
	label.outline_size = maxi(8, font_size / 6)
	label.modulate = color
	label.outline_modulate = Color(0.08, 0.06, 0.05, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.render_priority = 4
	label.outline_render_priority = 3
	var font := UITheme.heavy_font()
	if font != null:
		label.font = font
	add_child(label)
	return label

# ── Huellas en el suelo ──────────────────────────────────────────────

## Donde cae una unidad queda un crater: la pelea deja marca en la maqueta.
func crater(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Crater"
	mi.mesh = _crater()
	mi.material_override = _mat("crater", Color(0.2, 0.15, 0.1, 0.55), true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x, 0.025, at.z)
	mi.rotation.y = randf() * TAU
	add_child(mi)
	mi.scale = Vector3.ONE * 0.3
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.2).set_ease(Tween.EASE_OUT)
	return mi

func clear() -> void:
	for child in get_children():
		child.queue_free()

# ── Mallas y materiales compartidos ──────────────────────────────────

func _spark(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _spark_sphere()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

static func _spark_sphere() -> Mesh:
	if _spark_mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 8
		s.rings = 4
		_spark_mesh = s
	return _spark_mesh

static func _dust() -> Mesh:
	if _dust_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.26, 0.26, 0.26)
		_dust_mesh = b
	return _dust_mesh

static func _crater() -> Mesh:
	if _crater_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.75
		c.bottom_radius = 0.85
		c.height = 0.03
		c.radial_segments = 9
		c.rings = 1
		_crater_mesh = c
	return _crater_mesh

static func _mat(key: String, color: Color, alpha := false) -> Material:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		if alpha:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]
