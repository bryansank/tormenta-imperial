extends SceneTree
## Lanzador de la sonda del aspecto de los edificios (ver look_probe_runner.gd):
## una fila de edificios en cada estado —las tres fases de obra por huella,
## mejora, ruina, trabajando y quieto— fotografiada en 3D y en 2D.
##
##     godot --path . -s tools/look_probe.gd -- --no-dev
##
## Con ventana (los shaders solo compilan con un renderizador de verdad) y
## SIEMPRE con un override.cfg que apunte a otra carpeta de datos. Las capturas
## van a docs/media/dev/look_probe_3d.png y look_probe_2d.png, y las obras (una
## fila por fase, varios edificios y dos casas) a look_probe_obras_3d.png,
## look_probe_obras_3d_b.png (un instante despues: la grua se ha movido) y
## look_probe_obras_2d.png (git-ignored).
##
## `-- --niveles`: solo los edificios mejorables a nivel I, II y III, en 3D y 2D
## (look_probe_niveles_3d.png, look_probe_niveles_2d.png).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/look_probe_runner.gd").new())
