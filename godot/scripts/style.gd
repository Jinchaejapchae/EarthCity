extends RefCounted
# 지역 스타일: 위경도로 문화권(region, 건물/지붕/차 색)과 기후대(biome, 땅/식생/물 색)를 정한다.
#
# region: 0 일반  1 동아시아  2 서유럽  3 지중해·북아프리카  4 북미  5 북유럽
#         6 남아시아  7 동남아  8 중남미  9 사하라 이남 아프리카  10 오세아니아  11 러시아·동유럽  12 아라비아·이란
# biome : 0 온대  1 열대  2 사막  3 지중해성(건조)  4 냉대(침엽수림)  5 극지/툰드라

const GROUND := [
	Color(0.36, 0.41, 0.26), Color(0.18, 0.34, 0.12), Color(0.74, 0.62, 0.42),
	Color(0.5, 0.47, 0.3), Color(0.25, 0.31, 0.2), Color(0.58, 0.63, 0.58),
]
const GRASS := [
	Color(0.3, 0.45, 0.2), Color(0.2, 0.42, 0.1), Color(0.66, 0.57, 0.36),
	Color(0.5, 0.5, 0.28), Color(0.28, 0.37, 0.22), Color(0.55, 0.62, 0.55),
]
const WOOD := [
	Color(0.13, 0.27, 0.12), Color(0.06, 0.22, 0.07), Color(0.48, 0.44, 0.27),
	Color(0.28, 0.34, 0.18), Color(0.08, 0.19, 0.11), Color(0.42, 0.48, 0.42),
]
const FARM := [
	Color(0.5, 0.5, 0.28), Color(0.32, 0.5, 0.14), Color(0.6, 0.52, 0.32),
	Color(0.6, 0.52, 0.3), Color(0.45, 0.46, 0.27), Color(0.5, 0.55, 0.5),
]
const PARK := [
	Color(0.27, 0.46, 0.2), Color(0.18, 0.45, 0.12), Color(0.38, 0.5, 0.25),
	Color(0.36, 0.48, 0.22), Color(0.26, 0.4, 0.2), Color(0.45, 0.55, 0.42),
]
const WATER := [
	Color(0.1, 0.27, 0.36, 0.82), Color(0.04, 0.4, 0.44, 0.78), Color(0.08, 0.36, 0.4, 0.8),
	Color(0.07, 0.3, 0.4, 0.8), Color(0.08, 0.2, 0.27, 0.84), Color(0.12, 0.28, 0.34, 0.85),
]
# 눈선(m) = 5000 - |위도| * 60  (적도 5000m, 45도 2300m, 70도 800m)
const SNOW_A := 5000.0
const SNOW_B := 60.0

# 경사진 지붕 비율(나머지는 평지붕)
const PITCH := [1.0, 1.0, 1.0, 0.3, 1.0, 1.0, 0.1, 0.8, 0.5, 0.7, 1.0, 0.8, 0.0]
# 경사 지붕 색
const ROOF := [
	Color(0.32, 0.27, 0.25), Color(0.28, 0.3, 0.33), Color(0.55, 0.26, 0.16), Color(0.7, 0.36, 0.2),
	Color(0.32, 0.3, 0.3), Color(0.5, 0.15, 0.1), Color(0.5, 0.5, 0.47), Color(0.62, 0.3, 0.14),
	Color(0.62, 0.3, 0.2), Color(0.45, 0.28, 0.2), Color(0.55, 0.22, 0.16), Color(0.25, 0.4, 0.28),
	Color(0.7, 0.62, 0.48),
]
# 차 색(RGB 곱셈 색): 지역마다 흔한 색이 다르다
const CAR_COLORS := {
	1: [Color(1, 1, 1), Color(1, 1, 1), Color(0.35, 0.35, 0.38), Color(0.72, 0.72, 0.76), Color(0.2, 0.2, 0.22), Color(0.9, 0.9, 0.95)],
	6: [Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1), Color(0.72, 0.72, 0.76), Color(0.4, 0.4, 0.45), Color(0.85, 0.3, 0.3)],
	12: [Color(1, 1, 1), Color(1, 1, 1), Color(0.2, 0.2, 0.22), Color(0.72, 0.72, 0.76), Color(0.9, 0.85, 0.7)],
	2: [Color(0.4, 0.4, 0.43), Color(0.2, 0.2, 0.22), Color(0.75, 0.75, 0.78), Color(0.35, 0.45, 0.75), Color(1, 1, 1), Color(0.8, 0.3, 0.25)],
	4: [Color(1, 1, 1), Color(0.25, 0.25, 0.27), Color(0.75, 0.75, 0.78), Color(0.8, 0.2, 0.2), Color(0.3, 0.45, 0.8), Color(0.55, 0.55, 0.58)],
	7: [Color(1, 1, 1), Color(0.75, 0.75, 0.78), Color(0.25, 0.25, 0.27), Color(0.85, 0.35, 0.3), Color(0.9, 0.8, 0.3)],
	8: [Color(1, 1, 1), Color(0.75, 0.75, 0.78), Color(0.85, 0.3, 0.25), Color(0.3, 0.45, 0.8), Color(0.9, 0.8, 0.3), Color(0.25, 0.25, 0.27)],
	9: [Color(1, 1, 1), Color(1, 1, 1), Color(0.75, 0.75, 0.78), Color(0.85, 0.7, 0.3), Color(0.35, 0.4, 0.6)],
	11: [Color(0.75, 0.75, 0.78), Color(0.25, 0.25, 0.27), Color(1, 1, 1), Color(0.5, 0.55, 0.6), Color(0.35, 0.5, 0.35)],
}


static func region_of(la: float, lo: float) -> int:
	if lo > 95.0 and lo < 146.0 and la > 18.0 and la < 55.0:
		return 1
	if lo > 92.0 and lo < 142.0 and la > -11.0 and la <= 24.0:
		return 7
	if lo > 60.0 and lo <= 92.0 and la > 5.0 and la < 37.0:
		return 6
	if la >= 55.0 and lo > -25.0 and lo < 32.0:
		return 5
	if la > 43.0 and lo >= 23.0 and lo < 180.0:
		return 11
	if la > 35.0 and la < 72.0 and lo > -12.0 and lo < 23.0:
		return 2
	if la > 12.0 and la < 40.0 and lo >= 35.0 and lo < 63.0 and not (la > 37.0 and lo < 45.0):
		return 12
	if la > 12.0 and la < 42.0 and lo > -18.0 and lo < 45.0:
		return 3
	if la > 35.0 and la < 45.0 and lo >= 23.0 and lo < 45.0:
		return 3
	if la > -36.0 and la <= 12.0 and lo > -20.0 and lo < 52.0:
		return 9
	if la > -48.0 and la < -10.0 and lo > 110.0 and lo < 180.0:
		return 10
	if lo > -120.0 and lo < -30.0 and la < 24.0:
		return 8
	if lo > -170.0 and lo < -30.0:
		return 4
	return 0


static func _in(la: float, lo: float, la0: float, la1: float, lo0: float, lo1: float) -> bool:
	return la >= la0 and la <= la1 and lo >= lo0 and lo <= lo1


static func biome_of(la: float, lo: float) -> int:
	var a := absf(la)
	if a >= 68.0 or (la >= 63.0 and lo > -25.0 and lo < -12.0):
		return 5
	if la < -62.0:
		return 5
	# 사막: 사하라, 아라비아, 이란/중앙아시아, 고비, 타클라마칸, 호주 내륙, 미국 남서부, 아타카마, 나미브/칼라하리, 타르
	if _in(la, lo, 15, 32, -17, 33) or _in(la, lo, 15, 32, 34, 60) or _in(la, lo, 25, 38, 54, 66) \
			or _in(la, lo, 38, 46, 90, 115) or _in(la, lo, 36, 41, 77, 90) or _in(la, lo, -32, -20, 120, 142) \
			or _in(la, lo, 30, 37, -118, -106) or _in(la, lo, 25, 31, -112, -103) or _in(la, lo, -30, -18, -71, -68) \
			or _in(la, lo, -29, -17, 12, 24) or _in(la, lo, 24, 29, 68, 73):
		return 2
	# 열대: 적도 부근, 동남아/남인도/남중국, 카리브/플로리다, 중앙아프리카, 아마존, 북호주
	if a < 15.0 or _in(la, lo, 15, 25, 72, 125) or _in(la, lo, 15, 28, -90, -60) or _in(la, lo, -23, 15, -75, -35) \
			or _in(la, lo, -10, 15, -20, 52) or _in(la, lo, -20, -10, 125, 150):
		return 1
	# 지중해성: 남유럽/북아프리카 해안, 터키·레반트, 캘리포니아, 칠레 중부, 남호주, 케이프타운
	if _in(la, lo, 30, 45, -10, 40) or _in(la, lo, 32, 38, -125, -117) or _in(la, lo, -38, -30, -75, -70) \
			or _in(la, lo, -38, -31, 114, 140) or _in(la, lo, -35, -32, 17, 22):
		return 3
	# 냉대: 북위 58도 이상, 대륙성 50~58도(러시아·캐나다)
	if a >= 58.0 or (la >= 50.0 and (lo >= 35.0 or lo <= -60.0)):
		return 4
	return 0


## 눈선 높이(m)
static func snowline(la: float) -> float:
	return maxf(SNOW_A - absf(la) * SNOW_B, 150.0)


static func car_tint(region: int, rng: RandomNumberGenerator) -> Color:
	if CAR_COLORS.has(region):
		var arr: Array = CAR_COLORS[region]
		var c: Color = arr[rng.randi() % arr.size()]
		return c
	return Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.7), rng.randf_range(0.7, 1.0)).lerp(Color.WHITE, 0.25)
