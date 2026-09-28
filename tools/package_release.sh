#!/usr/bin/env bash
# Empaqueta builds ya exportadas en zips listos para dar a testers, con las
# licencias que exigen los componentes de terceros. No exporta nada: parte del
# .exe y del .apk que ya existen. Ver docs/19-exportar.md, "Distribución".
#
# Crea:
#   <out>/TormentaImperial-<version>-windows.zip
#     TormentaImperial-<version>-windows/
#       TormentaImperial.exe  LEEME.txt  LICENSE.txt  THIRD-PARTY-NOTICES.md
#       GODOT-COPYRIGHT.txt   licenses/fonts/*.txt
#   <out>/TormentaImperial-<version>-android.zip
#     TormentaImperial-<version>-android/
#       TormentaImperial-<version>.apk  (+ los mismos avisos y su LEEME.txt)
#
# Uso:
#   tools/package_release.sh [--exe RUTA] [--apk RUTA] [--out DIR]
#                            [--version X.Y.Z] [--only windows|android]
# Por defecto: --exe build/windows/TormentaImperial.exe,
#              --apk build/android/TormentaImperial-debug.apk, --out dist,
#              version = config/version de project.godot.
# Las rutas relativas se resuelven desde la raíz del proyecto.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXE="build/windows/TormentaImperial.exe"
APK="build/android/TormentaImperial-debug.apk"
OUT="dist"
VERSION=""
ONLY=""

die() { echo "package_release: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--exe) EXE="${2:?falta la ruta de --exe}"; shift 2 ;;
		--apk) APK="${2:?falta la ruta de --apk}"; shift 2 ;;
		--out) OUT="${2:?falta la carpeta de --out}"; shift 2 ;;
		--version) VERSION="${2:?falta el valor de --version}"; shift 2 ;;
		--only) ONLY="${2:?falta windows o android}"; shift 2 ;;
		-h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) die "argumento desconocido: $1 (ver --help)" ;;
	esac
done
case "$ONLY" in ""|windows|android) ;; *) die "--only acepta windows o android" ;; esac

abs() { case "$1" in /*|[A-Za-z]:*) printf '%s' "$1" ;; *) printf '%s/%s' "$ROOT" "$1" ;; esac; }
EXE="$(abs "$EXE")"; APK="$(abs "$APK")"; OUT="$(abs "$OUT")"

if [ -z "$VERSION" ]; then
	VERSION="$(sed -n 's/^config\/version="\(.*\)"[[:space:]]*$/\1/p' "$ROOT/project.godot" | head -n 1)"
	[ -n "$VERSION" ] || die "no encuentro config/version en project.godot (usa --version)"
fi

# Lo que acompaña a cada binario. Si falta algo, no hay zip: repartir el juego sin
# sus licencias es justo lo que este script existe para evitar.
NOTICES=(LICENSE THIRD-PARTY-NOTICES.md licenses/GODOT-COPYRIGHT.txt)
for f in "${NOTICES[@]}" tools/dist/LEEME-windows.txt tools/dist/LEEME-android.txt; do
	[ -f "$ROOT/$f" ] || die "falta $f"
done
FONT_LICENSES=()
for font in "$ROOT"/assets/fonts/*.ttf "$ROOT"/assets/fonts/*.otf; do
	[ -e "$font" ] || continue
	name="$(basename "$font")"; family="${name%%-*}"
	match=""
	for lic in "$ROOT"/assets/fonts/*.txt; do
		case "$(basename "$lic")" in *"$family"*) match="$lic" ;; esac
	done
	[ -n "$match" ] || die "la fuente $name no tiene su licencia al lado (assets/fonts/*$family*.txt)"
done
for lic in "$ROOT"/assets/fonts/*.txt; do FONT_LICENSES+=("$lic"); done
[ ${#FONT_LICENSES[@]} -gt 0 ] || die "no hay licencias de fuentes en assets/fonts/"

# Elige con qué comprimir: zip, python o el tar de Windows (bsdtar, que sí hace zip).
PY=""
for c in python3 python py; do
	if command -v "$c" >/dev/null 2>&1 && "$c" -c "import zipfile" >/dev/null 2>&1; then PY="$c"; break; fi
done
make_zip() { # make_zip <carpeta_padre> <nombre_carpeta> <zip_destino>
	local parent="$1" dir="$2" dest="$3"
	rm -f "$dest"
	if command -v zip >/dev/null 2>&1; then
		(cd "$parent" && zip -q -r -9 -X "$dest" "$dir")
	elif [ -n "$PY" ]; then
		(cd "$parent" && "$PY" - "$dest" "$dir" <<'PYEOF'
import os, sys, zipfile
dest, top = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for base, dirs, files in os.walk(top):
        dirs.sort()
        for name in sorted(files):
            p = os.path.join(base, name)
            z.write(p, p.replace(os.sep, "/"))
PYEOF
		)
	elif [ -x /c/Windows/System32/tar.exe ]; then
		(cd "$parent" && /c/Windows/System32/tar.exe -a -c -f "$dest" "$dir")
	else
		die "no hay con qué crear el zip: instala zip o python"
	fi
}

# Texto para Windows: CRLF, para que se lea bien en cualquier Bloc de notas.
to_crlf() { sed -e 's/\r$//' -e 's/$/\r/' "$1" > "$2"; }

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ti_package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT"

stage_common() { # stage_common <carpeta> <leeme>
	local d="$1"
	mkdir -p "$d/licenses/fonts"
	sed "s/{{VERSION}}/$VERSION/g" "$ROOT/$2" > "$d/LEEME.tmp"
	to_crlf "$d/LEEME.tmp" "$d/LEEME.txt"; rm -f "$d/LEEME.tmp"
	to_crlf "$ROOT/LICENSE" "$d/LICENSE.txt"
	to_crlf "$ROOT/licenses/GODOT-COPYRIGHT.txt" "$d/GODOT-COPYRIGHT.txt"
	cp "$ROOT/THIRD-PARTY-NOTICES.md" "$d/THIRD-PARTY-NOTICES.md"
	for lic in "${FONT_LICENSES[@]}"; do cp "$lic" "$d/licenses/fonts/"; done
}

magic() { head -c 2 "$1"; }
MADE=()

if [ "$ONLY" != "android" ]; then
	[ -f "$EXE" ] || die "no existe el .exe: $EXE (exporta primero o pasa --exe)"
	[ "$(magic "$EXE")" = "MZ" ] || die "$EXE no parece un ejecutable de Windows"
	name="TormentaImperial-$VERSION-windows"
	stage_common "$STAGE/$name" tools/dist/LEEME-windows.txt
	cp "$EXE" "$STAGE/$name/TormentaImperial.exe"
	make_zip "$STAGE" "$name" "$OUT/$name.zip"
	MADE+=("$OUT/$name.zip")
fi

if [ "$ONLY" != "windows" ]; then
	[ -f "$APK" ] || die "no existe el APK: $APK (exporta primero o pasa --apk)"
	[ "$(magic "$APK")" = "PK" ] || die "$APK no parece un APK"
	name="TormentaImperial-$VERSION-android"
	stage_common "$STAGE/$name" tools/dist/LEEME-android.txt
	cp "$APK" "$STAGE/$name/TormentaImperial-$VERSION.apk"
	make_zip "$STAGE" "$name" "$OUT/$name.zip"
	MADE+=("$OUT/$name.zip")
fi

for z in "${MADE[@]}"; do
	printf 'package_release: %s (%s bytes)\n' "$z" "$(wc -c < "$z" | tr -d ' ')"
done
