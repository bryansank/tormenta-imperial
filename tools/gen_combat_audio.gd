extends SceneTree
## Genera por sintesis los efectos de combate por tipo de unidad (tierra, mar y aire).
## Obra propia del proyecto, como tools/gen_ambient_audio.gd: ruido filtrado,
## osciladores y envolventes (al estilo sfxr), sin ninguna muestra de fuera.
##
## Uso (sin abrir el editor, con el override.cfg de un user dir propio):
##   godot --headless --path . -s tools/gen_combat_audio.gd -- --out=res://build/audio_gen/
##
## Escribe WAV PCM de 16 bits, MONO, a 22050 Hz en `--out` (por defecto
## `res://build/audio_gen/`, que git no sigue). Los OGG de assets/audio/sfx/ salen
## de estos WAV con cualquier codificador Vorbis (ver assets/audio/MANIFEST.md).
## Semilla fija: cada pasada da los mismos sonidos. Cada efecto lleva su propio
## generador sembrado con su nombre, asi que anadir uno no cambia los demas.
##
##   shot_rifle     0,6 s  fusil: chasquido + cuerpo + eco corto (infanteria)
##   shot_cannon    1,6 s  canonazo: golpe, retumbo y eco (artilleria, canonera, acorazado)
##   tank_fire      1,3 s  tanque: disparo seco + chirrido de orugas (blindado)
##   tank_engine    1,3 s  motor diesel que acelera + orugas (el blindado se mueve)
##   plane_prop     1,8 s  avion de helice que pasa (caza y bombardero se mueven)
##   plane_strafe   1,0 s  pasada con ametralladora (caza ataca)
##   bomb_drop      1,8 s  silbido de bomba que cae + estallido (bombardero ataca)
##   airship_drone  2,2 s  zumbido grave de motores de dirigible (el dirigible se mueve)
##   ship_horn      2,0 s  bocina grave de barco, lejana (un barco se mueve)
##   torpedo        1,6 s  lanzamiento, carrera bajo el agua y explosion sorda (lancha)
##   splash         0,8 s  impacto en el agua (le dan a un barco)
##   unit_sunk      1,8 s  chapuzon grande y burbujas (cae un barco)
##   unit_downed    1,8 s  avion que cae silbando y se estrella (cae un aparato)

const Amb := preload("res://tools/gen_ambient_audio.gd")

const RATE := 22050
const SEED := 20261018

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	var out := "res://build/audio_gen/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	if not out.ends_with("/"):
		out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var makers := {
		"shot_rifle": _shot_rifle,
		"shot_cannon": _shot_cannon,
		"tank_fire": _tank_fire,
		"tank_engine": _tank_engine,
		"plane_prop": _plane_prop,
		"plane_strafe": _plane_strafe,
		"bomb_drop": _bomb_drop,
		"airship_drone": _airship_drone,
		"ship_horn": _ship_horn,
		"torpedo": _torpedo,
		"splash": _splash,
		"unit_sunk": _unit_sunk,
		"unit_downed": _unit_downed,
	}
	for name: String in makers:
		_rng.seed = SEED + hash(name)
		var buf: PackedFloat32Array = (makers[name] as Callable).call()
		_fade_tail(buf, 0.04)
		_normalize(buf, 0.7)
		_write(out + name + ".wav", buf)
	print("gen_combat_audio: escritos en ", ProjectSettings.globalize_path(out))
	quit()

# ── Piezas ───────────────────────────────────────────────────────────

func _white() -> float:
	return _rng.randf_range(-1.0, 1.0)

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## Suma `src` en `dst` desde `at` segundos, con ganancia.
func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float = 1.0) -> PackedFloat32Array:
	var start := int(at * RATE)
	for i in range(src.size()):
		var idx := start + i
		if idx >= dst.size():
			break
		if idx >= 0:
			dst[idx] = dst[idx] + src[i] * gain
	return dst

## Ruido por un paso banda (o paso bajo si `q` <= 0) con caida exponencial.
func _noise_hit(seconds: float, freq: float, q: float, decay: float, attack: float = 0.002) -> PackedFloat32Array:
	var b := _buf(seconds)
	var f := Amb.Biquad.new()
	if q > 0.0:
		f.set_bandpass(freq, q, RATE)
	else:
		f.set_lowpass(freq, 0.7, RATE)
	for i in range(b.size()):
		var t := float(i) / RATE
		var env := minf(1.0, t / attack) * exp(-t / decay)
		b[i] = f.tick(_white()) * env
	return b

## Retumbo grave: ruido marron muy filtrado.
func _boom(seconds: float, cutoff: float, decay: float, attack: float = 0.01) -> PackedFloat32Array:
	var b := _buf(seconds)
	var lp := Amb.Biquad.new()
	lp.set_lowpass(cutoff, 0.8, RATE)
	var lp2 := Amb.Biquad.new()
	lp2.set_lowpass(cutoff * 1.3, 0.7, RATE)
	var brown := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		brown = (brown + 0.02 * _white()) / 1.02
		var env := minf(1.0, t / attack) * exp(-t / decay)
		b[i] = lp2.tick(lp.tick(brown * 6.0)) * env
	return b

## Seno que baja de `f0` a `f1` (el "pum" de un canonazo).
func _thump(seconds: float, f0: float, f1: float, decay: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var f := lerpf(f1, f0, exp(-t / (decay * 0.5)))
		phase += TAU * f / RATE
		b[i] = sin(phase) * exp(-t / decay)
	return b

## Eco de valle: copias retrasadas y mas bajas.
func _echo(b: PackedFloat32Array, taps: Array) -> PackedFloat32Array:
	var out := b.duplicate()
	for tap in taps:
		var d := int(float(tap[0]) * RATE)
		var lp := Amb.Biquad.new()
		lp.set_lowpass(1200.0, 0.7, RATE)
		for i in range(d, out.size()):
			out[i] = out[i] + lp.tick(b[i - d]) * float(tap[1])
	return out

## Golpe metalico: parciales inarmonicos que se apagan rapido.
func _clank(seconds: float, base: float, decay: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var ratios := [1.0, 2.27, 3.31, 4.79]
	for i in range(b.size()):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(ratios.size()):
			v += sin(TAU * base * float(ratios[k]) * t) / (1.0 + k)
		b[i] = v * exp(-t / decay) * 0.5
	return b

## Burbuja: seno que sube deprisa y se apaga (el "plop" del agua).
func _bubble(freq: float, decay: float) -> PackedFloat32Array:
	var b := _buf(decay * 5.0)
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		phase += TAU * freq * (1.0 + 6.0 * t) / RATE
		b[i] = sin(phase) * exp(-t / decay)
	return b

## Zumbido de helice: tren de pulsos a la frecuencia de las palas, con armonicos.
## `freq_at` y `amp_at` son funciones del tiempo (doppler y distancia).
func _prop(seconds: float, freq_at: Callable, amp_at: Callable, cutoff_near: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var lp := Amb.Biquad.new()
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var a: float = amp_at.call(t)
		if i % 32 == 0:
			lp.set_lowpass(300.0 + cutoff_near * a, 0.8, RATE)
		var f: float = freq_at.call(t)
		phase += f / RATE
		var p := fposmod(phase, 1.0)
		# Pulso estrecho: cada pala que pasa es un golpe de aire.
		var pulse := exp(-p * 9.0) - 0.11
		var engine := 0.35 * sin(TAU * phase * 0.5)
		b[i] = lp.tick(pulse + engine + 0.25 * _white()) * a
	return b

# ── Tierra ───────────────────────────────────────────────────────────

func _shot_rifle() -> PackedFloat32Array:
	var b := _buf(0.6)
	_mix(b, _noise_hit(0.05, 3200.0, 0.8, 0.008, 0.0005), 0.0, 1.2)
	_mix(b, _noise_hit(0.2, 700.0, 1.1, 0.035, 0.001), 0.0, 1.0)
	_mix(b, _boom(0.5, 260.0, 0.12), 0.0, 0.8)
	return _echo(b, [[0.16, 0.22], [0.31, 0.1]])

func _shot_cannon() -> PackedFloat32Array:
	var b := _buf(1.6)
	_mix(b, _noise_hit(0.15, 1800.0, 0.0, 0.025, 0.001), 0.0, 0.9)
	_mix(b, _thump(1.2, 120.0, 38.0, 0.32), 0.0, 1.0)
	_mix(b, _boom(1.5, 170.0, 0.45, 0.005), 0.0, 1.3)
	return _echo(b, [[0.32, 0.25], [0.7, 0.12]])

func _tank_fire() -> PackedFloat32Array:
	var b := _buf(1.3)
	_mix(b, _noise_hit(0.12, 2200.0, 0.0, 0.018, 0.001), 0.0, 0.8)
	_mix(b, _thump(0.8, 160.0, 55.0, 0.18), 0.0, 1.0)
	_mix(b, _boom(0.9, 220.0, 0.22, 0.004), 0.0, 1.0)
	# El retroceso hace chirriar las orugas.
	_mix(b, _clank(0.3, 410.0, 0.05), 0.28, 0.35)
	_mix(b, _clank(0.3, 380.0, 0.05), 0.42, 0.25)
	_mix(b, _engine(1.3, 34.0, 40.0, 0.25), 0.0, 0.35)
	return b

func _tank_engine() -> PackedFloat32Array:
	var b := _engine(1.3, 30.0, 52.0, 0.15)
	# Orugas: golpecitos metalicos al ritmo de la marcha.
	var t := 0.18
	while t < 1.1:
		_mix(b, _clank(0.12, _rng.randf_range(520.0, 700.0), 0.018), t, 0.12)
		t += _rng.randf_range(0.09, 0.13)
	return b

## Motor diesel: explosiones de cilindro a `f0` -> `f1` Hz, ruido de escape.
func _engine(seconds: float, f0: float, f1: float, attack: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var lp := Amb.Biquad.new()
	lp.set_lowpass(520.0, 0.9, RATE)
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var s := t / seconds
		var f := lerpf(f0, f1, smoothstep(0.0, 0.7, s))
		phase += f / RATE
		var p := fposmod(phase, 1.0)
		# Cada vuelta, un golpe de cilindro un poco irregular.
		var fire := exp(-p * 6.0) * (0.8 + 0.2 * sin(TAU * phase * 0.25))
		var env := minf(1.0, t / attack) * minf(1.0, (seconds - t) / 0.35)
		b[i] = lp.tick(fire + 0.35 * _white()) * env
	return b

# ── Aire ─────────────────────────────────────────────────────────────

func _plane_prop() -> PackedFloat32Array:
	var dur := 1.8
	var mid := 0.85
	return _prop(dur,
		func(t: float) -> float: return 82.0 * (1.0 + 0.14 * tanh((mid - t) * 3.0)),
		func(t: float) -> float: return exp(-pow((t - mid) / 0.5, 2.0)) * minf(1.0, (dur - t) / 0.3),
		1500.0)

func _plane_strafe() -> PackedFloat32Array:
	var dur := 1.0
	var b := _prop(dur,
		func(t: float) -> float: return 88.0 - 10.0 * t,
		func(t: float) -> float: return 0.55 * minf(1.0, t / 0.15) * minf(1.0, (dur - t) / 0.3),
		1200.0)
	# Rafaga de ametralladora: siete disparos secos.
	var t := 0.12
	for _k in range(7):
		_mix(b, _noise_hit(0.04, 2600.0, 0.9, 0.007, 0.0005), t, 0.9)
		_mix(b, _noise_hit(0.08, 450.0, 1.0, 0.02, 0.001), t, 0.8)
		t += _rng.randf_range(0.065, 0.08)
	return b

func _bomb_drop() -> PackedFloat32Array:
	var b := _buf(1.8)
	# Silbido que baja y crece mientras la bomba cae.
	var fall := 0.9
	var phase := 0.0
	for i in range(int(fall * RATE)):
		var t := float(i) / RATE
		var f := lerpf(1500.0, 520.0, t / fall) * (1.0 + 0.01 * sin(TAU * 7.0 * t))
		phase += TAU * f / RATE
		b[i] = sin(phase) * 0.28 * pow(t / fall, 1.5)
	_mix(b, _noise_hit(0.2, 1500.0, 0.0, 0.05, 0.002), fall, 1.0)
	_mix(b, _thump(0.9, 90.0, 40.0, 0.3), fall, 0.9)
	_mix(b, _boom(0.9, 150.0, 0.38, 0.005), fall, 1.4)
	return b

func _airship_drone() -> PackedFloat32Array:
	var dur := 2.2
	var b := _buf(dur)
	var lp := Amb.Biquad.new()
	lp.set_lowpass(380.0, 0.8, RATE)
	var phases := [0.0, 0.0, 0.0, 0.0]
	var freqs := [55.0, 56.3, 110.4, 165.0]
	var gains := [1.0, 0.8, 0.45, 0.2]
	for i in range(b.size()):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(4):
			phases[k] = float(phases[k]) + TAU * float(freqs[k]) / RATE
			v += sin(float(phases[k])) * float(gains[k])
		# Los motores petardean despacio sobre el zumbido.
		var putter := 0.5 + 0.5 * sin(TAU * 13.0 * t)
		v += lp.tick(_white()) * 1.6 * putter
		var env := minf(1.0, t / 0.5) * minf(1.0, (dur - t) / 0.7)
		b[i] = v * env
	return b

func _unit_downed() -> PackedFloat32Array:
	var b := _buf(1.8)
	var crash := 1.15
	var dive := _prop(crash,
		func(t: float) -> float: return lerpf(110.0, 60.0, t / crash),
		func(t: float) -> float: return 0.6 + 0.4 * t / crash,
		1300.0)
	_mix(b, dive, 0.0, 0.7)
	var phase := 0.0
	for i in range(int(crash * RATE)):
		var t := float(i) / RATE
		phase += TAU * lerpf(1100.0, 420.0, t / crash) / RATE
		b[i] = b[i] + sin(phase) * 0.15 * (t / crash)
	_mix(b, _noise_hit(0.4, 1200.0, 0.0, 0.08, 0.002), crash, 1.1)
	_mix(b, _boom(0.65, 160.0, 0.25, 0.005), crash, 1.2)
	_mix(b, _clank(0.3, 300.0, 0.06), crash + 0.05, 0.3)
	return b

# ── Mar ──────────────────────────────────────────────────────────────

func _ship_horn() -> PackedFloat32Array:
	var dur := 2.0
	var b := _buf(dur)
	var phases := [0.0, 0.0, 0.0]
	var freqs := [98.0, 98.7, 147.0]
	var gains := [1.0, 0.7, 0.45]
	for i in range(b.size()):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(3):
			phases[k] = float(phases[k]) + TAU * float(freqs[k]) / RATE
			for h in range(1, 9):
				v += sin(float(phases[k]) * h) / h * float(gains[k])
		var env := minf(1.0, t / 0.12) * minf(1.0, maxf(0.0, (1.55 - t) / 0.45))
		b[i] = v * env
	var lp := Amb.Biquad.new()
	lp.set_lowpass(850.0, 0.7, RATE)
	for i in range(b.size()):
		b[i] = lp.tick(b[i])
	# Lejana: rebota en la costa.
	return _echo(b, [[0.38, 0.22]])

func _torpedo() -> PackedFloat32Array:
	var b := _buf(1.6)
	_mix(b, _noise_hit(0.3, 900.0, 0.9, 0.07, 0.004), 0.0, 0.8)
	# Carrera bajo el agua: siseo sordo que tiembla.
	var lp := Amb.Biquad.new()
	lp.set_lowpass(320.0, 1.2, RATE)
	for i in range(int(0.1 * RATE), int(0.95 * RATE)):
		var t := float(i) / RATE
		var wob := 0.6 + 0.4 * sin(TAU * 11.0 * t)
		b[i] = b[i] + lp.tick(_white()) * 1.2 * wob * minf(1.0, (t - 0.1) / 0.15)
	var hit := 0.95
	_mix(b, _boom(0.65, 140.0, 0.3, 0.008), hit, 1.6)
	_mix(b, _thump(0.6, 80.0, 35.0, 0.22), hit, 0.7)
	# El agua que salta tras el golpe.
	_mix(b, _noise_hit(0.6, 2600.0, 0.5, 0.2, 0.05), hit + 0.02, 0.6)
	return b

func _splash() -> PackedFloat32Array:
	var b := _buf(0.8)
	var bp := Amb.Biquad.new()
	for i in range(b.size()):
		var t := float(i) / RATE
		if i % 32 == 0:
			bp.set_bandpass(lerpf(2600.0, 700.0, minf(1.0, t / 0.5)), 0.7, RATE)
		b[i] = bp.tick(_white()) * minf(1.0, t / 0.01) * exp(-t / 0.18)
	_add_bubbles(b, 0.08, 0.7, 6, 0.25)
	return b

func _unit_sunk() -> PackedFloat32Array:
	var b := _buf(1.8)
	_mix(b, _boom(0.6, 180.0, 0.2, 0.005), 0.0, 1.0)
	var bp := Amb.Biquad.new()
	for i in range(int(0.9 * RATE)):
		var t := float(i) / RATE
		if i % 32 == 0:
			bp.set_bandpass(lerpf(2200.0, 600.0, minf(1.0, t / 0.7)), 0.6, RATE)
		b[i] = b[i] + bp.tick(_white()) * minf(1.0, t / 0.02) * exp(-t / 0.3) * 0.9
	# Gorgoteo y burbujas que se van espaciando: el barco se va al fondo.
	var gurgle := Amb.Biquad.new()
	gurgle.set_lowpass(220.0, 1.5, RATE)
	for i in range(int(0.3 * RATE), b.size()):
		var t := float(i) / RATE
		b[i] = b[i] + gurgle.tick(_white()) * 0.9 * exp(-(t - 0.3) / 0.6)
	_add_bubbles(b, 0.25, 1.7, 22, 0.35)
	return b

## Burbujas al azar entre `from` y `to`, cada vez mas espaciadas.
func _add_bubbles(b: PackedFloat32Array, from: float, to: float, count: int, gain: float) -> void:
	for k in range(count):
		var u := pow(_rng.randf(), 1.6)
		var at := lerpf(from, to, u)
		var g := gain * (1.0 - 0.6 * u) * _rng.randf_range(0.5, 1.0)
		_mix(b, _bubble(_rng.randf_range(500.0, 1500.0), _rng.randf_range(0.012, 0.03)), at, g)

# ── Utilidades ───────────────────────────────────────────────────────

func _fade_tail(b: PackedFloat32Array, seconds: float) -> void:
	var n := int(seconds * RATE)
	for i in range(n):
		var idx := b.size() - n + i
		if idx >= 0:
			b[idx] = b[idx] * (1.0 - float(i) / n)

func _normalize(b: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	if m <= 0.0:
		return
	var k := peak / m
	for i in range(b.size()):
		b[i] = b[i] * k

func _write(path: String, b: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in range(b.size()):
		data.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var err := wav.save_to_wav(path)
	if err != OK:
		push_error("gen_combat_audio: no se pudo escribir %s (%d)" % [path, err])
	else:
		print("  ", path, "  ", "%.1f s" % (float(b.size()) / RATE))
