extends RefCounted
# 세계 유명 건축물을 코드로 만든 단순 모델로 실제 위치에 세운다(지도 데이터에는 모양 정보가 없어 상자로 나오기 때문).
# 항목: [이름, 위도, 경도, 종류, 방향(도, 시계방향), 크기 배율]

const LIST := [
	["에펠탑", 48.8584, 2.2945, "eiffel", 0.0, 1.0],
	["도쿄타워", 35.6586, 139.7454, "tokyo", 0.0, 1.0],
	["쿠푸 피라미드", 29.9792, 31.1342, "pyramid_big", 0.0, 1.0],
	["카프레 피라미드", 29.9753, 31.1308, "pyramid_mid", 0.0, 1.0],
	["멘카우레 피라미드", 29.9722, 31.1283, "pyramid_small", 0.0, 1.0],
	["빅벤", 51.5007, -0.1246, "clock", 0.0, 1.0],
	["시드니 오페라 하우스", -33.8568, 151.2153, "opera", 20.0, 1.0],
	["타지마할", 27.1751, 78.0421, "taj", 0.0, 1.0],
	["아야 소피아", 41.0086, 28.9800, "hagia", 40.0, 1.0],
	["성 베드로 대성당", 41.9022, 12.4539, "dome", 0.0, 1.0],
	["콜로세움", 41.8902, 12.4922, "colosseum", -30.0, 1.0],
	["스페이스 니들", 47.6205, -122.3493, "needle_space", 0.0, 1.0],
	["CN 타워", 43.6426, -79.3871, "needle_cn", 0.0, 1.0],
	["베를린 TV 타워", 52.5208, 13.4094, "needle_berlin", 0.0, 1.0],
	["동방명주", 31.2397, 121.4998, "pearl", 0.0, 1.0],
	["개선문", 48.8738, 2.2950, "arc", 0.0, 1.0],
	["브란덴부르크 문", 52.5163, 13.3777, "gate", 0.0, 1.0],
	["게이트웨이 아치", 38.6247, -90.1848, "gateway", 0.0, 1.0],
	["성 바실리 대성당", 55.7525, 37.6231, "basil", 0.0, 1.0],
	["피사의 사탑", 43.7230, 10.3966, "pisa", 0.0, 1.0],
	["자유의 여신상", 40.6892, -74.0445, "liberty", 0.0, 1.0],
	["구세주 그리스도상", -22.9519, -43.2105, "christ", 0.0, 1.0],
	["파르테논 신전", 37.9715, 23.7267, "parthenon", 0.0, 1.0],
	["사그라다 파밀리아", 41.4036, 2.1744, "sagrada", 0.0, 1.0],
	["미국 국회의사당", 38.8899, -77.0091, "capitol", 0.0, 1.0],
	["타워 브리지", 51.5055, -0.0754, "towerbridge", 0.0, 1.0],
]

const RADIUS := {
	"eiffel": 90.0, "tokyo": 45.0, "pyramid_big": 130.0, "pyramid_mid": 120.0, "pyramid_small": 70.0, "clock": 40.0,
	"opera": 110.0, "taj": 70.0, "hagia": 60.0, "dome": 100.0, "colosseum": 110.0, "needle_space": 35.0, "needle_cn": 40.0,
	"needle_berlin": 40.0, "pearl": 40.0, "arc": 40.0, "gate": 40.0, "gateway": 30.0, "basil": 40.0, "pisa": 25.0,
	"liberty": 30.0, "christ": 15.0, "parthenon": 55.0, "sagrada": 60.0, "capitol": 80.0, "towerbridge": 45.0,
}
var parts := {}   # 색 html -> SurfaceTool


func _st(col: Color) -> SurfaceTool:
	var k := col.to_html()
	if not parts.has(k):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[k] = s
	return parts[k]


func _add(col: Color, mesh: Mesh, xf: Transform3D) -> void:
	_st(col).append_from(mesh, 0, xf)


func _box(col: Color, c: Vector3, size: Vector3, rot_y := 0.0) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(col, m, Transform3D(Basis(Vector3.UP, rot_y), c))


func _cyl(col: Color, base: Vector3, r_top: float, r_bot: float, h: float, seg := 12) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_add(col, m, Transform3D(Basis.IDENTITY, base + Vector3(0, h * 0.5, 0)))


func _sphere(col: Color, c: Vector3, r: float, sy := 1.0, seg := 14) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = seg / 2
	_add(col, m, Transform3D(Basis.from_scale(Vector3(1, sy, 1)), c))


## 두 점을 잇는 각진 막대(트러스/다리/기둥)
func _beam(col: Color, a: Vector3, b: Vector3, t: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return
	var y := d / L
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var m := BoxMesh.new()
	m.size = Vector3(t, L, t)
	_add(col, m, Transform3D(Basis(x, y, z), (a + b) * 0.5))


func _lattice(col: Color, h: float, base: float, levels: Array, top_w: float) -> void:
	# 다리 4개: 아래에서 위로 가늘어지는 곡선, 층마다 가로 막대와 X 보강재
	var ys := [0.0]
	for l in levels:
		ys.append(float(l) * h)
	ys.append(h * 0.86)
	var prev: Array = []
	for yi in ys.size():
		var f: float = ys[yi] / (h * 0.86)
		var w := lerpf(base, top_w, pow(f, 0.55))
		var ring := [Vector3(w, ys[yi], w), Vector3(-w, ys[yi], w), Vector3(-w, ys[yi], -w), Vector3(w, ys[yi], -w)]
		if prev.size() > 0:
			for i in 4:
				_beam(col, prev[i], ring[i], maxf(1.2, 3.5 * (1.0 - f)))
			for i in 4:
				_beam(col, prev[i], ring[(i + 1) % 4], 0.8)
				_beam(col, ring[i], ring[(i + 1) % 4], 1.0)
		var plat := Vector3(w * 2.15, maxf(1.5, 4.0 * (1.0 - f) + 1.5), w * 2.15)
		if yi > 0 and yi < ys.size() - 1:
			_box(col, Vector3(0, ys[yi], 0), plat)
		prev = ring
	var tw := top_w
	_cyl(col, Vector3(0, h * 0.86, 0), 0.6, tw * 0.9, h * 0.14, 8)


func _needle(col: Color, h: float, shaft_r: float, pods: Array, spire: float, pod_col: Color) -> void:
	_cyl(col, Vector3.ZERO, shaft_r * 0.55, shaft_r, h - spire, 12)
	for p in pods:
		_sphere(pod_col, Vector3(0, float(p[0]), 0), float(p[1]), float(p[2]) if p.size() > 2 else 0.5)
	_cyl(col, Vector3(0, h - spire, 0), 0.3, shaft_r * 0.4, spire, 6)


func _dome_building(wall: Color, dome: Color, w: float, d: float, h: float, dome_r: float, minarets := 0, ming := 30.0) -> void:
	_box(wall, Vector3(0, h * 0.5, 0), Vector3(w, h, d))
	_sphere(dome, Vector3(0, h, 0), dome_r, 0.9, 18)
	for i in minarets:
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sz := 1.0 if i < 2 else -1.0
		var p := Vector3(sx * (w * 0.5 + 6.0), 0, sz * (d * 0.5 + 6.0))
		_cyl(wall.lightened(0.1), p, 1.6, 2.4, ming, 8)
		_cyl(dome, p + Vector3(0, ming, 0), 0.0, 2.2, 5.0, 8)


## 종류별 메시를 만든다. 반환: {mesh, solid(충돌 상자 크기 or null)}
func build(kind: String, scale: float) -> Dictionary:
	parts.clear()
	var stone := Color(0.78, 0.7, 0.55)
	var white := Color(0.93, 0.92, 0.88)
	var solid := Vector3.ZERO
	match kind:
		"eiffel":
			_lattice(Color(0.42, 0.34, 0.28), 324.0, 62.0, [0.18, 0.36, 0.62], 6.0)
			solid = Vector3(40, 60, 40)
		"tokyo":
			_lattice(Color(0.9, 0.35, 0.1), 333.0, 40.0, [0.2, 0.4, 0.62], 4.0)
		"pyramid_big":
			_pyramid(stone, 230.0, 139.0)
			solid = Vector3(150, 130, 150)
		"pyramid_mid":
			_pyramid(stone, 215.0, 136.0)
			solid = Vector3(140, 125, 140)
		"pyramid_small":
			_pyramid(stone, 103.0, 65.0)
			solid = Vector3(70, 60, 70)
		"clock":
			_box(stone, Vector3(0, 40, 0), Vector3(12, 80, 12))
			_box(stone.darkened(0.15), Vector3(0, 84, 0), Vector3(15, 10, 15))
			_cyl(Color(0.25, 0.35, 0.3), Vector3(0, 89, 0), 0.0, 9.0, 18.0, 4)
			for s in [[0, 7.5], [1, -7.5]]:
				var q := QuadMesh.new()
				q.size = Vector2(8, 8)
				var rot := Basis(Vector3.UP, 0.0 if s[0] == 0 else PI)
				_add(Color(0.95, 0.95, 0.9), q, Transform3D(rot, Vector3(0, 84, s[1] * 1.01)))
				_add(Color(0.95, 0.95, 0.9), q, Transform3D(rot * Basis(Vector3.UP, PI * 0.5), Vector3(s[1] * 1.01, 84, 0)))
			_box(stone, Vector3(25, 12, 0), Vector3(50, 24, 14))
			solid = Vector3(14, 80, 14)
		"opera":
			_box(Color(0.75, 0.72, 0.68), Vector3(0, 2.0, 0), Vector3(120, 4, 185))
			for i in 4:
				var z := -70.0 + i * 38.0
				_sail(white, Vector3(-20, 4, z), 38.0 - i * 3.0, 28.0 - i * 3.0)
				_sail(white, Vector3(18, 4, z + 6.0), 34.0 - i * 3.0, 24.0 - i * 3.0)
		"taj":
			_box(white, Vector3(0, 3.5, 0), Vector3(100, 7, 100))
			_dome_building(white, white, 57, 57, 28, 17.0)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_cyl(white, Vector3(sx * 45, 7, sz * 45), 1.8, 2.6, 36.0, 10)
					_sphere(white, Vector3(sx * 45, 45, sz * 45), 2.6, 1.0, 8)
					_sphere(white, Vector3(sx * 22, 31, sz * 22), 5.0, 1.0, 10)
			solid = Vector3(60, 40, 60)
		"hagia":
			_dome_building(Color(0.75, 0.55, 0.4), Color(0.5, 0.5, 0.52), 70, 75, 30, 15.0, 4, 55.0)
			solid = Vector3(72, 40, 78)
		"dome":
			_box(stone, Vector3(0, 22, 0), Vector3(130, 44, 190))
			_cyl(stone, Vector3(0, 44, 0), 20.0, 24.0, 30.0, 20)
			_sphere(Color(0.6, 0.6, 0.58), Vector3(0, 74, 0), 21.0, 0.9, 20)
			_cyl(Color(0.8, 0.7, 0.2), Vector3(0, 93, 0), 0.0, 1.2, 12.0, 6)
			solid = Vector3(130, 70, 190)
		"colosseum":
			_ring(Color(0.74, 0.66, 0.52), 94.0, 78.0, 48.0, 6.0)
		"needle_space":
			_needle(Color(0.85, 0.87, 0.9), 184.0, 5.0, [[150, 22, 0.18], [141, 18, 0.12]], 30.0, Color(0.8, 0.82, 0.85))
		"needle_cn":
			_needle(Color(0.78, 0.78, 0.76), 553.0, 15.0, [[340, 22, 0.55], [330, 10, 0.4]], 100.0, Color(0.7, 0.72, 0.74))
		"needle_berlin":
			_needle(Color(0.8, 0.8, 0.8), 368.0, 8.0, [[207, 16, 1.0]], 110.0, Color(0.85, 0.85, 0.85))
		"pearl":
			_needle(Color(0.75, 0.78, 0.85), 468.0, 5.0, [[50, 25, 1.0], [280, 22, 1.0], [350, 10, 1.0]], 90.0, Color(0.85, 0.35, 0.45))
		"arc":
			_box(stone, Vector3(-16, 25, 0), Vector3(14, 50, 22))
			_box(stone, Vector3(16, 25, 0), Vector3(14, 50, 22))
			_box(stone, Vector3(0, 38, 0), Vector3(26, 24, 22))
			_box(stone.darkened(0.1), Vector3(0, 51, 0), Vector3(46, 4, 24))
			solid = Vector3(46, 40, 22)
		"gate":
			for i in 6:
				_cyl(stone, Vector3(-12.5 + i * 5.0, 0, 0), 1.5, 1.8, 15.0, 10)
				_cyl(stone, Vector3(-12.5 + i * 5.0, 0, -9.0), 1.5, 1.8, 15.0, 10)
			_box(stone, Vector3(0, 17.5, -4.5), Vector3(66.0 * 0.4, 5, 14))
			_box(stone, Vector3(0, 21.0, -4.5), Vector3(30, 2, 14))
		"gateway":
			var pts: Array = []
			for i in 25:
				var t := i / 24.0
				var x := (t - 0.5) * 2.0
				pts.append(Vector3(x * 96.0, 192.0 * (1.0 - x * x), 0))
			for i in 24:
				_beam(Color(0.82, 0.83, 0.85), pts[i], pts[i + 1], 8.0)
		"basil":
			_box(Color(0.7, 0.3, 0.25), Vector3(0, 14, 0), Vector3(40, 28, 40))
			_cyl(Color(0.75, 0.4, 0.3), Vector3(0, 28, 0), 7.0, 9.0, 32.0, 10)
			_cyl(Color(0.2, 0.55, 0.3), Vector3(0, 60, 0), 0.0, 8.0, 16.0, 10)
			var cols := [Color(0.85, 0.2, 0.2), Color(0.2, 0.6, 0.35), Color(0.95, 0.75, 0.15), Color(0.25, 0.45, 0.8)]
			for i in 8:
				var a := TAU * i / 8.0
				var p := Vector3(cos(a) * 18.0, 0, sin(a) * 18.0)
				_cyl(Color(0.75, 0.4, 0.3), p, 3.2, 3.6, 22.0, 8)
				_sphere(cols[i % 4], p + Vector3(0, 28, 0), 5.2, 1.4, 10)
			_sphere(Color(0.95, 0.75, 0.15), Vector3(0, 66, 0), 6.0, 1.5, 10)
			solid = Vector3(50, 40, 50)
		"pisa":
			var tilt := Basis(Vector3.FORWARD, deg_to_rad(4.0))
			for i in 8:
				var m := CylinderMesh.new()
				m.top_radius = 9.5
				m.bottom_radius = 9.5
				m.height = 6.6
				m.radial_segments = 16
				_add(white, m, Transform3D(tilt, tilt * Vector3(0, 3.3 + i * 6.8, 0)))
				var m2 := CylinderMesh.new()
				m2.top_radius = 10.5
				m2.bottom_radius = 10.5
				m2.height = 0.8
				m2.radial_segments = 16
				_add(white.darkened(0.15), m2, Transform3D(tilt, tilt * Vector3(0, 6.9 + i * 6.8, 0)))
			solid = Vector3(20, 50, 20)
		"liberty":
			_box(Color(0.7, 0.68, 0.62), Vector3(0, 23, 0), Vector3(30, 46, 30))
			var green := Color(0.4, 0.65, 0.58)
			_cyl(green, Vector3(0, 46, 0), 3.5, 7.0, 32.0, 10)
			_sphere(green, Vector3(0, 80, 0), 3.2, 1.0, 10)
			_beam(green, Vector3(3, 70, 0), Vector3(6, 90, 0), 2.4)
			_sphere(Color(0.95, 0.8, 0.2), Vector3(6, 93, 0), 2.0, 1.4, 8)
			for i in 7:
				var a := deg_to_rad(-60.0 + i * 20.0)
				_beam(green, Vector3(0, 82, 0), Vector3(sin(a) * 7.0, 82 + cos(a) * 6.0, 0), 0.8)
			solid = Vector3(30, 60, 30)
		"christ":
			_box(white.darkened(0.1), Vector3(0, 4, 0), Vector3(8, 8, 8))
			_cyl(white, Vector3(0, 8, 0), 1.6, 3.2, 22.0, 10)
			_sphere(white, Vector3(0, 32, 0), 1.9, 1.1, 10)
			_box(white, Vector3(0, 27, 0), Vector3(28, 2.4, 2.4))
			solid = Vector3(8, 20, 8)
		"parthenon":
			_box(stone.lightened(0.1), Vector3(0, 1.5, 0), Vector3(34, 3, 75))
			for i in 8:
				for z in [-1.0, 1.0]:
					_cyl(stone, Vector3(-14 + i * 4.0, 3, z * 33.0), 1.0, 1.1, 10.4, 10)
			for i in 17:
				for x in [-1.0, 1.0]:
					_cyl(stone, Vector3(x * 14.0, 3, -32 + i * 4.0), 1.0, 1.1, 10.4, 10)
			_box(stone, Vector3(0, 14.0, 0), Vector3(32, 1.8, 72))
			_cyl(stone.darkened(0.1), Vector3(0, 15, 0), 0.0, 20.0, 5.0, 4)
		"sagrada":
			for i in 8:
				var a := TAU * i / 8.0
				var hh := 90.0 + (i % 3) * 28.0
				var p := Vector3(cos(a) * 20.0, 0, sin(a) * 12.0)
				_cyl(Color(0.75, 0.65, 0.5), p, 2.2, 4.5, hh, 8)
				_cyl(Color(0.8, 0.7, 0.45), p + Vector3(0, hh, 0), 0.0, 3.2, 16.0, 8)
			_box(Color(0.75, 0.65, 0.5), Vector3(0, 15, 0), Vector3(30, 30, 90))
			_cyl(Color(0.8, 0.7, 0.45), Vector3(0, 30, 0), 0.0, 7.0, 55.0, 8)
			solid = Vector3(50, 40, 90)
		"capitol":
			_box(white, Vector3(0, 12, 0), Vector3(100, 24, 40))
			_cyl(white, Vector3(0, 24, 0), 14.0, 16.0, 18.0, 16)
			_sphere(white, Vector3(0, 44, 0), 15.0, 0.9, 18)
			_cyl(white, Vector3(0, 57, 0), 3.0, 4.5, 12.0, 10)
			solid = Vector3(100, 50, 40)
		"towerbridge":
			var blue := Color(0.3, 0.45, 0.65)
			for z in [-30.0, 30.0]:
				_box(stone.darkened(0.1), Vector3(0, 22, z), Vector3(18, 44, 16))
				_cyl(blue, Vector3(0, 44, z), 0.0, 11.0, 18.0, 4)
			_box(blue, Vector3(0, 40, 0), Vector3(6, 3, 60))
			_box(blue, Vector3(0, 8, 0), Vector3(12, 1.5, 62))
	var mesh := ArrayMesh.new()
	for k in parts:
		var st: SurfaceTool = parts[k]
		st.generate_normals()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.html(k)
		mat.roughness = 0.85
		st.set_material(mat)
		st.commit(mesh)
	return {"mesh": mesh, "solid": solid * scale}


func _pyramid(col: Color, base: float, h: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = base * 0.7071
	m.height = h
	m.radial_segments = 4
	m.rings = 1
	_add(col, m, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, h * 0.5, 0)))


func _sail(col: Color, base: Vector3, w: float, h: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = w * 0.6
	m.height = h
	m.radial_segments = 3
	m.rings = 1
	_add(col, m, Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-12.0)), base + Vector3(0, h * 0.5, 0)))


func _ring(col: Color, a: float, b: float, h: float, thick: float) -> void:
	var n := 56
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(t0) * a, 0, sin(t0) * b)
		var p1 := Vector3(cos(t1) * a, 0, sin(t1) * b)
		var mid := (p0 + p1) * 0.5
		var seg := (p1 - p0).length()
		var yaw := atan2(-(p1.z - p0.z), p1.x - p0.x)
		var m := BoxMesh.new()
		m.size = Vector3(seg * 1.02, h - (6.0 if i % 7 == 0 else 0.0), thick)
		_add(col, m, Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, m.size.y * 0.5, 0)))
