extends SceneTree
## Lanzador de la sonda de QA de tablet (ver tablet_qa_probe_runner.gd): toques
## sinteticos de verdad (InputEventScreenTouch / ScreenDrag) sobre la partida:
## mantener pulsado, CONSTRUIR y su lista, colocar con el dedo (fantasma, ✓, ✕),
## carretera larga (toca inicio -> fin), pellizco y giro, Ajustes y tema oscuro,
## combate tocando el tablero.
##
##     godot --path . -s tools/tablet_qa_probe.gd -- --shot-size=1280x800 --profile=tablet
##     godot --path . -s tools/tablet_qa_probe.gd -- --shot-size=1113x835 --profile=tablet --view=2d
##
## Con ventana y SIEMPRE con un override.cfg que apunte a otra carpeta de datos.

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tools/tablet_qa_probe_runner.gd").new())
