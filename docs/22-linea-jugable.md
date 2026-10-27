# La línea jugable: de la primera obra a la victoria

> **Ojo, medida vieja (nota del 2026-10-14).** Todo lo de este documento se midió
> **antes** de las carreteras y los edificios de 2×2, los materiales del taller, la
> comida con la Granja y la producción que se recoge, y la isla irregular (y antes de
> los topes por era y las decoraciones nuevas). Las cifras de tiempos, esperas y
> victorias ya no describen el juego de hoy. La rama `balance/campana-4-6h` vuelve a
> medir la campaña entera con la sonda sobre la isla irregular; hasta que se integre,
> lea esto como historia de cómo se arregló la línea, no como su estado.

Qué pasa cuando alguien que no conoce el juego lo juega de principio a fin con los
**tiempos de verdad** (sin `dev_mode`): cuánto tarda cada hito, dónde se espera sin
nada que hacer, qué cuesta cada Tormenta, si el asedio se gana y dónde se atasca.
Medido, no estimado, con `tools/line_probe.gd`. Hermano de
[16-balance-combate.md](16-balance-combate.md) y
[17-balance-asedio.md](17-balance-asedio.md), que miden el combate por separado.

**Resumen.** Con el balance que había, **la campaña no se podía terminar**: de 15
partidas simuladas se ganaron 2, a las 4 y 6 horas; la moral vivía en 0 desde la
segunda tormenta, la gente moría de hambre y no se echó a los Tasadores casi nunca
(12 Diezmos de 349). Después de los arreglos, **10 de 10 partidas se ganan**, en
**2 h 18 min a 4 h** (mediana 3 h 11 min), la era 1 no tiene esperas de más de 6
minutos, y se echa a los Tasadores casi 9 de cada 10 veces.

---

## 1. Cómo se mide

`tools/line_probe.gd` juega una colonia entera por semilla con los servicios reales:
el `BuildingPlacer` y el `MapGenerator` de verdad (cada obra pasa por el mismo
`_try_place()` que un clic: yacimiento, requisitos, tope, obreros y coste), el mapa
sorteado por la semilla, y el reloj en la mano: los autoloads dejan de procesar solos y
la sonda les da el tiempo a pasos de 1 s. Tres horas de partida se juegan en un
minuto.

**El jugador razonable** (`tools/line_probe_player.gd`) mira la partida cada 2 s y:

1. repara lo que esté roto (lo que da de comer primero), nunca con la Tormenta encima;
2. hace **lo que diga el panel ¿QUÉ HACER?** (`Objectives.next_step()`, ver §4): es la
   misma cuenta que ve el jugador, así que si la sonda gana obedeciéndola, el panel no
   miente ni pide imposibles;
3. deja siempre en la caja dos ciclos de comida y sueldos (cuatro con la Tormenta a la
   vista), salvo para la mejora final;
4. si no le llega el oro para comer, vende lo que sobra;
5. baja a la Regencia con seis blindados en casa, las torres enteras y en calma.

Las peleas (Diezmo y oleadas) las juega `AutoResolver` con la **misma IA a los dos
lados**, que juega peor que una persona: las tasas de victoria son un suelo. El tiempo
de cada pelea sale de la fórmula de [16-balance-combate.md](16-balance-combate.md) §3
(5 s por turno de jugador) y **la base sigue corriendo mientras tanto**, porque el juego
no se pausa en el tablero.

Una **espera muerta** es un hueco de más de 2 minutos sin ningún paso de progreso
(construir, mejorar, entrenar, investigar, bajar al asedio). Reparar y comerciar no
cuentan como progreso.

Lo que la sonda no hace: expediciones (el botín es opcional), decoraciones, y en el
modo por defecto tampoco procesos manuales ni minado a mano (`--active=1` sí, §5.4).
Desde 2026-10-04 el jugador activo tiende la carretera hasta la veta (hasta 4 tramos)
antes de minar: minar pide carretera y dos obreros libres, y sin eso no minaba nunca.

---

## 2. Antes

### 2.1 El juego tal cual (primera sonda, 5 semillas)

La primera versión del jugador seguía la línea sin colchón y con la guarnición de tres
infantes que decía la guía. Minutos de partida:

| Semilla | Aserradero | Mina | Almacén | Era 2 | Era 3 | Comandante | CG | CG nv3 | Victoria | Tormentas | Diezmos echados | Esperas >2 min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 | 3 | 7 | — | — | — | — | — | 41 | 0/41 | 45 (424 min) |
| 2 | 0 | 0 | 3 | 8 | 207 | 279 | 392 | — | — | 37 | 0/37 | 44 (425 min) |
| 3 | 0 | 0 | 3 | 32 | 331 | — | — | — | — | 43 | 0/43 | 35 (443 min) |
| 4 | 0 | 0 | 3 | 32 | 118 | 304 | 371 | — | — | 43 | 0/43 | 45 (437 min) |
| 5 | 0 | 0 | 3 | 8 | 138 | — | — | — | — | 45 | 0/45 | 28 (448 min) |

Ocho horas de partida, ninguna victoria, ningún Diezmo echado. La moral estaba en 0 al
final de todas, con 57 a 123 muertos de hambre por partida.

### 2.2 Los números viejos con el jugador final (10 semillas)

El mismo jugador que gana en §5, sobre los números de balance de antes (`--cfg.*`
devuelve cada uno a su valor anterior; lo que no se puede volver atrás por
configuración —la guarnición por fuerza, la escolta, el mapa— queda arreglado, así que
esto es, si acaso, mejor que el juego de antes):

| Semilla | Era 2 | Era 3 | Comandante | CG | CG nv3 | Victoria | Tormentas | Diezmos echados | Esperas >2 min | Mayor espera antes de era 2 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 43 | 208 | 337 | — | — | — | 40 | 0/40 | 36 (426 min) | 25 min |
| 2 | 8 | 120 | 214 | 401 | — | — | 35 | 0/35 | 36 (414 min) | 4 min |
| 3 | 51 | 351 | 354 | — | — | — | 39 | 0/39 | 39 (426 min) | 32 min |
| 4 | 8 | 417 | 443 | — | — | — | 39 | 0/39 | 36 (417 min) | 5 min |
| 5 | 42 | 121 | 126 | — | — | — | 47 | 0/47 | 27 (463 min) | 23 min |
| 6 | 44 | 136 | 139 | 275 | 338 | 360 | 25 | 4/25 | 36 (313 min) | 25 min |
| 7 | 33 | 242 | 246 | 255 | — | — | 35 | 1/35 | 47 (421 min) | 15 min |
| 8 | 13 | 104 | 110 | 159 | 232 | 249 | 15 | 3/14 | 28 (223 min) | 10 min |
| 9 | 62 | 97 | 200 | 317 | 434 | — | 37 | 4/38 | 34 (416 min) | 29 min |
| 10 | 35 | 112 | 116 | 366 | — | — | 37 | 0/37 | 35 (422 min) | 16 min |

**2 de 10 victorias**, a las 4 h 9 min y a las 6 h. La era 2 llegaba entre el minuto 8
y el 62, con esperas de hasta media hora en la era 1: la Tormenta ya cobraba en la era
1, antes de que el jugador pudiera tener un solo soldado.

---

## 3. Lo que se encontró

### 3.1 Atascos (la partida no puede seguir, o no puede terminar)

| # | Atasco | Dónde | Arreglo | Test |
|---|---|---|---|---|
| A1 | **Islas sin pozo de petróleo, o sin bosque.** El sorteo elegía el tipo de cada yacimiento al azar sin mirar los demás: sin pozo no hay Refinería, ni era 3, ni final; sin bosque no hay apertura. Con 18-28 sorteos uniformes, ~0,8% de los mapas salían sin algún tipo y ~1,3% con un solo pozo (la Refinería se lo come) | `MapGenerator.generate_new_map()` | Desde el mapa aleatorio (2026-09-28) cada tipo sortea su propio número entre `deposit_per_type_min` y `deposit_per_type_max` (3-6), y cada yacimiento deja hueco a su extractor con camino hasta la acera del Núcleo (el antiguo `_guarantee_minimums()` ya no hace falta) | `tests/map/test_map_minimums.gd`, `tests/map/test_random_map.gd` |
| A2 | **La colonia hundida no se levanta.** Con 1 habitante y la moral en 0 no nace nadie (hace falta 30), sin obreros no produce la mina, sin oro no se paga la comida y sin comida la moral no sube. Pasó en 2 de 10 partidas | `PopulationManager._tick_growth()` | Por debajo de `population_regrow_floor` (5) la gente vuelve aunque la moral esté baja | `test_a_ruined_colony_regrows_up_to_the_floor_even_without_morale` |
| A3 | **Los blindados del final se quedaban en el cuartel.** La guarnición llenaba los 6 huecos por orden de diccionario, infantería primero: con 3 infantes viejos y 6 blindados nuevos, al asedio bajaban 3 y 3 | `CombatManager.get_garrison()` | Los huecos se llenan de la unidad más fuerte a la más débil | `test_a_full_board_fields_the_strongest_units_first` |
| A4 | **La mejora final no se podía juntar.** Cuesta 3.500 y la bolsa máxima sin tecnología es 3.500: hay que tener los cuatro recursos justos a la vez mientras la gente come y las fábricas producen, y lo que no cabe se pierde. 3 de 5 partidas se quedaron ahí con todo lo demás hecho | diseño (§3.3) | El panel manda a Logística 1-2 e Industria 1-2 (+500) antes de pedirla. El invariante 3.500 = 3.500 no se toca | `test_the_last_upgrade_sends_you_to_the_storage_techs_first` |
| A5 | **La bolsa llena de acero y petróleo deja a la gente sin comer.** Lo que no cabe se pierde, el oro de la comida incluido: hasta 50.000 recursos perdidos y 250 muertos de hambre en una partida | diseño | El panel pide comprar lo que falta con el oro que sobra (comprar hace sitio) o vender lo que sobra, y no pide más productores con la bolsa por encima del 75% | `tests/ui/test_objectives.gd` |

**La regla del extractor junto a su yacimiento** (aserradero → bosque, mina → veta,
fundición → hierro, a una casilla incluida la diagonal; refinería encima de un pozo;
`GameConfig.building_deposit_rules` y `PlacementRules`, la misma para las dos vistas)
está activa en todas las mediciones y no atascó ninguna: en las diez islas quedó sitio
para cada extractor que pidió la línea, también en la semilla 10, que solo trae dos
bosques. Lo que sí aparece en las diez es el tope de 4 minas de oro: ahí el panel pasa
a pedir subir de nivel la que menos rinde. El rechazo dice ahora exactamente lo que
hace falta: "El aserradero debe tocar un bosque (al lado o en diagonal)".

### 3.2 Pasos poco claros

El panel **¿QUÉ HACER?** eran cinco pasos fijos, y tres eran falsos: construir un Núcleo
(ya está puesto y no se construye), "conectar" edificios con almacenes (no se conecta
nada) y desbloquear edificios con el árbol tecnológico (los desbloquean otros
edificios). No decía nada después del Cuartel General, ni tras perder el asedio, ni tras
ganar. Y la guía decía que tres infantes bastaban para el Diezmo: **tres infantes solos
pierden incluso contra la escolta más pequeña** (tabla en §3.4).

Ahora el panel dice en cada momento **el siguiente paso, por qué y qué falta**, y pinta
la línea entera con lo hecho marcado (§4).

### 3.3 Ritmo

| Problema | Medido | Arreglo |
|---|---|---|
| **La primera tormenta no enseñaba: hundía.** La moral se cobraba redondeando cada tic: con 24 tics por tormenta, una de severidad 1 costaba **96 puntos**. La recuperación normal (+3 por ciclo) no podía con eso: la moral vivía en 0 desde la segunda tormenta. (El hallazgo viejo —que la severidad 1 no se notaba— era de otra versión del ciclo) | 63 → 30 en la primera tormenta, 0 desde la segunda | `storm_morale_per_tick` 2,0 → **0,25**, con decimales: **12 puntos por punto de severidad**. Sev. 1 = −12, sev. 5 = −60 |
| **La Tormenta llegaba en la era 1**, en el minuto ~9, a una colonia que no puede tener cuartel hasta la era 2. El diseño (Acto II) la trae con la industria | Diezmo cobrado en obreros en el minuto 9 | Se arma con la primera **Fundición** (`storm_arm_phase` = EXPANSION) y la primera llega 10 min después (`storm_first_interval` 420 → 600 s) |
| **La primera visita cobraba la Cuota Mínima** (60) a una colonia recién nacida | 1-2 obreros en la primera tormenta | La primera visita es un alta: solo el porcentaje (`storm_first_tithe_has_floor` = false) |
| **La escolta llegaba al tope a la séptima tormenta**, pagada o no: crecía con `storms_survived` y no con los Diezmos echados, como dicen el comentario y el diseño | escolta de 6 desde el minuto ~60 | Crece con `tithes_repelled` (nuevo, guardado) |
| **La Tormenta rompía las torres antes de que llegaran los Tasadores.** 24 mordiscos por tormenta van primero a torres y cuarteles: a severidad 3 las dos torres caían en la fase TORMENTA y sus dotaciones no llegaban nunca al Diezmo | 1-3 Diezmos echados de ~40, con guarnición de cinco | `storm_damage_per_tick` 0,06 → **0,03**. Con dos torres, una severidad 5 las deja al 15%; sin torres, en ruinas |
| **Demasiadas tormentas.** Una cada 7-10 min: 35-47 en ocho horas, y cada Diezmo es un tablero de 4-7 min | casi la mitad del tiempo en el tablero | Calma de 360-600 s (antes 240-420): **7-13 tormentas hasta la victoria** |

### 3.4 Qué guarnición gana el Diezmo

La escolta es 3 + (severidad − 1) unidades, dos tercios infantería y un tercio
artillería, tope 6. IA a los dos lados, moral 50, sin escalada:

| En casa | Sin torres | Con dos torres en pie |
|---|---|---|
| 3 infantes | **pierde siempre** | gana hasta sev. 3 |
| 4 infantes | gana sev. 1 | gana hasta sev. 3 |
| 3 infantes + 2 artillerías | gana hasta sev. 3 | **gana siempre** |
| 3 infantes + 3 artillerías | gana siempre | gana siempre |
| 3 blindados | gana hasta sev. 3 | gana siempre |
| 6 blindados | gana siempre, sin bajas | gana siempre, sin bajas |

Por eso la línea pide **cinco unidades, dos de ellas artillería**.

---

## 4. El panel ¿QUÉ HACER?

`scripts/services/Objectives.gd` calcula el paso desde la partida; `ObjectivePanel` lo
pinta con su porqué y lo que falta. La línea:

1. Aserradero (junto a un bosque) → 2. Mina de oro (junto a una veta) → 3. Casa →
4. Segundo aserradero → 5. Almacén (avisa de que sube la dificultad) → 6. Fundición,
era 2 → 7. Cuartel → 8. Guarnición: 5 unidades, 2 de artillería → 9. Refinería sobre
un pozo, era 3 → 10. Dos torres → 11. Cuartel General → 12. CG nivel 2 → 13. Seis
blindados → 14. CG nivel 3 (convoca la Auditoría) → sobrevivirla.

**La primera escaramuza** va entre el 7 y el 8: en cuanto hay una unidad en casa, y
mientras la partida no haya ganado ninguna salida, el panel pide "Lanza tu primera
escaramuza" (`kind: "sortie"`) por delante de todo lo demás de la línea, sin pasar por
los pasos de apoyo (no cuesta nada y su botín es oro y madera). No sale con una columna
fuera ni con la Auditoría convocada. Es un solo nodo fácil con 150 de oro y 100 de
madera (docs/15-combat.md §4); la sonda la lanza igual que el jugador.

Antes de cada paso, lo que lo haría imposible o absurdo, en este orden:

- algo que da de comer está en ruinas → **repáralo**;
- no llega para la comida de dos ciclos → **compra o vende en el Mercado**;
- el oro o la madera no dan para comer → **otra mina / otro aserradero**, y si no hay
  sitio o tope, **sube de nivel** el que menos rinde;
- faltan obreros y no van a nacer → **una casa**;
- el paso no cabe (o cabe tan justo, >90%, que no se puede juntar) → **un almacén**, y
  con los cinco en pie, **las tecnologías de almacén**;
- la bolsa por encima del 90% y al paso le falta algo → **compra** con el oro que sobra
  o **vende** lo que el paso no pide;
- lo que falta tarda más de 6 min en llegar y hay sitio → otro productor.

Y después: con el asedio convocado y menos de seis blindados en casa, entrenarlos; con
ellos, "pulsa QUE BAJEN"; tras perder, rehacer los seis blindados y reconvocar (se puede
con tres unidades, pero con tres no se gana); tras ganar, mundo libre.

El panel respeta el modo de la partida ([20-modos-de-juego.md](20-modos-de-juego.md)):
en **Constructor** no pide guarnición ni blindados y el CG nivel 3 es la meta; en
**Sandbox** no hay objetivo; en **Supervivencia** una Auditoría perdida es el final y lo
dice. La cabecera del panel es la del modo.

`tests/ui/test_objectives.gd` recorre la línea entera dando cada paso que el panel pide
con justo lo que cuesta, y comprueba que nunca se atasca, que el paso siempre se puede
dar y que el orden es el de la guía.

---

## 5. Después

Todos los números de §3.3 aplicados y el panel de §4, medido otra vez después de
integrar los modos de juego (la Campaña usa estos números tal cual; los otros modos
los escalan). Diez semillas, jugador por defecto (sin procesos ni minado a mano).
Minutos de partida:

| Semilla | Era 2 | Era 3 | Comandante | CG | CG nv3 | Asedio | Victoria | Tormentas | Diezmos echados | Esperas >2 min | Mayor espera | Antes de era 2 | Bolsa llena |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 9 | 26 | 31 | 60 | 123 | 123 | **138** | 7 | 7/7 | 15 | 15 min | 5 min | 1 min |
| 2 | 8 | 29 | 37 | 62 | 142 | 142 | **165** | 8 | 8/8 | 18 | 23 min | 4 min | 10 min |
| 3 | 9 | 30 | 44 | 120 | 188 | 188 · 225 | **239** | 13 | 11/14 | 23 | 20 min | 5 min | 21 min |
| 4 | 8 | 28 | 40 | 83 | 148 | 148 · 189 | **207** | 10 | 9/11 | 21 | 35 min | 5 min | 25 min |
| 5 | 10 | 44 | 48 | 128 | 180 | 180 | **195** | 10 | 9/10 | 19 | 16 min | 6 min | 12 min |
| 6 | 9 | 33 | 45 | 83 | 123 | 132 | **147** | 7 | 6/7 | 16 | 15 min | 5 min | 7 min |
| 7 | 9 | 40 | 44 | 92 | 166 | 166 | **182** | 9 | 8/9 | 20 | 16 min | 5 min | 3 min |
| 8 | 9 | 29 | 35 | 76 | 164 | 175 | **194** | 8 | 8/8 | 22 | 19 min | 6 min | 6 min |
| 9 | 8 | 29 | 44 | 80 | 159 | 159 · 192 | **206** | 10 | 9/11 | 20 | 27 min | 4 min | 24 min |
| 10 | 8 | 32 | 42 | 135 | 173 | 173 | **188** | 9 | 8/9 | 21 | 17 min | 4 min | 12 min |

(Aserradero y mina en el minuto 0 y almacén en el 3 en todas.) Dos asedios en una
casilla: el primero se perdió y el segundo se ganó.

### 5.1 Lo que dice la tabla

- **10 de 10 victorias**, de 2 h 18 min a 4 h, **mediana 3 h 11 min**, media 3 h 6 min. Dentro
  de la ventana de 2-4 h que se pedía, con un jugador que juega el tablero peor que una
  persona y que no usa procesos manuales ni minado.
- **Era 1 en 8-10 min, era 2 en 20-35 min, era 3 el resto.** La era 3 es la mitad de la
  partida (del CG a la victoria, 70-120 min): es el tramo de las decisiones grandes.
- **Sin esperas largas al principio**: la mayor antes de la era 2 es de 4-6 min (juntar
  los 200 de oro de la Fundición con una mina). Las esperas de más de 2 min se
  concentran en la era 3 (CG, CG 2 y blindados), y la mayor de todas es el propio
  asedio: 15-23 min de tablero.
- **La primera tormenta enseña**: llega en el minuto 19-21, severidad 1, la moral pierde
  0-6 puntos y el Diezmo se echa (o se paga su porcentaje: 60-100 de recursos). **Las
  siguientes muerden**: severidad 2-3 en la era 2 y 4-5 en la era 3, que se llevan 30-60
  puntos de moral y rompen 1-3 edificios.
- **Diezmos**: 83 de 94 echados (88%). Los que se pagan son la primera visita (sin
  cuartel todavía) y los que caen con el ejército recién gastado en un asedio perdido.
- **Asedio**: 10 ganados en 13 intentos con seis blindados; los tres que se perdieron
  (semillas 3, 4 y 9) se reconvocaron y se ganaron 33-47 min después. Coincide con
  [17-balance-asedio.md](17-balance-asedio.md) (82% con la guarnición máxima).
- **Hambre**: 0 muertos en 7 partidas, 16-21 en dos. Bajas de tropa: 5-25 por partida.

### 5.2 Tormentas, una partida típica (semilla 1)

| Minuto | Severidad | Torres | Ruinas | Moral antes → después | Diezmo |
|---|---|---|---|---|---|
| 20 | 1 | 0 | 0 | 99 → 100 | echado |
| 33 | 2 | 2 | 0 | 98 → 100 | echado |
| 50 | 4 | 2 | 0 | 91 → 86 | echado |

(y cuatro más, severidad 5, hasta la victoria en el 138). La moral de "antes" se mide
al empezar la fase TORMENTA, con la ceniza ya cobrada.

### 5.3 Dónde se espera (minutos que el panel pasa diciendo lo mismo)

Los pasos que más tiempo se quedan en pantalla, sumados sobre las diez partidas: la
Refinería (7-23 min: 300 de oro y 150 de acero con una fundición), el Cuartel General
(6-27 min), la segunda y la cuarta mina, y los seis blindados (8-9 min). Son las
compras grandes de cada era: ahí es donde el jugador decide si espera, comercia o usa
los procesos.

### 5.4 El jugador activo

`--active=1`: el mismo jugador, además, mina a mano un yacimiento a la vez (gratis:
20 de madera cada 8 s, 20 de oro cada 12 s, sin tocar el último de cada tipo) y
mantiene ocupados los procesos del Núcleo, el aserradero y la mina. (Tabla de antes del
recorte del minado y de la carretera hasta la veta; lo de ahora, en §5.5.)

| Semilla | Era 2 | Era 3 | CG | CG nv3 | Victoria | Tormentas | Diezmos echados | Mayor espera | Bolsa llena |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 3 | 20 | 43 | 181 | 233 | 13 | 13/14 | 55 min | 79 min |
| 2 | 3 | 24 | 50 | 153 | 218 | 11 | 11/12 | 39 min | 76 min |
| 3 | 3 | 20 | 43 | 87 | 102 | 5 | 5/5 | 14 min | 9 min |
| 4 | 3 | 22 | 57 | 118 | 140 | 7 | 7/7 | 22 min | 38 min |
| 5 | 3 | 20 | 40 | 91 | 106 | 6 | 6/6 | 15 min | 14 min |
| 6 | 3 | 22 | 58 | 109 | 180 | 10 | 9/11 | 35 min | 57 min |
| 7 | 3 | 20 | 41 | 80 | 101 | 5 | 5/5 | 20 min | 16 min |
| 8 | 3 | 13 | 49 | 90 | 143 | 8 | 6/8 | 24 min | 36 min |
| 9 | 3 | 21 | 44 | 127 | 149 | 8 | 8/8 | 25 min | 30 min |
| 10 | 3 | 21 | 59 | 151 | 174 | 9 | 9/9 | 58 min | 52 min |

**10 de 10, de 1 h 41 min a 3 h 53 min, mediana 2 h 26 min.** Dos cosas salen de aquí:

- **El minado a mano se come la era 1**: la era 2 llega en el minuto 3 en todas las
  semillas. Una veta a mano da 100 de oro por minuto, dos minas y media. Es finito (8
  usos por yacimiento) y es una decisión (gastar la veta que luego no está), pero hoy la
  era 1 dura lo que el jugador tarde en hacer clic.
- **El jugador activo llena la bolsa antes** (9-79 min con la bolsa llena, hasta 28.000
  recursos perdidos): los procesos producen de más en la era 3. Es el mismo riesgo de §7.

### 5.5 La era 1 (2026-10-04): tormenta de prueba y minado recortado

Dos decisiones de Bryan para la era 1: que dure **8-12 minutos** y que tenga una
**tormenta de prueba** suave hacia el minuto 5.

- **Tormenta de prueba** (`GameConfig.storm_trial_*`, `StormManager`): a los 300 s de
  partida jugada (escalados por `dev_time_scale` en dev) entra el Aviso, con sus avisos y
  consejos; luego Ceniza y Tormenta de duración normal, y calma. Sin Diezmo, sin romper
  edificios, sin llevarse la cola de procesos ni de entrenamiento, producción al 75% y un
  cuarto del mordisco de moral (−3 a severidad 1). Una vez por partida, guardada. Va en
  su propio `StormCycle`: el reloj de verdad sigue armándose con la Fundición. Si la
  Fundición llega antes del minuto 5, no sale. No en Constructor ni Sandbox (regla de
  modo `storm_trial`). La sonda no la cuenta como tormenta y la anota aparte.
  **Nunca en medio del tutorial** (2026-10-19, docs/23 §2.10): con el tutorial guiado en
  marcha espera, y llega como pronto `storm_trial_after_guide` (90 s jugados) después de
  acabarlo (`StormManager.trial_due_at`); tampoco corren entretanto el reloj de la
  Tormenta de verdad ni los eventos. La sonda juega con el tutorial ya hecho, así que la
  prueba le sigue llegando a su hora y estas cifras no cambian.
- **La primera Mina de oro a mitad de precio** (2026-10-19, docs/03): 60 oro + 40 madera
  en vez de 120 + 80. Sonda corta (`--seeds=1,2,3 --hours=0.4`): la Mina sale en el
  minuto 4,8 con y sin rebaja (en la línea va detrás del primer soldado y la misión, no
  la frena el oro), su espera en ¿QUÉ HACER? es de 2 min en los dos casos, y lo que se
  ahorra adelanta la era 2: minuto 15,7-17,8 con rebaja frente a 17,8-19,8 sin ella.
  En el tutorial, que la pide detrás de la Casa y los manejos, hay que juntar la mitad
  de oro; ese orden no lo mide ninguna sonda (el recorrido rellena la bolsa), queda
  para la ronda de pruebas con Bryan.
- **Minado a mano**: oro 20 cada 12 s → **12 cada 30 s**; madera 20 cada 8 s → **10 cada
  20 s** (hierro y petróleo igual). Por obrero y minuto rinden ahora lo mismo que su
  extractor (oro 12 frente a 13,3 de la Mina; madera 15 frente a 15 del Aserradero):
  minar sirve para arrancar o salir de un apuro, no es la vía rápida a la Fundición.

Minuto en que llega la era 2 (la Fundición), cinco semillas, `--no-dev`:

| Jugador | Antes | Con la tormenta de prueba | Con prueba y minado recortado |
|---|---|---|---|
| Por defecto (sin procesos ni minado) | 9-10 | 8,9 · 9,0 · 9,6 · 10,2 · 10,2 | **8,6 · 9,0 · 9,2 · 9,6 · 10,2** |
| Activo que mina (carretera hasta la veta) | **3,8** en las cinco | — | **6,7 · 6,7 · 6,7 · 6,7 · 7,6** |
| Activo sin minar (la sonda de antes: no podía) | 4,6 · 4,6 · 4,6 · 4,8 · 4,9 | igual (la era 2 llega antes del minuto 5 y la prueba no sale) | — |

La tormenta de prueba llega (fase Tormenta) en el minuto 6,7-6,8 en todas; su Aviso, en
el 5. Lo que dice la tabla:

- **El jugador por defecto cumple**: era 1 de 8,6 a 10,2 minutos.
- **El minado ya no rompe la era 1**: el que mina pasa del minuto 3,8 al 6,7-7,6, y la
  tormenta de prueba le pilla en la era 1.
- **Lo que sigue acortando la era 1 son los procesos**, no el minado: el jugador activo
  que solo encadena `wood_planks` y `refined_lumber` (Núcleo y aserradero) llega a la
  Fundición en el minuto 4,6-4,9, antes de la prueba. Con el minado recortado, minar
  además le quita obreros y lo retrasa. Si se quiere que la era 1 dure 8 minutos también
  para quien exprime los procesos, la palanca es `building_processes` (margen o
  duración de esas dos recetas): fuera de este cambio, pendiente de decisión.

---

## 6. Cada era trae su decisión

- **Era 1 — dónde y cuándo.** Los extractores van pegados a su yacimiento, así que el
  mapa decide la base. Y el primer Almacén es el interruptor de la dificultad (consumo al
  doble, eventos): ponerlo en el minuto 3 o en el 10 es la primera decisión con precio.
- **Era 2 — la Tormenta.** Llega con la Fundición. Guarnición (que cobra sueldo) contra
  economía, qué se deja en la bolsa (los Tasadores se llevan un porcentaje) y qué se
  gasta antes del Aviso.
- **Era 3 — la bolsa y el ejército.** El acero y el petróleo llenan la bolsa solos y
  echan fuera el oro de la comida: vender, comprar, investigar almacén o subir de nivel.
  Y qué ejército bajar a la Auditoría, y cuándo.

---

## 7. Lo que queda (riesgos)

- **El tablero se come un tercio de la partida.** 45-100 min de 140-240 son tableros
  (7-13 Diezmos de 4-7 min cada uno más el asedio), con 5 s por turno de jugador. Un
  Diezmo con seis blindados contra seis Tasadores es una pelea ganada de antemano que
  aún hay que jugar entera. **Propuesta para Bryan**: un botón "resolver solo" en el
  Diezmo (el `AutoResolver` ya existe y es el mismo que se usa con el tablero ocupado).
- **La bolsa se sigue llenando en la era 3** (1-25 min por partida y 350-9.000 recursos
  perdidos): el panel lo resuelve, pero pide varias compras y ventas seguidas. Si se
  quiere que no haga falta, las palancas son el precio del CG nv3 (con 3.100 en vez de
  3.500 se ganaron 2 de 5 partidas que antes se atascaban, serie `i` de la sonda), o
  que la producción de acero/petróleo se pare con la bolsa llena en vez de tirarse.
- ~~La era 1 no tiene Tormenta~~ y ~~el minado a mano se come la era 1~~: resueltos el
  2026-10-04 con la tormenta de prueba y el recorte del minado (§5.5). Queda que **los
  procesos manuales** (`wood_planks`, `refined_lumber`) llevan a la Fundición en el
  minuto 4,6-4,9 a quien los encadena sin parar.
- **El jugador de la sonda es rápido en la era 1** (actúa cada 2 s y coloca al primer
  intento). Una persona tardará más en encontrar el bosque y la veta; los minutos de la
  era 1 son un mínimo.
- **La IA juega los dos bandos.** Una persona gana más asedios y pierde menos tropa;
  las tasas son un suelo.
- **Sin expediciones.** La sonda no sale de expedición: el botín acortaría la partida y
  las bajas la alargarían.

---

## 8. Para el equipo del onboarding

El tutorial y las ayudas se rehacen aparte, así que aquí no se tocaron (unos retoques
que se hicieron se deshicieron en `a2f2b45`). Lo que la línea medida contradice hoy:

- `TUT_PLAY_4_BODY` da el camino en otro orden (casas antes que la mina, torres después
  del cuartel) y no dice que la Tormenta llega con la Fundición.
- `TUT_PLAY_3_BODY` presenta la Tormenta en la intro, 20 minutos antes de la primera.
- `TUT_TIP_TITHE_BODY` dice que se llevan "un porcentaje": desde la segunda visita hay
  Cuota Mínima (embargan edificios y obreros).
- `TUT_TIP_BARRACKS_BODY` no dice cuánta guarnición hace falta: tres infantes solos
  pierden siempre; cinco con dos cañones ganan (§3.4).
- `TUT_TIP_CONSUMPTION_BODY` no menciona el Mercado, que es lo único inmediato cuando
  falta oro o madera.
- `TUT_TIP_AUDIT_BODY` no dice qué ejército gana: seis blindados casi siempre, tres
  unidades casi nunca.
- Nada del tutorial menciona el panel **¿QUÉ HACER?**, que ahora sí dice siempre el
  siguiente paso.

---

## 9. Playtest humano: qué mirar

- [ ] La intro se lee entera y el primer paso del panel es "Construye: Aserradero".
- [ ] El aserradero rechaza el sitio si no toca un bosque, y lo dice.
- [ ] Hacia el minuto 5 pasa la tormenta de prueba: se ve el Aviso y su consejo, cae
      ceniza, pasa la tormenta y escampa sin que bajen los Tasadores ni se rompa nada.
- [ ] Antes de la Fundición no hay más tormentas; la primera de verdad llega ~10 min después.
- [ ] La primera tormenta: el consejo del Aviso sale, la moral baja poco, el Diezmo se
      pelea (si hay cuartel) o se paga poco.
- [ ] El panel ¿QUÉ HACER? dice siempre algo que se puede hacer ahora o dice qué falta.
- [ ] Con cinco unidades (dos cañones) en casa el Diezmo se gana.
- [ ] En la era 3 la bolsa se llena: el panel pide comprar/vender y funciona.
- [ ] Con los cinco almacenes, el panel manda al árbol antes del CG nv3.
- [ ] El CG nv3 convoca el asedio y el consejo de la Auditoría sale.
- [ ] Perder el asedio no acaba la partida y el panel dice cómo volver.
- [ ] Ganar: el cielo se despeja, la pantalla de victoria da el tiempo jugado (no el de
      la pared), las tormentas, los Diezmos y los asedios; "Seguir jugando" deja el
      panel en mundo libre y no vuelve ninguna tormenta.
- [ ] Cronometrar: ¿cuánto tarda una persona en la era 1? ¿y un Diezmo en el tablero?
- [ ] ¿Aburre pelear el Diezmo por octava vez? (§7, primer riesgo)

---

## 10. Cómo repetirlo

```
# override.cfg en la raíz (temporal, sin commitear): la sonda escribe partidas
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="TI_linea"

godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5
godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1 --log=1
godot --headless --path . -s tools/line_probe.gd -- --no-dev --active=1
godot --headless --path . -s tools/line_probe.gd -- --no-dev --cfg.storm_morale_per_tick=2.0
```

`--cfg.clave=valor` pisa cualquier número de `GameConfig` solo en esa corrida (así se
hicieron las tablas de antes: §2.2 usa `storm_morale_per_tick=2.0
storm_damage_per_tick=0.06 storm_arm_phase=1 storm_interval_min=240.0
storm_interval_max=420.0 storm_first_interval=420.0 storm_first_tithe_has_floor=true
population_regrow_floor=0`). Una semilla tarda 1-4 min de reloj; conviene lanzar una por
proceso. La sonda se niega a correr sin carpeta de usuario propia.

---

## 11. Campaña de 4-6 horas (2026-10-12, 2026-10-14 y 2026-10-16)

Decisión de Bryan: una Campaña en Colono dura 4-6 h, la era 1 se queda en 8-12
min, las eras 2 y 3 traen más construcción y el final pide más ejército y más
preparación. Medido con `line_probe` (`--no-dev`, 10 semillas, sobre
`integracion/arte-v1` fusionada), minutos de partida:

| Semilla | Antes: era 2 | era 3 | victoria | Después: era 2 | era 3 | CG nv3 | victoria | era 1 | era 3 dura | Diezmos echados | asedios | huecos >3 min sin decidir | mayor |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 15 | 32 | 131 | 11 | 31 | 234 | **255** | 11,2 | 224 | 14/14 | 1 | 10 | 7,9 |
| 2 | 15 | 32 | 128 | 14 | 34 | 330 | **351** | 14,2 | 317 | 19/19 | 1 | 15 | 12,5 |
| 3 | 14 | 31 | 141 | 13 | 32 | 252 | **281** | 13,2 | 250 | 15/15 | 1 | 11 | 8,7 |
| 4 | 16 | 33 | 156 | 11 | 33 | 204 | **226** | 11,2 | 193 | 12/12 | 1 | 4 | 12,3 |
| 5 | 14 | 33 | 154 | 12 | 32 | 199 | **272** | 12,2 | 239 | 15/16 | 2 | 7 | 6,1 |
| 6 | 16 | 33 | 134 | 12 | 32 | 261 | **282** | 12,2 | 250 | 13/13 | 1 | 8 | 7,8 |
| 7 | 14 | 32 | 131 | 12 | 33 | 252 | **274** | 12,2 | 240 | 15/15 | 1 | 11 | 9,6 |
| 8 | 14 | 32 | 271 | 12 | 32 | 245 | **315** | 12,2 | 282 | 14/15 | 2 | 12 | 8,3 |
| 9 | 16 | 33 | 181 | 12 | 32 | 254 | **282** | 12,2 | 249 | 15/15 | 1 | 8 | 6,5 |
| 10 | 15 | 32 | 125 | 11 | 37 | 268 | **289** | 11,2 | 252 | 14/15 | 1 | 9 | 8,2 |

- **Antes**: 125-271 min, mediana ~2 h 13 min; era 1 de 14-16 min; hasta 35.000
  recursos tirados por vender con la bolsa llena; 25-48 muertos de hambre.
- **Después**: 226-351 min, **mediana 4 h 42 min** (9 de 10 entre 4 y 6 h); era 1
  de 11-14 min; lo desbordado baja a 60-790 (eventos aleatorios y ventas
  pequeñas); 10 de 10 victorias, 2 con un asedio perdido y reconvocado.
- Tras ganar (`--after=20`, medido en 3 semillas): 0 tormentas, 0 Diezmos, 0
  convocatorias, la Tormenta sigue parada tras guardar y cargar, el panel dice
  "mundo libre" y la colonia produce (la bolsa se llena y para, no se tira).

Lo que se movió y por qué:

| Valor | Antes | Después | Por qué |
|---|---|---|---|
| (bug) `PopulationManager` | puestos solo al terminar una obra | también al nacer o morir alguien | la 1.ª mina pasaba ~10 min sin obreros con la gente ya nacida: era 1 de 15 min |
| `starting_resources` | 300 / 200 / 80 | 330 / 180 / 80 | el oro frenaba la Fundición; la madera sobraba. Medido con 360/160; 330/180 deja hueco en la bolsa y Supervivencia paga la apertura |
| `building_prerequisites.refinery` | Fundición, Cuartel | + Laboratorio | una obra más en la era 2 y el árbol abierto antes del petróleo |
| `unit_types.artillery` | 80 oro / 30 acero, 35 s | 120 / 50, 45 s | guarnición de la era 2 algo más cara |
| `unit_types.vehicle` | 140 / 60 / 30, 55 s | 400 / 180 / 90, 100 s | los seis blindados son el último gran esfuerzo |
| `hq_upgrade_costs[2]` | 800/500/300/400 + 15 vigas/10 lingotes/15 combustible | 1300/900/500/300 + 100/70/100 | más bolsa (3.000) y mucho más taller |
| `hq_upgrade_costs[3]` | 3.500 + 25/20/25 | 3.500 + 200/140/200 | el invariante 3.500 = bolsa máxima no se toca; los materiales alargan con trabajo |
| `final_audit_waves` | 3-5 | 4-5 | final más exigente |
| `final_audit_last_wave_multiplier` | 1,05 | 1,10 | ídem |
| `storm_tower_garrison_max` | 2 | 4 | preparación: con la guarnición mermada caben más dotaciones; Objectives pide 4 torres antes del CG nv3 |
| `game_tier_rules.governor.audit_enemy_mult` | 1,06 | 1,05 | con 4-5 oleadas, ×1,06 dejaba la máxima en 49 % |
| `market_calendar` (Gobernador) | sin comida | comida +25 % Aviso, +40 % Tormenta, +15 % tras el Diezmo | sube antes del Diezmo, como el resto |

Arreglos en `Objectives.gd`: los requisitos de un edificio se piden antes que él
(con la Refinería pidiendo Laboratorio la partida se quedaba atascada para
siempre); las torres del asedio salen de `storm_tower_garrison_max`; con la
bolsa llena se compra la receta del taller (horas con 3.000 de oro y sin acero
para una viga); las ventas solo venden lo que cabe (tiraban miles de oro); un
productor de apoyo sin obreros libres no se pide si la gente ya viene de camino
(el fallo de `test_following_the_panel_walks_the_whole_line_to_the_siege`).
`OBJ_WHY_SAWMILL_2` ya no dice que la gente come madera.

**Falta**: los huecos sin decidir pasan de 3 min (4-15 por partida, el mayor de
6-12 min), casi todos ahorrando para el CG nv2/nv3 con la bolsa casi llena y
entrenando blindados. Probado a medias (sin medir): bajar
`Objectives.SLOW_RESOURCE_SECONDS` de 360 a 180 para que el panel pida otro
productor antes. La era 2 solo creció de ~17 a ~20 min (sin tocar los `.tres`
no hay más palanca que el Laboratorio y la artillería). La era 1 queda en 11-14
min para la sonda, en el borde alto. La moral pesa mucho en el asedio (doc 17).

### 2026-10-14: medido sobre la integración de la fase 1

Fusionada `integracion/arte-v1` con todo lo de la fase 1: isla irregular
(rejillas 60-74 con agua), ventaja por tipo en combate, topes de edificios por
era, procesos en lote y el Núcleo haciendo las recetas de todos los talleres,
escaramuzas (incursiones, repuestos para el nivel 3 de los productores). El
jugador de la sonda fabrica en lotes (también en el Núcleo), sale de incursión
cuando ¿QUÉ HACER? lo pide (`Objectives.sortie_step`: repuestos, puesto
avanzado, oferta nueva; solo en calma y a más de 4 min del Aviso) y no deja
columnas colgadas. 10 semillas por línea, `--no-dev`, en paralelo.

**Cómo se movió la duración** (mediana de la victoria, minutos):

| Medida | Qué había | Mediana | Rango | Huecos >3 min sin decidir | Mayor |
|---|---|---|---|---|---|
| 12-10, antes del balance | integración vieja | 133 | 125-271 | — | — |
| 12-10, balance (§11 arriba) | integración vieja | 282 | 226-351 | 4-15 | 6-12,5 |
| B | fase 1 sin escaramuzas, subir productor con lo que sobra | 214 | 191-443 | 4-23 | 4,9-19,8 |
| C | B + `SLOW_RESOURCE_SECONDS` 240 | 210 | 176-334 | 2-9 | 3,9-15,1 |
| D1 | C + taller del CG ×1,5 | 231 | 193-270 | 1-7 | 3,4-9,1 |
| D3 | C + taller del CG ×2 | 282 | 247-330 + 2 atascos | 3-27 | 5-38 |
| **Final** | D3 + venta de comida + escaramuzas | **282** | **238-368** | **3-15** | **4,9-11,3** |

**La tabla final**, por semilla:

| Semilla | Era 2 | Era 3 | CG | CG nv2 | CG nv3 | Victoria | Era 1 | Era 3 dura | Diezmos echados | Asedios | Huecos >3 min | Mayor | Desbordado | Incursiones | Casas / gente / comida al final |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 12 | 36 | 66 | 151 | 273 | **298** | 12,2 | 262 | 15/15 | 1 | 7 | 8,0 | 298 | 2 | 8 / 53 / 106 por min |
| 2 | 12 | 35 | 60 | 148 | 274 | **301** | 12,2 | 266 | 16/16 | 1 | 5 | 9,0 | 374 | 2 | 8 / 53 / 106 |
| 3 | 12 | 35 | 78 | 137 | 243 | **274** | 12,2 | 239 | 14/14 | 1 | 9 | 11,3 | 447 | 2 | 11 / 71 / 142 |
| 4 | 13 | 37 | 69 | 149 | 267 | **294** | 13,2 | 258 | 15/15 | 1 | 11 | 7,4 | 141 | 2 | 8 / 53 / 106 |
| 5 | 13 | 37 | 68 | 127 | 211 | **238** | 13,2 | 201 | 12/12 | 1 | 3 | 5,1 | 26 | 1 | 11 / 71 / 142 |
| 6 | 12 | 33 | 71 | 186 | 349 | **368** | 12,3 | 335 | 17/17 | 1 | 15 | 7,6 | 267 | 7 | 9 / 59 / 118 |
| 7 | 12 | 36 | 67 | 147 | 241 | **267** | 12,2 | 231 | 14/14 | 1 | 4 | 4,9 | 152 | 3 | 11 / 71 / 142 |
| 8 | 11 | 34 | 58 | 165 | 263 | **290** | 11,2 | 256 | 12/12 | 1 | 8 | 7,5 | 214 | 2 | 8 / 53 / 106 |
| 9 | 12 | 35 | 63 | 144 | 241 | **261** | 12,2 | 226 | 13/13 | 1 | 4 | 5,2 | 381 | 2 | 10 / 64 / 128 |
| 10 | 10 | 33 | 69 | 125 | 222 | **241** | 10,2 | 208 | 12/12 | 1 | 3 | 5,9 | 116 | 1 | 9 / 58 / 116 |

- **Duración**: 238-368 min, **mediana 4 h 42**; 9 de 10 entre 4 y 6 h (la
  semilla 5 se queda en 3 h 58). 10 de 10 victorias, todas al primer asedio. Todos
  los Diezmos echados.
- **Era 1**: 10-13 min (la era 2 llega en el minuto 10,2-13,2). Está en el borde
  alto de los 8-12.
- **CG**: nivel 2 entre el minuto 125 y el 186; nivel 3 (la convocatoria) entre
  el 211 y el 349.
- **Lo tirado por bolsa llena**: 26-447 por partida, y **todo** de eventos
  aleatorios (hallazgo, caravana, buena cosecha): la producción y las ventas ya no
  tiran nada (antes de §11, hasta 35.000).
- **Consumo**: ninguna partida llega a 20 casas. Las que más gente tienen acaban
  con 11 casas, 71 personas y 142 de comida por minuto (6-7 granjas). Las 20
  casas que dejan los topes de la era 3 no se usan: el panel no las pide.
- **Tras ganar** (3 semillas, 20 min): 0 tormentas, 0 Diezmos, 0 convocatorias, y
  la Tormenta sigue parada tras guardar y cargar.
- **Huecos sin decidir**: 3-15 por partida, el mayor de 4,9-11,3 min. Por paso
  pedido: entrenar blindado (13 huecos en total), fabricar tablones al empezar la
  era 2 (9), fabricar combustible (9), vender comida (7).

Valores movidos este día y por qué:

| Valor | Antes | Después | Por qué |
|---|---|---|---|
| `hq_upgrade_costs` (materiales) | 100/70/100 y 200/140/200 | **200/140/200 y 400/280/400** | con los lotes y el Núcleo, el taller va mucho más rápido: la campaña había bajado a ~3 h 35 (B, C) |
| `Objectives.SLOW_RESOURCE_SECONDS` | 360 | **240** | pide otro productor antes: de 4-23 a 2-9 huecos (C) |
| `Objectives._surplus_upgrade_step` | — | nuevo | con la bolsa casi llena y el paso esperando un recurso lento, sube el productor que frena con lo que sobra |
| `Objectives._surplus_research_step` | — | nuevo | después, investiga con lo que sobra (producción, moral, logística) |
| `Objectives._sell_step` | solo petróleo/acero/madera | **+ la comida que sobra (8 ciclos de reserva)**, y la venta mayor que quepa | la comida se vende casi 1:1 y no tira oro; sin ella, 2 de 10 partidas se atascaban ante el CG nv3 con la bolsa llena (D3) |
| `final_audit_artillery_share` | 3 | **3** (se queda) | con la ventaja por tipo y las 4-5 oleadas, 1 de cada 4 cañones deja el final en trámite (97,5 %); con 3, 86 % (docs/17) |

**Falta**:

- Los huecos de más de 3 min no bajan de 3-15 por partida. Casi todos son
  esperas de recursos que el panel no llena:
  - el blindado (400/180/90): se podría abaratar a cambio de más materiales, o
    permitir entrenarlo pagando con repuestos;
  - los tablones del Cuartel al llegar a la era 2: madera escasa en el minuto 12;
  - el combustible: poco petróleo con una refinería.
- La era 1 queda en el borde alto.
- Nadie usa las 20 casas que deja la era 3.
- La semilla 5 se queda a 2 min de las 4 h.
- Riesgo de la sonda: 20 Godot en paralelo comparten carpeta de usuario. En 1 de
  60 corridas la partida arrancó rota (hitos vacíos, Fundición en el minuto 2) y
  se descartó.

### 2026-10-16: los huecos sin decidir (rama `balance/huecos`)

Meta de Bryan: algo que decidir cada 2-3 minutos. Con la medida del 14-10 quedaban
3-15 esperas de más de 3 min por partida, casi todas esperando recursos que ¿QUÉ
HACER? no llenaba (el blindado, los tablones del Cuartel al entrar en la era 2, el
combustible), y nadie pasaba de 13 casas.

**Cómo se midió.** `line_probe`, `--no-dev`, semillas 1-10, sobre
`integracion/arte-v1` con el tutorial nuevo fusionado. Cinco Godot a la vez, cada uno
con su carpeta de usuario y su copia del proyecto (dos semillas por proceso). El
jugador de la sonda levanta además el **Laboratorio que pide el tutorial** antes de
la Fundición (`--tutorial=0` lo quita). "Antes" es esa misma integración sin los
cambios de esta rama, medida igual.

> **Ruido de la sonda.** La misma semilla da resultados distintos según cuántos
> Godot corren a la vez (la sonda avanza con DT fijo, pero cede un fotograma cada
> 300 s y lo que va con reloj real se mueve): una semilla sola con `--log=1` puede
> acabar 90 min antes o después que en el lote. Compare lotes medidos con la misma
> carga, nunca una corrida suelta contra una tabla.

| Semilla | Antes: era 2 | CG nv3 | victoria | huecos >3 min | mayor | casas | Después: era 2 | CG nv3 | victoria | huecos >3 min | mayor | casas / gente |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 14,9 | 287 | **315** | 8 | 9,0 | 12 | 14,9 | 273 | **292** | 5 | 9,2 | 22 / 137 |
| 2 | 15,2 | 297 | **316** | 10 | 7,8 | 12 | 15,2 | 228 | **253** | 2 | 5,4 | 11 / 71 |
| 3 | 17,2 | 243 | **271** | 7 | 5,5 | 9 | 17,2 | 224 | **245** | 3 | 4,4 | 11 / 71 |
| 4 | 15,2 | 294 | **315** | 9 | 5,5 | 8 | 15,2 | 261 | **289** | 6 | 6,6 | 19 / 119 |
| 5 | 15,2 | 242 | **269** | 4 | 5,7 | 8 | 15,2 | 226 | **251** | 4 | 10,0 | 16 / 101 |
| 6 | 16,2 | 244 | **271** | 7 | 5,6 | 11 | 16,2 | 309 | **334** | 4 | 3,2 | 23 / 143 |
| 7 | 16,2 | 262 | **282** | 4 | 6,4 | 8 | 16,2 | 263 | **284** | 3 | 5,9 | 24 / 149 |
| 8 | 15,2 | 285 | **312** | 6 | 4,9 | 9 | 15,2 | 234 | **259** | 2 | 4,7 | 22 / 137 |
| 9 | 15,2 | 277 | **347** | 8 | 4,9 | 10 | 15,2 | 224 | **251** | 1 | 3,0 | 11 / 71 |
| 10 | 13,2 | 260 | **280** | 7 | 4,4 | 9 | 13,2 | 252 | **279** | 4 | 7,4 | 24 / 149 |

- **Duración**: antes 269-347 min, mediana 297 (4 h 57); después **245-334, mediana
  269 (4 h 29)**. Las diez entre 4 y 6 h, 10 de 10 victorias, todas al primer asedio
  (antes una necesitó dos). Todos los Diezmos echados salvo uno.
- **Huecos de más de 3 min sin decidir nada**: antes 4-10 por partida (70 en diez);
  después **1-6 (34)**. El mayor, 4,4-9,0 antes y 3,0-10,0 después (una espera de 10
  min en la semilla 5, con la bolsa clavada antes del CG nv3).
- **Dónde quedan**: fabricar combustible (8 de los 34), una Mina de oro en la era 1-2
  (6), vender madera con la bolsa llena (4) y el Laboratorio del tutorial (3). Los del
  blindado bajan de 18 a 1 y los de las casas de 10 a 0. Los de los tablones al entrar
  en la era 2 (9 de 10 partidas el 14-10, y antes del tutorial nuevo) se fueron con el
  Cuartel nuevo: 0 en la medida intermedia sin tutorial, 1 en esta.
- **Casas**: antes 8-12 al final; después **11-24** (el tope de la era 3 es 20, más
  lo que da el rango), con 71-149 personas.
- **Era 1** (el minuto de la era 2): 13,2-17,2 min, igual antes y después. **Ya no
  está en 8-12**: el tutorial nuevo pide Mina, Mercado, Almacén y Laboratorio antes de
  la Fundición, y el Laboratorio (150 oro, 100 madera) son ~3 min más que la línea de
  ¿QUÉ HACER? sola (10,2-13,2 el 14-10). No se tocó: es una decisión del tutorial.
- **Lo que se pierde vendiendo con la bolsa llena** (oro que no cabe): antes 0-464 por
  partida; después **1.200-7.800**. Es el precio de no quedarse clavado: sin vender así,
  dos partidas de diez se quedaban horas (una sin acabar) ante el CG nv3 con 4.104 de
  4.104, el oro justo y la bolsa llena de madera, acero o comida.
- **El asedio**: `siege_probe --seeds=200 --towers=4` sigue en **86 %** con seis
  blindados (69 % con cinco); `final_audit_artillery_share` sigue en 3. El blindado
  cambia de precio, no de fuerza.

Valores movidos y por qué:

| Valor | Antes | Después | Por qué |
|---|---|---|---|
| `unit_types.vehicle.cost` | 400 oro / 180 acero / 90 petróleo | **300 / 130 / 60 + 8 vigas** | casi lo mismo en recursos (8 vigas = 40 acero y 20 madera), pero la espera de 400 de oro se parte en dos decisiones: fabricar vigas y entrenar. Huecos del blindado: 18 → 1 |
| `barracks.tres` | 250 oro / 100 acero / 80 madera + 10 tablones | **150 / 60 / 80 + 20 tablones** | al entrar en la era 2 la Fundición deja el oro a 25: el Cuartel eran 5 min sin nada que hacer. Ahora el oro y el acero llegan en ~3 min y los tablones son una decisión más |
| `hq_upgrade_costs` (vigas) | 200 y 400 | **350 y 700** | con las esperas llenas y más casas la campaña bajaba a ~4 h 10 (cuatro de diez por debajo de 4 h). Las vigas porque eran las que menos esperas dejaban (hasta 6 fundiciones; el acero sobra en la era 3) |
| `Objectives._while_saving_step` | — | nuevo | si lo que falta tarda más de `WAIT_FILL_SECONDS` (90 s) y la bolsa no está a rebosar: subir el productor de lo que frena, investigar o un adorno si la moral baja de 80. Todo pagado con lo que el paso no pide |
| `Objectives.house_room_step` | — | nuevo | la gente al tope, comida para los seis que vienen y cuatro ciclos en el granero: otra casa, pagada con lo que sobra. Va antes de esperar |
| `Objectives._support_or` (taller) | "Fabrica X" aunque faltara la receta | si a la receta le falta algo, lo mismo que con cualquier paso: otro productor o algo útil | la espera es la de todas las vueltas (los 200 de combustible del CG nv2 son 600 de petróleo), no la de una |
| `Objectives._make_room_step` | — | nuevo | bolsa a rebosar y lo que falta no entra: pasar lo que sobra al taller (combustible, tablones, vigas, lingotes), que no ocupa bolsa |
| `Objectives._unclog_step` | solo vendía lo que cabía | con la bolsa clavada, vende lo más barato que sobre aunque el oro no quepa entero (`PINNED_SALE` 300), y de la comida guarda tres ciclos en vez de ocho | sin esto, bolsa clavada hasta el final (ver arriba) |
| `Objectives._sell_step` | vendía desde 5 unidades | **desde `MIN_SALE` (20)** | vendía 7 de comida cada 30 s durante minutos sin avanzar |
| `tools/line_probe_player.gd` | — | levanta el Laboratorio del tutorial en la era 1 (`--tutorial=0` no) | medir la era 1 del jugador que sigue el tutorial |

`OBJ_WHY_SURPLUS_*` se acortaron a menos de 16 palabras (`test_every_why_fits_in_a_short_sentence`)
y hay tres textos nuevos: `OBJ_WHY_HOUSE_ROOM`, `OBJ_WHY_DECORATE`, `OBJ_WHY_MAKE_ROOM`.

**Falta**:

- La era 1 con el tutorial está en 13-17 min. Para volver a 8-12 haría falta abaratar
  el Laboratorio o sacarlo del tutorial; no se tocó aquí.
- Combustible: sigue siendo la espera que más se repite (400 de combustible = 1.200 de
  petróleo para el CG nv3).
- El oro que se pierde vendiendo con la bolsa clavada (hasta 7.800). La raíz es que la
  bolsa máxima (3.500 + tecnologías) es casi el precio del CG nv3 y la comida de 100
  personas también ocupa bolsa.
- Los tests no se corrieron en esta rama (encargo: sondas sí, tests no). Los que más
  pueden notarlo: `tests/ui/test_objectives.gd` (un paso de casa puede salir antes que
  el que esperaban si la gente está al tope) y los que miran el coste del Cuartel o del
  blindado.

## 12. Cuartel temprano (2026-10-17, rama `feat/cuartel-temprano`)

Decisión de Bryan ("prioridad después de la madera", opción A del informe 26 del
contexto privado). La tabla de valores es de diseño; lo medido con la sonda de línea
(3 semillas) está en "Medido", al final de la sección.

| Valor | Antes | Después | Por qué |
|---|---|---|---|
| `barracks.tres` coste | 150 oro / 60 acero / 80 madera + 20 tablones | **120 / 0 / 80 + 10 tablones** | era 1 sin acero; los tablones (2 vueltas de 20 madera en el Aserradero) siguen siendo una decisión de taller |
| `barracks.tres` trabajadores | 3 | **1** | aserradero (2) + Cuartel (1) + Granja (2) = los 5 del Núcleo: con 3, la Granja se quedaba sin gente hasta la primera Casa y el tutorial se torcía. Un Cuartel sin gente entrena igual (los trabajadores no le daban nada) |
| `building_prerequisites.barracks` | Fundición + Aserradero | **Aserradero** | de ahí salen los tablones |
| `building_prerequisites.tower` | Cuartel | **Cuartel + Fundición** | antes el Cuartel ya implicaba la Fundición; la Torre pide acero y vigas |
| `building_limits_by_era.barracks` | 3 / 4 / 5 | sin cambio (y desde el 18-10-2026, **sin tope**: el freno pasa a la tropa, 3 + 8×3 + 4 por cuartel más, techo 43, y 5 a la vez; docs/03 "Cuartel sin tope") | 3 en la era 1 ya basta (cada uno es una plaza de entrenamiento) |
| `Objectives.LINE` | aserradero, granja, mina, casa, mercado, almacén, fundición, **cuartel**, guarnición… | aserradero, **cuartel** (`needs: tithe`), granja, **1 soldado** (`any`, `needs: tithe`, fila de la primera misión detrás), mina, casa, mercado, almacén, fundición, guarnición… | el Cuartel va antes que la Granja porque la comida de salida (80) dura ~16 min con 5 personas en las fases tempranas y el Cuartel ya no le quita gente. En Constructor (sin Impuesto) el Cuartel sigue tras la Fundición (`needs: no_tithe`) |
| Tormenta de prueba | sin Diezmo | **Impuesto de juguete** (`storm_trial_tithe_*`): con tropas en casa, defensa en el tablero contra 1-2 Cobradores de Infantería a escala 0,6 (combate guiado si es la primera pelea); sin tropas, 10 % de la bolsa con tope 40. Nunca edificios, trabajadores ni daño; no emite `tithe_resolved` (ni Mercado, ni rebaja, ni escolta que crece) sino `trial_tithe_resolved`, con su parte en `WarReportScreen` | que el Cuartel temprano se entienda antes de la Tormenta de verdad |

**Coste extra en la era 1:** Cuartel 120 oro + 80 madera + 40 madera de tablones, y un
soldado 40 oro + 20 madera (sueldo 1 oro / 30 s). Unos 160 oro y 140 madera más antes de
la Fundición; la primera misión devuelve parte (oro y madera). A ojo, +1-2 min de era 1
(de 13-17 a ~14-19 con el tutorial); el tope pedido por Bryan es "que no se alargue
mucho".

### Medido (2026-10-17, ronda de pruebas de la 1.0)

`line_probe`, `--no-dev`, semillas 1-3, un solo Godot, sobre
`integracion/1.0-cuartel-topes` con los arreglos de esta ronda. "Antes" son las mismas
semillas en la tabla del 16-10 (§11, con otra carga: compárese con cuidado).

| Semilla | Cuartel | 1.er soldado | 1.ª misión ganada | Impuesto de juguete | era 2 (antes) | era 3 | CG nv3 | victoria (antes) | huecos >3 min sin decidir | mayor |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **17,8** (14,9) | 35 | 187 | **214** (292) | 2 | 4,0 |
| 2 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **18,8** (15,2) | 37 | 252 | **272** (253) | 2 | 4,6 |
| 3 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **16,8** (17,2) | 35 | 207 | **234** (245) | 1 | 3,5 |

- **Era 1: 16,8-18,8 min** (antes 14,9-17,2): +1,5 a +3,6 min, en el borde de "si pasa de
  ~18 min" que se dejó como alarma. La tormenta de prueba llega en el 6,8 y el soldado ya
  está en casa: el Impuesto de juguete se repele siempre (0 de bolsa perdido).
- **Campaña: 214-272 min** (3 h 34 - 4 h 32), las tres ganadas al primer asedio. La
  semilla 1 queda por debajo de 4 h; con tres semillas y otra carga no se puede separar
  del ruido (ver el aviso de §11).
- Las esperas sin decidir siguen cortas (1-2 huecos de más de 3 min, el mayor 4,6).

**Arreglos de esta ronda** (en `Objectives.gd`; sin ellos la sonda se atascaba):

| Fallo | Arreglo |
|---|---|
| El Cuartel salía el sexto: la Granja (comida en negativo), una Casa y la Mina se le colaban como pasos de apoyo | entrada `eager` en `LINE`: si se puede pagar ya (los tablones en el taller cuentan) y tiene obrero, va antes que los apoyos |
| **Atasco de 8 h** en las tres semillas: dos Casas de golpe en el minuto 4 (la primera aún en obra no contaba como sitio), el oro de la Mina se iba en ellas y el sueldo del soldado dejaba el oro a 0 sin ningún productor | `_houses_would_help` cuenta el sitio de las casas en obra (`_room_on_the_way`) |
| "Fabrica tablones" seguía con el lote en marcha y se pagaba dos veces (80 de madera por 20 tablones) | `make_step_for` resta lo que ya se fabrica (`in_production`) |
| Con el Aserradero en ruinas se pedían tablones (que solo él hace) | reparar va antes que el taller en `_support_or` |

**Falta**:

- Diez semillas (con y sin `--tutorial=0`) para separar la era 1 y la duración del ruido.
- Si la era 1 se confirma por encima de 18 min: abaratar el Cuartel a 100 oro o quitar el
  soldado de la línea (la misión ya lo pide en cuanto hay uno).
- El tutorial pide el Laboratorio (2 trabajadores) con 1 libre: el Cuartel se lleva el
  que sobraba, así que el paso 13 siempre dice "Haz otra Casa" antes. No se atasca, pero
  es un paso más.

### Medido en la 1.1 (2026-10-17, merge de la 1.0 en `integracion/v1.1-aire-mar`)

`line_probe`, `--no-dev`, semillas 1-3, un solo Godot. "Antes" es la misma sonda sobre
`integracion/v1.1-aire-mar` justo antes del merge (bca7cb5: aire, mar, Muelle de pesca y
edificios útiles, sin el Cuartel temprano ni el Impuesto de juguete), corrida el mismo día
con la misma carga.

| Semilla | Cuartel | 1.er soldado | 1.ª misión | Impuesto de juguete | era 2 (antes) | era 3 (antes) | CG nv3 (antes) | victoria (antes) | huecos >3 min sin decidir (antes) | mayor (antes) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **17,8** (14,9) | 35 (49) | 231 (307) | **250** (334) | 4 (8) | 4,9 (11,8) |
| 2 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **18,8** (15,2) | 35 (33) | 344 (247) | **363** (266) | 11 (3) | 10,7 (5,7) |
| 3 | 0,4 | 2,3 | 3,0 | repelido en el 8,6 (1 en casa) | **16,8** (17,2) | 33 (38) | 176 (237) | **202** (256) | 2 (5) | 5,3 (6,4) |

- **No se atasca**: las tres ganan al primer asedio (13/13, 19/19 y 11/11 Diezmos
  repelidos). El Cuartel temprano sale en el minuto 0,4, el soldado en el 2,3, la primera
  misión en el 3,0, y el Impuesto de juguete se repele siempre. La era 1 queda igual que
  en la 1.0 (16,8-18,8 min, +1,5 a +3,6 sobre la 1.1 sin Cuartel temprano).
- **Campaña: 202-363 min** (antes 256-334; media 272 frente a 285). La semilla 2 pasa
  de 6 h: 82 min esperando el CG nivel 2 con la bolsa llena 108 min (vigas y combustible
  del taller); las semillas 1 y 3 acortan. Con tres semillas es ruido; mirar con diez.
- **El jugador de la sonda no usa la 1.1**: no levanta Muelle, Astillero, Aeródromo ni
  edificios útiles (la línea no los pide; el Muelle solo sale como apoyo de comida cuando
  no cabe otra Granja, y la sonda nunca llegó ahí: 6-9 Granjas). Así que estas cifras
  dicen que el Cuartel temprano no rompe la 1.1, no cuánto ayudan el Muelle o la flota.
- Pendiente: que `line_probe_player` sepa colocar el Muelle (orilla + banco de peces) y
  el Astillero (costa), y medir con diez semillas.


## 13. Medido con extras de la 1.1 (rama `feat/sonda-costa`)

La línea (§1-§12) la juega un jugador que sigue ¿QUÉ HACER?, y ¿QUÉ HACER? no pide nada de
la 1.1: ni Muelle de pesca (solo como apoyo de comida cuando no cabe otra Granja), ni
edificios útiles, ni Astillero o Aeródromo (salen en la segunda línea, `fleet_step()`), ni
barcos o aviones. Para saber cómo rinden en una partida, la sonda tiene un **jugador
completo**: `--extras=1` (o `--player=completo`). Sin la opción la sonda juega exactamente
como antes (el código nuevo no corre), así que las dos tandas se comparan.

### Qué hace el jugador completo

Sigue la línea igual (el mismo paso de ¿QUÉ HACER? en cada vistazo) y, después, **una**
acción de extras por vistazo, por este orden:

1. **Misión de costa** cada 6 min como mucho: una oferta del tablón con agua
   (`CombatManager.offer_has_water`), en calma, a más de 5 min del siguiente Aviso y sin
   asedio convocado. Columna: barcos y aviones al frente, más la tierra que sobre de la
   guarnición (en casa quedan al menos 2 de tierra y la mitad). Solo si la columna no es
   más floja que el enemigo más duro (`sortie_preview`), con "resolver solo" si el juego
   lo deja; si la oferta es de varios combates, elige la primera carta del draft y sigue.
2. **Muelle de pesca** junto a un banco de peces (la regla del juego, `buildable_spots_near`):
   ya, aunque cueste, si la comida por delante baja de 8 min; si no, hasta dos mientras sea
   barato.
3. **Astillero / Aeródromo** cuando los propone `Objectives.fleet_step()` (era 2 / era 3),
   en calma. El Astillero en una casilla de costa, girado hacia el agua con
   `Rules.steps_facing_water` (el mismo giro que el fantasma del juego).
4. **Edificios útiles**, cada 20 s, uno a la vez: Molino con dos o más Granjas a su radio
   (uno por cada dos Granjas, hasta dos); Silo y Depósito de combustible si la bolsa pasa
   del 80 % y hay comida (>150) o petróleo (>200) que sacar de ella; Taberna a radio de dos
   casas con más de 10 min de comida por delante; Pozo (junto a la producción) y Faro (en la
   costa si cabe) cuando la Tormenta de verdad está armada; Carpintería desde la era 2.
5. **Flota**: era 2, una Cañonera y una Lancha; era 3, dos Cañoneras, una Lancha, dos Cazas y
   un Bombardero. En calma, sin pasar del tope de tropa (`ArmyManager.can_train`). Los
   materiales que pida (tablones, vigas, combustible) se fabrican antes en su taller.

Nada de trampas: cada obra pasa por rango, tope, requisitos, obreros y coste (lo mismo que
`purchase_block_message`), el hueco por `evaluate_placement`, la carretera se paga a 1 oro
el tramo y se coloca con `_try_place` como un clic. Para no retrasar la línea, un extra
solo se paga si el paso principal sigue pudiéndose pagar después, o si no pasa del 25 % de
lo que hay de cada recurso (salvo el Muelle con hambre), y siempre con el colchón de la
tropa.

### Cómo lanzarlo

Con un `override.cfg` de carpeta propia (por ejemplo `TI_sonda_costa`, ver §10), headless:

```
godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5
godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5 --extras=1
```

Además de lo de siempre, cada semilla imprime dos líneas `1.1 …` y, al final, una tabla
"extras" con:

- minuto en que se termina el **primer** edificio de cada tipo nuevo (Muelle, Molino, Silo,
  Taberna, Carpintería, Pozo, Faro, Depósito, Astillero, Aeródromo);
- **comida recogida del Muelle** (y la que se estropeó en él);
- flota entrenada por tipo;
- **misiones de costa** lanzadas / ganadas / perdidas / abandonadas, y las descartadas por
  columna floja;
- duración de era 1, 2 y 3, minuto de la victoria y **huecos > 3 min sin decidir**;
- "sin hueco": cuántas veces un extra no encontró sitio (pista de mapa o regla rota).

La tabla de la línea de siempre se imprime igual en los dos modos: comparar era 2, era 3,
CG nv3, victoria, huecos y bolsa llena columna a columna.

### Medido (2026-10-18, ronda de pruebas de la 1.1, rama `prueba/v11-linea`)

`line_probe`, `--no-dev`, semillas 1-5, tope 8 h, un solo Godot, sobre
`integracion/v1.1-aire-mar` (aa04fad) con los arreglos de esta ronda (§14 "Medido").
Las dos tandas con campañas (lo de siempre desde §14). Minutos de juego.

**Jugador de la línea** (sin `--extras`):

| Semilla | era 1 | era 3 en | CG nv2 | CG nv3 | Tierra completa | Mar | Aire | Ataque Final | victoria | huecos >3 min sin decidir (mayor) | bolsa llena |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 17,8 | 37 | 117 | 295 | 247 | 4/5 | 0/5 | — | **no (8 h)** | 9 (14,0) | 127 |
| 2 | 18,8 | 41 | 136 | 367 | 240 | 447 | 4/5 | — | **no** | 8 (13,2) | 102 |
| 3 | 19,8 | 40 | 153 | 394 | 403 | 470 | 2/5 | — | **no** | 9 (12,4) | 103 |
| 4 | 17,8 | 37 | 131 | 325 | 289 | 427 | 4/5 | — | **no** | 3 (11,9) | 114 |
| 5 | 16,8 | 39 | 122 | 233 | 216 | 327 | 4/5 | — | **no** | 13 (14,9) | 140 |

**Jugador completo** (`--extras=1`):

| Semilla | era 1 | era 3 en | CG nv3 | Tierra | Mar | Aire | Ataque Final | victoria | huecos >3 min (mayor) | Astillero / Aeródromo | flota entrenada |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 20,8 | 43 | 306 | 314 | 376 | 458 | 470, 5/5 oleadas, GANADO | **498** (8 h 18) | 4 (7,4) | 31 / 71 | 63 |
| 2 | 22,8 | 47 | 344 | 295 | 409 | 448 | 449, 5/5, GANADO | **476** (7 h 56) | 10 (9,2) | 66 / 143 | 53 |
| 3 | 21,8 | 43 | 270 | 295 | 339 | 377 | 400, 4/4, GANADO | **423** (7 h 03) | 4 (4,0) | 70 / 86 | 68 |
| 4 | 20,8 | 44 | 275 | 255 | 336 | 4/5 | — | **no (8 h)** | 7 (4,3) | 68 / 84 | 96 |
| 5 | 21,8 | 47 | 313 | 285 | 381 | 3/5 | — | **no (8 h)** | 13 (11,1) | 41 / 76 | 64 |

Primer edificio de la 1.1 con el jugador completo: Muelle en el minuto 7 (las cinco),
Pozo 24-43, Silo 45-88, Carpintería 43-159, Faro 111-156, Depósito 111-170; Taberna en
dos de cinco y Molino en una (sin hueco: 220-350 intentos, las Granjas quedan en 1-4
porque el Muelle da la comida: 47-71 mil de comida en la partida). **Misiones de costa:
0** en todas: las mixtas están apagadas (`combat_mixed_missions_enabled = false`), así
que esa parte del jugador completo ya no hace nada.

Lectura:

- **Ninguna partida de la línea gana en 8 h, y el jugador completo gana 3 de 5 en
  7 h-8 h 20.** El objetivo era 4-6 h. Detalle de por qué, en §14 "Medido".
- **Era 1:** la línea 16,8-19,8 min (como en §12). El jugador completo 20,8-22,8: el
  Muelle (minuto 7), el Pozo y la flota de la era 2 le cuestan 3-4 min.
- **Huecos sin decidir:** 3-13 de más de 3 min por partida, el mayor 4-15 min, casi
  todos con el CG nv3 hecho y el panel en "la misión del Mar/Aire" (la tropa descansa o
  se está reponiendo). Antes del CG nv3 no hay atascos.

## 14. Las tres campañas (2026-10-18, rama `feat/tres-campanas`; medido al final)

El Ataque Final pide ahora el CG nivel 3 **y** las campañas de Tierra (5 + jefe),
Mar (4 + jefe) y Aire (4 + jefe): 16 misiones y 30 combates
([15-combat.md](15-combat.md) §13). La línea principal (`Objectives.LINE`) **no
cambia**: las campañas van en la segunda línea de ¿QUÉ HACER?
(`Objectives.campaign_step()`) mientras se construye, y solo pasan a ser el paso
principal cuando el CG ya está a nivel 3 y falta alguna (`campaign_gate_step()`:
su edificio, tropa de su medio —3 por defecto, `campaign_suggested_party`— o la
misión). EL CAMINO lleva la fila "Las tres campañas (N de 3)" antes del Ataque Final.

**El jugador de la sonda** (`tools/line_probe_player.gd`) las juega:

- en calma y a más de 5 min del Aviso, la misión que propone `campaign_step()`, con
  lo más fuerte de su medio (en tierra deja la mitad de la guarnición en casa), solo
  si su fuerza no es menor que la del enemigo más duro de la misión;
- con el CG a nivel 3, lo que pida la línea (Astillero en la costa, tropa, misión),
  aunque la fuerza no llegue;
- elige siempre la primera carta del draft entre combates;
- `--campaigns=0` juega solo lo segundo.

Imprime por semilla el minuto de cada misión ganada, cuándo se completa cada campaña
y las fallidas; la tabla gana las columnas **tierra / mar / aire**.

**Qué mirar en la ronda final** (diez semillas, `--no-dev`): que la victoria siga en
4-6 h (la estimación es 1,5-2 h de tablero repartidas por las tres eras, con la base
corriendo); que ninguna campaña se atasque (el Leviatán con solo barcos de la era 2,
el Zepelín con solo cazas); que la espera tras el CG nv3 no sea "jugar las tres
campañas de golpe". Palancas, por orden: `campaign_defs` (misiones y combates),
`campaign_level_step`, `campaign_boss_extra_scale` / `campaign_boss_heavies`,
`campaign_mission_cooldown`.

### Medido (2026-10-18, ronda de pruebas de la 1.1, rama `prueba/v11-linea`)

Las tablas por semilla (línea y jugador completo) están en §13 "Medido". Aquí, lo que
se encontró en las campañas, lo que se arregló y lo que queda de balance.

**Primera tanda, antes de arreglar nada** (aa04fad tal cual, semilla 1): 8 h sin CG
nv3. El jugador de la sonda salía a la misión 1 de Tierra con **2 cuerpos** (la mitad de
la guarnición se quedaba en casa y la vista previa decía "fuerza 56 contra 34") y perdía
una y otra vez: 33-42 derrotas, 134-143 bajas en la partida, el CG nv2 en el minuto
325-438 por estar reponiendo tropa. Con `--campaigns=0` (campañas solo tras el CG nv3)
la misma semilla llegaba al CG nv3 en el 237, pero luego Mar y Aire no cabían en las 8 h.

**Arreglos** (sin tocar una cifra de balance):

| Fallo | Dónde | Arreglo |
|---|---|---|
| Columna de 2 a la misión 1 de Tierra, derrota tras derrota | `tools/line_probe_player.gd` (jugador) | columna **mezclada** (tierra y mar, un poco de cada tipo; aire, solo cazas: el dirigible propio estorba, docs/15 §13), al menos 3 cuerpos; cada derrota en la misma misión pide uno más y un 25 % más de fuerza. Con la línea pidiéndola (tras el CG nv3) sale con la columna **llena** (6), entrenando antes lo que falte, o con lo que haya si el tope de tropa no deja |
| Tras el CG nv3 el oro se quedaba en las minas: el paso "misión" no cuesta nada, la recogida con la bolsa >75 % solo cogía oro por debajo de 200, y la bolsa se llenaba de comida y acero (oro clavado en 320 durante horas, 50-120 min en "la misión del Mar") | `tools/line_probe_player.gd` (jugador) | con el CG nv3 hecho, el oro se recoge hasta 1500 |
| Muelle "urgente" en el minuto 0,1 con el oro de la salida: en 2 de 5 semillas la Casa (50) y la Mina (120) no se pagaban nunca (oro 42, bolsa llena, los 5 obreros ocupados) | `tools/line_probe_player.gd` (jugador completo) | ningún extra antes de la primera Mina de oro |
| **¿QUÉ HACER? se quedaba en "la misión del Mar" mientras su tropa descansaba**, y el Aeródromo no se pedía hasta acabar el Mar (Aeródromo en el minuto 441-477, con el Mar hecho en el 440-477) | `scripts/services/Objectives.gd` (`campaign_gate_step`, juego) | si la campaña que toca no se puede lanzar ya y solo espera, el paso es preparar otra que falte (su edificio o su tropa). Ahora el Aeródromo sale 16-21 min después del Astillero. Test: `tests/ui/test_campaign_gate_prep.gd` |

**Problemas de balance que quedan** (no se tocaron: son cifras; el balance de combate
lo lleva otra rama):

1. **La campaña no cabe en 4-6 h.** Jugador de la línea: 0 de 5 gana en 8 h (Mar
   completo en 4 de 5, Aire 0-4 de 5). Jugador completo, que levanta Astillero (31-70)
   y Aeródromo (71-143) en cuanto ¿QUÉ HACER? los propone en la segunda línea: 3 de 5
   ganan, en 7 h 03 - 8 h 18, y las otras dos se quedan en el Aire (3-4 de 5). Del CG
   nv3 a la victoria pasan 132-192 min: las campañas de Mar y Aire se juegan casi
   enteras después del CG nv3.
2. **El CG nv3 llega más tarde que sin campañas:** 233-394 min con la línea (antes de
   las campañas, §12: 176-344). La Tierra se juega durante la construcción (completa en
   el 216-403) y sus bajas y su reposición se comen oro de la era 3.
3. **El Diezmo se come la tropa de las campañas.** Se repelen casi todos los Diezmos (23-28
   de 23-28 por partida), pero con una escolta que ha crecido mucho: la guarnición que defiende (barcos
   y aviones incluidos) cae casi entera. Ejemplo, línea, semilla 5: Diezmo del minuto
   337, repelido, 5 blindados, 1 acorazado y 2 cazas muertos; 365, 389 y 455: cazas de
   4-5 a 2. Cada ciclo de Tormenta (~16 min) hay que reponer la columna antes de la
   siguiente misión. Palancas: el crecimiento de la escolta del Diezmo, o que las
   unidades de mar y aire no defiendan el Diezmo.
4. **El oro se acaba en cada Tormenta.** Con la producción parada en la fase de
   Tormenta, el sueldo y la comida dejan el oro a 0 casi en cada ciclo de la era 3
   (deserciones: 10-33 la línea, 13-45 el completo). Los 6 blindados que pide la línea
   para el asedio (`OBJ_WHY_ARMOUR`, tras el CG nv2) cobran 24 oro / 30 s y esperan
   2-3 h a que acaben las campañas. Palanca no numérica a valorar: pedir esos blindados
   cuando el Ataque Final ya se puede convocar, no antes del CG nv3.
5. **El Aire es el cuello de botella.** Con 6 cazas la vista previa da 240 contra
   244-253 en las misiones 1-3: se ganan, pero perdiendo 2-3 cazas (200 oro cada uno).
   En las dos partidas del completo que no ganan, el Aire se queda en 3-4 de 5.
6. **¿QUÉ HACER? pide 3 de tropa por campaña** (`campaign_suggested_party = 3`) y la
   columna que gana es de 6 (docs/15 §13: 3 cazas pierden el 100 % de la misión 1 del
   Aire; 3 infantes, la 2 de Tierra). Un jugador que hace caso al panel pierde la
   primera vez.
7. **La vista previa engaña con columnas pequeñas:** "fuerza 56 contra 34" (2 cañones)
   perdía siempre la misión 1 de Tierra. La comparación por potencia no ve que 2
   cuerpos contra 3 pierden por número.

**Ruido:** la misma semilla no repite partida entre corridas (semilla 1: Tierra
completa en el 247 en una y 5 de 6 en el 464 en otra, con el mismo jugador). Algo de la
partida no sale de la semilla (las campañas o las ofertas). Con 5 semillas, los
minutos son orientativos; las conclusiones de arriba se repiten en todas.

Repetir (con `override.cfg` propio):

    godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5 --log=1
    godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5 --extras=1 --log=1

## 15. Ronda final de balance de la 1.1 (2026-10-18/19, `integracion/v1.1-aire-mar`)

Decisiones de Bryan tras §13-14 (0/5 ganaban en 8 h con la línea, 3/5 con extras):
duración objetivo **6-8 h** sin recortar campañas; menos bajas en defensa; sueldo más
bajo; la columna sugerida, la que gana; una previsión de fuerza que no engañe.

### Lo que cambió

| Cambio | Dónde | Qué |
|---|---|---|
| Heridos en la defensa | `CombatManager.defense_wounded()`, `combat_defense_return_share` | Defendiendo la base (Diezmo; **no** el Ataque Final), 2 de cada 3 caídos del ejército vuelven heridos (redondeando a su favor; siempre cae uno; mueren antes los de menos `power`). El parte dice "Vuelven heridos". Hook de la Enfermería (1.2) en esa función |
| Sueldo | `army_upkeep_interval` 30 → **90 s** | Un tercio del sueldo (con 60 s quedaban 3-18 deserciones) |
| Columna sugerida | `campaign_suggested_party` 3 → **6** | ¿QUÉ HACER? pide 6 de su medio (lo que quepa en el tope de tropa), salvo que la tropa en casa ya salga "Favorable" (`Objectives.campaign_home_favorable`) |
| Previsión de fuerza | `ExpeditionGenerator.column_strength()` | `power × escala² × cuerpos` (Lanchester) en vez de la suma de `power`: "56 contra 34" con 2 cañones ya sale "Difícil" |
| Reintentos de campaña | `campaign_retry_ease` 0,95, `campaign_retry_floor` 0,80, `CampaignBook.fails` | Cada derrota en la misión que toca le quita un 5 % al enemigo de esa misión (mismo mapa). Sin dados, una misión perdida con una columna se perdía siempre (semilla 4: el Zepelín, 6 derrotas) |
| Preparar otra campaña | `Objectives.campaign_gate_step` | Mientras una campaña espera, primero el edificio que falte a otra; luego reponer |
| Errores en la sonda | `StockIcon3D._set_anim` | Sin Tween vacío ni `play` sobre un bucle ya matado (miles de "Tween invalid" por partida) |

### Medido (`--no-dev --seeds=1,2,3,4,5`, tope 8 h, nómina 90 s)

**Jugador de la línea:**

| Semilla | era 1 | CG nv3 | Tierra | Mar | Aire | asedio | victoria | deserciones | bajas | huecos >3 min sin decidir (mayor) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 17,8 | 252 | 213 | 307 | 366 | 372 GANADO | **394** (6 h 34) | 9 | 47 | 4 (7,4) |
| 2 | 18,8 | 353 | 245 | 422 | 479 | 479 GANADO | **506** (8 h 26) | 1 | 63 | 9 (9,1) |
| 3 | 19,8 | 298 | 306 | 366 | 459 | 468 GANADO | **494** (8 h 14) | 2 | 54 | 7 (10,3) |
| 4 | 17,8 | — | 270 | 0/5 | 0/5 | — | no | 0 | 36 | 19 (12,0) |
| 5 | 17,8 | 237 | 228 | 314 | 363 | 363 GANADO | **389** (6 h 29) | 0 | 54 | 4 (4,2) |

**Jugador completo** (`--extras=1`):

| Semilla | era 1 | CG nv3 | Tierra | Mar | Aire | asedio | victoria | deserciones | bajas | huecos >3 min (mayor) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 20,8 | 236 | 235 | 284 | 319 | 327 GANADO | **353** (5 h 53) | 0 | 49 | 2 (6,0) |
| 2 | 20,8 | 389 | 396 | 459 | 3/5 | — | no | 4 | 45 | 17 (10,4) |
| 3 | 23,8 | 282 | 305 | 343 | 377 | 392 GANADO | **414** (6 h 54) | 7 | 63 | 7 (5,7) |
| 4 | 22,8 | 399 | 273 | 463 | 3/5 | — | no | 1 | 39 | 12 (9,5) |
| 5 | 20,8 | 236 | 243 | 316 | 395 | 395 GANADO | **422** (7 h 02) | 1 | 57 | 5 (7,0) |

La tanda anterior (nómina 60 s, sin reintentos) dio 3/5 con la línea (6 h 54 - 7 h 15)
y **5/5** con extras (6 h 34 - 8 h 06), con 3-9 y 8-18 deserciones.

Lectura:

- **Victoria: 7 de 10 partidas en esta tanda** (15 de 20 contando las dos), casi
  todas en 6-8 h; dos pasan algo de 8 h. Antes de esta ronda, 3 de 10.
- **Deserciones: 0-9** por partida (antes 10-45). El oro ya no se queda en 0 en cada
  Tormenta de la era 3.
- **Lo que no gana es la economía de la era 3, no las campañas:** las que pierden
  llegan al CG nv3 en el minuto 353-399 (o nunca: línea, semilla 4) por esperas de
  vigas, combustible y lingotes para el CG nv3 (110 min en la semilla 2 de la tanda
  anterior). Los huecos >3 min de esas partidas (12-19) caen todos ahí. Ninguna
  campaña se atasca: 0-2 misiones fallidas por partida.
- **Ruido:** la misma semilla no repite partida entre corridas (§14 "Ruido"): la
  semilla 4 de la línea ganó en el 411 con nómina 60 s y no llega al CG nv3 con 90 s.
  Con 5 semillas, las tasas son orientativas.
- Era 1: 17,8-19,8 min (línea), 20,8-23,8 (completo). Sin cambios.

Abierto: el camino de materiales del CG nv3 en la era 3 (Refinería → combustible,
Fundición → vigas, Mina → lingotes) es lo que alarga o rompe las partidas lentas.
Palanca para la próxima ronda: `hq_upgrade_costs` (materiales del nivel 3) o el
rendimiento de los procesos de taller.

## 16. La Casa trae a su gente de golpe (2026-10-19, rama `feat/casa-trae-trabajadores`)

Decisión de Bryan: "siento que tardan en aparecer cuando genero una casa". Antes la
gente llegaba de uno en uno (+1 por tic de crecimiento, 40 s en las fases 1-2) y una
Casa tardaba unos dos minutos en llenarse. Ahora, al **terminar la obra** de una Casa
(o su mejora), entran todos los que caben (`PopulationManager._move_in()`, docs/04),
salvo con la moral bajo 30. El goteo queda para recuperar a los que se pierden.
RETIRAR / PONER TRABAJADORES no cambia.

Medido con `--no-dev --seeds=1,2 --hours=1` (solo la primera hora: es la era 1 lo que
cambia), el mismo commit con y sin el cambio:

| Semilla | era 2 antes | era 2 después | 1.ª Mina de oro antes → después | muertos de hambre antes → después |
|---|---|---|---|---|
| 1 | 17,7 | **16,7** | min 5 → 3 | 0 → 3 |
| 2 | 15,7 | **15,7** | min 5 → 3 | 0 → 0 |

Lectura: la Mina de oro ya no espera a que la Casa se llene (dos minutos antes) y la
era 2 llega igual o un minuto antes; la era 1 no se rompe. Más gente antes come antes:
la semilla 1 tuvo 3 muertos de hambre (antes 0), que el goteo repone. El
resto de la primera hora (era 3 en el 38-42) queda dentro del ruido de §14.

## 15. Amenazas de costa (1.2, rama `feat/amenazas-costa`, sin medir)

Solo botín opcional (docs/15 §14): saqueadores, avanzadilla de la Regencia y pecios en
la orilla, que se van solos sin daño. **No tocan la línea**: `Objectives.next_step()`
no cambia y la sonda de línea no las ataca ni explora (las ignora y se van). Lo único
que pueden mover es el ritmo de quien sí las juega:

| Fuente | Cada cuánto | Botín medio (era 1) | Coste |
|---|---|---|---|
| Saqueadores | ~1 de cada 2 marcas, una marca cada 150-270 s | ~55 oro, ~30 madera, 1,5 repuestos | 1 combate fácil (prof. 0, ×0,9) |
| Pecio | ~1 de cada 3 | ~45 madera, ~25 oro, 1 repuesto | 2 trabajadores 60 s |
| Avanzadilla (era 2+) | ~1 de cada 3 | ~100 oro, ~38 acero (×1,25), 2,5 repuestos | 1 combate como la incursión |

Cuenta rápida: con todo atacado, ~25-40 recursos por minuto en la era 1, frente a los
~60-90 por minuto de una era 1 con aserradero y mina. Riesgo a medir: que adelante
la Fundición (hoy en el minuto 10-13) por debajo de 9 min con quien ataque todo. Las
palancas, por orden: `threat_rewards`, `threat_spawn_interval`, `threat_first_delay`,
`threat_weights` (menos pecios en la era 1), `threat_rare_chance`.

**Qué medir en la ronda final:** enseñar a `tools/line_probe.gd` un jugador
"oportunista" (`--threats=1`: ataca cuando la etiqueta es Favorable y explora todo
pecio con 2 libres) y comparar con 3 semillas: minuto de la Fundición, del CG 3 y
victoria; que los 2 trabajadores del pecio no paren la producción de la era 1.
## 15. Volverse el Imperio: después de ganar (1.2, rama `feat/volverse-imperio`, sin medir)

La línea ya no acaba en la victoria. Ganado el Ataque Final, ¿QUÉ HACER? pasa a la
siguiente conquista del archipiélago (`Objectives.empire_step()`: el edificio del medio
si falta, tropa de ese medio si no hay, o la misión) en vez de "mundo libre"; con las
seis islas tuyas dice "Todo el archipiélago es tuyo". Detalle en
[06-progression-victory.md](06-progression-victory.md) §Volverse el Imperio.

`line_probe` termina en la victoria, así que no cambia. Para medir la fase hace falta
que la sonda siga jugando tras ganar (conquistar en el orden que propone
`next_target()`): anotado como trabajo de la ronda final, con estas preguntas:

- ¿Cuánto dura conquistar las seis islas (16 misiones, ~27 combates más descansos)?
- ¿El tributo (hasta ~400 recursos y unos materiales cada 3 min con todas) llena la
  bolsa y se tira? Si es así, bajar `tribute` o subir `empire_tribute_interval`.
- ¿Hay huecos largos sin nada que hacer entre misiones (descanso de 120 s por isla)?

## 17. Colono en 3-4 h y Gobernador en 6-8 h (2026-10-25/26, rama `feat/ritmo-colono`)

Decisiones de Bryan tras la crítica (contexto 27): Colono en 3-4 h y tres capítulos
(docs/06 §Capítulos), uno de cada tres Impuestos en el tablero (la Visita, docs/15
§5), azar del daño (docs/15 §3) y una sola llave: las piezas de los jefes para el CG
nivel 3 (docs/15 §13). Gobernador se queda en 6-8 h sin perder contenido (las 16
misiones, el taller entero del CG, el asedio de 4-5 oleadas).

`line_probe`, `--no-dev --seeds=1,2,3,4,5`, jugador de la línea (sin `--extras`),
tope 8 h (9 h en Gobernador y en la base). Opción nueva: `--tier=governor`. La tabla
de la sonda gana las columnas **cap I**, **cap II**, **tableros** e **impuestos
tablero/auto**.

### Antes: `origin/main` (4c02f6d), Colono

| Semilla | CG nv3 | Tierra | Mar | Aire | victoria | minutos de tablero |
|---|---|---|---|---|---|---|
| 1 | — | — | — | — | **no (9 h)** | 192 |
| 2 | 274 | 281 | 337 | 387 | **412** (6 h 52) | 205 |
| 3 | 288 | 296 | 362 | 409 | **460** (7 h 40) | 224 |
| 4 | 268 | 240 | 334 | 405 | **448** (7 h 28) | 237 |
| 5 | — | 227 | — | — | **no (9 h)** | 201 |

Todos los Impuestos en el tablero (23-28 por partida).

### Lo que se probó por el camino (Colono, minutos de victoria)

| Tanda | Qué tenía | Victoria |
|---|---|---|
| v1 | todo lo nuevo; Colono Tierra 4 / Mar 3 / Aire 3, material del CG ×0,5; las campañas como paso principal solo con el CG nv3 esperando sus piezas | 241-355 (5/5) |
| v2 | la pieza de Tierra en la línea **antes del CG** (tras las torres) | 2/5 ganan (390, 419): el jefe de Tierra llegaba sin tanques ni economía, 18 derrotas y un Impuesto pagado tras otro |
| v3 | las tres piezas tras el CG, sin tanques antes | 410-476 (4/5): Tierra 9 derrotas, 74 → 266 min |
| v4 | **los 6 tanques del final antes de las campañas**; la sonda elige la columna más fuerte por la previsión | 295-320 (5/5), Tierra sin derrotas |
| v5 | + Astillero y Aeródromo en la línea con el CG en pie; Colono Mar 2 / Aire 2; bolsa del CG ×0,75 | 303-304 (2 semillas) |
| **v6** | + material del CG ×0,3, bolsa ×0,6, asedio de 3-4 oleadas en Colono; la sonda sale a la pieza en cuanto hay calma | ver abajo |

Gobernador en v4: 424-510 (5/5); en v5: 432-489 (5/5).

### Después (v6, la rama tal cual)

**Colono:**

| Semilla | cap I | cap II (Tierra) | Mar | Aire | CG nv3 | victoria | tableros | impuestos tablero/auto | min de tablero |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 17 | 139 | 175 | 198 | 246 | **268** (4 h 28) | 33 | 5/10 | 90 |
| 2 | 18 | 118 | 151 | 179 | 218 | **239** (3 h 59) | 30 | 4/7 | 87 |
| 3 | 15 | 116 | 155 | 178 | 195 | **216** (3 h 36) | 27 | 3/6 | 78 |
| 4 | 17 | 120 | 137 | 162 | 183 | **204** (3 h 24) | 28 | 2/6 | 76 |
| 5 | 19 | 128 | 157 | 177 | 218 | **239** (3 h 59) | 30 | 4/8 | 85 |

**Gobernador:**

| Semilla | cap I | cap II (Tierra) | Mar | Aire | CG nv3 | victoria | tableros | impuestos tablero/auto | min de tablero |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 17 | 138 | 204 | 264 | 370 | **392** (6 h 32) | 52 | 8/15 | 149 |
| 2 | 18 | 148 | 198 | 276 | 377 | **404** (6 h 44) | 53 | 8/12 | 162 |
| 3 | 16 | 134 | 184 | 236 | 348 | **376** (6 h 16) | 54 | 6/9 | 150 |
| 4 | 14 | 144 | 219 | 315 | 451 | **474** (7 h 54) | 57 | 10/16 | 173 |
| 5 | 15 | 142 | 208 | 258 | 350 | **373** (6 h 13) | 46 | 5/15 | 138 |

Lectura:

- **Colono: 5 de 5 ganan, en 3 h 24 - 4 h 28**; cuatro dentro de 3-4 h (la semilla 1,
  la más lenta en todas las tandas, 28 min por encima). Antes: 3 de 5, en 6 h 52 -
  7 h 40. **Gobernador: 5 de 5 en 6 h 13 - 7 h 54** (antes del ritmo nuevo no ganaba
  ninguna con las piezas en la línea, v3).
- **Capítulos (Colono):** I dura 15-19 min (el tutorial y la era 1), II hasta el
  minuto 116-139 (unos 100 min: era 2, Refinería, CG, tanques y la Campaña de
  Tierra), III unos 85-130 min (Mar, Aire, CG 2 y 3, asedio).
- **Tableros:** 27-33 por partida en Colono (antes ~60) y 76-90 minutos de tablero
  (antes 192-237). Impuestos en el tablero: 2-5 de 8-15; los demás, parte automático.
- **Huecos sin decidir de más de 3 min:** 1-5 por partida, el mayor 4-6 min.
- **El asedio** en Colono (3-4 oleadas, `final_audit_waves_delta` −1) se gana a la
  primera en las cinco; con 5 blindados y 4 torres, el 99 % en `siege_probe`. La
  referencia de ~80 % (docs/17) es la de 4-5 oleadas: Gobernador y la tabla base.
- **Ruido:** la misma semilla no repite partida entre corridas (§14 "Ruido"); con 5
  semillas, las cifras son orientativas.
- **Ojo (2026-10-26):** medido sobre `main` sin la rama `fix/tutorial-flujo`, que
  sube los colonos iniciales de 5 a 10 y cambia la línea de la era 1. Con ella, el
  capítulo I (y quizá todo) llegará antes: hay que volver a medir tras integrarla.

Palancas, por orden, si hay que mover Colono: `game_tier_rules.colonist`
(`hq_material_mult`, `hq_resource_mult`, `campaign_missions`,
`final_audit_waves_delta`); el orden de `Objectives.LINE` (tanques, Astillero y
Aeródromo antes de las piezas).

Repetir (con `override.cfg` propio; para correr dos a la vez, cada una con su
carpeta: se cambia el `override.cfg` entre los dos arranques):

    godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5
    godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5 --hours=9 --tier=governor

## 18. La 1.3 integrada: tutorial corto (10 colonos) con el ritmo de Colono (2026-10-26, `integracion/v1.3`)

El aviso de §17 se cumple: `fix/tutorial-flujo` sube los colonos iniciales de 5 a 10
(y el Núcleo da sitio a 10), así que se repite la línea sobre la integración (1.2 +
desbordes + tutorial corto + piel + ritmo + tablet y rendimiento). `line_probe`,
`--no-dev --seeds=1,2,3`, jugador de la línea, carpeta de usuario propia. Minutos de
juego.

**Colono** (objetivo 3-4 h):

| Semilla | era 2 | era 3 | cap I | cap II (Tierra) | Mar | Aire | CG nv3 | victoria | tableros | impuestos tablero/auto |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 12 | 32 | 12 | 113 | 141 | 158 | 203 | **217** (3 h 37) | 29 | 4/6 |
| 2 | 13 | 32 | 13 | 121 | 144 | 179 | 219 | **241** (4 h 01) | 31 | 4/8 |
| 3 | 14 | 38 | 14 | 130 | 148 | 167 | 209 | **232** (3 h 52) | 30 | 4/7 |

**Gobernador** (objetivo 6-8 h, `--tier=governor --hours=9`):

| Semilla | era 2 | era 3 | cap I | cap II (Tierra) | Mar | Aire | CG nv3 | victoria | tableros | impuestos tablero/auto |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 12 | 43 | 12 | 150 | 192 | 268 | 371 | **396** (6 h 36) | 54 | 7/12 |
| 2 | 12 | 34 | 12 | 139 | 200 | 271 | 365 | **384** (6 h 24) | 51 | 7/10 |
| 3 | 13 | 36 | 13 | 137 | 175 | 271 | 385 | **405** (6 h 45) | 53 | 6/14 |

Lectura:

- **Colono: 3 de 3 ganan en 3 h 37 - 4 h 01**, dentro del objetivo (la semilla 2, un
  minuto por encima). Frente a §17 v6 (3 h 24 - 4 h 28), igual o algo más rápido.
- **El capítulo I se cierra antes**: minuto 12-14 (antes 15-19). Con 10 colonos y el
  tutorial corto la Fundición llega en el 12-14; el II se cierra en el 113-130 (antes
  116-139) y el III, con la victoria, ~100 min después.
- **Gobernador: 3 de 3 en 6 h 24 - 6 h 45**, dentro de 6-8 h.
- Los huecos sin decidir de más de 3 min siguen en 3-4 por partida en Colono (el mayor
  4-9 min) y 6-10 en Gobernador (el mayor 5-12 min); la bolsa llena se dispara en
  Gobernador (20-83 min, hasta ~10 000 recursos tirados): a vigilar, no bloquea.
- Ruido: como siempre (§14), la misma semilla no repite partida entre corridas.
