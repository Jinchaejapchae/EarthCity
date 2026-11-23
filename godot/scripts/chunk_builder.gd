extends RefCounted
# z14 타일 하나의 지형/물/도로/건물 메시 데이터를 만든다. 스레드에서 돌리므로 씬 노드는 건드리지 않는다.
# 좌표는 청크 로컬(원점 = 타일 중심, +x 동, +z 남).

const MvtScript := preload("res://scripts/mvt.gd")
const Z := 14
const N := 128
const W := N + 1

var ts := 2000.0
var ext := 4096.0
var H := PackedFloat32Array()
var vcol := PackedColorArray()
var wmask := PackedByteArray()
var water_polys: Array = []
var net_lines: Array = []
var bpolys: Array = []


func lp(p: Vector2) -> Vector2:
	return Vector2((p.x / ext - 0.5) * ts, (p.y / ext - 0.5) * ts)


func hgt(x: float, z: float) -> float:
	var fi := clampf((x / ts + 0.5) * N, 0.0, float(N) - 0.0001)
	var fj := clampf((z / ts + 0.5) * N, 0.0, float(N) - 0.0001)
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


# a,b,c 삼각형을 n 방향이 앞면이 되도록(시계방향=앞면) 감아서 추가
func _tri(idx: PackedInt32Array, V: PackedVector3Array, a: int, b: int, c: int, n: Vector3) -> void:
	var cn := (V[c] - V[a]).cross(V[b] - V[a])
	if cn.dot(n) >= 0.0:
		idx.append_array([a, b, c])
	else:
		idx.append_array([a, c, b])


func _grp() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "u": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}


func build(tx: int, ty: int, vec: PackedByteArray, dem: PackedByteArray, k: float, region_: int, season_: int, lat_: float, biome_: int = 0, skip_: Array = []) -> Dictionary:
	region = region_
	biome = biome_
	skip = skip_
	season = season_
	lat = lat_
	rng.seed = tx * 7919 + ty * 104729 + 13
	ts = 40075016.686 / pow(2.0, Z) * k
	_load_dem(dem)
	var layers: Dictionary = {}
	if vec.size() > 0:
		layers = MvtScript.new().decode(vec, ["landcover", "landuse", "park", "water", "transportation", "building"])
	var out := {"n": N, "ts": ts}
	_paint(layers)
	_water(layers, out)
	_terrain(out)
	_roads(layers, out)
	_buildings(layers, out, tx, ty)
	_trees(layers, out)
	out["H"] = H
	return out


# ---------------------------------------------------------------- 고도
func _load_dem(dem: PackedByteArray) -> void:
	H.resize(W * W)
	H.fill(0.0)
	if dem.size() == 0:
		return
	var img := Image.new()
	if img.load_png_from_buffer(dem) != OK:
		return
	img.convert(Image.FORMAT_RGB8)
	var d := img.get_data()
	var w := img.get_width()
	var px := PackedFloat32Array()
	px.resize(w * w)
	for p in w * w:
		px[p] = d[p * 3] * 256.0 + d[p * 3 + 1] + d[p * 3 + 2] / 256.0 - 32768.0
	var sc := float(w - 1) / N
	for j in W:
		var fy := j * sc
		var y0 := int(fy)
		var y1 := mini(y0 + 1, w - 1)
		var ty_ := fy - y0
		for i in W:
			var fx := i * sc
			var x0 := int(fx)
			var x1 := mini(x0 + 1, w - 1)
			var tx_ := fx - x0
			var a := px[y0 * w + x0] * (1.0 - tx_) + px[y0 * w + x1] * tx_
			var b := px[y1 * w + x0] * (1.0 - tx_) + px[y1 * w + x1] * tx_
			H[j * W + i] = a * (1.0 - ty_) + b * ty_


# ---------------------------------------------------------------- 지표 색 / 물
func _land_color(layer: String, props: Dictionary) -> Color:
	var c: String = str(props.get("class", ""))
	if layer == "landcover":
		match c:
			"grass": return ST.GRASS[biome]
			"wood", "forest": return ST.WOOD[biome]
			"farmland": return ST.FARM[biome]
			"sand", "beach": return Color(0.78, 0.7, 0.5)
			"rock": return Color(0.45, 0.42, 0.38)
			"ice": return Color(0.9, 0.93, 0.95)
			"wetland": return Color(0.25, 0.38, 0.25)
	elif layer == "landuse":
		match c:
			"residential", "suburb", "neighbourhood": return Color(0.4, 0.4, 0.38)
			"commercial", "retail", "industrial", "railway": return Color(0.36, 0.36, 0.36)
			"cemetery", "playground", "pitch", "stadium", "track": return ST.PARK[biome]
			"school", "university", "college", "hospital": return Color(0.42, 0.42, 0.38)
	elif layer == "park":
		return ST.PARK[biome]
	return Color(0, 0, 0, 0)


func _local_poly(p: Dictionary) -> Dictionary:
	var o := PackedVector2Array()
	for q in p.o:
		o.append(lp(q))
	var hs: Array = []
	for hr in p.h:
		var h := PackedVector2Array()
		for q in hr:
			h.append(lp(q))
		hs.append(h)
	return {"o": o, "h": hs}


func _fill(poly: Dictionary, c: Color, water: bool) -> void:
	var o: PackedVector2Array = poly.o
	if o.size() < 3:
		return
	var mn := o[0]
	var mx := o[0]
	for q in o:
		mn = mn.min(q)
		mx = mx.max(q)
	var i0 := clampi(int(floor((mn.x / ts + 0.5) * N)), 0, N)
	var i1 := clampi(int(ceil((mx.x / ts + 0.5) * N)), 0, N)
	var j0 := clampi(int(floor((mn.y / ts + 0.5) * N)), 0, N)
	var j1 := clampi(int(ceil((mx.y / ts + 0.5) * N)), 0, N)
	for j in range(j0, j1 + 1):
		var z := (float(j) / N - 0.5) * ts
		for i in range(i0, i1 + 1):
			var p := Vector2((float(i) / N - 0.5) * ts, z)
			if not Geometry2D.is_point_in_polygon(p, o):
				continue
			var hole := false
			for hr in poly.h:
				if Geometry2D.is_point_in_polygon(p, hr):
					hole = true
					break
			if hole:
				continue
			if water:
				wmask[j * W + i] = 1
			else:
				vcol[j * W + i] = c


func _paint(layers: Dictionary) -> void:
	vcol.resize(W * W)
	vcol.fill(ST.GROUND[biome])
	wmask.resize(W * W)
	wmask.fill(0)
	for lname in ["landcover", "landuse", "park"]:
		if not layers.has(lname):
			continue
		ext = float(layers[lname].extent)
		for f in layers[lname].features:
			if f.type != 3 or not f.has("polys"):
				continue
			var c := _land_color(lname, f.props)
			if c.a == 0.0:
				continue
			for p in f.polys:
				_fill(_local_poly(p), c, false)


func _water(layers: Dictionary, out: Dictionary) -> void:
	var g := _grp()
	water_polys.clear()
	if layers.has("water"):
		ext = float(layers.water.extent)
		for f in layers.water.features:
			if f.type != 3 or not f.has("polys"):
				continue
			for p in f.polys:
				var lpoly := _local_poly(p)
				_fill(lpoly, Color.BLACK, true)
				water_polys.append(lpoly)
	# 수면 높이 = 물 윤곽 꼭짓점 지형 높이의 중앙값(탄소 전 원본 지형 기준)
	for lpoly in water_polys:
		var o: PackedVector2Array = lpoly.o
		# 타일 경계에 걸친 점(육지를 가로지르는 잘린 선)은 빼고, 안쪽 윤곽(= 물가) 높이의 낮은 쪽을 수면으로
		var hs: Array = []
		var lim := ts * 0.5 - 2.0
		var allp: Array = []
		for i in range(0, o.size(), maxi(1, o.size() / 40)):
			var hv := hgt(o[i].x, o[i].y)
			allp.append(hv)
			if absf(o[i].x) < lim and absf(o[i].y) < lim:
				hs.append(hv)
		if hs.is_empty():
			hs = allp
		hs.sort()
		var y: float = hs[int(hs.size() * 0.25)] if hs.size() > 0 else 0.0
		var tri := Geometry2D.triangulate_polygon(o)
		if tri.size() < 3:
			continue
		var base: int = g.v.size()
		for q in o:
			g.v.append(Vector3(q.x, y, q.y))
			g.n.append(Vector3.UP)
			g.u.append(Vector2(q.x, q.y) / 20.0)
		for t in range(0, tri.size(), 3):
			_tri(g.i, g.v, base + tri[t], base + tri[t + 1], base + tri[t + 2], Vector3.UP)
	out["water"] = g


# ---------------------------------------------------------------- 지형
func _terrain(out: Dictionary) -> void:
	for v in W * W:
		if wmask[v] == 1:
			H[v] -= 2.5
	var s := ts / N
	var V := PackedVector3Array()
	var Nn := PackedVector3Array()
	var Cc := PackedColorArray()
	var U := PackedVector2Array()
	var idx := PackedInt32Array()
	V.resize(W * W)
	Nn.resize(W * W)
	Cc.resize(W * W)
	U.resize(W * W)
	for j in W:
		for i in W:
			var v := j * W + i
			var h := H[v]
			V[v] = Vector3((float(i) / N - 0.5) * ts, h, (float(j) / N - 0.5) * ts)
			var hl := H[j * W + maxi(i - 1, 0)]
			var hr := H[j * W + mini(i + 1, N)]
			var hu := H[maxi(j - 1, 0) * W + i]
			var hd := H[mini(j + 1, N) * W + i]
			var nrm := Vector3((hl - hr) / (2.0 * s), 1.0, (hu - hd) / (2.0 * s)).normalized()
			Nn[v] = nrm
			var c := vcol[v]
			var slope := 1.0 - nrm.y
			if wmask[v] == 1:
				c = Color(0.2, 0.22, 0.17)
			else:
				if slope > 0.3:
					c = c.lerp(Color(0.43, 0.4, 0.36), clampf((slope - 0.3) * 3.0, 0.0, 1.0))
				var snow := ST.snowline(lat)
				if h > snow - 900.0:
					c = c.lerp(Color(0.5, 0.48, 0.45), clampf((h - (snow - 900.0)) / 500.0, 0.0, 1.0))
				if h > snow - 250.0:
					c = c.lerp(Color(0.95, 0.96, 0.98), clampf((h - (snow - 250.0)) / 350.0, 0.0, 1.0))
				if biome == 5 and slope < 0.25:
					c = c.lerp(Color(0.93, 0.95, 0.97), 0.7)
			Cc[v] = c
			U[v] = Vector2(float(i) / N, float(j) / N)
	for j in N:
		for i in N:
			var a := j * W + i
			idx.append_array([a, a + 1, a + W, a + 1, a + W + 1, a + W])
	# 청크 사이 틈 가리개(가장자리 아래로 드리운 스커트)
	var edges: Array = []
	var e0 := PackedInt32Array()
	var e1 := PackedInt32Array()
	var e2 := PackedInt32Array()
	var e3 := PackedInt32Array()
	for i in W:
		e0.append(i)
		e1.append(N * W + i)
		e2.append(i * W)
		e3.append(i * W + N)
	edges = [[e0, Vector3(0, 0, -1)], [e1, Vector3(0, 0, 1)], [e2, Vector3(-1, 0, 0)], [e3, Vector3(1, 0, 0)]]
	for e in edges:
		var ring: PackedInt32Array = e[0]
		var outn: Vector3 = e[1]
		var base := V.size()
		for v in ring:
			V.append(V[v] + Vector3(0, -8.0, 0))
			Nn.append(outn)
			Cc.append(Cc[v])
			U.append(U[v])
		for q in ring.size() - 1:
			_tri(idx, V, ring[q], ring[q + 1], base + q, outn)
			_tri(idx, V, ring[q + 1], base + q + 1, base + q, outn)
	out["t_v"] = V
	out["t_n"] = Nn
	out["t_c"] = Cc
	out["t_u"] = U
	out["t_i"] = idx


# ---------------------------------------------------------------- 도로
func _road_info(cls: String) -> Array: # [폭, 높이 순위, 그룹]
	match cls:
		"motorway": return [14.0, 5, "major"]
		"trunk": return [12.0, 4, "major"]
		"primary": return [11.0, 4, "major"]
		"secondary": return [9.5, 3, "major"]
		"tertiary": return [8.0, 3, "major"]
		"minor": return [6.5, 2, "minor"]
		"service": return [4.0, 1, "minor"]
		"track": return [3.0, 1, "path"]
		"path": return [1.8, 0, "path"]
	return []


func _roads(layers: Dictionary, out: Dictionary) -> void:
	var G := {"major": _grp(), "minor": _grp(), "path": _grp()}
	if layers.has("transportation"):
		ext = float(layers.transportation.extent)
		var half := ts * 0.5
		for f in layers.transportation.features:
			if f.type != 2 or not f.has("lines"):
				continue
			var cls := str(f.props.get("class", ""))
			var info := _road_info(cls)
			if info.is_empty():
				continue
			var brunnel := str(f.props.get("brunnel", ""))
			if brunnel == "tunnel":
				continue
			for line in f.lines:
				var pts := PackedVector2Array()
				for q in line:
					pts.append(lp(q))
				var lift: float = 0.12 + info[1] * 0.012
				_strip(pts, info[0], lift, brunnel == "bridge", G[info[2]], half)
				_graph_line(pts, info, lift, brunnel == "bridge", int(f.props.get("oneway", 0)), half)
	for k in G:
		out["r_" + k] = G[k]
	out["net"] = net_lines
	_lamps(out, ts * 0.5)


## 가로등 위치: 도로선을 따라 일정 간격, 좌우 번갈아, 도로 폭 바깥쪽
func _lamps(out: Dictionary, half: float) -> void:
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var side := 1.0
	for L in net_lines:
		if L.g == "path":
			continue
		var step: float = 42.0 if L.g == "major" else 56.0
		var P: PackedVector3Array = L.p
		var acc := 0.0
		var next := step * 0.5
		for i in range(1, P.size()):
			var a := P[i - 1]
			var b := P[i]
			var seg := Vector2(b.x - a.x, b.z - a.z)
			var l := seg.length()
			if l < 0.01:
				continue
			acc += l
			if acc >= next:
				next += step
				var d := seg / l
				var right := Vector2(-d.y, d.x)
				var off: float = float(L.w) * 0.5 + 1.0
				var px := b.x + right.x * off * side
				var pz := b.z + right.y * off * side
				if absf(px) <= half and absf(pz) <= half:
					pos.append(Vector3(px, hgt(px, pz), pz))
					var to_road := -right * side
					yaw.append(atan2(to_road.x, to_road.y))
				side = -side
	out["lamp_p"] = pos
	out["lamp_y"] = yaw


## 길찾기 그래프용 선: 3m 간격 3D 점(도로 윗면 높이), 타일 경계 3m 바깥까지 포함(이웃 타일과 겹쳐서 이어 붙임)
func _graph_line(pts: PackedVector2Array, info: Array, lift: float, bridge: bool, oneway: int, half: float) -> void:
	if pts.size() < 2:
		return
	var P := PackedVector2Array()
	var D := PackedFloat32Array()
	P.append(pts[0])
	D.append(0.0)
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var L := a.distance_to(b)
		var steps := maxi(1, int(round(L / 3.0)))
		for s in range(1, steps + 1):
			P.append(a.lerp(b, float(s) / steps))
			acc += L / steps
			D.append(acc)
	var h0 := hgt(P[0].x, P[0].y)
	var h1 := hgt(P[P.size() - 1].x, P[P.size() - 1].y)
	var total := maxf(acc, 0.01)
	var cur := PackedVector3Array()
	for i in P.size():
		if absf(P[i].x) <= half + 3.0 and absf(P[i].y) <= half + 3.0:
			var y := (lerpf(h0, h1, D[i] / total) + lift + 0.6) if bridge else (hgt(P[i].x, P[i].y) + lift)
			cur.append(Vector3(P[i].x, y, P[i].y))
		else:
			_flush_line(cur, info, oneway, bridge)
			cur = PackedVector3Array()
	_flush_line(cur, info, oneway, bridge)


func _flush_line(cur: PackedVector3Array, info: Array, oneway: int, bridge := false) -> void:
	if cur.size() < 2:
		return
	if oneway == -1:
		cur.reverse()
	net_lines.append({"p": cur, "w": info[0], "g": info[2], "ow": oneway != 0, "br": bridge})


func _strip(pts: PackedVector2Array, width: float, lift: float, bridge: bool, g: Dictionary, half: float) -> void:
	if pts.size() < 2:
		return
	var P := PackedVector2Array()
	var D := PackedFloat32Array()
	P.append(pts[0])
	D.append(0.0)
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var L := a.distance_to(b)
		var steps := maxi(1, int(ceil(L / 6.0)))
		for s in range(1, steps + 1):
			P.append(a.lerp(b, float(s) / steps))
			acc += L / steps
			D.append(acc)
	var h0 := hgt(P[0].x, P[0].y)
	var h1 := hgt(P[P.size() - 1].x, P[P.size() - 1].y)
	var total := maxf(acc, 0.01)
	var run_start := -1
	var base := 0
	var prev_row := -1
	for i in P.size():
		var inside := absf(P[i].x) <= half and absf(P[i].y) <= half
		# 이웃 타일과 겹치지 않게: 타일 안쪽 점만 그림(경계 한 점 여유)
		if not inside:
			prev_row = -1
			continue
		var d1 := P[maxi(i - 1, 0)]
		var d2 := P[mini(i + 1, P.size() - 1)]
		var dir := (d2 - d1).normalized()
		if dir.length() < 0.001:
			dir = Vector2(1, 0)
		var nrm := Vector2(-dir.y, dir.x) * width * 0.5
		var y := (lerpf(h0, h1, D[i] / total) + lift + 0.6) if bridge else (hgt(P[i].x, P[i].y) + lift)
		var row: int = g.v.size()
		g.v.append(Vector3(P[i].x + nrm.x, y, P[i].y + nrm.y))
		g.v.append(Vector3(P[i].x - nrm.x, y, P[i].y - nrm.y))
		g.n.append(Vector3.UP)
		g.n.append(Vector3.UP)
		g.u.append(Vector2(0, D[i] / 12.0))
		g.u.append(Vector2(1, D[i] / 12.0))
		if prev_row >= 0:
			_tri(g.i, g.v, prev_row, prev_row + 1, row, Vector3.UP)
			_tri(g.i, g.v, prev_row + 1, row + 1, row, Vector3.UP)
		prev_row = row


# ---------------------------------------------------------------- 건물
const NF := 6   # 파사드 변형 수(4,5 = 유리/오피스)
const NS := 3   # 1층 상가 변형 수
const FLOOR_H := 3.2
const SHOP_H := 4.2

var region := 0
var biome := 0
var skip: Array = []   # 랜드마크 자리(타일 로컬 x, z, 반경): 그 안의 지도 건물은 만들지 않음
const ST := preload("res://scripts/style.gd")
var season := 1
var lat := 0.0
var rng := RandomNumberGenerator.new()
var rgrid := {}
var bgrid := {}
var bboxes: Array = []
var tp := PackedVector3Array()
var ty_ := PackedFloat32Array()
var tsz := PackedFloat32Array()
var tk := PackedInt32Array()
var tc := PackedColorArray()
var tcs := PackedFloat32Array()
const TREE_CAP := 1500


func _tint(hsh: int) -> Color:
	var l := 0.84 + float(hsh % 37) / 100.0
	var r := 0.96 + float((hsh / 7) % 9) / 100.0
	var b := 0.96 + float((hsh / 61) % 9) / 100.0
	return Color(minf(l * r, 1.15), minf(l, 1.15), minf(l * b, 1.15), 1.0)


func _roof_color(hsh: int, pitched: bool) -> Color:
	var v := 0.85 + float(hsh % 25) / 100.0
	if pitched:
		return ST.ROOF[region] * v
	return Color(0.32, 0.32, 0.33) * v


func _buildings(layers: Dictionary, out: Dictionary, tx: int, ty: int) -> void:
	var G: Array = []
	for m in NF:
		G.append(_grp())
	var SG: Array = []
	for m in NS:
		SG.append(_grp())
	var roof := _grp()
	var faces := PackedVector3Array()
	if layers.has("building"):
		ext = float(layers.building.extent)
		for f in layers.building.features:
			if f.type != 3 or not f.has("polys"):
				continue
			var rh := float(f.props.get("render_height", 0.0))
			var rmin := float(f.props.get("render_min_height", 0.0))
			for p in f.polys:
				var o := PackedVector2Array()
				for q in p.o:
					o.append(lp(q))
				if o.size() < 3:
					continue
				var area := _poly_area(o)
				if absf(area) < 6.0:
					continue
				var c := Vector2.ZERO
				for q in o:
					c += q
				c /= o.size()
				var skipped := false
				for sk in skip:
					if (c - Vector2(sk.x, sk.y)).length() < sk.z:
						skipped = true
						break
				if skipped:
					continue
				var hsh := absi(hash(Vector2i(int(c.x * 7.0), int(c.y * 7.0))))
				var h := rh
				if h <= 0.0:
					h = 6.0 + float(hsh % 9)
				var gmin := 1e9
				for q in o:
					gmin = minf(gmin, hgt(q.x, q.y))
				var top := gmin + h
				var bot := gmin + rmin - (1.5 if rmin <= 0.0 else 0.0)
				if top - bot < 2.0:
					top = bot + 3.0
				var mi := hsh % 4
				if h > 45.0:
					mi = 4 + (hsh % 2)
				elif h > 22.0 and hsh % 3 == 0:
					mi = 4
				var house := h <= 12.0 and absf(area) < 450.0 and o.size() <= 14 and rmin <= 0.0 and float(hsh % 100) < float(ST.PITCH[region]) * 100.0
				var shop := rmin <= 0.0 and h >= 9.0 and not house
				bpolys.append(o)
				_extrude(o, area, gmin, bot, top, G[mi], (SG[hsh % NS] if shop else {}), house, _tint(hsh), roof, faces, hsh, c)
	for m in NF:
		out["b_%d" % m] = G[m]
	for m in NS:
		out["s_%d" % m] = SG[m]
	out["b_roof"] = roof
	out["b_faces"] = faces
	out["bpolys"] = bpolys


func _poly_area(o: PackedVector2Array) -> float:
	var a := 0.0
	for i in o.size():
		var p := o[i]
		var q := o[(i + 1) % o.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _wall_quad(g: Dictionary, a: Vector2, b: Vector2, y0: float, y1: float, u0: float, u1: float, v_bot: float, v_top: float, nrm: Vector3, col: Color) -> void:
	var base: int = g.v.size()
	var vv := [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]
	var uu := [Vector2(u0, v_bot), Vector2(u1, v_bot), Vector2(u1, v_top), Vector2(u0, v_top)]
	for q in 4:
		g.v.append(vv[q])
		g.n.append(nrm)
		g.u.append(uu[q])
		g.c.append(col)
	_tri(g.i, g.v, base, base + 1, base + 2, nrm)
	_tri(g.i, g.v, base, base + 2, base + 3, nrm)


func _extrude(o: PackedVector2Array, area: float, gmin: float, bot: float, top: float, g: Dictionary, sg: Dictionary, house: bool, tint: Color, roof: Dictionary, faces: PackedVector3Array, hsh: int, cen: Vector2) -> void:
	var sgn := 1.0 if area > 0.0 else -1.0
	var n := o.size()
	var has_shop := not sg.is_empty()
	var shop_top := gmin + SHOP_H
	var yb := shop_top if has_shop else bot
	var base_y := shop_top if has_shop else gmin
	var floors := maxi(1, int(round((top - base_y) / FLOOR_H)))
	var floor_h := (top - base_y) / floors
	var v_bot := (top - yb) / (floor_h * 4.0)
	var run_u := 0.0
	var run_s := 0.0
	for i in n:
		var a := o[i]
		var b := o[(i + 1) % n]
		var d := b - a
		var L := d.length()
		if L < 0.05:
			continue
		var nrm := Vector3(d.y, 0, -d.x).normalized() * sgn
		var nwin := maxi(1, int(round(L / 3.0)))
		_wall_quad(g, a, b, yb, top, run_u / 4.0, (run_u + nwin) / 4.0, v_bot, 0.0, nrm, tint)
		if has_shop:
			# 바깥에서 봤을 때 글자가 뒤집히지 않도록(감는 방향이 시계 반대면 u 를 반대로)
			var su0 := run_s / 5.0
			var su1 := (run_s + L) / 5.0
			if sgn > 0.0:
				su0 = (run_s + L) / 5.0
				su1 = run_s / 5.0
			_wall_quad(sg, a, b, bot, shop_top, su0, su1, (shop_top - bot) / SHOP_H, 0.0, nrm, Color(1, 1, 1, 1))
		run_u += nwin
		run_s += L
		var p0 := Vector3(a.x, bot, a.y)
		var p1 := Vector3(b.x, bot, b.y)
		var p2 := Vector3(b.x, top, b.y)
		var p3 := Vector3(a.x, top, a.y)
		for t in [[p0, p1, p2], [p0, p2, p3]]:
			faces.append(t[0])
			faces.append(t[1])
			faces.append(t[2])
	# 지붕
	if house and Geometry2D.is_point_in_polygon(cen, o):
		var ridge := clampf(0.2 * sqrt(absf(area)), 1.6, 4.2)
		var apex := Vector3(cen.x, top + ridge, cen.y)
		var rc := _roof_color(hsh, true)
		for i in n:
			var a2 := o[i]
			var b2 := o[(i + 1) % n]
			var va := Vector3(a2.x, top, a2.y)
			var vb := Vector3(b2.x, top, b2.y)
			var fn := (vb - va).cross(apex - va)
			if fn.length() < 0.001:
				continue
			fn = fn.normalized()
			if fn.y < 0.0:
				fn = -fn
			var rb: int = roof.v.size()
			for q in [va, vb, apex]:
				roof.v.append(q)
				roof.n.append(fn)
				roof.u.append(Vector2.ZERO)
				roof.c.append(rc)
			_tri(roof.i, roof.v, rb, rb + 1, rb + 2, fn)
			faces.append(va)
			faces.append(vb)
			faces.append(apex)
		return
	var tri := Geometry2D.triangulate_polygon(o)
	var flat := _roof_color(hsh, false)
	if tri.size() >= 3:
		var rb2: int = roof.v.size()
		for q in o:
			roof.v.append(Vector3(q.x, top, q.y))
			roof.n.append(Vector3.UP)
			roof.u.append(Vector2.ZERO)
			roof.c.append(flat)
		for t in range(0, tri.size(), 3):
			_tri(roof.i, roof.v, rb2 + tri[t], rb2 + tri[t + 1], rb2 + tri[t + 2], Vector3.UP)
			faces.append(roof.v[rb2 + tri[t]])
			faces.append(roof.v[rb2 + tri[t + 1]])
			faces.append(roof.v[rb2 + tri[t + 2]])
	# 옥상 설비(환기구/승강기실/물탱크 느낌의 상자)
	if top - gmin >= 14.0 and absf(area) > 180.0:
		var mn := o[0]
		var mx := o[0]
		for q in o:
			mn = mn.min(q)
			mx = mx.max(q)
		for k2 in (1 + hsh % 2):
			for tries in 6:
				var cx := lerpf(mn.x, mx.x, 0.25 + 0.5 * float((hsh >> (k2 * 5 + tries)) % 100) / 100.0)
				var cz := lerpf(mn.y, mx.y, 0.25 + 0.5 * float((hsh >> (k2 * 3 + tries + 2)) % 100) / 100.0)
				var bw := 2.0 + float((hsh >> 3) % 30) / 10.0
				var bh := 1.2 + float((hsh >> 5) % 20) / 10.0
				var ok := true
				for dx in [-1.0, 1.0]:
					for dz in [-1.0, 1.0]:
						if not Geometry2D.is_point_in_polygon(Vector2(cx + dx * bw * 0.5, cz + dz * bw * 0.5), o):
							ok = false
				if ok:
					_roof_box(roof, cx, cz, top, bw, bh, bw * 0.8, flat * 1.25)
					break


func _roof_box(g: Dictionary, cx: float, cz: float, y: float, w: float, h: float, d: float, col: Color) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	var c := [Vector3(cx - hw, y, cz - hd), Vector3(cx + hw, y, cz - hd), Vector3(cx + hw, y, cz + hd), Vector3(cx - hw, y, cz + hd)]
	var t := []
	for p in c:
		t.append(p + Vector3(0, h, 0))
	var faces := [
		[c[0], c[1], t[1], t[0], Vector3(0, 0, -1)], [c[1], c[2], t[2], t[1], Vector3(1, 0, 0)],
		[c[2], c[3], t[3], t[2], Vector3(0, 0, 1)], [c[3], c[0], t[0], t[3], Vector3(-1, 0, 0)],
		[t[0], t[1], t[2], t[3], Vector3(0, 1, 0)]]
	for f in faces:
		var base: int = g.v.size()
		for q in 4:
			g.v.append(f[q])
			g.n.append(f[4])
			g.u.append(Vector2.ZERO)
			g.c.append(col)
		_tri(g.i, g.v, base, base + 1, base + 2, f[4])
		_tri(g.i, g.v, base, base + 2, base + 3, f[4])


# ---------------------------------------------------------------- 나무
func _build_grids() -> void:
	rgrid.clear()
	for li in net_lines.size():
		var L: Dictionary = net_lines[li]
		if L.g == "path":
			continue
		var hw: float = float(L.w) * 0.5
		for q in L.p:
			var key := Vector2i(floori(q.x / 12.0), floori(q.z / 12.0))
			if not rgrid.has(key):
				rgrid[key] = []
			rgrid[key].append([q.x, q.z, hw, li])
	bgrid.clear()
	bboxes.clear()
	for bi in bpolys.size():
		var o: PackedVector2Array = bpolys[bi]
		var mn := o[0]
		var mx := o[0]
		for q in o:
			mn = mn.min(q)
			mx = mx.max(q)
		bboxes.append(Rect2(mn - Vector2(1.5, 1.5), mx - mn + Vector2(3.0, 3.0)))
		for cx in range(floori(mn.x / 40.0), floori(mx.x / 40.0) + 1):
			for cz in range(floori(mn.y / 40.0), floori(mx.y / 40.0) + 1):
				var key := Vector2i(cx, cz)
				if not bgrid.has(key):
					bgrid[key] = []
				bgrid[key].append(bi)


## (x,z) 가 도로(자기 도로 제외 li)/건물/물 위라 나무를 심을 수 없는가
func _blocked(x: float, z: float, li: int) -> bool:
	var c := Vector2i(floori(x / 12.0), floori(z / 12.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = rgrid.get(Vector2i(c.x + dx, c.y + dz))
			if arr == null:
				continue
			for e in arr:
				var d2: float = (e[0] - x) * (e[0] - x) + (e[1] - z) * (e[1] - z)
				var lim: float = float(e[2]) + (0.9 if e[3] == li else 1.6)
				if d2 < lim * lim:
					return true
	var bl = bgrid.get(Vector2i(floori(x / 40.0), floori(z / 40.0)))
	if bl != null:
		var pt := Vector2(x, z)
		for bi in bl:
			if bboxes[bi].has_point(pt) and Geometry2D.is_point_in_polygon(pt, bpolys[bi]):
				return true
	var i := clampi(int(round((x / ts + 0.5) * N)), 0, N)
	var j := clampi(int(round((z / ts + 0.5) * N)), 0, N)
	return wmask[j * W + i] == 1


func _leaf_color(kind: int) -> Color:
	var v := rng.randf_range(0.85, 1.12)
	if kind == 2:
		return Color(0.16, 0.44, 0.12) * v
	if kind == 1:
		return (Color(0.07, 0.2, 0.1) if biome == 4 else Color(0.1, 0.27, 0.13)) * v
	match biome:
		1: return Color(0.08, 0.34, 0.1) * v
		2: return Color(0.42, 0.46, 0.2) * v
		3: return Color(0.36, 0.42, 0.22) * v
	match season:
		0: return Color(0.42, 0.62, 0.22) * v
		2:
			var r := rng.randf()
			if r < 0.35:
				return Color(0.78, 0.5, 0.1) * v
			if r < 0.6:
				return Color(0.82, 0.3, 0.1) * v
			if r < 0.8:
				return Color(0.65, 0.58, 0.14) * v
			return Color(0.3, 0.45, 0.14) * v
		3: return Color(0.4, 0.34, 0.28) * v
	return Color(0.2, 0.46, 0.16) * v


func _add_tree(x: float, z: float, smin: float, smax: float, wood: bool, street := false) -> void:
	if tp.size() >= TREE_CAP or biome == 5:
		return
	var h := hgt(x, z)
	if h > ST.snowline(lat) - 700.0:
		return # 수목한계 위
	# 종류: 0 활엽, 1 침엽, 2 야자
	var conifer := (0.6 if region == 5 else 0.12) + (0.25 if wood else 0.0)
	var palm := 0.0
	match biome:
		1:
			conifer = 0.0
			palm = 0.55 if street else 0.35
		2:
			conifer = 0.0
			palm = 0.75 if street else 0.5
		3:
			conifer = 0.3 + (0.15 if wood else 0.0)
			palm = 0.1 if street else 0.0
		4:
			conifer = 0.8 if wood else 0.55
	var r := rng.randf()
	var kind := 0
	if r < palm:
		kind = 2
	elif rng.randf() < conifer:
		kind = 1
	tp.append(Vector3(x, h, z))
	ty_.append(rng.randf() * TAU)
	var sc := rng.randf_range(smin, smax)
	if biome == 2 and kind == 0:
		sc *= 0.6 # 사막 관목
	tsz.append(sc)
	tk.append(kind)
	tc.append(_leaf_color(kind))
	tcs.append(0.45 if (kind == 0 and season == 3 and biome == 0) else 1.0) # 겨울 활엽수는 잎이 거의 없어 작은 가지 덩어리


func _trees(layers: Dictionary, out: Dictionary) -> void:
	_build_grids()
	var half := ts * 0.5 - 1.0
	# 가로수
	for li in net_lines.size():
		var L: Dictionary = net_lines[li]
		if L.g == "path" or L.br:
			continue
		var major: bool = L.g == "major"
		var step := 15.0 if major else 19.0
		var P: PackedVector3Array = L.p
		var acc := 0.0
		var next := step * 0.5
		var side := 1.0
		for i in range(1, P.size()):
			var a := P[i - 1]
			var b := P[i]
			var seg := Vector2(b.x - a.x, b.z - a.z)
			var l := seg.length()
			if l < 0.01:
				continue
			acc += l
			if acc >= next:
				next += step
				var d := seg / l
				var right := Vector2(-d.y, d.x)
				var off: float = float(L.w) * 0.5 + 2.6
				for sd in ([1.0, -1.0] if major else [side]):
					var px: float = b.x + right.x * off * sd
					var pz: float = b.z + right.y * off * sd
					if absf(px) > half or absf(pz) > half:
						continue
					if _blocked(px, pz, li):
						continue
					_add_tree(px, pz, 0.85, 1.2, false, true)
				side = -side
	# 숲/공원/묘지 나무
	for lname in ["landcover", "park", "landuse"]:
		if not layers.has(lname):
			continue
		ext = float(layers[lname].extent)
		for f in layers[lname].features:
			if f.type != 3 or not f.has("polys"):
				continue
			var cls := str(f.props.get("class", ""))
			var wood := false
			if lname == "landcover":
				if cls != "wood" and cls != "forest":
					continue
				wood = true
			elif lname == "landuse" and cls != "cemetery":
				continue
			for p in f.polys:
				var lpoly := _local_poly(p)
				var o: PackedVector2Array = lpoly.o
				var area := absf(_poly_area(o))
				if area < 150.0:
					continue
				var mn := o[0]
				var mx := o[0]
				for q in o:
					mn = mn.min(q)
					mx = mx.max(q)
				var step := 6.5 if wood else 9.0
				if area / (step * step) > 900.0:
					step = sqrt(area / 900.0)
				var x := maxf(mn.x, -half)
				while x < minf(mx.x, half):
					var z := maxf(mn.y, -half)
					while z < minf(mx.y, half):
						var px := x + rng.randf_range(-0.4, 0.4) * step
						var pz := z + rng.randf_range(-0.4, 0.4) * step
						z += step
						if absf(px) > half or absf(pz) > half or tp.size() >= TREE_CAP:
							continue
						var pt := Vector2(px, pz)
						if not Geometry2D.is_point_in_polygon(pt, o):
							continue
						var inhole := false
						for hr in lpoly.h:
							if Geometry2D.is_point_in_polygon(pt, hr):
								inhole = true
								break
						if inhole or _blocked(px, pz, -1):
							continue
						if biome == 2 and rng.randf() > 0.3:
							continue
						_add_tree(px, pz, 0.95, 1.6 if wood else 1.3, wood)
					x += step
	out["tree_p"] = tp
	out["tree_y"] = ty_
	out["tree_s"] = tsz
	out["tree_k"] = tk
	out["tree_c"] = tc
	out["tree_cs"] = tcs
