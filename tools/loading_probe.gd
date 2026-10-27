extends SceneTree
## Capturas de la pantalla de carga (docs/19 §14): pone LoadingScreen como al
## arrancar, espera a que la barra pase de `--at` por ciento y guarda la foto;
## con `--fail` la pone en su estado de fallo. Necesita un override.cfg propio
## (carga la escena de verdad, aunque sale antes de montarla).
##
##   godot --path . -s tools/loading_probe.gd -- --shot-size=640x360 --out=docs/media/dev/carga_640.png
##   godot --path . -s tools/loading_probe.gd -- --fail --out=docs/media/dev/carga_fallo.png

## Se carga en _initialize, no con preload: un script -s se compila antes de que
## existan los autoloads, y LoadingScreen los nombra.
const LOADING_SCREEN := "res://scripts/boot/LoadingScreen.gd"

var _args := {}
var _screen: CanvasLayer
var _frames := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var size := str(_args.get("shot-size", "1280x720")).split("x")
	DisplayServer.window_set_size(Vector2i(int(size[0]), int(size[1])))
	root.size = Vector2i(int(size[0]), int(size[1]))
	_screen = load(LOADING_SCREEN).new()
	root.add_child(_screen)

func _process(_delta: float) -> bool:
	_frames += 1
	if _screen == null:
		return true
	if _frames == 3 and _args.has("fail"):
		_screen._fail("ui", "res://scenes/ui/BattleScreen.tscn")
	var ready_to_shoot: bool = (_args.has("fail") and _frames > 8) or \
		(not _args.has("fail") and _screen.percent() >= float(_args.get("at", "35")))
	if ready_to_shoot or _frames > 3000:
		var img := root.get_texture().get_image()
		var out := str(_args.get("out", "docs/media/dev/carga.png"))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
		img.save_png(ProjectSettings.globalize_path("res://" + out))
		print("[loading_probe] %s (%d %%, etapa %s)" % [out, int(_screen.percent()), _screen.stage()])
		_screen._phase = "done"
		return true
	return false
