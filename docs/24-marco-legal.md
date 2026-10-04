# 24 — Marco legal y normas de contenido

Qué leyes venezolanas tocan a Tormenta Imperial, qué dicen y qué reglas de contenido
salen de ellas. Sirve para revisar textos, arte, descripciones de tienda y publicidad
antes de cada versión, y para decidir qué falta antes de vender.

> Esto es investigación propia, no asesoría legal. Antes de vender el juego o abrir la
> nube a jugadores, conviene consultar a un abogado venezolano (ver §8).
> Última revisión: 2026-10-04.

---

## 1. Resumen

| Tema | Riesgo hoy | Qué hacer |
|---|---|---|
| Ley de Videojuegos Bélicos | **Medio**: la definición es amplia y te alcanza como desarrollador | Seguir las normas de contenido de §3 y la de comunicación de §4 |
| Propiedad intelectual propia | Bajo: la protección existe desde que creaste la obra | Registrar la obra y el nombre en el SAPI antes de publicar (§5) |
| Licencias de terceros | Bajo: todo está documentado en `THIRD-PARTY-NOTICES.md` | Mantener `assets/CREDITS.md` al día con cada asset nuevo |
| Datos personales | Ninguno hoy (el guardado es local) | Cumplir §6 antes de conectar `CloudSaveManager` |
| Venta, impuestos y tiendas | No aplica todavía | Resolver §7 antes de cobrar |

---

## 2. La Ley de Videojuegos Bélicos

**Ley para la Prohibición de Videojuegos Bélicos y Juguetes Bélicos.** Gaceta Oficial
N° 39.320, 03/12/2009. Vigente desde el 03/03/2010 y no derogada. Tiene 14 artículos.

### Los artículos que importan

**Art. 1 — Objeto.** Prohíbe "la fabricación, importación, distribución, compra,
venta, alquiler y uso de videojuegos bélicos".

**Art. 2 — Ámbito.** Aplica a toda persona natural o jurídica en el territorio
nacional. No distingue edades: rige igual para adultos y para niños.

**Art. 3.1 — Definición (texto literal):**

> "Videojuegos, bélicos: aquellos videojuegos o programas usables en computadoras
> personales, sistemas arcade, videocónsolas, dispositivos portátiles o teléfonos
> móviles y cualquier otro dispositivo electrónico o telemático, que contengan
> informaciones o simbolicen imágenes que **promuevan o inciten a la violencia o al uso
> de armas**."

**Art. 4.4 — Principio.** "Todo videojuego y juguete debe promover el respeto a la
vida, la creatividad, el sano entretenimiento, el compañerismo, la lealtad, el trabajo
en equipo, el respeto a la ley, la comprensión, la tolerancia, el entendimiento entre
las personas y el espíritu de paz y la fraternidad."

**Art. 6 — Publicidad.** "Se prohíbe todo tipo de publicidad o forma de difusión que,
de cualquier manera, incite la adquisición o uso de videojuegos bélicos".

**Art. 13 — Multa.** Promover por cualquier medio la compra o el uso de un videojuego
bélico: 2.000 a 4.000 unidades tributarias.

**Art. 14 — Prisión.** "Quien importe, **fabrique**, venda, alquile o **distribuya**
videojuegos bélicos […] será sancionado con prisión de 3 a 5 años", con comiso y
destrucción.

### Cómo se lee para este juego

- **Tener armas o combate no basta.** La definición exige que el juego "promueva o
  incite" a la violencia o al uso de armas. Esa es la frontera que hay que cuidar.
- **"Promover o incitar" no está definido.** La ley no tiene reglamento ni
  jurisprudencia conocida que lo aclare. Depende de cómo lo lea un fiscal o un juez.
- **Te alcanza como desarrollador.** El art. 14 castiga "fabricar" y "distribuir".
  Desarrollar en Venezuela y publicar el repositorio o un APK cumple esos verbos. Excluir
  a Venezuela de una tienda reduce la venta y la distribución en el país, pero no la
  fabricación.
- **La aplicación real es casi nula.** Juegos de guerra mucho más explícitos se venden
  en Venezuela por Steam, consolas y Google Play, y no se conocen procesos contra
  desarrolladores. Eso no es una garantía: la ley está vigente.
- **La defensa del juego es el art. 4.4.** Tormenta Imperial va de construir,
  administrar, cuidar a la población y resistir a un poder que cobra tributo. El combate
  sirve a esa historia. Cada decisión de contenido debe mantenerlo así.

---

## 3. Normas de contenido

Se aplican a textos (`scripts/services/Tr.gd`, ES y EN), arte, iconos, sonido,
mecánicas y lore.

### Verde: lo que el juego ya hace y debe seguir haciendo

- El combate es **abstracto**: siluetas en un tablero de 8x8, por turnos, sin cuerpos.
- **Sin sangre, sin gore, sin sufrimiento mostrado.** Las bajas son números.
- Las unidades son genéricas (infantería, artillería, vehículo). **No hay armas reales
  reconocibles** ni marcas de armamento.
- El conflicto central es **defensivo**: la Tormenta y los Tasadores vienen a cobrar; el
  jugador protege lo que construyó. El Diezmo puede pagarse en vez de pelearse.
- La victoria de Campaña es **detener la Tormenta**, no exterminar a nadie, y el modo
  Constructor gana sin combatir.
- El enemigo es una institución ficticia (la Regencia), **no un pueblo, una etnia, una
  religión ni un país real**.

### Amarillo: revisar antes de añadir o cambiar

- **Expediciones con botín.** Es la parte más ofensiva del juego: salir a pelear para
  ganar recursos. Conviene que el lore las presente como recuperar suministros, romper
  el bloqueo o liberar depósitos, no como saqueo.
- **Verbos de exterminio en la interfaz.** Hoy hay dos:
  - `OBJ_ELIMINATE_ALL`: "Elimina a todas las unidades enemigas". Alternativa: "Pon en
    retirada a todas las unidades enemigas" o "Gana el control del tablero".
  - `MSG_EXPEDITION_LOST`: "Expedición aniquilada". Alternativa: "La expedición no
    volvió" o "Expedición perdida".
- **Recompensas por bajas.** Hoy no las hay: el botín viene del nodo, no de cuántas
  unidades caen. Mantenerlo así.
- **Sonidos de combate.** Cuando haya audio de combate propio (hoy son alias), evitar
  gritos o sonidos de dolor.
- **Ejército con nombres o uniformes reales.** No usar insignias, banderas ni rangos de
  fuerzas armadas existentes.

### Rojo: no entra en el juego

- Sangre, desmembramiento, cadáveres, tortura o ejecuciones.
- Atacar a civiles o recompensar daño a la población.
- Armas reales identificables (modelos, marcas) o instrucciones de uso de armas.
- Matar como objetivo o puntuación ("racha de bajas", contadores de muertes).
- Enemigos que representen a grupos reales (pueblos, religiones, partidos, países,
  instituciones del Estado venezolano).
- Glorificar la guerra como algo deseable.

---

## 4. Normas de comunicación (tienda, readme, redes, tráiler)

El art. 6 y el art. 13 castigan la **publicidad**, no solo el juego. Lo que se dice del
juego pesa tanto como lo que tiene dentro.

- **Presentarlo como juego de gestión y estrategia.** Por ejemplo: "Construye tu
  colonia, sostén su economía y resiste la Tormenta Imperial".
- **El combate se menciona como una parte**, no como el gancho: "defiende lo que
  construiste", "resiste el cobro", "sobrevive al asedio".
- **Frases a evitar:** "aplasta a tus enemigos", "domina la guerra", "destrucción
  total", "arrasa", "conquista", "sin piedad", "armas devastadoras".
- **Capturas y tráiler:** que predomine la colonia, la economía y la Tormenta. Las
  escenas de tablero, como una parte del juego.
- **Clasificación por edad (IARC en Google Play):** responder con honestidad. La
  violencia del juego es leve y fantástica; declararla bien también sirve de prueba de
  buena fe.

Estado actual del `readme.md`: correcto. Habla de colonia, economía y Tormenta, y el
combate aparece como defensa ("ese cobro se pelea en un tablero"). La expresión "Partes
de guerra" es descriptiva y puede quedarse, aunque "Partes de defensa" sería más
coherente con §3.

---

## 5. Propiedad intelectual

### Lo propio

- **Derecho de autor** (Ley sobre el Derecho de Autor, G.O. N° 4.638 Ext., 01/10/1993):
  el código, el arte, el texto y el lore están protegidos desde su creación, sin
  registro. El art. 2 incluye expresamente los programas de computación y su
  documentación.
- **Registro voluntario en el SAPI** (Registro de la Producción Intelectual): no da el
  derecho, pero fija una fecha que sirve de prueba ante una copia. **Hacerlo antes de
  publicar.**
- **El nombre "Tormenta Imperial" no lo protege el derecho de autor**, sino la marca.
  Registrarlo en el SAPI (Ley de Propiedad Industrial, G.O. N° 25.227, 1956) en las
  clases de Niza 9 (software) y 41 (entretenimiento). Antes, buscar si ya existe. Si se
  vende fuera, revisar también en la USPTO (EE. UU.) y la EUIPO (Unión Europea).
- **La licencia del repositorio** (`LICENSE`: PolyForm Strict para el código; arte,
  texto y nombre con todos los derechos reservados) es válida. Ante una copia o venta no
  autorizada aplican la Ley sobre el Derecho de Autor y el art. 25 de la Ley Especial
  contra los Delitos Informáticos (apropiación de propiedad intelectual, 1 a 5 años).

### Lo generado con IA

Hay modelos 3D hechos con el MCP de Blender, iconos generados por script y código escrito
con asistentes de IA. La ley venezolana protege la obra de una **persona**: lo que el
autor dirige, elige y edita cuenta como suyo; lo generado de forma totalmente automática
es una zona gris, aquí y en el resto del mundo. El proyecto de Ley de Inteligencia
Artificial (aprobado solo en primera discusión) toca ese vacío.

Norma: **el historial de git es la prueba del trabajo creativo.** Commits con mensajes
claros, sin reescribir la historia de `main`.

### Lo de terceros

Ya está bien resuelto en `THIRD-PARTY-NOTICES.md` y `assets/CREDITS.md`:

- Godot 4.7: MIT, con su aviso y `licenses/GODOT-COPYRIGHT.txt` en cada zip.
- Fuentes (Black Ops One, Caveat, Rajdhani, Special Elite): OFL. Pueden ir en un juego
  que se vende, pero no venderse por separado.
- Música y efectos: CC0 (Kenney, OpenGameArt y otros).
- Textura de metal: Poly Haven, CC0.

Norma: **ningún asset entra sin su licencia verificada en `assets/CREDITS.md`.** Solo
CC0, CC-BY (con crédito), OFL o licencias equivalentes que permitan uso comercial.

---

## 6. Datos personales (cuando se conecte la nube)

Hoy el guardado es local y el juego no trata datos de nadie. `CloudSaveManager`
(Supabase, `docs/12-cloud-saves.md`) pedirá un correo o una cuenta anónima. Antes de
conectarlo:

- **CRBV art. 28 (habeas data):** el jugador puede pedir ver, corregir o destruir sus
  datos. Hace falta un botón o un procedimiento para **borrar la cuenta y su partida**.
- **Ley Especial contra los Delitos Informáticos, arts. 20-22:** castigan revelar o
  usar datos personales sin autorización (2 a 6 años). No compartir datos con terceros.
- **Recoger lo mínimo:** la cuenta anónima es preferible al correo.
- **Google Play** exige una política de privacidad publicada y el formulario de
  "Seguridad de los datos". Con jugadores en Europa aplica el GDPR.
- Venezuela no tiene una ley general de protección de datos; el Plan Legislativo
  2026-2027 prevé una Ley de Derechos Digitales (ver §9).

---

## 7. Venta, impuestos y tiendas

- **SENIAT:** cobrar requiere RIF, y los ingresos pagan ISLR. Consultar el IVA con un
  contador si se factura en Venezuela.
- **Tiendas:** verificar **antes** de fijar el modelo de negocio que Google Play y Steam
  acepten cuentas de comerciante o pagos a desarrolladores residentes en Venezuela. No
  está confirmado y puede ser una limitación real.
- **LOCTI** (aporte a ciencia y tecnología): no aplica mientras no exista una empresa con
  ingresos brutos superiores a 150.000 veces el tipo de cambio oficial.
- **Disponibilidad por país:** decidir con el abogado si se excluye Venezuela de las
  tiendas (§2).

---

## 8. Pendientes

| # | Pendiente | Cuándo |
|---|---|---|
| 1 | Cambiar `OBJ_ELIMINATE_ALL` y `MSG_EXPEDITION_LOST` (ES y EN) según §3 | Próxima revisión de textos |
| 2 | Revisar el lore de las expediciones para que no se lean como saqueo | Próxima revisión de lore |
| 3 | Registrar la obra en el Registro de la Producción Intelectual del SAPI | Antes de publicar |
| 4 | Buscar y registrar la marca "Tormenta Imperial" (clases 9 y 41) | Antes de publicar |
| 5 | Consultar a un abogado: art. 3 de la Ley de Videojuegos Bélicos y exclusión de Venezuela | Antes de vender |
| 6 | Confirmar si Google Play y Steam pagan a desarrolladores en Venezuela | Antes de vender |
| 7 | RIF e impuestos con un contador | Antes de vender |
| 8 | Borrado de cuenta, política de privacidad y formulario de datos | Antes de conectar la nube |

---

## 9. Leyes en camino

A octubre de 2026 ninguna está publicada en Gaceta Oficial. Revisar en cada actualización
de este documento:

- **Ley de Inteligencia Artificial:** aprobada en primera discusión el 19/11/2024. Puede
  cambiar quién es autor de lo generado con IA (§5).
- **Ley de Derechos Digitales:** puede traer una ley de datos personales (§6).
- **Ley de Ciberseguridad** y **Ley de Telecomunicaciones** nueva.
- **Ley de Propiedad Industrial** nueva: puede cambiar el registro de marcas (§5).
- **Código de Ética para el Desarrollo y Aplicación Responsable de la IA** (Ministerio de
  Ciencia y Tecnología, 19/02/2026): guía sin fuerza de ley.

Todas están en el Plan Básico Legislativo 2026-2027 (aprobado el 22/01/2026).

---

## 10. Cómo usar este documento en una revisión

1. Buscar en `Tr.gd` (ES y EN) los verbos de la lista roja y amarilla:
   `matar`, `aniquil`, `extermin`, `elimin`, `aplast`, `masacr`, `sangre`, `kill`,
   `annihilat`, `exterminat`, `eliminat`, `crush`, `slaughter`, `blood`.
2. Revisar el arte y los modelos nuevos contra §3 (sin sangre, sin armas reales, sin
   insignias reales).
3. Revisar el `readme.md`, la ficha de tienda y cualquier publicación contra §4.
4. Comprobar que cada asset nuevo está en `assets/CREDITS.md` con su licencia (§5).
5. Si se tocó la nube, repasar §6.
6. Actualizar §8 (pendientes) y §9 (leyes en camino), y la fecha de "Última revisión".

---

## Fuentes

- Ley para la Prohibición de Videojuegos Bélicos y Juguetes Bélicos, G.O. N° 39.320,
  03/12/2009. Texto completo en
  [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Ley_para_la_Prohibici%C3%B3n_de_Videojuegos_B%C3%A9licos_y_Juguetes_B%C3%A9licos.pdf),
  contrastado con [Tu Gaceta Oficial](https://tugacetaoficial.com/leyes/ley-para-la-prohibicion-de-videojuegos-belicos-y-juguetes-belicos-gaceta-39320-2009-texto/).
- Constitución de la República Bolivariana de Venezuela, G.O. N° 5.908 Ext., 19/02/2009
  (arts. 28, 60, 98).
- Ley sobre el Derecho de Autor, G.O. N° 4.638 Ext., 01/10/1993 (arts. 2, 3, 17, 26, 44,
  59).
- Ley Especial contra los Delitos Informáticos, G.O. N° 37.313, 30/10/2001 (arts. 20-22,
  25).
- Ley de Propiedad Industrial, G.O. N° 25.227, 1956.
- LOCTI, reforma G.O. N° 6.693 Ext., 01/04/2022 (art. 26).
- Asamblea Nacional:
  [Plan Básico Legislativo 2026-2027](https://www.asambleanacional.gob.ve/noticias/parlamento-aprueba-plan-basico-legislativo-2026-2027) y
  [primera discusión de la Ley de IA](https://www.asambleanacional.gob.ve/noticias/an-aprueba-en-primera-discusion-proyecto-de-ley-de-inteligencia-artificial).
- Baker McKenzie (2026):
  [Venezuela: Código Ético para Inteligencia Artificial](https://www.bakermckenzie.com/-/media/files/insight/publications/2026/03/venezuela-cdigo-tico-para-inteligencia-artificial.pdf).
