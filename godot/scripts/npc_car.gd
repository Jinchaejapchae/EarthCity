extends AnimatableBody3D
# 도로 그래프를 따라 달리는 NPC 차. 교차로에서는 직진을 선호하며 무작위로 방향을 고름.

const GROUPS := ["major", "minor"]
const CRUISE := {"major": 14.0, "minor": 8.5}

var net: RefCounted
var traffic: Node
var a := 0
var b := 0
var nx := -1
var t := 0.0
var elen := 1.0
var speed := 0.0
var cruise := 8.0
var w := 6.0
var g := "minor"
var dir_s := Vector2(0, -1)
var dead := false
var wait_t := 0.0
var look := {}
var look_t := 0.0
var look_travel := 0.0
var side := 1.0 # 1 = 우측통행


func setup(model_path: String, net_: RefCounted, traffic_: Node, from_id: int, to_id: int, start_t: float) -> void:
	net = net_
	traffic = traffic_
	side = traffic.side
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = false
	var scn := load(model_path) as PackedScene
	var model: Node3D = scn.instantiate()
	model.rotation.y = PI
	add_child(model)
	_tint(model)
	var ab := _aabb(model, Transform3D.IDENTITY)
	model.scale = Vector3.ONE * (4.3 / maxf(ab.size.z, ab.size.x))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 1.2, 4.2)
	cs.shape = sh
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	preload("res://scripts/lights.gd").attach(self, false)
	a = from_id
	b = to_id
	_edge_changed()
	t = minf(start_t, elen * 0.9)
	speed = cruise * 0.5
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	dir_s = Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	_place(0.0)


## 차마다 도장 색을 살짝 다르게(팔레트 텍스처에 색을 곱함; 흰색 쪽으로 섞어 타이어/유리가 안 죽게)
func _tint(n: Node) -> void:
	var rg := RandomNumberGenerator.new()
	rg.randomize()
	var c: Color = preload("res://scripts/style.gd").car_tint(traffic.world.region, rg)
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null or "glass" in mat.resource_name.to_lower() or "window" in mat.resource_name.to_lower():
				continue
			mat = mat.duplicate()
			mat.albedo_color = c
			mi.set_surface_override_material(i, mat)


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var r := AABB()
	var first := true
	if n is MeshInstance3D:
		r = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D:
			var ab := _aabb(c, xf * (c as Node3D).transform)
			if ab.size != Vector3.ZERO:
				r = ab if first else r.merge(ab)
				first = false
	return r


func _edge_changed() -> void:
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	elen = maxf(Vector2(pb.x - pa.x, pb.z - pa.z).length(), 0.5)
	g = "minor"
	w = 6.0
	for e in net.nodes[a].out:
		if e[0] == b:
			w = e[1]
			g = e[2]
	cruise = CRUISE.get(g, 8.0) * (0.85 + 0.3 * float(absi(hash(a)) % 100) / 100.0)
	nx = net.pick_next(a, b, GROUPS)


func _physics_process(dt: float) -> void:
	if dead:
		return
	if not net.nodes.has(a) or not net.nodes.has(b):
		dead = true
		return
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	var dir := Vector2(pb.x - pa.x, pb.z - pa.z) / elen
	var target := cruise
	var remain := elen - t
	if remain < 20.0:
		if nx != -1 and net.nodes.has(nx):
			var pc: Vector3 = net.nodes[nx].p
			var d2 := Vector2(pc.x - pb.x, pc.z - pb.z).normalized()
			var ang := acos(clampf(dir.dot(d2), -1.0, 1.0))
			target = minf(target, lerpf(cruise, 3.5, clampf(ang / 1.3, 0.0, 1.0)))
		else:
			target = minf(target, 3.0)
	target = minf(target, traffic.speed_limit_for(self, Vector2(dir_s.x, dir_s.y)))
	look_t -= dt
	if look_t <= 0.0:
		look_t = 0.15
		look = traffic.junction_ahead(self)
		look_travel = 0.0
	look_travel += speed * dt
	var jl: float = 99.0
	if not look.is_empty():
		jl = traffic.junction_limit(self, look, float(look.dist) - look_travel)
	target = minf(target, jl)
	if jl < cruise * 0.5 and speed < 0.5:
		wait_t += dt
	else:
		wait_t = maxf(0.0, wait_t - dt)
	speed = move_toward(speed, target, (3.5 if target > speed else 12.0) * dt)
	t += speed * dt
	while t >= elen:
		t -= elen
		if nx == -1 or not net.nodes.has(nx):
			var tmp := a # 막다른 길: 유턴
			a = b
			b = tmp
		else:
			a = b
			b = nx
		if not net.nodes.has(a) or not net.nodes.has(b):
			dead = true
			return
		_edge_changed()
		pa = net.nodes[a].p
		pb = net.nodes[b].p
		dir = Vector2(pb.x - pa.x, pb.z - pa.z) / elen
	_place(dt)


func _place(dt: float) -> void:
	var pa: Vector3 = net.nodes[a].p
	var pb: Vector3 = net.nodes[b].p
	var k := t / elen
	var dir := Vector2(pb.x - pa.x, pb.z - pa.z) / elen
	dir_s = dir_s.lerp(dir, 1.0 - exp(-5.0 * dt)).normalized() if dt > 0.0 else dir
	var right := Vector2(-dir_s.y, dir_s.x) * side
	var lane := minf(w * 0.25, 2.2)
	var base := pa.lerp(pb, k)
	var pos := Vector3(base.x + right.x * lane, base.y + 0.03, base.z + right.y * lane)
	# 지면 도로는 가장자리도 지형을 따라가므로 차선 위치의 지형 높이에 맞춘다(다리는 노드 높이 그대로)
	var wd: Node3D = traffic.world
	var lift: float = base.y - wd.height_at(base)
	if lift < 1.5:
		pos.y = wd.height_at(pos) + lift + 0.03
	var yaw := atan2(-dir_s.x, -dir_s.y)
	var slope := (pb.y - pa.y) / elen
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, atan(slope))
	global_transform = Transform3D(basis, pos)
