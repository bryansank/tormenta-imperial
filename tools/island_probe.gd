extends Node
## Sonda visual de A1/A2/A10/A11/A12: arranca una partida nueva, planta un
## extractor junto a cada yacimiento con la misma regla que usa el clic, y
## fotografia (1) la isla entera con la cuadricula y (2) el Nucleo con los
## badges de estado. Nada de mockups: son fotogramas del juego corriendo.
##
## Uso: borrar user://save_game.json, registrar temporalmente como autoload y
## arrancar el juego con ventana.
##   project.godot -> [autoload] -> IslandProbe="*res://tools/island_probe.gd"
## Salida: res://docs/media/dev/isla_rejilla.png y nucleo_badges.png (ignorados
## por git). Quitar la linea del autoload al terminar.
##
## Hermana de tools/storm_probe.gd y tools/showcase_shots.gd.

const OUT_DIR := "res://docs/media/dev"
const SETTLE := 2.5

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[island] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	var main := get_tree().current_scene
	if main == null:
		push_warning("[island] no hay escena actual")
		return
	var placer: Node = main.get_node_or_null("BuildingPlacer")
	var map_gen: Node = main.get_node_or_null("MapGenerator")
	if placer == null or map_gen == null:
		push_warning("[island] faltan BuildingPlacer o MapGenerator")
		return

	# La cuadricula tiene que verse en la foto aunque el settings.cfg de esta
	# maquina la tenga apagada. Solo en memoria: no se guarda la preferencia.
	GameConfig.ui_grid_visible = true
	EventBus.grid_overlay_toggled.emit(true)

	# Los tres extractores de Era 1-2, cada uno tocando su yacimiento.
	# Poblacion inicial 5: aserradero (2) + mina (3) quedan dotados y ensenan
	# el obrero; la fundicion (3) se queda sin gente y ensena el Zzz rojo.
	var report: Array = []
	report.append(_plant_near(placer, map_gen, "sawmill", "forest"))
	report.append(_plant_near(placer, map_gen, "gold_mine", "gold_vein"))
	report.append(_plant_near(placer, map_gen, "foundry", "iron_deposit"))
	PopulationManager._recalculate_all()
	for line in report:
		print(line)

	# Diagnostico de la apertura: cuantos huecos legales hay para el aserradero.
	var spots: Array = map_gen.buildable_spots_near("forest", Vector2i(2, 1), 1)
	print("[island] huecos legales para aserradero junto a bosque: %d" % spots.size())

	var helper: Node = main.get_node_or_null("HelperPanel")
	if helper != null:
		helper.visible = false

	var cam: Node = main.get_node_or_null("MonumentalCamera")
	# 1) La isla entera: hay que alejarse mas de lo que el juego permite.
	if cam != null:
		cam.max_distance = 110.0
		cam._distance = 105.0
		cam._target_distance = 105.0
	await get_tree().create_timer(1.5).timeout
	await _shot("isla_rejilla")

	# 2) El Nucleo y los badges a la distancia habitual.
	if cam != null:
		cam._distance = 24.0
		cam._target_distance = 24.0
	await get_tree().create_timer(1.5).timeout
	await _shot("nucleo_badges")

	print("[island] listo")
	get_tree().quit()

## Planta `id` en el hueco legal mas cercano al centro que toque `deposit_id`,
## usando la misma regla de alcance que el clic del jugador.
func _plant_near(placer: Node, map_gen: Node, id: String, deposit_id: String) -> String:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	if data == null:
		return "[island] falta %s.tres" % id
	var rule: Dictionary = GameConfig.get_deposit_rule(id)
	var spots: Array = map_gen.buildable_spots_near(deposit_id, data.grid_size, int(rule.get("reach", 1)))
	if spots.is_empty():
		return "[island] %s: NINGUN hueco junto a %s en este mapa" % [id, deposit_id]
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	spots.sort_custom(func(a, b): return (a["origin"] - center).length() < (b["origin"] - center).length())
	var spot: Dictionary = spots[0]
	var origin: Vector2i = spot["origin"]
	var size: Vector2i = spot["size"]
	var rot: int = 0 if size == data.grid_size else 1
	var node: Node3D = placer.place_building_at(data, origin, rot)
	if node == null:
		return "[island] %s: place_building_at fallo en %s" % [id, origin]
	ProductionManager.register_building(node, data, 0.0)
	# Lo que el clic habria dicho de este mismo sitio.
	var verdict: Dictionary = placer.evaluate_placement(id, origin, size, map_gen, node)
	return "[island] %s en %s (%s) junto a %s: regla ok=%s, huecos=%d" % [id, origin, size, deposit_id, verdict["ok"], spots.size()]

func _shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, file_name])
	print("[island] %s.png (err %d)" % [file_name, err])
