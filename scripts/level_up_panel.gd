# 升级三选一面板：暂停期间使用的独立 UI 层。
# 只负责展示选项、维护"是否已提交"状态并回传选择，不修改任何游戏状态。
# 选择状态规则：一次开启只允许提交一次，提交后立即禁用按钮并关闭，
# 防止连点、重复按键、上一帧的事件残留导致同一奖励被应用两次。
class_name LevelUpPanel
extends CanvasLayer

## 玩家选定某项强化时发出，携带选项 id。保证每次开启只发出一次。
signal upgrade_chosen(id: String)

const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]

var _buttons: Array[Button] = []
var _options_box: VBoxContainer = null
var _title: Label = null
var _hint: Label = null
var _ids: Array[String] = []
var _is_open: bool = false
var _submitted: bool = false


func _ready() -> void:
	# 树被暂停时本层仍需响应输入，否则三选一会卡死。
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UiStyle.theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	margin.add_child(_options_box)

	_title = Label.new()
	_title.text = "LEVEL UP —— 选择一项强化"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", UiStyle.ACCENT)
	_options_box.add_child(_title)

	_hint = Label.new()
	_hint.text = "点击选项，或按数字键 1 / 2 / 3 选择（奖励必须选择，无法跳过）"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", UiStyle.DIM)
	_options_box.add_child(_hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 2.0)
	_options_box.add_child(spacer)


func is_open() -> bool:
	return _is_open


## 显示一批选项。已开启或选项为空时拒绝，返回 false 交由上层决定是否恢复游戏。
func show_options(options: Array[Dictionary]) -> bool:
	if _is_open or options.is_empty():
		return false

	_clear_buttons()
	_ids.clear()
	_submitted = false

	for index in options.size():
		var option: Dictionary = options[index]
		var id: String = String(option.get("id", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(552.0, 74.0)
		button.focus_mode = Control.FOCUS_ALL
		# 左对齐比居中更好读：三行文字长度不一，居中会让每行起点都不同。
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", UiStyle.TEXT)
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))
		button.add_theme_stylebox_override("normal",
				UiStyle.button_style(Color(0.10, 0.13, 0.18), UiStyle.BORDER))
		button.add_theme_stylebox_override("hover",
				UiStyle.button_style(Color(0.14, 0.20, 0.26), UiStyle.ACCENT))
		button.add_theme_stylebox_override("focus",
				UiStyle.button_style(Color(0.12, 0.17, 0.22), UiStyle.ACCENT, 2))
		button.add_theme_stylebox_override("pressed",
				UiStyle.button_style(Color(0.18, 0.26, 0.34), UiStyle.ACCENT, 2))
		button.text = _option_text(index, option)
		button.pressed.connect(_choose.bind(index))
		_options_box.add_child(button)
		_buttons.append(button)
		_ids.append(id)

	_is_open = true
	visible = true
	_hint.text = "点击选项，或按数字键 1 ~ %d 选择（奖励必须选择，无法跳过）" % options.size()
	# 让键盘方向键 + 回车可用，同时给出明确的初始焦点
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	return true


## 强制关闭（玩家死亡、场景切换等），不发出信号。
func close() -> void:
	_is_open = false
	_submitted = true
	visible = false


func _option_text(index: int, option: Dictionary) -> String:
	var text := "%d. %s" % [index + 1, String(option.get("title", "?"))]
	var desc: String = String(option.get("desc", ""))
	if desc != "":
		text += "\n%s" % desc
	var detail: String = String(option.get("detail", ""))
	if detail != "":
		text += "\n%s" % detail
	return text


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_ESCAPE:
		# 奖励不允许跳过：吞掉按键，避免误触上层逻辑（如退出全屏菜单）
		get_viewport().set_input_as_handled()
		return

	var index: int = NUMBER_KEYS.find(key_event.keycode)
	if index >= 0:
		_choose(index)
		get_viewport().set_input_as_handled()


func _choose(index: int) -> void:
	# 状态锁：已提交、越界、面板已关闭时一律忽略
	if _submitted or not _is_open:
		return
	if index < 0 or index >= _ids.size():
		return

	_submitted = true
	for button: Button in _buttons:
		if is_instance_valid(button):
			button.disabled = true
	var chosen_id: String = _ids[index]
	_is_open = false
	visible = false
	AudioManager.play("click")
	upgrade_chosen.emit(chosen_id)


func _clear_buttons() -> void:
	for button: Button in _buttons:
		if is_instance_valid(button):
			button.queue_free()
	_buttons.clear()
