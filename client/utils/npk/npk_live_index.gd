class_name NpkLiveIndex
extends NpkIndex
## 直接扫 ImagePacks2 的“惰性”NPK 索引。
##
## 不做全量 16k 包扫描（实测 114 秒）。按资源路径猜包名：
##   map/hendonmyre/tile/hm01.img
##     → sprite_map_hendonmyre_tile.NPK
##     → sprite_map_hendonmyre.NPK
##     → sprite_map.NPK
## 找到包才读它的条目表，并把表缓存起来；查不到就返回空。
## 猜包规则来自 NPK 的命名习惯：sprite_<目录段用_连接>[_<子类>].NPK。

var dir := ""
var _packs: Dictionary = {}      # 小写文件名 -> 真实文件名
var _tables: Dictionary = {}     # 包名 -> Dictionary（名字 -> {offset,size}）
var _cache: Dictionary = {}      # 资源路径 -> 命中/空

func _init(p_dir := "") -> void:
	dir = p_dir
	count = 1
	if dir == "":
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.to_lower().ends_with(".npk"):
			_packs[f.to_lower()] = f


func find(path: String) -> Dictionary:
	var key := path.replace("\\", "/").to_lower().lstrip("/")
	if key.begins_with("sprite/"):
		key = key.substr(7)
	if _cache.has(key):
		return _cache[key]
	var segs := key.get_basename().split("/")
	for n in range(segs.size(), 0, -1):
		var name := "sprite_" + "_".join(segs.slice(0, n)) + ".npk"
		var real := str(_packs.get(name, ""))
		if real == "":
			continue
		var hit := _lookup(real, key)
		if not hit.is_empty():
			_cache[key] = hit
			return hit
	_cache[key] = {}
	return {}


func _lookup(pack: String, key: String) -> Dictionary:
	var table: Dictionary = _tables.get(pack, {})
	if table.is_empty():
		table = _read_table(pack)
		_tables[pack] = table
	var hit: Dictionary = table.get(key, {})
	if hit.is_empty() and key.contains("."):
		hit = table.get(key.trim_suffix("." + key.get_extension()), {})
	if hit.is_empty():
		return {}
	return {"pack": pack, "pack_id": 0, "offset": int(hit["o"]), "size": int(hit["s"])}


func _read_table(pack: String) -> Dictionary:
	var out: Dictionary = {}
	var path := dir.path_join(pack)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var magic := f.get_buffer(16).get_string_from_ascii()
	if magic != "NeoplePack_Bill":
		return out
	var cnt := f.get_32()
	if cnt <= 0 or cnt > 400000:
		return out
	var tab := f.get_buffer(cnt * 264)
	if tab.size() < cnt * 264:
		return out
	for i in cnt:
		var o := i * 264
		var off := tab.decode_s32(o)
		var size := tab.decode_s32(o + 4)
		var nm := ""
		for j in 255:
			var c := tab[o + 8 + j] ^ NpkIndex.XOR_TABLE[j]
			if c == 0:
				break
			nm += char(c)
		if nm == "":
			continue
		nm = nm.replace("\\", "/").to_lower().lstrip("/")
		if nm.begins_with("sprite/"):
			nm = nm.substr(7)
		out[nm] = {"o": off, "s": size}
	return out


func stats() -> Dictionary:
	return {"packs": _packs.size(), "tables": _tables.size(), "paths": _cache.size()}


func trim(keep := 8) -> void:
	while _tables.size() > keep:
		var k: String = _tables.keys()[0]
		_tables.erase(k)
