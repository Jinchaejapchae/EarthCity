extends Node3D
# 도로 옆(인도 쪽)을 걷는 NPC 보행자. 플레이어와 같은 Mixamo 캐릭터 + 걷기 애니메이션.

const CHAR := "res://assets/people/character.fbx"
const GROUPS := ["major", "minor", "path"]

var net: RefCounted
var world: Node3D
var a := 0
var b := 0
var nx := -1
var t := 0.0
var elen := 1.0
var speed := 1.3
var w := 6.0
var g := "minor"
var side := 1.0
var dead := false
var dir_s := Vector2(0, -1)
var anim: AnimationPlayer
var traffic: Node
var cur_anim := ""
var wants := false        # 이 교차로에서 길을 건너고 싶은가
var decided := false
var waiting := false
var wait_t := 0.0
var cross := 0.0          # 0 = 걷는 중, 0..1 = 횡단 진행도
var cross_dur := 8.0
var cross_ci := -1
var cross_phase := 0


func setup(net_: RefCounted, world_: Node3D, traffic_: Node, from_id: int, to_id: int, start_t: float) -> void:
	net = net_
	world = world_
	traffic = traffic_
	side = 1.0 if randf() < 0.5 else -1.0
	speed = randf_range(1.0, 1.5)
	var model: Node3D = (load(CHAR) as PackedScene).instantiate()
	model.rotation.y = PI
	add_child(model)
	var rg := RandomNumberGenerator.new()
	rg.randomize()
	look = preload("res://scripts/style.gd").ped_look(world.region, rg)
	_fix(model)
	model.scale = Vector3.ONE * randf_range(0.94, 1.06)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := AnimationLibrary.new()
	lib.add_animation("walking", load("res://assets/people/anim_walking.res"))
	lib.add_animation("idle", load("res://assets/people/anim_idle.res"))
	anim.add_animation_library("g", lib)
	_play("walking")
	anim.seek(randf() * 1.4)
	a = from_id
	b = to_id
	_edge_changed()
	t = minf(start_t, elen * 0.9)
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	dir_s = Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	_place(0.0)


func _play(nm: String) -> void:
	if cur_anim == nm:
		return
	cur_anim = nm
	anim.play("g/" + nm, 0.25)
	anim.speed_scale = speed / 1.02 if nm == "walking" else 1.0


## 교차로 입구(= 이 간선이 신호 교차로의 팔)에 닿았는가. 맞으면 건널 팔의 위상을 정함
func _entry_arm() -> bool:
	var sg: RefCounted = traffic.signals
	var cl: int = sg.node_cluster.get(b, -1)
	if cl == -1 or sg.node_cluster.get(a, -2) == cl or not sg.clusters.has(cl):
		return false
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	var travel := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	var best := 0.6
	var found := false
	for arm in sg.clusters[cl].arms:
		var dd: float = Vector2(arm.base.x - pb.x, arm.base.z - pb.z).length()
		var al: float = arm.d.dot(-travel)
		if dd < 12.0 and al > best:
			best = al
			cross_phase = arm.phase
			found = true
	if found:
		cross_ci = cl
	return found


func _can_cross() -> bool:
	var sg: RefCounted = traffic.signals
	if cross_ci == -1 or not sg.clusters.has(cross_ci):
		return false
	# 이 길의 차 신호가 빨강이고, 건너는 동안 초록으로 안 바뀔 만큼 남았을 때
	return sg.phase_state(cross_ci, cross_phase) == 2 and sg.time_to_green(cross_ci, cross_phase) > cross_dur + 1.5


const PED_SHADER := "shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 top_col : source_color;
uniform vec3 bot_col : source_color;
uniform vec3 skin_mul = vec3(1.0);
uniform float y0 = 0.0;
uniform float hgt = 1.0;
varying float ny;
void vertex() { ny = (VERTEX.y - y0) / hgt; }
void fragment() {
	vec4 t = texture(tex, UV);
	float luma = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(0.012, 0.05, luma);
	float neutral = step(t.r, t.b + 0.004);
	float cloth = dark * neutral * step(ny, 0.84);
	vec3 cc = ny < 0.5 ? bot_col : top_col;
	vec3 col = mix(t.rgb, cc * (0.3 + luma * 12.0), cloth);
	float skin = step(t.b + 0.008, t.r) * step(0.04, luma);
	col = mix(col, t.rgb * skin_mul, skin);
	ALBEDO = col;
	ROUGHNESS = 0.72;
}
"
var look := {}


func _fix(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.visibility_range_end = 140.0
		m.visibility_range_end_margin = 10.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			if mat.resource_name == "Ch06_body" and look.size() > 0:
				var sm := ShaderMaterial.new()
				sm.shader = _ped_shader()
				sm.set_shader_parameter("tex", mat.albedo_texture)
				sm.set_shader_parameter("top_col", look.top)
				sm.set_shader_parameter("bot_col", look.bottom)
				sm.set_shader_parameter("skin_mul", Vector3(look.skin.r, look.skin.g, look.skin.b))
				var ab := m.mesh.get_aabb()
				sm.set_shader_parameter("y0", ab.position.y)
				sm.set_shader_parameter("hgt", ab.size.y)
				m.set_surface_override_material(i, sm)
				continue
			mat = mat.duplicate()
			mat.albedo_color = Color(1, 1, 1, 1)
			mat.roughness = 0.72
			if "lash" in mat.resource_name.to_lower() or "hair" in mat.resource_name.to_lower():
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.set_surface_override_material(i, mat)


static var _shader: Shader


func _ped_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PED_SHADER
	return _shader


func _edge_changed() -> void:
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	elen = maxf(Vector2(pb.x - pa.x, pb.z - pa.z).length(), 0.5)
	for e in net.nodes[a].out:
		if e[0] == b:
			w = e[1]
			g = e[2]
	nx = net.pick_next(a, b, GROUPS)
	wants = randf() < 0.6
	decided = false


func _process(dt: float) -> void:
	if dead:
		return
	dt = minf(dt, 0.1)
	if not net.nodes.has(a) or not net.nodes.has(b):
		dead = true
		return
	# 횡단 중: 길을 가로질러 반대편 인도로(초록으로 바뀌면 서둘러 건넘)
	if cross > 0.0:
		var hurry := 1.0
		if traffic.signals.clusters.has(cross_ci) and traffic.signals.phase_state(cross_ci, cross_phase) != 2:
			hurry = 1.8
		cross += dt / cross_dur * hurry
		if cross >= 1.0:
			cross = 0.0
			side = -side
			_play("walking")
		_place(dt)
		return
	if waiting:
		wait_t += dt
		if _can_cross():
			waiting = false
			cross_dur = (w + 3.2) / 1.5
			cross = 0.001
			_play("walking")
		elif wait_t > 36.0:
			waiting = false # 오래 기다리면 포기하고 그냥 감
			_play("walking")
		else:
			_play("idle")
		_place(dt)
		return
	if wants and not decided and elen - t <= 2.0 and _entry_arm():
		decided = true
		waiting = true
		wait_t = 0.0
		_play("idle")
		_place(dt)
		return
	t += speed * dt
	while t >= elen:
		t -= elen
		if nx == -1 or not net.nodes.has(nx):
			var tmp := a
			a = b
			b = tmp
		else:
			a = b
			b = nx
		if not net.nodes.has(a) or not net.nodes.has(b):
			dead = true
			return
		_edge_changed()
	_place(dt)


func _place(dt: float) -> void:
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	var dir := Vector2(pb.x - pa.x, pb.z - pa.z) / elen
	dir_s = dir_s.lerp(dir, 1.0 - exp(-6.0 * dt)).normalized() if dt > 0.0 else dir
	var right := Vector2(-dir_s.y, dir_s.x)
	var off := 0.7 if g == "path" else w * 0.5 + 1.6
	var base := pa.lerp(pb, t / elen)
	var lat := off * side
	var face := dir_s
	if cross > 0.0:
		var k := smoothstep(0.0, 1.0, cross)
		lat = off * side * (1.0 - 2.0 * k)
		face = right * -side # 건너는 방향을 바라봄
	var p := Vector3(base.x + right.x * lat, 0.0, base.z + right.y * lat)
	p.y = world.height_at(p)
	global_position = p
	rotation.y = atan2(-face.x, -face.y)
