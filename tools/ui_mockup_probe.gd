extends SceneTree
## Lanzador de la sonda de maquetas del rediseno de la interfaz (fase 1,
## docs/28-guia-ui.md). Ver tools/ui_mockup/ui_mockup_runner.gd.
##
##     godot --path . -s tools/ui_mockup_probe.gd
##     godot --path . -s tools/ui_mockup_probe.gd -- --only=phone640
##
## Con ventana (una sola) y SIEMPRE con un override.cfg que apunte a otra
## carpeta de datos: siembra una partida y coloca edificios (autoguardado).
## Capturas en docs/media/dev/ui_mockups/ (ignorada por git).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/ui_mockup/ui_mockup_runner.gd").new())
