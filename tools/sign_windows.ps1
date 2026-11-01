# Firma el .exe exportado con signtool (Authenticode, SHA-256 y sello de tiempo) si
# hay un certificado de firma de codigo en el entorno. Sin certificado no hace nada:
# avisa y sale con 0, para que tools/package_release.ps1 -Sign funcione igual en una
# maquina sin certificado. Ver docs/19-exportar.md, "Firma de Windows".
#
# El certificado NUNCA va en el repo ni en un script: solo en variables de entorno
# de la sesion que firma.
#
#   TI_WINDOWS_SIGN_PFX          ruta a un .pfx/.p12 (certificado OV en fichero)
#   TI_WINDOWS_SIGN_PASSWORD     su contrasena (si el .pfx la tiene)
#   TI_WINDOWS_SIGN_THUMBPRINT   alternativa: huella SHA-1 de un certificado ya
#                                instalado en el almacen de Windows (token USB OV/EV)
#   TI_WINDOWS_SIGN_TIMESTAMP    servidor de sello de tiempo RFC 3161
#                                (por defecto http://timestamp.digicert.com)
#   TI_SIGNTOOL                  ruta a signtool.exe si no esta en el PATH ni en el
#                                Windows SDK
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tools\sign_windows.ps1 [-Exe RUTA] [-Required]
# Por defecto -Exe build\windows\TormentaImperial.exe. Con -Required, la falta de
# certificado es un error (exit 1) en vez de un aviso.
param(
	[string]$Exe = "build/windows/TormentaImperial.exe",
	[switch]$Required
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($Exe)) { $Exe = Join-Path $root $Exe }

function Fail([string]$msg) {
	[Console]::Error.WriteLine("sign_windows: $msg")
	exit 1
}

$pfx = $env:TI_WINDOWS_SIGN_PFX
$thumb = $env:TI_WINDOWS_SIGN_THUMBPRINT
if (-not $pfx -and -not $thumb) {
	if ($Required) { Fail "no hay certificado (TI_WINDOWS_SIGN_PFX o TI_WINDOWS_SIGN_THUMBPRINT)" }
	Write-Warning "sign_windows: sin certificado en el entorno; $Exe queda SIN FIRMAR (SmartScreen avisara)."
	exit 0
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { Fail "no existe el .exe: $Exe (exporta primero o pasa -Exe)" }
if ($pfx -and -not (Test-Path -LiteralPath $pfx -PathType Leaf)) { Fail "TI_WINDOWS_SIGN_PFX no apunta a un fichero" }

# signtool: TI_SIGNTOOL, el PATH o el Windows SDK mas reciente (x64).
$signtool = $env:TI_SIGNTOOL
if (-not $signtool) {
	$cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
	if ($cmd) { $signtool = $cmd.Source }
}
if (-not $signtool) {
	$kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
	if (Test-Path -LiteralPath $kits) {
		$found = Get-ChildItem -LiteralPath $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
			Where-Object { $_.FullName -match "\\x64\\" } | Sort-Object FullName -Descending | Select-Object -First 1
		if ($found) { $signtool = $found.FullName }
	}
}
if (-not $signtool -or -not (Test-Path -LiteralPath $signtool -PathType Leaf)) {
	Fail "no encuentro signtool.exe: instala el Windows SDK (componente 'Signing Tools') o pon TI_SIGNTOOL"
}

$timestamp = $env:TI_WINDOWS_SIGN_TIMESTAMP
if (-not $timestamp) { $timestamp = "http://timestamp.digicert.com" }

$signArgs = @("sign", "/fd", "sha256", "/tr", $timestamp, "/td", "sha256", "/d", "Tormenta Imperial")
if ($pfx) {
	$signArgs += @("/f", $pfx)
	if ($env:TI_WINDOWS_SIGN_PASSWORD) { $signArgs += @("/p", $env:TI_WINDOWS_SIGN_PASSWORD) }
} else {
	$signArgs += @("/sha1", $thumb)
}
$signArgs += $Exe

# No se imprime la linea de comandos: llevaria la contrasena.
Write-Output "sign_windows: firmando $Exe"
& $signtool @signArgs | Out-Host
if ($LASTEXITCODE -ne 0) { Fail "signtool sign fallo (codigo $LASTEXITCODE)" }

& $signtool verify /pa $Exe | Out-Host
if ($LASTEXITCODE -ne 0) { Fail "la firma no verifica (signtool verify /pa)" }

$sig = Get-AuthenticodeSignature -LiteralPath $Exe
Write-Output ("sign_windows: {0} firmado por {1}" -f $Exe, $sig.SignerCertificate.Subject)
exit 0
