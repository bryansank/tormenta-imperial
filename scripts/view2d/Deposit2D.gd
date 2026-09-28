extends Node2D
## Un yacimiento en la vista 2D: bosque, veta de oro, hierro o pozo de petroleo,
## dibujado a su tamano real en celdas (BuildingArt2D.draw_deposit). Lleva un
## Label oculto con el nombre, que es de donde BuildingInfoPanel lo lee al hacer
## clic (igual que el Label3D del yacimiento 3D). Los metadatos (deposit_id,
## cell, deposit_size, uses_remaining...) los pone MapGenerator.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

var deposit_id := ""
var dep_size := Vector2i(2, 2)
var seed_val := 0
var _selected := false
## Se atenua mientras su recurso no esta desbloqueado (como la vista 3D, que lo
## ensena pero no deja usarlo).
var _locked := false

func setup(id: String, display_name: String, size_cells: Vector2i) -> void:
	deposit_id = id
	dep_size = size_cells
	var label := Label.new()
	label.name = "NameLabel"
	label.text = display_name
	label.visible = false
	add_child(label)

func set_selected(value: bool) -> void:
	_selected = value
	queue_redraw()

func _process(_delta: float) -> void:
	var locked := not _resource_unlocked()
	if locked != _locked:
		_locked = locked
		modulate = Color(0.75, 0.75, 0.75, 0.85) if locked else Color.WHITE
	if _selected:
		queue_redraw()

func _resource_unlocked() -> bool:
	match deposit_id:
		"iron_deposit": return ResourceManager.is_unlocked(ResourceManager.Type.STEEL)
		"oil_well": return ResourceManager.is_unlocked(ResourceManager.Type.OIL)
	return true

func _draw() -> void:
	var size := Vector2(dep_size) * View2D.cell_px()
	Art.draw_deposit(self, deposit_id, size, seed_val)
	if _selected:
		Art.draw_selection(self, size, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
