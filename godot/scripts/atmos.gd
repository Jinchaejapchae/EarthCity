extends Node
# 하늘/태양/달/별/날씨(실시간 Open-Meteo)/현지 시각/비·눈/번개/안개를 관리.
# 시각 = 선택한 장소의 현재 시각(NOAA 태양 위치식). 날씨 = 그 장소의 현재 날씨.

signal place_info(city: String, country: String, left_hand: bool)
signal lightning

const WEATHER_URL := "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=temperature_2m,weather_code,cloud_cover,precipitation,wind_speed_10m&timezone=auto"
const GEO_URL := "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=%.3f&longitude=%.3f&localityLanguage=ko"
const LEFT_HAND := ["GB", "IE", "JP", "AU", "NZ", "IN", "ID", "TH", "MY", "SG", "HK", "MO", "ZA", "KE", "TZ", "UG", "ZM", "ZW", "MZ", "BW", "NA", "MW", "PK", "BD", "LK", "NP", "BT", "BN", "MU", "MT", "CY", "JM", "TT", "BS", "BB", "GY", "SR", "FJ", "PG", "TL", "MV", "GG", "JE", "IM"]
const TIME_PRESETS := [-1.0, 6.5, 12.0, 18.5, 0.0]       # -1 = 실시간
const WEATHER_NAMES := ["실시간", "맑음", "구름", "비", "눈", "안개", "뇌우"]

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var cam: Camera3D
var world: Node3D
var sky_mat := ProceduralSkyMaterial.new()
var stars: MeshInstance3D
var stars_mat: StandardMaterial3D
var rain: GPUParticles3D
var snow: GPUParticles3D
var cloud_dome: MeshInstance3D
var cloud_mat: ShaderMaterial
var moon_quad: MeshInstance3D
var moon_mat: ShaderMaterial
var moon_phase := 0.5   # 0 삭 ~ 0.5 보름 ~ 1 삭
var moon_el := -30.0
var moon_az := 0.0

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, fog_disabled;
uniform float cover = 0.5;
uniform vec3 col_lit = vec3(1.0);
uniform vec3 col_shade = vec3(0.6);
uniform float wind = 1.0;
uniform float alt = 1500.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * noise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; }
	return s;
}
void fragment() {
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);   // 픽셀마다 정확한 시선 방향
	if (dir.y < 0.06) { discard; }
	vec2 p = dir.xz / max(dir.y, 0.06) * alt;                 // 구름층 평면 위 좌표(m)
	vec2 uv = p * 0.00035 + vec2(TIME * 0.004 * wind, TIME * 0.0015 * wind);
	float n = fbm(uv);
	float d = smoothstep(1.0 - cover, 1.0 - cover + 0.28, n);
	float n2 = fbm(uv + vec2(0.035, 0.02));        // 약간 비껴 샘플 → 위쪽이 밝고 아래가 어두운 입체감
	float lit = clamp(0.55 + (n - n2) * 9.0, 0.0, 1.0);
	float fade = smoothstep(0.06, 0.25, dir.y);
	ALBEDO = mix(col_shade, col_lit, lit);
	ALPHA = d * fade * 0.92;
}
"""

const MOON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float elong = 3.14159;     // 태양-달 이각(라디안): 0 삭, PI 보름
uniform float alpha = 1.0;
uniform float flipx = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.x *= flipx;
	float r = length(p);
	float R = 0.36;
	if (r > R) {
		float h = exp(-(r - R) * 9.0) * 0.22;      // 달무리
		ALBEDO = vec3(0.7, 0.8, 1.0);
		ALPHA = h * alpha * (0.35 + 0.65 * smoothstep(0.0, 1.0, abs(sin(elong * 0.5))));
	} else {
		vec2 q = p / R;
		vec3 n = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)));
		vec3 L = vec3(sin(elong), 0.0, -cos(elong));
		float sh = smoothstep(-0.04, 0.1, dot(n, L));
		float tex = 0.62 + 0.28 * noise(q * 2.6 + 4.0) + 0.1 * noise(q * 9.0);
		ALBEDO = vec3(0.97, 0.95, 0.88) * tex * (sh + 0.03);
		ALPHA = alpha;
	}
}
"""

var lat := 35.5
var lon := 129.3
var utc_offset := 9 * 3600
var time_mode := 0
var weather_mode := 0
var night := 0.0
var el := 30.0
var code := 0
var temp := 0.0
var label_weather := "맑음"
# 현재(부드럽게 변하는) 날씨 값과 목표값
var w := {"cloud": 0.1, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": 2.0}
var wt := {"cloud": 0.1, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": 2.0}
var flash := 0.0
var flash_timer := 6.0
var refresh := 0.0
var gen := 0


func setup(env_: Environment, sun_: DirectionalLight3D, moon_: DirectionalLight3D, cam_: Camera3D, world_: Node3D) -> void:
	env = env_
	sun = sun_
	moon = moon_
	cam = cam_
	world = world_
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.15
	_make_stars()
	_make_cloud_dome()
	_make_moon()
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wn.frequency = 0.02
	var wt_ := NoiseTexture2D.new()
	wt_.noise = wn
	wt_.width = 256
	wt_.height = 256
	wt_.seamless = true
	wt_.as_normal_map = true
	wt_.bump_strength = 6.0
	world.mats.water.normal_enabled = true
	world.mats.water.normal_texture = wt_
	world.mats.water.normal_scale = 0.6
	world.mats.water.uv1_triplanar = true
	world.mats.water.uv1_scale = Vector3(0.05, 0.05, 0.05)
	rain = _make_rain()
	snow = _make_snow()
	add_child(stars)
	add_child(rain)
	add_child(snow)


# ---------------------------------------------------------------- 장소/날씨 가져오기
func set_location(la: float, lo: float) -> void:
	lat = la
	lon = lo
	utc_offset = int(round(lo / 15.0)) * 3600
	gen += 1
	_fetch(gen)
	_fetch_place(gen)


func _fetch(g: int) -> void:
	var body: PackedByteArray = await world.net.fetch(WEATHER_URL % [lat, lon], false)
	if g != gen:
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if not (j is Dictionary) or not j.has("current"):
		return
	utc_offset = int(j.get("utc_offset_seconds", utc_offset))
	if weather_mode != 0:
		return # 수동 날씨 선택 중이면 실시간 값으로 덮지 않음
	var c: Dictionary = j["current"]
	code = int(c.get("weather_code", 0))
	temp = float(c.get("temperature_2m", 0.0))
	var cc := float(c.get("cloud_cover", 0.0)) / 100.0
	var pr := float(c.get("precipitation", 0.0))
	var wind := float(c.get("wind_speed_10m", 5.0)) / 3.6
	wt = {"cloud": cc, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": wind}
	if code in [45, 48]:
		wt.fog = 0.8
		wt.cloud = maxf(cc, 0.7)
	elif code >= 51 and code <= 57:
		wt.rain = 0.3
	elif code >= 61 and code <= 67:
		wt.rain = clampf(0.5 + pr / 6.0, 0.5, 1.0)
	elif code >= 80 and code <= 82:
		wt.rain = clampf(0.5 + pr / 6.0, 0.5, 1.0)
	elif (code >= 71 and code <= 77) or code == 85 or code == 86:
		wt.snow = clampf(0.5 + pr / 3.0, 0.5, 1.0)
	elif code >= 95:
		wt.rain = 0.9
		wt.storm = 1.0
		wt.cloud = 1.0
	if wt.rain > 0.0 or wt.snow > 0.0:
		wt.cloud = maxf(wt.cloud, 0.85)
	label_weather = _label()


func _label() -> String:
	if wt.storm > 0.0:
		return "뇌우"
	if wt.snow > 0.0:
		return "눈"
	if wt.rain > 0.0:
		return "비"
	if wt.fog > 0.0:
		return "안개"
	if wt.cloud > 0.75:
		return "흐림"
	if wt.cloud > 0.35:
		return "구름 조금"
	return "맑음"


func _fetch_place(g: int) -> void:
	var body: PackedByteArray = await world.net.fetch(GEO_URL % [lat, lon], false)
	if g != gen:
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary:
		var cc := str(j.get("countryCode", ""))
		var city := str(j.get("city", j.get("locality", "")))
		place_info.emit(city, str(j.get("countryName", "")), cc in LEFT_HAND)


# ---------------------------------------------------------------- 시간
static func solar_pos(unix: float, la: float, lo: float) -> Vector2:
	var d := unix / 86400.0 + 2440587.5 - 2451545.0
	var gg := deg_to_rad(fposmod(357.529 + 0.98560028 * d, 360.0))
	var q := fposmod(280.459 + 0.98564736 * d, 360.0)
	var L := deg_to_rad(q + 1.915 * sin(gg) + 0.02 * sin(2.0 * gg))
	var e := deg_to_rad(23.439 - 3.6e-7 * d)
	var ra := atan2(cos(e) * sin(L), cos(L))
	var dec := asin(sin(e) * sin(L))
	var h := deg_to_rad(fposmod(18.697374558 + 24.06570982441908 * d, 24.0) * 15.0 + lo) - ra
	var l := deg_to_rad(la)
	var elv := asin(sin(l) * sin(dec) + cos(l) * cos(dec) * cos(h))
	var az := atan2(-sin(h) * cos(dec), sin(dec) * cos(l) - cos(dec) * sin(l) * cos(h))
	return Vector2(rad_to_deg(elv), fposmod(rad_to_deg(az), 360.0))


func sim_unix() -> float:
	var now := Time.get_unix_time_from_system()
	var hour: float = TIME_PRESETS[time_mode]
	if hour < 0.0:
		return now
	var local_midnight := floorf((now + utc_offset) / 86400.0) * 86400.0 - utc_offset
	return local_midnight + hour * 3600.0


func local_clock() -> String:
	var t := int(sim_unix()) + utc_offset
	var s := posmod(t, 86400)
	return "%02d:%02d" % [s / 3600, (s % 3600) / 60]


func cycle_time() -> void:
	time_mode = (time_mode + 1) % TIME_PRESETS.size()


func cycle_weather() -> void:
	weather_mode = (weather_mode + 1) % WEATHER_NAMES.size()
	set_weather_override(weather_mode)


func set_weather_override(m: int) -> void:
	weather_mode = m
	match m:
		1: wt = {"cloud": 0.05, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": 2.0}
		2: wt = {"cloud": 0.7, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": 4.0}
		3: wt = {"cloud": 0.95, "rain": 0.8, "snow": 0.0, "fog": 0.0, "storm": 0.0, "wind": 5.0}
		4: wt = {"cloud": 0.9, "rain": 0.0, "snow": 0.8, "fog": 0.0, "storm": 0.0, "wind": 2.0}
		5: wt = {"cloud": 0.85, "rain": 0.0, "snow": 0.0, "fog": 0.85, "storm": 0.0, "wind": 1.0}
		6: wt = {"cloud": 1.0, "rain": 1.0, "snow": 0.0, "fog": 0.0, "storm": 1.0, "wind": 9.0}
	if m > 0:
		label_weather = WEATHER_NAMES[m]
	else:
		_fetch(gen)


func status_text() -> String:
	var t := "" if TIME_PRESETS[time_mode] < 0.0 else "(고정) "
	return "현지 %s%s · %s %.0f°C" % [t, local_clock(), label_weather, temp]


# ---------------------------------------------------------------- 매 프레임
func update(dt: float) -> void:
	refresh += dt
	if refresh > 600.0 and weather_mode == 0:
		refresh = 0.0
		_fetch(gen)
	for k in w:
		w[k] = lerpf(w[k], wt[k], 1.0 - exp(-0.8 * dt))
	var sp := solar_pos(sim_unix(), lat, lon)
	el = sp.x
	var az := deg_to_rad(sp.y)
	var sd := Vector3(sin(az) * cos(deg_to_rad(el)), sin(deg_to_rad(el)), -cos(az) * cos(deg_to_rad(el))).normalized()
	night = 1.0 - smoothstep(-3.0, 8.0, el)
	var cloud: float = w.cloud
	# 햇빛 / 달빛
	var day_e := smoothstep(-1.0, 12.0, el)
	sun.basis = Basis.looking_at(-sd, Vector3.UP)
	sun.light_energy = 2.0 * day_e * (1.0 - 0.72 * cloud)
	var k := smoothstep(2.0, 25.0, el)
	sun.light_color = Color(1.0, lerpf(0.6, 0.96, k), lerpf(0.38, 0.9, k))
	sun.visible = sun.light_energy > 0.02
	var md := Vector3(-sd.x, maxf(0.4, -sd.y * 0.7 + 0.35), -sd.z).normalized()
	moon.basis = Basis.looking_at(-md, Vector3.UP)
	moon.light_energy = 0.28 * (1.0 - smoothstep(-6.0, 2.0, el)) * (1.0 - 0.6 * cloud)
	moon.light_color = Color(0.7, 0.8, 1.0)
	moon.visible = moon.light_energy > 0.01
	# 하늘색 / 안개 / 앰비언트
	var day := smoothstep(-6.0, 8.0, el)
	var top := Color(0.01, 0.015, 0.04).lerp(Color(0.2, 0.42, 0.85), day)
	var hor := Color(0.03, 0.045, 0.09).lerp(Color(0.62, 0.76, 0.93), day)
	var dusk := smoothstep(-10.0, 0.0, el) * (1.0 - smoothstep(0.0, 14.0, el))
	hor = hor.lerp(Color(1.0, 0.5, 0.25), dusk * 0.85 * (1.0 - cloud * 0.6))
	top = top.lerp(Color(0.25, 0.28, 0.45), dusk * 0.4)
	var gray := Color(0.5, 0.53, 0.58) * lerpf(0.05, 1.0, day)
	top = top.lerp(gray, cloud * 0.9)
	hor = hor.lerp(gray * 1.1, cloud * 0.85)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor * 0.5
	var fog_col := hor.lerp(gray, w.fog)
	env.fog_light_color = fog_col
	env.fog_density = 0.0004 + 0.0018 * cloud * 0.3 + 0.012 * w.fog + 0.0012 * w.rain
	env.ambient_light_color = Color(0.25, 0.3, 0.5).lerp(Color(0.62, 0.7, 0.85), day).lerp(gray, cloud * 0.4)
	env.ambient_light_energy = lerpf(0.14, 0.5, day) * (1.0 - 0.15 * cloud)
	# 번개
	if w.storm > 0.5:
		flash_timer -= dt
		if flash_timer <= 0.0:
			flash = 1.0
			lightning.emit()
			flash_timer = randf_range(4.0, 12.0)
	flash = maxf(0.0, flash - dt * 5.0)
	if flash > 0.0:
		env.ambient_light_energy += flash * 3.0
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.85, 0.9, 1.0), flash)
	# 구름 돔 / 달
	_update_sky_objects(dt, sd, day)
	# 별
	stars_mat.albedo_color.a = clampf(night * (1.0 - cloud) * (1.0 - w.fog) * (1.0 - w.rain), 0.0, 1.0)
	stars.visible = stars_mat.albedo_color.a > 0.02
	stars.global_position = cam.global_position
	# 비/눈 입자(카메라를 따라다님)
	var wind_x: float = clampf(w.wind * 0.5, 0.0, 6.0)
	rain.global_position = cam.global_position + Vector3(0, 18, 0)
	snow.global_position = cam.global_position + Vector3(0, 12, 0)
	rain.emitting = w.rain > 0.05
	rain.amount_ratio = clampf(w.rain, 0.05, 1.0)
	(rain.process_material as ParticleProcessMaterial).direction = Vector3(wind_x * 0.05, -1, 0).normalized()
	snow.emitting = w.snow > 0.05
	snow.amount_ratio = clampf(w.snow, 0.05, 1.0)
	# 젖은 노면 / 적설
	var wet: float = clampf(w.rain * 1.2 + w.snow * 0.2, 0.0, 1.0)
	world.mats.set_weather(wet, w.snow)
	world.mats.set_wind(w.wind)
	world.mats.set_night(night)


# ---------------------------------------------------------------- 구름 / 달
func _make_cloud_dome() -> void:
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = sh
	cloud_mat.render_priority = -10
	var sm := SphereMesh.new()
	sm.radius = 4000.0
	sm.height = 8000.0
	sm.radial_segments = 24
	sm.rings = 12
	cloud_dome = MeshInstance3D.new()
	cloud_dome.mesh = sm
	cloud_dome.material_override = cloud_mat
	cloud_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_dome.extra_cull_margin = 8000.0
	add_child(cloud_dome)


func _make_moon() -> void:
	var sh := Shader.new()
	sh.code = MOON_SHADER
	moon_mat = ShaderMaterial.new()
	moon_mat.shader = sh
	moon_mat.render_priority = -5
	var q := QuadMesh.new()
	q.size = Vector2(420, 420)
	moon_quad = MeshInstance3D.new()
	moon_quad.mesh = q
	moon_quad.material_override = moon_mat
	moon_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon_quad.extra_cull_margin = 8000.0
	add_child(moon_quad)


## 오늘의 달 위상(삭일 기준 일수)과, 달의 하늘 위치(태양이 그 이각만큼 전에 있던 자리로 근사)
func _update_sky_objects(dt: float, sd: Vector3, day: float) -> void:
	var cam_p := cam.global_position
	var unix := sim_unix()
	var jd := unix / 86400.0 + 2440587.5
	var age := fposmod(jd - 2451550.26, 29.530588853)
	var elong := age / 29.530588853 * TAU           # 0 삭 → PI 보름 → TAU 삭
	moon_phase = age / 29.530588853
	var mp := solar_pos(unix - age / 29.530588853 * 86400.0, lat, lon)
	moon_el = mp.x
	moon_az = mp.y
	var maz := deg_to_rad(mp.y)
	var mel := deg_to_rad(mp.x)
	var mdir := Vector3(sin(maz) * cos(mel), sin(mel), -cos(maz) * cos(mel)).normalized()
	# 달빛: 달이 떠 있고 밤일 때만, 밝은 면적 비율만큼
	var illum := (1.0 - cos(elong)) * 0.5
	moon.basis = Basis.looking_at(-mdir, Vector3.UP)
	moon.light_energy = 0.34 * illum * smoothstep(-1.0, 8.0, moon_el) * (1.0 - smoothstep(-3.0, 8.0, el) * 0.97) * (1.0 - 0.6 * float(w.cloud))
	moon.light_color = Color(0.7, 0.8, 1.0)
	moon.visible = moon.light_energy > 0.01
	moon_quad.visible = moon_el > -3.0
	moon_quad.global_position = cam_p + mdir * 3400.0
	moon_mat.set_shader_parameter("elong", elong)
	moon_mat.set_shader_parameter("flipx", 1.0 if lat >= 0.0 else -1.0)
	moon_mat.set_shader_parameter("alpha", (1.0 - 0.9 * float(w.cloud)) * (0.4 + 0.6 * night))
	# 구름
	cloud_dome.global_position = cam_p
	var cov := clampf(float(w.cloud) * 0.95 + 0.08, 0.0, 1.0)
	cloud_mat.set_shader_parameter("cover", cov)
	cloud_mat.set_shader_parameter("wind", 1.0 + float(w.wind) * 0.4)
	var br := lerpf(0.07, 1.0, smoothstep(-8.0, 10.0, el))
	var dusk := smoothstep(-8.0, 0.0, el) * (1.0 - smoothstep(0.0, 14.0, el))
	var lit := Color(1, 1, 1).lerp(Color(1.0, 0.62, 0.42), dusk * 0.85) * br * (1.0 - 0.3 * float(w.cloud))
	cloud_mat.set_shader_parameter("col_lit", Vector3(lit.r, lit.g, lit.b))
	var shd := lit * Color(0.62, 0.66, 0.78)
	cloud_mat.set_shader_parameter("col_shade", Vector3(shd.r, shd.g, shd.b))
	# 물결 움직임
	var wm: StandardMaterial3D = world.mats.water
	wm.uv1_offset += Vector3(dt * 0.012, dt * 0.009, 0.0) * (1.0 + float(w.wind) * 0.3)


# ---------------------------------------------------------------- 보조 노드
func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in 1800:
		var u := rng.randf() * 2.0 - 1.0
		var a := rng.randf() * TAU
		var r := sqrt(1.0 - u * u)
		var v := Vector3(cos(a) * r, absf(u) * 0.97 + 0.03, sin(a) * r) * 3500.0
		verts.append(v)
		var b := rng.randf_range(0.5, 1.0)
		cols.append(Color(b, b, b * 1.05, 1.0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	stars = MeshInstance3D.new()
	stars.mesh = m
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.extra_cull_margin = 16384.0
	stars_mat = StandardMaterial3D.new()
	stars_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stars_mat.vertex_color_use_as_albedo = true
	stars_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stars_mat.use_point_size = true
	stars_mat.point_size = 2.2
	stars_mat.disable_fog = true
	stars_mat.albedo_color = Color(1, 1, 1, 0)
	stars.material_override = stars_mat


func _particle_base(amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _make_rain() -> GPUParticles3D:
	var p := _particle_base(6000, 1.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 0.5, 28)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.65)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.38)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = true
	q.material = m
	p.draw_pass_1 = q
	return p


func _make_snow() -> GPUParticles3D:
	var p := _particle_base(3500, 9.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 0.5, 28)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = true
	q.material = m
	p.draw_pass_1 = q
	return p
