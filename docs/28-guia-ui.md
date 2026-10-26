# 28 · Guía de estilo de la interfaz (rediseño 2026-10)

Bryan: *"las interfaces se ven demasiado feas, la fuente, los textos muy feos y
sobrecargados, los botones no se entienden bien"*, *"en teléfonos pequeños se ve
feo y sobrecargado"* y *"las alertas se sobreponen a todo"*. Esta guía es la
fase 1 del rediseño: el estilo nuevo, decidido y probado en cinco pantallas
clave con maquetas. La fase 2 rehace todas las pantallas con ella.

- Código: `scripts/ui/CartoonTheme.gd` (estilo, tokens, piezas),
  `scripts/ui/CartoonIcon.gd` (iconos dibujados), el interruptor en
  `scripts/ui/UITheme.gd` (`UITheme.use_style()`).
- Maquetas: `tools/ui_mockup_probe.gd` → `docs/media/dev/ui_mockups/`
  (hoja de comparación: `docs/media/dev/ui_mockups/index.html`).
- Tests: `tests/ui/test_cartoon_theme.gd`.

## 0. Principios

1. **El mapa es el protagonista.** Cuanta menos interfaz y menos texto en
   pantalla, mejor. Nada fijo que no haga falta; los paneles solo existen
   mientras están abiertos.
2. **Icono antes que palabra**, siempre que el icono se entienda solo. La
   palabra va debajo (PC) o al mantener pulsado (teléfono).
3. **Una frase como mucho** por tarjeta o panel. El detalle, al tocar o al
   mantener pulsado (globo de ayuda, §11).
4. **Horizontal.** El juego se diseña y se juega apaisado: teléfono pequeño
   (640×360 y 800×360 lógicos), tablet y PC. Vertical es solo una opción de
   Ajustes (§4.3).
5. **Teléfono primero.** Cada pantalla se diseña para 640×360 y luego se
   escala hacia arriba, nunca al revés.
6. **Sin animación.** Todo aparece y desaparece al instante. Los estados
   (encima, pulsado) cambian el estilo, nunca con un `Tween`.
7. **Caricatura limpia, de juguete.** Paneles redondeados con borde grueso,
   colores vivos y claros, botones pastilla grandes, letra redonda y gruesa.
   Casa con la isla de maqueta y con los instructores (Capitana Remache,
   Sargento Bombarda). Referencia de estilo: Empires & Allies; **nunca** sus
   assets.

## 1. Decisiones de Bryan (2026-10-18)

| Tema | Decisión |
|---|---|
| Fuente | **Baloo 2** (títulos, botones, cifras) + **Nunito Sans** (texto). |
| Fondo de paneles | **Mixto**: HUD oscuro y fino sobre el mapa (`#1a2531` al 90 %, texto claro); ventanas grandes claras crema (`#fff6e3`, borde marrón `#7a5634` de 4 px, radio 22 px, sombra dura 0 4 px 0). |
| Menú | **Barra de abajo**: CONSTRUIR verde grande en el centro; a los lados botones redondos con icono y nombre debajo: Ejército, Misiones (con punto rojo), Mercado, Investigar, Ayuda. ☰ arriba a la derecha solo para Ajustes / Partidas / Salir. |
| Animación | Ninguna. |
| Texto | Icono + número, una frase, detalle al mantener pulsado. |
| Botones | Por intención: verde = acción principal, azul = abrir, ámbar = avisar / reparar, rojo = derribar / cerrar, gris = no se puede (con el porqué debajo). |
| Orientación | Horizontal siempre; vertical solo si se elige en Ajustes. |

## 2. Paleta

Sale de la de `docs/24-paleta.md`: los mismos significados, más luz y más
saturación. Los colores son tokens de `CartoonTheme` (`sem()` para los
semánticos, `c(role, KEY)` para los de superficie).

### 2.1 Semánticos (los mismos en las dos superficies)

| Token | Hex | Antes (docs/24) | Uso |
|---|---|---|---|
| `ACCENT` | `#f5b31c` | Latón `#C49629` | Lo elegido, la cinta de la ficha, estrellas, deslizadores. |
| `POSITIVE` | `#37a847` | `#4A8C40` | Acción principal (CONSTRUIR, MEJORAR, ¡AL ATAQUE!), lo bueno, tu bando. |
| `DANGER` | `#e0453a` | `#8C3B29` | Derribar, cerrar, el enemigo, lo que falta. |
| `WARNING` | `#ff8c1a` | `#CC8721` | Avisar, reparar, falta algo pronto. |
| `INFO` | `#2a88d8` | `#4A6B8C` | Abrir (los redondos de la barra), ayuda, pestaña de Ajustes. |

### 2.2 Superficies

| Clave | Ventana (clara) | HUD (oscura) | Uso |
|---|---|---|---|
| `BG` | `#fff6e3` | `#1a2531` (90 %) | Fondo de la ventana / de las fichas del HUD. |
| `CARD` | `#fffcf4` | `#26364a` | Tarjetas dentro de una ventana. |
| `CARD_ALT` | `#f7e7c4` | `#34495f` | Pestañas sin elegir, tarjetas bloqueadas. |
| `WELL` | `#ecd9b2` | `#152130` | Huecos hundidos: fondo de costes, carril de barras y deslizadores, miniaturas. |
| `BORDER` | `#7a5634` | `#f5b31c` | Borde de ventana (4 px). |
| `CARD_BORDER` | `#a07a52` | `#5b7898` | Borde de tarjeta (3 px) y del HUD fino (2 px). |
| `TEXT` | `#2e2218` | `#fff5e1` | Texto. |
| `TEXT_DIM` | `#6a543c` | `#bdd0e2` | Texto secundario (el nombre bajo una cifra). |
| `NEUTRAL` | `#fffcf4` | `#44607f` | Botón secundario. |
| Tinta `INK` | `#1f170f` | — | Contorno de iconos y botones, contorno del texto blanco. La misma tinta que los instructores. |

Contraste medido (test): `TEXT` ≥ 4,5:1 (7:1 en alto contraste) y `TEXT_DIM`
≥ 4,5:1 sobre las dos superficies, en las tres paletas.

### 2.3 Variantes que se conservan

- **Daltonismo** (`red_green`, `tritan`): cambian solo los semánticos
  (`_SEMANTIC_PALETTES`, los mismos tonos Okabe-Ito que docs/24). Todo lo demás
  se deriva y los iconos tienen forma propia, así que nada depende solo del color.
- **Alto contraste**: ventana blanca pura con tinta negra, HUD casi negro con
  texto blanco, bordes +1 px, velo más opaco (`_SURF_HC`).
- **Opacidad de paneles** (Ajustes): solo transparenta el HUD y las ventanas
  oscuras; las ventanas claras van opacas (la crema translúcida sobre el mapa se
  ve sucia).

### 2.4 Las otras dos superficies (descartadas, siguen seleccionables)

`CartoonTheme.surface = "light"` (todo crema, también el HUD) y `"dark"` (todo
pizarra con borde de latón). Capturas en la hoja de comparación.

## 3. Tipografía

| Pareja | Títulos / botones / cifras | Texto | Licencia |
|---|---|---|---|
| **B (elegida)** | Baloo 2, peso 800 (variable) | Nunito Sans, 650 / 850 | OFL 1.1 |
| A | Lilita One | Nunito, 700 / 900 | OFL 1.1 |
| C | Fredoka, 600 | Inter, 550 / 750 | OFL 1.1 |

Todas de `github.com/google/fonts` (`ofl/`), en `assets/fonts/<familia>/` con
su `OFL.txt`, anotadas en `THIRD-PARTY-NOTICES.md` §3. Todas tienen ñ, tildes,
¿ y ¡. A y C se borrarán cuando aterrice la fase 2 (solo la elegida se queda en
el paquete). `tools/package_release.*` mete cada `OFL.txt` de carpeta en
`licenses/fonts/OFL-<familia>.txt`.

### 3.1 Tamaños (px del lienzo)

| Nivel | Fuente | PC / tablet | Teléfono | Suelo teléfono | Uso |
|---|---|---|---|---|---|
| `display` | Baloo 2 | 34 | 22 | 20 | Cinta del título de ventana, CONSTRUIR de la barra (PC). |
| `title` | Baloo 2 | 26 | 19 | 17 | Nombre del edificio, de la misión. |
| `button` | Baloo 2 | 22 | 17 | 16 | Texto de botones y pestañas, nombres de fila. |
| `number` | Baloo 2 | 22 | 17 | 16 | Cifras (recursos, costes, contadores). |
| `body` | Nunito Sans | 18 | 15 | 14 | La frase de una tarjeta, globos de ayuda, avisos (PC). |
| `small` | Nunito Sans negrita | 15 | 13 | 12 | El nombre bajo una cifra o un icono. |

- En tablet y PC el lienzo ya escala con `DeviceProfile`; en teléfono el lienzo
  es de ~360 de alto (§4) y los números de la columna "Teléfono" son dp.
- El texto "grande / enorme" de Ajustes multiplica todo (`UITheme.text_scale`);
  el suelo nunca se cruza hacia abajo.
- Mayúsculas solo en botones de acción (CONSTRUIR, MEJORAR, HACER, ¡AL ATAQUE!)
  y en la cinta del título. Todo lo demás en minúscula normal.
- Sin contorno en el texto de cuerpo. Contorno de tinta (≈ 30 % del tamaño)
  solo en texto blanco sobre color (botones, cintas) o directamente sobre el mapa
  (los nombres bajo los redondos de la barra).

## 4. Lienzos, escala y orientación

### 4.1 Teléfono primero

Lienzos de diseño: **640×360** (teléfono pequeño, 360 dp de alto), **800×360**
(teléfono ancho), tablet y **1280×720** (PC). `CartoonTheme.phone` (lienzo de
menos de 450 de alto) cambia letras, botones y disposiciones.

En teléfono:

- HUD aún más reducido: **4 cifras** visibles (oro, madera, acero y libres; 5 a
  partir de 780 de ancho con comida). El resto, al tocar la ficha de recursos.
- Barra de abajo **solo iconos** (el nombre al mantener).
- Ventanas **a pantalla completa**, una columna (o dos bloques lado a lado
  cuando los dos se tienen que ver a la vez, como misión y tropa).
- Ningún botón por debajo de **48 dp** de lado (`CartoonTheme.TOUCH_MIN`,
  `CartoonTheme.h()`).

### 4.2 Hallazgo para la fase 2: el lienzo del teléfono es demasiado grande

Hoy `DeviceProfile` no deja que el lienzo baje de **540 de alto**
(`MIN_LOGICAL_HEIGHT`) y el perfil teléfono usa escala 1,3 sobre 720: un
teléfono de 360 dp dibuja un lienzo de ~554 de alto. Todo sale a ~0,65 de su
tamaño físico: el cuerpo de 17 px se ve como 11 dp. **Es la causa principal de
"en teléfonos pequeños se ve feo y sobrecargado".** Fase 2: en el perfil
teléfono, el lienzo debe seguir a los dp reales (alto lógico ≈ alto en dp,
entre 360 y 540), y las pantallas se maquetan como en estas maquetas.
La sonda fuerza los lienzos de teléfono a mano por eso.

### 4.3 Orientación

Horizontal de serie. **Ajustes → Pantalla (Interfaz) → Orientación:
Horizontal (recomendado) / Vertical**: `GameConfig.ui_orientation`
(`[ui] orientation` en `settings.cfg`), aplicada con
`DisplayServer.screen_set_orientation()` (sensor horizontal o sensor vertical)
solo en Android/iOS. En vertical basta con que funcione: no se maqueta.

## 5. Botones

| Clase (`kind`) | Color | Para | Ejemplos |
|---|---|---|---|
| `primary` | verde `POSITIVE` | La acción principal de la pantalla. Una por pantalla. | CONSTRUIR, MEJORAR, HACER, ¡AL ATAQUE! |
| `open` | azul `INFO` | Abrir otra pantalla. | Ejército, Misiones, Mercado, Investigar, Ayuda; "+" de tropa. |
| `warn` | ámbar `WARNING` | Avisar, reparar. | REPARAR. |
| `danger` | rojo `DANGER` | Derribar, cerrar, quitar. | Derribar (solo icono), ✕. |
| `secondary` | crema / pizarra | Lo demás. | MOVER, "−" de tropa, opción no elegida. |
| `disabled` | gris | No se puede. **Siempre con el porqué escrito debajo o al lado** ("Falta Almacén", "Era 3"). | — |

- **Pastilla** (`pill_button`): radio = medio alto, borde de tinta 3 px y un
  **labio** de 5 px más grueso abajo (botón de juguete). Pulsado: el labio baja
  a 1 px y el contenido baja con él. Encima: +12 % de luz.
- Contenido: **[icono] PALABRA**, 1-2 palabras. Solo icono cuando el icono es
  inequívoco (derribar, cerrar, +, −) — el nombre sale al mantener.
- Altos: grande 64 (teléfono 52), normal 52 (48), pequeño 44 (48).
- **Redondo** (`round_button`): barra de abajo (64 PC, 48 teléfono) y ☰ (54 /
  48); el nombre debajo en blanco con contorno (PC).
- Foco de teclado: anillo de latón de 3 px.

## 6. Ventanas y tarjetas

- **Ventana** (`CartoonTheme.window()`): crema, borde 4 px `#7a5634`, radio 22,
  sombra dura (desplazada 5 px, sin desenfoque). **Cinta** con el título encima
  del borde superior, centrada (color de la pantalla: verde CONSTRUIR, rojo
  MISIONES, azul AJUSTES, latón la ficha). **✕** roja redonda en la esquina
  superior derecha, montada sobre el borde.
- Detrás de una ventana, un **velo** oscuro al 42 % sobre el mapa (no en la
  ficha de edificio, que es un panel lateral para que el edificio se siga viendo).
- PC: ventana centrada con un tope de tamaño (≈ 1180×650 la más grande; las de
  poco contenido, más bajas). Teléfono: a pantalla completa con 6 px de margen.
- **Tarjeta**: `CARD`, borde 3 px, radio 18; elegida = borde de latón de 4 px
  y halo; bloqueada = `CARD_ALT`, miniatura a media luz y candado + motivo.
- **Huecos** (`WELL`): fondo de miniaturas, costes y barras.
- Espaciado: 4 / 8 / 12 / 16 / 24. Margen interior de ventana 18 (teléfono 10),
  de tarjeta 12 (teléfono 3-8), separación entre tarjetas 10.

## 7. Pestañas y controles

- **Pestaña** (`tab`): la elegida, rellena de color con labio y texto blanco;
  las demás, planas en `CARD_ALT` con texto tenue. En teléfono, las no elegidas
  solo con icono (o carril vertical de iconos a la izquierda).
- **Selector** (`segmented`): 2-4 pastillas en fila; la elegida azul. Sustituye
  a los desplegables.
- **Deslizador** (`slider`): carril de 14 px, relleno de latón, bolita blanca de
  34 px con tinta. Valor numérico a la derecha.
- **Interruptor** (`switch`): carril pastilla 76×40, verde encendido, bolita
  blanca.
- **Barra** (`progress`): redonda, con borde; color por significado.

## 8. Iconos

- **Interfaz** (`CartoonIcon`, 34 glifos: construir, ejército, misiones,
  mercado, investigar, ayuda, menú, ajustes, mejorar, mover, derribar, cerrar,
  candado, estrella, reloj, sonido, música, pantalla, controles, accesibilidad,
  partida, ancla, avión, tanque, ataque rápido, check, tormenta, sol, +, −,
  flechas, retirar trabajadores, llave inglesa): dibujados con `_draw`, formas
  gordas con contorno de tinta, sin imágenes.
- **Recursos y unidades**: los PNG de siempre (`UITheme.icon_texture`,
  `unit_icon`), las unidades en blanco dentro de un disco de su bando.
- Tamaños: 20-24 en costes y avisos, 26-34 en fichas de cifra, ≈ 58 % del
  diámetro en botones redondos, 56 % del alto en pastillas.

## 9. Reglas de texto

1. **Icono + número** antes que una frase ("[madera] 860", no "Madera: 860").
2. **Una frase como mucho** por tarjeta o panel, de ≤ 8 palabras. Si necesita
   más, va al globo de ayuda.
3. **Botones: 1-2 palabras**, en infinitivo o imperativo corto.
4. Nombres de pantalla y de botón de una palabra (CONSTRUIR, MISIONES).
5. Lo que no se puede: **el porqué en 2-3 palabras** al lado ("Falta Almacén").
6. Sin "Pulsa aquí para…", sin repetir lo que dice el icono.

| Antes | Después |
|---|---|
| "Corta madera del bosque de al lado. Casi todo se construye con madera." | "Corta madera del bosque de al lado." (+ globo: "Madera: la usan casi todos los edificios.") |
| "Almacenamiento: 2650/3200" | barra fina bajo los recursos; "Almacén: 2.650 de 3.200" al mantener |
| "No hay camino libre hasta la carretera del Núcleo: deja un paso o pon carretera a mano." | "Sin carretera" + resaltar dónde |
| "Fabrica 5 de Tablones en el Aserradero" + "Lo siguiente lo pide. Selecciona el edificio y elige el proceso." | Línea del siguiente paso: [cara de la Capitana] "Haz tablones →" |
| "Demoler" | [bomba] (rojo, solo icono; "Derribar" al mantener) |
| "Soldados, cañones y tanques contra la Regencia en tierra firme. Se abre con el Cuartel." | Pestaña [tanque] "Tierra"; el resto al mantener |
| "Campaña de Tierra · 3 de 6 misiones · Jefe: el Coronel de Hierro" | Recorrido de 6 puntos (✓ ✓ ★ 4 5 [jefe]) + "3 de 6" |
| "¡A LA MISIÓN!" | "¡AL ATAQUE!" |

## 10. Avisos

Solo el **estilo**; la cola y la colocación son de `NotificationPanel` (otro
frente de trabajo, llega por merge desde la 1.0). Pieza: `CartoonTheme.notice()`.

- **Un único sitio**: columna en el borde izquierdo, bajo los recursos. Nunca
  en el centro de la pantalla.
- **Máximo 2 visibles**; el resto espera en cola.
- **Icono + una frase** (≤ 5 palabras) + **✕**. Franja izquierda del color del
  tipo (verde bueno, ámbar aviso, rojo peligro, azul información).
- **Se cierra solo** (unos segundos) y con la ✕. En teléfono, tocar el aviso
  entero lo cierra (la ✕ dibujada es pequeña).
- **Repetidos agrupados**: una pastilla "×3", no tres avisos.
- **Nunca encima de una ventana abierta**: esperan a que se cierre. Un peligro
  inmediato (ataque, Tormenta) sale pequeño, en la misma columna.
- Sin animación de entrada ni salida.

## 11. Mantener pulsado (globo de ayuda)

Todo lo que se quitó de la pantalla vive aquí: `tooltip_text` + `TouchTooltip`
(mantener 0,5 s con el dedo; pasar el ratón en PC). Estilo `tooltip_bubble()`:
tinta oscura `#2e2218`, borde de latón 2 px, radio 14, texto claro de cuerpo,
230 px de ancho como mucho (190 en teléfono), con piquito hacia lo que explica.
Igual en las tres superficies.

## 12. HUD mínimo: qué queda fijo y qué sale

**Fijo** (arriba a la izquierda) recursos; (arriba a la derecha) rango + ☰,
y debajo la Tormenta como un icono; (abajo) la barra; la columna de avisos
cuando hay alguno; la línea del siguiente paso.

| Elemento de hoy | En el rediseño |
|---|---|
| Fila de recursos con palabras + fila de materiales | Icono + cifra (+ nombre pequeño en PC); teléfono: 4 cifras, el resto y los materiales al tocar. |
| Barra de almacén con "usado/tope" | Barra fina de 8 px (PC); el número al mantener. Teléfono: fuera. |
| Trabajadores y moral como fichas | "Libres" queda; moral solo en PC (teléfono: al tocar recursos). |
| StormHUD (color + icono + texto de fase) | Solo el icono redondo (sol / nube); la fase al mantener. |
| ¿QUÉ HACER? (tarjeta) | **Una línea plegable** con la cara de la Capitana: "Haz una Casa →". Desde 2026-10-19 (docs/23 §2.9): el objetivo y el paso de ahora, "Construye un Cuartel · Fabrica tablones 6/10"; al abrirla, el objetivo y 2-4 pasos ✓/●/○ que se tocan. |
| Toasts sueltos | Columna de avisos (§10). |
| Insignia de rango con título, barra y bandera | PC igual pero compacta; teléfono: bandera + número + barra. |
| Botón MISIONES suelto y entradas de ☰ (Ejército, Misiones, Mercado, Investigar) | **Barra de abajo**. Mercado e Investigar abren su edificio; sin él, gris con el porqué. |
| ☰ con COLONIA y PARTIDA | ☰ solo Ajustes / Partidas / Salir. |
| Botón de velocidad x1 / x2 | Fuera del HUD fijo: propuesta, dentro de ☰ (pendiente de Bryan). |
| Controles en pantalla (cruceta, zoom, girar) | Teléfono: apagados de serie (los gestos bastan); queda "cancelar" mientras se coloca. |
| Globos de ayuda flotantes (HelperPanel) | Apagados de serie; se abren desde Ayuda. |
| Busto grande de los instructores | Solo en tutorial y partes; en el HUD, la cara pequeña de la línea del siguiente paso. |

## 13. Cómo se activa (desarrollo)

- Código: `UITheme.use_style("cartoon", "mixed", "baloo_nunitosans")`; vuelta:
  `UITheme.use_style("classic")`. **Desde la fase 2 (rama `feat/ui2-hud`) de
  serie es `UITheme.STYLE_DEFAULT = "cartoon"`**; el clásico queda como respaldo
  interno.
- Línea de comandos: `godot --path . -- --ui-style=classic` (vuelta al viejo),
  `--ui-font=lilita_nunito --ui-surface=light` (las otras opciones).
- Activado, los tokens de `UITheme` se reescriben (`CartoonTheme.legacy_tokens()`)
  y las factorías de panel, botón, tarjeta del HUD, tooltip y letras pasan al
  estilo nuevo, así que los paneles que aún no se rehicieron lo siguen a grandes
  rasgos; `readable()` oscurece en vez de aclarar sobre fondo claro.
- Maquetas: `godot --path . -s tools/ui_mockup_probe.gd` con un `override.cfg`
  propio (se niega a correr en la carpeta del jugador). `-- --only=phone640`
  para un solo lienzo. Las pantallas de maqueta (`tools/ui_mockup/mock_screens.gd`)
  usan nombres, iconos, costes y miniaturas 3D reales, pero no están cableadas a
  los servicios.

## 14. Fase 2 (después de esta aprobación)

1. Cambiar `DeviceProfile` para que el lienzo del teléfono siga a los dp (§4.2).
2. Rehacer cada pantalla con `CartoonTheme` (HUD, avisos, CONSTRUIR, ficha,
   Ejército, Misiones, combate, menús, Ajustes, Ayuda, tutorial, partes), con
   textos nuevos en `Tr.gd` (ES/EN) según §9.
3. Barra de abajo y ☰ reducido (§12); decidir dónde van velocidad y Encargos.
4. Pasar `STYLE_DEFAULT` a `"cartoon"` y borrar las fuentes y el estilo viejo
   que ya no se usen (Black Ops One, Rajdhani, las parejas A y C).

## 15. Fase 2: lo implementado del HUD (rama `feat/ui2-hud`, 2026-10-18)

Detalle técnico en `docs/21-interfaz-y-dispositivos.md` §1 (lienzo del teléfono)
y §15 (HUD). Resumen frente a §14:

| Punto | Estado |
|---|---|
| 1. Lienzo del teléfono | **Hecho.** `DeviceProfile.phone_content_scale_for()`: alto lógico = alto en dp (360-540) en apaisado. Un teléfono de 360 dp pasa de un lienzo de ~554 de alto a **360** (todo a su tamaño físico, ×1,54). `CartoonTheme.phone` se enciende solo con lienzos de < 450 de lado corto. Escala del perfil Móvil 100 % y texto normal |
| 2. HUD y avisos con `CartoonTheme` | **Hecho** (recursos, rango, Tormenta, ¿QUÉ HACER?, avisos, controles en pantalla, ☰). El resto de pantallas, en sus ramas (CONSTRUIR/ficha/Mercado/Investigar; Ejército/Misiones/combate; Ajustes/Ayuda/tutorial/menús) |
| 3. Barra de abajo y ☰ | **Hecho.** `BottomBar` (Ejército, Misiones, [CONSTRUIR], Mercado, Investigar, Ayuda); ☰ = Ajustes, Partidas, Salir + **velocidad x1 / x2 dentro**. **Encargos**, Progreso, Registro y Sandbox, en la tarjeta de la colonia (tocar el rango). Historia e Informar fallo, en pequeño al pie del ☰ (pendiente de Bryan: ¿mejor dentro de Ayuda?) |
| 4. `STYLE_DEFAULT = "cartoon"` | **Hecho.** Borrar el estilo y las fuentes viejas queda para cuando todas las pantallas estén rehechas |

Decisiones tomadas aquí (revisables):

- **SALIR** guarda y vuelve al menú principal (que tiene "Salir del juego"); en
  Android no hay "cerrar la app" dentro de un juego.
- La cifra del almacén va al mantener pulsado (PC) y al detalle (teléfono); la
  barra fina se queda en PC.
- En teléfono, la moral pasa al detalle de la barra de recursos (§12 lo pedía
  "al tocar recursos").
- La línea del siguiente paso se oculta mientras habla la Capitana en el
  tutorial guiado (no se repite la misma cara dos veces).

## 16. Fase 2 · CONSTRUIR, ficha, Mercado e Investigar (rama `feat/ui2-construir`)

Hechas con las piezas de esta guía y las de la sección `# --- CONSTRUIR` de
`CartoonTheme`; detalle por pantalla en `docs/21-interfaz-y-dispositivos.md` §16.

- **CONSTRUIR**: carril de pestañas a la izquierda (icono; con palabra en PC),
  filas de una línea `[miniatura] Nombre … [coste] [martillo]` con lo que falta
  en rojo, candado + porqué corto en lo bloqueado ("Era 2", "Falta Almacén",
  "Rango 4"), "Al máximo" + MEJORAR en lo lleno. En PC, la ficha a la derecha;
  en teléfono, pantalla completa y el detalle al mantener la fila.
- **Ficha**: panel lateral sin velo; "Nivel N de 3" con barra; lo que hace en
  fichas de cifra; MEJORAR verde y REPARAR ámbar con su coste al lado y el
  porqué en rojo si están apagados; abajo ABRIR (azul), trabajadores, MOVER,
  GIRAR (crema) y derribar (rojo, solo icono).
- **Mercado**: una fila por recurso, los precios con icono de oro, [−] n [+],
  COMPRAR (verde) y VENDER (latón), grises con su porqué si no alcanza.
- **Investigar**: tarjetas de dos líneas (nivel · nombre y ventaja), el porqué,
  el coste y el lore al mantener; ficha con INVESTIGAR. En teléfono, carril de
  ramas y una rama a la vez.

Colores de cinta: CONSTRUIR verde, ficha latón, MERCADO latón, INVESTIGAR azul.
Pendiente de la ronda de pruebas (capturas en 640×360, 800×360, tablet y
1280×720) y de que el frente del HUD ponga `CartoonTheme.phone` y el lienzo del
teléfono en dp (§4.2): hasta entonces, en un teléfono real el lienzo mide ~554 de
alto y estas pantallas salen con la disposición de tablet.

## 17. Fase 2 · Ejército, Misiones, combate y partes (`feat/ui2-ejercito`)

Pantallas rehechas con esta guía: `ArmyPanel`, `RegimentCard`, `UnitCard`,
`SkirmishPanel` (MISIONES), `SkirmishButton`, la piel de `BattleScreen`,
`WarReportScreen`, `AuditWaveBanner`, `AuditDefeatScreen` y `ContractPanel`
(ENCARGOS). La tarjeta de la Orden de la Regencia vive en `StormHUD` (HUD, otro
frente). Textos nuevos: bloque `# UI v2 EJÉRCITO` de `Tr.gd` (claves `ARMY2_*`).

**Piezas** (sección `# --- EJÉRCITO (feat/ui2-ejercito)` al final de
`CartoonTheme.gd`): `modal_window()` (velo + ventana con cinta, en un `holder`
que se enciende y apaga) con `fit_window()` (teléfono a pantalla completa, PC
centrada con tope) o `fit_card()` (alto por contenido: partes); `set_ribbon()`;
`style_pill()` (piel de pastilla sobre un `Button` normal: su `text` sigue siendo
el texto); `set_pill_text()`; `unit_disc()` y `roster_discs()` (silueta blanca en
un disco del bando, con "×N"); `cost_row()` / `row_amounts()` (huecos con
[icono] cifra, en rojo lo que falta, cifras `Amount_<recurso>`);
`campaign_track()` (✓ ✓ ★ 4 5 [jefe]); `odds_badge()`; `stamp()`;
`icon_line()`; `tone_color()`; `style_card_button()`; `phone_canvas()` (lienzo
de menos de 450 de alto aunque nadie haya fijado `phone`).

| Pantalla | Qué queda a la vista | Qué va al mantener pulsado |
|---|---|---|
| EJÉRCITO | Pestañas Tierra / Mar / Aire (candado sin su edificio); [casco] poder, [trabajadores] 5/11, [reloj] 1/2; por unidad: disco, nombre ×3, coste en iconos, "Poder 10", [reloj][oro] 1 de sueldo, ficha (?) y **+** verde; cola con barra y ✕ roja; REGIMIENTO al final | Topes y de dónde salen, el sueldo, cifras de combate, lo que devuelve cancelar |
| MISIONES | Pestañas + lista de lo que falta para el Ataque Final; misión (recorrido, nombre, Favorable/Difícil, enemigos, botín) y tropa (− n +) lado a lado; **¡AL ATAQUE!** fijo abajo con moral y 3/6 | El mapa entero, de qué va la campaña, las fuerzas, el botín exclusivo |
| Combate (piel) | Cabecera oscura (país, combate, [3/20], de quién es el turno, x2, vista); acciones con icono (teléfono: solo icono) | Qué es cada acción, la ronda |
| Partes | Cinta PARTE verde/roja, sello, lo perdido en iconos, líneas cortas, Sargento, ¡ENTENDIDO! | — |
| Oleada | Cinta roja "Oleada 2 de 4" arriba al centro; la nota en una pastilla oscura; se quita de golpe a los 3,6 s (sin fundido) | — |
| ENCARGOS | Tres tarjetas lado a lado (columna en teléfono): quién en pastilla de su color, reloj, piden / dan en iconos, ENTREGAR verde y descartar (✕) | Quién es cada uno, qué significa cada premio |

Botones: verde = la acción (¡AL ATAQUE!, +, ENTREGAR, TERMINAR TURNO), azul =
abrir / elegir (+ de tropa, ataque rápido elegido), rojo = quitar (✕, abandonar),
ámbar = avisar (RESOLVER SOLO, alcance enemigo encendido).

Pendiente para la ronda de capturas: MISIONES a 640×360 con las cuatro pestañas y
la lista del Ataque Final a la vez (puede pedir scroll en la tarjeta de misión).

## 18. Menús y pantallas de lectura (fase 2, rama `feat/ui2-menus`)

Ajustes, Ayuda, tutorial, consejos, menú principal, Nueva partida, país y
bandera, Partidas, victoria, prólogo (marco y letra), guía rápida y REGISTRO.
Piezas nuevas, solo añadidas al final de `CartoonTheme` (sección "MENÚS"):

| Pieza | Para |
|---|---|
| `menus_phone(vp)` | Maquetar como teléfono: lienzo de menos de 450 de alto, o perfil teléfono (mientras su lienzo siga siendo mayor, §4.2). |
| `menu_window(title, fill, small)` + `place_window(root, vp, max, small)` | La ventana con cinta y ✕; centrada con tope en PC/tablet, a pantalla completa en teléfono. Con anclas: sigue al lienzo. |
| `setting_row(name, glyph, text, control)` | Fila grande de Ajustes: [icono] Nombre ··· control [valor]. |
| `picker(options, selected, cb)` (`CartoonPicker.gd`) | El selector que sustituye a los desplegables: pastillas (≤ 4 opciones cortas) o paso a paso `[◀] opción [▶]`. API de `OptionButton`. |
| `live_switch(on, cb, name)` | El interruptor de §7, pulsable: `CheckButton` con el carril dibujado. |
| `menu_slider(name, value, min, max)` | El deslizador de §7 con nombre y rango. |
| `text_button(text, glyph, kind, h)` / `button_text(b)` | Pastilla que guarda su texto en la meta `"text"` (`Button.text` va vacío porque lo pinta una etiqueta); las pruebas buscan por ella. |
| `menu_h(size)` | Alto de botón de menú: `h(size)` sin bajar de `UITheme.MIN_BTN_H`. |
| `list_button(glyph, text, small, mark)` | Fila-tarjeta de una lista (índice de ayuda): [icono] texto ··· [✓]. |
| `bubble_style()` + `Tail` + `place_tail()` | El bocadillo del instructor (tutorial, consejos) y su piquito hacia el busto. |
| `group_title(text)` | Título pequeño de grupo ("AVANZADO"). |

Textos: bloque propio `# UI v2 MENÚS` en `Tr.gd`, claves `UI2M_*` (ES/EN).
Detalle por pantalla: Ajustes en `docs/21` §2; prólogo, guía rápida, tutorial,
consejos e índice de ayuda en `docs/23` §10. Lo demás:

- **Menú principal** (`TitleMenu`): tarjeta crema sin título a la izquierda de la
  ilustración; CONTINUAR verde con el modo en pequeño debajo, Nueva partida,
  Partidas n/5 y Ajustes crema, Salir rojo. 280 de ancho en teléfono.
- **Nueva partida** (`NewGameDialog`): ventana crema; tarjetas de modo y de nivel
  elegibles (borde de latón la elegida, apagada con candado la cerrada y el
  porqué debajo); Cancelar crema, EMPEZAR verde.
- **País y bandera** (`ColonyIdentityPanel`): cinta de latón; nombre grande con
  "Al azar"; a la izquierda la bandera, su "Al azar" y los botones (Saltar o
  Cancelar, LISTO verde); a la derecha las pestañas Fondo / Emblema / Colores
  (solo icono en teléfono) y las piezas. Cabe en 640×360.
- **Partidas** (`SavesPanel`): cinta azul, "3/5" arriba, una tarjeta por partida
  (borde de latón la que se juega) con bandera, nombre, cifras pequeñas, CARGAR
  verde y borrar rojo **solo icono** (confirmación en la misma fila).
- **Victoria** (`VictoryScreen`): cinta verde, bandera y nombre, una frase y las
  cifras como icono + número (el nombre debajo); SEGUIR verde, Nueva partida
  crema. Sin fundido.
- **REGISTRO** (`NotificationPanel`, solo el panel del registro; la columna de
  avisos es de otro frente): ventana crema en su hueco, una fila por aviso con el
  icono del tipo y una franja de su color. La lista solo se rehace con el
  registro abierto.

Pendiente de decidir (no se tocó): los globos de ayuda siguen **encendidos** de
serie (`GameConfig.ui_helper_visible`); §12 propone apagarlos.

## 19. Ronda de Bryan sobre la versión previa (2026-10-19, `integracion/ui-v2`)

- **Una sola pregunta de teléfono:** `CartoonTheme.is_phone()` lee la bandera
  `phone` que fija `DeviceProfile` (perfil Móvil o lienzo de menos de 450 de lado
  corto). Se quitaron `phone_canvas()` y `menus_phone()`.
- **Tema de las ventanas:** Ajustes › Pantalla › Tema: *Claro* (crema, de serie)
  u *Oscuro* (fondo `#243241`, tarjetas `#2e3f51`, borde `#4fa3e0`, texto
  `#f3f7fb` / tenue `#a9bccd`). Guardado en `settings.cfg [interfaz] ui_theme`;
  se aplica al momento (rehace la interfaz). Todo sale de `CartoonTheme.c()`
  (`window_theme`, `_SURF_NIGHT`); el HUD es oscuro en los dos. Alto contraste
  y daltonismo siguen mandando.
  Los colores con significado sobre una ventana (rojo de lo que falta, verde de
  lo que se gana, ambar de aviso) se piden a `danger_text()`, `positive_text()`
  o `tone_color()`, nunca `sem(...).darkened(...)` a mano: pasan por
  `CartoonTheme.readable()`, que los oscurece (Claro) o aclara (Oscuro) hasta el
  contraste minimo sobre BG, CARD y CARD_ALT con cualquier paleta. El contorno
  de lo dibujado sobre la ventana (bocadillo, piquito) es `edge()`; las piezas
  cerradas, `pick_fill(false)`; las miniaturas van en un hueco claro en Oscuro
  (`thumb_frame`). Pruebas: `tests/ui/test_ui3_tema.gd`.
- **Rejillas de piezas** (País y bandera, regimiento): la pieza arriba, entera;
  cerrada, a media luz y con una **placa clara** «candado + rango» debajo
  (`CartoonTheme.rank_plate`), nunca pintada encima. La tarjeta mide lo que su
  contenido (`fit_button_content`); la elegida, borde de latón de 5
  (`pick_style`). Revisión (feat/ui3-bandera): todas las fichas salen de
  `CartoonTheme.piece_tile` y en una rejilla miden **igual de ancho** (el de la
  placa), así que caben más por fila (los 13 colores en una fila a 800×360);
  la abierta llena la ficha con su pieza. Color cerrado: su tono, más gris pero
  opaco (antes casi crema: no se distinguían). Abierto pero «no se leería»: la
  placa lleva el símbolo de prohibido rojo (antes nada, o una raya encima).
  «Sin emblema»: hueco hundido con el símbolo de prohibido (`none_piece`), no
  una muestra vacía ni un disco liso. Sonda: `tools/bandera_ui_probe.gd`.
- **CONSTRUIR a pantalla completa** en todos los perfiles; la ficha a la derecha
  en tablet y PC. El nombre del edificio va siempre entero: la fila crece a dos
  líneas antes que cortar.
- **Ficha del edificio:** 14 px de margen con el borde (más la zona segura), la
  cinta ya no tapa lo primero (`CartoonTheme.sync_ribbon_pad`), la mejora en
  una tarjeta (efecto + MEJORAR + coste), y los botones de abajo con nombre en
  PC y tablet (en teléfono, el nombre al mantener).
- **Procesos del taller: tandas que acumulan.** Cada ×1 / ×5 / MÁX (verdes, con
  el verbo encima: «Fabricar (cada toque suma):») suma tandas a la cola de ese
  proceso; «En cola: N», **−1** y **Vaciar** (devuelven entero lo no empezado).
  Se cobra al encolar (`ProcessManager.enqueue_process`), tope
  `process_batch_max`; con otro proceso en marcha la tarjeta se apaga y dice
  «Ocupado: …».
- **Se entrena en los Cuarteles:** la ficha del Cuartel, Astillero y Aeródromo
  trae ENTRENAR (`TrainingSection`); el botón Ejército de la barra lleva al
  edificio militar (centra la cámara y abre su ficha; con varios, rota).
  `ArmyPanel` queda como resumen («Ver ejército»).
- **Tutorial menos pesado:** los pasos de espera (`need_*`, `wait_*`) se ven
  4 s y se pliegan a un recordatorio con la cara de la Capitana (o con «Más
  tarde»); tocarlo los abre; a los 90 s sin avance solo se resalta. Los pasos
  de acción siguen como antes. Revisión en `feat/ui3-tutorial` (docs/23 §2.11):
  el recordatorio en una línea con el paso de ahora, ya plegado al volver a un
  paso visto, «¡Ya puedes!» una vez al tenerlo todo, y recoger también espera.
- **La línea del siguiente paso** va encima de la barra de abajo en PC (en la
  misma fila se montaba sobre Ejército / Misiones).
- **Cinco detalles de la revisión** (`tests/ui/test_ui2_detalles_feos.gd`):
  las miniaturas 3D de CONSTRUIR se pintan a 256 holgadas y se recortan a lo
  que ocupa el modelo en 4:3 (`ConstructionMenu._crop_to_model`), y el hueco
  crece (56×42 teléfono, 72×54 PC); el Mercado rehace sus filas al cargar y al
  abrir si cambiaron los recursos abiertos (`set_unlock_state` no avisa: salían
  solo comida y madera aunque hubiera acero y petróleo); la Victoria esconde
  el ☰ mientras se ve (no tiene X que apartar); el paso a paso de `CartoonPicker`
  pide el ancho de su opción más larga (96-170) y parte en dos líneas antes que
  poner puntos; la cabecera de ENTRENAR deja 22 de margen a la derecha.

## 20. Pantallas de la 1.2 (integración `integracion/v1.2b`, 2026-10-25)

Las ramas de la 1.2 se escribieron con el estilo viejo; al integrarlas pasaron a esta
guía. Capturas: `tools/v12_probe.gd` (640×360 teléfono y 1280×720 PC,
`docs/media/dev/v12/`).

| Pantalla | Cómo queda |
|---|---|
| **El barco** (`SmugglerPanel`) | `modal_window` con cinta de latón, velo y ✕ (dodge del ☰); arriba el barco dibujado y "El barco zarpa en 1:20"; una tarjeta por oferta: qué es (palabra de color), [icono] cifra (`cost_row`, en rojo lo que falta) y TRATO HECHO verde, gris con su porqué al mantener; el pie solo en PC |
| **Amenaza de costa** (`ThreatCard`) | Ficha lateral a la derecha sin velo (la marca se sigue viendo), debajo del ☰ y encima de la barra; cinta de una palabra (AMENAZA roja, PECIO azul) y el nombre dentro; reloj, discos de enemigos, Favorable/Difícil, botín en iconos; ¡AL ATAQUE! o EXPLORAR fijos abajo; el resto en un scroll |
| **MISIONES · Ataques rápidos** | Las amenazas libres son pastillas más (ancla en el mar, tormenta en tierra) y los pecios, una fila con EXPLORAR; la pestaña cuenta incursiones + amenazas |
| **MISIONES · IMPERIO** | Pestaña con estrella (solo con la fase); pastillas por isla (azul la elegida), el recorrido de campaña, el candado y VER EL ARCHIPIÉLAGO; jefe y "toma la isla" como líneas con icono |
| **El archipiélago** (`ArchipelagoPanel`) | Ventana azul: el Sargento (cara quieta, sin mover la boca) y su frase arriba; el mapa a la izquierda (en teléfono solo se nombra la isla elegida, las demás "n/m"); la ficha de la isla a la derecha con su scroll y PREPARAR EL ASALTO verde (gris con el candado) |
| **Final con elección** (`VictoryScreen`) | Victoria → EL LIBRO (verde) → la mesa: dos tarjetas lado a lado con la cara del instructor, su frase y FIRMAR (latón) / QUEMAR (naranja) → el final (cinta latón "AHORA FIRMAS TÚ" o verde "LA ISLA ES LIBRE") con la última palabra del otro instructor |

Todas sin `Tween` ni animación, el ☰ apartado de la ✕ y nada fuera de la ventana en
640×360 (lo largo va en scroll o al mantener pulsado).

