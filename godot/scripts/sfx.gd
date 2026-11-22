extends Node
# 소리: 전부 코드로 합성(외부 음원 없음). 엔진/타이어/경적/충돌/발소리/비/바람/천둥/도시 소음/새소리.
# main.gd 가 setup() 으로 참조를 넘기고 매 프레임 update(dt) 를 호출.

const RATE := 22050

var rng := RandomNumberGenerator.new()
var main: Node
var atmos: Node
var traffic: Node
var world: Node3D
var player: CharacterBody3D

var s_engine: AudioStreamWAV
var s_tire: AudioStreamWAV
var s_horn: AudioStreamWAV
var s_rain: AudioStreamWAV
var s_wind: AudioStreamWAV
var s_city: AudioStreamWAV
var s_steps: Array = []
var s_birds: Array = []
var s_thunder: AudioStreamWAV
var s_crash: AudioStreamWAV
var s_door: AudioStreamWAV

var p_engine: AudioStreamPlayer
var p_tire: AudioStreamPlayer
var p_horn: AudioStreamPlayer
var p_rain: AudioStreamPlayer
var p_wind: AudioStreamPlayer
var p_city: AudioStreamPlayer
var p_oneshot: AudioStreamPlayer
var p_step: AudioStreamPlayer3D
var p_bird: AudioStreamPlayer3D
var p_thunder: AudioStreamPlayer

var muted := false
var step_acc := 0.0
var last_speed := 0.0
var bird_timer := 3.0
var city_timer := 0.0
var road_dist := 999.0
var engine_was_on := false
var thunder_delay := -1.0


func setup(main_: Node, atmos_: Node, traffic_: Node, world_: Node3D, player_: CharacterBody3D) -> void:
	main = main_
	atmos = atmos_
	traffic = traffic_
	world = world_
	player = player_
	rng.seed = 77
	_synthesize()
	p_engine = _loop_player(s_engine, -80.0)
	p_tire = _loop_player(s_tire, -80.0)
	p_horn = _loop_player(s_horn, -80.0)
	p_rain = _loop_player(s_rain, -80.0)
	p_wind = _loop_player(s_wind, -80.0)
	p_city = _loop_player(s_city, -80.0)
	p_oneshot = AudioStreamPlayer.new()
	add_child(p_oneshot)
	p_thunder = AudioStreamPlayer.new()
	p_thunder.stream = s_thunder
	add_child(p_thunder)
	p_step = AudioStreamPlayer3D.new()
	p_step.max_distance = 30.0
	p_step.unit_size = 6.0
	add_child(p_step)
	p_bird = AudioStreamPlayer3D.new()
	p_bird.max_distance = 80.0
	p_bird.unit_size = 12.0
	add_child(p_bird)
	if atmos.has_signal("lightning"):
		atmos.lightning.connect(func(): thunder_delay = rng.randf_range(0.4, 2.8))


func _loop_player(st: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	add_child(p)
	p.play()
	return p


# ---------------------------------------------------------------- 합성
func _wav(a: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	var data := PackedByteArray()
	data.resize(a.size() * 2)
	for i in a.size():
		data.encode_s16(i * 2, int(clampf(a[i], -1.0, 1.0) * 32000.0))
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = a.size()
	return s


## 끝부분을 처음과 크로스페이드해서 이음매 없는 루프로
func _loopify(a: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := a.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = a[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = a[i] * t + a[n + i] * (1.0 - t)
	return out


func _noise(n: int, lp: float, hp := 0.0) -> PackedFloat32Array:
	# lp/hp: 0..1 한 극 필터 계수(클수록 높은 주파수까지 통과)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var z := 0.0
	for i in n:
		var x := rng.randf() * 2.0 - 1.0
		y += (x - y) * lp
		var v := y
		if hp > 0.0:
			z += (y - z) * hp
			v = y - z
		out[i] = v
	return out


func _norm(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	for i in a.size():
		a[i] = a[i] / m * peak
	return a


func _synthesize() -> void:
	# 엔진: 36Hz 기본음 + 배음(정수배라 1초 루프가 이음매 없음), 12Hz 맥동, 소프트 클리핑
	var eng := PackedFloat32Array()
	eng.resize(RATE)
	var amps := [1.0, 0.75, 0.95, 0.5, 0.5, 0.32, 0.25, 0.16, 0.1]
	for i in RATE:
		var t := float(i) / RATE
		var s := 0.0
		for h in amps.size():
			s += amps[h] * sin(TAU * 36.0 * (h + 1) * t + h * 0.7)
		s *= 0.78 + 0.22 * sin(TAU * 12.0 * t)
		eng[i] = tanh(s * 0.45)
	s_engine = _wav(_norm(eng, 0.7), true)
	# 타이어/도로 소음
	s_tire = _wav(_norm(_loopify(_noise(RATE * 2 + 3000, 0.12), 3000), 0.55), true)
	# 경적: 440 + 554Hz(정수 주기)
	var hn := PackedFloat32Array()
	hn.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		var v := sin(TAU * 440.0 * t) + 0.5 * sin(TAU * 880.0 * t) + sin(TAU * 554.0 * t) + 0.4 * sin(TAU * 1108.0 * t)
		hn[i] = tanh(v * 0.6)
	s_horn = _wav(_norm(hn, 0.5), true)
	# 비: 밝은 잡음, 바람: 어두운 잡음 + 느린 맥동, 도시: 아주 낮은 웅웅거림
	s_rain = _wav(_norm(_loopify(_noise(RATE * 3 + 4000, 0.7, 0.04), 4000), 0.6), true)
	var wn := _loopify(_noise(RATE * 3 + 4000, 0.035), 4000)
	for i in wn.size():
		wn[i] *= 0.65 + 0.35 * sin(TAU * float(i) / wn.size() * 2.0)
	s_wind = _wav(_norm(wn, 0.6), true)
	var cn := _loopify(_noise(RATE * 3 + 4000, 0.012), 4000)
	for i in cn.size():
		var t := float(i) / RATE
		cn[i] = cn[i] * 0.8 + 0.2 * sin(TAU * 50.0 * t) * 0.3
	s_city = _wav(_norm(cn, 0.6), true)
	# 발소리 3종: 짧은 잡음 + 낮은 쿵
	for k in 3:
		var n := int(RATE * 0.16)
		var st := _noise(n, 0.25 + 0.08 * k)
		for i in n:
			var t := float(i) / RATE
			var env := exp(-t * (38.0 - 4.0 * k))
			st[i] = (st[i] * 0.9 + 0.7 * sin(TAU * (70.0 + 10.0 * k) * t)) * env
		s_steps.append(_wav(_norm(st, 0.75), false))
	# 천둥: 갈색 잡음 + 긴 감쇠 + 처음 균열음
	var tn := int(RATE * 4.5)
	var th := _noise(tn, 0.02)
	var crack := _noise(tn, 0.4)
	for i in tn:
		var t := float(i) / RATE
		th[i] = th[i] * (1.0 - exp(-t * 14.0)) * exp(-t * 0.85) + crack[i] * exp(-t * 18.0) * 0.5
	s_thunder = _wav(_norm(th, 0.9), false)
	# 충돌: 잡음 폭발 + 금속 울림
	var cr := int(RATE * 0.7)
	var cs := _noise(cr, 0.5)
	for i in cr:
		var t := float(i) / RATE
		cs[i] = (cs[i] * exp(-t * 9.0) + 0.5 * sin(TAU * 180.0 * t) * exp(-t * 7.0) + 0.25 * sin(TAU * 760.0 * t) * exp(-t * 12.0))
	s_crash = _wav(_norm(cs, 0.9), false)
	# 문 닫는 소리
	var dn := int(RATE * 0.25)
	var ds := _noise(dn, 0.2)
	for i in dn:
		var t := float(i) / RATE
		ds[i] = (ds[i] * 0.6 + sin(TAU * 110.0 * t)) * exp(-t * 24.0) + 0.4 * sin(TAU * 1700.0 * t) * exp(-t * 90.0)
	s_door = _wav(_norm(ds, 0.7), false)
	# 새소리 3종: 위로 쓸어올리는 짧은 음 여러 개
	for k in 3:
		var parts := 2 + k
		var total := int(RATE * (0.14 * parts + 0.05))
		var b := PackedFloat32Array()
		b.resize(total)
		var base := 2800.0 + 600.0 * k
		for p in parts:
			var start := int(RATE * 0.14 * p)
			var plen := int(RATE * 0.1)
			var ph := 0.0
			for i in plen:
				var t := float(i) / plen
				var f := base * (1.0 + 0.5 * t + 0.12 * p)
				ph += TAU * f / RATE
				b[start + i] += sin(ph) * sin(PI * t) * 0.6
		s_birds.append(_wav(_norm(b, 0.5), false))


## 합성한 소리를 WAV 파일로 저장(들어 보기/분석용)
func dump(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var items := {"engine": s_engine, "tire": s_tire, "horn": s_horn, "rain": s_rain, "wind": s_wind, "city": s_city, "thunder": s_thunder, "crash": s_crash, "door": s_door, "step0": s_steps[0], "bird0": s_birds[0], "bird2": s_birds[2]}
	for k in items:
		(items[k] as AudioStreamWAV).save_to_wav("%s/%s.wav" % [dir, k])


# ---------------------------------------------------------------- 재생
func _db(v: float) -> float: # 0..1 선형 → dB
	return -80.0 if v <= 0.001 else linear_to_db(v)


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


func play_door() -> void:
	p_oneshot.stream = s_door
	p_oneshot.volume_db = -4.0
	p_oneshot.play()


func update(dt: float) -> void:
	var driving: CharacterBody3D = main.driving
	var spd := absf(driving.speed) if driving else 0.0
	# 내 차 엔진/타이어/경적
	var on := driving != null
	if on:
		var thr := absf(float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
		var target_pitch := 0.75 + spd / 36.0 * 2.2 + thr * 0.15
		p_engine.pitch_scale = lerpf(p_engine.pitch_scale, target_pitch, 1.0 - exp(-8.0 * dt))
		p_engine.volume_db = lerpf(p_engine.volume_db, _db(0.16 + 0.12 * thr + 0.06 * spd / 36.0), 1.0 - exp(-6.0 * dt))
		p_tire.pitch_scale = 0.8 + spd / 36.0 * 0.8
		p_tire.volume_db = _db(clampf(spd / 30.0, 0.0, 1.0) * 0.32)
		var horn := Input.is_key_pressed(KEY_H)
		p_horn.volume_db = -6.0 if horn else -80.0
		if absf(last_speed) - spd > 6.0: # 갑자기 속도가 확 줄면 충돌
			p_oneshot.stream = s_crash
			p_oneshot.volume_db = -2.0
			p_oneshot.play()
		if not engine_was_on:
			play_door()
	else:
		p_engine.volume_db = lerpf(p_engine.volume_db, -80.0, 1.0 - exp(-10.0 * dt))
		p_tire.volume_db = -80.0
		p_horn.volume_db = -80.0
		if engine_was_on:
			play_door()
	engine_was_on = on
	last_speed = spd
	# 발소리
	if not on and player.visible and player.is_on_floor():
		var hs := Vector2(player.velocity.x, player.velocity.z).length()
		if hs > 0.6:
			var stride := 0.75 if hs < 3.6 else 1.15
			step_acc += hs * dt / stride
			if step_acc >= 1.0:
				step_acc -= 1.0
				p_step.stream = s_steps[rng.randi() % s_steps.size()]
				p_step.pitch_scale = rng.randf_range(0.85, 1.15)
				p_step.volume_db = -6.0 if hs < 3.6 else -2.0
				p_step.global_position = player.global_position
				p_step.play()
		else:
			step_acc = 0.4
	# 날씨: 비 / 바람 / 천둥
	var rain: float = atmos.w.rain
	var wind: float = clampf(float(atmos.w.wind) / 9.0, 0.0, 1.0)
	p_rain.volume_db = lerpf(p_rain.volume_db, _db(rain * 0.5), 1.0 - exp(-2.0 * dt))
	p_wind.volume_db = lerpf(p_wind.volume_db, _db(0.04 + wind * 0.3 + float(atmos.w.cloud) * 0.04), 1.0 - exp(-1.5 * dt))
	if thunder_delay >= 0.0:
		thunder_delay -= dt
		if thunder_delay < 0.0:
			p_thunder.pitch_scale = rng.randf_range(0.8, 1.1)
			p_thunder.volume_db = -3.0
			p_thunder.play()
	# 도시 소음(도로와 가까울수록) / 새소리(낮, 도로에서 멀 때)
	city_timer -= dt
	if city_timer <= 0.0:
		city_timer = 0.6
		var net: RefCounted = world.net_roads
		var id: int = net.nearest(player.global_position, 220.0, ["major", "minor"])
		road_dist = 999.0 if id == -1 else Vector2(net.nodes[id].p.x - player.global_position.x, net.nodes[id].p.z - player.global_position.z).length()
	var city_v: float = clampf(1.0 - road_dist / 220.0, 0.0, 1.0) * (1.0 - 0.4 * atmos.night)
	p_city.volume_db = lerpf(p_city.volume_db, _db(city_v * 0.35), 1.0 - exp(-1.5 * dt))
	bird_timer -= dt
	if bird_timer <= 0.0:
		bird_timer = rng.randf_range(2.5, 7.0)
		if atmos.night < 0.3 and rain < 0.2 and road_dist > 35.0 and not main.loading:
			var a := rng.randf() * TAU
			p_bird.stream = s_birds[rng.randi() % s_birds.size()]
			p_bird.global_position = player.global_position + Vector3(cos(a) * rng.randf_range(6, 22), rng.randf_range(3, 9), sin(a) * rng.randf_range(6, 22))
			p_bird.pitch_scale = rng.randf_range(0.9, 1.2)
			p_bird.volume_db = -8.0
			p_bird.play()
	_update_npc_engines(dt)


## 가까운 NPC 차(최대 10대)에만 3D 엔진 소리를 붙임
func _update_npc_engines(dt: float) -> void:
	if traffic == null or main.loading:
		return
	var listener: Vector3 = player.global_position
	var near: Array = []
	for c in traffic.cars:
		if is_instance_valid(c):
			var d: float = c.global_position.distance_to(listener)
			if d < 70.0:
				near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for i in mini(10, near.size()):
		var c: Node3D = near[i][1]
		keep[c] = true
		var ap: AudioStreamPlayer3D = c.get_node_or_null("EngineSfx")
		if ap == null:
			ap = AudioStreamPlayer3D.new()
			ap.name = "EngineSfx"
			ap.stream = s_engine
			ap.max_distance = 75.0
			ap.unit_size = 7.0
			ap.volume_db = -9.0
			ap.pitch_scale = 0.9 + randf() * 0.2
			c.add_child(ap)
			ap.play()
		var sp: float = c.speed
		ap.pitch_scale = lerpf(ap.pitch_scale, 0.7 + sp / 16.0 * 1.4, 1.0 - exp(-4.0 * dt))
	for c in traffic.cars:
		if is_instance_valid(c) and not keep.has(c):
			var ap2: Node = c.get_node_or_null("EngineSfx")
			if ap2:
				ap2.queue_free()
