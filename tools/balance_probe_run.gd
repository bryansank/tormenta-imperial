extends SceneTree
## Lanza tools/balance_probe.gd SIN registrarlo como autoload (feat/ritmo-colono):
## crea la sonda, la cuelga de la raiz y llama a su _run(). Los argumentos son los
## de la sonda (despues de `--`). Con un override.cfg de carpeta propia, como todas
## las sondas.
##
##   godot --headless --path . -s tools/balance_probe_run.gd -- --only=campaigns --camp-seeds=100
##   godot --headless --path . -s tools/balance_probe_run.gd -- --only=campaigns --retry-sim=4 --ease=0

func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	await process_frame
	await process_frame
	var probe: Node = load("res://tools/balance_probe.gd").new()
	root.add_child(probe)
	await process_frame
	probe._run()
	quit()
