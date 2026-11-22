extends RefCounted
# 차 전조등/후미등: 발광 구 + 노면에 퍼지는 빛 무리(가산). 실제 라이트는 내 차(SpotLight)만.

static var head_mat: StandardMaterial3D
static var tail_mat: StandardMaterial3D
static var beam_mat: StandardMaterial3D
static var beam_tex: GradientTexture2D


static func _init_mats() -> void:
	if head_mat != null:
		return
	head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(1, 0.95, 0.8)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1, 0.93, 0.75)
	head_mat.emission_energy_multiplier = 0.4
	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.5, 0.02, 0.02)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1, 0.05, 0.03)
	tail_mat.emission_energy_multiplier = 0.3
	beam_tex = GradientTexture2D.new()
	beam_tex.fill = GradientTexture2D.FILL_RADIAL
	beam_tex.fill_from = Vector2(0.5, 0.5)
	beam_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.92, 0.7, 0.5), Color(1, 0.92, 0.7, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	beam_tex.gradient = g
	beam_mat = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_texture = beam_tex
	beam_mat.albedo_color = Color(1, 1, 1, 0)
	beam_mat.disable_fog = true


static func set_night(f: float) -> void:
	_init_mats()
	head_mat.emission_energy_multiplier = 0.4 + 5.0 * f
	tail_mat.emission_energy_multiplier = 0.3 + 2.5 * f
	beam_mat.albedo_color.a = 0.9 * f


## 차(앞 = -Z, 길이 4.3m)에 전조등/후미등 추가. spot=true 면 진짜 스포트라이트도 달고 반환
static func attach(car: Node3D, spot: bool) -> Array:
	_init_mats()
	var spots: Array = []
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	for s in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		h.mesh = sm
		h.material_override = head_mat
		h.position = Vector3(0.68 * s, 0.7, -2.1)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(h)
		var t := MeshInstance3D.new()
		t.mesh = sm
		t.material_override = tail_mat
		t.position = Vector3(0.7 * s, 0.78, 2.1)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(t)
		if spot:
			var l := SpotLight3D.new()
			l.position = Vector3(0.68 * s, 0.75, -2.2)
			l.rotation_degrees = Vector3(-6, 0, 0)
			l.spot_range = 48.0
			l.spot_angle = 30.0
			l.light_energy = 0.0
			l.light_color = Color(1, 0.95, 0.85)
			l.shadow_enabled = false
			car.add_child(l)
			spots.append(l)
	var beam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.5, 15.0)
	beam.mesh = q
	beam.material_override = beam_mat
	beam.rotation_degrees = Vector3(-90, 0, 0)
	beam.position = Vector3(0, 0.12, -9.6)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	car.add_child(beam)
	return spots
