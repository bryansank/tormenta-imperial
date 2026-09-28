#!/usr/bin/env bash
# Lanza la suite de gdUnit4 con una carpeta de usuario propia.
#
# Sin esto los tests corren en la carpeta de usuario del editor, que es donde
# vive la partida del jugador (%APPDATA%\Godot\app_userdata\Tormenta Imperial):
# varias suites aparcan y devuelven user://save_game.json, y dos ejecuciones a la
# vez se pisan la partida de verdad.
#
# Godot resuelve user:// al arrancar, antes de que exista ningun script, asi que
# la carpeta no se puede cambiar desde dentro de la suite. Un override.cfg en la
# raiz del proyecto si se lee antes: este script lo escribe, lanza GdUnitCmdTool
# y lo quita al salir (trap), falle o no. Si ya habia un override.cfg, se aparta
# y se devuelve tal cual.
#
# Uso:
#   GODOT=/ruta/a/godot tools/run_tests.sh              # toda la suite (tests/)
#   GODOT=/ruta/a/godot tools/run_tests.sh -a tests/combat
# Variables:
#   GODOT              ejecutable de Godot 4.7 .NET (por defecto: godot en PATH)
#   TI_TEST_USER_DIR   nombre de la carpeta de tests (por defecto TormentaImperial_tests,
#                      queda en %APPDATA%\<nombre>)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT:-godot}"
DIR_NAME="${TI_TEST_USER_DIR:-TormentaImperial_tests}"
OVERRIDE="$ROOT/override.cfg"
BACKUP="$ROOT/override.cfg.run_tests.bak"
MARK="; tools/run_tests: temporal, se borra al terminar"

case "$DIR_NAME" in
	""|"TormentaImperial"|"Tormenta Imperial")
		echo "run_tests: '$DIR_NAME' es la carpeta del jugador; elige otra en TI_TEST_USER_DIR" >&2
		exit 2 ;;
esac

OWNED=0
cleanup() {
	if [ "$OWNED" = 1 ]; then
		rm -f "$OVERRIDE"
		if [ -e "$BACKUP" ]; then
			mv -f "$BACKUP" "$OVERRIDE"
		fi
	fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if [ -e "$OVERRIDE" ] && grep -qF "$MARK" "$OVERRIDE"; then
	# Otra ejecucion de este script en la misma carpeta ya lo puso: se usa y lo
	# quita ella.
	:
else
	if [ -e "$OVERRIDE" ]; then
		if [ -e "$BACKUP" ]; then
			echo "run_tests: ya existe $BACKUP (una ejecucion anterior murio?); revisalo antes de seguir" >&2
			exit 2
		fi
		mv "$OVERRIDE" "$BACKUP"
	fi
	OWNED=1
	printf '%s\n[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"\n' \
		"$MARK" "$DIR_NAME" > "$OVERRIDE"
fi

if [ "$#" -eq 0 ]; then
	set -- -a tests
fi

"$GODOT_BIN" --headless --path "$ROOT" -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode "$@"
STATUS=$?
exit "$STATUS"
