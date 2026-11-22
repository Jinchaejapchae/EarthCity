extends RefCounted
# 교차로 신호 시스템. 도로 그래프에서 3갈래 이상 갈라지는 노드(큰 도로 포함)를 22m 안에서 묶어 교차로로 보고,
# 접근 방향을 두 위상(축 A / 축 B)으로 나눠 신호를 돌린다. 주기 = 2 × (초록 + 노랑 + 전적색).
# 청크 단위로 증분 계산(서울처럼 노드가 17만 개여도 한 번에 끊기지 않도록).

const CLUSTER_R := 22.0
const GREEN := 17.0
const YELLOW := 3.0
const ALLRED := 2.5

var clusters := {}              # 교차로 id -> {center, axis, arms:[{d,w,phase}], offset, chunk}
var node_cluster := {}          # 노드 id -> 교차로 id
var by_chunk := {}              # 청크 키 -> [교차로 id]
var next_cid := 1


func cycle() -> float:
	return 2.0 * (GREEN + YELLOW + ALLRED)


func remove_chunk(key: Vector2i) -> void:
	if not by_chunk.has(key):
		return
	for cid in by_chunk[key]:
		clusters.erase(cid)
	by_chunk.erase(key)
	for nid in node_cluster.keys():
		if not clusters.has(node_cluster[nid]):
			node_cluster.erase(nid)


## 이 청크가 새로 만든 노드들만 검사해서 교차로를 만든다
func add_chunk(net: RefCounted, key: Vector2i) -> void:
	by_chunk[key] = []
	var ids: Array = net.by_chunk.get(key, [])
	var cand: Array = []
	var grid := {}
	for id in ids:
		if not net.nodes.has(id):
			continue
		var n: Dictionary = net.nodes[id]
		if n.out.size() < 3:
			continue
		var dirs: Array = []
		var has_major := false
		for e in n.out:
			if e[2] == "path" or not net.nodes.has(e[0]):
				continue
			var q: Vector3 = net.nodes[e[0]].p
			var d := Vector2(q.x - n.p.x, q.z - n.p.z)
			if d.length() < 0.1:
				continue
			d = d.normalized()
			var dup := false
			for x in dirs:
				if x.dot(d) > 0.8:
					dup = true
					break
			if not dup:
				dirs.append(d)
			if e[2] == "major":
				has_major = true
		if dirs.size() >= 3 and has_major:
			cand.append(id)
			var c := Vector2i(floori(n.p.x / CLUSTER_R), floori(n.p.z / CLUSTER_R))
			if not grid.has(c):
				grid[c] = []
			grid[c].append(id)
	var seen := {}
	for id in cand:
		if seen.has(id):
			continue
		var comp: Array = [id]
		seen[id] = true
		var qi := 0
		while qi < comp.size():
			var cur: int = comp[qi]
			qi += 1
			var cp: Vector3 = net.nodes[cur].p
			var c := Vector2i(floori(cp.x / CLUSTER_R), floori(cp.z / CLUSTER_R))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var arr = grid.get(Vector2i(c.x + dx, c.y + dz))
					if arr == null:
						continue
					for o in arr:
						if seen.has(o):
							continue
						var op: Vector3 = net.nodes[o].p
						if Vector2(op.x - cp.x, op.z - cp.z).length() <= CLUSTER_R:
							seen[o] = true
							comp.append(o)
		_make_cluster(net, comp, key)


func _make_cluster(net: RefCounted, comp: Array, key: Vector2i) -> void:
	var inset := {}
	var center := Vector3.ZERO
	for id in comp:
		inset[id] = true
		center += net.nodes[id].p
	center /= comp.size()
	var arms: Array = []
	for id in comp:
		var p: Vector3 = net.nodes[id].p
		for e in net.nodes[id].out:
			if inset.has(e[0]) or e[2] == "path" or not net.nodes.has(e[0]):
				continue
			var q: Vector3 = net.nodes[e[0]].p
			var d := Vector2(q.x - p.x, q.z - p.z).normalized()
			var merged := false
			for a in arms:
				if a.d.dot(d) > 0.85:
					a.w = maxf(a.w, float(e[1]))
					merged = true
					break
			if not merged:
				arms.append({"d": d, "w": float(e[1]), "phase": 0, "base": p})
	if arms.size() < 3:
		return
	var axis: Vector2 = arms[0].d
	var p0 := false
	var p1 := false
	for a in arms:
		a.phase = 0 if absf(a.d.dot(axis)) >= 0.7 else 1
		if a.phase == 0:
			p0 = true
		else:
			p1 = true
	if not (p0 and p1):
		return
	var cid := next_cid
	next_cid += 1
	var off := float(absi(hash(Vector2i(int(center.x), int(center.z)))) % 1000) / 1000.0 * cycle()
	clusters[cid] = {"center": center, "axis": axis, "arms": arms, "offset": off, "chunk": key}
	by_chunk[key].append(cid)
	for id in comp:
		node_cluster[id] = cid


## phase(0/1)의 현재 신호: 0=초록 1=노랑 2=빨강
func phase_state(ci: int, phase: int) -> int:
	var c: Dictionary = clusters[ci]
	var step := GREEN + YELLOW + ALLRED
	var t := fposmod(Time.get_ticks_msec() / 1000.0 + float(c.offset) - phase * step, cycle())
	if t < GREEN:
		return 0
	if t < GREEN + YELLOW:
		return 1
	return 2


## phase 의 신호가 초록이 될 때까지 남은 초(이미 초록이면 0)
func time_to_green(ci: int, phase: int) -> float:
	var c: Dictionary = clusters[ci]
	var step := GREEN + YELLOW + ALLRED
	var t := fposmod(Time.get_ticks_msec() / 1000.0 + float(c.offset) - phase * step, cycle())
	if t < GREEN:
		return 0.0
	return cycle() - t


## 이 방향(travel)으로 교차로에 접근하는 차에 대한 신호
func state(ci: int, travel: Vector2) -> int:
	if not clusters.has(ci):
		return 0
	var c: Dictionary = clusters[ci]
	var phase := 0 if absf(travel.dot(c.axis)) >= 0.7 else 1
	return phase_state(ci, phase)
