# 无头逻辑验证：把合成触摸事件喂进 Godot 输入管线，确认虚拟摇杆能激活、
# 产出正确方向向量，并真的推动玩家位移。结果写入文件，避免 stdout 缓冲被退出吞掉。
extends SceneTree

var _game: Node = null
var _t: float = 0.0
var _fed_touch: bool = false
var _x0: float = 0.0
var _x1: float = 0.0
var _log: String = ""
var _done: bool = false


func _write(result: String) -> void:
	var f := FileAccess.open("D:/1/art/preview/joystick_test.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(result)
		f.close()


func _initialize() -> void:
	_write("initialize ok\n")
	var packed := load("res://game.tscn")
	Game.auto_start = true
	_game = packed.instantiate()
	root.add_child(_game)


func _process(delta: float) -> bool:
	if _done:
		return false
	_t += delta

	if _game == null or not is_instance_valid(_game) or _game.get("player") == null:
		return false
	var player: Node = _game.player
	if not _fed_touch and _t > 0.5:
		_x0 = player.global_position.x
		var down := InputEventScreenTouch.new()
		down.pressed = true
		down.position = Vector2(220.0, 470.0)
		down.index = 0
		Input.parse_input_event(down)
		var drag := InputEventScreenDrag.new()
		drag.position = Vector2(330.0, 470.0)
		drag.index = 0
		Input.parse_input_event(drag)
		_fed_touch = true
		_log += "after touch: enabled=%s active=%s vector=%s\n" % [
			_game.joystick.is_enabled(), _game.joystick.is_active(), _game.joystick.get_vector()]

	if _fed_touch and _t > 1.6:
		_x1 = player.global_position.x
		_log += "player x moved: %.2f -> %.2f (delta %.2f)\n" % [_x0, _x1, _x1 - _x0]
		_done = true
		var up := InputEventScreenTouch.new()
		up.pressed = false
		up.position = Vector2(330.0, 470.0)
		up.index = 0
		Input.parse_input_event(up)
		_write(_log)
		# 给一帧让文件落盘再退出
		call_deferred("quit")
	return false
