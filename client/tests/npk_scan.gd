extends SceneTree
## 批量扫描世界内容引用到的 IMG：地砖、装饰/背景动画、NPC 脸/动画、怪物、被动对象。
## 目标是找出“解码失败/退化成 1×1/帧为空”的资源；位置偏移不在这里判断。

const NPK_DIR := "/mnt/d/dnf_latest/ImagePacks2"
var _content: LivePvfContent
var _store: NpkStore
var _seen := {}
var _bad := []
var _total := 0
var _decoded := 0
var _frames := 0
var _started := 0


func _init() -> void:
	_started = Time.get_ticks_msec()
	_content = LivePvfContent.new()
	_content.load_index()
	_store = NpkStore.new(NPK_DIR)
	_store.open_live()
	for t in _content.index.get("towns", []):
		var td = _content.town(str(t.get("key", "")))
		if td == null: continue
		for i in td.area_count():
			var mp: String = str(td.map_of(i))
			if mp == "": continue
			_scan_map(mp)
	print("SCAN images=%d decoded=%d frames=%d bad=%d ms=%d" % [
		_total, _decoded, _frames, _bad.size(), Time.get_ticks_msec() - _started])
	for b in _bad.slice(0, 120): print("BAD ", b)
	quit(0 if _bad.is_empty() else 1)


func _scan_map(mp: String) -> void:
	var r: MapRoom = _content.map_room(mp)
	if r == null: return
	var tds: Dictionary = _content.tiles_for(r)
	for k in tds.keys():
		var td: TileDef = tds[k]
		_add_img(td.img, td.frame, "tile:" + mp)
	for ext in r.extended_tiles:
		var etd: TileDef = _content.tile(str(ext))
		if etd != null: _add_img(etd.img, etd.frame, "ext:" + mp)
	_scan_anims(r.anims, "ani:" + mp)
	_scan_anims(r.background_anims, "bg:" + mp)
	for n in r.npcs:
		if n is Dictionary: _scan_npc(int(n.get("id", 0)))
		else: _scan_npc(int(n))
	for m in r.monsters:
		if m is Dictionary: _scan_monster(int(m.get("id", 0)))
	for o in r.objects:
		if o is Dictionary: _scan_object(str(o.get("obj", "")))
	for a in r.town_movable_anim:
		if a is Dictionary:
			for k in ["basic", "open", "loop", "close"]:
				_scan_one_ani(str(a.get(k, "")), "movA:" + mp)


func _scan_anims(list: Array, src: String) -> void:
	for a in list:
		_scan_one_ani(str(a.get("path", "")), src)


func _scan_one_ani(path: String, src: String) -> void:
	if path == "": return
	var def = _content.ani(path)
	if def == null or def.is_empty(): return
	var f: Dictionary = def.at(0)
	_add_img(str(f.get("img", "")), int(f.get("frame", 0)), src + "@" + path)


func _scan_npc(id: int) -> void:
	if id <= 0 or not _content.has_npc(id): return
	var n: NpcDef = _content.npc(id)
	if n == null: return
	if n.face_img != "": _add_img(n.face_img, n.face_frame, "face:%d" % id)
	_scan_one_ani(n.ani_path, "npc:%d" % id)


func _scan_monster(id: int) -> void:
	if not _content.has_monster(id): return
	var m: MonsterDef = _content.monster(id)
	if m == null: return
	_scan_one_ani(m.stay_ani_path, "monster:%d" % id)
	_scan_one_ani(m.move_ani_path, "monster:%d" % id)


func _scan_object(obj_path: String) -> void:
	if obj_path == "": return
	var o: ObjectDef = _content.object(obj_path)
	if o == null: return
	_scan_one_ani(o.ani_path, "obj:" + obj_path)
	for s in o.sub_anis:
		_scan_one_ani(str(s.get("ani", "")), "objsub:" + obj_path)


func _add_img(img: String, frame: int, src: String) -> void:
	if img == "": return
	var key := "%s#%d" % [img, frame]
	if _seen.has(key): return
	_seen[key] = true
	_total += 1
	var im := _store.image(img)
	if im == null:
		_bad.append({"img": img, "frame": frame, "src": src, "error": "image-null"})
		return
	if im.frame_count <= 0:
		_bad.append({"img": img, "frame": frame, "src": src, "error": "frame-count-0"})
		return
	_decoded += 1
	var f: Dictionary = im.frame(frame if frame < im.frame_count else 0)
	_frames += 1
	var pic = f.get("image")
	if pic == null:
		_bad.append({"img": img, "frame": frame, "src": src, "error": "frame-null"})
		return
	var sz: Vector2i = (pic as Image).get_size()
	if sz.x <= 1 or sz.y <= 1:
		_bad.append({"img": img, "frame": frame, "src": src, "error": "frame-1x1 %s" % sz})
