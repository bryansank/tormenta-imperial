extends RefCounted
## Un camion de RoadTraffic: solo datos. Lo mueve RoadTraffic y lo dibujan
## TrafficFigures3D / TrafficFigures2D. Campos con tipo (leerlos en cada
## fotograma cuesta menos que las claves de un Dictionary). Nada de esto se
## guarda: el trafico es solo vista.

## Valor de `state` cuando rueda (RoadTraffic.State.DRIVE).
const DRIVING := 1

var source: Node = null      # el extractor del que sale la carga
var dest: Node = null        # el almacen o el Nucleo donde la deja
var at: Node = null          # donde esta dentro (cargando o descargando)
var state := 0               # RoadTraffic.State
var timer := 0.0
var pts: Array = []          # Vector2 en celdas (centro de celda = +0.5)
var seg := 0
var f := 0.0
var door_in := false
var door_out := false
var pos := Vector2.ZERO
var dir := Vector2.DOWN
var scale := 0.0
var out := false             # se ve en la carretera
var loaded := false          # lleva carga (va al almacen) o vuelve vacio
var cargo := Color.WHITE     # color de la carga (el del recurso)
var paint := Color.WHITE     # color de la cabina
var pace := 1.0
var gone := false
