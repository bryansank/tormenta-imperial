extends Node2D
## El indicador Zzz / obrero (A11) en la vista 2D. La regla es la misma que en
## 3D —BuildingStatusBadge.derive(), estatica y pura— y el pictograma del obrero
## es la misma textura; solo cambia como se pinta: aqui es un Node2D en la
## esquina superior del edificio, contraescalado para leerse a cualquier zoom.
##
## Se llama "StatusBadge" y tiene refresh(): PopulationManager lo busca por ese
## nombre al repartir obreros, igual que en 3D. Ademas se relee cada poco por si
## acaso (procesos que empiezan, cargas de partida) sin escuchar senales.
##
## Compacto (2026-10-18, feat/vista2d-y-prologo): el cartel "Zzz sin
## trabajadores" entero salia hacia la izquierda desde la esquina y se comia el
## edificio de al lado (dos vecinos parados = dos carteles pisados). Ahora, en
## reposo, es una ficha pequena —"Zzz" y un pictograma del motivo (obrero
## tachado, calzada tachada, veta tachada, llama, caja llena)— que nunca sale de
## la huella de su edificio: si al alejarse no cabe, encoge (`chip_scale`). El
## texto entero sale solo con el edificio seleccionado (y en su ficha, como
## siempre). En obras no se pinta: ya lo dice el rotulo de la obra, como en 3D.

const Badge3D := preload("res://scripts/buildings/BuildingStatusBadge.gd")

## Cada cuanto se relee (lo marca Building2D: CHECK_FRAMES x BADGE_EVERY fotogramas).
const REFRESH_EVERY := 0.5
const ICON_PX := 18.0
## La ficha compacta: alto, tamano de letra y lado del pictograma (px de badge).
const CHIP_H := 17.0
const CHIP_FS := 12
const GLYPH_PX := 11.0
## Lo que la ficha puede ocupar del ancho de la huella, como mucho.
const CHIP_MAX_FRACTION := 0.9

var _building: Node2D = null
var _data: BuildingData = null
var _status: int = Badge3D.Status.NONE
var _reason: String = ""
## Ultimo zoom, huella y seleccion con que se coloco (solo se recoloca si cambian).
var _placed_zoom := -1.0
var _placed_fp := Vector2.ZERO
var _expanded := false

func setup(building: Node2D, data: BuildingData) -> void:
	_building = building
	_data = data
	name = "StatusBadge"
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh()

func get_status() -> int:
	return _status

func get_reason() -> String:
	return _reason

## ¿Esta ensenando el texto entero (edificio seleccionado)?
func is_expanded() -> bool:
	return _expanded

## Building2D lo llama al seleccionar o soltar el edificio (sin mirar cada
## fotograma): seleccionado, el cartel entero; si no, la ficha.
func set_expanded(value: bool) -> void:
	if value == _expanded:
		return
	_expanded = value
	_placed_zoom = -1.0
	place()
	queue_redraw()

func refresh() -> void:
	if _building == null or _data == null or not is_instance_valid(_building):
		_apply(Badge3D.Status.NONE, "")
		return
	var facts := {
		"can_work": Badge3D.can_work(_data),
		"under_construction": _building.has_meta("under_construction"),
		"ruined": BuildingHealth.is_ruined(_building),
		"connected": bool(_building.get_meta("connected", true)),
		"has_vein": bool(_building.get_meta("has_vein", true)),
		"workers_off": bool(_building.get_meta("workers_off", false)),
		"busy": ProcessManager.is_busy(_building),
		"needs_workers": _data.workers_required > 0,
		"staffed": bool(_building.get_meta("staffed", false)),
		"produces": _data.is_producer(),
		"full": ProductionManager.is_full(_building),
	}
	var verdict := Badge3D.derive(facts)
	_apply(int(verdict["status"]), String(verdict["reason"]))

## ¿Se pinta este estado? "idle" es el Nucleo en reposo, su estado normal (un
## "Zzz parado" fijo en el edificio principal parecia una averia), y en obras ya
## habla el rotulo de la obra: ninguno de los dos se pinta, como en 3D.
static func shows(status: int, reason: String) -> bool:
	if status == Badge3D.Status.NONE:
		return false
	if status == Badge3D.Status.IDLE and (reason == "idle" or reason == "construction"):
		return false
	return true

func _apply(status: int, reason: String) -> void:
	if status == _status and reason == _reason:
		return
	_status = status
	_reason = reason
	visible = shows(status, reason)
	_placed_zoom = -1.0
	place()
	queue_redraw()

## Sin _process (2026-10-26): la relectura la pide su Building2D desde el reloj
## unico (Building2DClock, cada ~0,5 s) y la colocacion, ese reloj cuando cambia
## el zoom, o el propio badge cuando cambia lo que ensena.
func _ready() -> void:
	set_process(false)
	place()

## Coloca el badge en la esquina de la huella, contraescalado al zoom. Solo
## trabaja si cambio el zoom, la huella (girar, mover) o la seleccion.
func place() -> void:
	if not visible or _building == null or not is_inside_tree():
		return
	# Solo se recoloca si cambio el zoom, la huella (girar, mover) o la seleccion.
	var z := _frame_zoom(self)
	var fp: Vector2 = _building.footprint_px() if _building.has_method("footprint_px") else Vector2(32, 32)
	if is_equal_approx(z, _placed_zoom) and fp == _placed_fp:
		return
	_placed_zoom = z
	_placed_fp = fp
	var inv: float = _building.label_scale(self) if _building.has_method("label_scale") else 1.0
	if not _expanded:
		inv = chip_scale(inv, chip_width(_status), fp.x)
	scale = Vector2(inv, inv)
	# Esquina superior derecha de la huella, por dentro.
	position = Vector2(fp.x * 0.5 - 3.0, -fp.y * 0.5 + 3.0)

## Escala de la ficha: la del rotulo (`label_inv`), pero sin que la ficha de
## `chip_w` px pase de CHIP_MAX_FRACTION del ancho de la huella. Asi dos
## vecinos parados nunca se pisan. Pura, para las pruebas.
static func chip_scale(label_inv: float, chip_w: float, footprint_w: float) -> float:
	if chip_w <= 0.0:
		return label_inv
	return minf(label_inv, footprint_w * CHIP_MAX_FRACTION / chip_w)

## Ancho de la ficha compacta en px de badge: "Zzz" y el pictograma; el obrero
## trabajando es un circulo de ICON_PX.
static func chip_width(status: int) -> float:
	if status == Badge3D.Status.WORKING:
		return ICON_PX * 1.24
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(Tr.t("LBL_STATUS_IDLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FS).x if font else 22.0
	return tw + GLYPH_PX + 12.0

## El zoom de la camara, leido UNA vez por fotograma para todos los badges.
static var _zoom_frame := -1
static var _zoom := 1.0
static func _frame_zoom(ci: CanvasItem) -> float:
	var f := Engine.get_process_frames()
	if f != _zoom_frame:
		_zoom_frame = f
		var cam := ci.get_viewport().get_camera_2d()
		_zoom = cam.zoom.x if cam != null else 1.0
	return _zoom

func _draw() -> void:
	match _status:
		Badge3D.Status.IDLE:
			if _expanded:
				_draw_full_label()
			else:
				draw_chip(self, _reason)
		Badge3D.Status.WORKING:
			var tex := Badge3D.worker_texture()
			draw_circle(Vector2(-ICON_PX * 0.5, ICON_PX * 0.5), ICON_PX * 0.62, Color(0.05, 0.05, 0.05, 0.6))
			draw_texture_rect(tex, Rect2(Vector2(-ICON_PX, 0), Vector2(ICON_PX, ICON_PX)), false)

## El cartel de siempre ("Zzz sin trabajadores"), solo con el edificio
## seleccionado: hacia la izquierda desde la esquina.
func _draw_full_label() -> void:
	var font := ThemeDB.fallback_font
	var col := Badge3D.color_for_reason(_reason)
	var text := "%s %s" % [Tr.t("LBL_STATUS_IDLE"), Badge3D.reason_text(_reason)]
	var fs := 14
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(Vector2(-w - 6, 0), Vector2(w + 8, fs + 5)), Color(0.05, 0.05, 0.05, 0.75))
	var base := Vector2(-w - 2, fs)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## La ficha compacta, con su esquina superior derecha en (0, 0): fondo oscuro,
## "Zzz" en el color del motivo y el pictograma. Estatica para las pruebas.
static func draw_chip(ci: CanvasItem, reason: String) -> void:
	var font := ThemeDB.fallback_font
	var col := Badge3D.color_for_reason(reason)
	var w := chip_width(Badge3D.Status.IDLE)
	var r := Rect2(Vector2(-w, 0), Vector2(w, CHIP_H))
	ci.draw_rect(r, Color(0.05, 0.05, 0.05, 0.72))
	ci.draw_rect(r, Color(col, 0.9), false, 1.0)
	if font != null:
		var base := Vector2(-w + 4.0, CHIP_H - 4.0)
		ci.draw_string_outline(font, base, Tr.t("LBL_STATUS_IDLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FS, 3, Color(0, 0, 0, 0.9))
		ci.draw_string(font, base, Tr.t("LBL_STATUS_IDLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FS, col)
	draw_reason_glyph(ci, reason, Rect2(Vector2(-GLYPH_PX - 3.0, (CHIP_H - GLYPH_PX) * 0.5), Vector2(GLYPH_PX, GLYPH_PX)), col)

## El pictograma del motivo dentro de `r`: lo que falta, tachado.
static func draw_reason_glyph(ci: CanvasItem, reason: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := r.size.x
	match reason:
		"unstaffed", "workers_off":
			# Un obrero (cabeza y cuerpo) tachado.
			ci.draw_circle(c + Vector2(0, -s * 0.25), s * 0.17, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.06), Vector2(s * 0.44, s * 0.48)), col)
			_slash(ci, r, col)
		"no_road":
			# Dos bordillos y la raya del centro, tachados.
			ci.draw_line(r.position + Vector2(s * 0.2, 0), r.position + Vector2(s * 0.2, s), col, 1.5)
			ci.draw_line(r.position + Vector2(s * 0.8, 0), r.position + Vector2(s * 0.8, s), col, 1.5)
			ci.draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, -s * 0.1), col, 1.0)
			ci.draw_line(c + Vector2(0, s * 0.1), c + Vector2(0, s * 0.35), col, 1.0)
			_slash(ci, r, col)
		"no_vein":
			# Un cristal de mineral tachado.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.45), c + Vector2(s * 0.32, 0), c + Vector2(0, s * 0.45), c + Vector2(-s * 0.32, 0)]), col)
			_slash(ci, r, col)
		"ruined":
			# Una llama.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.5), c + Vector2(s * 0.18, -s * 0.12), c + Vector2(s * 0.36, -s * 0.22), c + Vector2(s * 0.34, s * 0.25), c + Vector2(0, s * 0.45), c + Vector2(-s * 0.34, s * 0.25), c + Vector2(-s * 0.3, -s * 0.05), c + Vector2(-s * 0.12, -s * 0.18)]), col)
		"full":
			# Una caja llena con la flecha de recoger.
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.05), Vector2(s * 0.8, s * 0.48)), col)
			ci.draw_line(c + Vector2(0, -s * 0.15), c + Vector2(0, -s * 0.5), col, 1.5)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.2, -s * 0.32), c + Vector2(0, -s * 0.55)]), col)
		_:
			# Parado sin mas: el signo de pausa.
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.35), Vector2(s * 0.2, s * 0.7)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.35), Vector2(s * 0.2, s * 0.7)), col)

static func _slash(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_line(r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), Color(0.05, 0.05, 0.05, 0.9), 3.0)
	ci.draw_line(r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), col.lightened(0.3), 1.5)
