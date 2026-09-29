# 24. La paleta de la interfaz

La interfaz usaba demasiados colores: cada panel se pintaba los suyos. Contando
los colores escritos a mano en `scripts/ui/` y en los avisos de los servicios,
había **71 colores distintos** en pantalla (sin contar el prólogo, el blanco y el
negro puros ni las modulaciones de brillo). Ahora hay **una paleta de 10
colores**, más los 4 colores de recurso, que son la leyenda del almacén.

Todo vive en `scripts/ui/UITheme.gd`: la paleta es `_BASE` (sus nombres, en
`PALETTE_NAMES`) y el resto de tokens se calcula a partir de ella en `_derive()`.

## 1. Los diez colores

| Nombre (token) | Hex | Para qué se usa | Dónde no usarlo |
|---|---|---|---|
| Superficie (`SURFACE`) | `#1A1C17` | Fondo de paneles, tarjetas y HUD (con sus variantes). | Nunca como color de texto ni de borde. |
| Neutro (`NEUTRAL`) | `#262921` | Botones normales (`BTN`), bordes discretos, botones del filtro sin elegir. | No para marcar un estado: neutro es "nada que decir". |
| Latón (`ACCENT`) | `#C49629` | El acento del juego: marcos de panel, títulos, lo seleccionado, el botón activo, la flecha del tutorial. | No para avisos (para eso está Advertencia) ni como relleno grande. |
| Texto (`TEXT`) | `#E8DBC7` | Todo el texto normal. 12,6:1 sobre la superficie. | No como fondo. |
| Texto tenue (`TEXT_DIM`) | `#B8A885` | Texto secundario: descripciones, pistas, lo bloqueado. 7,4:1. | No para información que hay que leer sí o sí. |
| Texto brillante (`TEXT_BRIGHT`) | `#FFF2D9` | Cifras y nombres destacados, texto al pasar el ratón. | No para párrafos enteros: pierde su efecto. |
| Positivo (`POSITIVE`) | `#4A8C40` | Lo bueno y lo aliado: ganancia, investigado, tu bando en el tablero, el botón CONSTRUIR. | No como "decorativo verde". |
| Peligro (`DANGER`) | `#8C3B29` | Lo malo y lo enemigo: pérdidas, falta de recursos, el enemigo, cerrar, lo militar. | No para simples avisos. |
| Advertencia (`WARNING`) | `#CC8721` | Lo que pide atención sin ser grave: costes, moral, la Tormenta que se acerca. | No como acento: se confundiría con el latón. |
| Información (`INFO`) | `#4A6B8C` | Ayudas, reglas, el objetivo, casillas a las que se puede mover. | No para lo bueno ni lo malo. |

Positivo, Peligro e Información no llegan a 4,5:1 como texto sobre la
superficie. No hace falta tocarlos: todo el texto pasa por `UITheme.readable()`,
que los aclara lo justo para llegar al mínimo (7:1 en alto contraste).

## 2. Lo que se deriva

Ningún token fuera de la paleta tiene un color propio. Sale de uno de los diez
con `darkened()`, `lightened()` o un alfa:

| Token | De dónde sale |
|---|---|
| `BG_DARK` | Superficie oscurecida 50 % (campos de texto, barras, velos) |
| `PANEL_BG` / `CARD_BG` / `PANEL_BG_LIGHT` | Superficie con alfa 0,95 / aclarada 2 % / aclarada 4 % |
| `HUD_BG` | Superficie oscurecida 40 %, alfa 0,92 |
| `ACCENT_DIM` | Latón oscurecido 35 %, alfa 0,6 (bordes secundarios) |
| `OUTLINE_COLOR` | Superficie oscurecida 70 % (contorno del texto) |
| `BTN_HOVER` / `BTN_PRESSED` / `BTN_DISABLED` | Neutro aclarado 10 % / 17 %; superficie con alfa 0,7 |
| `BOARD_EMPTY` / `BOARD_MOVE` / `BOARD_TARGET` | Superficie aclarada; Información oscurecida 20 %; Peligro oscurecido 15 % |
| Fase de ceniza de la Tormenta | Mezcla a medias de Advertencia y Peligro |

Si un panel necesita otro tono, lo deriva igual (`UITheme.INFO.darkened(0.3)`),
no escribe un `Color(...)` nuevo.

## 3. Categorías de CONSTRUIR y ramas del árbol

Antes, cada una de las 5 categorías tenía su color de botón (amarillo, verde,
rojo, violeta) y cada una de las 3 ramas su color de cabecera (naranja, rojo,
celeste). Ahora:

- **Botones del filtro de CONSTRUIR**: todos neutros; el elegido, en latón
  oscuro (`ConstructionMenu.filter_color()`).
- **Tarjetas de edificio**: la categoría solo se ve en la **franja inferior**, con
  tres tonos de la paleta: Latón (producción y soporte), Peligro (militar) y
  Texto tenue (decoración).
- **Árbol tecnológico**: las tres cabeceras en latón; la rama solo se ve en la
  **franja izquierda** de sus tarjetas: Latón (industrial), Peligro (militar),
  Información (logística). El fondo de la tarjeta es el de siempre.

## 4. Avisos

Los servicios siguen mandando un color en `EventBus.notification_posted`, pero lo
decide la interfaz: `NotificationPanel` pasa la categoría por
`UITheme.notice_color()` (positivo / éxito → Positivo, peligro → Peligro,
advertencia → Advertencia, info → Información, notice → Latón). Solo una
categoría desconocida, o `combat`, que ya llega con un token, conserva el suyo.

## 5. Daltonismo y alto contraste

Siguen generándose desde la paleta. Una paleta para daltonismo solo cambia los
cuatro semánticos (y dos recursos); el alto contraste solo cambia Superficie,
Latón y los tres textos. Categorías, ramas, tablero, botones y fondos se derivan
después, así que siguen la preferencia sin tener colores propios.
`tests/ui/test_ui_palettes.gd` comprueba que la paleta tiene diez colores, que
categorías, ramas y botones son colores de la paleta en todas las variantes, y
que el texto llega al contraste mínimo sobre la superficie y el HUD.

## 6. Fuera de la paleta, a propósito

- **El mundo de juego**: materiales 3D, dibujo 2D de edificios (`BuildingArt2D`),
  carreteras, personajes, depósitos, texto flotante sobre el mapa.
- **Los colores de recurso** (`RES_*`, `GameConfig.resource_colors`): son la
  leyenda de la barra del almacén y van con un icono de forma distinta. No se
  usan para nada más.
- **Los bandos del tablero**: las siluetas se tiñen con Positivo y Peligro
  aclarados (`unit_icon_tint()`), no con colores nuevos.
- **El prólogo** (`PrologueScreen`, `RegenciaSeal`): es un documento de papel,
  tinta y lacre, con su propio lenguaje para que el lore no se confunda con el
  tutorial ni con la ayuda (`PARCHMENT`, `INK`, `SEAL_RED`...).
- **`UI_BG_REFERENCE`**: no se pinta; es el fondo contra el que se mide el
  contraste.
