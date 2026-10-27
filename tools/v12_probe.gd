extends SceneTree
## Lanzador de la sonda de la 1.2 (ver v12_probe_runner.gd): las pantallas
## nuevas de la integracion (edificios, amenazas, barco, final con eleccion).
##
##     godot --path . -s tools/v12_probe.gd -- --shot-size=640x360 --profile=phone
##     godot --path . -s tools/v12_probe.gd -- --shot-size=1280x720 --profile=pc
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/v12_probe_runner.gd").new())
