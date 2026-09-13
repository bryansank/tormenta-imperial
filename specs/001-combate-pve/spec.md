# Feature Specification: Combate Roguelike por Turnos (PVE)

**Feature Branch**: `001-combate-pve`

**Created**: 2026-07-20

**Status**: Draft

**Input**: User description: "Implementar el combate PVE — el próximo pilar del juego
(Milestone B del roadmap): batalla táctica por turnos en grid, con estructura **roguelike**
(expediciones de encuentros generados proceduralmente, dificultad creciente y muerte
permanente de las unidades caídas). Acciones mover/atacar/defender, IA enemiga, y resolución
de la expedición con recompensas que retroalimentan la economía de la base."

## Clarifications

### Session 2026-07-20

- Q: ¿Qué estructura tiene una expedición? → A: Ramificada — un mapa de nodos con rutas
  entre las que el jugador elige su camino (estilo Slay the Spire), culminando en un jefe.
- Q: ¿Hay elección de recompensa entre encuentros? → A: Sí, un draft — tras ganar un
  encuentro el jugador elige 1 de varias recompensas/mejoras ofrecidas.
- Q: ¿Se curan las unidades entre encuentros de la misma expedición? → A: No — el daño
  persiste toda la expedición (atrición pura); la salud solo se restaura al volver a la base.
- Q: ¿Hay progresión persistente entre expediciones? → A: No — roguelike puro; cada
  expedición parte del ejército actual de la base, sin desbloqueos permanentes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Librar una batalla táctica por turnos (Priority: P1)

El jugador entra en un enfrentamiento PVE con las unidades que comprometió desde su base. El
juego cambia de la vista de gestión a un tablero de batalla por celdas donde despliega sus
unidades. Por turnos, el jugador y el enemigo mueven y actúan hasta que un bando es
derrotado. El jugador controla cada unidad: la selecciona, la mueve dentro de su alcance y la
usa para atacar a un enemigo en rango, defenderse o esperar. El encuentro termina cuando
todas las unidades de un bando son eliminadas.

**Why this priority**: Es el bloque atómico del pilar de combate. Sin una batalla jugable de
principio a fin no existe la feature; la estructura roguelike, las recompensas y la IA
avanzada se apoyan en este núcleo. Entregada sola ya es un MVP demostrable.

**Independent Test**: Iniciar un único encuentro con un grupo de prueba, ejecutar turnos de
mover/atacar hasta eliminar al enemigo y verificar que se declara la victoria del encuentro.
No depende de la generación procedural, la cadena de encuentros ni las recompensas.

**Acceptance Scenarios**:

1. **Given** el jugador comprometió al menos una unidad, **When** comienza un encuentro,
   **Then** el juego presenta un tablero con sus unidades y las del enemigo desplegadas en
   zonas iniciales distintas.
2. **Given** es el turno del jugador y tiene una unidad seleccionada, **When** elige una celda
   válida dentro del alcance de movimiento, **Then** la unidad se desplaza y consume su acción
   de movimiento del turno.
3. **Given** una unidad del jugador tiene un enemigo dentro de su rango de ataque, **When** el
   jugador ordena atacar, **Then** el enemigo recibe daño según los atributos de ambas
   unidades y, si su salud llega a cero, es eliminado del tablero.
4. **Given** todas las unidades enemigas del encuentro fueron eliminadas, **When** se resuelve
   la última acción, **Then** el juego declara la victoria del encuentro.
5. **Given** todas las unidades del jugador fueron eliminadas, **When** se resuelve la última
   acción enemiga, **Then** el juego declara la derrota (fin de la expedición).

---

### User Story 2 - Expedición roguelike de encuentros encadenados (Priority: P1)

El jugador lanza una **expedición** desde un panel de escaramuzas en su base, comprometiendo
un grupo de sus unidades entrenadas. La expedición se presenta como un **mapa ramificado de
nodos** generado proceduralmente: el jugador elige su ruta entre caminos que ofrecen
encuentros de distinto riesgo/recompensa, y la dificultad crece hasta un **encuentro de jefe**
final. Tras ganar cada encuentro, el jugador elige **una recompensa/mejora de entre varias
ofrecidas** (draft). Las unidades que caen se pierden para el resto de la expedición
(**muerte permanente**); las supervivientes continúan **conservando su daño acumulado sin
curarse** (atrición) hasta que la expedición se resuelve. La expedición termina cuando el
jugador vence al jefe final (victoria) o cuando su grupo es aniquilado (derrota). Cada
expedición se siente distinta gracias a la generación procedural del mapa y los encuentros.

**Why this priority**: Es lo que define el pilar como **roguelike** y no como una batalla
suelta: procedural, con riesgo creciente y decisiones de "hasta dónde arriesgar". Es P1 junto
al núcleo porque es la identidad de la feature; sin la estructura de expedición, el combate no
cumple la visión del juego.

**Independent Test**: Lanzar una expedición y recorrer su mapa; verificar que (a) el mapa y
los encuentros se generan proceduralmente y no son idénticos entre expediciones, (b) el
jugador puede elegir entre rutas ramificadas, (c) tras ganar un encuentro se ofrece un draft
de recompensas del que elige una, (d) la dificultad escala hasta un jefe final, (e) una
unidad eliminada no reaparece y las supervivientes conservan su daño, y (f) la expedición
concluye en victoria (jefe vencido) o derrota (grupo aniquilado).

**Acceptance Scenarios**:

1. **Given** el jugador tiene unidades disponibles, **When** abre el panel de escaramuzas y
   lanza una expedición, **Then** se genera proceduralmente un mapa de nodos ramificado y
   comienza en el nodo inicial con el grupo comprometido.
2. **Given** el jugador está en un nodo con varias rutas salientes, **When** elige una,
   **Then** avanza al encuentro de esa ruta (con su riesgo/recompensa asociados).
3. **Given** el jugador gana un encuentro, **When** se resuelve, **Then** se le ofrece un
   conjunto de recompensas/mejoras y aplica la que elige antes de continuar.
4. **Given** el jugador avanza por el mapa, **When** progresa hacia el final, **Then** la
   dificultad de los encuentros aumenta hasta culminar en un encuentro de jefe.
5. **Given** el jugador vence el encuentro de jefe, **When** se resuelve, **Then** la
   expedición se declara completada con éxito.
6. **Given** el grupo del jugador es aniquilado en cualquier encuentro, **When** se resuelve,
   **Then** la expedición termina en derrota y no continúa.
7. **Given** dos expediciones distintas, **When** se comparan sus mapas y encuentros,
   **Then** su estructura y composición difieren: no son idénticas.

---

### User Story 3 - El resultado de la expedición impacta la economía (Priority: P2)

El jugador quiere que las expediciones tengan consecuencias tangibles en su base. Al completar
una expedición (y por hitos dentro de ella) recibe recompensas que se suman a su economía. Las
bajas sufridas se reflejan en su ejército: las unidades eliminadas dejan de contar en su Poder
Militar y deben reentrenarse en el Cuartel. Las unidades que sobreviven regresan a la base
disponibles y con la salud restaurada.

**Why this priority**: Conecta el pilar de combate con el bucle de gestión ya existente y le da
propósito (arriesgar ejército por recompensas). Va después del núcleo y la estructura porque
depende de que ambos funcionen.

**Independent Test**: Completar una expedición y verificar que las recompensas se reflejan en
los recursos de la base con notificación; y que, al volver, el ejército muestra exactamente
las unidades supervivientes (las caídas ausentes, las vivas al 100% de salud).

**Acceptance Scenarios**:

1. **Given** el jugador completa una expedición con éxito, **When** regresa a la base, **Then**
   su economía refleja las recompensas obtenidas y recibe una notificación del botín.
2. **Given** el jugador perdió unidades durante la expedición (haya ganado o perdido), **When**
   regresa a la base, **Then** esas unidades ya no forman parte de su ejército ni de su Poder
   Militar, y puede reentrenarlas en el Cuartel.
3. **Given** el jugador termina la expedición con unidades supervivientes, **When** regresa a
   la base, **Then** esas unidades están disponibles de nuevo y con la salud restaurada.
4. **Given** el jugador pierde la expedición, **When** regresa a la base, **Then** el estado de
   su base (edificios, recursos existentes) se conserva salvo las bajas del ejército.

---

### User Story 4 - IA enemiga táctica y dificultad escalada (Priority: P3)

El jugador quiere que los encuentros se sientan como un reto y no como un trámite. El enemigo
actúa de forma inteligente: se aproxima, elige objetivos razonables (p. ej. unidades débiles o
de alto valor), ataca cuando le conviene y se posiciona. La dificultad de la expedición guarda
relación con el progreso del jugador (era actual y tamaño de su ejército) además de escalar
dentro de la propia expedición.

**Why this priority**: Eleva el combate de "funcional" a "divertido y rejugable", el corazón de
la rejugabilidad roguelike. Es mejorable de forma incremental sobre el núcleo, por eso es P3.

**Independent Test**: Enfrentar a la IA en un encuentro fijo y observar que sus unidades se
desplazan hacia el jugador, seleccionan objetivos y atacan cuando están en rango, en lugar de
permanecer inmóviles o actuar al azar.

**Acceptance Scenarios**:

1. **Given** es el turno del enemigo y hay unidades del jugador en el tablero, **When** la IA
   actúa, **Then** cada unidad enemiga se mueve hacia un objetivo alcanzable y lo ataca si
   queda en rango, o se aproxima si no.
2. **Given** varias unidades del jugador están al alcance de un enemigo, **When** la IA elige
   objetivo, **Then** prioriza según un criterio consistente (p. ej. el objetivo que puede
   eliminar o el de mayor valor) y no de forma puramente aleatoria.
3. **Given** el jugador está en una era avanzada con un ejército grande, **When** se genera una
   expedición, **Then** la fuerza enemiga base escala en consecuencia.

---

### Edge Cases

- **Sin unidades disponibles:** si el jugador intenta lanzar una expedición sin unidades
  comprometibles, el sistema lo impide con un mensaje claro.
- **Empate / estancamiento:** si en un encuentro ninguna unidad puede alcanzar a la otra, debe
  existir un límite de turnos con resolución definida para evitar encuentros infinitos.
- **Abandono a mitad de expedición:** el jugador debe poder retirarse de la expedición, con
  consecuencias definidas (conserva las recompensas ya ganadas y las unidades supervivientes;
  se cuenta como fin de la expedición, no como aniquilación).
- **Salir del juego durante una expedición:** el estado debe quedar consistente al reabrir
  (retomar la expedición donde iba o resolverla como abandono), sin corromper la partida.
- **Grupo mayor que el tablero:** debe existir un límite de despliegue por encuentro; el
  compromiso de unidades a la expedición respeta una capacidad definida.
- **Unidad sin acciones válidas:** una unidad rodeada o sin objetivos en rango debe poder
  pasar/defender sin bloquear el flujo del turno.
- **Generación procedural degenerada:** ni el mapa ni un encuentro generado deben ser
  imposibles por construcción (p. ej. un nodo sin ruta hacia el jefe, o un tablero sin espacio
  de despliegue) ni trivialmente vacíos; el jefe final siempre debe ser alcanzable.
- **Draft sin opción útil:** el draft siempre debe ofrecer al menos una recompensa aplicable;
  si el jugador ya no puede aprovechar cierta mejora, el conjunto ofrecido lo tiene en cuenta.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema MUST permitir al jugador lanzar una expedición PVE desde un panel de
  escaramuzas dedicado en la base, comprometiendo un grupo de sus unidades entrenadas
  (hasta una capacidad de despliegue definida).
- **FR-002**: El sistema MUST impedir lanzar una expedición si el jugador no tiene unidades
  comprometibles, e informar el motivo.
- **FR-003**: El sistema MUST estructurar cada expedición como un **mapa ramificado de nodos**
  generado **proceduralmente**, de forma que dos expediciones no sean idénticas.
- **FR-003a**: Los usuarios MUST poder elegir su ruta entre los caminos disponibles del mapa
  cuando un nodo ofrece más de una salida.
- **FR-004**: El sistema MUST aumentar la dificultad de los encuentros a medida que avanza la
  expedición, culminando en un **encuentro de jefe** final.
- **FR-005**: El sistema MUST presentar cada encuentro en un tablero de batalla por celdas,
  desplegando las unidades del jugador y del enemigo en zonas iniciales separadas.
- **FR-006**: El sistema MUST resolver cada encuentro por turnos, alternando entre el bando del
  jugador y el del enemigo según un orden de actuación (iniciativa) definido y observable.
- **FR-007**: Cada unidad MUST tener atributos de combate: salud, ataque, defensa, alcance de
  movimiento y rango de ataque, derivados de su tipo (Infantería, Artillería, Vehículo).
- **FR-008**: Los usuarios MUST poder, en su turno, seleccionar una unidad y ordenarle una
  acción: mover (dentro de su alcance), atacar (a un objetivo en rango), defender o esperar.
- **FR-009**: El sistema MUST calcular el daño según los atributos de atacante y defensor,
  reducir la salud del objetivo y eliminarlo del tablero cuando su salud llega a cero.
- **FR-010**: El sistema MUST tratar las bajas como **muerte permanente**: una unidad eliminada
  no reaparece en los encuentros posteriores de la expedición ni regresa a la base.
- **FR-011**: El sistema MUST llevar las unidades supervivientes de un encuentro al siguiente
  **conservando su daño acumulado sin curarse** (atrición): dentro de una expedición no hay
  recuperación de salud; esta solo se restaura al regresar a la base.
- **FR-011a**: Tras ganar un encuentro, el sistema MUST ofrecer al jugador un conjunto de
  recompensas/mejoras y aplicar únicamente la que el jugador elija (**draft**).
- **FR-012**: El sistema MUST declarar la victoria de un encuentro cuando todas las unidades
  enemigas de ese encuentro son eliminadas, y permitir avanzar por el mapa si hay más nodos.
- **FR-013**: El sistema MUST declarar la expedición completada con éxito cuando se vence el
  **encuentro de jefe** final, y terminada en derrota cuando el grupo del jugador es aniquilado.
- **FR-014**: El sistema MUST controlar las unidades enemigas mediante IA durante su turno:
  aproximarse, seleccionar objetivo y atacar cuando corresponde.
- **FR-015**: El sistema MUST impedir encuentros infinitos mediante una condición de término
  (p. ej. límite de turnos con resolución definida).
- **FR-016**: Los usuarios MUST poder abandonar la expedición en curso, conservando las
  recompensas ya ganadas y las unidades supervivientes.
- **FR-017**: Al finalizar la expedición, el sistema MUST reflejar las bajas en el ejército del
  jugador y en su Poder Militar, y devolver a las unidades supervivientes disponibles y con la
  salud restaurada por completo.
- **FR-018**: Al completar la expedición (y en hitos definidos dentro de ella), el sistema MUST
  otorgar recompensas que se integren en la economía de la base y notificar el resultado. Las
  mejoras obtenidas por draft (FR-011a) aplican solo durante la expedición en curso; no
  persisten entre expediciones (roguelike puro, sin meta-progresión).
- **FR-019**: El sistema MUST conservar el estado de la base (edificios, recursos previos,
  progreso) tras la expedición, modificando solo lo derivado del resultado (bajas y
  recompensas).
- **FR-020**: El sistema MUST mantener la partida en un estado consistente si el jugador cierra
  el juego durante una expedición, sin corromper el guardado.
- **FR-021**: La dificultad base de la expedición SHOULD escalar con el progreso del jugador
  (era actual y tamaño del ejército), además de la escalada interna entre encuentros.

### Key Entities *(include if feature involves data)*

- **Expedición (Run):** una tanda roguelike de combate. Reúne el grupo de unidades
  comprometido, el mapa ramificado de nodos, la posición actual en el mapa, las mejoras del
  draft activas, las recompensas acumuladas y el estado (en curso / completada / derrota /
  abandono).
- **Mapa de expedición:** grafo ramificado de nodos generado proceduralmente que define las
  rutas posibles desde el nodo inicial hasta el nodo del jefe final; el jugador elige su
  camino entre las salidas de cada nodo.
- **Nodo:** una posición del mapa; en esta versión representa un encuentro (con su
  riesgo/recompensa), siendo el último el del jefe.
- **Encuentro:** una batalla individual asociada a un nodo; tiene su tablero, su fuerza
  enemiga generada proceduralmente y su nivel de dificultad según la profundidad en el mapa.
- **Recompensa / mejora (draft):** conjunto de opciones ofrecidas tras ganar un encuentro, de
  las que el jugador elige una; sus efectos aplican solo durante la expedición en curso.
- **Unidad de combate:** instancia de una unidad dentro de la expedición; parte de un tipo del
  ejército (Infantería/Artillería/Vehículo) y añade estado de combate: salud actual, posición
  en el tablero, bando y si ya actuó este turno. Persiste entre encuentros de la misma
  expedición hasta morir (permanente).
- **Tablero de batalla:** cuadrícula de celdas con zonas de despliegue; determina posiciones,
  distancias de movimiento y rangos de ataque.
- **Orden de turno / iniciativa:** secuencia que define qué bando y qué unidades actúan y en
  qué orden dentro de una ronda de un encuentro.
- **Fuerza enemiga:** conjunto de unidades controladas por la IA en un encuentro, con
  composición y dificultad determinadas por la generación procedural y el progreso del jugador.
- **Generador de expedición:** la fuente procedural que produce el mapa ramificado, sus
  encuentros (composición enemiga, disposición, escalada), el jefe final y las opciones del
  draft, de modo que las expediciones sean variadas.
- **Resultado de expedición:** desenlace (éxito / derrota / abandono) con las bajas del jugador
  y las recompensas obtenidas, que se aplican de vuelta a la base.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un jugador puede completar una expedición de principio a fin (lanzar → encuentros
  por turnos → éxito/derrota → regreso a la base) sin ayuda externa en su primer intento en al
  menos el 80% de los casos.
- **SC-002**: Un encuentro típico se resuelve en menos de 5 minutos de tiempo real.
- **SC-003**: El 100% de los encuentros terminan en un desenlace definido; ninguno queda
  bloqueado o en bucle infinito.
- **SC-004**: Tras cada expedición, el ejército mostrado en la base coincide exactamente con
  las unidades supervivientes (0 discrepancias entre bajas de combate y roster resultante).
- **SC-005**: Al completar una expedición, las recompensas se reflejan en la economía de la
  base en el 100% de los casos, con notificación visible.
- **SC-006**: Cerrar y reabrir el juego durante una expedición nunca corrompe la partida
  (0 partidas corruptas en pruebas de interrupción).
- **SC-007**: En un encuentro contra la IA, las unidades enemigas realizan una acción
  significativa (aproximarse o atacar) en el 100% de sus turnos cuando existe un objetivo
  alcanzable; no permanecen inertes.
- **SC-008**: Dos expediciones consecutivas del mismo jugador presentan mapas y encuentros
  diferenciables (estructura de rutas, composición enemiga y/o disposición distintas) en al
  menos el 90% de los nodos comparables — la variabilidad procedural es perceptible.
- **SC-009**: En cada nodo con más de una salida, el jugador puede elegir su ruta; y tras cada
  encuentro ganado se le ofrece un draft con al menos 2 opciones aplicables (0 casos de draft
  sin opción útil).

## Assumptions

- La feature reutiliza el ejército gestionado por el sistema actual (unidades entrenadas en el
  Cuartel, con su capacidad, coste y Poder Militar); no introduce reclutamiento paralelo.
- Los tipos de unidad para el combate son los tres existentes (Infantería, Artillería,
  Vehículo), respetando su gating por era.
- El jugador compromete a la expedición un grupo de sus unidades (hasta una capacidad de
  despliegue), no necesariamente todo su ejército.
- Las recompensas se expresan en los recursos económicos existentes (oro/madera/acero/petróleo)
  y/o beneficios equivalentes; no se introducen monedas nuevas en esta versión.
- El combate ocurre en una vista/escena de batalla separada de la vista de gestión; no se juegan
  simultáneamente.
- Muerte permanente: las unidades caídas se pierden para siempre; las supervivientes regresan a
  la base al 100% de salud tras la expedición y se reentrena en el Cuartel lo perdido.
- Alcance del MVP: una expedición roguelike jugable con mapa ramificado procedural, encuentros
  por turnos, atrición, draft de recompensas, jefe final y permadeath.
- Roguelike puro (sin meta-progresión): no hay mejoras/desbloqueos persistentes entre
  expediciones; cada una parte del ejército actual de la base y las mejoras del draft duran
  solo la run. Un modelo roguelite queda fuera de alcance de esta versión.
- Los nodos del mapa representan encuentros de combate (más el jefe final). Los nodos
  no-combate (tiendas, descanso, eventos) quedan FUERA de alcance de esta versión.
- El multijugador (PVP/Co-op) está explícitamente fuera de alcance; esta feature es solo PVE.
