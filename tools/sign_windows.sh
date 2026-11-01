#!/usr/bin/env bash
# Firma el .exe exportado (Authenticode, SHA-256, sello de tiempo) si hay un
# certificado en el entorno; sin certificado avisa y sale con 0. Mismas variables
# que tools/sign_windows.ps1 (ver allí y docs/19-exportar.md, "Firma de Windows"):
#
#   TI_WINDOWS_SIGN_PFX, TI_WINDOWS_SIGN_PASSWORD, TI_WINDOWS_SIGN_THUMBPRINT,
#   TI_WINDOWS_SIGN_TIMESTAMP, TI_SIGNTOOL
#
# En Windows (Git Bash) delega en tools/sign_windows.ps1, que usa signtool. En Linux
# o macOS usa osslsigncode, que solo sabe firmar con un .pfx (no con un certificado
# del almacén de Windows ni con un token EV).
#
# Uso: tools/sign_windows.sh [--exe RUTA] [--required]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXE="build/windows/TormentaImperial.exe"
REQUIRED=0

die() { echo "sign_windows: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--exe) EXE="${2:?falta la ruta de --exe}"; shift 2 ;;
		--required) REQUIRED=1; shift ;;
		-h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) die "argumento desconocido: $1 (ver --help)" ;;
	esac
done
case "$EXE" in /*|[A-Za-z]:*) ;; *) EXE="$ROOT/$EXE" ;; esac

PFX="${TI_WINDOWS_SIGN_PFX:-}"
THUMB="${TI_WINDOWS_SIGN_THUMBPRINT:-}"
if [ -z "$PFX" ] && [ -z "$THUMB" ]; then
	[ "$REQUIRED" = 1 ] && die "no hay certificado (TI_WINDOWS_SIGN_PFX o TI_WINDOWS_SIGN_THUMBPRINT)"
	echo "sign_windows: AVISO: sin certificado en el entorno; $EXE queda SIN FIRMAR (SmartScreen avisará)." >&2
	exit 0
fi
[ -f "$EXE" ] || die "no existe el .exe: $EXE (exporta primero o pasa --exe)"

# Windows: signtool a través del script de PowerShell (mismo resultado).
if command -v powershell.exe >/dev/null 2>&1; then
	ps_args=(-Exe "$(cygpath -w "$EXE" 2>/dev/null || printf '%s' "$EXE")")
	[ "$REQUIRED" = 1 ] && ps_args+=(-Required)
	exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/tools/sign_windows.ps1" 2>/dev/null || printf '%s' "$ROOT/tools/sign_windows.ps1")" "${ps_args[@]}"
fi

# Linux / macOS: osslsigncode con el .pfx.
[ -n "$PFX" ] || die "fuera de Windows solo se firma con TI_WINDOWS_SIGN_PFX (osslsigncode)"
[ -f "$PFX" ] || die "TI_WINDOWS_SIGN_PFX no apunta a un fichero"
command -v osslsigncode >/dev/null 2>&1 || die "no encuentro osslsigncode (apt install osslsigncode / brew install osslsigncode)"
TS="${TI_WINDOWS_SIGN_TIMESTAMP:-http://timestamp.digicert.com}"
TMP="$EXE.signing"
args=(sign -h sha256 -ts "$TS" -n "Tormenta Imperial" -pkcs12 "$PFX" -in "$EXE" -out "$TMP")
# La contraseña por fichero temporal y no en la línea de comandos (se vería en ps).
if [ -n "${TI_WINDOWS_SIGN_PASSWORD:-}" ]; then
	PASSFILE="$(mktemp)"; trap 'rm -f "$PASSFILE" "$TMP"' EXIT
	printf '%s' "$TI_WINDOWS_SIGN_PASSWORD" > "$PASSFILE"
	args+=(-readpass "$PASSFILE")
else
	trap 'rm -f "$TMP"' EXIT
fi
echo "sign_windows: firmando $EXE"
osslsigncode "${args[@]}" >/dev/null || die "osslsigncode sign falló"
mv -f "$TMP" "$EXE"
# Sin un almacén de CAs de Windows la cadena puede no validar aquí: solo se avisa.
# La comprobación que cuenta es la de Windows (Propiedades → Firmas digitales).
osslsigncode verify -in "$EXE" >/dev/null 2>&1 \
	|| echo "sign_windows: AVISO: osslsigncode verify no valida la cadena; compruébala en Windows" >&2
echo "sign_windows: $EXE firmado"
