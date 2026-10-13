extends SceneTree
## Lanzador de la sonda del dia y la noche (ver dianoche_probe_runner.gd): la
## colonia de tools/arte_probe_runner.gd fotografiada al amanecer, a mediodia,
## al atardecer, de noche y de noche con Tormenta, en 3D y en 2D, mas la noche
## en calidad minima y una medida de FPS de dia y de noche.
##
##     godot --path . -s tools/dianoche_probe.gd -- --no-title --no-dev --tag=dianoche
##
## Con ventana (headless no pinta) y SIEMPRE con un override.cfg que apunte a
## otra carpeta de datos: siembra una partida (la que hubiera se aparca y se
## devuelve). Capturas en docs/media/dev/dianoche_<tag>_*.png (git-ignored).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/dianoche_probe_runner.gd").new())
