extends Node
## La cache de dibujos horneados de la vista 2D (rendimiento: la 2D es la
## opcion para equipos flojos, tiene que ir "en una papa").
##
## Un edificio de BuildingArt2D son cien o doscientas ordenes de dibujo
## (discos, poligonos, lineas). Godot las guarda, pero el renderizador las
## recorre y las rellena en cada fotograma, y en un mapa con doscientas
## calzadas y cincuenta edificios eso es lo que mas cuesta. Aqui cada dibujo se
## pinta UNA vez en un SubViewport pequeno (a `SCALE` px por px de mapa, para
## que se vea nitido de cerca), se lee como imagen con mipmaps y se guarda por
## clave (edificio, giro, nivel, calzadas vecinas...). Desde entonces el
## edificio es un solo rectangulo con textura.
##
## Mientras la textura no esta (el primer fotograma, o sin renderizador: las
## pruebas headless) quien la pide dibuja a mano, igual que antes; al tenerla
## se le avisa con queue_redraw(). Lo que cambia a menudo (obra, ruina, cultivo,
## atrezo de la parcela) no se hornea.
##
## Ojo con el alfa: el horneado mezcla sobre transparente, asi que lo
## semitransparente que no sea negro sale mas oscuro. Los dibujos horneados solo
## llevan semitransparencia en sombras (oscuras) y en brillos sobre zonas
## opacas, donde no se nota.

## Pixeles de textura por pixel de mapa (la camara llega a zoom 3: x2 basta).
const SCALE := 2.0
## Margen alrededor de la huella: sombras, chimeneas, mastiles y el canon.
const MARGIN := 14.0
## Horneados que se lanzan como mucho en un fotograma.
const PER_FRAME := 24
## Intentos por clave antes de rendirse y dibujar a mano para siempre.
const TRIES := 3

## clave -> Texture2D, o null si no se pudo hornear (se dibuja a mano).
static var _tex := {}
## clave -> Array de WeakRef de quien espera la textura.
static var _waiting := {}
## Pendientes: {key, size, painter, margin, scale, done}.
static var _queue: Array = []
static var _node: Node = null
## Interruptor (herramientas de captura y pruebas pueden apagarla).
static var enabled := true

## En curso: [peticion, SubViewport, fotograma en que se lanzo, intentos].
var _inflight: Array = []

## Margen y escala de los horneados POR INSTANCIA (la parcela entera de un
## edificio: suelo, cuerpo y atrezo). La parcela ya cubre la huella, asi que el
## margen es pequeno; la escala es algo menor para que doscientas parcelas
## quepan en poca memoria.
const INSTANCE_MARGIN := 6.0
const INSTANCE_SCALE := 1.5

static func available() -> bool:
	return enabled and DisplayServer.get_name() != "headless"

## El rectangulo (marco local, centrado) donde se pinta la textura de un
## dibujo de tamano `size`.
static func rect_for(size: Vector2, margin: float = MARGIN) -> Rect2:
	return Rect2(-size * 0.5 - Vector2.ONE * margin, size + Vector2.ONE * margin * 2.0)

## Textura horneada de `key`, o null si aun no esta. Si no esta la pide una sola
## vez: `painter` (Callable(ci: CanvasItem)) dibuja centrado en el origen con
## tamano `size`, y `who` recibe queue_redraw() cuando este lista.
static func fetch(key: String, size: Vector2, painter: Callable, who: CanvasItem) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	if not available() or who == null or not who.is_inside_tree():
		return null
	if _waiting.has(key):
		(_waiting[key] as Array).append(weakref(who))
		return null
	_waiting[key] = [weakref(who)]
	_queue.append({"key": key, "size": size, "painter": painter, "margin": MARGIN, "scale": SCALE, "done": Callable()})
	_ensure(who.get_tree())
	return null

## Un horneado suelto, sin clave compartida (la parcela de UNA instancia): al
## terminar llama `done(textura)` (textura null si no se pudo). Quien lo pide
## guarda la textura y la suelta cuando ya no le sirve. Devuelve false si no
## hay horneado posible (pruebas headless): entonces se dibuja a mano.
static func bake(size: Vector2, painter: Callable, who: CanvasItem, done: Callable) -> bool:
	if not available() or who == null or not who.is_inside_tree():
		return false
	_queue.append({"key": "", "size": size, "painter": painter, "margin": INSTANCE_MARGIN,
		"scale": INSTANCE_SCALE, "done": done})
	_ensure(who.get_tree())
	return true

static func has_texture(key: String) -> bool:
	return _tex.get(key) != null

static func count() -> int:
	return _tex.size()

## Memoria aproximada de lo horneado, en bytes (para la sonda).
static func bytes() -> int:
	var total := 0
	for t in _tex.values():
		if t != null:
			total += int((t as Texture2D).get_width() * (t as Texture2D).get_height() * 4 * 1.34)
	return total

static func _ensure(tree: SceneTree) -> void:
	if _node != null and is_instance_valid(_node):
		return
	_node = load("res://scripts/view2d/ArtCache2D.gd").new()
	_node.name = "ArtCache2D"
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_node)

func _process(_delta: float) -> void:
	var drawn := Engine.get_frames_drawn()
	# Recoger lo que ya se pinto (al menos un fotograma despues de lanzarlo).
	var still: Array = []
	for job in _inflight:
		var vp: SubViewport = job[1]
		if drawn <= int(job[2]) + 1:
			still.append(job)
			continue
		var req: Dictionary = job[0]
		var done: Callable = req["done"]
		# Quien lo pidio ya no esta (edificio demolido, escena cambiada): nada.
		if String(req["key"]) == "" and not done.is_valid():
			vp.queue_free()
			continue
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			if int(job[3]) + 1 < TRIES:
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE
				still.append([req, vp, drawn, int(job[3]) + 1])
				continue
			_finish(req, null)
		else:
			img.generate_mipmaps()
			_finish(req, ImageTexture.create_from_image(img))
		vp.queue_free()
	_inflight = still
	# Lanzar los pendientes.
	var n := 0
	while not _queue.is_empty() and n < PER_FRAME:
		_launch(_queue.pop_front())
		n += 1

func _launch(req: Dictionary) -> void:
	var rect := rect_for(req["size"], float(req["margin"]))
	var scale := float(req["scale"])
	var painter: Callable = req["painter"]
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.size = Vector2i(ceili(rect.size.x * scale), ceili(rect.size.y * scale))
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := Node2D.new()
	canvas.draw.connect(func() -> void:
		canvas.draw_set_transform(-rect.position * scale, 0.0, Vector2(scale, scale))
		if painter.is_valid():
			painter.call(canvas))
	vp.add_child(canvas)
	add_child(vp)
	_inflight.append([req, vp, Engine.get_frames_drawn(), 0])

static func _finish(req: Dictionary, tex: Texture2D) -> void:
	var key := String(req["key"])
	if key == "":
		var done: Callable = req["done"]
		if done.is_valid():
			done.call(tex)
		return
	_tex[key] = tex
	for w in _waiting.get(key, []):
		var who: Object = (w as WeakRef).get_ref()
		if who != null and is_instance_valid(who):
			(who as CanvasItem).queue_redraw()
	_waiting.erase(key)
