extends Control
# 세계 지도 화면: OSM 타일(슬리피 맵). 드래그=이동, 휠=확대/축소, 클릭=위치 선택, 더블클릭/[이동]=그곳으로 순간이동.
# 타일 © OpenStreetMap contributors (tile.openstreetmap.de 사용. tile.openstreetmap.org 는 이 PC 에서 연결 안 됨, CARTO 는 API 키 필요)

signal chosen(lat: float, lon: float, place: String)

const GeoScript := preload("res://scripts/geo.gd")
const TILE_URL := "https://tile.openstreetmap.de/%d/%d/%d.png"
const GEOCODE := "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=5&language=ko"
const CITIES := [
	["서울", 37.5665, 126.978], ["부산", 35.1796, 129.0756], ["울산", 35.5384, 129.3114], ["도쿄", 35.6762, 139.6503],
	["오사카", 34.6937, 135.5023], ["베이징", 39.9042, 116.4074], ["싱가포르", 1.3521, 103.8198], ["두바이", 25.2048, 55.2708],
	["파리", 48.8566, 2.3522], ["런던", 51.5074, -0.1278], ["로마", 41.9028, 12.4964], ["카이로", 30.0444, 31.2357],
	["케이프타운", -33.9249, 18.4241], ["뉴욕", 40.7128, -74.006], ["샌프란시스코", 37.7749, -122.4194], ["리우", -22.9068, -43.1729],
	["시드니", -33.8688, 151.2093],
]

var net: Node
var zoom := 4
var clat := 35.5
var clon := 129.3
var cur_lat := 0.0
var cur_lon := 0.0
var tiles := {}
var pending := {}
var dragging := false
var drag_dist := 0.0
var sel_ok := false
var sel_lat := 0.0
var sel_lon := 0.0
var sel_name := ""
var search: LineEdit
var info: Label
var result_box: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var vb := VBoxContainer.new()
	bar.add_child(vb)
	var row := HBoxContainer.new()
	vb.add_child(row)
	search = LineEdit.new()
	search.placeholder_text = "도시/장소 검색 (예: 파리, Tokyo, 마추픽추) — Enter"
	search.custom_minimum_size = Vector2(380, 0)
	search.text_submitted.connect(_search)
	row.add_child(search)
	_btn(row, "내 위치", func(): _focus(cur_lat, cur_lon, 12, "현재 위치"))
	_btn(row, "IP로 내 위치", _ip_locate)
	_btn(row, "여기로 이동", _go)
	_btn(row, "닫기 (M)", func(): visible = false)
	info = Label.new()
	info.text = "지도를 드래그하고 휠/두 손가락 스크롤/핀치(또는 +/- 키)로 확대한 뒤 클릭해서 위치를 고르세요. 더블클릭하면 바로 이동합니다."
	row.add_child(info)
	var flow := HFlowContainer.new()
	vb.add_child(flow)
	for c in CITIES:
		var cc: Array = c
		_btn(flow, cc[0], func(): _focus(cc[1], cc[2], 11, cc[0]))
	result_box = HBoxContainer.new()
	vb.add_child(result_box)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func open(lat: float, lon: float) -> void:
	cur_lat = lat
	cur_lon = lon
	clat = lat
	clon = lon
	zoom = 12
	sel_ok = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func _focus(lat: float, lon: float, z: int, nm: String) -> void:
	clat = lat
	clon = lon
	zoom = z
	sel_ok = true
	sel_lat = lat
	sel_lon = lon
	sel_name = nm
	queue_redraw()


func _go() -> void:
	if not sel_ok:
		sel_lat = clat
		sel_lon = clon
		sel_name = "%.3f, %.3f" % [clat, clon]
	visible = false
	chosen.emit(sel_lat, sel_lon, sel_name)


## 인터넷 주소(IP) 기반 대략적 위치(도시 수준). 버튼을 눌렀을 때만 외부 서비스(ipwho.is)에 요청
func _ip_locate() -> void:
	info.text = "내 위치를 찾는 중..."
	var body: PackedByteArray = await net.fetch("https://ipwho.is/", false)
	var j = JSON.parse_string(body.get_string_from_utf8())
	if j is Dictionary and j.get("success", false):
		_focus(float(j["latitude"]), float(j["longitude"]), 11, "%s, %s" % [j.get("city", ""), j.get("country", "")])
		info.text = "IP 기준 대략적인 위치입니다(도시 수준)."
	else:
		info.text = "IP 위치를 가져오지 못했습니다"


func _search(q: String) -> void:
	if q.strip_edges() == "":
		return
	var body: PackedByteArray = await net.fetch(GEOCODE % q.strip_edges().uri_encode(), false)
	var j = JSON.parse_string(body.get_string_from_utf8())
	for c in result_box.get_children():
		c.queue_free()
	if j is Dictionary and j.has("results"):
		var first := true
		for r in j["results"]:
			var nm := "%s, %s" % [r.get("name", ""), r.get("country", "")]
			var la := float(r["latitude"])
			var lo := float(r["longitude"])
			_btn(result_box, nm, func(): _focus(la, lo, 12, nm))
			if first:
				_focus(la, lo, 12, nm)
				first = false
	else:
		info.text = "'%s' 를 찾지 못했습니다" % q


# ---------------------------------------------------------------- 좌표 변환
func _n() -> float:
	return 256.0 * pow(2.0, zoom)


func ll_to_px(lat: float, lon: float) -> Vector2:
	var m := GeoScript.ll_to_merc(lat, lon)
	var n := _n()
	return Vector2((m.x / GeoScript.C + 0.5) * n, (0.5 - m.y / GeoScript.C) * n)


func px_to_ll(p: Vector2) -> Vector2:
	var n := _n()
	var py := clampf(p.y, 0.0, n)
	return GeoScript.merc_to_ll(Vector2((p.x / n - 0.5) * GeoScript.C, (0.5 - py / n) * GeoScript.C))


# ---------------------------------------------------------------- 그리기
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.13, 0.18))
	var cpx := ll_to_px(clat, clon)
	var tl := cpx - size / 2.0
	var tn := 1 << zoom
	var x0 := floori(tl.x / 256.0)
	var x1 := floori((tl.x + size.x) / 256.0)
	var y0 := maxi(floori(tl.y / 256.0), 0)
	var y1 := mini(floori((tl.y + size.y) / 256.0), tn - 1)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var wx := posmod(tx, tn)
			var key := "%d/%d/%d" % [zoom, wx, ty]
			var pos := Vector2(tx * 256, ty * 256) - tl
			if tiles.has(key):
				draw_texture_rect(tiles[key], Rect2(pos, Vector2(256, 256)), false)
			else:
				_request(key)
				for dz in range(1, 5): # 확대 중에는 낮은 줌 타일을 늘려서 임시로 보여줌
					if zoom - dz < 0:
						break
					var pk := "%d/%d/%d" % [zoom - dz, wx >> dz, ty >> dz]
					if tiles.has(pk):
						var s := 256.0 / float(1 << dz)
						var src := Rect2(float(wx & ((1 << dz) - 1)) * s, float(ty & ((1 << dz) - 1)) * s, s, s)
						draw_texture_rect_region(tiles[pk], Rect2(pos, Vector2(256, 256)), src)
						break
	if cur_lat != 0.0 or cur_lon != 0.0:
		var cp := ll_to_px(cur_lat, cur_lon) - tl
		draw_circle(cp, 7.0, Color(0.1, 0.5, 1.0))
		draw_arc(cp, 9.0, 0, TAU, 24, Color.WHITE, 2.0)
	if sel_ok:
		var sp := ll_to_px(sel_lat, sel_lon) - tl
		draw_circle(sp, 8.0, Color(1.0, 0.25, 0.2))
		draw_arc(sp, 11.0, 0, TAU, 24, Color.WHITE, 2.5)
		var f := ThemeDB.fallback_font
		draw_string(f, sp + Vector2(14, 5), sel_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 300, size.y - 8), "© OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))


func _request(key: String) -> void:
	if pending.has(key) or net == null:
		return
	pending[key] = true
	var p := key.split("/")
	var bytes: PackedByteArray = await net.fetch(TILE_URL % [int(p[0]), int(p[1]), int(p[2])])
	pending.erase(key)
	if bytes.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			if tiles.size() > 400:
				tiles.clear()
			tiles[key] = ImageTexture.create_from_image(img)
			queue_redraw()


# ---------------------------------------------------------------- 입력
var gesture_acc := 0.0


## 마우스(m) 아래 지점을 고정한 채 한 단계 확대(+1)/축소(-1)
func _zoom_at(dz: int, m: Vector2) -> void:
	var nz := clampi(zoom + dz, 2, 17)
	if nz == zoom:
		return
	var under := px_to_ll(ll_to_px(clat, clon) + m - size / 2.0)
	zoom = nz
	var c2 := px_to_ll(ll_to_px(under.x, under.y) - (m - size / 2.0))
	clat = c2.x
	clon = c2.y
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_EQUAL or e.keycode == KEY_PLUS or e.keycode == KEY_KP_ADD):
		_zoom_at(1, size / 2.0)
		return
	if e is InputEventKey and e.pressed and (e.keycode == KEY_MINUS or e.keycode == KEY_KP_SUBTRACT):
		_zoom_at(-1, size / 2.0)
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				dragging = true
				drag_dist = 0.0
				if e.double_click:
					var ll := px_to_ll(ll_to_px(clat, clon) + e.position - size / 2.0)
					sel_ok = true
					sel_lat = ll.x
					sel_lon = ll.y
					sel_name = "%.3f, %.3f" % [ll.x, ll.y]
					_go()
			else:
				if dragging and drag_dist < 6.0:
					var ll := px_to_ll(ll_to_px(clat, clon) + e.position - size / 2.0)
					sel_ok = true
					sel_lat = ll.x
					sel_lon = ll.y
					sel_name = "%.3f, %.3f" % [ll.x, ll.y]
					queue_redraw()
				dragging = false
	# 맥 매직마우스/트랙패드: 두 손가락 스크롤(PanGesture)과 핀치(MagnifyGesture)
	elif e is InputEventMagnifyGesture:
		gesture_acc += log(e.factor) / log(1.35)
		while gesture_acc >= 1.0:
			_zoom_at(1, e.position)
			gesture_acc -= 1.0
		while gesture_acc <= -1.0:
			_zoom_at(-1, e.position)
			gesture_acc += 1.0
	elif e is InputEventPanGesture:
		gesture_acc += -e.delta.y * 0.6
		while gesture_acc >= 1.0:
			_zoom_at(1, get_local_mouse_position())
			gesture_acc -= 1.0
		while gesture_acc <= -1.0:
			_zoom_at(-1, get_local_mouse_position())
			gesture_acc += 1.0
	elif e is InputEventMouseMotion and dragging:
		drag_dist += e.relative.length()
		var c2 := px_to_ll(ll_to_px(clat, clon) - e.relative)
		clat = c2.x
		clon = c2.y
		queue_redraw()
