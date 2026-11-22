extends Node3D
# 실제 지도 월드: 플레이어 주변 z14 타일(3x3)을 스트리밍한다.
# 지형 = Terrarium(AWS) 고도, 도로/건물/물/토지 = OpenFreeMap 벡터 타일. 둘 다 무료/키 불필요.

const Z := 14
const GeoScript := preload("res://scripts/geo.gd")
const BuilderScript := preload("res://scripts/chunk_builder.gd")
const MatScript := preload("res://scripts/wmats.gd")
const NetScript := preload("res://scripts/roadnet.gd")
const TILEJSON := "https://tiles.openfreemap.org/planet"
const DEM_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"

signal center_ready

var geo := GeoScript.new()
var mats := MatScript.new()
var show_trees := true
var region := 0
var season := 1
var tree_trunk_mesh: ArrayMesh
var tree_broad_mesh: ArrayMesh
var tree_conifer_mesh: ArrayMesh
var lamp_mesh: ArrayMesh
var pool_mesh: QuadMesh
var net_roads := NetScript.new()   # 도로 그래프(교통/보행자 AI 용)
var net: Node
var tile_tpl := ""
var chunks := {}      # Vector2i -> {node, h, n, ts, cx, cz}
var loading := {}     # Vector2i -> true
var gen := 0          # 위치를 바꿀 때마다 증가(진행 중이던 로딩 폐기)
var center_done := false
var last_tile := Vector2i(-99999, -99999)
var radius := 1


## 나무 메시: 줄기 / 활엽수 잎(구 둘) / 침엽수 잎(원뿔 셋)
func _make_tree_meshes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.22
	cyl.height = 3.2
	cyl.radial_segments = 6
	cyl.rings = 1
	st.append_from(cyl, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)))
	st.set_material(mats.tree_trunk)
	tree_trunk_mesh = st.commit()
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 7
	sph.rings = 4
	sb.append_from(sph, 0, Transform3D(Basis.from_scale(Vector3(2.5, 2.1, 2.5)), Vector3(0, 4.4, 0)))
	sb.append_from(sph, 0, Transform3D(Basis.from_scale(Vector3(1.7, 1.5, 1.7)), Vector3(0.9, 5.4, 0.5)))
	sb.set_material(mats.tree_leaf)
	tree_broad_mesh = sb.commit()
	var sc := SurfaceTool.new()
	sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.9 - 0.45 * k
		cone.height = 2.8
		cone.radial_segments = 7
		cone.rings = 1
		sc.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, 3.0 + 1.9 * k, 0)))
	sc.set_material(mats.tree_leaf)
	tree_conifer_mesh = sc.commit()


func _season_of(la: float) -> int:
	if absf(la) < 23.0:
		return 4
	var m: int = Time.get_date_dict_from_system().month
	if la < 0.0:
		m = ((m - 1 + 6) % 12) + 1
	if m >= 3 and m <= 5:
		return 0
	if m >= 6 and m <= 8:
		return 1
	if m >= 9 and m <= 11:
		return 2
	return 3


func _make_lamp_meshes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.11
	cyl.height = 7.5
	cyl.radial_segments = 6
	cyl.rings = 1
	st.append_from(cyl, 0, Transform3D(Basis.IDENTITY, Vector3(0, 3.75, 0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.1, 0.1, 2.3)
	st.append_from(arm, 0, Transform3D(Basis.IDENTITY, Vector3(0, 7.5, 1.05)))
	var head := BoxMesh.new()
	head.size = Vector3(0.45, 0.14, 0.9)
	st.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0, 7.5, 2.1)))
	st.set_material(mats.lamp_metal)
	lamp_mesh = st.commit()
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bulb := BoxMesh.new()
	bulb.size = Vector3(0.36, 0.04, 0.7)
	sb.append_from(bulb, 0, Transform3D(Basis.IDENTITY, Vector3(0, 7.42, 2.1)))
	sb.set_material(mats.lamp_bulb)
	sb.commit(lamp_mesh)
	pool_mesh = QuadMesh.new()
	pool_mesh.size = Vector2(17, 17)
	pool_mesh.material = mats.lamp_pool


func _ready() -> void:
	_make_lamp_meshes()
	_make_tree_meshes()
	net = preload("res://scripts/net.gd").new()
	add_child(net)


## 새 위치로 이동(원점 재설정)
func teleport(lat: float, lon: float) -> void:
	gen += 1
	for key in chunks:
		chunks[key].node.queue_free()
	chunks.clear()
	net_roads = NetScript.new()
	loading.clear()
	center_done = false
	last_tile = Vector2i(-99999, -99999)
	geo.set_origin(lat, lon)
	region = MatScript.region_of(lat, lon)
	season = _season_of(lat)
	if tile_tpl == "":
		var tj: PackedByteArray = await net.fetch(TILEJSON, false)
		var j = JSON.parse_string(tj.get_string_from_utf8())
		if j is Dictionary and j.has("tiles"):
			tile_tpl = str(j["tiles"][0])
	update(Vector3.ZERO)


func update(p: Vector3) -> void:
	if tile_tpl == "":
		return
	_tree_colliders(p)
	var t := geo.tile_of_local(p, Z)
	if t == last_tile:
		return
	last_tile = t
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var key := Vector2i(t.x + dx, t.y + dy)
			if not chunks.has(key) and not loading.has(key):
				_load(key, gen)
	for key in chunks.keys():
		if absi(key.x - t.x) > radius + 1 or absi(key.y - t.y) > radius + 1:
			chunks[key].node.queue_free()
			net_roads.remove_chunk(key)
			chunks.erase(key)


var tree_body: StaticBody3D
var tree_shapes: Array = []
var tree_timer := 0.0
const TREE_POOL := 48


## 플레이어 주변 나무에만 원기둥 충돌체를 붙임(풀 재사용; 0.4초마다 갱신)
func _tree_colliders(p: Vector3) -> void:
	tree_timer -= get_process_delta_time()
	if tree_timer > 0.0:
		return
	tree_timer = 0.4
	if tree_body == null:
		tree_body = StaticBody3D.new()
		tree_body.collision_layer = 1
		add_child(tree_body)
		for i in TREE_POOL:
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.35
			cy.height = 4.0
			cs.shape = cy
			cs.disabled = true
			tree_body.add_child(cs)
			tree_shapes.append(cs)
	var used := 0
	if show_trees:
		var key := geo.tile_of_local(p, Z)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := Vector2i(key.x + dx, key.y + dy)
				if not chunks.has(k):
					continue
				var ch: Dictionary = chunks[k]
				var tp: PackedVector3Array = ch.tp
				var tsz: PackedFloat32Array = ch.ts_
				var off: Vector3 = ch.node.position
				for i in tp.size():
					var wp := tp[i] + off
					if absf(wp.x - p.x) > 12.0 or absf(wp.z - p.z) > 12.0:
						continue
					if used >= TREE_POOL:
						break
					var cs: CollisionShape3D = tree_shapes[used]
					cs.global_position = wp + Vector3(0, 2.0, 0)
					(cs.shape as CylinderShape3D).radius = 0.3 * tsz[i] + 0.1
					cs.disabled = false
					used += 1
	for i in range(used, TREE_POOL):
		tree_shapes[i].disabled = true


## p(월드 로컬)가 건물 안이면 true (margin: 건물 바깥 여유 거리 m)
func inside_building(p: Vector3, margin := 0.0) -> bool:
	var key := geo.tile_of_local(p, Z)
	if not chunks.has(key):
		return false
	var c: Dictionary = chunks[key]
	var q := Vector2(p.x - c.cx, p.z - c.cz)
	for poly in c.bp:
		var pts: PackedVector2Array = poly
		if margin > 0.0:
			var mn := pts[0]
			var mx := pts[0]
			for v in pts:
				mn = mn.min(v)
				mx = mx.max(v)
			if q.x < mn.x - margin or q.x > mx.x + margin or q.y < mn.y - margin or q.y > mx.y + margin:
				continue
			for v in pts:
				if v.distance_to(q) < margin:
					return true
		if Geometry2D.is_point_in_polygon(q, pts):
			return true
	return false


func height_at(p: Vector3) -> float:
	var key := geo.tile_of_local(p, Z)
	if not chunks.has(key):
		return 0.0
	var c: Dictionary = chunks[key]
	var n: int = c.n
	var W := n + 1
	var H: PackedFloat32Array = c.h
	var ts: float = c.ts
	var fi := clampf(((p.x - c.cx) / ts + 0.5) * n, 0.0, float(n) - 0.0001)
	var fj := clampf(((p.z - c.cz) / ts + 0.5) * n, 0.0, float(n) - 0.0001)
	var i := int(fi)
	var j := int(fj)
	var tx := fi - i
	var tz := fj - j
	var h00 := H[j * W + i]
	var h10 := H[j * W + i + 1]
	var h01 := H[(j + 1) * W + i]
	var h11 := H[(j + 1) * W + i + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func _load(key: Vector2i, g: int) -> void:
	loading[key] = true
	var vec: PackedByteArray = await net.fetch(tile_tpl.replace("{z}", str(Z)).replace("{x}", str(key.x)).replace("{y}", str(key.y)))
	var dem: PackedByteArray = await net.fetch(DEM_URL % [Z, key.x, key.y])
	if g != gen:
		return
	var th := Thread.new()
	var k := geo.k
	var rg := region
	var sn := season
	var la := geo.lat0
	th.start(func(): return BuilderScript.new().build(key.x, key.y, vec, dem, k, rg, sn, la))
	while th.is_alive():
		await get_tree().process_frame
	var data: Dictionary = th.wait_to_finish()
	if g != gen:
		return
	loading.erase(key)
	_instantiate(key, data)


func _mesh(g: Dictionary) -> ArrayMesh:
	if g.v.size() == 0 or g.i.size() == 0:
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_TEX_UV] = g.u
	if g.has("c") and g.c.size() == g.v.size():
		arr[Mesh.ARRAY_COLOR] = g.c
	arr[Mesh.ARRAY_INDEX] = g.i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _add_mesh(parent: Node3D, g: Dictionary, mat: Material, shadow := true) -> void:
	var m := _mesh(g)
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_trees(root: Node3D, d: Dictionary) -> void:
	var tp: PackedVector3Array = d["tree_p"]
	if tp.size() == 0:
		return
	var ty: PackedFloat32Array = d["tree_y"]
	var ts: PackedFloat32Array = d["tree_s"]
	var tk: PackedInt32Array = d["tree_k"]
	var tc: PackedColorArray = d["tree_c"]
	var tcs: PackedFloat32Array = d["tree_cs"]
	var n0 := 0
	var n1 := 0
	for k in tk:
		if k == 0:
			n0 += 1
		else:
			n1 += 1
	var trunk := MultiMesh.new()
	trunk.transform_format = MultiMesh.TRANSFORM_3D
	trunk.mesh = tree_trunk_mesh
	trunk.instance_count = tp.size()
	var broad := MultiMesh.new()
	broad.transform_format = MultiMesh.TRANSFORM_3D
	broad.use_colors = true
	broad.mesh = tree_broad_mesh
	broad.instance_count = n0
	var con := MultiMesh.new()
	con.transform_format = MultiMesh.TRANSFORM_3D
	con.use_colors = true
	con.mesh = tree_conifer_mesh
	con.instance_count = n1
	var i0 := 0
	var i1 := 0
	for i in tp.size():
		var bs := Basis(Vector3.UP, ty[i]).scaled(Vector3.ONE * ts[i])
		trunk.set_instance_transform(i, Transform3D(bs, tp[i]))
		if tk[i] == 0:
			var cb := Basis(Vector3.UP, ty[i]).scaled(Vector3.ONE * ts[i] * tcs[i])
			var cp := tp[i] + Vector3(0, (1.0 - tcs[i]) * ts[i] * 1.5, 0)
			broad.set_instance_transform(i0, Transform3D(cb, cp))
			broad.set_instance_color(i0, tc[i])
			i0 += 1
		else:
			con.set_instance_transform(i1, Transform3D(bs, tp[i]))
			con.set_instance_color(i1, tc[i])
			i1 += 1
	for mm in [trunk, broad, con]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 650.0
		mi.visible = show_trees
		mi.add_to_group("trees")
		root.add_child(mi)


func _instantiate(key: Vector2i, d: Dictionary) -> void:
	var c := geo.tile_center(Z, key.x, key.y)
	var root := Node3D.new()
	root.position = c
	add_child(root)
	# 지형
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d["t_v"]
	arr[Mesh.ARRAY_NORMAL] = d["t_n"]
	arr[Mesh.ARRAY_COLOR] = d["t_c"]
	arr[Mesh.ARRAY_TEX_UV] = d["t_u"]
	arr[Mesh.ARRAY_INDEX] = d["t_i"]
	var tm := ArrayMesh.new()
	tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm
	tmi.material_override = mats.terrain
	root.add_child(tmi)
	# 지형 충돌(높이맵)
	var n: int = d["n"]
	var ts: float = d["ts"]
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var hs := HeightMapShape3D.new()
	hs.map_width = n + 1
	hs.map_depth = n + 1
	hs.map_data = d["H"]
	var cs := CollisionShape3D.new()
	cs.shape = hs
	cs.scale = Vector3(ts / n, 1.0, ts / n)
	body.add_child(cs)
	root.add_child(body)
	# 가로등 + 빛 무리 (MultiMesh)
	var lp: PackedVector3Array = d["lamp_p"]
	var ly: PackedFloat32Array = d["lamp_y"]
	if lp.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lamp_mesh
		mm.instance_count = lp.size()
		var mp := MultiMesh.new()
		mp.transform_format = MultiMesh.TRANSFORM_3D
		mp.mesh = pool_mesh
		mp.instance_count = lp.size()
		for i in lp.size():
			var bs := Basis(Vector3.UP, ly[i])
			mm.set_instance_transform(i, Transform3D(bs, lp[i]))
			var pp := lp[i] + bs * Vector3(0, 0, 3.2)
			pp.y = lp[i].y + 0.35
			mp.set_instance_transform(i, Transform3D(bs * Basis(Vector3.RIGHT, -PI / 2.0), pp))
		var lmi := MultiMeshInstance3D.new()
		lmi.multimesh = mm
		root.add_child(lmi)
		var pmi := MultiMeshInstance3D.new()
		pmi.multimesh = mp
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pmi)
	# 물, 도로, 건물
	_add_mesh(root, d["water"], mats.water, false)
	_add_mesh(root, d["r_major"], mats.road_major, false)
	_add_mesh(root, d["r_minor"], mats.road_minor, false)
	_add_mesh(root, d["r_path"], mats.road_path, false)
	for m in 6:
		_add_mesh(root, d["b_%d" % m], mats.facade_mat(region, m))
	for m in 3:
		_add_mesh(root, d["s_%d" % m], mats.shop_mats[m])
	_add_trees(root, d)
	_add_mesh(root, d["b_roof"], mats.roof)
	var faces: PackedVector3Array = d["b_faces"]
	if faces.size() >= 3:
		var bb := StaticBody3D.new()
		bb.collision_layer = 1
		var bs := ConcavePolygonShape3D.new()
		bs.set_faces(faces)
		var bcs := CollisionShape3D.new()
		bcs.shape = bs
		bb.add_child(bcs)
		root.add_child(bb)
	net_roads.add_chunk(key, d["net"], c)
	chunks[key] = {"bp": d["bpolys"], "node": root, "h": d["H"], "n": n, "ts": ts, "cx": c.x, "cz": c.z, "tp": d["tree_p"], "ts_": d["tree_s"]}
	if not center_done and chunks.has(geo.tile_of_local(Vector3.ZERO, Z)):
		center_done = true
		center_ready.emit()
