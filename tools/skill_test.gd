extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://game.tscn") as PackedScene
	var game: Node = packed.instantiate()
	add_child(game)
	var p: Player = game.get("player") as Player
	print("GAME_READY player=", p != null, " state=", game.get("_state"))
	game.call("_enter_play")
	print("ENTER_PLAY state=", game.get("_state"), " skills=", p.skills.size())

	var guard: int = 0
	while p.level < 5 and guard < 300:
		p.add_xp(p.xp_to_next - p.xp)
		guard += 1
	print("AT_LV5 level=", p.level, " skills=", p.skills.size(), " mastery=", p.skill_mastery)
	print("PANEL_OPEN=", game.get("level_panel").call("is_open"), " paused=", get_tree().paused)
	print("PENDING_TOASTS=", game.get("_pending_toasts"))
	print("SKILL_BUTTONS=", game.get("skill_buttons").size())

	game.call("_on_upgrade_chosen", "damage")
	await get_tree().process_frame
	await get_tree().process_frame
	print("AFTER_CHOICE paused=", get_tree().paused, " skills=", p.skills.size())
	for slot: Dictionary in p.skill_ui():
		print("  SLOT ", slot.get("key"), " ", slot.get("name"))
	var buttons: Array = game.get("skill_buttons")
	for b: Button in buttons:
		print("  BUTTON ", b.name, " visible=", b.visible, " text=", b.text.replace("\n", " / "))
	var hud: Node = game.get("hud")
	print("HUD_SLOTS=", hud.get("skill_slots").size(), " chips=", hud.get("show_skill_chips"))
	get_tree().quit()
