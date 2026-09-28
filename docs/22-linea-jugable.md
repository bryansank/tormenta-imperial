# La línea jugable: de la primera obra a la victoria

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
| A1 | **Islas sin pozo de petróleo, o sin bosque.** El sorteo elegía el tipo de cada yacimiento al azar sin mirar los demás: sin pozo no hay Refinería, ni era 3, ni final; sin bosque no hay apertura. Con 18-28 sorteos uniformes, ~0,8% de los mapas salían sin algún tipo y ~1,3% con un solo pozo (la Refinería se lo come) | `MapGenerator.generate_new_map()` | `_guarantee_minimums()` completa hasta `deposit_min_per_type` (2 bosques, 2 vetas, 1 hierro, 2 pozos) y exige sitio para el extractor. Solo añade: los mapas que ya estaban bien no cambian | `tests/map/test_map_minimums.gd` |
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
mantiene ocupados los procesos del Núcleo, el aserradero y la mina.

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
- **La era 1 no tiene Tormenta.** Es lo que dice el diseño (Acto I), pero son 8-10 min
  sin otra presión que el consumo. Si se quiere una "tormenta de prueba" guionizada en la
  era 1, es una decisión de diseño abierta (ver [13-roadmap.md](13-roadmap.md), decisiones abiertas).
- **El minado a mano es la palanca más fuerte de la era 1** (§5.4): con él la era 2
  llega en el minuto 3. Si se quiere que la era 1 dure, la palanca es
  `mining_data` (rendimiento o duración), no la línea.
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
- [ ] Antes de la Fundición no hay tormentas; la primera llega ~10 min después.
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
