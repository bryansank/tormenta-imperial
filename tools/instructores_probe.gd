extends SceneTree
## Lanzador de la sonda de los instructores (ver instructores_probe_runner.gd).
##
##     godot --path . -s tools/instructores_probe.gd -- --shot-size=1280x720 --profile=pc
##     godot --path . -s tools/instructores_probe.gd -- --shot-size=800x400 --profile=phone
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/instructores_probe_runner.gd").new())
