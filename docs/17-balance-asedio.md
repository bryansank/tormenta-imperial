# Balance de la Auditoría Final

La Auditoría Final es el final del juego: de 3 a 5 oleadas defensivas
encadenadas, sin relevos y sin curación entre ellas. Este documento recoge cómo
se midió y por qué los multiplicadores son tan pequeños.

Hermano de [16-balance-combate.md](16-balance-combate.md), que cubre los
encuentros y las expediciones. Sonda: `tools/siege_probe.gd`.

---

## El hallazgo: no se podía ganar

El test de campaña completa (`tests/integration/test_full_campaign.gd`) destapó
que el asedio era invencible. La sonda lo confirmó sobre 200 semillas por
configuración, con moral 100, era 3 y las dos torres en pie:

| Guarnición | Gana | Oleadas limpiadas | Supervivientes |
|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 1,00 de 3,98 | 0,00 |
| 3 vehículos | 0,0 % | 2,00 | 0,00 |
| 4 vehículos | 0,0 % | 2,00 | 0,00 |
| 5 vehículos | 0,0 % | 2,00 | 0,00 |
| 6 infantería | 0,0 % | 2,00 | 0,00 |
| Mixta 3+2+1 | 0,0 % | 2,00 | 0,00 |
| Mixta 2+2+2 | 0,0 % | 2,00 | 0,00 |
| **6 vehículos (máxima)** | **0,0 %** | 2,32 | 0,27 |

Cero victorias en 1.600 asedios. Con la guarnición más fuerte que el juego
permite: el tope de despliegue ocupado por la unidad de más poder, más las dos
dotaciones de torre, y con la inteligencia artificial jugando los dos bandos.

## Por qué

No era el número de oleadas ni su composición. Eran tres cosas sumándose:

1. **El multiplicador toca vida y ataque a la vez.** El poder efectivo sube al
   cuadrado, así que un `+0,22` por oleada no es un 22 % más de dificultad.
2. **No era la única cuesta.** Los cuerpos ya suben solos (3, 4, 5, 6), la
   formación ya mete cañones en la segunda oleada y blindados en la tercera, y
   la guarnición no se cura ni se reentrena. La atrición ya era el balance de
   verdad; la escalada solo decidía cuánto muerde.
3. **La era entraba dos veces.** El `+0,25` por era valía `+0,50` fijo en *toda*
   oleada, porque el Cuartel General es de era 3 y el asedio no se convoca
   antes. La oleada de apertura salía ya multiplicada por 1,5.

## Lo que se cambió

| Clave | Antes | Después |
|---|---|---|
| `final_audit_scale_per_wave` | 0,22 | **0,03** |
| `final_audit_scale_per_era` | 0,25 | **0,05** |
| `final_audit_last_wave_multiplier` | 1,50 | **1,05** |

Nada más. Ni el número de oleadas, ni los cuerpos por oleada, ni la formación,
ni una sola estadística de unidad.

## Después

Mismas 200 semillas por configuración:

| Guarnición | Gana | Oleadas | Supervivientes al ganar | Minutos |
|---|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 2,00 | — | 8,7 |
| 3 vehículos | 6,0 % | 2,73 | 1,00 | 14,3 |
| 4 vehículos | 33,5 % | 3,25 | 2,76 | 16,5 |
| 5 vehículos | 65,0 % | 3,63 | 2,92 | 19,8 |
| 6 infantería | 0,0 % | 2,00 | — | 16,0 |
| Mixta 3+2+1 | 29,0 % | 2,96 | 0,72 | 18,6 |
| Mixta 2+2+2 | 33,5 % | 3,06 | 3,24 | 19,9 |
| **6 vehículos (máxima)** | **82,0 %** | 3,81 de 3,98 | 3,89 de 6 | 21,1 |

Lo que dice esta tabla, que es lo que se buscaba:

- **Duro y ganable.** La guarnición máxima gana cuatro de cada cinco veces y
  llega al final con tres de seis unidades en pie. No es un trámite.
- **La mínima no basta.** Tres infantes no ganan nunca; tres vehículos, una de
  cada dieciséis. Perder el asedio sigue costando.
- **Hay gradiente.** 4 vehículos 33 %, 5 vehículos 65 %, 6 vehículos 82 %. Más
  ejército, más posibilidades, que es lo que hace que valga la pena criarlo.
- **La infantería sola no llega.** Seis infantes pierden siempre. Para el final
  hacen falta blindados, y eso es una afirmación de diseño, no un accidente.

## Gobernador

En el nivel Gobernador de la Campaña (docs/20 §1b) cada oleada lleva además
`audit_enemy_mult` (`GameConfig.game_tier_rules.governor`) sobre su escala.
Objetivo: con la guarnición máxima el asedio sigue siendo ganable **≥ 60 %**.
Medido el 2026-10-04 con 200 semillas, era 3, moral 100, 2 torres:

| Guarnición | Colono (×1,00) | **Gobernador ×1,06** | ×1,10 |
|---|---|---|---|
| 3 infantería (mínima) | 0,0 % | 0,0 % | 0,0 % |
| 3 vehículos | 6,0 % | 0,0 % | 0,0 % |
| 4 vehículos | 33,5 % | 33,5 % | 33,5 % |
| 5 vehículos | 65,0 % | **43,0 %** | 33,5 % |
| 6 infantería | 0,0 % | 0,0 % | 0,0 % |
| Mixta 3+2+1 | 29,0 % | 0,0 % | 0,0 % |
| Mixta 2+2+2 | 33,5 % | 29,0 % | 15,0 % |
| **6 vehículos (máxima)** | 82,0 % | **68,0 %** (2,46 vivos; 3,63 al ganar) | 68,0 % |

Se queda **×1,06**: la máxima gana 68 % (≥ 60 %), cinco vehículos bajan de 65 %
a 43 % (en Gobernador hay que llegar con el ejército entero) y las mixtas
siguen teniendo opciones. Con ×1,10 la máxima no se mueve (el combate es
determinista y salta a escalones), pero las mixtas y los cinco vehículos se
hunden: más castigo sin ganar nada. Duración igual (~21 min con la máxima).

```
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --tier=governor
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --tier=governor --audit_mult=1.10
```

(Con un `override.cfg` propio en la raíz, como toda sonda; bórralo al terminar.)

## Advertencias

- **La medición es un suelo pesimista.** La juega `AutoResolver` con
  `CombatAI` a los dos lados, y esa inteligencia está escrita para atacar, no
  para defender una posición. Una persona juega la defensa mejor.
- **Duración.** El asedio completo con guarnición máxima son unos 21 minutos y
  34 rondas repartidas en cuatro oleadas, es decir 8 o 9 rondas por oleada, que
  es justo la ventana de diseño de un encuentro. Largo para una sola sentada,
  pero es el final de la partida. Si alguna vez se quiere acortar, la palanca
  es el rango de oleadas (`final_audit_waves`), no la escalada.
- **El combate no tira dados.** Como se explica en
  [16-balance-combate.md](16-balance-combate.md), el daño es determinista: las
  tasas de victoria de esta tabla salen de que cambia la semilla del asedio
  (longitud y formación), no de que el mismo asedio se juegue distinto.

## Cómo volver a medirlo

```
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200
godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --spw=0.12 --last=1.25
```

Los argumentos `--spw`, `--spe` y `--last` pisan los tres multiplicadores sin
tocar `GameConfig`, que es como se hicieron las dos tablas de arriba. `--detail=1`
desglosa por longitud de asedio.

Los dos casos de guardia viven en `tests/integration/test_full_campaign.gd`:
`test_the_siege_is_hard_but_winnable_with_a_full_garrison` y
`test_the_smallest_garrison_that_can_resummon_does_not_win`.

## 2026-10-12: un final que pide preparación

Decisión de Bryan: la Auditoría pide más ejército y más preparación. Valores:
`final_audit_waves` 3-5 → **4-5**, `final_audit_last_wave_multiplier` 1,05 →
**1,10**, `storm_tower_garrison_max` 2 → **4** (con la guarnición mermada caben
más dotaciones: el tablero deja 8 − vivos), Gobernador ×1,06 → **×1,05**. 200
semillas, era 3, moral 100:

| Guarnición | 4 torres | 2 torres | 4 torres, moral 75 | Gobernador ×1,05 (4 torres) |
|---|---|---|---|---|
| 3 infantería | 0 % | 0 % | — | — |
| 4 vehículos | 33,5 % | 0 % | 0 % | 10,5 % |
| 5 vehículos | 45 % | 34 % | 26,5 % | 45 % |
| mixtas | 0 % | 0 % | 0 % | 0 % |
| **6 vehículos** | **82,5 %** | **45 %** | **43 %** | **64 %** |

La guarnición máxima bien preparada gana como antes (82 %); sin las torres o con
la moral a medias, una de cada dos. Con moral 50, nunca. Gobernador ≥ 60 %.
`tools/siege_probe.gd` acepta `--crews=N`.

---

## Ventaja por tipo (2026-10-13, rama `feat/combate-3d`)

La regla nueva del combate (docs/15 §3 "Segunda tanda"): artilleria > vehiculo >
infanteria > artilleria, x1,5 con ventaja y x0,75 con desventaja sobre el dano
neto (`GameConfig.combat_type_advantage`). Medido con `tools/siege_probe.gd`
(era 3, moral 100, 2 torres, nivel Colono), con los `final_audit_*` de esta rama
(oleada 0.03, era 0.05, ultima x1.05, 3+1 cuerpos, un canon cada 3, blindado
desde la oleada 2). `-- --adv=off` mide el antes; `-- --adv=A,D` pisa los
multiplicadores.

| Guarnicion | Antes (sin ventaja, 200 sem.) | Despues x1,5/x0,75 (200 sem.) |
|---|---|---|
| min 3 infanteria | 0 % | 0 % |
| min 3 vehiculos | 6,0 % | 6,0 % |
| 4 vehiculos | 33,5 % | 33,5 % |
| 5 vehiculos | 65,0 % | 48,5 % |
| 6 infanteria | 0 % | 0 % |
| mixta 3+2+1 | 29,0 % | 25,5 % |
| mixta 2+2+2 | 33,5 % | 33,5 % |
| **MAX 6 vehiculos** | **82,0 %** | **68,0 %** |

Por que baja: las oleadas llevan un canon por cada 3 cuerpos, y el canon pega al
blindado con ventaja; la guarnicion maxima es toda blindados. Variantes (100
semillas, MAX 6 vehiculos / mixta 2+2+2):

| Multiplicadores | Canones de la Regencia | MAX 6 vehiculos | mixta 2+2+2 |
|---|---|---|---|
| 1,25 / 0,8 | 1 de cada 3 | 71 % | 34 % |
| 1,35 / 0,85 | 1 de cada 3 | 76 % | 34 % |
| 1,5 / 0,9 | 1 de cada 3 | 71 % | 34 % |
| 1,25 / 0,9 | 1 de cada 3 | 76 % | 34 % |
| **1,5 / 0,75** | **1 de cada 4** (`--gun=4`) | **83 %** | 34 % |
| 1,5 / 0,75 | 1 de cada 5 (`--gun=5`) | 83 % | 34 % |
| 1,35 / 0,85 | 1 de cada 4 | 88 % | 34 % |

**Propuesta (sin aplicar, la decide la rama de balance):** mantener x1,5 / x0,75
y subir `final_audit_artillery_share` de 3 a 4. Devuelve la guarnicion maxima al
~82 % de antes (83 %) sin tocar la escala de las oleadas, y deja intacta la
mixta. 5 no da mas. Hay que medirlo junto a lo que endurezca el final la rama
`balance/campana-4-6h`: los dos cambios tocan el mismo asedio.

## Las dos cosas juntas (2026-10-14): 4-5 oleadas, 4 dotaciones y ventaja por tipo

Con la ventaja por tipo fusionada y los valores del 2026-10-12 (4-5 oleadas,
última ×1,10, hasta 4 dotaciones), 200 semillas, era 3:

| Guarnición | canón 1/3, 4 torres | 1/3, 2 torres | 1/3, moral 75 | 1/3, Gobernador | canón 1/4, 4 torres | 1/4, 2 torres | 1/4, moral 75 | 1/4, Gobernador |
|---|---|---|---|---|---|---|---|---|
| 3 vehículos | 0 % | 0 % | 0 % | 0 % | 13,5 % | 0 % | 0 % | 0 % |
| 4 vehículos | 33,5 % | 0 % | 0 % | 19 % | 45 % | 0 % | 19 % | 32 % |
| 5 vehículos | 69 % | 6,5 % | 19 % | 41 % | 86 % | 28,5 % | 38,5 % | 62,5 % |
| mixtas | 0 % | 0 % | 0 % | 0 % | 0 % | 0 % | 0 % | 0 % |
| **6 vehículos** | **86 %** | **45 %** | **40,5 %** | **75,5 %** | **97,5 %** | **71,5 %** | **71,5 %** | **92 %** |

**Decisión: `final_audit_artillery_share` se queda en 3.** La propuesta de 4
compensaba la ventaja por tipo sobre el asedio de 3-5 oleadas; sobre el de 4-5
oleadas el final se volvería un trámite (97,5 % con 6 blindados, 86 % con 5,
71,5 % sin las torres). Con 3, la guarnición máxima bien preparada gana el 86 %
(como el 82 % de siempre), sin las torres o con la moral a 75 una de cada dos o
menos, y Gobernador el 75,5 % (≥ 60 %).

## Aire y mar (2026-10-17, rama `feat/aire-mar-reglas`) — medido el mismo día: APAGADO

Decisión de Bryan: la Regencia trae **dirigibles a la última oleada**. Lo que
cambia en `FinalAudit._compose()` (solo la última oleada; las anteriores salen
igual, con la misma moneda al aire):

- Desde la era `final_audit_air_min_era` (3), `final_audit_airships_last_wave`
  (1) dirigible **en el hueco de un cañón** (si no hay cañón, en el de un
  infante; la línea nunca se queda vacía). No añade cuerpos: el tope de 6 sigue.
- Si en la guarnición hay **aviones** cuando se convoca (o cuando se abre la
  puerta, si aún no había empezado), `final_audit_air_escort_fighters` (1) **caza
  de escolta** en el hueco de un infante. Se guarda (`air_escort` en el
  `to_dict()`; un guardado viejo no lo trae = sin escolta).

Por qué en el hueco del cañón: el dirigible (260 de vida, ataque 10, defensa 4,
alcance 2) pega menos de golpe que el cañón de la última oleada pero cuesta mucho
más tumbarlo, y **solo se le puede pegar a 1 casilla** (infantería y tanques) o con
aviones: la artillería y las dotaciones de torre no le llegan (no hay artillería
antiaérea, el caza es el antiaéreo). Cambiar un cañón por un dirigible quita
golpe y pone aguante: la intención es que el total quede parecido, pero **no está
medido**.

En casa el tablero del asedio solo tiene agua si en la guarnición hay barcos
(`CombatManager.home_terrain()`), así que la guarnición de referencia (6
blindados) sigue peleando en tierra: lo único que le cambia es el dirigible.

**Pendiente (ronda final) — hecho, ver "Medido" abajo:** repetir la tabla de arriba con
`godot --headless --path . -s tools/siege_probe.gd -- --seeds=200` (con su
`override.cfg`) y mirar sobre todo la columna de 6 blindados con 4 torres (era
86 %) y Gobernador (75,5 %). Si baja más de 5 puntos, las palancas son, por
orden: `final_audit_airships_last_wave` a 0 en Colono, o el dirigible enemigo con
menos vida (otra fila en `combat_unit_stats` solo para la Regencia). La sonda
tampoco sabe aún componer guarniciones con barcos o aviones: añadir filas
"4 blindados + 2 cazas" y "4 blindados + 2 cañoneras" cuando se mida.

### Medido (ronda de la 1.1, `integracion/v1.1-aire-mar`)

`tools/siege_probe.gd` ya compone guarniciones con aviones y barcos (filas
"6 veh + 2 cazas", "4 veh + 2 cazas", "4 veh + 2 canoneras"; con barcos el
tablero de casa tiene agua, como `CombatManager.home_terrain()`) y pisa los
valores nuevos: `--airships=N`, `--escort=N`, `--airship_hp=N`, `--land_air=N`.
200 semillas, era 3, moral 100, 4 torres:

| Guarnición | Con dirigible y escolta (lo de la rama) | Sin dirigible ni escolta (lo que queda) | Gobernador, sin |
|---|---|---|---|
| 4 vehículos | 0 % | 33,5 % | 19 % |
| 5 vehículos | 0 % | 69 % | 41 % |
| **6 vehículos (referencia)** | **13,5 %** | **86 %** | **75,5 %** |
| 6 veh + 2 cazas | 17 % | 82,5 % (45 % con escolta y sin dirigible) | 46 %* |
| 4 veh + 2 cazas | 0 % | 45 % | — |
| 4 veh + 2 cañoneras (agua en casa) | — | 59 % | 29,5 % |

\* Gobernador medido aún con la escolta encendida.

Lo que se probó para salvar el dirigible (60 semillas, 6 vehículos):

| Variante | Gana |
|---|---|
| Sin dirigible (`--airships=0`) | 90 % |
| Dirigible de serie (260 de vida, ×1,34 en la última oleada = 349) | 13,5 % |
| Vida 180 / 140 / 100 | 48 % / 63 % / 77 % |
| Tierra y mar le pegan a 2 casillas (`--land_air=2`) | 75 % |
| Dirigible de serie, guarnición con 2 cazas | 25 % |

**Por qué se hunde** (lo enseña una traza de la última oleada): no es solo la
vida. `CombatAI._target_quality` elige, a igual "lo mato o no" y a igual ventaja,
el rival de más `power`: el dirigible (55) va antes que el cañón (28). Los
blindados se pasan la oleada arañándole 7 puntos por golpe (solo a 1 casilla)
mientras los cañones, que les ganan por tipo, los rompen; o se agota el reloj de
20 rondas con el dirigible vivo. Con vida 100 sigue 13 puntos por debajo, y con
dos cazas propios (el antiaéreo) en el 25 %.

**Decisión (valores, documentada):** `final_audit_airships_last_wave` = **0**.
El código del dirigible se queda (volver es una línea), pero no se enciende hasta
que la IA pese el daño que hace de verdad antes que el `power` del objetivo, o
la Regencia tenga su propio dirigible más frágil. Y `final_audit_air_escort_fighters`
= **0**: sin dirigible que escoltar, la escolta solo castigaba tener Aerodromo
(6 vehículos + 2 cazas: 45 % con escolta frente al 86 % sin aviones). Sin ella, los
cazas en casa no restan (82,5 %, dentro del ruido de 86 %) y con 4 vehículos suman
(45 % frente a 33,5 %). Los barcos en casa suman también: 4 vehículos + 2 cañoneras
ganan el 59 % (frente al 33,5 % de 4 vehículos).

Los tests (`tests/combat/test_air_sea_missions.gd`) fuerzan 1 para seguir fijando
cómo entran el dirigible y la escolta, y uno nuevo fija que de serie no entran.

Repetir:

    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --airships=1 --escort=1
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --tier=governor


## La IA nueva (1.1, `integracion/v1.1-aire-mar`): dirigible y escolta ENCENDIDOS

Decisión de Bryan: arreglar la IA y volver a encender el dirigible de la última
oleada (`final_audit_airships_last_wave` = **1**) y la escolta de cazas si tienes
aviones (`final_audit_air_escort_fighters` = **1**). La IA ya no elige por `power`
sino por el valor del golpe (`CombatAI.shot_worth`: parte de la vida que se lleva
× amenaza del objetivo; docs/15 §8 "La IA"): los blindados rompen los cañones y no
persiguen al dirigible.

**Sondeo corto** (antes de la ronda final, `tools/siege_probe.gd`, era 3, moral
100, 4 torres; `--threat_w=N` pisa el peso):

| Guarnición | IA vieja (200 sem.) | IA nueva, sin dirigible | IA nueva, con dirigible y escolta |
|---|---|---|---|
| 4 vehículos | 33,5 % | 52 % (100 sem.) | — |
| 5 vehículos | 69 % | 78 % (100 sem.) | — |
| mixta 2+2+2 | 0 % | 31 % (100 sem.) | — |
| **6 vehículos (referencia)** | **86 %** | **100 %** (100 sem.) | **87,5 %** (40 sem.; antes 13,5 %) |

Con peso 0 (solo daño relativo) salía casi igual: 100 % / 80 %. El "tiro pobre"
(docs/15 §8) se probó y se quitó: bajaba el asedio 15-30 puntos.

Lectura provisional: la IA nueva hace a la guarnición de blindados bastante más
fuerte en tierra (dejaba de pegarle a la infantería mientras los cañones la
rompían), y el dirigible devuelve la referencia a la franja pedida. Como el
asedio real es siempre de era 3, **el dirigible va siempre**: la cifra que
cuenta es la de la columna derecha.

**Ronda final — qué medir y con qué objetivo** (200 semillas, `override.cfg`
propio):

    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --airships=0 --escort=0
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=2
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --morale=75
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --tier=governor

- **6 vehículos, 4 torres, con dirigible y escolta (la serie): 75-85 %.** Si
  sale por encima, `final_audit_last_wave_multiplier` 1,10 → 1,15 (no las
  estadísticas de tierra); si sale por debajo, el peso de la IA o la vida del
  dirigible de la Regencia.
- 6 veh + 2 cazas no debe quedar por debajo de 6 vehículos solos (la escolta no
  puede castigar tener Aeródromo; si lo hace, escolta a 0).
- Sin torres (2) o con moral 75: claramente por debajo (antes ~45 %);
  Gobernador ≥ 60 %.
- Tierra pura (`--airships=0 --escort=0`): documentar la subida frente a la IA
  vieja; si se dispara más allá del ~100 % en 5 vehículos, revisar
  `combat_ai_threat_weight`.
- Los casos de guardia de `tests/integration/test_full_campaign.gd`
  (`test_the_siege_is_hard_but_winnable_with_a_full_garrison`,
  `test_the_smallest_garrison_that_can_resummon_does_not_win`) se revisan con la
  suite: la IA nueva puede moverlos.

## Ronda final de la 1.1 (2026-10-18): medido y ajustado

`tools/siege_probe.gd`, 200 semillas por fila, era 3, `override.cfg` propio. IA
nueva (`combat_ai_threat_weight` 1,0), dirigible en la última oleada.

### La referencia y la palanca

6 blindados, 4 torres, moral 100, Colono. `final_audit_last_wave_multiplier`
(con escolta de cazas salvo donde se dice):

| Última oleada | 6 vehículos | 6 veh + 2 cazas | 6 veh + 2 cazas sin escolta |
|---|---|---|---|
| ×1,10 (la rama) | 90,0 % | 79,5 % | — |
| ×1,12 | 88,0 % | 79,5 % | — |
| ×1,13 | 90,0 % | 49,5 % | — |
| **×1,14** | **82,5 %** | 49,5 % | **65,0 %** |
| ×1,15 | 57,5 % | 56,5 % | 46,5 % |

El combate no tira dados: entre ×1,10 y ×1,13 apenas se mueve y de ×1,14 a ×1,15
se desploma. **Decisión:** `final_audit_last_wave_multiplier` 1,10 → **1,14**
(82,5 %, dentro de 75-85 %) y `final_audit_air_escort_fighters` 1 → **0**: con
escolta, tener 2 cazas en casa bajaba del 82,5 % al 49,5 % (la escolta castigaba
tener Aeródromo). Sin ella, 65 %: los cazas siguen restando algo (ocupan sitio de
despliegue y no paran a los cañones), pero ya no por la escolta.

### Con los valores nuevos (×1,14, sin escolta)

| Guarnición | 4 torres, moral 100 | 2 torres | moral 75 | moral 90 | Gobernador ×1,05 | Gobernador ×1,005 | sin dirigible |
|---|---|---|---|---|---|---|---|
| 5 vehículos | 40,0 % | 0 % | 0 % | — | 6,5 % | 40,0 % | 61,0 % |
| mixta 2+2+2 | 0 % | 0 % | 0 % | — | 0 % | — | 24,0 % |
| **6 vehículos** | **82,5 %** | 25,5 % | **0 %** | 30,5 % | 23,0 % | **67,5 %** | 100 % |
| 6 veh + 2 cazas | 65,0 % | 24,0 % | 0 % | — | 20,0 % | 58,5 % | 92,0 % |

- **Dos torres:** 25,5 %, claramente por debajo (antes ~45 %).
- **Moral 75: 0 %** (también con ×1,10), moral 90: 30,5 %, con el rango de moral
  general. Resuelto abajo, "La moral en el asedio".
- **Gobernador:** con `audit_enemy_mult` 1,05 la máxima ganaba el 23 % (×1,02
  45 %, ×1,01 57,5 %). **Decisión:** **1,005** → 67,5 % (≥ 60 %). El Gobernador
  sigue siendo más duro en expediciones (×1,05), campañas y Diezmo (×1,34); en
  el asedio, casi nada.
- **Sin dirigible** (`--airships=0`): 100 % la máxima, 61 % cinco blindados. El
  dirigible es lo que deja la referencia en la franja.

### Peso de la IA (`combat_ai_threat_weight`, ×1,14 sin escolta)

| Peso | 6 vehículos | 6 veh + 2 cazas | 5 vehículos | mixta 2+2+2 |
|---|---|---|---|---|
| 0 (solo la parte de la vida) | 60,0 % | 56,5 % | 40,0 % | 0 % |
| **1 (la serie)** | **82,5 %** | 65,0 % | 40,0 % | 0 % |
| 2 | 68,0 % | 44,0 % | 25,5 % | 0 % |

Se queda en 1.

Repetir:

    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --tier=governor
    godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --morale=75

### La moral en el asedio (decisión de Bryan, 2026-10-18)

Con el rango general (`combat_morale_attack_range` 0,60-1,40 y ±2 de iniciativa)
el asedio dependía solo de la moral: 82,5 % a moral 100, 30,5 % a 90, 0 % a 75.
Bryan: suavizarlo para que la referencia gane ~50 % con moral 75 y ~80 % con 100.

La guarnición de casa del Ataque Final **y** las dotaciones de las torres pelean
ahora con su propio rango (`CombatRules.siege_morale_attack_mod` /
`siege_morale_initiative_bonus`; `FinalAudit` y `CombatManager` al montar cada
oleada): `final_audit_morale_attack_range` = **(1,20, 1,40)** y
`final_audit_morale_initiative_range` = **(0, +2)**. A moral 100 todo vale lo
mismo que antes; a moral 75, ×1,35 de ataque y +2 de iniciativa (antes ×1,20 y
+1). Las expediciones, campañas y el Diezmo siguen con el rango general.

Lo que se probó a moral 75 (6 vehículos, 4 torres, 200 semillas):

| Ataque (moral 0-100) | Iniciativa | Moral 75 |
|---|---|---|
| 0,60-1,40 (el general) | -2..+2 | 0 % |
| 1,00 / 1,10 / 1,20 / 1,30 - 1,40 | -2..+2 | 12 / 27 / 27 / 27 % |
| 0,60-1,40 | 0..+2 | 0 % |
| 1,00-1,40 | 0..+2 | 30,5 % |
| **1,20-1,40** | **0..+2** | **48,5 %** |

Solo con el ataque no basta: a moral 75 la iniciativa +1 la deja en 27 %.

Con los valores nuevos (×1,14, dirigible, sin escolta, 200 semillas):

| Guarnición | moral 100 | moral 90 | moral 75 | Gobernador, 100 | Gobernador, 75 | 2 torres, 100 |
|---|---|---|---|---|---|---|
| 5 vehículos | 40,0 % | 40,0 % | 28,5 % | 40,0 % | 34,0 % | 0 % |
| **6 vehículos** | **82,5 %** | **75,0 %** | **48,5 %** | **67,5 %** | 22,5 % | 25,5 % |
| 6 veh + 2 cazas | 65,0 % | 56,0 % | 25,5 % | 58,5 % | 38,5 % | 24,0 % |

Repetir: `godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 --morale=75`
(`--siege_atk=lo,hi` y `--siege_init=lo,hi` pisan los dos rangos).

## Azar del daño (2026-10-25, rama `feat/ritmo-colono`)

Con el daño ±12 % (`combat_damage_spread`, docs/15 §3 "El daño y su azar") el asedio
de 4-5 oleadas **acumula la mala suerte** de oleada en oleada: con la última oleada a
×1,14 la referencia (6 blindados, 4 torres, moral 100, Colono) bajó del 82,5 % al
**58,5 %**. Cada oleada siembra su `Encounter` con la semilla del asedio y su número
(`siege_probe`, igual que `CombatManager.fight_seed()` en partida).

`tools/siege_probe.gd`, 200 semillas, 4 torres:

| `final_audit_last_wave_multiplier` | 6 vehículos (referencia) |
|---|---|
| ×1,14 sin azar (lo de antes) | 82,5 % |
| ×1,14 con azar | 58,5 % |
| ×1,10 | 69,5 % |
| **×1,06** | **79,5 %** |
| ×1,02 | 86,5 % |

Ya no es un escalón (antes ×1,14 → ×1,15 caía del 82,5 % al 57,5 %): ahora cada 0,04
mueve unos diez puntos. **Decisión: ×1,14 → ×1,06** (referencia ~80 %).

Con ×1,06 y azar (200 semillas):

| Guarnición | 4 torres, moral 100 | moral 75 | 2 torres | Gobernador |
|---|---|---|---|---|
| 5 vehículos | 50,0 % (antes 40,0 %) | — | — | — |
| **6 vehículos** | **79,5 %** | 61,0 % (antes 48,5 %) | 40,0 % (antes 25,5 %) | **71,5 %** (antes 67,5 %) |
| 6 veh + 2 cazas | 84,0 % (antes 65,0 %) | — | — | — |

Las guarniciones flojas y las de dos torres suben algo (la suerte también ayuda al
que va justo), y la de referencia queda en la franja.

Repetir: `godot --headless --path . -s tools/siege_probe.gd -- --seeds=200 --towers=4 [--spread=0] [--last=F] [--tier=governor] [--morale=75]`.
