# Lanza la suite de gdUnit4 con una carpeta de usuario propia (version PowerShell
# de tools/run_tests.sh; el porque esta alli).
#
# Escribe un override.cfg temporal en la raiz del proyecto, lanza GdUnitCmdTool y
# lo quita en el finally, falle o no. Si ya habia un override.cfg, se aparta y se
# devuelve tal cual.
#
# Uso:
#   $env:GODOT = "C:\ruta\Godot_v4.7-stable_mono_win64_console.exe"
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -a tests/combat
# Variables: GODOT (por defecto godot en PATH), TI_TEST_USER_DIR (por defecto
# TormentaImperial_tests, queda en %APPDATA%\<nombre>).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$dirName = if ($env:TI_TEST_USER_DIR) { $env:TI_TEST_USER_DIR } else { "TormentaImperial_tests" }
$override = Join-Path $root "override.cfg"
$backup = Join-Path $root "override.cfg.run_tests.bak"
$mark = "; tools/run_tests: temporal, se borra al terminar"

if (@("", "TormentaImperial", "Tormenta Imperial") -contains $dirName) {
	Write-Error "run_tests: '$dirName' es la carpeta del jugador; elige otra en TI_TEST_USER_DIR"
	exit 2
}

$owned = $false
$status = 1
try {
	$ours = (Test-Path $override) -and ((Get-Content -Raw $override) -like "*$mark*")
	if (-not $ours) {
		if (Test-Path $override) {
			if (Test-Path $backup) {
				Write-Error "run_tests: ya existe $backup (una ejecucion anterior murio?); revisalo antes de seguir"
				exit 2
			}
			Move-Item $override $backup
		}
		$owned = $true
		$text = "$mark`n[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$dirName`"`n"
		[System.IO.File]::WriteAllText($override, $text, (New-Object System.Text.UTF8Encoding($false)))
	}
	$testArgs = if ($args.Count -gt 0) { $args } else { @("-a", "tests") }
	# Godot escribe avisos por stderr; con "Stop", PowerShell 5.1 los tomaria por
	# un error y cortaria la ejecucion a medias.
	$ErrorActionPreference = "Continue"
	& $godot --headless --path $root -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode @testArgs
	$status = $LASTEXITCODE
}
finally {
	if ($owned) {
		Remove-Item -Force -ErrorAction SilentlyContinue $override
		if (Test-Path $backup) { Move-Item -Force $backup $override }
	}
}
exit $status
