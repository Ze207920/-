# 摇杆逻辑验证（精简版）：显式加载 joystick.gd，注入合成触摸，确认激活并产出正确向量。
extends Node2D

var _joy: Node = null
var _t: float = 0.0
var _fed: bool = false
var _done: bool = false
var _buffer: String = ""


func _ready() -> void:
	_buffer += "ready\n"
	var JoyScript = load("res://scripts/joystick.gd")
	if JoyScript == null:
		_buffer += "FATAL: cannot load joystick.gd\n"
		_done = true
		_write()
		return
	_buffer += "script ok: set_enabled=%s is_enabled=%s is_active=%s get_vector=%s\n" % [
		JoyScript.has_method("set_enabled"), JoyScript.has_method("is_enabled"),
		JoyScript.has_method("is_active"), JoyScript.has_method("get_vector")]
	var layer := CanvasLayer.new()
	add_child(layer)
	_joy = JoyScript.new()
	layer.add_child(_joy)
	_joy.set_enabled(true)
	_buffer += "viewport_rect=%s\n" % get_viewport_rect().size


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta

	if not _fed and _t > 0.4:
		# 直接调用摇杆的 _input（绕过合成事件到不了 _input 的测试管线限制），
		# 验证真实逻辑：左半屏按下 + 右拖 -> (+1, 0)
		var down := InputEventScreenTouch.new()
		down.pressed = true
		down.position = Vector2(220.0, 470.0)
		down.index = 0
		_joy._input(down)
		var drag := InputEventScreenDrag.new()
		drag.position = Vector2(330.0, 470.0)
		drag.index = 0
		_joy._input(drag)
		_fed = true
		_buffer += "right-drag: enabled=%s active=%s vector=%s\n" % [
			_joy.is_enabled(), _joy.is_active(), _joy.get_vector()]

		# 第二个用例：向下拖动应得到 (0, +1)
		var down2 := InputEventScreenTouch.new()
		down2.pressed = true
		down2.position = Vector2(200.0, 300.0)
		down2.index = 1
		_joy._input(down2)
		var drag2 := InputEventScreenDrag.new()
		drag2.position = Vector2(200.0, 420.0)
		drag2.index = 1
		_joy._input(drag2)
		_buffer += "down-drag: vector=%s\n" % _joy.get_vector()
		var up2 := InputEventScreenTouch.new()
		up2.pressed = false
		up2.position = Vector2(200.0, 420.0)
		up2.index = 1
		_joy._input(up2)
		_done = true
		_write()
		get_tree().quit()


func _write() -> void:
	var f := FileAccess.open("D:/1/art/preview/joystick_test.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(_buffer)
		f.close()
