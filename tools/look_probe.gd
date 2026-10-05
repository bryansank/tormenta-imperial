extends SceneTree
## Lanzador de la sonda del aspecto de los edificios (ver look_probe_runner.gd):
## una fila de edificios en cada estado —las tres fases de obra por huella,
## mejora, ruina, trabajando y quieto— fotografiada en 3D y en 2D.
##
##     godot --path . -s tools/look_probe.gd -- --no-dev
##
## Con ventana (los shaders solo compilan con un renderizador de verdad) y
## SIEMPRE con un override.cfg que apunte a otra carpeta de datos. Las capturas
## van a docs/media/dev/look_probe_3d.png y look_probe_2d.png (git-ignored).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/look_probe_runner.gd").new())
