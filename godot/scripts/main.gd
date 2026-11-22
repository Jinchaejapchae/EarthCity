extends Node3D

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const CarScript := preload("res://scripts/car.gd")
const TrafficScript := preload("res://scripts/traffic.gd")
const MapScript := preload("res://scripts/worldmap.gd")
const AtmosScript := preload("res://scripts/atmos.gd")
const LightsScript := preload("res://scripts/lights.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const MenuScript := preload("res://scripts/menu.gd")
const CAR_FILES := ["sedan", "sedan-sports", "hatchback-sports", "suv", "suv-luxury", "taxi", "van", "truck", "delivery", "police"]
const GEOCODE := "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=ko"

var world: Node3D
var traffic: Node
var map_ui: Control
var map_test := -1
var player: CharacterBody3D
var cars: Array = []
var driving: CharacterBody3D = null
var cam: Camera3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var atmos: Node
var sfx: Node
var dump_dir := ""
var player_spots: Array = []
var arg_tm := 0
var arg_wx := 0
var env: Environment
var yaw := 0.0
var pitch := 0.3
var hud: Label
var place_name := ""
var search: LineEdit
var hour := 15.5
var frames := 0
var shot_path := ""
var shot_cam := ""
var shot_frame := 150
var cam_override: Array = []
var lat := 35.5384
var lon := 129.3114
var loading := true
var loaded_frames := 0
var settings: RefCounted
var menu: Control
var overlay: Control
var ov_label: Label
var ov_bar: ProgressBar
var ll_given := false
var force_walk := 0.0
var force_run := false


func _ready() -> void:
	settings = SettingsScript.new()
	settings.load_all()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--cam="):
			shot_cam = a.substr(6)
		elif a.begins_with("--frame="):
			shot_frame = a.substr(8).to_int()
		elif a.begins_with("--walk"):
			force_walk = 1.0
			force_run = a == "--walk=run"
		elif a.begins_with("--map="):
			map_test = a.substr(6).to_int()
		elif a.begins_with("--dump-sfx="):
			dump_dir = a.substr(11)
		elif a.begins_with("--tm="):
			arg_tm = a.substr(5).to_int()
		elif a.begins_with("--wx="):
			arg_wx = a.substr(5).to_int()
		elif a.begins_with("--ll="):
			var p := a.substr(5).split(",")
			lat = p[0].to_float()
			lon = p[1].to_float()
			ll_given = true
	if not ll_given and settings.d.has_loc:
		lat = float(settings.d.lat)
		lon = float(settings.d.lon)
		place_name = str(settings.d.place)
	_environment()
	world = WorldScript.new()
	add_child(world)
	traffic = TrafficScript.new()
	traffic.world = world
	add_child(traffic)
	player = PlayerScript.new()
	add_child(player)
	traffic.player_node = player
	traffic.debug = "--sigdbg" in OS.get_cmdline_user_args()
	traffic.player_cars = cars
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 4500
	add_child(cam)
	atmos = AtmosScript.new()
	add_child(atmos)
	atmos.setup(env, sun, moon, cam, world)
	atmos.place_info.connect(_on_place_info)
	atmos.time_mode = arg_tm
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.setup(self, atmos, traffic, world, player)
	apply_settings()
	if dump_dir != "":
		sfx.dump(dump_dir)
		set_process(false)
		get_tree().quit()
		return
	_hud()
	world.center_ready.connect(_on_center_ready)
	_go(lat, lon)


func _go(la: float, lo: float) -> void:
	loading = true
	lat = la
	lon = lo
	for c in cars:
		c.queue_free()
	cars.clear()
	driving = null
	traffic.enabled = false
	traffic.clear()
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	settings.d.lat = la
	settings.d.lon = lo
	settings.d.has_loc = true
	settings.save()
	overlay.modulate.a = 1.0
	overlay.visible = true
	world.teleport(la, lo)
	atmos.set_location(la, lo)
	if arg_wx > 0:
		atmos.set_weather_override(arg_wx)


func _on_center_ready() -> void:
	# 가장 가까운 도로 옆에 서고, 그 도로 위에 내 차를 세운다(도로가 없으면 원점)
	var ppos := Vector3(0, world.height_at(Vector3.ZERO) + 1.0, 0)
	var cpos := Vector3(5.0, 0.0, 3.0)
	var chead := 0.0
	var rn: RefCounted = world.net_roads
	var nid: int = rn.nearest(Vector3.ZERO, 400.0, ["major", "minor"])
	if nid != -1:
		var e: Array = rn.alive_out(nid, ["major", "minor"])[0]
		var p0: Vector3 = rn.nodes[nid].p
		var p1: Vector3 = rn.nodes[e[0]].p
		var d := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
		var right := Vector2(-d.y, d.x)
		chead = atan2(-d.x, -d.y)
		cpos = Vector3(p0.x + right.x * 2.2, p0.y + 0.8, p0.z + right.y * 2.2)
		# 도로 양옆 중 건물 안이 아닌 곳에 선다(둘 다 막히면 도로 위)
		var found := false
		for off in [3.0, 1.6, 5.5]:
			for sd in [1.0, -1.0]:
				var d_: float = float(e[1]) * 0.5 + off
				var sx: float = p0.x + right.x * d_ * sd
				var sz: float = p0.z + right.y * d_ * sd
				if not world.inside_building(Vector3(sx, 0, sz), 1.2):
					ppos = Vector3(sx, world.height_at(Vector3(sx, 0, sz)) + 1.0, sz)
					found = true
					break
			if found:
				break
		if not found:
			ppos = Vector3(p0.x, p0.y + 1.0, p0.z)
	player.global_position = ppos
	player.velocity = Vector3.ZERO
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.arrive()
	var c: CharacterBody3D = CarScript.new()
	add_child(c)
	c.setup("res://assets/cars/sedan-sports.glb", cpos, chead)
	player_spots = LightsScript.attach(c, true)
	cars.append(c)
	# 처음 시점: 플레이어가 차를 바라보게(카메라가 차 안으로 들어가지 않도록 반대편에 둠)
	var tc := Vector2(cpos.x - ppos.x, cpos.z - ppos.z)
	if tc.length() > 0.1:
		tc = tc.normalized()
		yaw = atan2(-tc.x, -tc.y)
	pitch = 0.3
	traffic.enabled = true
	loading = false
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): overlay.visible = false)


func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = PhysicalSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.85)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_density = 0.0004
	env.fog_light_color = Color(0.7, 0.78, 0.9)
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.shadow_enabled = false
	add_child(moon)


func _on_place_info(city: String, country: String, left: bool) -> void:
	if city != "" or country != "":
		place_name = ("%s, %s" % [city, country]) if city != "" else country
	traffic.side = -1.0 if left else 1.0
	settings.d.place = place_name
	settings.save()


func _hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(hud)
	search = LineEdit.new()
	search.placeholder_text = "도시/장소 검색 (예: 파리, Tokyo, 울산) — Enter"
	search.position = Vector2(16, 80)
	search.custom_minimum_size = Vector2(420, 36)
	search.visible = false
	search.text_submitted.connect(_on_search)
	cl.add_child(search)
	map_ui = MapScript.new()
	map_ui.net = world.net
	map_ui.visible = false
	map_ui.chosen.connect(_on_map_chosen)
	cl.add_child(map_ui)
	# 불러오는 중 화면
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.03, 0.05, 0.09, 0.92)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(overlay)
	var ovb := VBoxContainer.new()
	ovb.set_anchors_preset(Control.PRESET_CENTER)
	ovb.custom_minimum_size = Vector2(520, 0)
	ovb.position = Vector2(-260, -40)
	overlay.add_child(ovb)
	var t := Label.new()
	t.text = "EARTH CITY"
	t.add_theme_font_size_override("font_size", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovb.add_child(t)
	ov_label = Label.new()
	ov_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovb.add_child(ov_label)
	ov_bar = ProgressBar.new()
	ov_bar.max_value = 9
	ov_bar.show_percentage = false
	ovb.add_child(ov_bar)
	menu = MenuScript.new()
	cl.add_child(menu)
	menu.build(self, settings)


func _on_map_chosen(la: float, lo: float, nm: String) -> void:
	place_name = nm
	_go(la, lo)


func _on_search(q: String) -> void:
	search.visible = false
	search.release_focus()
	if q.strip_edges() == "":
		return
	var body: PackedByteArray = await world.net.fetch(GEOCODE % q.strip_edges().uri_encode(), false)
	var j = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary and j.has("results") and j["results"].size() > 0:
		var r: Dictionary = j["results"][0]
		place_name = "%s, %s" % [r.get("name", ""), r.get("country", "")]
		_go(float(r["latitude"]), float(r["longitude"]))
	else:
		place_name = "'%s' 를 찾지 못했습니다" % q


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch + e.relative.y * 0.003, -0.2, 1.2)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			if map_ui.visible:
				map_ui.visible = false
			elif search.visible:
				search.visible = false
			else:
				menu.open()
		elif e.keycode == KEY_M:
			if map_ui.visible:
				map_ui.visible = false
			else:
				var cur: Vector2 = world.geo.local_to_ll(player.global_position)
				map_ui.open(cur.x, cur.y)
		elif e.keycode == KEY_SLASH:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			search.text = ""
			search.visible = true
			search.call_deferred("grab_focus")
		elif e.keycode == KEY_E:
			_toggle_car()
		elif e.keycode == KEY_G:
			player.drunk = not player.drunk
		elif e.keycode == KEY_T:
			atmos.cycle_time()
		elif e.keycode == KEY_N:
			settings.d.mute = not settings.d.mute
			settings.save()
			apply_settings()
		elif e.keycode == KEY_K:
			atmos.cycle_weather()
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_X:
				_toggle_car()
			JOY_BUTTON_Y:
				open_map()
			JOY_BUTTON_START:
				menu.open()


func open_map() -> void:
	if map_ui.visible:
		map_ui.visible = false
		return
	var cur: Vector2 = world.geo.local_to_ll(player.global_position)
	map_ui.open(cur.x, cur.y)


func apply_settings() -> void:
	var s: Dictionary = settings.d
	sun.shadow_enabled = s.shadows
	env.ssao_enabled = s.ssao
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(s.msaa)]
	get_viewport().scaling_3d_scale = float(s.scale)
	traffic.max_cars = int(26.0 * float(s.traffic))
	traffic.max_peds = int(14.0 * float(s.traffic))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s.volume), 0.0001)))
	AudioServer.set_bus_mute(0, bool(s.mute))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	world.show_trees = s.trees
	get_tree().call_group("trees", "set_visible", s.trees)


func _toggle_car() -> void:
	if driving:
		var c := driving
		driving = null
		c.occupied = false
		player.global_position = c.global_position + c.global_transform.basis.x * -2.4 + Vector3(0, 0.5, 0)
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		var best: CharacterBody3D = null
		var bd := 5.0
		for c in cars:
			var d: float = c.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = c
		if best:
			driving = best
			best.occupied = true
			player.visible = false
			player.process_mode = Node.PROCESS_MODE_DISABLED
			yaw = best.heading


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	var kf := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	var kr := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var run_btn := Input.is_key_pressed(KEY_SHIFT)
	var jump_btn := Input.is_key_pressed(KEY_SPACE)
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var id: int = pads[0]
		var lx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
		var rt := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)
		if absf(lx) > 0.2:
			kr += lx
		if absf(ly) > 0.2:
			kf -= ly
		if driving:
			kf += rt - lt
		if absf(rx) > 0.2:
			yaw -= rx * dt * 2.6
		if absf(ry) > 0.2:
			pitch = clampf(pitch + ry * dt * 1.8, -0.2, 1.2)
		kf = clampf(kf, -1.0, 1.0)
		kr = clampf(kr, -1.0, 1.0)
		run_btn = run_btn or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
		jump_btn = jump_btn or Input.is_joy_button_pressed(id, JOY_BUTTON_A)
	if force_walk > 0.0 and not loading:
		kf = 1.0
	if search.visible or map_ui.visible:
		kf = 0.0
		kr = 0.0
	var target := Vector3(0, 1.4, 0)
	if not loading:
		if driving:
			driving.drive(dt, kf, -kr, jump_btn)
			yaw = lerp_angle(yaw, driving.heading, 1.0 - exp(-2.5 * dt))
			target = driving.global_position + Vector3(0, 1.2, 0)
		else:
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var dir := fwd * kf + right * kr
			if dir.length() > 1.0:
				dir = dir.normalized()
			player.clap = Input.is_key_pressed(KEY_C)
			player.move(dt, dir, run_btn or force_run, jump_btn)
			target = player.global_position + Vector3(0, 1.4, 0)
		for c in cars:
			if c != driving:
				c.drive(dt, 0.0, 0.0, false)
		# 원점에서 8km 넘게 멀어지면 그 자리를 새 원점으로 다시 불러옴(실수 정밀도 유지)
		if not loading and Vector2(target.x, target.z).length() > 8000.0:
			var ll: Vector2 = world.geo.local_to_ll(target)
			_go(ll.x, ll.y)
			return
		world.update(target)
		traffic.focus = target
		traffic.night = atmos.night
	else:
		target = Vector3(0, world.height_at(Vector3.ZERO) + 30.0, 0)
	var dist := 7.5 if driving else 4.2
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var want := target + off
	if not loading:
		for f in [1.0, 0.75, 0.55, 0.38, 0.25, 0.15]:
			want = target + off * f
			if not world.inside_building(Vector3(want.x, 0, want.z), 0.0):
				break
	if not loading:
		# 카메라가 건물/지형을 뚫지 않게: 대상에서 카메라 쪽으로 레이를 쏴서 막히면 그 앞에 둠
		var q := PhysicsRayQueryParameters3D.create(target, want, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = hit["position"] + (target - want).normalized() * 0.35
	cam.global_position = want
	cam.look_at(target, Vector3.UP)
	var ll: Vector2 = world.geo.local_to_ll(target)
	var spd := absf(driving.speed) * 3.6 if driving else 0.0
	hud.text = "EARTH CITY · %s%s\n%.4f, %.4f · %s · WASD 이동 · Shift 달리기 · E 탑승 · / 장소검색 · T 시간 · K 날씨 · M 세계지도 · H 경적 · N 음소거 · G 술취한 걸음 · C 박수%s" % [place_name if place_name != "" else "시작 위치", "  (지도 불러오는 중...)" if loading else "", ll.x, ll.y, atmos.status_text(), ("   %d km/h" % spd) if driving else ""]
	if overlay.visible and loading:
		ov_bar.value = world.chunks.size()
		var warn := "\n인터넷 연결을 확인하세요" if world.chunks.is_empty() and frames > 1500 else ""
		ov_label.text = "%s · 지도를 불러오는 중 (%d/9)%s" % [place_name if place_name != "" else "시작 위치", world.chunks.size(), warn]
	atmos.update(dt)
	sfx.update(dt)
	var sp_e: float = 7.0 * atmos.night if driving else 0.0
	for sl in player_spots:
		sl.light_energy = sp_e
	if loaded_frames == 300 and "--fps" in OS.get_cmdline_user_args():
		print("FPS ", Engine.get_frames_per_second())
	if loaded_frames == 20 and "--moondbg" in OS.get_cmdline_user_args():
		print("MOON phase=", atmos.moon_phase, " el=", atmos.moon_el, " az=", atmos.moon_az, " sun_el=", atmos.el)
	frames += 1
	if map_test >= 0 and not loading and loaded_frames == 5:
		var cur2: Vector2 = world.geo.local_to_ll(player.global_position)
		map_ui.open(cur2.x, cur2.y)
		map_ui.zoom = maxi(map_test, 2)
	if not loading:
		loaded_frames += 1
	if shot_path != "":
		if shot_cam != "" and not loading:
			var p := shot_cam.split(",")
			var gh: float = world.height_at(Vector3.ZERO)
			cam.global_position = Vector3(p[0].to_float(), gh + p[1].to_float(), p[2].to_float())
			cam.look_at(Vector3(p[3].to_float(), gh + p[4].to_float(), p[5].to_float()), Vector3.UP)
		if loaded_frames >= shot_frame and not loading:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
