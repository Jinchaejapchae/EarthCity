extends RefCounted
# 도로 그래프: 로드된 청크의 도로선을 점(노드)과 방향 간선으로 이어 붙임. 다른 선의 점이 3.2m 안에 있으면 같은 노드(= 교차로).
# 노드: {p: Vector3(월드 로컬, y=도로 윗면), out: [[to, 폭, 그룹]], chunk}. 그룹: major / minor / path

const CELL := 8.0
const MERGE := 3.2

var nodes := {}
var cells := {}
var by_chunk := {}
var next_id := 1


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _find(p: Vector3, used: Dictionary) -> int:
	var c := _cell(p)
	var best := -1
	var bd := MERGE
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = cells.get(Vector2i(c.x + dx, c.y + dz))
			if arr == null:
				continue
			for id in arr:
				if used.has(id):
					continue
				var q: Vector3 = nodes[id].p
				if absf(q.y - p.y) > 3.0: # 다리와 아래 도로는 잇지 않음
					continue
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd:
					bd = d
					best = id
	return best


func add_chunk(key: Vector2i, lines: Array, off: Vector3) -> void:
	var own: Array = []
	for L in lines:
		var prev := -1
		var used := {}
		for q in L.p:
			var p: Vector3 = Vector3(q.x + off.x, q.y, q.z + off.z)
			var id := _find(p, used)
			if id == -1:
				id = next_id
				next_id += 1
				nodes[id] = {"p": p, "out": [], "chunk": key}
				var c := _cell(p)
				if not cells.has(c):
					cells[c] = []
				cells[c].append(id)
				own.append(id)
			used[id] = true
			if prev != -1 and prev != id:
				_link(prev, id, L.w, L.g)
				if not L.ow:
					_link(id, prev, L.w, L.g)
			prev = id
	by_chunk[key] = own


func _link(a: int, b: int, w: float, g: String) -> void:
	var out: Array = nodes[a].out
	for e in out:
		if e[0] == b:
			return
	out.append([b, w, g])


func remove_chunk(key: Vector2i) -> void:
	if not by_chunk.has(key):
		return
	for id in by_chunk[key]:
		if not nodes.has(id):
			continue
		var c := _cell(nodes[id].p)
		if cells.has(c):
			cells[c].erase(id)
		nodes.erase(id)
	by_chunk.erase(key)


func alive_out(a: int, groups: Array) -> Array:
	var r: Array = []
	if not nodes.has(a):
		return r
	for e in nodes[a].out:
		if nodes.has(e[0]) and groups.has(e[2]):
			r.append(e)
	return r


## p 에서 가장 가까운 (groups 간선이 있는) 노드
func nearest(p: Vector3, max_r: float, groups: Array) -> int:
	var c := _cell(p)
	var rr := int(ceil(max_r / CELL))
	var best := -1
	var bd := max_r
	for dx in range(-rr, rr + 1):
		for dz in range(-rr, rr + 1):
			var arr = cells.get(Vector2i(c.x + dx, c.y + dz))
			if arr == null:
				continue
			for id in arr:
				var q: Vector3 = nodes[id].p
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd and not alive_out(id, groups).is_empty():
					bd = d
					best = id
	return best


func random_near(p: Vector3, rmin: float, rmax: float, groups: Array) -> int:
	for i in 24:
		var ang := randf() * TAU
		var r := randf_range(rmin, rmax)
		var q := Vector3(p.x + cos(ang) * r, 0, p.z + sin(ang) * r)
		var arr = cells.get(_cell(q))
		if arr == null or arr.is_empty():
			continue
		var id: int = arr[randi() % arr.size()]
		if not alive_out(id, groups).is_empty():
			return id
	return -1


## b 에서 다음으로 갈 노드 선택(직진 선호). 없으면 -1(유턴)
func pick_next(a: int, b: int, groups: Array) -> int:
	if not nodes.has(a) or not nodes.has(b):
		return -1
	var pa: Vector3 = nodes[a].p
	var pb: Vector3 = nodes[b].p
	var din := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
	var cands: Array = []
	var wts: Array = []
	var sum := 0.0
	for e in alive_out(b, groups):
		if e[0] == a:
			continue
		var pc: Vector3 = nodes[e[0]].p
		var dout := Vector2(pc.x - pb.x, pc.z - pb.z).normalized()
		var ang := acos(clampf(din.dot(dout), -1.0, 1.0))
		var wgt := exp(-ang * 1.1)
		cands.append(e[0])
		wts.append(wgt)
		sum += wgt
	if cands.is_empty():
		return -1
	var r := randf() * sum
	for i in cands.size():
		r -= wts[i]
		if r <= 0.0:
			return cands[i]
	return cands[cands.size() - 1]
