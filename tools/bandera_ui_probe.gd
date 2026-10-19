extends SceneTree
## Lanzador de la sonda de las rejillas de PAIS Y BANDERA y de REGIMIENTO
## (bandera_ui_probe_runner.gd): sin partida, solo el editor y la tarjeta.
##
##     godot --path . -s tools/bandera_ui_probe.gd -- --shot-size=640x360 --profile=phone --tag=antes
##     godot --path . -s tools/bandera_ui_probe.gd -- --shot-size=1280x800 --profile=tablet --rank=5
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/bandera_ui_probe_runner.gd").new())
