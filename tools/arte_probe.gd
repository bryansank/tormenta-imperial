extends SceneTree
## Lanzador de la sonda del arte del mapa (ver arte_probe_runner.gd): una
## colonia poblada fotografiada en calma y en las tres fases de la Tormenta, en
## 3D y en 2D, y una medida de FPS sin vsync.
##
##     godot --path . -s tools/arte_probe.gd -- --no-title --no-dev --tag=despues
##     godot --path . --rendering-method mobile -s tools/arte_probe.gd -- --no-title --no-dev --tag=mobile
##
## `--tag=` pone el prefijo de las capturas (docs/media/dev/arte_<tag>_*.png,
## git-ignored). Con ventana (headless no pinta) y SIEMPRE con un override.cfg
## que apunte a otra carpeta de datos: siembra una partida (la que hubiera se
## aparca y se devuelve).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/arte_probe_runner.gd").new())
