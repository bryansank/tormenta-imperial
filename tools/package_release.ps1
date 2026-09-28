# Empaqueta builds ya exportadas en zips listos para dar a testers (version
# PowerShell de tools/package_release.sh; el porque y el contenido estan alli y en
# docs/19-exportar.md, "Distribucion"). No exporta nada.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 `
#     [-Exe RUTA] [-Apk RUTA] [-Out DIR] [-Version X.Y.Z] [-Only windows|android]
# Por defecto: -Exe build\windows\TormentaImperial.exe,
#              -Apk build\android\TormentaImperial-debug.apk, -Out dist,
#              version = config/version de project.godot.
# Las rutas relativas se resuelven desde la raiz del proyecto.
param(
	[string]$Exe = "build/windows/TormentaImperial.exe",
	[string]$Apk = "build/android/TormentaImperial-debug.apk",
	[string]$Out = "dist",
	[string]$Version = "",
	[ValidateSet("", "windows", "android")][string]$Only = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
function Resolve-FromRoot([string]$p) {
	if ([System.IO.Path]::IsPathRooted($p)) { return $p }
	return (Join-Path $root $p)
}
function Fail([string]$msg) {
	[Console]::Error.WriteLine("package_release: $msg")
	exit 1
}

$Exe = Resolve-FromRoot $Exe
$Apk = Resolve-FromRoot $Apk
$Out = Resolve-FromRoot $Out

if (-not $Version) {
	$m = Select-String -Path (Join-Path $root "project.godot") -Pattern '^config/version="(.*)"\s*$' | Select-Object -First 1
	if (-not $m) { Fail "no encuentro config/version en project.godot (usa -Version)" }
	$Version = $m.Matches[0].Groups[1].Value
}

# Sin licencias no hay zip: es justo lo que este script existe para evitar.
foreach ($f in @("LICENSE", "THIRD-PARTY-NOTICES.md", "licenses/GODOT-COPYRIGHT.txt",
		"tools/dist/LEEME-windows.txt", "tools/dist/LEEME-android.txt")) {
	if (-not (Test-Path -LiteralPath (Join-Path $root $f) -PathType Leaf)) { Fail "falta $f" }
}
$fontDir = Join-Path $root "assets/fonts"
$fontLicenses = @(Get-ChildItem -LiteralPath $fontDir -Filter *.txt -File)
if ($fontLicenses.Count -eq 0) { Fail "no hay licencias de fuentes en assets/fonts/" }
foreach ($font in Get-ChildItem -LiteralPath $fontDir -File | Where-Object { $_.Extension -in ".ttf", ".otf" }) {
	$family = $font.BaseName.Split("-")[0]
	if (-not ($fontLicenses | Where-Object { $_.Name -like "*$family*" })) {
		Fail "la fuente $($font.Name) no tiene su licencia al lado (assets/fonts/*$family*.txt)"
	}
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
# Texto para Windows en CRLF, sin BOM.
function Get-CrlfBytes([string]$path, [string]$version) {
	$text = [System.IO.File]::ReadAllText($path, $utf8)
	$text = $text.Replace("{{VERSION}}", $version) -replace "`r?`n", "`r`n"
	return $utf8.GetBytes($text)
}

function Add-Bytes($zip, [string]$name, [byte[]]$bytes) {
	$entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
	$s = $entry.Open()
	try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
}
function Add-File($zip, [string]$name, [string]$path) {
	[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $path, $name,
		[System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
}

function New-Package([string]$name, [string]$binary, [string]$binaryName, [string]$leeme) {
	$dest = Join-Path $Out "$name.zip"
	if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
	$zip = [System.IO.Compression.ZipFile]::Open($dest, [System.IO.Compression.ZipArchiveMode]::Create)
	try {
		# Nombres con "/": el Compress-Archive de PowerShell 5.1 los mete con "\".
		Add-Bytes $zip "$name/GODOT-COPYRIGHT.txt" (Get-CrlfBytes (Join-Path $root "licenses/GODOT-COPYRIGHT.txt") $Version)
		Add-Bytes $zip "$name/LEEME.txt" (Get-CrlfBytes (Join-Path $root $leeme) $Version)
		Add-Bytes $zip "$name/LICENSE.txt" (Get-CrlfBytes (Join-Path $root "LICENSE") $Version)
		Add-File $zip "$name/THIRD-PARTY-NOTICES.md" (Join-Path $root "THIRD-PARTY-NOTICES.md")
		Add-File $zip "$name/$binaryName" $binary
		foreach ($lic in $fontLicenses | Sort-Object Name) {
			Add-File $zip "$name/licenses/fonts/$($lic.Name)" $lic.FullName
		}
	} finally {
		$zip.Dispose()
	}
	return $dest
}

function Test-Magic([string]$path, [string]$magic) {
	$fs = [System.IO.File]::OpenRead($path)
	try {
		$b = New-Object byte[] 2
		[void]$fs.Read($b, 0, 2)
		return ([System.Text.Encoding]::ASCII.GetString($b) -eq $magic)
	} finally { $fs.Dispose() }
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$made = @()

if ($Only -ne "android") {
	if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { Fail "no existe el .exe: $Exe (exporta primero o pasa -Exe)" }
	if (-not (Test-Magic $Exe "MZ")) { Fail "$Exe no parece un ejecutable de Windows" }
	$made += New-Package "TormentaImperial-$Version-windows" $Exe "TormentaImperial.exe" "tools/dist/LEEME-windows.txt"
}
if ($Only -ne "windows") {
	if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { Fail "no existe el APK: $Apk (exporta primero o pasa -Apk)" }
	if (-not (Test-Magic $Apk "PK")) { Fail "$Apk no parece un APK" }
	$made += New-Package "TormentaImperial-$Version-android" $Apk "TormentaImperial-$Version.apk" "tools/dist/LEEME-android.txt"
}

foreach ($z in $made) {
	Write-Output ("package_release: {0} ({1} bytes)" -f $z, (Get-Item -LiteralPath $z).Length)
}
