extends RefCounted
## Una figura de WorkerWalkers (obrero o ciudadano): solo datos. La mueve
## WorkerWalkers y la dibujan WalkerFigures3D / WalkerFigures2D. Campos con
## tipo: leerlos en cada fotograma cuesta mucho menos que las claves de un
## Dictionary. Nada de esto se guarda.

const ROLE_WORKER := "worker"
const ROLE_CITIZEN := "citizen"
## Valor de `state` cuando anda (WorkerWalkers.State.WALK): el que balancea.
const WALKING := 1

var role := ROLE_CITIZEN
var kind := 0               # WorkerWalkers.Kind
var target: Node = null     # obrero: su edificio de trabajo
var home: Node = null
var at: Node = null         # donde esta dentro (null si esta fuera)
var dest: Node = null       # a donde va
var state := 0              # WorkerWalkers.State
var timer := 0.0
var pts: Array = []         # Vector2 en celdas (centro de celda = +0.5)
var seg := 0
var f := 0.0
var then := 0               # WorkerWalkers.Then
var door_in := false
var door_out := false
var pos := Vector2.ZERO
var dir := Vector2.DOWN
var scale := 0.0
var out := false            # se ve en la calle
var side := 0.0
var phase := 0.0
var pace := 1.0
var body := Color.WHITE
var accent := Color.WHITE
var skin := 0.0
var retiring := false
var gone := false
