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

const REFRESH_EVERY := 0.25
const ICON_PX := 18.0

var _building: Node2D = null
var _data: BuildingData = null
var _status: int = Badge3D.Status.NONE
var _reason: String = ""
var _timer := 0.0

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

func refresh() -> void:
	if _building == null or _data == null or not is_instance_valid(_building):
		_apply(Badge3D.Status.NONE, "")
		return
	var facts := {
		"can_work": Badge3D.can_work(_data),
		"under_construction": _building.has_meta("under_construction"),
		"ruined": BuildingHealth.is_ruined(_building),
		"connected": bool(_building.get_meta("connected", true)),
		"busy": ProcessManager.is_busy(_building),
		"needs_workers": _data.workers_required > 0,
		"staffed": bool(_building.get_meta("staffed", false)),
		"produces": _data.is_producer(),
	}
	var verdict := Badge3D.derive(facts)
	_apply(int(verdict["status"]), String(verdict["reason"]))

func _apply(status: int, reason: String) -> void:
	if status == _status and reason == _reason:
		return
	_status = status
	_reason = reason
	visible = status != Badge3D.Status.NONE
	queue_redraw()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_EVERY
		refresh()
	if not visible or _building == null:
		return
	var inv: float = _building.label_scale(self) if _building.has_method("label_scale") else 1.0
	scale = Vector2(inv, inv)
	# Esquina superior derecha de la huella
	var fp: Vector2 = _building.footprint_px() if _building.has_method("footprint_px") else Vector2(32, 32)
	position = Vector2(fp.x * 0.5 - 4.0, -fp.y * 0.5 + 2.0)

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
