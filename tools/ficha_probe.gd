extends SceneTree
## Lanzador de la sonda de las fichas (ver ficha_probe_runner.gd): todas las
## fichas de edificio y de yacimiento, con la cola de tandas y ENTRENAR.
##
##     godot --path . -s tools/ficha_probe.gd -- --shot-size=640x360 --profile=phone --tag=antes
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/ficha_probe_runner.gd").new())
