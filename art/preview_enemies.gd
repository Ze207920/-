# 邪物图鉴：把四种敌人的造型各画一遍渲染成 PNG，用来检查轮廓能不能一眼区分。
# 纯开发期工具。用法：godot --path . art/preview_enemies.tscn
# 加 -- --detail 只看海猴子（体型最大、细节最多）的 5 倍特写。
extends Node2D

const OUT_PATH: String = "res://art/preview/enemies.png"
const DETAIL_PATH: String = "res://art/preview/enemies_detail.png"
const BG: Color = Color(0.075, 0.085, 0.115)
const CELL: Vector2 = Vector2(105.0, 120.0)
const ORIGIN: Vector2 = Vector2(70.0, 80.0)

var _detail: bool = false


func _ready() -> void:
	_detail = OS.get_cmdline_user_args().has("--detail")
	RenderingServer.set_default_clear_color(BG)
	_build_backdrop()
	_build_camera()
	_build_cases()

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	var out: String = DETAIL_PATH if _detail else OUT_PATH
	var err: int = img.save_png(out)
	print("enemy preview saved: ", out, "  err=", err)
	get_tree().quit()


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(2000.0, 2000.0)
	bg.position = Vector2(-500.0, -500.0)
	bg.z_index = -50
	add_child(bg)


func _build_camera() -> void:
	var cam := Camera2D.new()
	if _detail:
		cam.position = ORIGIN
		cam.zoom = Vector2(5.0, 5.0)
	else:
		cam.position = ORIGIN + Vector2(CELL.x * 1.5, CELL.y * 0.5)
		cam.zoom = Vector2(3.0, 3.0)
	cam.enabled = true
	add_child(cam)


func _build_cases() -> void:
	var presets: Array[EnemyData] = EnemyData.presets()

	if _detail:
		# 海猴子体型最大，造型细节也最多，用它检查边缘和比例
		_spawn(presets[2], ORIGIN, 1.0, false)
		_spawn(presets[2], ORIGIN, 0.45, true)
		return

	for i in presets.size():
		var pos: Vector2 = ORIGIN + Vector2(CELL.x * float(i), 0.0)
		_spawn(presets[i], pos, 1.0, false)
		_spawn(presets[i], pos + Vector2(0.0, CELL.y), 0.45, true)


## hurt 为 true 时画半血 + 受击闪白，用来确认血条弧不会盖住记号色。
func _spawn(preset: EnemyData, pos: Vector2, health_ratio: float, hurt: bool) -> void:
	var enemy := Enemy.new()
	enemy.apply_data(preset)
	enemy.position = pos
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy._health = preset.max_health * health_ratio
	if hurt:
		enemy.modulate = Color(1.55, 1.40, 1.40)
	enemy.queue_redraw()

	var label := Label.new()
	label.text = preset.display_name
	label.add_theme_font_override("font", UiStyle.font())
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	label.position = Vector2(pos.x - 22.0, pos.y + 40.0)
	add_child(label)
