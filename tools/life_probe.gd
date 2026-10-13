extends SceneTree
## Lanzador de la sonda de la vida de la ciudad (ver life_probe_runner.gd):
## un pueblo sembrado con obreros y ciudadanos en la calle, fotografiado en 3D
## y en 2D, la calle vacia en la Ceniza, y la medida de rendimiento con 60+
## figuras.
##
##     godot --path . -s tools/life_probe.gd -- --no-title --no-dev
##
## Con ventana (headless no pinta) y SIEMPRE con un override.cfg que apunte a
## otra carpeta de datos: siembra una partida. Aun asi el guardado que haya se
## aparca y se devuelve. Capturas en docs/media/dev/life_probe_*.png (git-ignored).

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/life_probe_runner.gd").new())
