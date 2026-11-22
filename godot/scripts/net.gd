extends Node
# HTTP 가져오기 + 디스크 캐시(user://cache). 동시 요청 수 제한.

const MAX_ACTIVE := 6
var active := 0
const UA := "UlsanCityGame/0.1"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")


func fetch(url: String, use_cache := true) -> PackedByteArray:
	var cp := "user://cache/" + url.md5_text()
	if use_cache and FileAccess.file_exists(cp):
		return FileAccess.get_file_as_bytes(cp)
	for attempt in 3:
		while active >= MAX_ACTIVE:
			await get_tree().process_frame
		active += 1
		var req := HTTPRequest.new()
		req.timeout = 30.0
		add_child(req)
		var err := req.request(url, PackedStringArray(["User-Agent: " + UA]))
		if err != OK:
			req.queue_free()
			active -= 1
			continue
		var res: Array = await req.request_completed
		req.queue_free()
		active -= 1
		if res[0] == HTTPRequest.RESULT_SUCCESS:
			if res[1] == 200:
				var body: PackedByteArray = res[3]
				if use_cache:
					var f := FileAccess.open(cp, FileAccess.WRITE)
					if f:
						f.store_buffer(body)
				return body
			if res[1] == 404 or res[1] == 204:
				return PackedByteArray()
	return PackedByteArray()
