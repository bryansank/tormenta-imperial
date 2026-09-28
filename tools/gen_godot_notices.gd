extends SceneTree
## Herramienta re-ejecutable: vuelca los avisos de copyright y licencias del motor
## (el equivalente al COPYRIGHT.txt de Godot) a licenses/GODOT-COPYRIGHT.txt.
##
## Los saca del propio binario (Engine.get_license_text, get_copyright_info,
## get_license_info), así que describen exactamente el Godot con el que se exporta.
## Hay que volver a ejecutarla cada vez que se cambie de versión del motor.
##
## Uso (no necesita importar el proyecto; la salida es una ruta absoluta):
##   "$GODOT" --headless --path . -s tools/gen_godot_notices.gd -- "$PWD/licenses/GODOT-COPYRIGHT.txt"
## El fichero lo empaquetan tools/package_release.{sh,ps1}. Ver THIRD-PARTY-NOTICES.md.

const RULE := "--------------------------------------------------------------------------------"
const DOUBLE := "================================================================================"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "res://licenses/GODOT-COPYRIGHT.txt"
	var v := Engine.get_version_info()
	var lines := PackedStringArray()
	lines.append("Godot Engine %s — copyright and third-party licence notices" % v["string"])
	lines.append("")
	lines.append("Generated from the engine binary (Engine.get_license_text, get_copyright_info,")
	lines.append("get_license_info) by tools/gen_godot_notices.gd. It is the same information as")
	lines.append("Godot's COPYRIGHT.txt: https://github.com/godotengine/godot/blob/%s/COPYRIGHT.txt" % v["hash"])
	lines.append("Engine build hash: %s" % v["hash"])
	lines.append("")
	lines.append("The list covers every component compiled into Godot; a given export template")
	lines.append("contains a subset of it (e.g. the Windows template has no Wayland or Android code).")
	lines.append("")
	lines.append(DOUBLE)
	lines.append("GODOT ENGINE LICENCE (MIT / Expat)")
	lines.append(DOUBLE)
	lines.append("")
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append(DOUBLE)
	lines.append("THIRD-PARTY COMPONENTS INCLUDED IN GODOT")
	lines.append(DOUBLE)
	for c in Engine.get_copyright_info():
		lines.append("")
		lines.append("Component: %s" % c["name"])
		for p in c["parts"]:
			lines.append("  Files: %s" % ", ".join(PackedStringArray(p["files"])))
			for cr in p["copyright"]:
				lines.append("  Copyright: %s" % cr)
			lines.append("  License: %s" % p["license"])
	lines.append("")
	lines.append(DOUBLE)
	lines.append("LICENCE TEXTS REFERENCED ABOVE")
	lines.append(DOUBLE)
	var info := Engine.get_license_info()
	var keys := info.keys()
	keys.sort()
	for k in keys:
		lines.append("")
		lines.append(RULE)
		lines.append("License: %s" % k)
		lines.append(RULE)
		lines.append("")
		lines.append(str(info[k]).strip_edges())
	lines.append("")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("gen_godot_notices: no se pudo escribir %s (%s)" % [out_path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("gen_godot_notices: %s (%d componentes, %d licencias)" % [out_path, Engine.get_copyright_info().size(), keys.size()])
	quit(0)
