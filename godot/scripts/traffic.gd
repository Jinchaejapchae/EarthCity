extends Node
# NPC 교통/보행자 관리: 플레이어 주변에만 생성하고 멀어지면 지움.

const CarScript := preload("res://scripts/npc_car.gd")
const PedScript := preload("res://scripts/npc_ped.gd")
const SignalsScript := preload("res://scripts/signals.gd")
const SignalViewScript := preload("res://scripts/signal_view.gd")
const STOP_D := 6.0
const DECEL := 3.5
const CAR_FILES := ["sedan", "sedan-sports", "hatchback-sports", "suv", "suv-luxury", "taxi", "van", "truck", "delivery", "police"]
var max_cars := 26
var max_peds := 14

var world: Node3D
var focus := Vector3.ZERO          # 플레이어(또는 탄 차) 위치
var player_cars: Array = []        # 플레이어가 탈 수 있는 차(장애물로 취급)
var player_node: Node3D            # 걸어 다니는 플레이어
var cars: Array = []
var peds: Array = []
var timer := 0.0
var side := 1.0   # 1 = 우측통행, -1 = 좌측통행
var enabled := false
var signals := SignalsScript.new()
var sview: Node3D
var night := 0.0
var debug := false


func _ready() -> void:
	sview = SignalViewScript.new()
	sview.signals = signals
	sview.world = world
	add_child(sview)


func clear() -> void:
	for c in cars:
		if is_instance_valid(c):
			c.queue_free()
	for p in peds:
		if is_instance_valid(p):
			p.queue_free()
	cars.clear()
	peds.clear()


func _process(dt: float) -> void:
	if not enabled:
		return
	sview.update(dt, focus, night, side)
	timer -= dt
	if timer <= 0.0:
		timer = 0.4
		_maintain()


func _maintain() -> void:
	var net: RefCounted = world.net_roads
	for list in [cars, peds]:
		for i in range(list.size() - 1, -1, -1):
			var o = list[i]
			if not is_instance_valid(o):
				list.remove_at(i)
				continue
			var far: bool = Vector2(o.global_position.x - focus.x, o.global_position.z - focus.z).length() > 520.0
			if o.dead or far:
				o.queue_free()
				list.remove_at(i)
	# 청크가 생기고 사라질 때 교차로를 한 번에 하나씩 증분 갱신
	for key in signals.by_chunk.keys():
		if not net.by_chunk.has(key):
			signals.remove_chunk(key)
	for key in net.by_chunk.keys():
		if not signals.by_chunk.has(key):
			var t0 := Time.get_ticks_msec()
			signals.add_chunk(net, key)
			if debug:
				print("SIGCHUNK ms=", Time.get_ticks_msec() - t0, " clusters=", signals.clusters.size())
			break
	if debug:
		var waiting := 0
		var near_sig := 0
		var run_red := 0
		for c in cars:
			var lk: Dictionary = c.look
			if not lk.is_empty() and lk.type == "signal":
				near_sig += 1
				var st: int = signals.state(lk.cl, lk.dir)
				var rem: float = float(lk.dist) - c.look_travel
				if c.speed < 0.3 and st == 2:
					waiting += 1
				if st == 2 and rem < 1.0 and rem > -1.0 and c.speed > 4.0:
					run_red += 1
		var any_look := 0
		var yields := 0
		for c in cars:
			if not c.look.is_empty():
				any_look += 1
				if c.look.type == "yield":
					yields += 1
		var pw := 0
		var pc := 0
		for pd in peds:
			if pd.waiting:
				pw += 1
			if pd.cross > 0.0:
				pc += 1
		print("PEDSTAT peds=", peds.size(), " waiting=", pw, " crossing=", pc)
		print("SIGSTAT clusters=", signals.clusters.size(), " cars=", cars.size(), " approaching_signal=", near_sig, " waiting_red=", waiting, " running_red=", run_red)
	while cars.size() > max_cars:
		var oc = cars.pop_back()
		if is_instance_valid(oc):
			oc.queue_free()
	while peds.size() > max_peds:
		var op = peds.pop_back()
		if is_instance_valid(op):
			op.queue_free()
	if cars.size() < max_cars:
		_spawn_car(net)
	if peds.size() < max_peds:
		_spawn_ped(net)


func _spawn_car(net: RefCounted) -> void:
	var id: int = net.random_near(focus, 70.0, 380.0, ["major", "minor"])
	if id == -1:
		return
	var outs: Array = net.alive_out(id, ["major", "minor"])
	var e: Array = outs[randi() % outs.size()]
	var pos: Vector3 = net.nodes[id].p
	for c in cars:
		if c.global_position.distance_to(pos) < 12.0:
			return
	if pos.distance_to(focus) < 60.0:
		return
	var car: AnimatableBody3D = CarScript.new()
	add_child(car)
	car.setup("res://assets/cars/%s.glb" % CAR_FILES[randi() % CAR_FILES.size()], net, self, id, e[0], randf() * 8.0)
	cars.append(car)


func _spawn_ped(net: RefCounted) -> void:
	var id: int = -1
	var e: Array = []
	# 절반은 신호 교차로 쪽으로 걸어오게 해서 횡단보도 근처에 사람이 생기게 함
	if randf() < 0.5 and not signals.clusters.is_empty():
		var keys: Array = signals.clusters.keys()
		for tries in 8:
			var c: Dictionary = signals.clusters[keys[randi() % keys.size()]]
			var cd := Vector2(c.center.x - focus.x, c.center.z - focus.z).length()
			if cd < 40.0 or cd > 220.0:
				continue
			var arm: Dictionary = c.arms[randi() % c.arms.size()]
			var far: Vector3 = arm.base + Vector3(arm.d.x, 0.0, arm.d.y) * 22.0
			var nid: int = net.nearest(far, 12.0, ["major", "minor", "path"])
			if nid == -1:
				continue
			var best_d := 1e9
			for oe in net.alive_out(nid, ["major", "minor", "path"]):
				var dq: float = (net.nodes[oe[0]].p - arm.base).length()
				if dq < best_d:
					best_d = dq
					e = oe
			if not e.is_empty():
				id = nid
				break
	if id == -1:
		id = net.random_near(focus, 30.0, 220.0, ["major", "minor", "path"])
		if id == -1:
			return
		var outs: Array = net.alive_out(id, ["major", "minor", "path"])
		e = outs[randi() % outs.size()]
	var ped: Node3D = PedScript.new()
	add_child(ped)
	ped.setup(net, world, self, id, e[0], randf() * 6.0)
	peds.append(ped)


func _dir_of(o: Node3D) -> Vector2:
	if "dir_s" in o:
		return o.dir_s
	return Vector2(-sin(o.heading), -cos(o.heading))


## 차의 앞쪽 경로(최대 75m)를 훑어 가장 먼저 만나는 교차로를 찾는다. {type: "signal"|"yield", cl, node, dist, dir}
func junction_ahead(car: Node3D) -> Dictionary:
	var net: RefCounted = world.net_roads
	var a: int = car.a
	var b: int = car.b
	if not net.nodes.has(a) or not net.nodes.has(b):
		return {}
	var dist: float = car.elen - car.t
	for step in 40:
		if dist > 75.0 or not net.nodes.has(b):
			break
		var pa: Vector3 = net.nodes[a].p
		var pb: Vector3 = net.nodes[b].p
		var d_in := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
		var cl: int = signals.node_cluster.get(b, -1)
		if cl != -1:
			if signals.node_cluster.get(a, -2) != cl:
				return {"type": "signal", "cl": cl, "node": b, "dist": dist, "dir": d_in}
		elif _arm_count(net, b) >= 3:
			return {"type": "yield", "cl": -1, "node": b, "dist": dist, "dir": d_in}
		# 다음 노드: 첫 칸은 차가 실제로 고른 길, 이후는 가장 곧은 길
		var nxt := -1
		if step == 0:
			nxt = car.nx
		if nxt == -1 or not net.nodes.has(nxt):
			nxt = -1
			var best := -2.0
			for e in net.alive_out(b, ["major", "minor"]):
				if e[0] == a:
					continue
				var pc: Vector3 = net.nodes[e[0]].p
				var dd := Vector2(pc.x - pb.x, pc.z - pb.z).normalized()
				if d_in.dot(dd) > best:
					best = d_in.dot(dd)
					nxt = e[0]
		if nxt == -1:
			break
		var pn: Vector3 = net.nodes[nxt].p
		dist += Vector2(pn.x - pb.x, pn.z - pb.z).length()
		a = b
		b = nxt
	return {}


func _arm_count(net: RefCounted, id: int) -> int:
	var n: Dictionary = net.nodes[id]
	if n.out.size() < 3:
		return 0
	var dirs: Array = []
	for e in n.out:
		if e[2] == "path" or not net.nodes.has(e[0]):
			continue
		var q: Vector3 = net.nodes[e[0]].p
		var d := Vector2(q.x - n.p.x, q.z - n.p.z).normalized()
		var dup := false
		for x in dirs:
			if x.dot(d) > 0.8:
				dup = true
				break
		if not dup:
			dirs.append(d)
	return dirs.size()


## 교차로 규칙에 따른 속도 상한: 신호(정지선에서 정지, 노랑이면 멈출 수 있을 때만 정지) / 신호 없는 교차로 양보
func junction_limit(car: Node3D, look: Dictionary, dist: float) -> float:
	if look.is_empty():
		return 99.0
	if look.type == "signal":
		var st: int = signals.state(look.cl, look.dir)
		var dstop := dist - STOP_D
		if st == 0 or dstop < -2.0:
			return 99.0 # 초록이거나 이미 정지선을 넘음
		if st == 1 and car.speed * car.speed / (2.0 * DECEL) >= dstop:
			return 99.0 # 노랑인데 못 멈춤: 통과
		return sqrt(maxf(0.0, 2.0 * DECEL * dstop))
	# 신호 없는 교차로: 우선순위에 따라 양보 (큰 도로 우선, 같은 등급이면 오른쪽 차 우선)
	if dist > 22.0 or dist < -1.0 or car.wait_t > 6.0:
		return 99.0
	var net: RefCounted = world.net_roads
	var nid: int = look.node
	if not net.nodes.has(nid):
		return 99.0
	var higher := false
	for e in net.alive_out(nid, ["major", "minor"]):
		if e[2] == "major" and car.g != "major":
			higher = true
	var bp: Vector3 = net.nodes[nid].p
	var dir: Vector2 = look.dir
	var right := Vector2(-dir.y, dir.x) * side
	var others: Array = cars + player_cars
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var rel := Vector2(o.global_position.x - bp.x, o.global_position.z - bp.z)
		if rel.length() > 16.0:
			continue
		var od := _dir_of(o)
		if absf(od.dot(dir)) > 0.7 or float(o.speed) < 0.8:
			continue # 같은 방향이거나 서 있는 차
		var og: String = o.g if "g" in o else "major"
		var yield_me := false
		if higher:
			yield_me = og == "major"
		elif og == car.g:
			yield_me = rel.dot(right) > 0.0
		if yield_me:
			return maxf(0.0, (dist - 5.0) * 1.2)
	return 99.0


## 앞에 차/플레이어가 있으면 속도 제한
func speed_limit_for(car: Node3D, dir: Vector2) -> float:
	var lim := 99.0
	var p := car.global_position
	var fwd := Vector2(dir.x, dir.y)
	var right := Vector2(-fwd.y, fwd.x)
	var others: Array = cars + player_cars
	if player_node and player_node.visible:
		others = others + [player_node]
	for pd in peds:
		if is_instance_valid(pd):
			var prel := Vector2(pd.global_position.x - p.x, pd.global_position.z - p.z)
			var pdd := prel.dot(fwd)
			if pdd > 0.5 and pdd < 14.0 and absf(prel.dot(right)) < 2.3:
				lim = minf(lim, maxf(0.0, (pdd - 4.0) * 1.6))
	for o in others:
		if o == car or not is_instance_valid(o):
			continue
		var rel := Vector2(o.global_position.x - p.x, o.global_position.z - p.z)
		var d := rel.dot(fwd)
		if d <= 0.0 or d > 16.0:
			continue
		if absf(rel.dot(right)) > 2.4:
			continue
		lim = minf(lim, maxf(0.0, (d - 5.5) * 1.6))
	return lim
