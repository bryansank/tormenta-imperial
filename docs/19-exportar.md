# 19 — Exportar el juego: .exe de Windows y APK de Android

Cómo sacar de este proyecto un `TormentaImperial.exe` que otra persona pueda
descargar y jugar, qué viaja dentro, qué se queda fuera y qué falta para publicarlo.
Android (tableta primero) está en la sección 11; la lista de comprobación de una
publicación (itch.io y GitHub Releases), en la 12.

Medido el 2026-09-27 con Godot 4.7-stable mono en Windows 11 (RTX 3060, Vulkan).

---

## 1. Resumen

| Qué | Valor |
|---|---|
| Preset | `Windows Desktop` en `export_presets.cfg` (versionado, sin secretos) |
| Salida | `build/windows/TormentaImperial.exe` (un solo fichero, PCK embebido) |
| Tamaño | 119,7 MB el .exe (104 MB son la plantilla del motor, ~10 MB el juego); 48 MB en .zip |
| Contenido del PCK | 335 ficheros: escenas, scripts compilados, modelos, audio, texturas, fuentes |
| Tiempo de export | ~34 s |
| Arranque | la ventana aparece en ~1,3 s; partida nueva con tiempos reales |
| Errores en el log | ninguno |
| Requisitos del jugador | Windows 10/11 x64 y una GPU con Vulkan. **No** necesita .NET |

---

## 2. Plantillas de exportación

Godot no exporta sin las *export templates* de **exactamente** su misma versión.
Se leen con:

```bash
godot --version          # 4.7.stable.mono.official.5b4e0cb0f
```

La carpeta se llama como la parte `4.7.stable.mono` de esa cadena.

1. Descargar de la release oficial (solo `github.com/godotengine/godot` o `godotengine.org`):
   `https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_mono_export_templates.tpz`
   (1,2 GB, trae todas las plataformas).
2. Comprobar el hash contra `SHA512-SUMS.txt` de la misma release:
   ```powershell
   (Get-FileHash -Algorithm SHA512 Godot_v4.7-stable_mono_export_templates.tpz).Hash
   ```
3. El `.tpz` es un zip con una carpeta `templates/`. Su contenido va a:
   `%APPDATA%\Godot\export_templates\4.7.stable.mono\`
   (dentro debe quedar `version.txt` con `4.7.stable.mono` y los `windows_release_x86_64.exe`, etc.)

Desde el editor es lo mismo: *Editor → Administrar plantillas de exportación → Descargar e instalar*.

### ¿Mono o estándar?

El editor instalado es el **mono (.NET)**, así que usa plantillas mono. Probado: el
proyecto **no tiene C#** (ni `.csproj` ni `.cs`) y el export mono funciona igual,
sin generar la carpeta `data_TormentaImperial_*` de ensamblados y sin pedir .NET al
jugador. No hace falta cambiar nada para Windows.

Aun así, la recomendación a medio plazo es el **editor estándar 4.7-stable** (no .NET):

- es lo que corresponde a un proyecto 100 % GDScript (ver "Key Rule" en `CLAUDE.md`);
- es el único que exporta a **Web** (el .NET de Godot 4 no exporta a HTML5);
- sus plantillas son algo más ligeras y no arrastran el runtime de mono.

El cambio es solo de binario: el proyecto abre igual en los dos. Si se hace, hay
que instalar también `Godot_v4.7-stable_export_templates.tpz` (carpeta `4.7.stable`).

---

## 3. Construir el .exe paso a paso

Desde la raíz del proyecto, con `GODOT` apuntando al ejecutable de consola:

```bash
# 0. Si lo lanza un agente o un script: override.cfg con carpeta de usuario propia
#    (ver CLAUDE.md, "Running the Project"), y borrarlo al terminar.
# 1. Importar (primera vez o tras tocar assets)
"$GODOT" --headless --path . --import

# 2. Tests (deben quedar en verde). Siempre por el envoltorio: da a la suite su
#    propia carpeta de usuario y no toca la partida del jugador.
GODOT="$GODOT" tools/run_tests.sh

# 3. Exportar
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/TormentaImperial.exe
```

Desde el editor: *Proyecto → Exportar… → Windows Desktop → Exportar proyecto*
(desmarcar "Exportar con depuración").

`build/` está en `.gitignore`: **nunca** se versiona un exportado.

Nota: al exportar en headless el editor carga sus plugins, y Beckett abre su servidor
local un momento. Si hay otro editor abierto con Beckett en el mismo puerto, cerrar
uno de los dos antes de exportar.

### Ver qué viaja dentro

```bash
"$GODOT" --headless --path . --export-pack "Windows Desktop" /tmp/pack.zip
tar -tf /tmp/pack.zip
```

Con extensión `.zip` Godot escribe el paquete como zip, y se lista con cualquier herramienta.

---

## 4. El preset `Windows Desktop`

| Opción | Valor | Por qué |
|---|---|---|
| Plataforma / arquitectura | Windows, x86_64 | el 99 % de los PCs de juego |
| `binary_format/embed_pck` | `true` | un solo .exe, sin `.pck` al lado que el jugador pueda perder |
| `debug/export_console_wrapper` | `0` | no genera el `.console.exe` extra |
| `script_export_mode` | binario comprimido | scripts tokenizados, no texto plano |
| `application/*` | "Tormenta Imperial", "Bryan Key", © 2026 | metadatos que Windows enseña en Propiedades |
| `application/file_version` | vacío → `config/version` (0.9.0) | la versión vive en un solo sitio: `project.godot` |
| `application/icon` | vacío → `icon.svg` del proyecto | ver abajo |
| `export_path` | `build/windows/TormentaImperial.exe` | relativa: una absoluta filtraría la máquina de quien exporta |

**Icono y metadatos sin rcedit.** Godot 4.7 reescribe los recursos del .exe él mismo
(`application/modify_resources=true`): el icono sale de `icon.svg` y los campos de
versión, empresa y copyright aparecen en *Propiedades → Detalles*. `rcedit` ya no hace
falta. Si algún día se quiere un icono distinto al del proyecto, basta con un `.ico`
de 256 px en `application/icon`.

### Qué se excluye

```
tests/*, tools/*, docs/*, specs/*, reports/*,
addons/gdUnit4/*, addons/beckett/*,
.claude/*, .specify/*, .beckett/*, .cursor/*, .vscode/*,
.mcp.json, secret.json, .env*, build/*, *.md
```

Ojo con `.mcp.json`: Godot lo trata como recurso JSON y, sin esta línea, **se metía en
el PCK con el token local de Beckett**. Si alguien añade más ficheros locales con
credenciales en la raíz, hay que añadirlos aquí. `tests/build/test_export_guards.gd`
falla si desaparece cualquiera de estas exclusiones.

Los scripts de `addons/*` que tenían `class_name` siguen listados en
`.godot/global_script_class_cache.cfg`, pero como nada del juego los usa no dan error.

---

## 5. `dev_mode` en el exportado

`GameConfig.dev_mode` ya no es un valor escrito a mano:

| Dónde corre | `dev_mode` |
|---|---|
| Editor (F5), tests, sondas | `true` (feature tag `editor`) |
| Cualquier exportado, release o debug | `false` |
| Exportado con `TormentaImperial.exe -- --dev` | `true` |
| Editor con `godot --path . -- --no-dev` | `false` |

Con `false` todas las duraciones son las reales y desaparecen el botón de borrar
partida (`ResourceHUD`) y el de combate de prueba (`SkirmishPanel`), porque los dos
dependen de `dev_mode`. La primera línea del log lo dice:

```
[GameConfig] version 0.9.0, dev_mode=false
```

## 6. Beckett no viaja

`BeckettRuntime` (el puente MCP de desarrollo: `addons/beckett/runtime/mcp_runtime.gd`
se conecta como cliente a `127.0.0.1:8771`, el servidor MCP del editor, y ejecuta las
órdenes que le llegan; no es un simple socket abierto) ya no apunta al
addon: apunta a `scripts/services/BeckettGate.gd`, un portero que solo carga el
runtime del addon con `load()` cuando `OS.has_feature("editor")`. Se mantiene el
nombre del autoload a propósito, porque el plugin solo se registra si ese nombre no
existe. En el exportado el addon no está (excluido) y el portero se retira sin
tocar nada: cero errores en el log.

## 7. Dónde guarda el exportado

El exportado usa un directorio de usuario propio, distinto del editor:

| Build | Carpeta |
|---|---|
| Editor | `%APPDATA%\Godot\app_userdata\Tormenta Imperial\` |
| Exportado | `%APPDATA%\TormentaImperial\` |

Así las partidas de prueba (con tiempos de dev) y las reales no se pisan. Lo hacen
dos overrides con el feature tag `template` en `project.godot`
(`config/use_custom_user_dir.template`, `config/custom_user_dir_name.template`).
Ahí viven las partidas (`partidas/`), `settings.cfg` y `logs/`.

### El registro de errores (`logs/registro.txt`)

Lo primero que hay que pedir a quien reporte un fallo, y casi nunca hace falta
buscarlo: **☰ MENÚ → PARTIDA → Informar de un fallo** copia al portapapeles un
bloque corto (versión, sistema, vídeo, perfil, calidad, vista, idioma, modo/nivel,
era, velocidad y las últimas 40 líneas del registro) listo para pegar en WhatsApp o
en un issue. No se envía nada: el juego no usa la red para esto.

| Plataforma | Dónde está |
|---|---|
| Windows (exportado) | `%APPDATA%\TormentaImperial\logs\registro.txt` |
| Windows (editor) | `%APPDATA%\Godot\app_userdata\Tormenta Imperial\logs\registro.txt` |
| Android | almacenamiento interno de la app: `/data/user/0/com.bryankey.tormentaimperial/files/logs/registro.txt`. Sin root solo se lee desde el propio juego (el botón) o, con el APK de depuración, `adb shell run-as com.bryankey.tormentaimperial cat files/logs/registro.txt` |

- **Quién lo escribe:** `scripts/services/ErrorLog.gd`, un `Logger` propio que
  `GameConfig._ready()` engancha con `OS.add_logger()`. Recibe lo mismo que la
  consola: `print`, `push_error` / `push_warning`, errores de script (con el archivo
  y la línea del script cuando hay pila) y del motor.
- **Por qué uno propio y no solo `debug/file_logging`:** el log de archivo de Godot
  viene apagado en Android, no tiene tope por archivo (una sesión que repite un error
  lo hace crecer sin fin) y el juego no puede leer sus últimas líneas al día. El de
  Godot se deja como viene (`logs/godot*.log` en PC); el informe no lo necesita.
- **Tope:** 200 KB por archivo y dos rotaciones (`registro.1.txt`,
  `registro.2.txt`): ~600 KB como mucho.
- **Rendimiento:** nada por fotograma. Las líneas van a memoria y se escriben en
  bloque cada 3 s (un `Timer`), al cerrar y al pasar a segundo plano. Una línea
  repetida seguida se cuenta (`(x27)`), no se repite; con más de 600 líneas sin
  escribir se tiran las más viejas y se anota cuántas.
- **Al abrir** se recuperan en memoria las últimas líneas de la sesión anterior: si
  el juego se cerró de golpe, el informe del arranque siguiente las incluye.
- **Sin datos personales** (`scripts/services/BugReport.gd`): las rutas de la
  carpeta del usuario (`C:\Users\<nombre>`, `/home/<nombre>`, `/Users/<nombre>`)
  pasan a `~`, y el nombre de la colonia (el del país del jugador) a `<colonia>`.
  Tests: `tests/support/test_bug_report.gd`.

---

## 8. Distribución

El .exe y el APK no se reparten sueltos: la MIT de Godot, la Apache 2.0 de Special
Elite y la OFL de las otras fuentes exigen que su licencia acompañe al binario, y el
tester necesita saber cómo abrirlo. `tools/package_release.sh` (o `.ps1`, el mismo
resultado desde PowerShell) lo hace de una vez **a partir de builds ya exportadas**;
no exporta nada.

```bash
# Por defecto: build/windows/TormentaImperial.exe y build/android/TormentaImperial-debug.apk,
# versión de project.godot (config/version) y salida en dist/ (fuera de git).
bash tools/package_release.sh

# Con otras rutas, o solo una plataforma:
bash tools/package_release.sh --exe ruta/al.exe --apk ruta/al.apk --out ../tormenta-imperial-builds
bash tools/package_release.sh --only windows
```

```powershell
powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 -Exe ruta\al.exe -Apk ruta\al.apk -Out dist
```

Deja un zip por plataforma, cada uno con una carpeta dentro:

| Fichero | Windows (`TormentaImperial-<versión>-windows.zip`) | Android (`TormentaImperial-<versión>-android.zip`) |
|---|---|---|
| Binario | `TormentaImperial.exe` | `TormentaImperial-<versión>.apk` |
| `LEEME.txt` | requisitos, cómo abrirlo, SmartScreen, dónde se guarda (`%APPDATA%\TormentaImperial`), cómo desinstalar, controles, cómo reportar fallos, licencia y créditos; entero en español y en inglés | requisitos, sideload con "orígenes desconocidos", Play Protect, actualizar, partida, desinstalar, controles táctiles, fallos, licencia y créditos; entero en español y en inglés |
| `LICENSE.txt` | `LICENSE` del repo (PolyForm Strict 1.0.0 + derechos reservados) | igual |
| `THIRD-PARTY-NOTICES.md` | todo lo de terceros que viaja, con MIT, Apache 2.0 y OFL completas | igual |
| `GODOT-COPYRIGHT.txt` | los 101 componentes del motor (FreeType, HarfBuzz, Jolt...) con sus licencias completas | igual |
| `licenses/fonts/` | las cuatro licencias de `assets/fonts/` | igual |

Las plantillas de los LEEME están en `tools/dist/LEEME-{windows,android}.txt`
(`{{VERSION}}` se sustituye al empaquetar; salen en CRLF). No llevan ningún correo
personal: los fallos van a los issues de GitHub o a quien pasó el juego.

El script se niega a crear el zip si falta `LICENSE`, `THIRD-PARTY-NOTICES.md`,
`licenses/GODOT-COPYRIGHT.txt` o la licencia de alguna fuente, y
`tests/build/test_export_guards.gd` falla por lo mismo. Regla para fuentes nuevas:
la licencia va al lado, en un `.txt` cuyo nombre contenga la familia (lo que va antes
del primer `-` del nombre de la fuente: `SpecialElite-Regular.ttf` →
`LICENSE-SpecialElite.txt`), y la fuente se añade a `THIRD-PARTY-NOTICES.md` §3.

Medido el 2026-09-28 con las builds 0.9.0: 48,9 MB el zip de Windows (el .exe pesa
120,6 MB sin comprimir) y 39,4 MB el de Android (el APK ya va comprimido).

### Qué es de terceros y qué no

| Qué | Licencia | Dónde |
|---|---|---|
| Godot 4.7 y sus componentes | MIT; cada componente la suya | `THIRD-PARTY-NOTICES.md` §1, `licenses/GODOT-COPYRIGHT.txt` |
| Librerías Android del APK (AndroidX, Kotlin, kotlinx.coroutines, libc++) | Apache 2.0 | §2 |
| Fuentes (Special Elite, Caveat, Black Ops One, Rajdhani) | Apache 2.0 / OFL 1.1 | §3 y `assets/fonts/*.txt` |
| Música y efectos | CC0 (SRG774, Kenney) | §4 y `assets/CREDITS.md` |
| Textura `metal_plate` | CC0 (Poly Haven) | §5 |
| Modelos, iconos, logo, key art, textos | del autor, derechos reservados | §6 y `LICENSE` |
| gdUnit4, Beckett | MIT, pero **no viajan** (excluidos en los tres presets) | §7 |

**No viaja .NET.** El proyecto no tiene C#: el export de Windows no genera la carpeta
`data_TormentaImperial_*` ni ningún ensamblado, y el APK no contiene ninguna `.dll`.
La plantilla mono solo lleva el código de enlace de C# del propio Godot (MIT), sin
usar. Comprobado sobre las builds 0.9.0: en el .exe, `addons/gdUnit4` y
`addons/beckett` solo aparecen como nombres en la lista `editor_plugins/enabled` del
`project.binary`, sin ningún fichero suyo.

### Al cambiar de versión de Godot

`licenses/GODOT-COPYRIGHT.txt` sale del propio binario del motor. Hay que regenerarlo
con el Godot nuevo (no necesita importar el proyecto) y actualizar la versión y el
hash de `THIRD-PARTY-NOTICES.md` §1:

```bash
"$GODOT" --headless --path . -s tools/gen_godot_notices.gd -- "$PWD/licenses/GODOT-COPYRIGHT.txt"
```

### Dónde publicar

1. **Testers:** el zip tal cual, por el canal que sea. La licencia no deja que nadie
   lo vuelva a subir a otra página, y el LEEME lo dice.
2. **itch.io:** crear el proyecto como "Downloadable", subir el zip marcado como
   Windows (y el de Android como Android). Para publicar versiones sin la web, `butler`:
   `butler push TormentaImperial-0.9.0-windows.zip usuario/tormenta-imperial:windows --userversion 0.9.0`.
3. GitHub Releases también vale (adjuntar el zip a un tag), nunca dentro del repo.

El paso a paso de una publicación está en §12.

### SmartScreen y el aviso de "editor desconocido"

El .exe **no está firmado**. En la primera ejecución Windows enseña "Windows protegió
su PC"; el jugador tiene que pulsar *Más información → Ejecutar de todas formas*.
Algunos antivirus marcan de más los ejecutables de Godot sin firma. Opciones:

- decirlo en la página de descarga (lo habitual en itch.io para indies);
- firmar con un certificado de firma de código (OV o EV; EV quita el aviso antes)
  y activar `codesign/enable` en el preset con `signtool`;
- la reputación de SmartScreen también crece sola con descargas.

---

## 9. Límites conocidos

- Solo x86_64. ARM64 (Windows on ARM) existe en las plantillas pero no se ha probado.
- Requiere Vulkan (renderer Forward+). En GPUs muy viejas o máquinas virtuales sin
  Vulkan no arranca; habría que exportar con el renderer Compatibility (OpenGL) o
  activar el fallback a D3D12, y el look cambia.
- No hay pantalla de opciones de resolución más allá de pantalla completa (F11).
- Sin firma de código (ver arriba).
- El guardado en la nube (`CloudSaveManager`) sigue sin cablear: en el exportado solo
  existe la partida local.
- El smoke test es de arranque y un minuto de partida; no sustituye una partida entera
  jugada a mano con tiempos reales.

---

## 10. Otras plataformas

| Destino | ¿Posible hoy? | Qué haría falta |
|---|---|---|
| **Linux** (x86_64) | Sí | Preset "Linux" con las mismas exclusiones; las plantillas ya están instaladas. Probar en una distro real (Vulkan/Mesa). Distribuir como `.tar.gz` o en itch.io. |
| **macOS** | Con trabajo | Preset "macOS" (plantilla universal incluida). Para que Gatekeeper lo deje abrir hace falta firmar y **notarizar** con una cuenta de Apple Developer (99 USD/año) y, en la práctica, un Mac. Sin eso el jugador tiene que forzar la apertura. |
| **Web (HTML5)** | No con este editor | Godot 4 .NET **no exporta a Web**. Haría falta el editor estándar 4.7 y sus plantillas. Además: Forward+ no existe en Web (solo Compatibility/WebGL2), así que habría que revisar luces, niebla y materiales; `user://` pasa a IndexedDB; el audio necesita un clic del jugador antes de sonar; y para hilos hay que servir con cabeceras COOP/COEP (itch.io tiene la casilla "SharedArrayBuffer"). Es la vía de mayor alcance para una demo, pero es un port, no un clic. |
| **Android** | Sí (APK de depuración) | Preset "Android" listo: ver §11. Falta el keystore de release, el AAB y la cuenta de Google Play. |
| **iOS** | No sin Mac | Requiere Xcode y cuenta de Apple Developer. |

---

## 11. Android (tableta primero)

La tableta en apaisado es el objetivo principal en móvil; el teléfono, secundario.
Medido el 2026-09-27 con Godot 4.7-stable mono en Windows 11.

### 11.1 Resumen

| Qué | Valor |
|---|---|
| Preset | `Android` en `export_presets.cfg` (sin secretos); `Android QA (emulador)` para el emulador (11.8) |
| Salida | `build/android/TormentaImperial-debug.apk` |
| Tamaño | 38,9 MB el APK (73 MB son `libgodot_android.so` sin comprimir; ~10 MB el juego) |
| Paquete | `com.bryankey.tormentaimperial`, versionCode `900`, versionName `0.9.0` |
| SDK | minSdk 24 (Android 7), targetSdk 36 |
| ABI | `arm64-v8a` (todas las tabletas y teléfonos de los últimos años) |
| Orientación | apaisado con sensor (`userLandscape` en el manifiesto: gira 180° y respeta el bloqueo de rotación) |
| Permisos | ninguno |
| Renderer | Mobile (Vulkan) en Android; Forward+ sigue en PC |
| Tiempo de export | ~40-60 s |

### 11.2 ¿Mono o estándar?

Igual que en Windows: el editor mono exporta a Android sin `.csproj` y sin meter
ensamblados .NET en el APK. Lo único que se nota es una línea en el logcat al
arrancar, inocua: `E GODOT: Unable to load System.Security.Cryptography.Native.Android library`
(la plantilla mono intenta cargar su runtime y no lo encuentra, porque no hay C#).
Con el editor estándar desaparecería.

### 11.3 Herramientas (una vez por máquina, todo gratis y oficial)

Lo que pide la documentación de Godot 4.7:

| Pieza | Versión | De dónde |
|---|---|---|
| OpenJDK | 17 | Eclipse Temurin (`adoptium.net`), el zip portable vale |
| Android SDK command-line tools | latest | `developer.android.com/studio` → "Command line tools only" |
| platform-tools | 35.0.0 o más | `sdkmanager` |
| build-tools | 35.0.1 | `sdkmanager` |
| platform | android-35 | `sdkmanager` |
| NDK r28b + CMake 3.10.2 | — | **solo** para la build con Gradle (AAB); el APK precompilado no los usa |

Comprobar los SHA-256 que publica cada página antes de descomprimir. Con el SDK en
`%LOCALAPPDATA%\Android\Sdk` (el sitio por defecto de Android Studio):

```powershell
# cmdline-tools va en <sdk>\cmdline-tools\latest\
$env:JAVA_HOME = "<carpeta del JDK 17>"
$sm = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
& $sm --licenses                       # aceptar todas
& $sm "platform-tools" "build-tools;35.0.1" "platforms;android-35"
```

Después, en el editor: *Editor → Configuración del editor → Exportar → Android*:

- `Java SDK Path` → la carpeta del JDK 17 (la que contiene `bin\java.exe`);
- `Android SDK Path` → `%LOCALAPPDATA%\Android\Sdk`.

Viven en `%APPDATA%\Godot\editor_settings-4.7.tres`, **fuera del repositorio**. Si se
editan a mano, con todos los editores de Godot cerrados: cualquier editor abierto
(también uno headless de los tests) reescribe el fichero al salir y deshace el cambio.

### 11.4 Firmar: depuración y release

**Depuración.** Godot firma el APK de depuración con el keystore de
`export/android/debug_keystore` (también en la configuración del editor). Si no
existe, se crea con el `keytool` del JDK, fuera del repo:

```powershell
keytool -genkeypair -v -keystore "$env:APPDATA\Godot\keystores\debug.keystore" `
  -storepass android -alias androiddebugkey -keypass android `
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```

**Release.** Es la identidad de la app para siempre: Google Play no deja publicar una
actualización firmada con otra clave. Se crea **una vez**, se guarda con copia de
seguridad fuera del repo (gestor de contraseñas + copia offline) y nunca se versiona:

```powershell
keytool -genkeypair -v -keystore "D:\claves\tormenta-release.keystore" `
  -alias tormenta -keyalg RSA -keysize 2048 -validity 10000
```

`export_presets.cfg` es público, así que los campos `keystore/release*` se dejan
**vacíos**. Godot los lee de variables de entorno al exportar:

```powershell
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH     = "D:\claves\tormenta-release.keystore"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER     = "tormenta"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "<la contraseña>"
& $GODOT --headless --path . --export-release "Android" build/android/TormentaImperial.apk
```

(Existen también `GODOT_ANDROID_KEYSTORE_DEBUG_*` por si se quiere un keystore de
depuración propio en CI.) `tests/build/test_export_guards.gd` falla si alguien guarda
una ruta de keystore o una contraseña en el preset.

### 11.5 Exportar

```bash
"$GODOT" --headless --path . --import      # la primera vez, o tras tocar assets
mkdir -p build/android
"$GODOT" --headless --path . --export-debug "Android" build/android/TormentaImperial-debug.apk
```

Queda también un `.apk.idsig` al lado (firma v4 para instalación incremental); no
hace falta distribuirlo.

**Si el export no termina.** El plugin de Android arranca el servidor de `adb` y, si
lo arranca él, `adb` hereda la consola y el `_console.exe` se queda esperando aunque el
APK ya esté escrito. Arrancar `adb start-server` antes de exportar lo evita.

Para comprobar qué lleva dentro (`aapt2` está en `build-tools\35.0.1`):

```bash
aapt2 dump badging build/android/TormentaImperial-debug.apk   # paquete, versión, SDK, ABI, permisos
unzip -l build/android/TormentaImperial-debug.apk             # assets/ es el contenido del PCK
```

Verificado: 359 ficheros en `assets/`, ninguno de `addons/beckett`, `addons/gdUnit4`,
`tests/`, `tools/`, `docs/`, ni `.mcp.json`/`.env`. `BeckettGate.gdc` sí viaja (es el
portero, y se retira solo).

### 11.6 El preset `Android`

| Opción | Valor | Por qué |
|---|---|---|
| `package/unique_name` | `com.bryankey.tormentaimperial` | identificador en la tienda. Se puede cambiar **hasta la primera publicación**; después es para siempre |
| `version/code` | `900` | entero que Play exige creciente. Regla: `mayor*10000 + menor*100 + parche` (0.9.0 → 900, 1.0.0 → 10000). Subirlo a mano con cada release |
| `version/name` | vacío → `config/version` | la versión legible vive solo en `project.godot` |
| `gradle_build/use_gradle_build` | `false` | plantillas precompiladas: no hace falta NDK ni Gradle para un APK |
| `architectures/arm64-v8a` | `true` (el resto `false`) | armeabi-v7a solo sirve para tabletas muy viejas de 32 bits y suma ~25 MB; Play acepta solo-64 bits |
| `screen/immersive_mode` | `true` | sin barra de estado ni de navegación |
| `screen/support_small` | `false` | pantallas < 3" no tienen sitio para la UI |
| `permissions/*` | todos `false` | el juego no usa red, cámara ni almacenamiento externo |
| `launcher_icons/*` | vacío → `icon.svg` | Godot genera el icono y el icono adaptativo a partir del del proyecto |
| `keystore/*` | vacío | ver 11.4 |

Y en `project.godot` (solo afectan a móvil):

- `display/window/handheld/orientation=4` → apaisado con sensor;
- `rendering/renderer/rendering_method.mobile="mobile"` (explícito; Forward+ se queda
  en `rendering_method` para PC);
- `rendering/textures/vram_compression/import_etc2_astc=true`, sin el cual el export a
  Android se niega. Hoy todas las texturas del juego son sin pérdida, así que no cambia nada.

### 11.7 Instalar en una tableta

1. En la tableta: *Ajustes → Información → Número de compilación* siete veces para
   activar las opciones de desarrollador; activar **Depuración por USB**.
2. Conectar por USB, aceptar la huella del PC y:
   ```bash
   adb devices
   adb install -r build/android/TormentaImperial-debug.apk
   adb logcat -s godot        # el log del juego
   ```
3. Sin cable (*sideload*): copiar el `.apk` a la tableta y abrirlo desde el gestor de
   archivos; Android pide permitir "instalar apps de fuentes desconocidas" para esa app.

La partida se guarda en el almacenamiento interno de la app
(`/data/data/com.bryankey.tormentaimperial/files/`); `use_custom_user_dir` no aplica en
Android. Desinstalar la app borra la partida (`retain_data_on_uninstall=false`).

### 11.8 Lo que se vio en el emulador

Emulador oficial con un AVD *Pixel Tablet* (2560×1600, 320 dpi, Android 16, imagen
x86_64 con WHPX).

- **El APK arm64 arranca** gracias a la traducción ARM del emulador (≈60 s hasta el
  primer fotograma), pero la pantalla queda **negra**: el Vulkan del emulador falla al
  presentar (`ERROR: Couldn't present to Vulkan queue (VkResult error 5)`). Con un APK
  x86_64 nativo pasa lo mismo. Es el emulador, no el juego: el mismo renderer Mobile
  pinta bien en el PC (Vulkan real).
- Con una variante **solo para el emulador** (x86_64 + `command_line/extra_args=
  "--rendering-method gl_compatibility --rendering-driver opengl3"`; hoy es el preset
  versionado `Android QA (emulador)`, paquete `com.bryankey.tormentaimperial.qa`,
  salida `build/android/TormentaImperial-qa.apk`, el que usan los flujos de
  `qa/maestro/`) el
  juego arranca en ~15 s, enseña el menú de título, y los toques funcionan: *Nueva
  partida → Confirmar → Saltar* llevan a la isla con el tutorial y los controles
  táctiles en pantalla. Cero errores de script en el logcat.
- Bug encontrado y corregido: con la preferencia de pantalla completa por defecto
  (`false`) `GameConfig` pedía modo ventana al arrancar, y en Android eso vuelve a sacar
  las barras del sistema encima del juego. Ahora en móvil siempre es pantalla completa.
- Lo que se anotó entonces para la UI de tableta, ya resuelto
  ([21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md)):
  - ~~Franjas negras arriba y abajo con `keep_height`~~: el lienzo es
    `window/stretch/aspect="expand"`.
  - ~~Textos de ayuda con "WASD" y "la rueda del ratón" en táctil~~: los textos van
    por dispositivo (`Tr.ti`).
  - ~~El diálogo de "Nueva partida" con el tema de Godot~~: es `NewGameDialog`, con
    `UITheme` y el selector de modo.
  - ~~El *splash* de Godot~~: `application/boot_splash/image` es
    `res://assets/branding/logo.png`.

### 11.9 Renderer Mobile frente a Forward+

Probado en el PC con `--rendering-method mobile`, ventana y directorio de usuario
temporal: la isla, los modelos y la UI se ven igual. La única diferencia que avisa el
motor es que **el SSAO no existe en Mobile**
(`WARNING: Screen-space ambient occlusion (SSAO) is only available when using the
Forward+ or Compatibility renderers`), así que en Android las esquinas y la base de los
edificios quedan algo menos oscurecidas. No es un error; si molesta el aviso, se puede
apagar `ssao_enabled` en móvil. El MSAA 2x se mantiene. Falta medir rendimiento en una
tableta real de gama media, que es lo que decide si Mobile basta o hay que bajar a
Compatibility (OpenGL ES 3) en equipos sin Vulkan fiable.

### 11.10 Google Play

1. **Cuenta de desarrollador** (pago único de 25 USD). Las cuentas personales nuevas
   tienen que pasar una prueba cerrada con testers (hoy: 12 personas durante 14 días)
   antes de poder publicar en producción.
2. **AAB, no APK.** Play solo acepta Android App Bundle. Hace falta la build con Gradle:
   *Proyecto → Instalar plantilla de compilación de Android* (crea `android/build/`,
   que se versiona o se regenera), `gradle_build/use_gradle_build=true`,
   `gradle_build/export_format=1` (AAB) y el NDK r28b + CMake del cuadro de 11.3.
3. **Firma:** keystore de release (11.4) como *upload key*, con *Play App Signing*
   activado (Google guarda la clave final).
4. **targetSdk:** Play exige un nivel reciente cada año; la plantilla de 4.7 ya apunta a 36.
5. Ficha: icono 512×512, gráfico destacado 1024×500, capturas de tableta de 7" y 10",
   política de privacidad (URL; el juego no recoge datos, pero la ficha la pide),
   cuestionario de clasificación por edades y formulario de seguridad de datos.

### 11.11 Límites conocidos (Android)

- No probado aún en una tableta física; el emulador no pinta Vulkan (11.8).
- Solo arm64. Sin x86_64 no corre en Chromebooks x86 ni en emuladores sin traducción.
- Sin keystore de release ni AAB todavía: el APK de depuración solo sirve para probar.
- Sin guardado en la nube: la partida vive en la tableta y se pierde al desinstalar.
- La adaptación a tableta (stretch `expand`, perfiles de dispositivo, tamaños
  táctiles, colocación táctil, textos por dispositivo) ya está hecha
  ([21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md)); falta probarla en
  una tableta física.

---

## 12. Publicar una versión: lista de comprobación

Para cada versión que se reparte en itch.io o GitHub Releases. El juego se publica
gratis; si algún día se cobra, antes hay que resolver `docs/25-marco-legal.md` §7.

### 12.1 Antes de exportar

- [ ] **Textos y comunicación revisados contra `docs/25-marco-legal.md`** (§3 y §4,
      y la búsqueda de verbos de §10 en `Tr.gd`). Las notas de versión y la página de
      la tienda también pasan por ahí.
- [ ] **Versión en un solo sitio:** `config/version` en `project.godot` (por ejemplo
      `1.0.0`). De ahí salen la versión del .exe (*Propiedades → Detalles*), el
      `versionName` del APK, la primera línea del log y el nombre de los zips.
- [ ] **`version/code` en los dos presets de Android** (`Android` y `Android QA
      (emulador)`), con la regla de §11.6: `mayor*10000 + menor*100 + parche`
      (0.9.0 → 900, 1.0.0 → 10000). Tiene que crecer siempre: Android no instala
      encima un APK con un número menor.
- [ ] Copia limpia del repo en la versión exacta (un worktree en el commit que se
      publica) y `override.cfg` temporal con carpeta de usuario propia (§3).
- [ ] `--import` y **tests en verde** por el envoltorio (`tools/run_tests.sh`).

### 12.2 Exportar los dos

```bash
mkdir -p build/windows build/android
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/TormentaImperial.exe
adb start-server   # evita que el export de Android se quede colgado (§11.5)
# Con el keystore de release cargado en el entorno (12.5):
"$GODOT" --headless --path . --export-release "Android" build/android/TormentaImperial.apk
# Sin keystore de release (solo para testers): --export-debug ... TormentaImperial-debug.apk
```

- [ ] La primera línea de `logs/godot.log` del exportado dice `dev_mode=false` y la
      versión correcta.

### 12.3 Empaquetar

```bash
bash tools/package_release.sh --apk build/android/TormentaImperial.apk
# (sin --apk toma el de depuración, build/android/TormentaImperial-debug.apk)
```

- [ ] Salen `dist/TormentaImperial-<versión>-windows.zip` y `-android.zip`, cada uno
      con su `LEEME.txt`, `LICENSE.txt`, `THIRD-PARTY-NOTICES.md`,
      `GODOT-COPYRIGHT.txt` y `licenses/fonts/`. Si falta una licencia, el script no
      crea el zip (§8).
- [ ] Opcional: una suma de comprobación para quien quiera verificar la descarga:
      `sha256sum dist/*.zip > dist/SHA256SUMS.txt`.

### 12.4 Probar el zip en limpio

Se prueba **el zip**, no la carpeta `build/`: es lo que recibe el jugador.

- [ ] **Windows:** descomprimir en una carpeta nueva. Para ver la primera partida de
      un jugador nuevo, renombrar antes `%APPDATA%\TormentaImperial` (no borrarlo) y
      devolverle el nombre al terminar. Comprobar: el aviso de SmartScreen y *Más
      información → Ejecutar de todas formas*, el prólogo y el tutorial, unos minutos
      de partida, cerrar y volver a abrir con la partida guardada, F11 y el cambio
      de idioma.
- [ ] **Android:** instalar el APK del zip en una tableta real por sideload (no por
      `adb`), siguiendo el `LEEME.txt` tal cual. Comprobar: arranque, controles
      táctiles, colocar un edificio, salir y volver con la partida guardada. Con una
      versión nueva, instalarla **encima** de la anterior y ver que la partida sigue.
- [ ] Leer los dos `LEEME.txt` del zip: versión correcta y nada desfasado.

### 12.5 El keystore de release de Android

Un APK de depuración se firma con una clave genérica que cambia de una máquina a otra,
y Android no instala encima una versión firmada con otra clave: el jugador tendría que
desinstalar antes (y perder la partida). Por eso, **antes de la primera versión pública
del APK** conviene firmar ya con la clave de release, y no cambiarla nunca. Es la misma
clave que pedirá Google Play (§11.10).

1. **Crear la clave una vez** con el `keytool` del JDK 17, en una carpeta fuera del
   repositorio (comando en §11.4). `keytool` pide la contraseña por teclado: no se
   escribe en el comando.
2. **Guardarla con copia:** el `.keystore` y su contraseña en un gestor de
   contraseñas, más una copia offline. Sin ella no hay actualizaciones con la misma
   identidad.
3. **No tocar `export_presets.cfg`:** los campos `keystore/release*` se quedan vacíos
   (`tests/build/test_export_guards.gd` falla si no). Godot los lee del entorno al
   exportar:

   | Variable | Qué lleva |
   |---|---|
   | `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` | la ruta al `.keystore` |
   | `GODOT_ANDROID_KEYSTORE_RELEASE_USER` | el alias de la clave |
   | `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` | la contraseña |

4. **Cargarlas solo en la sesión que exporta**, sin que la contraseña quede en el
   historial ni en ningún fichero:

   ```powershell
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "<ruta al .keystore>"
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "<alias>"
   $p = Read-Host "Contraseña del keystore" -AsSecureString
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
       [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))
   & $GODOT --headless --path . --export-release "Android" build/android/TormentaImperial.apk
   Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
   ```

   ```bash
   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="<ruta al .keystore>"
   export GODOT_ANDROID_KEYSTORE_RELEASE_USER="<alias>"
   read -rsp "Contraseña del keystore: " GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD; echo
   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
   "$GODOT" --headless --path . --export-release "Android" build/android/TormentaImperial.apk
   unset GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
   ```

   Nunca en un `.env` dentro del repo, en un script versionado ni en las variables
   permanentes del sistema.
5. **Comprobar la firma** con `apksigner` (en `build-tools\35.0.1`):
   `apksigner verify --print-certs build/android/TormentaImperial.apk`. Tiene que
   salir tu certificado, no `CN=Android Debug`.

Si ya se repartió un APK de depuración, avisarlo en las notas de versión: el primer
APK firmado con la clave de release obliga a desinstalar el anterior una vez.

### 12.6 Subir

- [ ] **itch.io:** subir los dos zips (o con `butler`, §8) y marcar cada uno con su
      plataforma: Windows y Android. Nombre visible del archivo con la versión.
- [ ] **GitHub Releases:** crear el tag `v<versión>` en el commit exportado y una
      release con los dos zips (y `SHA256SUMS.txt` si se hizo). Los binarios van
      adjuntos a la release, nunca dentro del repositorio.
- [ ] En las dos páginas, el aviso de SmartScreen y el de "orígenes desconocidos".
- [ ] Probar la descarga desde la página publicada (otra cuenta o una ventana
      privada) y abrir el zip descargado.
- [ ] Poner el enlace de itch.io en la sección "Descargar y jugar" del `readme.md`.

### 12.7 Notas de versión

- [ ] Unas notas cortas por versión: qué hay de nuevo, qué se arregló, problemas
      conocidos y requisitos. Las mismas en itch.io (*devlog* o descripción) y en la
      release de GitHub, en español y en inglés.
- [ ] Mismo criterio que la página (`docs/25-marco-legal.md` §4): el juego es de
      gestión y estrategia; el combate se cuenta como defensa, nunca como gancho.
- [ ] No anunciar lo que no está: nada de nube, PvP ni multijugador mientras no exista.
- [ ] Al terminar: borrar `override.cfg` y el worktree de publicación.
