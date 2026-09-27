# 19 — Exportar el juego a un .exe de Windows

Cómo sacar de este proyecto un `TormentaImperial.exe` que otra persona pueda
descargar y jugar, qué viaja dentro, qué se queda fuera y qué falta para publicarlo.

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
# 1. Importar (primera vez o tras tocar assets)
"$GODOT" --headless --path . --import

# 2. Tests (deben quedar en verde)
"$GODOT" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests

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

`BeckettRuntime` (el puente MCP de desarrollo, abre un socket local) ya no apunta al
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
Ahí viven `save_game.json`, `settings.cfg` y `logs/godot.log`, que es lo primero que
hay que pedir a quien reporte un fallo.

---

## 8. Distribuir

1. Comprimir `TormentaImperial.exe` en un zip (`TormentaImperial-0.9.0-windows.zip`,
   ~48 MB). Conviene añadir `LICENSE` y `THIRD-PARTY-NOTICES.md` al zip: las
   licencias de terceros (Godot, fuentes, audio) exigen acompañar el binario.
2. **itch.io:** crear el proyecto como "Downloadable", subir el zip marcado como
   Windows. Para publicar versiones sin la web, `butler`:
   `butler push TormentaImperial-0.9.0-windows.zip usuario/tormenta-imperial:windows --userversion 0.9.0`.
3. GitHub Releases también vale (adjuntar el zip a un tag), nunca dentro del repo.

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
| **Android** | Con trabajo | Plantillas incluidas; falta instalar JDK 17 + Android SDK, crear un keystore de release (secreto: fuera del repo) y un preset "Android". El juego ya tiene controles táctiles. Forward+ en móvil es pesado: probablemente Mobile renderer. Para Google Play, AAB firmado y cuenta de desarrollador. |
| **iOS** | No sin Mac | Requiere Xcode y cuenta de Apple Developer. |
