# 墓室障碍：挑战模式下随机隆起的碎石 / 石墩，用来限制玩家与邪物的走位。
#
# 用 StaticBody2D（物理体）承载碰撞 —— 敌人是 CharacterBody2D，靠 move_and_slide
# 就能自然贴着石头滑开；玩家是纯 Node2D（没有物理体），所以由 Game 在移动时
# 手动把坐标推出障碍圆。两者因此都被同一块石头挡住，但实现路径不同。
#
# 投射物只查 ENEMY 层，飞过碎石不受任何影响，避免远程玩法被石头坑到。
class_name Obstacle
extends StaticBody2D

## 视觉淡入 / 淡出时长（秒）。
const FADE: float = 0.5

## 碰撞与视觉共用的半径。
var radius: float = 48.0
## 存活时长：到点后淡出并销毁，防止玩家一路走下去把整个世界堆满碎石。
var lifetime: float = 20.0

var _life: float = 0.0
var _alpha: float = 0.0
var _seed: float = 0.0
var _shape: CollisionShape2D = null

## 材质三段色，来自关卡主题：冰关的障碍是冰块、铜关是铜片、雪关是冻岩。
## 未设置时退回灰石（生存模式的默认色）。
var _base: Color = Color(0.39, 0.41, 0.45)
var _light: Color = Color(0.56, 0.58, 0.62)
var _dark: Color = Color(0.23, 0.25, 0.28)


## 设置本关的碎石材质。必须在 add_child 之前调用（setup 只建碰撞体，不管外观）。
func set_palette(base: Color, light: Color, dark: Color) -> void:
	_base = base
	_light = light
	_dark = dark


## 初始化碰撞体与圆半径，并把自己放到「障碍层」。
## 只在障碍层：不与任何东西互检（collision_mask = 0），自身也不会被其它查询命中。
func setup(radius_value: float, life: float, seed_value: float) -> void:
	radius = radius_value
	lifetime = life
	_seed = seed_value

	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape = CollisionShape2D.new()
	_shape.shape = circle
	add_child(_shape)

	collision_layer = PhysicsLayers.OBSTACLE
	collision_mask = 0
	# 先全透明，靠 _process 淡入；淡出时也只改 modulate.a，颜色保持实体。
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	# 压在地面之上、角色之下：玩家与邪物永远画在石头前面，读位更清楚。
	z_index = -1


func _process(delta: float) -> void:
	_life += delta
	if _life < 0.3:
		# 出生 0.3 秒内淡入，给「随机隆起」一点缓冲而不是凭空砸出来。
		_alpha = minf(1.0, _alpha + delta / 0.3)
	elif _life >= lifetime:
		# 寿命到了淡出，淡完自我销毁。
		_alpha = maxf(0.0, _alpha - delta / FADE)
		if _alpha <= 0.0:
			queue_free()
			return
	modulate.a = _alpha
	# 只在「还在变透明度」时重绘，稳定显示期间省掉每帧重画。
	if _alpha < 1.0 or _life >= lifetime:
		queue_redraw()


func _draw() -> void:
	var R: float = radius
	var base: Color = _base
	var light: Color = _light
	var dark: Color = _dark
	var outline: Color = Color(0.10, 0.11, 0.14, 0.90)

	# 落地阴影：压扁的椭圆，纯黑低透明。
	_draw_ellipse(Vector2(0.0, R * 0.52), Vector2(R * 0.92, R * 0.40), Color(0.0, 0.0, 0.0, 0.30))

	# 主体：底圆 + 左上高光 + 右下暗部，叠出石头的体积感。
	draw_circle(Vector2.ZERO, R, base)
	draw_circle(Vector2(-R * 0.30, -R * 0.32), R * 0.62, light)
	draw_circle(Vector2(R * 0.32, R * 0.34), R * 0.66, dark)

	# 随种子旋转的裂纹，让每块碎石略有不同。
	var a1: float = _seed * TAU
	var a2: float = a1 + 2.1
	draw_line(Vector2(cos(a1), sin(a1)) * R * 0.80,
			Vector2(cos(a1 + 0.40), sin(a1 + 0.40)) * -R * 0.50, outline, 1.6, true)
	draw_line(Vector2(cos(a2), sin(a2)) * R * 0.70,
			Vector2(cos(a2 - 0.30), sin(a2 - 0.30)) * -R * 0.40, outline, 1.4, true)

	# 外轮廓。
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 34, outline, 2.0, true)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 20) -> void:
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts[i] = center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
	draw_colored_polygon(pts, color)
