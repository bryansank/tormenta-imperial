extends Node2D
## Un yacimiento en la vista 2D: bosque, veta de oro, hierro o pozo de petroleo,
## dibujado en "maqueta" a su tamano real en celdas (BuildingArt2D.draw_deposit,
## el mismo vocabulario que la 3D de DepositMesh). Lleva un Label oculto con el
## nombre, que es de donde BuildingInfoPanel lo lee al hacer clic (igual que el
## Label3D del yacimiento 3D). Los metadatos (deposit_id, cell, deposit_size,
## uses_remaining...) los pone MapGenerator; la etapa de agotamiento
## (`stage`, 4 entero .. 1 casi gastado) la pone MapGenerator2D al minarlo.
##
## Rendimiento: el dibujo se hornea una vez por yacimiento y etapa (ArtCache2D:
## un rectangulo con textura). Nada por fotograma salvo mientras esta
## seleccionado (el pulso del marco); el atenuado de "bloqueado" llega por
## senal (resource_unlocked, carga y partida nueva).

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
const ArtCache := preload("res://scripts/view2d/ArtCache2D.gd")
const DepositMesh := preload("res://scripts/map/DepositMesh.gd")

var deposit_id := ""
var dep_size := Vector2i(2, 2)
var seed_val := 0
## Etapa de agotamiento (DepositMesh.stage_of): 4 entero, 1 el ultimo uso.
var stage := 4
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

func _ready() -> void:
	set_process(false)
	EventBus.resource_unlocked.connect(_on_unlock_changed)
	EventBus.game_load_completed.connect(_refresh_locked)
	EventBus.game_new_started.connect(_refresh_locked)
	_refresh_locked()

func _on_unlock_changed(_resource_name: String) -> void:
	_refresh_locked()

func _refresh_locked() -> void:
	var locked := not _resource_unlocked()
	if locked == _locked:
		return
	_locked = locked
	modulate = Color(0.75, 0.75, 0.75, 0.85) if locked else Color.WHITE

func set_selected(value: bool) -> void:
	_selected = value
	set_process(value)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _resource_unlocked() -> bool:
	match deposit_id:
		"iron_deposit": return ResourceManager.is_unlocked(ResourceManager.Type.STEEL)
		"oil_well": return ResourceManager.is_unlocked(ResourceManager.Type.OIL)
	return true

func _draw() -> void:
	var size := Vector2(dep_size) * View2D.cell_px()
	var id := deposit_id
	# La variante (no la semilla entera): yacimientos iguales comparten horneado.
	var sv := DepositMesh.variant_of(seed_val)
	var st := stage
	var key := "dep|%s|%d|%d|%d|%d" % [id, dep_size.x, dep_size.y, sv, st]
	var tex := ArtCache.fetch(key, size, func(ci: CanvasItem) -> void: Art.draw_deposit(ci, id, size, sv, st), self)
	if tex != null:
		draw_texture_rect(tex, ArtCache.rect_for(size), false)
	else:
		Art.draw_deposit(self, id, size, sv, st)
	if _selected:
		Art.draw_selection(self, size, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
