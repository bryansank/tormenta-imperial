extends SceneTree
## Lanzador de la sonda de la isla irregular (ver costa_probe_runner.gd): varias
## partidas nuevas, cada una con su isla, fotografiadas enteras en 3D y en 2D,
## de dia, de noche y con Tormenta, mas un plano cerca de la costa.
##
##     godot --path . -s tools/costa_probe.gd -- --no-title --no-dev --islands=5
##
## Con ventana (headless no pinta) y SIEMPRE con un override.cfg que apunte a
## otra carpeta de datos: empieza partidas nuevas (la que hubiera se aparca y se
## devuelve). Capturas en docs/media/dev/costa_<n>_*.png (git-ignored).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/costa_probe_runner.gd").new())
