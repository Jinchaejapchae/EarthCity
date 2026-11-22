extends RefCounted
# 설정과 마지막 위치를 user://settings.cfg 에 저장

const PATH := "user://settings.cfg"

var d := {
	"lat": 35.5384, "lon": 129.3114, "place": "", "has_loc": false,
	"volume": 0.8, "mute": false,
	"shadows": true, "ssao": true, "msaa": 1, "scale": 1.0, "trees": true, "traffic": 1.0, "fullscreen": false,
}


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in d.keys():
		d[k] = cfg.get_value("s", k, d[k])


func save() -> void:
	var cfg := ConfigFile.new()
	for k in d.keys():
		cfg.set_value("s", k, d[k])
	cfg.save(PATH)
