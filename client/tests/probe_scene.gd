extends Node

func _ready() -> void:
	Log.info("scene 里直接调 Log", {"ok": true})
	Env.ensure()
	print("Env in scene: ", Env.env_name, " / ", Env.cfg("server_url"))
	Log.tag("Sc").warn("tag in scene")
	await get_tree().process_frame
	get_tree().quit()
