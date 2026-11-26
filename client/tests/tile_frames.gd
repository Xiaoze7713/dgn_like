extends SceneTree

# 地砖 `[IMAGE]` 的帧号回归：gent 的 Imperial_Palace_Tile.img 有 5 帧，
# 每张 .til 的 `[IMAGE] ... <n>` 必须落到对应 n；不能全部读成 0。
const TILE_DIR := "map/cataclysm/town/gent/tile/imperial_palace_tile0%d.til"

func _init() -> void:
	var ok := 0
	var fail := 0
	var c := LivePvfContent.new()
	c.load_index()
	var store := NpkStore.new(PathUtil.dnf_imagepacks())
	store.open_live()
	var hashes := {}
	for i in 5:
		var path := TILE_DIR % i
		var t: TileDef = c.tile(path)
		if t == null:
			print("FAIL missing %s" % path); fail += 1
			continue
		if t.frame != i:
			print("FAIL frame %s got %d want %d" % [path, t.frame, i]); fail += 1
		else:
			print("OK frame %s = %d" % [path, t.frame]); ok += 1
		var tex := store.texture(t.img, t.frame)
		if tex == null:
			print("FAIL texture %s" % path); fail += 1
			continue
		hashes[hash(tex.get_image().get_data())] = true
	if hashes.size() == 5:
		print("OK five distinct tile frames"); ok += 1
	else:
		print("FAIL distinct frames=%d" % hashes.size()); fail += 1
	print("== %d ok, %d fail ==" % [ok, fail])
	quit(1 if fail > 0 else 0)
