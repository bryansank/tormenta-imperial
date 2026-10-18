extends SceneTree
## Genera por sintesis los sonidos que no tienen una pista CC0 que encaje: los tres
## bucles de ambiente (dia, noche y Tormenta) y dos efectos de la Tormenta (sirena lejana
## del Aviso y trueno). Es obra propia del proyecto: ruido filtrado y osciladores,
## sin ninguna muestra de fuera.
##
## Uso (sin abrir el editor):
##   godot --headless --path . -s tools/gen_ambient_audio.gd -- --out=res://build/audio_gen/
##
## Escribe WAV PCM de 16 bits a 22050 Hz en `--out` (por defecto `res://build/audio_gen/`,
## que git no sigue). Los OGG del repo salen de estos WAV con cualquier codificador
## Vorbis (calidad ~0.3); ver assets/audio/MANIFEST.md. La semilla es fija, asi que
## cada pasada da los mismos sonidos.
##
##   ambient/day      40 s, estereo, bucle: olas suaves + pajaros
##   ambient/storm    40 s, estereo, bucle: viento con rachas + lluvia + truenos lejanos
##   ambient/night    40 s, estereo, bucle: grillos + olas suaves, sin pajaros
##   ambient/coast    40 s, estereo, bucle: orilla del tablero (resaca, brisa, gaviotas)
##   sfx/storm_warning  ~5 s, mono: sirena lejana con eco
##   sfx/storm_thunder  ~5.5 s, mono: chasquido y retumbo

const RATE := 22050
const LOOP_SECONDS := 40.0
## Cola que se funde con el principio para que el bucle no tenga costura.
const XFADE_SECONDS := 3.0
const SEED := 20261012

var _rng := RandomNumberGenerator.new()
## La lluvia de la Tormenta tira de su propio generador: asi el viento, los truenos
## y los demas bucles salen identicos a los de antes de anadirla.
var _rain_rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = SEED
	_rain_rng.seed = SEED + 7
	var out := "res://build/audio_gen/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	if not out.ends_with("/"):
		out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_write(out + "day.wav", _day())
	_write(out + "storm.wav", _storm())
	_write(out + "storm_warning.wav", [_siren()])
	_write(out + "storm_thunder.wav", [_thunder_sfx()])
	# La noche va la ultima: asi la semilla sigue dando los mismos cuatro de antes.
	_write(out + "night.wav", _night())
	# La costa del tablero, despues de todo lo anterior (misma razon).
	_write(out + "coast.wav", _coast())
	print("gen_ambient_audio: escritos en ", ProjectSettings.globalize_path(out))
	quit()

# ── Filtro biquad (RBJ) ──────────────────────────────────────────────

class Biquad:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func set_lowpass(freq: float, q: float, rate: float) -> void:
		var w := TAU * freq / rate
		var alpha := sin(w) / (2.0 * q)
		var c := cos(w)
		var a0 := 1.0 + alpha
		b0 = (1.0 - c) * 0.5 / a0
		b1 = (1.0 - c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0

	## Paso banda con 0 dB en el pico.
	func set_bandpass(freq: float, q: float, rate: float) -> void:
		var w := TAU * freq / rate
		var alpha := sin(w) / (2.0 * q)
		var c := cos(w)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b1 = 0.0
		b2 = -alpha / a0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0

	func tick(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y

## Ruido rosa (Paul Kellet, version economica). Un estado por voz.
class Pink:
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0

	func tick(white: float) -> float:
		b0 = 0.99765 * b0 + white * 0.0990460
		b1 = 0.96300 * b1 + white * 0.2965164
		b2 = 0.57000 * b2 + white * 1.0526913
		return (b0 + b1 + b2 + white * 0.1848) * 0.2

func _white() -> float:
	return _rng.randf_range(-1.0, 1.0)

# ── Envolventes ──────────────────────────────────────────────────────

## Oleaje: suma de olas que suben y bajan, cada una de 5-9 s, solapadas.
func _swell_envelope(n: int) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	env.resize(n)
	var t := 0.0
	var total := float(n) / RATE
	while t < total:
		var d := _rng.randf_range(5.5, 9.0)
		var rise := d * _rng.randf_range(0.3, 0.45)
		var amp := _rng.randf_range(0.55, 1.0)
		var start := int(t * RATE)
		var length := int(d * RATE)
		for i in range(length):
			var idx := start + i
			if idx >= n:
				break
			var s := float(i) / RATE
			var v: float
			if s < rise:
				v = pow(sin(PI * 0.5 * s / rise), 2.0)
			else:
				v = exp(-3.2 * (s - rise) / (d - rise))
			env[idx] = env[idx] + amp * v
		t += d * _rng.randf_range(0.55, 0.8)
	for i in range(n):
		env[i] = minf(env[i], 1.0)
	return env

## Valor aleatorio suave: puntos al azar cada `min_s`-`max_s` segundos,
## interpolados con coseno. Rango 0..1.
func _smooth_random(n: int, min_s: float, max_s: float) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	env.resize(n)
	var i := 0
	var a := _rng.randf()
	while i < n:
		var b := _rng.randf()
		var seg := int(_rng.randf_range(min_s, max_s) * RATE)
		for k in range(seg):
			if i + k >= n:
				break
			var f := (1.0 - cos(PI * float(k) / seg)) * 0.5
			env[i + k] = lerpf(a, b, f)
		i += seg
		a = b
	return env

# ── Dia: olas + pajaros ──────────────────────────────────────────────

func _day() -> Array:
	var n := int((LOOP_SECONDS + XFADE_SECONDS) * RATE)
	var chans := _waves(n, 1100.0)
	_add_birds(chans, n)
	_normalize(chans, 0.5)
	return _seamless(chans)

## Oleaje en estereo. `brightness` es cuanto se abre el filtro en la cresta de
## cada ola: de noche, menos (el mar suena mas lejos y mas tranquilo).
func _waves(n: int, brightness: float) -> Array:
	var env := _swell_envelope(n)
	var chans: Array = []
	for ch in range(2):
		var buf := PackedFloat32Array()
		buf.resize(n)
		var pink := Pink.new()
		var lp := Biquad.new()
		var low := Biquad.new()
		low.set_lowpass(180.0, 0.7, RATE)
		var brown := 0.0
		# El canal derecho va un poco por detras: el oleaje se abre en estereo.
		var lag := int((0.35 if ch == 1 else 0.0) * RATE)
		for i in range(n):
			var e := env[(i - lag + n) % n]
			if i % 32 == 0:
				lp.set_lowpass(260.0 + brightness * e, 0.6, RATE)
			var w := _white()
			brown = (brown + 0.02 * w) / 1.02
			var hiss := lp.tick(pink.tick(w)) * (0.12 + 0.88 * e)
			var boom := low.tick(brown * 3.5) * (0.25 + 0.75 * e)
			buf[i] = hiss * 0.9 + boom * 0.6
		chans.append(buf)
	return chans

# ── Noche: grillos + olas suaves (sin pajaros) ───────────────────────

func _night() -> Array:
	var n := int((LOOP_SECONDS + XFADE_SECONDS) * RATE)
	var chans := _waves(n, 550.0)
	# Las olas bajan: de noche mandan los grillos.
	for ci in range(chans.size()):
		var c: PackedFloat32Array = chans[ci]
		for i in range(n):
			c[i] = c[i] * 0.45
		chans[ci] = c
	_add_crickets(chans, n)
	_normalize(chans, 0.45)
	return _seamless(chans)

## Varios grillos, cada uno con su tono (3,6-4,9 kHz), su ritmo y su sitio en
## el estereo. Cada chirrido son 2-4 pulsos muy cortos; cada grillo se calla y
## vuelve de vez en cuando para que el coro no suene a metronomo.
func _add_crickets(chans: Array, n: int) -> void:
	var left: PackedFloat32Array = chans[0]
	var right: PackedFloat32Array = chans[1]
	for _c in range(6):
		var freq := _rng.randf_range(3600.0, 4900.0)
		var period := _rng.randf_range(0.45, 0.85)
		var pulses := _rng.randi_range(2, 4)
		var pulse_len := _rng.randf_range(0.010, 0.016)
		var pulse_gap := _rng.randf_range(0.018, 0.028)
		var amp := _rng.randf_range(0.10, 0.22) * (0.5 if _rng.randf() < 0.4 else 1.0)
		var pan := _rng.randf_range(0.1, 0.9)
		var gl := sqrt(1.0 - pan)
		var gr := sqrt(pan)
		var presence := _smooth_random(n, 3.0, 8.0)
		var t := _rng.randf_range(0.0, period)
		var total := float(n) / RATE
		while t < total:
			var start := int(t * RATE)
			var p := presence[mini(start, n - 1)]
			# Por debajo de un umbral este grillo calla un rato.
			var level := clampf((p - 0.3) / 0.4, 0.0, 1.0)
			if level > 0.0:
				for k in range(pulses):
					var ps := start + int(k * (pulse_len + pulse_gap) * RATE)
					var pl := int(pulse_len * RATE)
					for i in range(pl):
						var idx := ps + i
						if idx >= n:
							break
						var s := float(i) / pl
						var v := sin(TAU * freq * float(idx) / RATE) * sin(PI * s) * amp * level
						left[idx] = left[idx] + v * gl
						right[idx] = right[idx] + v * gr
			t += period * _rng.randf_range(0.93, 1.07)
	chans[0] = left
	chans[1] = right

## Grupos de trinos: cada uno con su tono, su barrido (baja, sube o trino) y su
## sitio en el estereo. Algunos lejos (mas bajos).
func _add_birds(chans: Array, n: int) -> void:
	var left: PackedFloat32Array = chans[0]
	var right: PackedFloat32Array = chans[1]
	var t := _rng.randf_range(0.5, 2.0)
	var total := float(n) / RATE
	while t < total - 1.0:
		var base := _rng.randf_range(2400.0, 4300.0)
		var kind := _rng.randi_range(0, 2)
		var chirps := _rng.randi_range(3, 7)
		var amp := _rng.randf_range(0.05, 0.14) * (0.45 if _rng.randf() < 0.35 else 1.0)
		var pan := _rng.randf_range(0.15, 0.85)
		var gains := [sqrt(1.0 - pan), sqrt(pan)]
		var c := t
		for _k in range(chirps):
			var d := _rng.randf_range(0.05, 0.13)
			var start := int(c * RATE)
			var length := int(d * RATE)
			var phase := 0.0
			for i in range(length):
				var idx := start + i
				if idx >= n:
					break
				var s := float(i) / length
				var f: float
				match kind:
					0:
						f = base * lerpf(1.3, 0.95, s)
					1:
						f = base * lerpf(0.9, 1.25, s)
					_:
						f = base + 350.0 * sin(TAU * 32.0 * float(i) / RATE)
				phase += TAU * f / RATE
				var v := (sin(phase) + 0.15 * sin(2.0 * phase)) * pow(sin(PI * s), 2.0) * amp
				left[idx] = left[idx] + v * float(gains[0])
				right[idx] = right[idx] + v * float(gains[1])
			c += d + _rng.randf_range(0.04, 0.12)
		t = c + _rng.randf_range(1.2, 4.5)
	chans[0] = left
	chans[1] = right

# ── Tormenta: viento + truenos lejanos ───────────────────────────────

func _storm() -> Array:
	var n := int((LOOP_SECONDS + XFADE_SECONDS) * RATE)
	var gust := _smooth_random(n, 1.5, 4.0)
	var howl := _smooth_random(n, 2.0, 5.0)
	var chans: Array = []
	for ch in range(2):
		var buf := PackedFloat32Array()
		buf.resize(n)
		var pink := Pink.new()
		var low := Biquad.new()
		low.set_lowpass(420.0, 0.7, RATE)
		var band := Biquad.new()
		var brown := 0.0
		var lag := int((0.6 if ch == 1 else 0.0) * RATE)
		for i in range(n):
			var g := gust[(i - lag + n) % n]
			var h := howl[(i - lag + n) % n]
			if i % 32 == 0:
				band.set_bandpass(320.0 + 520.0 * h + 180.0 * g, 5.0, RATE)
			var w := _white()
			brown = (brown + 0.02 * w) / 1.02
			var body := low.tick(brown * 3.5) * (0.35 + 0.65 * g)
			var whistle := band.tick(pink.tick(w)) * (0.15 + 0.85 * g * h) * 2.2
			buf[i] = body + whistle
		chans.append(buf)
	# Tres truenos lejanos, sin chasquido: solo el retumbo.
	var left: PackedFloat32Array = chans[0]
	var right: PackedFloat32Array = chans[1]
	for at in [5.5 + _rng.randf() * 3.0, 18.0 + _rng.randf() * 3.0, 30.0 + _rng.randf() * 3.0]:
		var rumble := _rumble(_rng.randf_range(4.0, 6.0), 140.0)
		var amp := _rng.randf_range(0.9, 1.4)
		var start := int(at * RATE)
		for i in range(rumble.size()):
			var idx := start + i
			if idx >= n:
				break
			left[idx] = left[idx] + rumble[i] * amp
			right[idx] = right[idx] + rumble[i] * amp * 0.85
	chans[0] = left
	chans[1] = right
	_add_rain(chans, n, gust)
	_normalize(chans, 0.55)
	return _seamless(chans)

## Lluvia: un siseo agudo que sube con las rachas y gotas sueltas que golpean
## cerca (chasquidos muy cortos repartidos en estereo). Va con `_rain_rng`.
func _add_rain(chans: Array, n: int, gust: PackedFloat32Array) -> void:
	var m := 0.0
	for c: PackedFloat32Array in chans:
		for i in range(0, n, 16):
			m = maxf(m, absf(c[i]))
	# Por debajo del viento: lo agudo se oye mucho aunque lleve poca energia.
	var level := maxf(m, 0.05) * 0.09
	for ci in range(chans.size()):
		var c: PackedFloat32Array = chans[ci]
		var hiss := Biquad.new()
		hiss.set_bandpass(3800.0, 0.5, RATE)
		var hiss2 := Biquad.new()
		hiss2.set_bandpass(1900.0, 0.7, RATE)
		var lag := int((0.4 if ci == 1 else 0.0) * RATE)
		for i in range(n):
			var g := gust[(i - lag + n) % n]
			var w := _rain_rng.randf_range(-1.0, 1.0)
			c[i] = c[i] + (hiss.tick(w) * 1.1 + hiss2.tick(w) * 0.5) * level * (0.6 + 0.4 * g)
		# Gotas: ~25 por segundo en cada canal.
		var drops := int(float(n) / RATE * 25.0)
		for _d in range(drops):
			var at := _rain_rng.randi_range(0, n - 200)
			var amp := _rain_rng.randf_range(0.3, 1.0) * level * 1.6
			var f := _rain_rng.randf_range(2500.0, 5500.0)
			for k in range(120):
				var s := float(k) / RATE
				c[at + k] = c[at + k] + sin(TAU * f * s) * exp(-s / 0.0015) * amp
		chans[ci] = c

# ── Costa del tablero: resaca mas viva, gaviotas y brisa ─────────────

## Lo que suena en un tablero cuando la Tormenta no esta encima: la orilla de la
## isla (olas que rompen mas cerca que en el dia), alguna gaviota y brisa.
func _coast() -> Array:
	var n := int((LOOP_SECONDS + XFADE_SECONDS) * RATE)
	var chans := _waves(n, 1700.0)
	var breeze := _smooth_random(n, 2.0, 5.0)
	for ci in range(chans.size()):
		var c: PackedFloat32Array = chans[ci]
		var bp := Biquad.new()
		var pink := Pink.new()
		for i in range(n):
			if i % 32 == 0:
				bp.set_bandpass(450.0 + 250.0 * breeze[i], 2.0, RATE)
			c[i] = c[i] + bp.tick(pink.tick(_white())) * (0.15 + 0.35 * breeze[i])
		chans[ci] = c
	_add_gulls(chans, n)
	_normalize(chans, 0.5)
	return _seamless(chans)

## Gaviotas: llamadas nasales que caen de tono ("kiau"), de dos a cuatro seguidas,
## cada una en su sitio del estereo; pocas, para que no canse.
func _add_gulls(chans: Array, n: int) -> void:
	var left: PackedFloat32Array = chans[0]
	var right: PackedFloat32Array = chans[1]
	var t := _rng.randf_range(1.5, 4.0)
	var total := float(n) / RATE
	while t < total - 2.0:
		var base := _rng.randf_range(1300.0, 1800.0)
		var calls := _rng.randi_range(2, 4)
		var amp := _rng.randf_range(0.05, 0.11) * (0.5 if _rng.randf() < 0.4 else 1.0)
		var pan := _rng.randf_range(0.1, 0.9)
		var gl := sqrt(1.0 - pan)
		var gr := sqrt(pan)
		var c := t
		for _k in range(calls):
			var d := _rng.randf_range(0.22, 0.4)
			var start := int(c * RATE)
			var length := int(d * RATE)
			var phase := 0.0
			for i in range(length):
				var idx := start + i
				if idx >= n:
					break
				var s := float(i) / length
				var f := base * lerpf(1.15, 0.7, pow(s, 0.7))
				phase += TAU * f / RATE
				# Nasal: fundamental con armonicos fuertes y un poco de aspereza.
				var v := sin(phase) + 0.6 * sin(2.0 * phase) + 0.35 * sin(3.0 * phase)
				v *= pow(sin(PI * minf(1.0, s * 1.15)), 1.5) * amp
				left[idx] = left[idx] + v * gl
				right[idx] = right[idx] + v * gr
			c += d + _rng.randf_range(0.08, 0.2)
		t = c + _rng.randf_range(4.0, 9.0)
	chans[0] = left
	chans[1] = right

## Retumbo: ruido marron muy filtrado con varios golpes que decaen.
func _rumble(seconds: float, cutoff: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := Biquad.new()
	lp.set_lowpass(cutoff, 0.8, RATE)
	var lp2 := Biquad.new()
	lp2.set_lowpass(cutoff * 1.4, 0.7, RATE)
	var bumps: Array = []
	var bt := 0.0
	for _k in range(_rng.randi_range(3, 5)):
		bumps.append([bt, _rng.randf_range(0.5, 1.0), _rng.randf_range(0.8, 2.2)])
		bt += _rng.randf_range(0.3, 1.1)
	var brown := 0.0
	for i in range(n):
		var s := float(i) / RATE
		var e := 0.0
		for b in bumps:
			var dt: float = s - float(b[0])
			if dt < 0.0:
				continue
			var att := minf(1.0, dt / 0.25)
			e += float(b[1]) * att * exp(-dt / float(b[2]))
		e *= minf(1.0, (seconds - s) / 0.8)
		brown = (brown + 0.02 * _white()) / 1.02
		buf[i] = lp2.tick(lp.tick(brown * 3.5)) * e
	return buf

# ── Efectos sueltos de la Tormenta ───────────────────────────────────

## Sirena antiaerea lejana: sube, se sostiene y cae; filtrada y con eco.
func _siren() -> PackedFloat32Array:
	var seconds := 5.0
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phases := [0.0, 0.0]
	var detune := [1.0, 1.012]
	for i in range(n):
		var s := float(i) / RATE
		var f: float
		if s < 1.6:
			f = lerpf(170.0, 520.0, 1.0 - pow(1.0 - s / 1.6, 2.0))
		elif s < 2.6:
			f = 520.0 + 6.0 * sin(TAU * 5.0 * s)
		else:
			f = lerpf(520.0, 190.0, (s - 2.6) / (seconds - 2.6))
		var v := 0.0
		for voice in range(2):
			phases[voice] = float(phases[voice]) + TAU * f * float(detune[voice]) / RATE
			for k in range(1, 6):
				v += sin(float(phases[voice]) * k) / k
		var env := minf(1.0, s / 0.6) * minf(1.0, (seconds - s) / 1.4)
		buf[i] = v * env
	var lp := Biquad.new()
	lp.set_lowpass(1100.0, 0.7, RATE)
	for i in range(n):
		buf[i] = lp.tick(buf[i])
	# Eco de valle: la sirena suena lejos, no en la plaza.
	var out := buf.duplicate()
	for delay_gain in [[0.31, 0.35], [0.73, 0.18]]:
		var d := int(float(delay_gain[0]) * RATE)
		for i in range(d, n):
			out[i] = out[i] + buf[i - d] * float(delay_gain[1])
	var chans := [out]
	_normalize(chans, 0.5)
	return chans[0]

## Trueno cercano: chasquido corto y retumbo largo.
func _thunder_sfx() -> PackedFloat32Array:
	var seconds := 5.5
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bp := Biquad.new()
	bp.set_bandpass(1400.0, 0.7, RATE)
	for i in range(n):
		var s := float(i) / RATE - 0.03
		if s < 0.0:
			continue
		if s > 0.8:
			break
		var crack := exp(-s / 0.09) + 0.4 * exp(-maxf(0.0, s - 0.12) / 0.12) * (1.0 if s > 0.12 else 0.0)
		buf[i] = bp.tick(_white()) * crack * 0.55
	var rumble := _rumble(seconds - 0.1, 220.0)
	var start := int(0.1 * RATE)
	for i in range(rumble.size()):
		if start + i >= n:
			break
		buf[start + i] = buf[start + i] + rumble[i] * 1.6
	var chans := [buf]
	_normalize(chans, 0.6)
	return chans[0]

# ── Utilidades ───────────────────────────────────────────────────────

func _normalize(chans: Array, peak: float) -> void:
	var m := 0.0
	for c: PackedFloat32Array in chans:
		for v in c:
			m = maxf(m, absf(v))
	if m <= 0.0:
		return
	var k := peak / m
	# Por indice y de vuelta al Array: un Packed*Array sacado de un Array es una
	# copia (copia al escribir), y escribir en ella no tocaria el original.
	for ci in range(chans.size()):
		var c: PackedFloat32Array = chans[ci]
		for i in range(c.size()):
			c[i] = c[i] * k
		chans[ci] = c

## Funde la cola (XFADE_SECONDS) sobre el principio y recorta a LOOP_SECONDS:
## el ultimo sample lleva al primero sin salto.
func _seamless(chans: Array) -> Array:
	var length := int(LOOP_SECONDS * RATE)
	var xf := int(XFADE_SECONDS * RATE)
	var out: Array = []
	for c: PackedFloat32Array in chans:
		var o := PackedFloat32Array()
		o.resize(length)
		for i in range(length):
			o[i] = c[i]
		for i in range(xf):
			var t := float(i) / xf
			o[i] = c[i] * sqrt(t) + c[length + i] * sqrt(1.0 - t)
		out.append(o)
	return out

func _write(path: String, chans: Array) -> void:
	var n: int = (chans[0] as PackedFloat32Array).size()
	var stereo := chans.size() > 1
	var data := PackedByteArray()
	data.resize(n * chans.size() * 2)
	var off := 0
	for i in range(n):
		for c in chans:
			data.encode_s16(off, int(clampf(c[i], -1.0, 1.0) * 32767.0))
			off += 2
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = stereo
	wav.data = data
	var err := wav.save_to_wav(path)
	if err != OK:
		push_error("gen_ambient_audio: no se pudo escribir %s (%d)" % [path, err])
	else:
		print("  ", path, "  ", "%.1f s" % (float(n) / RATE))
