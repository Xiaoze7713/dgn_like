class_name AniDef
extends RefCounted
## `.ani`（PVF 里的帧动画）→ 只保留「怎么画」需要的字段。
##
## 每帧 = 一张 NPK 图里的某一帧 + 相对锚点的偏移 + 停留毫秒。
## PVF 的 `.ani` 是平铺语法（没有 `[/FRAME]`），所以编译期已经把帧切好，
## 运行时只管按 delay 轮播，不再解析 token 流。

var path := ""
var loop := false
var shadow := false
var frame_max := 0
var frames: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> AniDef:
	var a := AniDef.new()
	a.path = str(d.get("path", ""))
	a.loop = int(d.get("loop", 0)) != 0
	a.shadow = int(d.get("shadow", 0)) != 0
	a.frame_max = int(d.get("frame_max", 0))
	var raw: Array = d.get("frames", [])
	for f in raw:
		var fd: Dictionary = f
		a.frames.append({
			"img": str(fd.get("img", "")),
			"frame": int(fd.get("frame", 0)),
			"dx": int(fd.get("dx", 0)),
			"dy": int(fd.get("dy", 0)),
			"delay": maxi(1, int(fd.get("delay", 100))),
			"effect": str(fd.get("effect", "")),
			"rgba": fd.get("rgba", []),
		})
	return a


func is_empty() -> bool:
	return frames.is_empty()


func at(i: int) -> Dictionary:
	if frames.is_empty():
		return {}
	return frames[clampi(i, 0, frames.size() - 1)]


func total_ms() -> int:
	var t := 0
	for f in frames:
		t += int(f.get("delay", 100))
	return maxi(1, t)
