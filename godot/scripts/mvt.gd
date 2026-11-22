extends RefCounted
# Mapbox Vector Tile(.pbf) 디코더. decode(bytes, 원하는 레이어 이름들) -> { 레이어: {extent, features:[{type, props, lines|polys}]} }
# type 2: lines = Array[PackedVector2Array], type 3: polys = Array[{o: PackedVector2Array, h: Array[PackedVector2Array]}]

var buf := PackedByteArray()
var pos := 0


func _varint() -> int:
	var r := 0
	var shift := 0
	while pos < buf.size():
		var b := buf[pos]
		pos += 1
		r |= (b & 0x7f) << shift
		if b < 0x80:
			break
		shift += 7
	return r


func _skip(wt: int) -> void:
	match wt:
		0: _varint()
		1: pos += 8
		2: pos += _varint()
		5: pos += 4
		_: pos = buf.size()


func _str(n: int) -> String:
	var s := buf.slice(pos, pos + n).get_string_from_utf8()
	pos += n
	return s


func decode(bytes: PackedByteArray, want: Array) -> Dictionary:
	buf = bytes
	pos = 0
	var out := {}
	while pos < buf.size():
		var tag := _varint()
		if (tag >> 3) == 3 and (tag & 7) == 2:
			var n := _varint()
			var end := pos + n
			_layer(end, want, out)
			pos = end
		else:
			_skip(tag & 7)
	return out


func _layer(end: int, want: Array, out: Dictionary) -> void:
	var lname := ""
	var extent := 4096
	var keys: Array = []
	var vals: Array = []
	var feats: Array = []
	while pos < end:
		var tag := _varint()
		var field := tag >> 3
		var wt := tag & 7
		if field == 1 and wt == 2:
			lname = _str(_varint())
		elif field == 2 and wt == 2:
			var n := _varint()
			feats.append(Vector2i(pos, pos + n))
			pos += n
		elif field == 3 and wt == 2:
			keys.append(_str(_varint()))
		elif field == 4 and wt == 2:
			var n := _varint()
			vals.append(_value(pos + n))
		elif field == 5 and wt == 0:
			extent = _varint()
		else:
			_skip(wt)
	if not want.has(lname):
		return
	var list: Array = []
	for f in feats:
		list.append(_feature(f.x, f.y, keys, vals))
	out[lname] = {"extent": extent, "features": list}


func _value(end: int) -> Variant:
	var v: Variant = null
	while pos < end:
		var tag := _varint()
		var field := tag >> 3
		var wt := tag & 7
		if field == 1 and wt == 2:
			v = _str(_varint())
		elif field == 2 and wt == 5:
			v = buf.decode_float(pos)
			pos += 4
		elif field == 3 and wt == 1:
			v = buf.decode_double(pos)
			pos += 8
		elif field == 4 or field == 5:
			v = _varint()
		elif field == 6:
			var z := _varint()
			v = (z >> 1) ^ -(z & 1)
		elif field == 7:
			v = _varint() != 0
		else:
			_skip(wt)
	pos = end
	return v


func _feature(start: int, end: int, keys: Array, vals: Array) -> Dictionary:
	pos = start
	var props := {}
	var type := 0
	var gs := -1
	var ge := 0
	while pos < end:
		var tag := _varint()
		var field := tag >> 3
		var wt := tag & 7
		if field == 2 and wt == 2:
			var n := _varint()
			var e := pos + n
			while pos < e:
				var ki := _varint()
				var vi := _varint()
				if ki < keys.size() and vi < vals.size():
					props[keys[ki]] = vals[vi]
		elif field == 3 and wt == 0:
			type = _varint()
		elif field == 4 and wt == 2:
			var n := _varint()
			gs = pos
			ge = pos + n
			pos += n
		else:
			_skip(wt)
	var f := {"type": type, "props": props}
	if gs >= 0 and type >= 2:
		var rings := _geometry(gs, ge, type)
		if type == 2:
			f["lines"] = rings
		else:
			f["polys"] = _group(rings)
	return f


func _geometry(s: int, e: int, type: int) -> Array:
	var rings: Array = []
	var cur := PackedVector2Array()
	var x := 0
	var y := 0
	pos = s
	while pos < e:
		var cmd := _varint()
		var id := cmd & 7
		var cnt := cmd >> 3
		if id == 7:
			if cur.size() > 0:
				rings.append(cur)
				cur = PackedVector2Array()
		else:
			for i in cnt:
				var a := _varint()
				var b := _varint()
				x += (a >> 1) ^ -(a & 1)
				y += (b >> 1) ^ -(b & 1)
				if id == 1 and cur.size() > 0:
					rings.append(cur)
					cur = PackedVector2Array()
				cur.append(Vector2(x, y))
	if cur.size() > 0:
		rings.append(cur)
	return rings


static func _area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _group(rings: Array) -> Array:
	var polys: Array = []
	var first_sign := 0.0
	for r in rings:
		if r.size() < 3:
			continue
		var a := _area(r)
		if first_sign == 0.0:
			first_sign = signf(a)
		if signf(a) == first_sign or polys.is_empty():
			polys.append({"o": r, "h": []})
		else:
			polys[polys.size() - 1]["h"].append(r)
	return polys
