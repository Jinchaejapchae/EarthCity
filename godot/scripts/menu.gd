extends Control
# ESC 일시정지 메뉴: 음량/화질/교통량/전체화면 설정, 세계지도/종료. 게임을 멈추고(트리 일시정지) 열린다.

var main: Node
var settings: RefCounted
var panel: PanelContainer


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func build(main_: Node, settings_: RefCounted) -> void:
	main = main_
	settings = settings_
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 0)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "EARTH CITY — 일시정지"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	_button(vb, "계속하기 (Esc)", close)
	_button(vb, "세계지도로 이동 (M)", func():
		close()
		main.open_map())
	var s: Dictionary = settings.d
	_slider(vb, "음량", 0.0, 1.0, 0.05, s.volume, func(v): _apply_opt("volume", v))
	_check(vb, "음소거", s.mute, func(v): _apply_opt("mute", v))
	_check(vb, "그림자", s.shadows, func(v): _apply_opt("shadows", v))
	_check(vb, "화면 구석 음영 (SSAO)", s.ssao, func(v): _apply_opt("ssao", v))
	_check(vb, "나무 표시", s.trees, func(v): _apply_opt("trees", v))
	_check(vb, "전체화면", s.fullscreen, func(v): _apply_opt("fullscreen", v))
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var l := Label.new()
	l.text = "안티앨리어싱  "
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.add_item("끄기", 0)
	ob.add_item("2배", 1)
	ob.add_item("4배", 2)
	ob.select(int(s.msaa))
	ob.item_selected.connect(func(i): _apply_opt("msaa", i))
	hb.add_child(ob)
	_slider(vb, "해상도 배율 (낮추면 빨라짐)", 0.5, 1.0, 0.05, s.scale, func(v): _apply_opt("scale", v))
	_slider(vb, "교통/보행자 수", 0.0, 1.5, 0.1, s.traffic, func(v): _apply_opt("traffic", v))
	var help := Label.new()
	help.text = "WASD 이동 · Shift 달리기 · E 탑승/하차 · Space 점프/브레이크 · H 경적\n/ 장소 검색 · M 세계지도 · G 술취한 걸음 · C 박수\n게임패드: 왼쪽 스틱 이동, 오른쪽 스틱 시점, A 점프, X 탑승, Y 지도,\nRT/LT 가속/브레이크, RB 달리기, Start 메뉴"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(help)
	_button(vb, "게임 종료", func(): main.get_tree().quit())


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _check(parent: Node, text: String, v: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = v
	c.toggled.connect(cb)
	parent.add_child(c)


func _slider(parent: Node, text: String, mn: float, mx: float, st: float, v: float, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(210, 0)
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = st
	sl.value = v
	sl.custom_minimum_size = Vector2(220, 0)
	sl.value_changed.connect(cb)
	hb.add_child(sl)


func _apply_opt(key: String, v: Variant) -> void:
	settings.d[key] = v
	settings.save()
	main.apply_settings()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif visible and e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START:
		close()


func open() -> void:
	visible = true
	main.get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	main.get_tree().paused = false
