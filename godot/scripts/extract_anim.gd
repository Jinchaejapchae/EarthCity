extends SceneTree
# 사용: godot --headless --path godot --script res://scripts/extract_anim.gd
# assets/people/src/*.fbx 의 애니메이션만 anim_<이름>.res 로 저장하고 이동량을 출력
func _init():
	var d := DirAccess.open("res://assets/people/src")
	for f in d.get_files():
		if not f.ends_with(".fbx"):
			continue
		var nm := f.get_basename()
		var n := (load("res://assets/people/src/" + f) as PackedScene).instantiate()
		var ap := n.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var an: Animation = null
		for a in ap.get_animation_list():
			if a != "Take 001" and a != "RESET":
				an = ap.get_animation(a)
		if an == null:
			an = ap.get_animation(ap.get_animation_list()[0])
		an = an.duplicate()
		var info := ""
		for t in an.get_track_count():
			if str(an.track_get_path(t)).ends_with("Hips") and an.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var a0: Vector3 = an.position_track_interpolate(t, 0.0)
				var a1: Vector3 = an.position_track_interpolate(t, an.length)
				info = " travel_z=%.3f m (%.3f m/s)" % [a1.z - a0.z, (a1.z - a0.z) / an.length]
		# 루트 모션 제거: Hips 의 x,z 이동을 첫 값으로 고정(높이 y 는 유지). 이동은 게임 쪽 속도가 담당
		for t in an.get_track_count():
			if str(an.track_get_path(t)).ends_with("Hips") and an.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var first: Vector3 = an.track_get_key_value(t, 0)
				for i in an.track_get_key_count(t):
					var v: Vector3 = an.track_get_key_value(t, i)
					an.track_set_key_value(t, i, Vector3(first.x, v.y, first.z))
		if nm in ["idle", "walking", "drunk_walk", "running", "clapping"]:
			an.loop_mode = Animation.LOOP_LINEAR
		ResourceSaver.save(an, "res://assets/people/anim_%s.res" % nm)
		print("ANIM ", nm, " len=", snappedf(an.length, 0.01), " tracks=", an.get_track_count(), info)
	quit()
