extends Node3D
# 가까운 교차로에 신호등 기둥(3색 등)을 세우고 상태에 맞춰 불을 켠다.

const SHOW_R := 260.0
const HIDE_R := 340.0

var signals: RefCounted
var heads := {}         # 교차로 번호 -> [ {node, lamps, phase, state} ]
var timer := 0.0
var side := 1.0
var mats := {}
var pole_mat: StandardMaterial3D
var world: Node3D
var zebra_mat: StandardMaterial3D


func _init() -> void:
	zebra_mat = StandardMaterial3D.new()
	zebra_mat.albedo_color = Color(0.88, 0.88, 0.86)
	zebra_mat.roughness = 0.75
	zebra_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.15, 0.16, 0.17)
	pole_mat.metallic = 0.5
	pole_mat.roughness = 0.5
	var cols := {"r": Color(1.0, 0.1, 0.05), "y": Color(1.0, 0.7, 0.05), "g": Color(0.1, 1.0, 0.3)}
	for k in cols:
		var on := StandardMaterial3D.new()
		on.albedo_color = cols[k]
		on.emission_enabled = true
		on.emission = cols[k]
		on.emission_energy_multiplier = 3.0
		var off := StandardMaterial3D.new()
		off.albedo_color = cols[k] * 0.18
		off.roughness = 0.4
		mats[k + "_on"] = on
		mats[k + "_off"] = off


func clear() -> void:
	for ci in heads:
		for h in heads[ci]:
			h.node.queue_free()
	heads.clear()


func update(dt: float, focus: Vector3, night: float, side_: float) -> void:
	if signals == null:
		return
	side = side_
	timer -= dt
	if timer > 0.0:
		return
	timer = 0.25
	for k in ["r", "y", "g"]:
		(mats[k + "_on"] as StandardMaterial3D).emission_energy_multiplier = 2.5 + 3.0 * night
	for ci in heads.keys():
		if not signals.clusters.has(ci):
			for h in heads[ci]:
				h.node.queue_free()
			heads.erase(ci)
	for ci in signals.clusters.keys():
		var c: Dictionary = signals.clusters[ci]
		var d := Vector2(c.center.x - focus.x, c.center.z - focus.z).length()
		if d < SHOW_R and not heads.has(ci):
			_build(ci)
		elif d > HIDE_R and heads.has(ci):
			for h in heads[ci]:
				h.node.queue_free()
			heads.erase(ci)
	for ci in heads:
		for h in heads[ci]:
			if h.phase < 0:
				continue # 횡단보도 메시
			var st: int = signals.phase_state(ci, h.phase)
			if st != h.state:
				h.state = st
				h.lamps[0].material_override = mats["r_on"] if st == 2 else mats["r_off"]
				h.lamps[1].material_override = mats["y_on"] if st == 1 else mats["y_off"]
				h.lamps[2].material_override = mats["g_on"] if st == 0 else mats["g_off"]


func _build(ci: int) -> void:
	var c: Dictionary = signals.clusters[ci]
	var list: Array = []
	for a in c.arms:
		var d: Vector2 = a.d                     # 교차로에서 바깥으로 향하는 방향
		var travel := -d                        # 이 팔에서 들어오는 차의 진행 방향
		var right := Vector2(-travel.y, travel.x) * side
		var off: float = float(a.w) * 0.5 + 1.0
		var pos := Vector2(c.center.x, c.center.z) + d * 8.0 + right * off
		var root := Node3D.new()
		root.position = Vector3(pos.x, c.center.y, pos.y)
		root.rotation.y = atan2(-travel.x, -travel.y) + PI # +Z 가 들어오는 차를 향하게
		add_child(root)
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.09
		cm.height = 5.4
		cm.radial_segments = 6
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position = Vector3(0, 2.7, 0)
		root.add_child(pole)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.36, 1.05, 0.3)
		box.mesh = bm
		box.material_override = pole_mat
		box.position = Vector3(0, 5.2, 0.05)
		root.add_child(box)
		var lamps: Array = []
		for i in 3:
			var l := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.18
			sm.radial_segments = 8
			sm.rings = 4
			l.mesh = sm
			l.position = Vector3(0, 5.45 - 0.3 * i, 0.2)
			l.material_override = mats["r_off"]
			root.add_child(l)
			lamps.append(l)
		var pl: Array = []
		for sx in [-1.0, 1.0]:
			var pb := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = Vector3(0.1, 0.34, 0.24)
			pb.mesh = pbm
			pb.material_override = pole_mat
			pb.position = Vector3(sx * 0.11, 2.7, 0)
			root.add_child(pb)
			var pq := MeshInstance3D.new()
			var psm := SphereMesh.new()
			psm.radius = 0.09
			psm.height = 0.12
			psm.radial_segments = 8
			psm.rings = 4
			pq.mesh = psm
			pq.position = Vector3(sx * 0.17, 2.7, 0)
			pq.material_override = mats["r_off"]
			root.add_child(pq)
			pl.append(pq)
		list.append({"node": root, "lamps": lamps, "plamps": pl, "phase": a.phase, "state": -1})
	list.append(_zebra(c))
	heads[ci] = list


func _quad(st: SurfaceTool, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> void:
	st.set_normal(Vector3.UP)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.add_vertex(Vector3(p.x, world.height_at(Vector3(p.x, 0, p.y)) + 0.27, p.y))


## 각 팔의 교차로 입구에 횡단보도(얼룩말)와 정지선
func _zebra(c: Dictionary) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in c.arms:
		var d: Vector2 = a.d
		var n := Vector2(-d.y, d.x)
		var base := Vector2(a.base.x, a.base.z)
		var w: float = a.w
		var mid := base + d * 1.5
		var s := -w * 0.5 + 0.35
		while s < w * 0.5 - 0.4:
			var c0 := mid + n * s
			_quad(st, c0 - d * 1.2, c0 + d * 1.2, c0 + d * 1.2 + n * 0.45, c0 - d * 1.2 + n * 0.45)
			s += 0.95
		# 정지선: 들어오는 차선(오른쪽) 쪽 절반
		var travel := -d
		var right := Vector2(-travel.y, travel.x) * side
		var sl := base + d * 5.0
		_quad(st, sl + right * 0.2 - d * 0.2, sl + right * (w * 0.5 - 0.3) - d * 0.2, sl + right * (w * 0.5 - 0.3) + d * 0.2, sl + right * 0.2 + d * 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = zebra_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return {"node": mi, "lamps": [], "phase": -1, "state": -2}
