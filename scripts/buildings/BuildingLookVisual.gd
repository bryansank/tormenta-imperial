extends Node3D
## El aspecto de un edificio 3D en el mapa: fase de obra, andamio de mejora,
## ruina y humo/luz de "trabajando" (docs/03, "Aspecto en el mapa").
##
## Cuelga de cada edificio (hijo "LookVisual", lo pone BuildingPlacer) y no
## escucha nada ni tiene reloj propio: BuildingPlacer le llama sync() cuando
## llega una senal de obra/ruina/reparacion y, para el paso de fase y el
## encendido de la actividad, con UN solo reloj para todo el mapa
## (GameConfig.building_look_sync_interval). La regla vive en BuildingLook,
## compartida con la vista 2D.
##
## - Obra: el modelo se oculta y en su sitio sale la fase de la huella
##   (DieselpunkBuildingFactory.create_construction_phase).
## - Mejora: el modelo sigue a la vista, rodeado de andamio.
## - Ruina: el modelo se hunde y se ladea (encima ya lleva el hollin de
##   BuildingHealth), rodeado de escombros y con humo negro animado.
## - Trabajando: humo, serrin o luz animados por shader (BuildingFx).
## Todo lo que cuelga de aqui esta en el grupo "building_fx": ni el hollin de
## BuildingHealth ni la medida de la cima (BuildingStatusBadge) lo cuentan.

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")

var _building: Node3D = null
var _data: BuildingData = null
var _top := 2.0
var _cell := 2.0
var _model: Node3D = null
var _look := -1
var _phase := -1
var _site: Node3D = null
var _ruin: Node3D = null
var _active: Node3D = null

## `top_y`: la cima medida del modelo (BuildingStatusBadge.measure_top).
func setup(building: Node3D, data: BuildingData, top_y: float, cell_size: float = -1.0) -> void:
	name = "LookVisual"
	add_to_group("building_fx")
	_building = building
	_data = data
	_top = maxf(0.5, top_y)
	_cell = cell_size if cell_size > 0.0 else GridManager.cell_size
	_model = _find_model()

## Relee los hechos del edificio y aplica el aspecto que toca.
func sync() -> void:
	if _building == null or _data == null or not is_instance_valid(_building):
		return
	apply(LookRule.derive(LookRule.facts_of(_building, _data)))

func get_look() -> int:
	return _look

func get_phase() -> int:
	return _phase

## Aplica un veredicto de BuildingLook.derive(). Si no cambia, no toca nada.
func apply(verdict: Dictionary) -> void:
	var look := int(verdict.get("look", LookRule.Look.IDLE))
	var phase := int(verdict.get("phase", 0))
	if look == _look and phase == _phase:
		return
	_look = look
	_phase = phase
	_clear_site()
	if look != LookRule.Look.RUIN:
		_leave_ruin()
	if _model != null:
		_model.visible = look != LookRule.Look.CONSTRUCTION
	match look:
		LookRule.Look.CONSTRUCTION:
			_site = DieselpunkBuildingFactory.create_construction_phase(_data.grid_size, phase, _cell)
		LookRule.Look.UPGRADE:
			_site = DieselpunkBuildingFactory.create_scaffold(_data.grid_size, _cell, _top + 0.3)
		LookRule.Look.RUIN:
			_enter_ruin()
	if _site != null:
		add_child(_site)
	if look == LookRule.Look.ACTIVE:
		_ensure_active()
	if _active != null:
		_active.visible = look == LookRule.Look.ACTIVE

# ── Piezas ────────────────────────────────────────────────────────────

func get_site() -> Node3D:
	return _site

func get_ruin() -> Node3D:
	return _ruin

func get_active() -> Node3D:
	return _active

func get_model() -> Node3D:
	return _model

func _clear_site() -> void:
	if _site != null:
		# Sin script ni senales: se libera en el acto, sin esperar al fin de frame.
		remove_child(_site)
		_site.free()
		_site = null

## La ruina: escombros por huella + humo negro, y el modelo hundido y ladeado.
## La posicion original se guarda en el propio modelo para devolverla al reparar.
func _enter_ruin() -> void:
	if _ruin == null:
		_ruin = DieselpunkBuildingFactory.create_ruin_overlay(_data.grid_size, _cell, hash(_building.name))
		var smoke := Fx.quad_3d("smoke", 1.4 + 0.3 * LookRule.footprint_class(_data.grid_size), "ruin")
		smoke.position = Vector3(0.0, _top * (1.0 - GameConfig.ruin_sink_ratio) + 0.6, 0.0)
		_ruin.add_child(smoke)
		add_child(_ruin)
	if _model != null and not _model.has_meta("look_base_pos"):
		_model.set_meta("look_base_pos", _model.position)
		_model.set_meta("look_base_rot", _model.rotation)
		_model.position.y -= _top * GameConfig.ruin_sink_ratio
		_model.rotation.z += GameConfig.ruin_tilt
		_model.rotation.x -= GameConfig.ruin_tilt * 0.5

func _leave_ruin() -> void:
	if _ruin != null:
		# Sin script ni senales: se libera en el acto, sin esperar al fin de frame.
		remove_child(_ruin)
		_ruin.free()
		_ruin = null
	if _model != null and _model.has_meta("look_base_pos"):
		_model.position = _model.get_meta("look_base_pos")
		_model.rotation = _model.get_meta("look_base_rot")
		_model.remove_meta("look_base_pos")
		_model.remove_meta("look_base_rot")

## Humo / serrin desde la cima, o una luz que parpadea en el tejado. Se crea la
## primera vez que el edificio trabaja; luego solo se enciende y apaga.
func _ensure_active() -> void:
	if _active != null:
		return
	var kind := LookRule.fx_kind(_data.id)
	if kind == "":
		return
	_active = Node3D.new()
	_active.name = "ActiveFx"
	var n := LookRule.footprint_class(_data.grid_size)
	if kind == "glow":
		var glow := Fx.quad_3d("glow", 1.4 + 0.3 * n)
		glow.position = Vector3(0.0, _top + 0.15, 0.0)
		_active.add_child(glow)
	else:
		var size := 2.0 + 0.5 * n
		var col := Fx.quad_3d(kind, size)
		col.position = Vector3(0.0, _top + size * 0.35, 0.0)
		_active.add_child(col)
	add_child(_active)

func _find_model() -> Node3D:
	if _building == null:
		return null
	for child in _building.get_children():
		if child == self or not (child is Node3D):
			continue
		if child is Label3D or child is Sprite3D or child.is_in_group("building_fx"):
			continue
		if child.name in ["ConstructionBar", "LevelPlate"]:
			continue
		return child
	return null
