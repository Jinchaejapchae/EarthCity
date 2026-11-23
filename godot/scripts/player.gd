extends CharacterBody3D
# 걷는 플레이어. Mixamo 캐릭터(FBX) + Mixamo 애니메이션(제자리화해서 res 로 뽑아 둠: scripts/extract_anim.gd).

const WALK := 2.0
const RUN := 5.2
const CHAR := "res://assets/people/character.fbx"
const ANIMS := ["standing_up", "idle", "walking", "drunk_walk", "left_turn", "right_turn", "walk_to_stop", "run_to_stop", "running_to_turn", "running", "clapping"]
# 애니메이션 한 바퀴에 원래 이동하던 속도(m/s). 이동 속도와 맞춰 발 미끄러짐을 줄이는 데 씀
const STRIDE := {"walking": 1.02, "drunk_walk": 0.79, "running": 4.5}

var visual: Node3D
var model: Node3D
var anim: AnimationPlayer
var face := 0.0
var cur := ""
var drunk := false
var clap := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	visual = Node3D.new()
	add_child(visual)
	model = (load(CHAR) as PackedScene).instantiate()
	model.rotation.y = PI # 믹사모는 +Z 가 앞
	visual.add_child(model)
	_fix_materials(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := AnimationLibrary.new()
	for nm in ANIMS:
		var path := "res://assets/people/anim_%s.res" % nm
		if ResourceLoader.exists(path):
			lib.add_animation(nm, load(path))
	anim.add_animation_library("g", lib)
	_play("idle")


func _play(nm: String, spd := 1.0, blend := 0.25) -> void:
	if cur != nm:
		anim.play("g/" + nm, blend)
		cur = nm
	anim.speed_scale = spd


## 새 장소에 도착했을 때 바닥에서 일어나는 연출
func arrive() -> void:
	cur = ""
	_play("standing_up", 1.0, 0.0)


var swimming := false


## water_y: 지금 위치의 수면 높이(없으면 -1e9). 바닥보다 0.5m 넘게 깊으면 헤엄(느리게, 수면에 떠서)
func move(dt: float, dir: Vector3, run: bool, jump: bool, water_y := -1e9) -> void:
	swimming = water_y > -1e8 and water_y - global_position.y > 0.5
	var sp := RUN if run else WALK
	if swimming:
		sp = 1.5 if run else 1.0
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	if swimming:
		# 목까지 잠기게 수면 아래 0.9m 높이로 떠 있는다(중력 무시)
		velocity.y = clampf((water_y - 0.9 - global_position.y) * 5.0, -3.0, 3.0)
	elif is_on_floor():
		velocity.y = 4.6 if jump else -0.5
	else:
		velocity.y -= 16.0 * dt
	if dir.length() > 0.1:
		face = lerp_angle(face, atan2(-dir.x, -dir.z), 1.0 - exp(-12.0 * dt))
		visual.rotation.y = face
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 0.3:
		var nm := "drunk_walk" if drunk else ("running" if hs > 3.6 else "walking")
		_play(nm, clampf(hs / float(STRIDE[nm]), 0.6, 3.2), 0.2)
	elif cur == "standing_up" and anim.is_playing():
		pass # 일어나는 중
	elif (cur == "running" or cur == "walking") and anim.has_animation("g/" + ("run_to_stop" if cur == "running" else "walk_to_stop")):
		_play("run_to_stop" if cur == "running" else "walk_to_stop", 1.0, 0.15)
	elif (cur == "run_to_stop" or cur == "walk_to_stop") and anim.is_playing():
		pass # 멈추는 동작 재생 중
	elif clap:
		_play("clapping", 1.0, 0.2)
	else:
		_play("idle", 1.0, 0.3)


## Mixamo 재질은 알파 0.8 + 깊이 선처리로 반투명하게 나옴 → 불투명으로, 속눈썹만 알파 컷아웃
func _fix_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
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
