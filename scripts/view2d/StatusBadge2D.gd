extends Node2D
## El indicador Zzz / obrero (A11) en la vista 2D. La regla es la misma que en
## 3D —BuildingStatusBadge.derive(), estatica y pura— y el pictograma del obrero
## es la misma textura; solo cambia como se pinta: aqui es un Node2D en la
## esquina superior del edificio, contraescalado para leerse a cualquier zoom.
##
## Se llama "StatusBadge" y tiene refresh(): PopulationManager lo busca por ese
## nombre al repartir obreros, igual que en 3D. Ademas se relee cada poco por si
## acaso (procesos que empiezan, cargas de partida) sin escuchar senales.

const Badge3D := preload("res://scripts/buildings/BuildingStatusBadge.gd")

const REFRESH_EVERY := 0.5
const ICON_PX := 18.0

var _building: Node2D = null
var _data: BuildingData = null
var _status: int = Badge3D.Status.NONE
var _reason: String = ""
var _timer := 0.0
## Ultimo zoom y huella con que se coloco (solo se recoloca si cambian).
var _placed_zoom := -1.0
var _placed_fp := Vector2.ZERO

func setup(building: Node2D, data: BuildingData) -> void:
	_building = building
	_data = data
	name = "StatusBadge"
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Repartidos: no todos los badges se releen en el mismo fotograma.
	_timer = randf() * REFRESH_EVERY
	refresh()

func get_status() -> int:
	return _status

func get_reason() -> String:
	return _reason

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

func _apply(status: int, reason: String) -> void:
	if status == _status and reason == _reason:
		return
	_status = status
	_reason = reason
	# "idle" es el Nucleo en reposo, su estado normal: como en 3D, no se pinta
	# (un "Zzz parado" fijo en el edificio principal parecia una averia).
	visible = status != Badge3D.Status.NONE and not (status == Badge3D.Status.IDLE and reason == "idle")
	queue_redraw()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_EVERY
		refresh()
	if not visible or _building == null:
		return
	# Solo se recoloca si cambio el zoom o la huella (girar, mover).
	var z := _frame_zoom(self)
	var fp: Vector2 = _building.footprint_px() if _building.has_method("footprint_px") else Vector2(32, 32)
	if is_equal_approx(z, _placed_zoom) and fp == _placed_fp:
		return
	_placed_zoom = z
	_placed_fp = fp
	var inv: float = _building.label_scale(self) if _building.has_method("label_scale") else 1.0
	scale = Vector2(inv, inv)
	# Esquina superior derecha de la huella
	position = Vector2(fp.x * 0.5 - 4.0, -fp.y * 0.5 + 2.0)

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
			var font := ThemeDB.fallback_font
			var col := Badge3D.color_for_reason(_reason)
			var text := "%s %s" % [Tr.t("LBL_STATUS_IDLE"), Badge3D.reason_text(_reason)]
			var fs := 14
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(Vector2(-w - 6, -fs - 1), Vector2(w + 8, fs + 5)), Color(0.05, 0.05, 0.05, 0.7))
			draw_string_outline(font, Vector2(-w - 2, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
			draw_string(font, Vector2(-w - 2, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		Badge3D.Status.WORKING:
			var tex := Badge3D.worker_texture()
			draw_circle(Vector2(-ICON_PX * 0.5, -ICON_PX * 0.5), ICON_PX * 0.62, Color(0.05, 0.05, 0.05, 0.6))
			draw_texture_rect(tex, Rect2(Vector2(-ICON_PX, -ICON_PX), Vector2(ICON_PX, ICON_PX)), false)
