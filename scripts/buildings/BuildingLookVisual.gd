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
## - Obra: el modelo se oculta y en su sitio sale la fase, con el estilo de su
##   tipo y la disposicion de su semilla (BuildingLook.seed_of; la misma que
##   usa la vista 2D), via SiteMesh.construction_phase: todo lo quieto en UNA
##   malla con los materiales de ToyPalette (la maqueta). Grua, gancho,
##   banderin y chispas/polvo los anima un shader (SiteFx), sin crear nodos.
## - Mejora: el modelo sigue a la vista, rodeado de andamio.
## - Ruina: el modelo se hunde y se ladea (encima ya lleva el hollin de
##   BuildingHealth), rodeado de escombros y con humo negro animado.
## - Trabajando: humo, serrin o luz animados por shader (BuildingFx).
## - Dano leve o grave (en pie, quieto o trabajando): grietas, tejas caidas,
##   tabla suelta; en grave ademas chapa colgando, viga partida, humo negro y
##   chispas (SiteMesh.damage_overlay, una malla cacheada por etapa) y el
##   modelo algo ladeado (GameConfig.damage_tilt / damage_sink_ratio).
## Todo lo que cuelga de aqui esta en el grupo "building_fx": ni el hollin de
## BuildingHealth ni la medida de la cima (BuildingStatusBadge) lo cuentan.

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")
const Site := preload("res://scripts/buildings/SiteMesh.gd")

var _building: Node3D = null
var _data: BuildingData = null
var _top := 2.0
var _cell := 2.0
var _model: Node3D = null
var _look := -1
var _phase := -1
var _seed := 0
var _site: Node3D = null
var _ruin: Node3D = null
var _active: Node3D = null
## Etapa de dano a la vista (BuildingLook.DAMAGE_*) y su malla, o null.
var _damage := 0
var _damage_node: Node3D = null

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

func get_damage() -> int:
	return _damage

func get_damage_node() -> Node3D:
	return _damage_node

## Aplica un veredicto de BuildingLook.derive(). Si no cambia, no toca nada.
func apply(verdict: Dictionary) -> void:
	var look := int(verdict.get("look", LookRule.Look.IDLE))
	var phase := int(verdict.get("phase", 0))
	# El dano leve o grave solo se ve en pie: la obra, el andamio y la ruina lo tapan.
	var damage := int(verdict.get("damage", 0))
	if look != LookRule.Look.IDLE and look != LookRule.Look.ACTIVE:
		damage = LookRule.DAMAGE_NONE
	# La obra de esta instancia: estilo de su tipo + semilla de su celda. Si la
	# semilla cambia (se registro en la rejilla, o se movio), se rehace.
	var seed_val := LookRule.seed_of(_building, _data) if look == LookRule.Look.CONSTRUCTION else 0
	if look == _look and phase == _phase and seed_val == _seed and damage == _damage:
		return
	_look = look
	_phase = phase
	_seed = seed_val
	_clear_site()
	if look != LookRule.Look.RUIN:
		_leave_ruin()
	_set_damage(damage)
	if _model != null:
		_model.visible = look != LookRule.Look.CONSTRUCTION
	match look:
		LookRule.Look.CONSTRUCTION:
			_site = Site.construction_phase(_data.grid_size, phase, _cell, _data.id, seed_val)
		LookRule.Look.UPGRADE:
			_site = Site.scaffold(_data.grid_size, _cell, _top + 0.3)
		LookRule.Look.RUIN:
			_enter_ruin()
	if _site != null:
		add_child(_site)
	if look == LookRule.Look.ACTIVE:
		_ensure_active()
	if _active != null:
		_active.visible = look == LookRule.Look.ACTIVE
	# La parcela acompana: a medio preparar en obra, volcada y quemada en ruina.
	var lot := _building.get_node_or_null("Lot") if _building != null else null
	if lot != null and lot.has_method("set_look"):
		lot.set_look(look, phase)

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
		_ruin = Site.ruin_overlay(_data.grid_size, _cell, hash(_building.name))
		var smoke := Fx.quad_3d("smoke", 1.4 + 0.3 * LookRule.footprint_class(_data.grid_size), "ruin")
		smoke.position = Vector3(0.0, _top * (1.0 - GameConfig.ruin_sink_ratio) + 0.6, 0.0)
		_ruin.add_child(smoke)
		add_child(_ruin)
	_pose_model(GameConfig.ruin_sink_ratio, GameConfig.ruin_tilt, 1.0)

func _leave_ruin() -> void:
	if _ruin == null:
		# No estaba en ruinas: la postura (si la hay) es la del dano, no se toca.
		return
	# Sin script ni senales: se libera en el acto, sin esperar al fin de frame.
	remove_child(_ruin)
	_ruin.free()
	_ruin = null
	_pose_model(0.0, 0.0, 1.0)

## Hunde el modelo `sink` (fraccion de su altura) y lo ladea `tilt` radianes
## hacia `side` (1 o -1). Siempre desde la postura original, que se guarda en
## el propio modelo ("look_base_pos/rot") para devolverla; 0 y 0 la devuelve.
## Mientras la lleva, apply_level_visual no le mueve la posicion.
func _pose_model(sink: float, tilt: float, side: float) -> void:
	if _model == null:
		return
	if _model.has_meta("look_base_pos"):
		_model.position = _model.get_meta("look_base_pos")
		_model.rotation = _model.get_meta("look_base_rot")
		_model.remove_meta("look_base_pos")
		_model.remove_meta("look_base_rot")
	if is_zero_approx(sink) and is_zero_approx(tilt):
		return
	_model.set_meta("look_base_pos", _model.position)
	_model.set_meta("look_base_rot", _model.rotation)
	_model.position.y -= _top * sink
	_model.rotation.z += tilt * side
	_model.rotation.x -= tilt * 0.5

# ── Dano leve y grave ────────────────────────────────────────────────

## Pone la etapa de dano `stage` (0 quita la que hubiera): la malla de su etapa
## (cacheada en SiteMesh por etapa, variante y caja del modelo) y el ladeo.
## Solo se llama cuando cambia el aspecto, nunca por frame.
func _set_damage(stage: int) -> void:
	if stage == _damage and (stage == LookRule.DAMAGE_NONE or _damage_node != null):
		return
	if _damage_node != null:
		remove_child(_damage_node)
		_damage_node.free()
		_damage_node = null
	var had := _damage
	_damage = stage
	if stage == LookRule.DAMAGE_NONE:
		if had != LookRule.DAMAGE_NONE:
			_pose_model(0.0, 0.0, 1.0)
		return
	# La caja se mide con el modelo derecho (sin el ladeo de la etapa anterior).
	_pose_model(0.0, 0.0, 1.0)
	var variant := LookRule.seed_of(_building, _data) % Site.DAMAGE_VARIANTS
	_damage_node = Site.damage_overlay(stage, _model_box(), variant)
	if _damage_node != null:
		add_child(_damage_node)
	var i := clampi(stage - 1, 0, 1)
	var side := 1.0 if variant % 2 == 0 else -1.0
	_pose_model(float(_pick(GameConfig.damage_sink_ratio, i)), float(_pick(GameConfig.damage_tilt, i)), side)

static func _pick(values: Array, i: int) -> float:
	if values.is_empty():
		return 0.0
	return float(values[clampi(i, 0, values.size() - 1)])

## La caja del modelo en el marco del edificio (todas sus mallas). Sin modelo,
## la huella con la altura medida.
func _model_box() -> AABB:
	var box := AABB()
	var found := false
	if _model != null:
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var mesh_i := mi as MeshInstance3D
			if mesh_i.mesh == null:
				continue
			var b: AABB = _to_building(mesh_i) * mesh_i.get_aabb()
			box = b if not found else box.merge(b)
			found = true
	if not found:
		var d := Vector2(_data.grid_size) * _cell * 0.8 if _data else Vector2(1.6, 1.6)
		box = AABB(Vector3(-d.x * 0.5, 0.0, -d.y * 0.5), Vector3(d.x, _top, d.y))
	return box

## La transformacion de `node` en el marco del edificio (sin depender del arbol).
func _to_building(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _building:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

## Humo / serrin desde la cima, o un farol encendido en el tejado. Se crea la
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
		# Un farol pequeno posado en el tejado (no una bola de luz encima).
		var lamp_size := 0.6 + 0.1 * n
		var glow := Fx.quad_3d("glow", lamp_size)
		glow.position = Vector3(0.0, _top + lamp_size * 0.3, 0.0)
		_active.add_child(glow)
	else:
		var size := 2.0 + 0.5 * n
		var anchor = _fx_anchor()
		if anchor != null:
			# El modelo marca de donde sale (la sierra del Aserradero): mas
			# pequeno, y pegado a la boca en vez de flotar sobre el tejado.
			size *= 0.6
		var col := Fx.quad_3d(kind, size)
		col.position = (anchor + Vector3(0.0, size * 0.3, 0.0)) if anchor != null else Vector3(0.0, _top + size * 0.35, 0.0)
		_active.add_child(col)
	add_child(_active)

## Un Marker3D "FxAnchor" dentro del modelo, en el espacio del edificio, o null.
func _fx_anchor() -> Variant:
	if _model == null:
		return null
	var marker := _model.find_child("FxAnchor", true, false) as Node3D
	if marker == null:
		return null
	var xf := Transform3D.IDENTITY
	var n: Node = marker
	while n != null and n != _building:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin

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
