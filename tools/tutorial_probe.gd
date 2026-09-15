extends Node
## Dev tool: captura la intro del tutorial y un consejo contextual tal y como
## los ve el jugador, para comprobar a ojo que el texto cabe, se lee y no se
## sale del panel. Los tests dicen que la logica va; esto dice que se ve.
##
## Uso: borrar user://save_game.json, registrar temporalmente como autoload y
## arrancar el juego CON ventana (no headless).
##   project.godot -> [autoload] -> TutorialProbe="*res://tools/tutorial_probe.gd"
## Quitar la linea al terminar.
##
## Hermano de tools/storm_probe.gd.

const SETTLE := 1.5
const OUT_DIR := "res://docs/media/dev"

func _ready() -> void:
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	var main := get_tree().current_scene
	var panel: Node = main.get_node_or_null("TutorialPanel") if main != null else null
	if panel == null:
		print("[tutorial] ERROR: no hay TutorialPanel en la escena")
		get_tree().quit()
		return

	print("[tutorial] intro abierta al arrancar = %s (intro_seen=%s)" % [
		panel.is_intro_open(), TutorialManager.intro_seen])
	if not panel.is_intro_open():
		# Partida ya vista: se fuerza para poder mirarla igual.
		TutorialManager.show_intro()
		await get_tree().process_frame

	await _shot("tutorial_01_intro_p1")
	panel._next_page()
	panel._next_page()
	await _shot("tutorial_02_intro_p3")
	# La pagina mas larga del lore y la primera de "como se juega".
	panel.go_to_page(3)
	await _shot("tutorial_03_intro_p4")
	panel.go_to_page(6)
	await _shot("tutorial_04_play_p7")
	panel.go_to_page(panel.page_count() - 1)
	await _shot("tutorial_05_play_last")

	panel._close()
	await get_tree().process_frame
	print("[tutorial] intro cerrada; intro_seen=%s" % TutorialManager.intro_seen)

	# Un consejo de verdad, por la senal real: el primer Aviso.
	EventBus.storm_incoming.emit(30.0)
	await get_tree().create_timer(0.4).timeout
	print("[tutorial] consejo en pantalla = %s, vistos = %s" % [
		panel.is_tip_showing(), TutorialManager.tips_seen])
	await _shot("tutorial_06_tip_aviso")
	panel._dismiss_tip()

	# Y el consejo largo, para ver que tambien cabe.
	EventBus.tithe_demanded.emit(1)
	await get_tree().create_timer(0.4).timeout
	await _shot("tutorial_07_tip_diezmo")

	# Y el mismo consejo otra vez: no debe salir.
	panel._dismiss_tip()
	EventBus.storm_incoming.emit(30.0)
	await get_tree().process_frame
	print("[tutorial] repetido el aviso: consejo en pantalla = %s (debe ser false)" % panel.is_tip_showing())

	get_tree().quit()

func _shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, file_name])
	print("[tutorial] %s.png (err %d)" % [file_name, err])
