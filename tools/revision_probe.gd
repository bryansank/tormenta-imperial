extends SceneTree
## Lanzador de la sonda de revision visual (ver revision_probe_runner.gd).
##
##     godot --path . -s tools/revision_probe.gd -- --shot-size=1280x720 --profile=pc
##     godot --path . -s tools/revision_probe.gd -- --shot-size=1280x800 --profile=tablet
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/revision_probe_runner.gd").new())
