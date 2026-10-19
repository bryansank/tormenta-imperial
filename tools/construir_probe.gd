extends SceneTree
## Lanzador de la sonda de CONSTRUIR (ver construir_probe_runner.gd):
##
##     godot --path . -s tools/construir_probe.gd -- --shot-size=640x360 --profile=phone
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/construir_probe_runner.gd").new())
