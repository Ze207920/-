# 全屏覆盖层：标题 / 暂停 / 结算三种状态共用一块面板。
#
# 这一层永远 PROCESS_MODE_ALWAYS —— 暂停是整棵树级的，若本层也跟着停，
# 玩家就再也按不动"继续"，会直接卡死在暂停界面。
class_name GameOverlay
extends CanvasLayer

signal start_requested
signal resume_requested
signal restart_requested
signal title_requested
signal challenge_requested
signal characters_requested
signal next_requested
signal select_requested

enum Mode {
	HIDDEN,
	TITLE,
	PAUSE,
	OVER,
}

var _mode: int = Mode.HIDDEN
## 当前面板第一个按钮的动作。空格 / 回车直接触发它，而不是硬编码「重开」——
## 通关后第一个按钮是「下一关」，此时按空格继续下一关才符合直觉。
var _primary_action: String = "start"
## 最后一个按钮的动作，ESC 用它。挑战模式是「返回选关」，生存模式是「返回标题」。
var _secondary_action: String = "title"
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _body: Label = null
var _hint: Label = null
var _button_row: HBoxContainer = null
## 暂停面板里的静音按钮引用，切换静音时改它的文字。
var _pause_mute_button: Button = null

## 是否触摸设备。决定提示文案用「点击」还是「按键」，避免手机上看不懂。
static func is_touch_device() -> bool:
	return OS.has_feature("touchscreen")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiStyle.theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_style())
	_panel.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", UiStyle.TEXT)
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", UiStyle.ACCENT)
	box.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	box.add_child(spacer)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(470.0, 0.0)
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	_body.add_theme_constant_override("line_spacing", 8)
	box.add_child(_body)

	var button_gap := Control.new()
	button_gap.custom_minimum_size = Vector2(0.0, 10.0)
	box.add_child(button_gap)

	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 14)
	box.add_child(_button_row)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", UiStyle.DIM)
	box.add_child(_hint)


func mode() -> int:
	return _mode


func is_open() -> bool:
	return _mode != Mode.HIDDEN


func show_title(best: Dictionary = {}, progress: Dictionary = {},
		character: Dictionary = {}) -> void:
	_mode = Mode.TITLE
	_title.text = "幸存者"
	_subtitle.text = "SURVIVORS"
	var lines: Array[String] = [
		"WASD / 方向键    移动        E / 空格    释放全部就绪技能",
		"1 / 2 / 3    单独放技能        攻击全自动，专心走位",
		"每 5 级解锁一个新技能，集齐三招后转为技能强化",
		"升级时从三个强化里挑一个",
		"",
		"生存模式    无尽，熬到倒下为止",
		"挑战模式    八道关卡，由易到难",
	]
	# 当前角色放在最显眼的位置：玩家进标题页第一件想确认的事就是"我在用谁"。
	var character_name: String = String(character.get("name", ""))
	if character_name != "":
		lines.append("")
		lines.append("当前角色    %s · %s    技能 %d 招" % [
			character_name, String(character.get("role", "")),
			int(character.get("skills", 1))])
	var best_time: float = float(best.get("time", 0.0))
	if best_time > 0.0:
		lines.append("")
		lines.append("最佳记录  %s   ·   %d 击杀" % [
			format_time(best_time), int(best.get("kills", 0))])
	# 挑战进度只在真打过一关之后显示，没玩过的人不需要看「0 / 8」。
	var cleared: int = int(progress.get("cleared", 0))
	if cleared > 0:
		lines.append("挑战进度  %d / %d 关" % [cleared, int(progress.get("total", 0))])
	_body.text = "\n".join(lines)
	_set_buttons([
		{"text": "生存模式", "action": "start"},
		{"text": "挑战模式", "action": "challenge"},
		{"text": "选择角色", "action": "characters"},
	])
	if is_touch_device():
		_hint.text = "点击按钮开始 · 左下拖动移动 · 右下角暂停与技能"
	else:
		_hint.text = "空格 开始生存模式    C 挑战模式    Tab 换角色    M 静音"
	visible = true
	_focus_first()


func show_pause() -> void:
	_mode = Mode.PAUSE
	_title.text = "已暂停"
	_subtitle.text = "PAUSED"
	if is_touch_device():
		_body.text = "点击「继续」回到游戏"
	else:
		_body.text = "按 ESC 继续游戏"
	_set_buttons([
		{"text": "继续", "action": "resume"},
		{"text": "重新开始", "action": "restart"},
	])
	# 静音入口：键盘端可用 M，但移动端没有键盘，必须给一个可点的按钮。
	_add_mute_button()
	if is_touch_device():
		_hint.text = "点击按钮操作"
	else:
		_hint.text = "M 静音"
	visible = true
	_focus_first()


func show_over(stats: Dictionary) -> void:
	_mode = Mode.OVER
	var cleared: bool = bool(stats.get("cleared", false))
	var challenge: bool = bool(stats.get("challenge", false))
	var has_next: bool = bool(stats.get("has_next", false))

	if cleared:
		_title.text = "闯关成功"
		_subtitle.text = "STAGE CLEAR"
	else:
		_title.text = "被包围了"
		_subtitle.text = "GAME OVER"

	var lines: Array[String] = []
	if challenge:
		lines.append("第 %d 关    %s" % [
			int(stats.get("level_index", 0)) + 1, String(stats.get("level_name", ""))])
		lines.append("")
	lines.append("存活 %s" % String(stats.get("time_text", "00:00")))
	lines.append("等级 %d    击杀 %d" % [
		int(stats.get("level", 1)), int(stats.get("kills", 0))])
	if not challenge:
		lines.append("武器 %s" % String(stats.get("weapon_text", "—")))
	_body.text = "\n".join(lines)

	if bool(stats.get("record", false)):
		_body.text += "\n\n新纪录！"
	elif cleared and challenge and not has_next:
		_body.text += "\n\n全部关卡通关，到此为止了。"
	else:
		var best_time: float = float(stats.get("best_time", 0.0))
		if best_time > 0.0:
			_body.text += "\n\n最佳记录  %s" % format_time(best_time)

	var buttons: Array = []
	if cleared and has_next:
		buttons.append({"text": "下一关", "action": "next"})
	buttons.append({"text": "再来一局", "action": "restart"})
	if challenge:
		buttons.append({"text": "返回选关", "action": "select"})
	else:
		buttons.append({"text": "返回标题", "action": "title"})
	_set_buttons(buttons)
	_hint.text = "空格 继续    ESC 返回    M 静音"
	visible = true
	_focus_first()


## 把秒数格式化成 mm:ss，标题页与结算页共用一份逻辑。
static func format_time(seconds: float) -> String:
	var total: int = int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func hide_overlay() -> void:
	_mode = Mode.HIDDEN
	visible = false


func _set_buttons(entries: Array) -> void:
	# 先 remove_child 再 queue_free：queue_free 要等帧末才真正移除，
	# 直接留着会让随后的 _focus_first() 抓到一颗正在销毁的按钮。
	for child: Node in _button_row.get_children():
		_button_row.remove_child(child)
		child.queue_free()
	_pause_mute_button = null
	for entry: Dictionary in entries:
		var button := _make_button(String(entry["text"]), String(entry["action"]))
		_button_row.add_child(button)
	if not entries.is_empty():
		_primary_action = String(entries[0]["action"])
		_secondary_action = String(entries[entries.size() - 1]["action"])


func _focus_first() -> void:
	# 键盘玩家不该被迫先按一次方向键才能选中按钮。
	if _button_row.get_child_count() > 0:
		var first := _button_row.get_child(0) as Button
		if first != null:
			first.grab_focus()


## 在暂停面板追加一个静音按钮。每次 show_pause 都会重建按钮行，
## 所以这里也跟着重建并把引用存到 _pause_mute_button，方便切换时改文字。
func _add_mute_button() -> void:
	if _button_row == null:
		return
	var button := Button.new()
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal",
			UiStyle.button_style(Color(0.11, 0.14, 0.19), UiStyle.BORDER))
	button.add_theme_stylebox_override("hover",
			UiStyle.button_style(Color(0.15, 0.21, 0.28), UiStyle.ACCENT))
	button.add_theme_stylebox_override("pressed",
			UiStyle.button_style(Color(0.19, 0.27, 0.35), UiStyle.ACCENT, 2))
	button.pressed.connect(_toggle_mute)
	_button_row.add_child(button)
	_pause_mute_button = button
	_refresh_mute_label()


func _refresh_mute_label() -> void:
	if _pause_mute_button != null:
		_pause_mute_button.text = "取消静音" if AudioManager.muted else "静音"


func _toggle_mute() -> void:
	AudioManager.muted = not AudioManager.muted
	_refresh_mute_label()
	AudioManager.play("click")


func _make_button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal",
			UiStyle.button_style(Color(0.11, 0.14, 0.19), UiStyle.BORDER))
	button.add_theme_stylebox_override("hover",
			UiStyle.button_style(Color(0.15, 0.21, 0.28), UiStyle.ACCENT))
	button.add_theme_stylebox_override("focus",
			UiStyle.button_style(Color(0.13, 0.18, 0.24), UiStyle.ACCENT, 2))
	button.add_theme_stylebox_override("pressed",
			UiStyle.button_style(Color(0.19, 0.27, 0.35), UiStyle.ACCENT, 2))
	button.pressed.connect(_on_action.bind(action))
	return button


func _on_action(action: String) -> void:
	# 键盘快捷键（空格 / ESC）也走这里，所以点击声对两种输入都成立。
	AudioManager.play("click")
	_emit_action(action)


func _emit_action(action: String) -> void:
	match action:
		"start":
			start_requested.emit()
		"resume":
			resume_requested.emit()
		"restart":
			restart_requested.emit()
		"title":
			title_requested.emit()
		"challenge":
			challenge_requested.emit()
		"characters":
			characters_requested.emit()
		"next":
			next_requested.emit()
		"select":
			select_requested.emit()
		_:
			push_warning("GameOverlay: 未知按钮动作「%s」" % action)


func _input(event: InputEvent) -> void:
	if _mode == Mode.HIDDEN:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var confirm: bool = key.keycode == KEY_SPACE or key.keycode == KEY_ENTER \
			or key.keycode == KEY_KP_ENTER

	# 先吞掉按键再发信号：GUI 在 _input 之后才处理，不吞的话空格会同时
	# 触发「聚焦按钮被按下」和这里的快捷键，同一次按键开两局。
	match _mode:
		Mode.TITLE:
			if confirm:
				get_viewport().set_input_as_handled()
				_emit_action(_primary_action)
			elif key.keycode == KEY_C:
				get_viewport().set_input_as_handled()
				challenge_requested.emit()
			elif key.keycode == KEY_TAB:
				get_viewport().set_input_as_handled()
				characters_requested.emit()
		Mode.PAUSE:
			if key.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				resume_requested.emit()
		Mode.OVER:
			if confirm:
				get_viewport().set_input_as_handled()
				_emit_action(_primary_action)
			elif key.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_emit_action(_secondary_action)
