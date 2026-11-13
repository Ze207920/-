# 角色外观检查台：把 Q 版主角的几种姿态排成一张对照表渲染成 PNG。
# 纯开发期工具，不参与游戏运行。用法：
#   godot --path . art/preview_player.tscn
# 因为要真渲染，不能加 --headless（Dummy 驱动下 get_image() 拿不到画面）。
extends Node2D

const OUT_PATH: String = "res://art/preview/player_states.png"
const BG: Color = Color(0.075, 0.085, 0.115)
## 网格间距（设计坐标）。相机 zoom 会把它换算成屏幕像素。
const CELL: Vector2 = Vector2(112.0, 140.0)
const ORIGIN: Vector2 = Vector2(58.0, 78.0)

var _cases: int = 0
## 特写模式：只画两个姿态并把镜头推到 5 倍，用来看清五官和描边是否对齐。
## 用法：godot --path . art/preview_player.tscn -- --detail
var _detail: bool = false


func _ready() -> void:
	_detail = OS.get_cmdline_user_args().has("--detail")
	RenderingServer.set_default_clear_color(BG)
	_build_backdrop()
	_build_camera()
	_build_cases()

	# 等两帧让 _draw 全部提交，再等一次绘制完成信号，否则截到的是空画面。
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var out_path: String = "res://art/preview/player_detail.png" if _detail else OUT_PATH
	var err: int = img.save_png(out_path)
	print("preview saved: ", out_path, "  size=", img.get_size(), "  err=", err)
	get_tree().quit()


func _build_backdrop() -> void:
	# 铺一块和实际地板同色系的底，角色在深色背景上的对比度才看得准。
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(2000.0, 2000.0)
	bg.position = Vector2(-500.0, -500.0)
	bg.z_index = -50
	add_child(bg)


func _build_camera() -> void:
	var cam := Camera2D.new()
	if _detail:
		cam.position = Vector2(ORIGIN.x, ORIGIN.y - 4.0)
		cam.zoom = Vector2(6.0, 6.0)
	else:
		cam.position = ORIGIN + Vector2(CELL.x * 1.5, CELL.y * 0.5 - 14.0)
		cam.zoom = Vector2(2.2, 2.2)
	cam.enabled = true
	add_child(cam)


func _build_cases() -> void:
	if _detail:
		_case("待机", func(p: Player) -> void:
			p.facing = Vector2.DOWN)
		return

	_case("待机（朝下）", func(p: Player) -> void:
		p.facing = Vector2.DOWN)
	_case("迈步 A", func(p: Player) -> void:
		p._walk_amp = 1.0
		p._walk_phase = PI * 0.5)
	_case("迈步 B", func(p: Player) -> void:
		p._walk_amp = 1.0
		p._walk_phase = -PI * 0.5)
	_case("看向右", func(p: Player) -> void:
		p._ever_moved = true
		p.facing = Vector2.RIGHT)
	_case("看向左", func(p: Player) -> void:
		p._ever_moved = true
		p.facing = Vector2.LEFT)
	_case("眨眼", func(p: Player) -> void:
		p.facing = Vector2.DOWN
		p._blink = 0.5)
	_case("受击闪白", func(p: Player) -> void:
		p.facing = Vector2.DOWN
		p._hit_flash = 1.0)
	_case("无敌闪烁", func(p: Player) -> void:
		p.facing = Vector2.DOWN
		p._invuln_timer = 0.3
		p._anim_time = 0.03)


func _case(caption: String, setup: Callable) -> void:
	var col: int = _cases % 4
	var row: int = int(_cases / 4.0)
	var pos: Vector2 = ORIGIN + Vector2(CELL.x * col, CELL.y * row)
	_cases += 1

	var p := Player.new()
	p.position = pos
	add_child(p)
	# add_child 会同步跑完 _ready（其中会装上手枪并排好首次开火），
	# 这里必须把物理/处理关掉，否则这些展示用的角色会真的开始射击。
	p.set_physics_process(false)
	p.set_process(false)
	for child in p.get_children():
		child.set_physics_process(false)
		child.set_process(false)
	setup.call(p)
	p.queue_redraw()

	var label := Label.new()
	label.text = caption
	label.add_theme_font_override("font", UiStyle.font())
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.66, 0.73, 0.84))
	label.position = Vector2(pos.x - 36.0, pos.y + 24.0)
	add_child(label)
