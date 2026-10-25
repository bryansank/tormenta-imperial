extends Node
const UtilityEffects := preload("res://scripts/buildings/UtilityEffects.gd")
const DefenseLifeEffects := preload("res://scripts/buildings/DefenseLifeEffects.gd")
## Manages passive resource production from buildings and construction timers.
## Buildings with build_time > 0 go through construction before producing.
## Spawns floating text when resources are awarded.

# Construction tracking: Node -> {remaining: float, duration: float}
var _constructing: Dictionary = {}
# Production tracking: Node -> {timer: float, data: BuildingData}
var _producing: Dictionary = {}

# ── Produccion que se recoge (2026-10-04) ──
# Lo que produce un edificio se queda EN el edificio hasta que el jugador lo
# recoge con un toque (collect). Hay un tope por edificio (GameConfig.
# get_stock_cap): lleno, el edificio se para hasta que se recoja. Al recoger,
# lo que no cabe en la bolsa se queda dentro: nada se tira.
const FARM_ID := "farm"
## Node -> {"res": {recurso: int}, "age": float}. `age` son los segundos que
## lleva lo acumulado sin recoger (para echarse a perder, si el modo lo pide).
var _stock: Dictionary = {}
## Node -> id del cultivo de esa Granja. Sin entrada, el de serie.
var _crops: Dictionary = {}
## Aviso de "bolsa llena, queda en el edificio": uno cada tanto, no uno por toque.
var _full_bag_notice_cooldown := 0.0
## Lo que se echo a perder en la ultima progresion offline (para el parte).
var last_offline_spoiled: Dictionary = {}


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	# Areas de los edificios utiles (Molino, Pozo, Taberna, Silo, Deposito,
	# Faro): se recalculan cuando cambia lo que hay en pie, agrupado y diferido.
	EventBus.building_placed.connect(_mark_areas_dirty.unbind(2))
	EventBus.building_moved.connect(_mark_areas_dirty.unbind(2))
	EventBus.building_demolished.connect(_mark_areas_dirty.unbind(2))
	EventBus.construction_completed.connect(_mark_areas_dirty.unbind(1))
	EventBus.building_ruined.connect(_mark_areas_dirty.unbind(1))
	EventBus.building_repaired.connect(_mark_areas_dirty.unbind(1))
	EventBus.game_load_completed.connect(_mark_areas_dirty)
	# Defensa (feat/edificios-defensa-vida): la Chatarreria y el Telegrafo solo
	# cuentan con obreros; mejorar un edificio puede cambiar su huella.
	EventBus.building_upgrade_completed.connect(_mark_areas_dirty.unbind(2))
	EventBus.workers_changed.connect(_mark_areas_dirty.unbind(2))

## Las areas de efecto de los edificios utiles (UtilityEffects): un solo
## recuento al final del frame, aunque se coloquen veinte tramos de carretera.
var _areas_dirty := false

func _mark_areas_dirty() -> void:
	if _areas_dirty:
		return
	_areas_dirty = true
	_refresh_areas.call_deferred()

func _refresh_areas() -> void:
	_areas_dirty = false
	UtilityEffects.refresh()
	DefenseLifeEffects.refresh()

## Pide el recuento de areas (agrupado y diferido). Lo usa EconomyManager
## cuando cambian los obreros: una Central, un Puerto o una Casa de cambio sin
## gente deja de trabajar.
func request_area_refresh() -> void:
	_mark_areas_dirty()

# ── Registration ──

func _on_building_placed(data: Resource, cell: Vector2i) -> void:
	var building_data := data as BuildingData
	var node := GridManager.get_building_at(cell)
	if not node:
		return
	# Ya registrado (en obras, en mejora o produciendo): un building_placed
	# repetido no puede volver a ponerlo en obras. Antes pisaba la entrada, y una
	# mejora en curso se convertia en una obra normal que al terminar no subia de
	# nivel (bug 7: "los edificios pierden su nivel").
	if _constructing.has(node) or _producing.has(node):
		return
	var build_time := GameConfig.get_build_time(building_data.build_time)
	if build_time > 0.0:
		_start_construction(node, building_data, build_time)
	else:
		_register_producer(node, building_data)

## Called by GameManager when loading saved buildings.
##
## `upgrade_to` > 0 dice que lo que estaba en obras era una mejora a ese nivel y
## no la construccion inicial. Sin el, una mejora a medias volvia de la carga
## como obra normal: al terminar no subia de nivel, y la del Cuartel General a
## nivel 3 —la que convoca la Auditoria Final— se perdia sin dejar rastro. Un
## save anterior a la clave llega con 0, que es lo que siempre significo.
func register_building(node: Node, data: BuildingData, construction_remaining := 0.0, upgrade_to: int = 0) -> void:
	if construction_remaining > 0.0:
		var is_upgrade: bool = upgrade_to > 1
		var total_duration := GameConfig.get_upgrade_duration(upgrade_to) if is_upgrade 				else GameConfig.get_build_time(data.build_time)
		var info := {
			"remaining": minf(construction_remaining, total_duration),
			"duration": total_duration,
		}
		if is_upgrade:
			info["is_upgrade"] = true
			info["new_level"] = upgrade_to
		_constructing[node] = info
		node.set_meta("under_construction", true)
		_apply_construction_visual(node)
	else:
		_register_producer(node, data)

## Olvida todo lo que estaba en obras y produciendo. Lo llama GameManager en los
## tres sitios que empiezan partida: los nodos de la escena anterior mueren con
## la recarga, pero este autoload sobrevive y los seguiria teniendo de clave.
## Tira, no liquida: una partida nueva no termina las obras de la vieja.
func reset() -> void:
	_constructing.clear()
	_producing.clear()
	_stock.clear()
	_crops.clear()
	last_offline_spoiled = {}
	_full_bag_notice_cooldown = 0.0
	UtilityEffects.clear()
	DefenseLifeEffects.clear()

func _register_producer(node: Node, data: BuildingData) -> void:
	if data.is_producer():
		_producing[node] = {"timer": 0.0, "data": data}

func unregister(node: Node) -> void:
	_constructing.erase(node)
	_producing.erase(node)
	_stock.erase(node)
	_crops.erase(node)

# ── Construction ──

func is_constructing(node: Node) -> bool:
	return _constructing.has(node)

func get_construction_progress(node: Node) -> float:
	if not _constructing.has(node):
		return 1.0
	var info: Dictionary = _constructing[node]
	if info["duration"] <= 0.0:
		return 1.0
	return clampf(1.0 - (info["remaining"] / info["duration"]), 0.0, 1.0)

func get_construction_remaining(node: Node) -> float:
	if not _constructing.has(node):
		return 0.0
	return _constructing[node]["remaining"]

## El nivel al que sube una mejora en curso, o 0 si lo que hay en obras es una
## construccion (o no hay nada). Es lo que el guardado necesita para no confundir
## una cosa con la otra.
func get_upgrade_target(node: Node) -> int:
	if not _constructing.has(node):
		return 0
	var info: Dictionary = _constructing[node]
	if not bool(info.get("is_upgrade", false)):
		return 0
	return int(info.get("new_level", 0))

func _start_construction(node: Node, data: BuildingData, duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else GameConfig.get_build_time(data.build_time)
	_constructing[node] = {
		"remaining": dur,
		"duration": dur,
	}
	node.set_meta("under_construction", true)
	_apply_construction_visual(node)
	EventBus.construction_started.emit(node)

func _apply_construction_visual(node: Node) -> void:
	# Un edificio que se pinta solo (la vista 2D) pone su propio "ConstructionLabel";
	# el texto de progreso y el borrado al terminar siguen siendo cosa de aqui.
	if node.has_method("apply_construction_visual"):
		node.apply_construction_visual()
		return
	var mesh_inst: Node = node.get_child(0) if node.get_child_count() > 0 else null
	if mesh_inst is MeshInstance3D:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.35
	if not node.get_node_or_null("ConstructionLabel"):
		var data_info := GridManager.get_building_info(node)
		var height: float = 1.5
		if not data_info.is_empty():
			height = (data_info["data"] as BuildingData).mesh_height
		# La cima de la malla de verdad: con un GLB, mesh_height se queda corto y
		# el rotulo salia dentro del edificio.
		if node is Node3D:
			height = maxf(height, BuildingStatusBadge.measure_top(node))
		var label := Label3D.new()
		label.name = "ConstructionLabel"
		label.text = construction_text(node)
		# Del tamano del badge de estado, que se lee desde la camara de siempre
		# (antes 18 px a 0.005: no se leia).
		label.font_size = BuildingStatusBadge.FONT_SIZE
		label.pixel_size = BuildingStatusBadge.PIXEL_SIZE
		label.position.y = height + 1.6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(1.0, 0.8, 0.2, 0.95)
		label.outline_size = 8
		label.outline_modulate = Color(0, 0, 0, 0.85)
		node.add_child(label)
		var bar := _make_progress_bar()
		bar.position.y = height + 0.9
		node.add_child(bar)

## El nivel se ve (2026-09-28; rehecho 2026-10-17): el MISMO modelo crece
## (poco en planta, bastante en alto: LevelTrim.level_scale), se sube a un
## zocalo de piedra con fleje de laton y gana chimeneas de ladrillo (farolas en
## las decoraciones), todo en LevelTrim, horneado una vez por medida. Sin
## placa "II" / "III" flotante: el nivel lo dice el modelo (y la ficha del
## edificio). En 2D lo pinta el propio edificio (BuildingArt2D).
##
## Siempre el MISMO modelo (2026-10-14): el que conoce el aspecto del edificio
## (LookVisual.get_model()), y si no hay aspecto, el primer hijo que no sea
## rotulo, barra, placa ni del grupo "building_fx" (parcela, obra, andamio,
## icono). Crece sin moverse de su sitio en planta.
static func apply_level_visual(node: Node, level: int) -> void:
	if not (node is Node3D):
		return
	var model: Node3D = null
	var decor := false
	var look := node.get_node_or_null("LookVisual")
	if look != null and look.has_method("get_model"):
		model = look.get_model() as Node3D
		if look.has_method("get_data") and look.get_data() != null:
			decor = (look.get_data() as BuildingData).is_decoration
	if model == null:
		for child in node.get_children():
			if child is Node3D and not (child is Label3D) and not (child is Sprite3D) \
					and not child.is_in_group("building_fx") \
					and child.name != "ConstructionBar" and child.name != "LevelPlate" \
					and child.name != "LookVisual" and child.name != "ColonyFlag":
				model = child
				break
	# La placa flotante de antes (Label3D "II"/"III"), si una partida vieja la trae.
	var plate := node.get_node_or_null("LevelPlate")
	if plate != null:
		plate.queue_free()
	if model == null:
		return
	var trim: Script = load("res://scripts/buildings/LevelTrim.gd")
	if not model.has_meta("base_scale"):
		model.set_meta("base_scale", model.scale)
		model.set_meta("base_pos", model.position)
	var base: Vector3 = model.get_meta("base_scale")
	var k: Vector3 = trim.call("level_scale", level)
	model.scale = base * k
	# Crecer alrededor del centro de la parcela, no del origen del modelo: el
	# desplazamiento de encaje (fit_model) crece con el; la base sube al zocalo.
	var p0: Vector3 = model.get_meta("base_pos", model.position)
	var target := Vector3(p0.x * k.x, p0.y + float(trim.call("plinth_height", level)), p0.z * k.z)
	if model.has_meta("look_base_pos"):
		# Hundido o ladeado (dano, ruina): se mueve la postura guardada y lo que
		# este desplazado se desplaza lo mismo, para que al reparar vuelva bien.
		var was: Vector3 = model.get_meta("look_base_pos")
		model.position += target - was
		model.set_meta("look_base_pos", target)
	else:
		model.position = target
	trim.call("apply", model, level, decor)

## "Construyendo 45 % · faltan 12 s" (o "Mejorando ..."): lo que dice el rotulo
## de la obra sobre el mapa, en 3D y en 2D.
func construction_text(node: Node) -> String:
	var info: Dictionary = _constructing.get(node, {})
	var key := "FMT_UPGRADING_ETA" if bool(info.get("is_upgrade", false)) else "FMT_CONSTRUCTING_ETA"
	return Tr.t(key) % [int(get_construction_progress(node) * 100), eta_text(get_construction_remaining(node))]

## Segundos que faltan, para leer de un vistazo: "12 s", "2:05 min".
static func eta_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s < 60:
		return "%d s" % s
	return "%d:%02d min" % [s / 60, s % 60]

const _BAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 back_color : source_color = vec4(0.05, 0.04, 0.03, 0.85);
void vertex() {
	// Siempre de cara a la camara, como los Label3D del rotulo.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	bool border = UV.x < 0.02 || UV.x > 0.98 || UV.y < 0.12 || UV.y > 0.88;
	vec4 c = border ? vec4(0.0, 0.0, 0.0, 0.9) : (UV.x <= progress ? fill_color : back_color);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
static var _bar_shader: Shader = null

## Barra de progreso de la obra, flotando bajo el rotulo. Un quad con su propio
## material (el progreso es de cada obra) y un shader compartido.
func _make_progress_bar() -> MeshInstance3D:
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = _BAR_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 0.42)
	var mat := ShaderMaterial.new()
	mat.shader = _bar_shader
	mat.set_shader_parameter("progress", 0.0)
	mat.render_priority = 1
	var bar := MeshInstance3D.new()
	bar.name = "ConstructionBar"
	bar.mesh = quad
	bar.material_override = mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar

## Rotulo y barra de una obra, al dia. Los dos son opcionales (la vista 2D solo
## tiene el rotulo; su barra la pinta el propio edificio).
func _refresh_construction_visual(node: Node) -> void:
	var label: Node = node.get_node_or_null("ConstructionLabel")
	if label:
		label.text = construction_text(node)
	var bar := node.get_node_or_null("ConstructionBar") as MeshInstance3D
	if bar and bar.material_override is ShaderMaterial:
		(bar.material_override as ShaderMaterial).set_shader_parameter("progress", get_construction_progress(node))

## Sin tipo en el parametro a proposito: una clave de `_constructing` puede ser
## un nodo ya liberado, y pasar un objeto liberado a un parametro tipado revienta
## la llamada antes de la primera linea. Entonces el erase no llegaba a correr y
## el mismo error se repetia cada fotograma. Primero se borra, despues se mira.
func _complete_construction(stale_or_node) -> void:
	var constr_info: Dictionary = _constructing.get(stale_or_node, {})
	_constructing.erase(stale_or_node)
	if not is_instance_valid(stale_or_node):
		return
	var node: Node = stale_or_node
	var is_upgrade: bool = constr_info.get("is_upgrade", false)
	# Una mejora nunca baja el nivel: como mucho lo deja donde estaba.
	var new_level: int = maxi(int(constr_info.get("new_level", 1)), int(node.get_meta("level", 1)))
	node.remove_meta("under_construction")
	# Restore mesh opacity
	var mesh_inst: Node = node.get_child(0) if node.get_child_count() > 0 else null
	if mesh_inst is MeshInstance3D:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0
	# Remove construction label and bar
	for child_name in ["ConstructionLabel", "ConstructionBar"]:
		var child: Node = node.get_node_or_null(child_name)
		if child:
			child.queue_free()
	if is_upgrade:
		node.set_meta("level", new_level)
		apply_level_visual(node, new_level)
		FloatingText.spawn_on(node, Tr.t("LBL_UPGRADE_COMPLETE"), Color(0.3, 0.8, 1.0))
		EventBus.building_upgrade_completed.emit(node, new_level)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_UPGRADE_DONE") % [(binfo["data"] as BuildingData).get_display_name(), new_level], "info", Color(0.3, 0.8, 1.0))
	else:
		FloatingText.spawn_on(node, Tr.t("FMT_CONSTRUCTION_COMPLETE"), Color(0.3, 1.0, 0.3))
		EventBus.construction_completed.emit(node)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_BUILT") % (binfo["data"] as BuildingData).get_display_name(), "info", Color(0.3, 1.0, 0.3))
	# Register for production
	var info := GridManager.get_building_info(node)
	if not info.is_empty():
		_register_producer(node, info["data"])

# ── Production ──

func _process(delta: float) -> void:
	# x2: construccion, produccion y caducidad al doble (GameConfig.sim_delta).
	# El enfriamiento del aviso de saco lleno es de la interfaz: segundos reales.
	var sim := GameConfig.sim_delta(delta)
	_tick_construction(sim)
	_tick_production(sim)
	_tick_spoilage(sim)
	if _full_bag_notice_cooldown > 0.0:
		_full_bag_notice_cooldown -= delta

func _tick_construction(delta: float) -> void:
	var completed: Array = []
	var gone: Array = []
	for node in _constructing:
		if not is_instance_valid(node):
			gone.append(node)
			continue
		_constructing[node]["remaining"] -= delta
		_refresh_construction_visual(node)
		if _constructing[node]["remaining"] <= 0.0:
			completed.append(node)
	for node in gone:
		_constructing.erase(node)
	for node in completed:
		_complete_construction(node)

func _tick_production(delta: float) -> void:
	var to_remove: Array = []
	for node in _producing:
		if not is_instance_valid(node):
			to_remove.append(node)
			continue
		if node.has_meta("under_construction"):
			continue
		# Sin carretera hasta el Nucleo no produce (PopulationManager pone la meta).
		if not bool(node.get_meta("connected", true)):
			continue
		# Lleno: parado hasta que se recoja. El reloj no avanza (no se adelanta
		# trabajo que no tiene donde ir).
		if is_full(node):
			continue
		var data: BuildingData = _producing[node]["data"]
		# Una granja sin obreros o en ruinas no crece: el cultivo espera. Los
		# demas edificios ya se quedaban sin rendir en ese caso.
		if data.id == FARM_ID and not can_work(node, data):
			continue
		_producing[node]["timer"] += delta
		var interval := get_cycle_seconds(node, data)
		if interval > 0.0 and _producing[node]["timer"] >= interval:
			_producing[node]["timer"] -= interval
			_award_production(node, data)
	for node in to_remove:
		_producing.erase(node)

func _award_production(node: Node, data: BuildingData) -> void:
	var produced := get_cycle_yield(node, data)
	if produced.is_empty():
		return
	# A la reserva del edificio, no a la bolsa: se recoge con un toque. El texto
	# flotante sale al recoger, que es cuando entra de verdad.
	_add_to_stock(node, produced)
	EventBus.production_tick.emit(node)

## Lo que rinde un edificio en UN ciclo ahora mismo (recurso -> cantidad). Es la
## unica formula de produccion: la usan el tic en vivo y la progresion offline,
## para que estar fuera nunca rinda distinto de estar mirando.
##
## Vacio si el edificio esta en ruinas o le faltan trabajadores. Con
## `include_events` a false se deja fuera lo pasajero (tormenta, plaga): offline
## no se simula ninguno de los dos, asi que tampoco se cobran.
func get_cycle_yield(node: Node, data: BuildingData, include_events := true) -> Dictionary:
	# A building in ruins produces nothing until it is repaired. This is what
	# gives the storm teeth beyond a bad afternoon.
	if BuildingHealth.is_ruined(node):
		return {}
	# Skip if building is not staffed (no workers assigned)
	if data.workers_required > 0 and not PopulationManager.is_building_staffed(node):
		return {}
	var level: int = node.get_meta("level", 1)
	var base_mult := GameConfig.get_production_multiplier(level) + GameConfig.tech_production_bonus + GameConfig.rank_production_bonus
	var mult := base_mult * PopulationManager.get_morale_multiplier()
	# Molino cerca (solo Granjas, meta de UtilityEffects).
	mult *= 1.0 + float(node.get_meta(UtilityEffects.MILL_META, 0.0))
	# Temporary, event-driven penalties (the Imperial Storm, the plague) ride on
	# their own multipliers so they can be lifted cleanly. Folding them into the
	# tech bonus would mix a passing squall with permanent research.
	if include_events:
		mult *= GameConfig.get_event_production_multiplier()
		# Central diesel cerca (industriales, meta de UtilityEffects). Va con lo
		# pasajero: offline no se quema combustible, asi que tampoco se cobra.
		mult *= 1.0 + float(node.get_meta(UtilityEffects.DIESEL_META, 0.0))
	var produced := {}
	var base := base_cycle_production(node, data)
	for res_name in base:
		produced[res_name] = int(float(base[res_name]) * mult)
	return produced

## Lo que rinde un ciclo antes de multiplicadores (recurso -> cantidad). En la
## Granja depende del cultivo; en los demas, del .tres.
func base_cycle_production(node: Node, data: BuildingData) -> Dictionary:
	if data.id == FARM_ID:
		var crop: Dictionary = GameConfig.get_crop(get_crop(node))
		return {"food": int(crop.get("food", data.produces_food))}
	return data.get_production()

## Segundos de un ciclo de este edificio ya escalados: el cultivo en la Granja,
## el intervalo del .tres en los demas.
func get_cycle_seconds(node: Node, data: BuildingData) -> float:
	if data.id == FARM_ID:
		return GameConfig.get_crop_duration(get_crop(node))
	return GameConfig.get_production_interval(data.production_interval)

## Lo que lleva hecho el ciclo en curso (0..1). 0 si no produce.
func get_cycle_progress(node: Node) -> float:
	if not _producing.has(node):
		return 0.0
	var data: BuildingData = _producing[node]["data"]
	var interval := get_cycle_seconds(node, data)
	if interval <= 0.0:
		return 0.0
	return clampf(float(_producing[node]["timer"]) / interval, 0.0, 1.0)

## Segundos que faltan para el ciclo en curso (lo que le queda al cultivo).
func get_cycle_remaining(node: Node) -> float:
	if not _producing.has(node):
		return 0.0
	var data: BuildingData = _producing[node]["data"]
	return maxf(0.0, get_cycle_seconds(node, data) - float(_producing[node]["timer"]))

## Puede trabajar ahora mismo: en pie, con carretera y con sus obreros.
func can_work(node: Node, data: BuildingData) -> bool:
	if node.has_meta("under_construction") or BuildingHealth.is_ruined(node):
		return false
	if not bool(node.get_meta("connected", true)):
		return false
	return data.workers_required <= 0 or PopulationManager.is_building_staffed(node)

# ══════════════════════════════════════════════════════════════════════
# ── Cultivos de la Granja ──
# ══════════════════════════════════════════════════════════════════════

## El cultivo de esta Granja (el de serie si nunca se eligio).
func get_crop(node: Node) -> String:
	var crop_id := String(_crops.get(node, GameConfig.farm_default_crop))
	return crop_id if not GameConfig.get_crop(crop_id).is_empty() else GameConfig.farm_default_crop

## Planta `crop_id` en la Granja. Cambiar de cultivo empieza de cero (lo que
## estaba creciendo se pierde); elegir el mismo no hace nada. Devuelve si cambio.
func plant_crop(node: Node, crop_id: String) -> bool:
	if node == null or not is_instance_valid(node) or GameConfig.get_crop(crop_id).is_empty():
		return false
	if get_crop(node) == crop_id:
		return false
	_crops[node] = crop_id
	if _producing.has(node):
		_producing[node]["timer"] = 0.0
	EventBus.crop_planted.emit(node, crop_id)
	return true

# ══════════════════════════════════════════════════════════════════════
# ── Lo acumulado y recoger ──
# ══════════════════════════════════════════════════════════════════════

## Lo que hay acumulado en el edificio (recurso -> cantidad). Copia.
func get_stock(node: Node) -> Dictionary:
	if not _stock.has(node):
		return {}
	return (_stock[node]["res"] as Dictionary).duplicate()

func get_stock_total(node: Node) -> int:
	var total := 0
	if _stock.has(node):
		for res_name in _stock[node]["res"]:
			total += int(_stock[node]["res"][res_name])
	return total

func has_stock(node: Node) -> bool:
	return get_stock_total(node) > 0

## Segundos que lleva lo acumulado sin recoger.
func get_stock_age(node: Node) -> float:
	return float(_stock[node]["age"]) if _stock.has(node) else 0.0

## Lo que cabe en el edificio a su nivel. 0 si no es un productor.
func get_stock_cap(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	var data: BuildingData = _data_of(node)
	if data == null or not data.is_producer():
		return 0
	return GameConfig.get_stock_cap(data.id, int(node.get_meta("level", 1)))

## Lleno: el edificio se para hasta que se recoja.
func is_full(node: Node) -> bool:
	var cap := get_stock_cap(node)
	return cap > 0 and get_stock_total(node) >= cap

func _data_of(node: Node) -> BuildingData:
	if _producing.has(node):
		return _producing[node]["data"]
	var info := GridManager.get_building_info(node)
	return info["data"] if not info.is_empty() else null

## Mete `produced` en el edificio, sin pasar del tope. Devuelve lo que entro.
func _add_to_stock(node: Node, produced: Dictionary) -> Dictionary:
	var room: int = maxi(0, get_stock_cap(node) - get_stock_total(node))
	if room <= 0:
		return {}
	if not _stock.has(node):
		_stock[node] = {"res": {}, "age": 0.0}
	var added := {}
	for res_name in produced:
		var amount: int = mini(int(produced[res_name]), room)
		if amount <= 0:
			continue
		_stock[node]["res"][res_name] = int(_stock[node]["res"].get(res_name, 0)) + amount
		added[res_name] = amount
		room -= amount
	if (_stock[node]["res"] as Dictionary).is_empty():
		_stock.erase(node)
	_stock_changed(node)
	return added

## Lo que no cupo en la bolsa al terminar un proceso del taller del edificio se
## queda dentro en vez de perderse (2026-10-04). Sin tope: ya estaba hecho.
func keep_in_building(node: Node, leftover: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	if GridManager.get_building_info(node).is_empty() and not _producing.has(node):
		return
	var any := false
	for res_name in leftover:
		if int(leftover[res_name]) <= 0:
			continue
		if not _stock.has(node):
			_stock[node] = {"res": {}, "age": 0.0}
		_stock[node]["res"][res_name] = int(_stock[node]["res"].get(res_name, 0)) + int(leftover[res_name])
		any = true
	if any:
		_stock_changed(node)

## Recoge lo de un edificio: a la bolsa lo que quepa (repartido en proporcion);
## lo demas se queda dentro. Devuelve lo que entro en la bolsa.
func collect(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node) or not has_stock(node):
		return {}
	var held: Dictionary = _stock[node]["res"]
	var fitted: Dictionary = ResourceManager.fit_into_storage(held)
	var offset := 0.0
	for res_name in fitted:
		var amount: int = int(fitted[res_name])
		if amount <= 0:
			continue
		ResourceManager.add(_res_to_type(res_name), amount)
		held[res_name] = int(held[res_name]) - amount
		# spawn_resource_on: vale para un edificio 3D y para uno 2D.
		FloatingText.spawn_resource_on(node, amount, res_name, offset)
		offset += 0.3
	for res_name in held.keys():
		if int(held[res_name]) <= 0:
			held.erase(res_name)
	# Recoger es volver: lo que se queda dentro (bolsa llena) empieza a contar de nuevo.
	if held.is_empty():
		_stock.erase(node)
	else:
		_stock[node]["age"] = 0.0
		if _full_bag_notice_cooldown <= 0.0:
			_full_bag_notice_cooldown = 20.0
			EventBus.notification_posted.emit(Tr.t("NOTIF_COLLECT_BAG_FULL"), "warning", Color(0.9, 0.6, 0.2))
	if not fitted.is_empty():
		EventBus.production_collected.emit(node, fitted)
	_stock_changed(node)
	return fitted

## Recoge todos los edificios. Devuelve el total que entro en la bolsa.
func collect_all() -> Dictionary:
	var total := {}
	for node in _stock.keys():
		if not is_instance_valid(node):
			_stock.erase(node)
			continue
		var got := collect(node)
		for res_name in got:
			total[res_name] = int(total.get(res_name, 0)) + int(got[res_name])
	return total

## Todo lo que espera a ser recogido, sumado (recurso -> cantidad).
func get_all_stock() -> Dictionary:
	var total := {}
	for node in _stock:
		if not is_instance_valid(node):
			continue
		for res_name in _stock[node]["res"]:
			total[res_name] = int(total.get(res_name, 0)) + int(_stock[node]["res"][res_name])
	return total

func _stock_changed(node: Node) -> void:
	if is_instance_valid(node):
		EventBus.building_stock_changed.emit(node, get_stock(node))

# ── Se echa a perder (solo si el modo lo pide) ──

func _tick_spoilage(delta: float) -> void:
	if _stock.is_empty():
		return
	var spoil := GameMode.spoilage_enabled()
	for node in _stock.keys():
		if not is_instance_valid(node):
			_stock.erase(node)
			continue
		_stock[node]["age"] = float(_stock[node]["age"]) + delta
		if spoil and float(_stock[node]["age"]) >= _spoil_after(node):
			_spoil(node, 1)

## Plazo de caducidad de lo acumulado en `node` (el Silo lo alarga en las Granjas).
func _spoil_after(node: Node) -> float:
	var data := _data_of(node)
	return GameConfig.spoil_after_for(data.id if data != null else "")

## Pierde `spoil_ratio` de lo acumulado `times` veces seguidas y vuelve a contar.
## Devuelve lo perdido.
func _spoil(node: Node, times: int) -> Dictionary:
	if not _stock.has(node) or times <= 0:
		return {}
	var held: Dictionary = _stock[node]["res"]
	var keep: float = pow(1.0 - GameConfig.spoil_ratio, times)
	var lost := {}
	for res_name in held.keys():
		var before: int = int(held[res_name])
		var after: int = int(floor(float(before) * keep))
		if before - after > 0:
			lost[res_name] = before - after
		if after <= 0:
			held.erase(res_name)
		else:
			held[res_name] = after
	if held.is_empty():
		_stock.erase(node)
	else:
		_stock[node]["age"] = 0.0
	if not lost.is_empty():
		EventBus.stock_spoiled.emit(node, lost)
		_stock_changed(node)
	return lost

# ── Guardar / cargar ──

## Lo acumulado, el cultivo y el reloj de cada productor, por celda de origen.
func get_save_data() -> Array:
	var out: Array = []
	var nodes: Dictionary = {}
	for node in _stock:
		nodes[node] = true
	for node in _crops:
		nodes[node] = true
	for node in _producing:
		if float(_producing[node]["timer"]) > 0.0:
			nodes[node] = true
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var info := GridManager.get_building_info(node)
		if info.is_empty():
			continue
		var origin: Vector2i = info["origin_cell"]
		var entry := {"cell_x": origin.x, "cell_y": origin.y}
		if _stock.has(node):
			entry["stock"] = (_stock[node]["res"] as Dictionary).duplicate()
			entry["age"] = float(_stock[node]["age"])
		if _crops.has(node):
			entry["crop"] = String(_crops[node])
		if _producing.has(node):
			entry["timer"] = float(_producing[node]["timer"])
		out.append(entry)
	return out

## Idempotente: pisa lo que haya, no suma. Una entrada cuyo edificio ya no esta
## se ignora; un guardado sin la clave no trae nada que restaurar.
func load_save_data(entries: Array) -> void:
	_stock.clear()
	_crops.clear()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var node := GridManager.get_building_at(Vector2i(int(entry.get("cell_x", -1)), int(entry.get("cell_y", -1))))
		if node == null or not is_instance_valid(node) or GridManager.get_building_info(node).is_empty():
			continue
		var crop_id := String(entry.get("crop", ""))
		if crop_id != "" and not GameConfig.get_crop(crop_id).is_empty():
			_crops[node] = crop_id
		var raw: Variant = entry.get("stock", {})
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var res := {}
			for res_name in raw:
				if ResourceManager.name_to_type(String(res_name)) != -1 and int(raw[res_name]) > 0:
					res[String(res_name)] = int(raw[res_name])
			if not res.is_empty():
				_stock[node] = {"res": res, "age": maxf(0.0, float(entry.get("age", 0.0)))}
		if _producing.has(node):
			_producing[node]["timer"] = maxf(0.0, float(entry.get("timer", 0.0)))
	for node in _stock:
		_stock_changed(node)

## Start upgrade on a building (reuses construction system)
func start_upgrade(node: Node, data: BuildingData, new_level: int) -> void:
	# Ya en obras (o en mejora): un segundo toque no cobra otra vez ni reinicia
	# la obra. Y nunca se "mejora" a un nivel que no es mas alto.
	if node == null or not is_instance_valid(node) or _constructing.has(node):
		return
	if new_level <= int(node.get_meta("level", 1)) or new_level > GameConfig.max_building_level:
		return
	var cost := GameConfig.get_upgrade_cost(data, new_level)
	if not ResourceManager.can_afford(cost):
		return
	ResourceManager.spend_cost(cost)
	var dur := GameConfig.get_upgrade_duration(new_level)
	_producing.erase(node)
	_constructing[node] = {
		"remaining": dur,
		"duration": dur,
		"is_upgrade": true,
		"new_level": new_level,
	}
	node.set_meta("under_construction", true)
	_apply_construction_visual(node)
	EventBus.building_upgrade_started.emit(node, new_level)

# ── Offline Progression ──
#
# Offline solo se produce (y se come, con tope). La tormenta, los eventos, el
# ejercito y los procesos se quedan congelados donde estaban: ver
# docs/09-save-system.md. Cada edificio rinde lo que diga get_cycle_yield(), la
# misma formula que en vivo, asi que una ruina o un edificio sin obreros tampoco
# produce estando fuera.
#
# Desde 2026-10-04 lo producido fuera se queda EN LOS EDIFICIOS, con su tope,
# como en vivo: al volver hay que recogerlo. Lo que come la gente sale de la
# comida que se cultivo fuera, nunca de la bolsa (nadie vuelve mas pobre de lo
# que se fue). Si el modo lo pide, lo acumulado se echa a perder igual que en vivo.
#
# Devuelve lo que se acumulo en los edificios estando fuera (recurso -> cantidad),
# ya descontado lo que se comio y lo que se echo a perder. Lo perdido queda en
# `last_offline_spoiled`.

func apply_offline_progression(elapsed: float) -> Dictionary:
	last_offline_spoiled = {}
	# Reloj atrasado, NaN o infinito: no ha pasado nada que se pueda cobrar.
	if is_nan(elapsed) or elapsed <= 0.0:
		return {}
	# Un salto hacia delante sospechoso (reloj adelantado, anos de ausencia) se
	# queda en el tope de 8 h, igual que una ausencia real larga.
	elapsed = minf(elapsed, GameConfig.max_offline_seconds)

	var existing_producers: Array = _producing.keys().duplicate()

	var to_complete: Array = []
	for node in _constructing.keys():
		if not is_instance_valid(node):
			continue
		var remaining: float = _constructing[node]["remaining"]
		if elapsed >= remaining:
			to_complete.append({"node": node, "leftover": elapsed - remaining})
		else:
			_constructing[node]["remaining"] -= elapsed
			_refresh_construction_visual(node)

	# Lo que se termina estando fuera produce solo el tiempo que le sobro. Se
	# completa antes de medir: completar pone el nivel nuevo y (por la senal de
	# construccion/mejora) reparte los obreros, y el rendimiento lee las dos cosas.
	var finished: Array = []
	for entry in to_complete:
		var node: Node = entry["node"]
		var info := GridManager.get_building_info(node)
		_complete_construction(node)
		if not info.is_empty():
			finished.append({"node": node, "data": info["data"], "seconds": float(entry["leftover"])})
	for node in existing_producers:
		if not is_instance_valid(node) or not _producing.has(node):
			continue
		finished.append({"node": node, "data": _producing[node]["data"], "seconds": elapsed})

	# Lo que habia antes de irse envejece todo el rato que se estuvo fuera.
	var aged_before: Dictionary = {}
	for node in _stock:
		aged_before[node] = true

	var added_total := {}
	var food_added: Dictionary = {}  # Node -> comida que entro estando fuera
	for entry in finished:
		var node: Node = entry["node"]
		if not is_instance_valid(node):
			continue
		var data: BuildingData = entry["data"]
		if not data.is_producer() or not _producing.has(node):
			continue
		var interval := get_cycle_seconds(node, data)
		if interval <= 0.0:
			continue
		if data.id == FARM_ID and not can_work(node, data):
			continue
		var clock: float = float(_producing[node]["timer"]) + float(entry["seconds"])
		var cycles := int(clock / interval)
		_producing[node]["timer"] = clock - float(cycles) * interval
		if cycles <= 0:
			continue
		var per_cycle := get_cycle_yield(node, data, false)
		var produced := {}
		for res_name in per_cycle:
			produced[res_name] = int(per_cycle[res_name]) * cycles
		var added := _add_to_stock(node, produced)
		# Lleno estando fuera: parado, el ciclo no sigue corriendo.
		if is_full(node):
			_producing[node]["timer"] = 0.0
		for res_name in added:
			added_total[res_name] = int(added_total.get(res_name, 0)) + int(added[res_name])
		if added.has("food"):
			food_added[node] = int(added["food"])
		if not aged_before.has(node) and _stock.has(node):
			# Lo nuevo empezo a acumularse con el primer ciclo, no al irse.
			_stock[node]["age"] = maxf(0.0, float(entry["seconds"]) - interval)

	# La gente come de lo que se cultivo fuera, nunca de la bolsa.
	var pop := PopulationManager.get_population()
	if pop > 0 and not food_added.is_empty():
		var cons_interval := GameConfig.get_duration(GameConfig.consumption_interval)
		if cons_interval > 0.0:
			var cons_ticks := int(elapsed / cons_interval)
			var cons_mult := maxf(0.1, 1.0 - GameConfig.tech_consumption_reduction)
			var demand := int(float(pop * cons_ticks * GameConfig.food_per_pop) * cons_mult)
			for node in food_added:
				if demand <= 0:
					break
				var eat: int = mini(demand, int(food_added[node]))
				eat = mini(eat, int(_stock[node]["res"].get("food", 0)) if _stock.has(node) else 0)
				if eat <= 0:
					continue
				_stock[node]["res"]["food"] = int(_stock[node]["res"]["food"]) - eat
				if int(_stock[node]["res"]["food"]) <= 0:
					_stock[node]["res"].erase("food")
				if (_stock[node]["res"] as Dictionary).is_empty():
					_stock.erase(node)
				added_total["food"] = int(added_total.get("food", 0)) - eat
				demand -= eat
				_stock_changed(node)

	# Echarse a perder, si el modo lo pide: cuantas veces paso el plazo.
	if GameMode.spoilage_enabled():
		for node in _stock.keys():
			if not is_instance_valid(node):
				continue
			var age: float = float(_stock[node]["age"])
			if aged_before.has(node):
				age += elapsed
			var after := _spoil_after(node)
			var periods := int(age / after)
			if periods <= 0:
				_stock[node]["age"] = age
				continue
			var rest: float = age - float(periods) * after
			var lost := _spoil(node, periods)
			if _stock.has(node):
				_stock[node]["age"] = rest
			for res_name in lost:
				last_offline_spoiled[res_name] = int(last_offline_spoiled.get(res_name, 0)) + int(lost[res_name])
				added_total[res_name] = int(added_total.get(res_name, 0)) - int(lost[res_name])
	else:
		for node in aged_before:
			if _stock.has(node):
				_stock[node]["age"] = float(_stock[node]["age"]) + elapsed

	for res_name in added_total.keys():
		if int(added_total[res_name]) == 0:
			added_total.erase(res_name)
	return added_total

func _res_to_type(res_name: String) -> int:
	return ResourceManager.name_to_type(res_name)
