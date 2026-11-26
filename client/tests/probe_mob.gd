extends SceneTree

func _initialize() -> void:
	var assets := Sf85Assets.new()
	var pvf_path := "/home/sunmingze/dnf_like/build/sf85.Script.utf8.pvf"
	var ok := assets.open(pvf_path)
	print("open=", ok)
	print("mob_path(4)=", assets.mob_path(4))
	print("mob_path(1)=", assets.mob_path(1))
	var doc: PvfTypes.DocNode = assets.pvf.pvf.get_document(assets.mob_path(4))
	if doc == null:
		print("mob doc null")
	else:
		print("sections=", doc.children.size())
		for c in doc.children:
			var n: PvfTypes.DocNode = c
			print("  [", n.name, "] attrs=", n.attrs.slice(0, 4))
	var def := assets.pvf.build_monster(assets.mob_path(4))
	print("def keys=", def.keys())
	var layers: Array = def.get("layers", [])
	if not layers.is_empty():
		var anims: Dictionary = layers[0]["anims"]
		print("anims=", anims.keys())
	print("warnings=", assets.pvf.warnings)
	quit()
