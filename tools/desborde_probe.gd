extends SceneTree
## Lanzador de la sonda de desbordes (ver desborde_probe_runner.gd): abre cada
## pantalla y escribe en consola lo que se sale del lienzo o de su panel.
##
##     godot --path . -s tools/desborde_probe.gd -- --shot-size=640x360 --profile=phone --canvas=640x360
##     godot --path . -s tools/desborde_probe.gd -- --shot-size=1280x720 --profile=pc --theme=dark
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/desborde_probe_runner.gd").new())
