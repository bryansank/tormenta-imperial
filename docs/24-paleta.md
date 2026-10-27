# 24. La paleta de la interfaz

La interfaz usaba demasiados colores: cada panel se pintaba los suyos. Contando
los colores escritos a mano en `scripts/ui/` y en los avisos de los servicios,
había **71 colores distintos** en pantalla. Ahora hay **una paleta de 10
colores**, más los 4 colores de recurso, que son la leyenda del almacén.

**Desde 2026-10-25 la paleta es la de la piel dieselpunk "D · Mezcla sobria"**
(decisión de Bryan: la piel caricatura, crema con letra redonda, le parecía "de
niño"). Base oscura de búnker, filos de latón, titulares Art Déco altos; el mapa
manda. La piel completa (fuentes, botones, paneles) está en
`docs/21-interfaz-y-dispositivos.md` §17.

Todo vive en `scripts/ui/UITheme.gd`: la paleta es `_BASE` (sus nombres, en
`PALETTE_NAMES`). Los tokens de siempre se calculan a partir de ella en
`_derive()`, y las superficies de la piel de serie (búnker y papel) en
`CartoonTheme._surface()`. Ningún panel escribe un `Color(...)` propio.

## 1. Los diez colores

| Nombre (token) | Hex | Para qué se usa | Dónde no usarlo |
|---|---|---|---|
| Pizarra (`SURFACE`) | `#1C2026` | Fondo de ventanas, HUD y fichas. | Nunca como texto. |
| Placa (`NEUTRAL`) | `#252B32` | Tarjetas, botones secundarios, filas. | No para marcar un estado. |
| Latón (`ACCENT`) | `#C99A45` | El filo de las ventanas, lo elegido, la acción principal (botón relleno con luz piloto). | No para avisos (para eso está Ámbar). |
| Texto (`TEXT`) | `#EEEAE1` | Todo el texto normal. También es el papel del tema claro. 14:1 sobre la Pizarra. | No como fondo en el búnker. |
| Texto tenue (`TEXT_DIM`) | `#AEB5BD` | Texto secundario: descripciones, pistas, lo apagado. 8:1. | No para lo que hay que leer sí o sí. |
| Texto brillante (`TEXT_BRIGHT`) | `#FFFFFF` | Cifras destacadas, alto contraste. | No para párrafos. |
| Verde (`POSITIVE`) | `#86C27A` | Lo bueno y lo aliado; la luz piloto encendida; el interruptor encendido. | No como decorado. |
| Rojo (`DANGER`) | `#C9503A` | Lo malo y lo enemigo; destruir (siempre con confirmación). | No para simples avisos. |
| Ámbar (`WARNING`) | `#E5AE3E` | Avisar: lo que pide atención sin ser grave. | No como acento: se confundiría con el latón. |
| Acero azul (`INFO`) | `#2E4A5E` | Abrir / ver: relleno de los botones que abren algo. Como tinta (iconos de Ajustes, filos) se aclara con `CartoonTheme.info_ink()`. | No para lo bueno ni lo malo. |

Verde, Rojo y Acero no llegan a 4,5:1 como texto sobre la Pizarra. No hace falta
tocarlos: el texto pasa por `UITheme.readable()` / `CartoonTheme.readable()`,
que los aclara lo justo (7:1 en alto contraste).

## 2. Lo que se deriva

Ningún token fuera de la paleta tiene un color propio. Sale de uno de los diez
con `darkened()`, `lightened()` o un alfa.

### Superficies de la piel (`CartoonTheme._surface(kind, alto_contraste)`)

| Clave | Búnker (`dark`, de serie) | Papel (`light`) |
|---|---|---|
| `BG` | Pizarra | Texto oscurecido 4 % |
| `CARD` | Placa | Texto aclarado 35 % |
| `CARD_ALT` | Placa aclarada 6 % | Texto oscurecido 9 % |
| `WELL` (hueco) | Pizarra oscurecida 32 % | Texto oscurecido 14 % |
| `BORDER` / `CARD_BORDER` (filo) | Placa aclarada 14 % | Latón oscurecido 32 % / Texto oscurecido 30 % |
| `TRIM` (filo de latón de arriba) | Latón | Latón oscurecido 32 % |
| `TEXT` / `TEXT_DIM` | Texto / Texto tenue | Pizarra / Pizarra aclarada 22 % |
| `NEUTRAL` (botón secundario) | Placa | Texto aclarado 20 % |
| `OFF` / `OFF_INK` (no disponible) | Placa aclarada 3 % / Texto tenue | Texto oscurecido 12 % / Pizarra aclarada 30 % |

`CartoonTheme.INK` (`#13171B`, la tinta de las letras sobre latón y ámbar y de
los contornos de iconos) es la Pizarra muy oscurecida.

### Tokens de siempre (`_derive()`, estilo clásico de respaldo)

| Token | De dónde sale |
|---|---|
| `BG_DARK` | Superficie oscurecida 50 % |
| `PANEL_BG` / `CARD_BG` / `PANEL_BG_LIGHT` | Superficie con alfa 0,95 / aclarada 2 % / aclarada 4 % |
| `HUD_BG` | Superficie oscurecida 40 %, alfa 0,92 |
| `ACCENT_DIM` | Latón oscurecido 35 %, alfa 0,6 |
| `BTN_HOVER` / `BTN_PRESSED` / `BTN_DISABLED` | Neutro aclarado 10 % / 17 %; superficie con alfa 0,7 |
| `BOARD_EMPTY` / `BOARD_MOVE` / `BOARD_TARGET` | Superficie aclarada; Acero oscurecido 20 %; Rojo oscurecido 15 % |

En la piel de serie, `CartoonTheme.legacy_tokens()` reescribe estos tokens con
las superficies de arriba, para que los paneles que pintan con `UITheme.TEXT`,
`UITheme.CARD_BG`... sigan la piel sin saberlo.

Si un panel necesita otro tono, lo deriva igual (`UITheme.INFO.darkened(0.3)`),
no escribe un `Color(...)` nuevo.

## 3. Categorías de CONSTRUIR y ramas del árbol

- **Botones del filtro de CONSTRUIR**: todos neutros; el elegido, en latón.
- **Tarjetas de edificio**: la categoría solo se ve en la franja inferior:
  Latón (producción y soporte), Rojo (militar) y Texto tenue (decoración).
- **Árbol tecnológico**: la rama solo se ve en la franja izquierda de sus
  tarjetas: Latón (industrial), Rojo (militar), Acero (logística).

## 4. Avisos

Los servicios siguen mandando un color en `EventBus.notification_posted`, pero lo
decide la interfaz: `NotificationPanel` pasa la categoría por
`UITheme.notice_color()` (positivo / éxito → Verde, peligro → Rojo,
advertencia → Ámbar, info → Acero, notice → Latón). En la ficha del aviso el
color va en el filo izquierdo de 7 px (`CartoonTheme.notice()`), nunca bajo el
texto.

## 5. Daltonismo y alto contraste

Una paleta para daltonismo **solo cambia tres o cuatro tokens** (y dos recursos):

| Paleta | Verde → | Rojo → | Ámbar → | Acero → |
|---|---|---|---|---|
| `red_green` (protanopia, deuteranopia) | Azul `#5AAEF5` | Bermellón `#D55E00` | Amarillo `#F2E15A` | — |
| `tritan` (tritanopia) | Turquesa `#3DB5AE` | Carmesí `#DC264D` | Rosa `#F59AAA` | Gris acero `#4A4F5C` |

**Alto contraste** (la variante que vio Bryan y la que más tiene que cuidarse):
fondo casi negro (Pizarra oscurecida 55 %), texto blanco puro y tenue `#E4E4E4`,
todos los filos en latón claro (Latón aclarado 18 %), bordes un punto más
gruesos (`CartoonTheme.border_k()`; la ficha del HUD llega a 3 px), HUD y
ventanas opacos, y el rojo de los botones de destruir baja de luz para que su
letra llegue a 4,5:1. En papel, blanco y negro puros con filos negros.
Categorías, ramas, tablero, botones y fondos se derivan después, así que siguen
la preferencia sin tener colores propios.

Lo comprueban `tests/ui/test_ui_palettes.gd` (separación de los semánticos con
la visión simulada, contraste del texto), `tests/ui/test_ui3_tema.gd` (texto y
tonos sobre las dos superficies, todas las paletas, con y sin alto contraste) y
`tests/ui/test_piel_dieselpunk.gd` (la paleta elegida, 7:1 en alto contraste
sobre todas las superficies, la letra de cada intención de botón, como mucho
cuatro tokens por paleta).

## 6. Fuera de la paleta, a propósito

- **El mundo de juego**: materiales 3D, dibujo 2D de edificios (`BuildingArt2D`),
  carreteras, personajes, depósitos, texto flotante sobre el mapa.
- **Los colores de recurso** (`RES_*`, `GameConfig.resource_colors`): la leyenda
  de la barra del almacén, con un icono de forma distinta.
- **Los iconos dibujados** (`CartoonIcon`): conservan sus rellenos de color; solo
  su contorno pasó a la tinta de la piel (`#13171B`).
- **Los bandos del tablero**: las siluetas se tiñen con Verde y Rojo aclarados
  (`unit_icon_tint()`).
- **El prólogo** (`PrologueScreen`, `RegenciaSeal`): un documento de papel,
  tinta y lacre, con su propio lenguaje (`PARCHMENT`, `INK`, `SEAL_RED`...).
- **`UI_BG_REFERENCE`**: no se pinta; es el fondo contra el que se mide el
  contraste del estilo clásico.
