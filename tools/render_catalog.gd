extends SceneTree
## Dev tool: retrata cada edificio del juego por separado para la guia.
##
## Nada de mockups: instancia el mismo modelo que ve el jugador. Replica la
## logica de BuildingPlacer._create_building_mesh(): si el .tres trae
## model_scene (el GLB), se usa ese; si no, se genera con
## DieselpunkBuildingFactory.create(id, cell_size, grid_size).
##
## Uso (CON ventana, NO headless: sin render 3D las capturas salen negras):
##   godot --path . -s tools/render_catalog.gd
##
## Salida: res://docs/media/guia/<building_id>.png  (400x400, fondo BG_DARK)
##
## Encuadre: camara en perspectiva 3/4 fija (mismo angulo que la partida,
## ver MonumentalCamera) y distancia mezclada entre "lleno el cuadro" y
## "escala compartida" —ver ENCUADRE_MIX—, para que un 2x2 se vea mas grande
## que un 1x1 sin que un 1x1 quede como una mota.
##
## Hermano de tools/render_brand.gd (marca) y tools/showcase_shots.gd (UI).

const DATA_DIR := "res://data/buildings"
const OUT_DIR := "res://docs/media/guia"

## Lado del PNG final. Se renderiza a SHOT*SUPER y se reduce: antialias barato.
const SHOT := 400
const SUPER := 2

## Angulo de camara: 3/4 dieselpunk, primo del isometrico de la partida
## (MonumentalCamera usa pitch -45 y pasos de yaw de 45).
const CAM_FOV := 30.0
const CAM_YAW := 38.0
const CAM_PITCH := -30.0

## Cuanto del cuadro puede ocupar el edificio (1.0 = pegado a los bordes).
const ENCUADRE_MARGEN := 0.88
## 0.0 = todos a la misma distancia (escala real, el 1x1 queda diminuto).
## 1.0 = cada uno llena su cuadro (no se pueden comparar).
## Con 0.6 el tamano aparente crece como size^0.4: el nucleo 3x3 llena el
## cuadro, la vivienda 1x1 ocupa poco mas de la mitad, y el orden se lee.
const ENCUADRE_MIX := 0.6

## Empujon vertical, en fracciones de medio cuadro. Centrar la caja deja al
## edificio un pelin bajo —la silueta no llena las esquinas de arriba de la
## caja—, asi que se sube un poco a ojo.
const ENCUADRE_SUBIR := 0.06

## Fondo neutro de la paleta (UITheme.BG_DARK).
const BG := Color(0.05, 0.06, 0.04)

var _cam: Camera3D
var _mundo: Node3D
var _aabb: AABB
var _aabb_ok: bool


func _initialize() -> void:
	var ids := _leer_edificios()
	if ids.is_empty():
		_fail("no se encontro ningun .tres en " + DATA_DIR)
		return

	var err := DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_fail("no se pudo crear %s (err %d)" % [OUT_DIR, err])
		return

	# El proyecto usa stretch canvas_items sobre 1280x720; sin desactivarlo, un
	# lienzo cuadrado se escala y se recorta.
	var px := SHOT * SUPER
	var root := get_root()
	DisplayServer.window_set_size(Vector2i(px, px))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(px, px)
	root.msaa_3d = Viewport.MSAA_4X
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

	_montar_estudio()
	await process_frame

	# Base de la camara: fija para todos, asi que se calcula una sola vez.
	var dir := _direccion_camara()
	_cam.global_position = dir * 10.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	var base := _cam.global_transform.basis
	var derecha := base.x
	var arriba := base.y
	var frente := -base.z

	# Pasada 1: instanciar todo, medir su volumen y su distancia de encuadre.
	var fichas: Array = []
	var d_max := 0.0
	for id in ids:
		var ficha := _instanciar(id)
		if ficha.is_empty():
			printerr("[catalog] sin modelo para %s, se salta" % id)
			continue
		_mundo.add_child(ficha["nodo"])
		ficha["nodo"].visible = false
		await process_frame
		var caja := _medir(ficha["nodo"])
		if caja.size == Vector3.ZERO:
			printerr("[catalog] %s no tiene geometria visible, se salta" % id)
			continue
		ficha["caja"] = caja
		var ajuste := _encuadrar(caja, derecha, arriba, frente,
				_distancia_encuadre(caja, derecha, arriba, frente), true)
		ficha["dist"] = ajuste[0]
		d_max = maxf(d_max, ficha["dist"])
		fichas.append(ficha)

	# Pasada 2: retratar. La distancia mezcla encuadre propio y escala comun.
	var hechas: Array = []
	for ficha in fichas:
		for otra in fichas:
			otra["nodo"].visible = false
		ficha["nodo"].visible = true

		var caja: AABB = ficha["caja"]
		var dist: float = pow(ficha["dist"], ENCUADRE_MIX) * pow(d_max, 1.0 - ENCUADRE_MIX)
		# A la distancia final hay que recentrar otra vez: la perspectiva mueve
		# la silueta segun lo cerca que este la camara.
		var mira: Vector3 = _encuadrar(caja, derecha, arriba, frente, dist, false)[1]
		_cam.global_position = mira + dir * dist
		_cam.look_at(mira, Vector3.UP)

		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw

		var img := root.get_texture().get_image()
		img.resize(SHOT, SHOT, Image.INTERPOLATE_LANCZOS)
		var ruta: String = "%s/%s.png" % [OUT_DIR, ficha["id"]]
		var e := img.save_png(ruta)
		print("[catalog] %s -> %dx%d  celdas %s  alto %.2f  encuadre %.1f  dist %.1f (err %d)" % [
			ruta, img.get_width(), img.get_height(),
			str(ficha["celdas"]), caja.size.y, ficha["dist"], dist, e])
		hechas.append(ficha["id"])

	print("[catalog] %d/%d edificios retratados en %s" % [hechas.size(), ids.size(), OUT_DIR])
	quit(0)


## Lee los ids de data/buildings/*.tres. No se escriben a mano: si manana hay
## un edificio nuevo, aparece solo.
func _leer_edificios() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return ids
	for archivo in dir.get_files():
		# Exportado, los .tres llegan como .remap; da igual, load() resuelve.
		if not archivo.ends_with(".tres"):
			continue
		# Sin tipar a BuildingData a proposito: al arrancar con -s, ese script
		# tira de ResourceManager -> EventBus, que todavia no existe, y Godot
		# escupe un "Identifier not found: EventBus" antes de recompilar.
		var data = load("%s/%s" % [DATA_DIR, archivo])
		if data == null or not ("id" in data):
			continue
		ids.append(data.id)
	ids.sort()
	return ids


## Instancia el modelo del jugador: GLB si el .tres lo trae, si no la fabrica.
func _instanciar(id: String) -> Dictionary:
	var data = load("%s/%s.tres" % [DATA_DIR, id])
	if data == null:
		return {}
	var celda := _cell_size()
	var modelo: Node3D = null
	if data.model_scene:
		modelo = data.model_scene.instantiate()
	else:
		modelo = DieselpunkBuildingFactory.create(data.id, celda, data.grid_size)
	if modelo == null:
		return {}
	var raiz := Node3D.new()
	raiz.name = id
	raiz.add_child(modelo)
	return {"id": id, "nodo": raiz, "celdas": data.grid_size}


## cell_size real de la partida (GridManager es autoload; 2.0 es su valor por
## defecto y el respaldo si el autoload no esta cargado).
func _cell_size() -> float:
	var gm := get_root().get_node_or_null("GridManager")
	if gm != null and "cell_size" in gm:
		return float(gm.cell_size)
	return 2.0


## Fondo plano, sin cielo ni terreno, y tres luces: clave con sombra para el
## volumen, relleno frio para que la cara oscura no se cierre, y contra para
## recortar la silueta contra el fondo.
func _montar_estudio() -> void:
	_mundo = Node3D.new()
	get_root().add_child(_mundo)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.80)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	# Los detalles emisivos (hornos, faroles) son medio dieselpunk: que brillen.
	# El umbral alto es clave: sin el, los modelos claros (casi todos son chapa
	# blanca) florecen enteros y salen envueltos en niebla.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	_mundo.add_child(we)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.near = 0.05
	_cam.far = 500.0
	_mundo.add_child(_cam)
	_cam.current = true

	var dir := _direccion_camara()
	# Ejes de pantalla para colocar las luces respecto al punto de vista.
	var derecha := dir.cross(Vector3.UP).normalized()
	var arriba := Vector3.UP

	_luz(-derecha * 0.7 + arriba * 1.1 + dir * 0.5, Color(1.0, 0.95, 0.86), 2.2, true)
	_luz(derecha * 1.0 + arriba * 0.25 + dir * 0.3, Color(0.62, 0.72, 0.90), 0.65, false)
	_luz(derecha * 0.2 + arriba * 0.45 - dir * 1.0, Color(0.95, 0.80, 0.55), 0.9, false)


func _luz(desde: Vector3, color: Color, energia: float, sombra: bool) -> void:
	var luz := DirectionalLight3D.new()
	luz.light_color = color
	luz.light_energy = energia
	luz.shadow_enabled = sombra
	if sombra:
		luz.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		luz.directional_shadow_max_distance = 60.0
		luz.shadow_normal_bias = 0.6
	_mundo.add_child(luz)
	luz.look_at_from_position(desde.normalized() * 30.0, Vector3.ZERO, Vector3.UP)


## Vector unitario del centro hacia la camara.
func _direccion_camara() -> Vector3:
	var p := deg_to_rad(CAM_PITCH)
	var y := deg_to_rad(CAM_YAW)
	return Vector3(cos(p) * sin(y), -sin(p), cos(p) * cos(y)).normalized()


## Caja envolvente en mundo de toda la geometria del nodo.
func _medir(nodo: Node) -> AABB:
	_aabb_ok = false
	_aabb = AABB()
	_recorrer(nodo)
	return _aabb if _aabb_ok else AABB()


func _recorrer(nodo: Node) -> void:
	if nodo is VisualInstance3D:
		var vi := nodo as VisualInstance3D
		var caja := vi.get_aabb()
		var t := vi.global_transform
		for i in 8:
			var p: Vector3 = t * _esquina(caja, i)
			if not _aabb_ok:
				_aabb = AABB(p, Vector3.ZERO)
				_aabb_ok = true
			else:
				_aabb = _aabb.expand(p)
	for hijo in nodo.get_children():
		_recorrer(hijo)


## Distancia minima a la que las 8 esquinas caben en el cuadro.
## Con la camara en centro + dir*d, para una esquina p: su profundidad es
## d + p·frente y su desplazamiento lateral p·derecha, asi que cabe si
## |p·derecha| <= tan(fov/2) * (d + p·frente). Se despeja d y se toma el peor.
func _distancia_encuadre(caja: AABB, derecha: Vector3, arriba: Vector3, frente: Vector3) -> float:
	var centro := caja.position + caja.size * 0.5
	# Viewport cuadrado: el medio angulo horizontal es igual al vertical.
	var t := tan(deg_to_rad(CAM_FOV * 0.5)) * ENCUADRE_MARGEN
	var d := 0.1
	for i in 8:
		var v := _esquina(caja, i) - centro
		var prof := v.dot(frente)
		d = maxf(d, absf(v.dot(derecha)) / t - prof)
		d = maxf(d, absf(v.dot(arriba)) / t - prof)
	return d


## Afina el encuadre sobre la caja: mueve el punto de mira hasta que la
## proyeccion real de las 8 esquinas queda centrada en el cuadro y, si
## ajustar_distancia, acerca o aleja la camara hasta rozar ENCUADRE_MARGEN.
## Centrar permite acercarse mas: la caja vista en 3/4 se proyecta torcida y
## sin esto sobra aire de un lado y falta del otro.
## Devuelve [distancia, punto_de_mira].
func _encuadrar(caja: AABB, derecha: Vector3, arriba: Vector3, frente: Vector3,
		d0: float, ajustar_distancia: bool) -> Array:
	var mira := caja.position + caja.size * 0.5
	var d := d0
	var t := tan(deg_to_rad(CAM_FOV * 0.5))
	for paso in 5:
		var u_min := INF
		var u_max := -INF
		var w_min := INF
		var w_max := -INF
		for i in 8:
			var v := _esquina(caja, i) - mira
			# Profundidad desde la camara, que esta en mira + dir * d.
			var prof := maxf(0.01, d + v.dot(frente))
			var u := v.dot(derecha) / (t * prof)
			var w := v.dot(arriba) / (t * prof)
			u_min = minf(u_min, u)
			u_max = maxf(u_max, u)
			w_min = minf(w_min, w)
			w_max = maxf(w_max, w)
		# Desplaza la mira para que el centro de la proyeccion caiga en el medio.
		var uc := (u_min + u_max) * 0.5
		var wc := (w_min + w_max) * 0.5
		mira += derecha * (uc * t * d) + arriba * ((wc - ENCUADRE_SUBIR) * t * d)
		if ajustar_distancia:
			var ext: float = maxf(u_max - u_min, w_max - w_min) * 0.5
			d = maxf(0.5, d * ext / ENCUADRE_MARGEN)
	return [d, mira]


func _esquina(caja: AABB, i: int) -> Vector3:
	return caja.position + Vector3(
		caja.size.x * float(i & 1),
		caja.size.y * float((i >> 1) & 1),
		caja.size.z * float((i >> 2) & 1))


func _fail(msg: String) -> void:
	printerr("[catalog] " + msg)
	quit(1)
