class_name BuildingStatusBadge
extends Label3D
## Indicador flotante del estado de un edificio (A11): el dueno quiere saber que
## hace cada edificio SIN abrir nada. Un billboard encima de cada edificio que
## dice **Zzz** si esta parado y ensena un **obrero** si esta trabajando.
##
## Generaliza el cartel rojo de "SIN TRABAJADORES" que pintaba
## PopulationManager: en vez de un segundo sistema, el mismo badge cubre sin
## trabajadores, en construccion, en ruinas, sin proceso y produciendo. La
## razon del Zzz se distingue por el color (el rojo del cartel viejo se conserva
## para "sin trabajadores", que es la que el jugador puede arreglar).
##
## Escucha EventBus y deriva el estado con `derive()`, una funcion estatica y
## pura que los tests fijan con hechos sueltos, sin escena. El propio Label3D
## es el "Zzz"; el obrero es un Sprite3D hijo con un pictograma dibujado en
## codigo (la fuente por defecto no trae glifos de obrero fiables).
##
## Edificios sin nada que hacer (casas, jardines, calzadas) no llevan badge:
## una casa no esta "parada", es una casa. Ver `can_work()`.

enum Status { NONE, IDLE, WORKING }

## Tamano del glifo. ConstructionLabel usa 18 px a 0.005: aqui hace falta mas
## porque tiene que leerse desde la camara habitual (distancia 20, fov 60).
const FONT_SIZE := 48
const PIXEL_SIZE := 0.0125
## Hueco entre la cima del edificio y el badge.
const HEIGHT_MARGIN := 1.0
## Tamano del pictograma del obrero (textura 32 px x pixel_size).
const ICON_TEXTURE_SIZE := 32
const ICON_PIXEL_SIZE := 0.026

## Colores por razon del Zzz.
const COLOR_IDLE := Color(0.78, 0.86, 1.0, 0.95)        # duerme: azul palido
const COLOR_UNSTAFFED := Color(1.0, 0.35, 0.25, 0.95)   # el rojo del cartel viejo
const COLOR_RUINED := Color(0.65, 0.28, 0.22, 0.95)
const COLOR_CONSTRUCTION := Color(1.0, 0.8, 0.2, 0.9)   # el ambar de ConstructionLabel

var _building: Node3D = null
var _data: BuildingData = null
var _status: int = Status.NONE
var _reason: String = ""
## Proceso o minado en marcha, seguido por senal. Se cruza con
## ProcessManager.is_busy() en refresh() para cubrir la carga de partida.
var _busy: bool = false
var _icon: Sprite3D = null

static var _worker_texture: Texture2D = null

# ── Construccion ──────────────────────────────────────────────────────

## Configura el badge para `building` con sus datos. `top_y` es la altura de la
## cima del edificio (ver `measure_top`); el badge flota HEIGHT_MARGIN encima.
func setup(building: Node3D, data: BuildingData, top_y: float) -> void:
	_building = building
	_data = data
	name = "StatusBadge"
	text = Tr.t("LBL_STATUS_IDLE")
	font_size = FONT_SIZE
	pixel_size = PIXEL_SIZE
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	outline_size = 10
	outline_modulate = Color(0, 0, 0, 0.85)
	position.y = top_y + HEIGHT_MARGIN
	if _icon == null:
		_icon = Sprite3D.new()
		_icon.name = "WorkerIcon"
		_icon.texture = worker_texture()
		_icon.pixel_size = ICON_PIXEL_SIZE
		_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_icon.no_depth_test = true
		_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_icon.visible = false
		add_child(_icon)
	refresh()

func _ready() -> void:
	var bus := EventBus
	bus.production_tick.connect(_on_building_signal)
	bus.process_started.connect(_on_process_started)
	bus.process_completed.connect(_on_process_ended)
	bus.process_cancelled.connect(_on_process_cancelled)
	bus.mining_started.connect(_on_process_started)
	bus.mining_completed.connect(_on_process_ended)
	bus.building_ruined.connect(_on_building_signal)
	bus.building_repaired.connect(_on_building_signal)
	bus.construction_started.connect(_on_building_signal)
	bus.construction_completed.connect(_on_building_signal)
	bus.building_upgrade_started.connect(_on_upgrade_signal)
	bus.building_upgrade_completed.connect(_on_upgrade_signal)
	bus.workers_changed.connect(_on_workers_changed)
	refresh()

func _exit_tree() -> void:
	# Las conexiones a metodos se sueltan solas al liberar el nodo, pero al
	# demoler queremos dejar de escuchar en el acto, no al final del frame.
	var bus := EventBus
	for pair in [
		[bus.production_tick, _on_building_signal],
		[bus.process_started, _on_process_started],
		[bus.process_completed, _on_process_ended],
		[bus.process_cancelled, _on_process_cancelled],
		[bus.mining_started, _on_process_started],
		[bus.mining_completed, _on_process_ended],
		[bus.building_ruined, _on_building_signal],
		[bus.building_repaired, _on_building_signal],
		[bus.construction_started, _on_building_signal],
		[bus.construction_completed, _on_building_signal],
		[bus.building_upgrade_started, _on_upgrade_signal],
		[bus.building_upgrade_completed, _on_upgrade_signal],
		[bus.workers_changed, _on_workers_changed],
	]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)

# ── Senales ───────────────────────────────────────────────────────────

func _on_building_signal(node: Node3D) -> void:
	if node == _building:
		refresh()

func _on_upgrade_signal(node: Node3D, _level: int) -> void:
	if node == _building:
		refresh()

func _on_process_started(node: Node3D, _id: String) -> void:
	if node == _building:
		_busy = true
		refresh()

func _on_process_ended(node: Node3D, _id: String) -> void:
	if node == _building:
		_busy = false
		refresh()

func _on_process_cancelled(node: Node3D, _id: String, _refund: Dictionary) -> void:
	_on_process_ended(node, _id)

func _on_workers_changed(_used: int, _total: int) -> void:
	# El reparto de obreros cambia para todos a la vez; cada badge relee su meta.
	refresh()

# ── Estado ────────────────────────────────────────────────────────────

func get_status() -> int:
	return _status

func get_reason() -> String:
	return _reason

## Relee los hechos del edificio y repinta.
func refresh() -> void:
	if _building == null or _data == null or not is_instance_valid(_building):
		_apply(Status.NONE, "")
		return
	var facts := {
		"can_work": can_work(_data),
		"under_construction": _building.has_meta("under_construction"),
		"ruined": BuildingHealth.is_ruined(_building),
		"busy": _busy or ProcessManager.is_busy(_building),
		"needs_workers": _data.workers_required > 0,
		"staffed": bool(_building.get_meta("staffed", false)),
		"produces": _data.is_producer(),
	}
	var verdict := derive(facts)
	_apply(int(verdict["status"]), String(verdict["reason"]))

## Regla pura: de los hechos al estado. Devuelve {"status": Status, "reason": String}.
## Razones: "" (trabajando o sin badge), "construction", "ruined", "unstaffed", "idle".
##
## Orden: una obra o una ruina mandan sobre todo (no produce ni aunque tenga
## cola); un proceso manual en marcha cuenta como trabajo aunque el edificio no
## produzca pasivamente (el Nucleo fabricando); sin trabajadores es Zzz aunque
## el edificio tenga produccion definida; y un edificio con produccion o
## dotacion en regla esta trabajando.
static func derive(facts: Dictionary) -> Dictionary:
	if not bool(facts.get("can_work", false)):
		return {"status": Status.NONE, "reason": ""}
	if bool(facts.get("under_construction", false)):
		return {"status": Status.IDLE, "reason": "construction"}
	if bool(facts.get("ruined", false)):
		return {"status": Status.IDLE, "reason": "ruined"}
	if bool(facts.get("busy", false)):
		return {"status": Status.WORKING, "reason": ""}
	if bool(facts.get("needs_workers", false)) and not bool(facts.get("staffed", false)):
		return {"status": Status.IDLE, "reason": "unstaffed"}
	if bool(facts.get("produces", false)) or bool(facts.get("needs_workers", false)):
		return {"status": Status.WORKING, "reason": ""}
	return {"status": Status.IDLE, "reason": "idle"}

## Un edificio "puede trabajar" si produce, necesita dotacion o tiene procesos
## manuales. Los demas (casas, decoracion, calzadas) no llevan badge.
static func can_work(data: BuildingData) -> bool:
	if data == null:
		return false
	if data.is_producer() or data.workers_required > 0:
		return true
	return not GameConfig.get_processes_for(data.id).is_empty()

static func color_for_reason(reason: String) -> Color:
	match reason:
		"construction": return COLOR_CONSTRUCTION
		"ruined": return COLOR_RUINED
		"unstaffed": return COLOR_UNSTAFFED
	return COLOR_IDLE

func _apply(status: int, reason: String) -> void:
	_status = status
	_reason = reason
	match status:
		Status.NONE:
			visible = false
		Status.IDLE:
			visible = true
			text = Tr.t("LBL_STATUS_IDLE")
			modulate = color_for_reason(reason)
			if _icon:
				_icon.visible = false
		Status.WORKING:
			visible = true
			text = ""
			if _icon:
				_icon.visible = true

# ── Geometria ─────────────────────────────────────────────────────────

## Cima visual de un edificio: el punto mas alto de todas sus mallas, con sus
## transformaciones (incluida la escala del Nucleo). `BuildingData.mesh_height`
## se queda corto en cuanto la malla crece, y un badge dentro de la cupula no
## sirve de nada.
static func measure_top(node: Node3D) -> float:
	return _measure_top_rec(node, Transform3D.IDENTITY)

static func _measure_top_rec(node: Node, xform: Transform3D) -> float:
	var top: float = -INF
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var n3: Node3D = child
		# Los rotulos no cuentan: son lo que estamos colocando.
		if n3 is Label3D or n3 is Sprite3D:
			continue
		var local: Transform3D = xform * n3.transform
		if n3 is MeshInstance3D and (n3 as MeshInstance3D).mesh:
			var aabb: AABB = local * (n3 as MeshInstance3D).mesh.get_aabb()
			top = maxf(top, aabb.end.y)
		top = maxf(top, _measure_top_rec(n3, local))
	return top

## Pictograma de obrero, 32x32, dibujado a mano y cacheado: casco amarillo,
## cara, peto azul y brazos, con contorno oscuro para que lea sobre la hierba.
static func worker_texture() -> Texture2D:
	if _worker_texture != null:
		return _worker_texture
	var s := ICON_TEXTURE_SIZE
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hat := Color(0.95, 0.75, 0.10)
	var skin := Color(0.90, 0.70, 0.55)
	var suit := Color(0.25, 0.42, 0.72)
	var strap := Color(0.15, 0.25, 0.45)
	# Casco: media esfera arriba + visera
	_disc(img, Vector2i(16, 10), 7, hat, true)
	_rect(img, 7, 10, 25, 11, hat)
	# Cara
	_disc(img, Vector2i(16, 14), 5, skin, false)
	_rect(img, 11, 12, 21, 17, skin)
	# Peto y hombros
	_rect(img, 9, 19, 23, 30, suit)
	_rect(img, 12, 18, 20, 19, suit)
	_rect(img, 13, 20, 14, 30, strap)
	_rect(img, 18, 20, 19, 30, strap)
	# Brazos
	_rect(img, 6, 20, 8, 27, skin)
	_rect(img, 24, 20, 26, 27, skin)
	_outline(img, Color(0.05, 0.05, 0.05, 0.95))
	_worker_texture = ImageTexture.create_from_image(img)
	return _worker_texture

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)

static func _disc(img: Image, center: Vector2i, r: int, c: Color, upper_half_only: bool) -> void:
	for y in range(center.y - r, center.y + r + 1):
		if upper_half_only and y > center.y:
			continue
		for x in range(center.x - r, center.x + r + 1):
			if Vector2(x - center.x, y - center.y).length() <= float(r) + 0.3:
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, c)

## Pinta de `c` cada pixel transparente que toque uno opaco (contorno de 1 px).
static func _outline(img: Image, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in range(h):
		for x in range(w):
			if src.get_pixel(x, y).a > 0.5:
				continue
			var touches := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					touches = true
					break
			if touches:
				img.set_pixel(x, y, c)
