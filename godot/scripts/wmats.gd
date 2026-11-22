extends RefCounted
# 월드 재질 모음 (건물 파사드 5종, 지붕, 도로 3종, 지형, 물)

var rng := RandomNumberGenerator.new()
var region_mats := {}      # 지역 번호 -> 파사드 재질 6개(필요할 때 만듦)
var shop_mats: Array = []   # 1층 상가 띠 3종
var all_mats: Array = []    # 밤 창문 발광을 켜고 끄기 위한 목록
var tree_trunk: ShaderMaterial
var tree_leaf: ShaderMaterial
var roof: StandardMaterial3D
var road_major: StandardMaterial3D
var road_minor: StandardMaterial3D
var road_path: StandardMaterial3D
var terrain: StandardMaterial3D
var water: StandardMaterial3D
var lamp_metal: StandardMaterial3D
var lamp_bulb: StandardMaterial3D
var lamp_pool: StandardMaterial3D
var wet_amt := 0.0

const TREE_SHADER := "shader_type spatial;
uniform vec4 base : source_color = vec4(1.0);
uniform float use_vcol = 1.0;
uniform float sway = 1.0;
uniform float wind = 0.2;
varying vec4 vc;
void vertex() {
	vc = COLOR;
	vec3 wp = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float ph = wp.x * 0.37 + wp.z * 0.23;
	float a = sway * wind * 0.045 * h * (sin(TIME * 1.7 + ph) + 0.5 * sin(TIME * 3.1 + ph * 2.3));
	VERTEX.x += a;
	VERTEX.z += a * 0.6;
}
void fragment() {
	ALBEDO = mix(base.rgb, vc.rgb, use_vcol);
	ROUGHNESS = 0.9;
}
"


func _init() -> void:
	rng.seed = 21
	for i in 3:
		shop_mats.append(_shop(i))
	var tsh := Shader.new()
	tsh.code = TREE_SHADER
	tree_trunk = ShaderMaterial.new()
	tree_trunk.shader = tsh
	tree_trunk.set_shader_parameter("base", Color(0.3, 0.22, 0.15))
	tree_trunk.set_shader_parameter("use_vcol", 0.0)
	tree_trunk.set_shader_parameter("sway", 0.35)
	tree_leaf = ShaderMaterial.new()
	tree_leaf.shader = tsh
	tree_leaf.set_shader_parameter("use_vcol", 1.0)
	tree_leaf.set_shader_parameter("sway", 1.0)
	roof = StandardMaterial3D.new()
	roof.albedo_color = Color(1, 1, 1)
	roof.vertex_color_use_as_albedo = true
	roof.roughness = 0.9
	road_major = _road_mat(true, Color(0.2, 0.2, 0.21))
	road_minor = _road_mat(false, Color(0.23, 0.23, 0.24))
	road_path = _road_mat(false, Color(0.5, 0.45, 0.36))
	terrain = StandardMaterial3D.new()
	terrain.vertex_color_use_as_albedo = true
	terrain.roughness = 1.0
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.05
	n.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.7, 0.7, 0.7), Color(0.95, 0.95, 0.95)])
	gr.offsets = PackedFloat32Array([0.0, 1.0])
	nt.color_ramp = gr
	terrain.albedo_texture = nt
	terrain.uv1_triplanar = true
	terrain.uv1_scale = Vector3(0.12, 0.12, 0.12)
	lamp_metal = StandardMaterial3D.new()
	lamp_metal.albedo_color = Color(0.18, 0.19, 0.2)
	lamp_metal.metallic = 0.6
	lamp_metal.roughness = 0.5
	lamp_bulb = StandardMaterial3D.new()
	lamp_bulb.albedo_color = Color(1, 0.95, 0.8)
	lamp_bulb.emission_enabled = true
	lamp_bulb.emission = Color(1, 0.85, 0.55)
	lamp_bulb.emission_energy_multiplier = 0.2
	var pt := GradientTexture2D.new()
	pt.fill = GradientTexture2D.FILL_RADIAL
	pt.fill_from = Vector2(0.5, 0.5)
	pt.fill_to = Vector2(1.0, 0.5)
	var pg := Gradient.new()
	pg.colors = PackedColorArray([Color(1, 0.85, 0.55, 0.6), Color(1, 0.85, 0.55, 0.0)])
	pg.offsets = PackedFloat32Array([0.0, 1.0])
	pt.gradient = pg
	lamp_pool = StandardMaterial3D.new()
	lamp_pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lamp_pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_pool.albedo_texture = pt
	lamp_pool.albedo_color = Color(1, 1, 1, 0)
	lamp_pool.disable_fog = true
	water = StandardMaterial3D.new()
	water.albedo_color = Color(0.1, 0.27, 0.36, 0.82)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic = 0.1


func set_night(f: float) -> void:
	for m in all_mats:
		m.emission_energy_multiplier = 2.2 * f
	lamp_bulb.emission_energy_multiplier = 0.2 + 6.0 * f
	lamp_pool.albedo_color.a = 0.85 * f
	preload("res://scripts/lights.gd").set_night(f)


## 비에 젖은 노면(어둡고 반들반들) / 눈 덮임(밝은 발광으로 흉내)
func set_wind(v: float) -> void:
	var a := clampf(v / 8.0, 0.08, 1.0)
	tree_trunk.set_shader_parameter("wind", a)
	tree_leaf.set_shader_parameter("wind", a)


func set_weather(wet: float, snow: float) -> void:
	wet_amt = wet
	for m in [road_major, road_minor]:
		m.roughness = lerpf(0.9, 0.28, wet)
		m.albedo_color = Color(1, 1, 1).lerp(Color(0.62, 0.64, 0.68), wet)
	terrain.roughness = lerpf(1.0, 0.7, wet)
	for m in [terrain, roof, road_major, road_minor, road_path]:
		m.emission_enabled = snow > 0.05
		m.emission = Color(0.78, 0.82, 0.88)
		m.emission_energy_multiplier = 0.5 * snow


## 위경도로 건축 양식(지역) 구분: 0 일반 / 1 동아시아 / 2 유럽 / 3 중동·지중해 / 4 아메리카 / 5 북유럽
static func region_of(la: float, lo: float) -> int:
	if lo > 95.0 and lo < 146.0 and la > 18.0 and la < 55.0:
		return 1
	if la >= 55.0 and lo > -25.0 and lo < 35.0:
		return 5
	if la > 35.0 and la < 72.0 and lo > -12.0 and lo < 45.0:
		return 2
	if la > 12.0 and la < 38.0 and lo > -18.0 and lo < 65.0:
		return 3
	if lo > -170.0 and lo < -30.0:
		return 4
	return 0


const PALETTES := {
	0: [[Color(0.55, 0.28, 0.2), Color(0.12, 0.16, 0.2), 0.45], [Color(0.72, 0.66, 0.52), Color(0.15, 0.2, 0.26), 0.4], [Color(0.55, 0.55, 0.53), Color(0.13, 0.15, 0.18), 0.35], [Color(0.78, 0.78, 0.76), Color(0.18, 0.22, 0.28), 0.4]],
	1: [[Color(0.82, 0.8, 0.74), Color(0.2, 0.26, 0.32), 0.45], [Color(0.7, 0.72, 0.72), Color(0.16, 0.2, 0.26), 0.5], [Color(0.85, 0.82, 0.7), Color(0.18, 0.24, 0.3), 0.4], [Color(0.62, 0.66, 0.7), Color(0.14, 0.18, 0.24), 0.45]],
	2: [[Color(0.82, 0.72, 0.55), Color(0.15, 0.17, 0.2), 0.35], [Color(0.88, 0.84, 0.74), Color(0.18, 0.2, 0.24), 0.35], [Color(0.6, 0.32, 0.24), Color(0.12, 0.14, 0.17), 0.4], [Color(0.7, 0.7, 0.68), Color(0.14, 0.16, 0.2), 0.35]],
	3: [[Color(0.86, 0.78, 0.62), Color(0.16, 0.16, 0.18), 0.35], [Color(0.92, 0.9, 0.85), Color(0.18, 0.2, 0.24), 0.35], [Color(0.78, 0.6, 0.42), Color(0.14, 0.14, 0.16), 0.3], [Color(0.84, 0.72, 0.55), Color(0.16, 0.18, 0.2), 0.35]],
	4: [[Color(0.55, 0.28, 0.2), Color(0.12, 0.16, 0.2), 0.4], [Color(0.42, 0.3, 0.25), Color(0.14, 0.16, 0.2), 0.4], [Color(0.7, 0.7, 0.7), Color(0.16, 0.2, 0.26), 0.35], [Color(0.6, 0.62, 0.66), Color(0.14, 0.18, 0.24), 0.4]],
	5: [[Color(0.72, 0.25, 0.2), Color(0.16, 0.18, 0.22), 0.4], [Color(0.85, 0.7, 0.3), Color(0.16, 0.18, 0.22), 0.4], [Color(0.9, 0.9, 0.88), Color(0.16, 0.2, 0.26), 0.4], [Color(0.4, 0.5, 0.6), Color(0.14, 0.18, 0.24), 0.4]],
}


## 지역의 파사드 재질 m(0..5). 4,5 는 모든 지역 공통의 유리/오피스 타워
func facade_mat(region: int, m: int) -> StandardMaterial3D:
	if not region_mats.has(region):
		var list: Array = []
		for e in PALETTES[region]:
			list.append(_facade(e[0], e[1], e[2]))
		list.append(_facade(Color(0.3, 0.38, 0.45), Color(0.2, 0.3, 0.38), 0.5))
		list.append(_facade(Color(0.18, 0.2, 0.24), Color(0.25, 0.32, 0.4), 0.55))
		region_mats[region] = list
	return region_mats[region][m]


## 1층 상가: 간판 띠 + 쇼윈도 + 출입문 (밤엔 쇼윈도가 환하게 켜짐)
func _shop(i: int) -> StandardMaterial3D:
	var img := Image.create(256, 128, true, Image.FORMAT_RGB8)
	var em := Image.create(256, 128, true, Image.FORMAT_RGB8)
	var wall: Color = [Color(0.72, 0.7, 0.66), Color(0.62, 0.6, 0.58), Color(0.78, 0.74, 0.66)][i]
	var sign_col: Color = [Color(0.78, 0.2, 0.18), Color(0.2, 0.4, 0.7), Color(0.9, 0.72, 0.2)][i]
	img.fill(wall)
	em.fill(Color.BLACK)
	for y in range(6, 34):
		for x in range(8, 248):
			img.set_pixel(x, y, sign_col * (0.9 + rng.randf() * 0.1))
			if rng.randf() < 0.5 or true:
				em.set_pixel(x, y, sign_col * 0.7)
	for y in range(44, 118):
		for x in range(12, 244):
			var door := x > 112 and x < 144
			var c := Color(0.1, 0.14, 0.18) if not door else Color(0.25, 0.2, 0.16)
			img.set_pixel(x, y, c)
			if not door:
				em.set_pixel(x, y, Color(1.0, 0.85, 0.6) * (0.55 + rng.randf() * 0.2))
	for y in range(40, 128):
		for x in [10, 11, 76, 77, 142, 143, 208, 209, 244, 245]:
			img.set_pixel(x, y, wall.darkened(0.3))
	img.generate_mipmaps()
	em.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(em)
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.7
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	all_mats.append(m)
	return m


func _facade(base: Color, glass: Color, lit: float) -> StandardMaterial3D:
	var img := Image.create(256, 256, true, Image.FORMAT_RGB8)
	var em := Image.create(256, 256, true, Image.FORMAT_RGB8)
	img.fill(base)
	em.fill(Color.BLACK)
	for cy in 4:
		for cx in 4:
			var on := rng.randf() < lit
			var gc := glass * (0.7 + rng.randf() * 0.5)
			for y in range(cy * 64 + 14, cy * 64 + 52):
				for x in range(cx * 64 + 12, cx * 64 + 52):
					img.set_pixel(x, y, Color(gc.r, gc.g, gc.b))
					if on:
						em.set_pixel(x, y, Color(1.0, 0.82, 0.5) * (0.6 + rng.randf() * 0.4))
			for x in range(cx * 64 + 10, cx * 64 + 54):
				img.set_pixel(x, cy * 64 + 52, base.darkened(0.35))
				img.set_pixel(x, cy * 64 + 53, base.darkened(0.2))
	img.generate_mipmaps()
	em.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(em)
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.75
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	all_mats.append(m)
	return m


func _road_mat(markings: bool, base: Color) -> StandardMaterial3D:
	var img := Image.create(64, 128, true, Image.FORMAT_RGB8)
	for y in 128:
		for x in 64:
			var v := 0.9 + rng.randf() * 0.2
			var c := base * v
			if markings:
				if (x >= 3 and x <= 4) or (x >= 59 and x <= 60):
					c = Color(0.82, 0.82, 0.8) # 가장자리 실선
				elif (x == 31 or x == 32) and y < 44:
					c = Color(0.9, 0.78, 0.2) # 중앙 점선
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
