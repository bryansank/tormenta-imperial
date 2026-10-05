extends Node2D
## Un edificio en la vista 2D. Es la entidad que ven los servicios: la misma que
## en 3D era un Node3D, con los mismos metadatos (level, rotation_steps, health,
## staffed, under_construction, custom_name) y los mismos hijos con nombre
## ("NameLabel", "StatusBadge", "ConstructionLabel") que ellos buscan.
##
## No escucha senales para pintarse: cada frame compara una firma barata de su
## estado (obra, nivel, vida, calzadas vecinas, seleccion) y solo repinta si ha
## cambiado. Asi una partida cargada, una tormenta o una reparacion se ven sin
## que ningun servicio sepa que existe la vista 2D.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const StatusBadge2D := preload("res://scripts/view2d/StatusBadge2D.gd")
const ColonyFlag2D := preload("res://scripts/view2d/ColonyFlag2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
## Obra por fases, ruina y actividad: la misma regla que en 3D (docs/03).
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Fx := preload("res://scripts/buildings/BuildingFx.gd")
## La parcela: la misma plantilla que la 3D (docs/03, "Parcela y atrezo").
const LotPlan := preload("res://scripts/buildings/LotPlan.gd")
const SiteFx := preload("res://scripts/buildings/SiteFx.gd")

var data: BuildingData = null
## Fantasma de colocacion: no esta en la rejilla, se pinta translucido.
var ghost := false
var ghost_valid := true

var _selected := false
var _signature: Array = []
var _pulse := 0.0
var _name_label: Label = null
## Veredicto de LookRule.derive() del ultimo repintado.
var _look: Dictionary = {"look": LookRule.Look.IDLE, "phase": 0}
## Humo/luz de "trabajando" (creado la primera vez) y humo negro de la ruina.
var _active_fx: Node2D = null
var _ruin_fx: Node2D = null
## Plan de la parcela (LotPlan.plan) y lo que lo decidio: [origen, lados de
## calzada locales, estado, fase]. Se rehace solo si eso cambia; las calzadas
## vecinas se releen cuando una senal de la rejilla avisa (_lot_dirty).
var _lot_plan: Dictionary = {}
var _lot_key: Array = []
var _lot_dirty := true
var _lot_origin := Vector2i(-99999, -99999)
var _lot_sides := 0
## Lo que se mueve en una obra (pluma y carro de la grua, banderin, chispas o
## polvo), rehecho al cambiar de fase o de semilla; y esa semilla (la misma que
## en 3D: BuildingLook.seed_of).
var _site_fx: Node2D = null
var _site_key := ""
var _site_seed := 0

func setup(building_data: BuildingData, is_ghost: bool = false) -> void:
	data = building_data
	ghost = is_ghost
	name = data.id
	if ghost:
		z_index = 20
		return
	z_index = 2
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = _label_text()
	_name_label.visible = false
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.z_index = 40
	add_child(_name_label)
	var badge: Node2D = StatusBadge2D.new()
	add_child(badge)
	badge.setup(self, data)
	if LotPlan.has_lot(data.id):
		for sig in [EventBus.building_placed, EventBus.building_demolished, EventBus.building_moved,
				EventBus.game_load_completed]:
			(sig as Signal).connect(_on_map_changed)

func _on_map_changed(_a = null, _b = null) -> void:
	_lot_dirty = true

## Patio de la parcela en px (lo que el dibujo del edificio deja libre por lado).
func yard_px() -> float:
	return LotPlan.yard_of(data.id) * View2D.cell_px() if data else 0.0

func get_lot_plan() -> Dictionary:
	return _lot_plan

## Rehace el plan de la parcela si cambio su celda, sus calzadas, la obra o la ruina.
func _update_lot() -> void:
	if ghost or data == null or not LotPlan.has_lot(data.id):
		return
	if _lot_dirty:
		_lot_dirty = false
		var info := GridManager.get_building_info(self)
		var steps := int(get_meta("rotation_steps", 0))
		if not info.is_empty():
			_lot_origin = info["origin_cell"]
			var world := LotPlan.road_sides_of(_lot_origin, (info["data"] as BuildingData).grid_size)
			_lot_sides = LotPlan.local_sides(world, steps, true)
	var state := LotPlan.state_for(int(_look["look"]))
	var phase := int(_look["phase"]) if state == "construction" else 0
	var key := [_lot_origin, _lot_sides, state, phase]
	if key == _lot_key:
		return
	_lot_key = key
	_lot_plan = LotPlan.plan(data.id, data.grid_size, LotPlan.seed_for(_lot_origin, data.id), _lot_sides, state, phase)
	queue_redraw()
	# La bandera de la colonia (rango del gobernador) sobre el Nucleo.
	if data.is_core:
		var flag: Node2D = ColonyFlag2D.new()
		add_child(flag)
		flag.setup(base_size_px())

func set_selected(value: bool) -> void:
	_selected = value
	if _name_label:
		_name_label.visible = value
	queue_redraw()

func is_selected() -> bool:
	return _selected

## Huella sin girar, en pixeles.
func base_size_px() -> Vector2:
	return Vector2(data.grid_size) * View2D.cell_px() if data else Vector2.ONE * View2D.cell_px()

## Huella con el giro aplicado (la que ocupa en la rejilla), en pixeles.
func footprint_px() -> Vector2:
	var steps: int = get_meta("rotation_steps", 0)
	return Vector2(Rules.rotated_size(data, steps)) * View2D.cell_px()

## ProductionManager llama aqui en vez de montar su Label3D: la obra la pinta el
## propio edificio y el texto de progreso lo actualiza ProductionManager.
func apply_construction_visual() -> void:
	if get_node_or_null("ConstructionLabel") == null:
		var label := Label.new()
		label.name = "ConstructionLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		label.z_index = 41
		add_child(label)
	queue_redraw()

func _process(delta: float) -> void:
	if data == null:
		return
	if _selected:
		_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		queue_redraw()
	_layout_labels()
	if ghost:
		return
	var sig := _current_signature()
	_update_lot()
	if sig != _signature:
		_signature = sig
		if _name_label:
			_name_label.text = _label_text()
		_apply_fx()
		queue_redraw()

func _current_signature() -> Array:
	var constructing := has_meta("under_construction")
	var progress := 0
	if constructing:
		progress = int(ProductionManager.get_construction_progress(self) * 20.0)
	var mask := 0
	if data.id == "road":
		var info := GridManager.get_building_info(self)
		if not info.is_empty():
			mask = Rules.road_neighbor_mask(info["origin_cell"])
	_look = LookRule.derive(LookRule.facts_of(self, data))
	_site_seed = LookRule.seed_of(self, data) if int(_look["look"]) == LookRule.Look.CONSTRUCTION else 0
	return [constructing, progress, int(get_meta("level", 1)), int(get_meta("health", data.max_health)),
		BuildingHealth.is_ruined(self), mask, int(get_meta("rotation_steps", 0)), String(get_meta("custom_name", "")),
		Tr.get_locale(), int(_look["look"]), int(_look["phase"]), _site_seed]

func get_look() -> Dictionary:
	return _look

func get_active_fx() -> Node2D:
	return _active_fx

func get_ruin_fx() -> Node2D:
	return _ruin_fx

func get_site_fx() -> Node2D:
	return _site_fx

func get_site_seed() -> int:
	return _site_seed

## Las piezas animadas de la obra: se crean al entrar en una fase (o cambiar
## de semilla) y se van al acabar. Las mueve un shader (SiteFx/BuildingFx):
## ni este nodo ni ellas tienen _process por la animacion.
func _apply_site_fx() -> void:
	var look := int(_look["look"])
	var key := ""
	if look == LookRule.Look.CONSTRUCTION:
		key = "%d:%d:%d" % [int(_look["phase"]), _site_seed, int(get_meta("rotation_steps", 0))]
	if key == _site_key:
		return
	_site_key = key
	if _site_fx != null:
		remove_child(_site_fx)
		_site_fx.queue_free()
		_site_fx = null
	if key == "":
		return
	_site_fx = _make_site_fx(int(_look["phase"]))
	add_child(_site_fx)

func _make_site_fx(phase: int) -> Node2D:
	var holder := Node2D.new()
	holder.name = "SiteFx"
	holder.z_index = 5
	holder.rotation = float(int(get_meta("rotation_steps", 0))) * PI * 0.5
	var n := LookRule.footprint_class(data.grid_size)
	var style := LookRule.site_style(data.id)
	var layout := LookRule.site_layout(_site_seed, style, n)
	# La obra ocupa el rectangulo del edificio; el patio es la parcela a medio preparar.
	var site_size := base_size_px() - Vector2.ONE * yard_px() * 2.0
	var anchors := Art.site_anchors(site_size, phase, n, style, layout)
	var crane: Dictionary = anchors["crane"]
	if not crane.is_empty():
		var jib := float(crane["jib"])
		var color: Color = style["crane"]
		var outline := Line2D.new()
		outline.name = "CraneJibOutline"
		outline.points = PackedVector2Array([Vector2(-jib * 0.22, 0), Vector2(jib, 0)])
		outline.width = 4.5
		outline.default_color = Art.OUTLINE
		var arm := Line2D.new()
		arm.name = "CraneJib"
		arm.points = outline.points
		arm.width = 2.6
		arm.default_color = color
		var weight := Polygon2D.new()
		weight.name = "CraneWeight"
		weight.polygon = PackedVector2Array([Vector2(-jib * 0.24, -3), Vector2(-jib * 0.12, -3), Vector2(-jib * 0.12, 3), Vector2(-jib * 0.24, 3)])
		weight.color = Art.CONCRETE_DARK
		var trolley := Polygon2D.new()
		trolley.name = "CraneHook"
		var tx := jib * 0.5
		trolley.polygon = PackedVector2Array([Vector2(tx - 2.5, -2.5), Vector2(tx + 2.5, -2.5), Vector2(tx + 2.5, 2.5), Vector2(tx - 2.5, 2.5)])
		trolley.color = Art.IRON
		for part in [outline, arm, weight]:
			part.material = SiteFx.crane_material_2d()
		trolley.material = SiteFx.crane_material_2d(jib * 0.4)
		for part in [outline, arm, weight, trolley]:
			part.position = crane["mast"]
			part.rotation = float(crane["angle"])
			holder.add_child(part)
	var flag := Polygon2D.new()
	flag.name = "SiteFlag"
	flag.polygon = PackedVector2Array([Vector2(0, -3), Vector2(3.3, -2.4), Vector2(6.6, -1.4), Vector2(10, 0),
		Vector2(6.6, 1.4), Vector2(3.3, 2.4), Vector2(0, 3)])
	flag.color = style["flag"]
	flag.material = SiteFx.flag_material_2d()
	flag.position = anchors["flag"]
	holder.add_child(flag)
	var kind := String(anchors["fx_kind"])
	if kind != "":
		var fx := Fx.sprite_2d(kind, minf(site_size.x, site_size.y) * 0.45, "site" if kind == "dust" else "")
		fx.position = anchors["fx"]
		holder.add_child(fx)
	return holder

## Enciende o apaga los efectos animados segun el aspecto. Los sprites los
## anima un shader (BuildingFx): aqui solo se crean una vez y se muestran.
func _apply_fx() -> void:
	var look := int(_look["look"])
	if look == LookRule.Look.ACTIVE and _active_fx == null:
		_active_fx = _make_active_fx()
	if _active_fx:
		_active_fx.visible = look == LookRule.Look.ACTIVE
		_place_fx(_active_fx)
	if look == LookRule.Look.RUIN and _ruin_fx == null:
		_ruin_fx = Node2D.new()
		_ruin_fx.name = "RuinFx"
		_ruin_fx.z_index = 6
		var smoke := Fx.sprite_2d("smoke", minf(footprint_px().x, footprint_px().y) * 0.7, "ruin")
		smoke.position = Vector2(0, -footprint_px().y * 0.2)
		_ruin_fx.add_child(smoke)
		add_child(_ruin_fx)
	if _ruin_fx:
		_ruin_fx.visible = look == LookRule.Look.RUIN
	_apply_site_fx()

func _make_active_fx() -> Node2D:
	var kind := LookRule.fx_kind(data.id)
	if kind == "":
		return null
	var holder := Node2D.new()
	holder.name = "ActiveFx"
	holder.z_index = 6
	var size := minf(base_size_px().x, base_size_px().y)
	for anchor in Art.fx_anchors(data.id):
		var sprite := Fx.sprite_2d(kind, size * (0.6 if kind == "glow" else 0.85))
		sprite.set_meta("anchor", anchor)
		holder.add_child(sprite)
	add_child(holder)
	return holder

## Cada sprite en su chimenea, con el giro del edificio aplicado. El humo sube
## un poco por encima de la boca para que salga de ella y no la tape.
func _place_fx(holder: Node2D) -> void:
	# Las bocas estan en el dibujo del edificio, que deja libre el patio.
	var size := base_size_px() - Vector2.ONE * yard_px() * 2.0
	var angle := float(int(get_meta("rotation_steps", 0))) * PI * 0.5
	for sprite in holder.get_children():
		var anchor: Vector2 = sprite.get_meta("anchor", Vector2(0.5, 0.5))
		var local := (anchor - Vector2(0.5, 0.5)) * size
		var rise := 0.04 if String(sprite.name).ends_with("glow") else 0.28
		sprite.position = local.rotated(angle) + Vector2(0, -size.y * rise)

## El rotulo: el nombre que le puso el jugador o, si no tiene, el del edificio en
## el idioma actual. Nunca el campo crudo del .tres, que esta en espanol.
func _label_text() -> String:
	var custom := String(get_meta("custom_name", ""))
	return custom if custom != "" else data.get_display_name()

## Los rotulos no giran ni crecen con el zoom: se contraescalan para leerse igual
## a cualquier distancia.
func _layout_labels() -> void:
	var inv := label_scale(self)
	var fp := footprint_px()
	var below := fp.y * 0.5 + 2.0
	var cl: Label = get_node_or_null("ConstructionLabel")
	if cl:
		cl.scale = Vector2(inv, inv)
		cl.reset_size()
		cl.position = Vector2(-cl.size.x * 0.5 * inv, below)
		below += cl.size.y * inv
	if _name_label and _name_label.visible:
		_name_label.scale = Vector2(inv, inv)
		_name_label.reset_size()
		_name_label.position = Vector2(-_name_label.size.x * 0.5 * inv, below)

## Escala de los rotulos y badges: tamano de pantalla constante de cerca, y
## algo mas pequenos al alejarse para no tapar el mapa.
static func label_scale(ci: CanvasItem) -> float:
	var cam := ci.get_viewport().get_camera_2d() if ci.is_inside_tree() else null
	if cam == null:
		return 1.0
	var boost: float = cam.screen_boost() if cam.has_method("screen_boost") else 1.0
	var z := cam.zoom.x
	return clampf(z / boost / 1.8, 0.6, 1.0) * boost / z

func _draw() -> void:
	if data == null:
		return
	var steps: int = get_meta("rotation_steps", 0)
	var size := base_size_px()
	var mask := 0
	if data.id == "road" and not ghost:
		var info := GridManager.get_building_info(self)
		if not info.is_empty():
			mask = Rules.road_neighbor_mask(info["origin_cell"])
	if ghost:
		var fp := footprint_px()
		var tint := Color(0.2, 0.85, 0.2, 0.28) if ghost_valid else Color(0.9, 0.2, 0.2, 0.34)
		draw_rect(Rect2(-fp * 0.5, fp), tint)
		draw_rect(Rect2(-fp * 0.5, fp), Color(tint, 0.9), false, 2.0)
	# Las calzadas no giran: sus uniones ya dicen hacia donde van.
	var angle := 0.0 if data.id == "road" else steps * PI * 0.5
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	var level: int = get_meta("level", 1)
	var look := int(_look["look"]) if not ghost else LookRule.Look.IDLE
	var n := LookRule.footprint_class(data.grid_size)
	# La parcela: el suelo y el remate debajo, el edificio en su rectangulo (la
	# huella menos el patio) y el atrezo en el patio. Obra, dano y ruina van
	# sobre el edificio, no sobre la parcela, que tiene su propio aspecto.
	var inset := yard_px()
	var inner := size - Vector2.ONE * inset * 2.0
	var has_lot := not ghost and not _lot_plan.is_empty()
	if has_lot:
		Art.draw_lot_ground(self, _lot_plan, size)
	if look == LookRule.Look.CONSTRUCTION:
		# Obra nueva: la fase de la huella EN LUGAR del edificio (que aun no esta).
		Art.draw_construction_phase(self, inner, int(_look["phase"]),
			ProductionManager.get_construction_progress(self), n, data.id, _site_seed)
	else:
		if has_lot:
			Art.draw_lot_shadow(self, Rect2(-inner * 0.5, inner).grow(-Art.INSET))
		Art.draw_building(self, data.id, size, {"road_mask": mask, "level": level, "shadow": not ghost, "inset": inset})
	if has_lot:
		Art.draw_lot_props(self, _lot_plan, size)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ghost:
		return
	var fp2 := footprint_px()
	var fp_inner := fp2 - Vector2.ONE * inset * 2.0
	if look == LookRule.Look.UPGRADE:
		# Mejora: el edificio sigue a la vista, con andamio y rayas encima.
		Art.draw_construction(self, fp_inner, ProductionManager.get_construction_progress(self))
	var ratio := BuildingHealth.get_health_ratio(self)
	var ruined := BuildingHealth.is_ruined(self)
	if ratio < 1.0 or ruined:
		Art.draw_damage(self, fp_inner, ratio, ruined, hash(name), n)
	if _selected:
		Art.draw_selection(self, fp2, _pulse)
