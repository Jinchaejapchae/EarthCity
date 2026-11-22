extends CharacterBody3D
# 아케이드 차량. 앞방향은 -Z(Godot 기준). Kenney 모델은 +Z 가 앞이라 180도 돌려서 붙임.

var speed := 0.0
var heading := 0.0
var occupied := false
var model: Node3D
var length := 4.2
var wheelbase := 2.6


func setup(path: String, start: Vector3, head: float) -> void:
	collision_layer = 8
	collision_mask = 1 | 8
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(55.0)
	var scn := load(path) as PackedScene
	model = scn.instantiate()
	model.rotation.y = PI
	add_child(model)
	var ab := _aabb(model, Transform3D.IDENTITY)
	# 길이 약 4.3m 로 맞춤
	var sc := 4.3 / maxf(ab.size.z, ab.size.x)
	model.scale = Vector3.ONE * sc
	length = 4.3
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 1.2, 4.2)
	cs.shape = sh
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	position = start
	heading = head
	rotation.y = head


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var r := AABB()
	var first := true
	if n is MeshInstance3D:
		r = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for c in n.get_children():
		if c is Node3D:
			var a := _aabb(c, xf * (c as Node3D).transform)
			if a.size != Vector3.ZERO:
				r = a if first else r.merge(a)
				first = false
	return r


func drive(dt: float, throttle: float, steer_in: float, brake: bool) -> void:
	if throttle != 0.0:
		var acc := 15.0 if throttle * speed >= 0.0 else 30.0
		speed += throttle * acc * dt
	else:
		speed = move_toward(speed, 0.0, 5.0 * dt)
	if brake:
		speed = move_toward(speed, 0.0, 22.0 * dt)
	speed = clampf(speed, -9.0, 36.0)
	var ang := steer_in * 0.6 * clampf(1.0 - absf(speed) / 55.0, 0.3, 1.0)
	if absf(speed) > 0.3:
		heading += speed * tan(ang) / wheelbase * dt
	rotation.y = heading
	var v := -global_transform.basis.z * speed
	v.y = velocity.y - 30.0 * dt if not is_on_floor() else -1.0
	velocity = v
	move_and_slide()
	if get_slide_collision_count() > 0:
		speed *= 0.4
