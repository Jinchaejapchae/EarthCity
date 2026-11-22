extends RefCounted
# 위경도 <-> 웹 메르카토르 <-> 게임 로컬 좌표. 로컬: +x 동쪽, -z 북쪽(= +z 남쪽), 원점 = 선택한 위치.

const C := 40075016.686
const R := C / (2.0 * PI)

var lat0 := 0.0
var lon0 := 0.0
var ox := 0.0
var oy := 0.0
var k := 1.0 # 메르카토르 미터 -> 실제 미터 보정(cos 위도)


func set_origin(lat: float, lon: float) -> void:
	lat0 = lat
	lon0 = lon
	var m := ll_to_merc(lat, lon)
	ox = m.x
	oy = m.y
	k = cos(deg_to_rad(lat))


static func ll_to_merc(lat: float, lon: float) -> Vector2:
	var s := sin(deg_to_rad(clampf(lat, -85.0511, 85.0511)))
	return Vector2(lon / 360.0 * C, R * 0.5 * log((1.0 + s) / (1.0 - s)))


static func merc_to_ll(m: Vector2) -> Vector2: # (lat, lon)
	return Vector2(rad_to_deg(2.0 * atan(exp(m.y / R)) - PI / 2.0), m.x / C * 360.0)


func local_to_ll(p: Vector3) -> Vector2:
	return merc_to_ll(Vector2(p.x / k + ox, -p.z / k + oy))


func tile_of_local(p: Vector3, z: int) -> Vector2i:
	var mx := p.x / k + ox
	var my := -p.z / k + oy
	var n := pow(2.0, z)
	return Vector2i(int(floor((mx / C + 0.5) * n)), int(floor((0.5 - my / C) * n)))


func tile_size(z: int) -> float:
	return C / pow(2.0, z) * k


## 타일 중심의 로컬 좌표
func tile_center(z: int, tx: int, ty: int) -> Vector3:
	var n := pow(2.0, z)
	var mx := ((tx + 0.5) / n - 0.5) * C
	var my := (0.5 - (ty + 0.5) / n) * C
	return Vector3((mx - ox) * k, 0.0, -(my - oy) * k)
