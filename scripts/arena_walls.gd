# 墓室四壁：把「场地边界」画出来，让玩家知道哪儿是墙。
#
# 这里只有视觉。真正的约束由 Game / Player / Enemy 负责（把坐标夹进矩形）——
# 不做物理墙的原因：墙是一整圈无限长的边，用 StaticBody2D 拼要几十段碰撞体，
# 而「贴着边界滑」和「夹住坐标」在这个俯视玩法里手感完全一样，后者更便宜。
#
# 墙的配色与画法来自 ArenaTheme：石墓砌砖、荒土垒石、寒冰开裂、青铜铸板，
# 同一个约束（一圈边界）在不同关卡里要长成不同地方的墙。
class_name ArenaWalls
extends Node2D

## 墙外的颜色：近黑。墓室之外没有地面，只有黑。
## 不能纯黑 —— 纯黑和屏幕边框糊在一起，玩家会以为显示器坏了。
const VOID_COLOR: Color = Color(0.043, 0.047, 0.062)

## 可走区域（墙的内沿）。墙带从这个矩形向外画。
var rect: Rect2 = Rect2()
## 墙带厚度。
var thickness: float = 72.0

## 当前关卡主题。setup 之前为 null（此时退回默认墓室配色，预览场景用）。
var theme: ArenaTheme = null


func setup(bounds: Rect2, wall_thickness: float, theme_value: ArenaTheme = null) -> void:
	rect = bounds
	thickness = wall_thickness
	theme = theme_value
	# 压在底面（-100）之上、所有角色之下。角色默认 z_index 0。
	z_index = -90
	queue_redraw()


## 主题缺省值：没传主题时退回最初的青灰墓室，保证预览场景不崩。
func _style_top() -> Color:
	return theme.wall_top if theme != null else Color(0.30, 0.31, 0.36)


func _style_side() -> Color:
	return theme.wall_side if theme != null else Color(0.21, 0.22, 0.26)


func _style_bottom() -> Color:
	return theme.wall_bottom if theme != null else Color(0.12, 0.13, 0.16)


func _style_joint() -> Color:
	return theme.wall_joint if theme != null else Color(0.10, 0.11, 0.14, 0.55)


func _style_rim() -> Color:
	return theme.wall_rim if theme != null else Color(0.42, 0.78, 0.92, 0.28)


func _style_id() -> int:
	return theme.wall_style if theme != null else ArenaTheme.WallStyle.BRICK


func _draw() -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return

	_draw_void()
	_draw_ambient()
	_draw_wall_bands()
	match _style_id():
		ArenaTheme.WallStyle.ROUGH:
			_draw_rough_joints()
		ArenaTheme.WallStyle.ICE:
			_draw_ice_cracks()
		ArenaTheme.WallStyle.PLATE:
			_draw_plate_seams()
		_:
			_draw_brick_joints()
	_draw_inner_rim()


## 墙外：四块巨大的实心矩形把外面糊死。
## 相机被夹在场地外一圈，正常只会露出墙带；但宽屏（expand 拉伸）下可能露得更多，
## 所以整片都涂满，不留任何能看到底图重复的边缘。
func _draw_void() -> void:
	var far: float = 6000.0
	var top := Rect2(rect.position.x - far, rect.position.y - far,
			rect.size.x + far * 2.0, far)
	var bottom := Rect2(rect.position.x - far, rect.end.y,
			rect.size.x + far * 2.0, far)
	var left := Rect2(rect.position.x - far, rect.position.y, far, rect.size.y)
	var right := Rect2(rect.end.x, rect.position.y, far, rect.size.y)
	for piece: Rect2 in [top, bottom, left, right]:
		draw_rect(piece, VOID_COLOR)


## 氛围罩：一整块低透明度的主题色盖在可走区域上。
## 地面贴图已经带了各关的材质，这里只负责「这间墓室里的光」——
## 冰宫偏冷蓝、血玉偏暗红。画在墙节点里是因为它天然就在底面之上、角色之下。
func _draw_ambient() -> void:
	if theme == null:
		return
	draw_rect(rect, theme.ambient)


## 四条墙带，全部画在可走区域之外，不占玩家能站的地方。
func _draw_wall_bands() -> void:
	var w: float = thickness
	draw_rect(Rect2(rect.position.x - w, rect.position.y - w, rect.size.x + w * 2.0, w),
			_style_top())
	draw_rect(Rect2(rect.position.x - w, rect.end.y, rect.size.x + w * 2.0, w),
			_style_bottom())
	draw_rect(Rect2(rect.position.x - w, rect.position.y, w, rect.size.y), _style_side())
	draw_rect(Rect2(rect.end.x, rect.position.y, w, rect.size.y), _style_side())

	# 墙带外沿压一道更暗的边，墙和黑底之间才有分界。
	var edge := Color(0.07, 0.08, 0.10, 0.55)
	draw_rect(Rect2(rect.position.x - w, rect.position.y - w,
			rect.size.x + w * 2.0, w), edge, false, 3.0)
	draw_rect(Rect2(rect.position.x - w, rect.end.y,
			rect.size.x + w * 2.0, w), edge, false, 3.0)


## 砖缝：每 96 像素一道。没有砖缝的墙带是一条纯色长条，
## 铺在同样有石板纹理的地面旁边会显得像没画完。
func _draw_brick_joints() -> void:
	var step: float = 96.0
	var w: float = thickness
	var joint: Color = _style_joint()

	var x: float = rect.position.x
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y - w), Vector2(x, rect.position.y), joint, 2.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x, rect.end.y + w), joint, 2.0)
		x += step

	var y: float = rect.position.y
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x - w, y), Vector2(rect.position.x, y), joint, 2.0)
		draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x + w, y), joint, 2.0)
		y += step


## 垒石（ROUGH）：缝时断时续、位置带确定性抖动。
## 腐土和泥沼里的墙不是砌出来的，是乱石垒的 —— 规整砖缝一眼就假。
## 抖动用「像素坐标散列」而不是随机数：每次重绘结果一致，不会闪。
func _draw_rough_joints() -> void:
	var step: float = 110.0
	var w: float = thickness
	var joint: Color = _style_joint()

	var x: float = rect.position.x
	var col: int = 0
	while x < rect.end.x:
		_draw_broken_edge(Vector2(x, rect.position.y - w),
				Vector2(x, rect.position.y), joint, col * 31 + 7)
		_draw_broken_edge(Vector2(x, rect.end.y),
				Vector2(x, rect.end.y + w), joint, col * 31 + 11)
		x += step * (0.8 + 0.4 * _hash01(col * 17 + 3))
		col += 1

	var y: float = rect.position.y
	var row: int = 0
	while y < rect.end.y:
		_draw_broken_edge(Vector2(rect.position.x - w, y),
				Vector2(rect.position.x, y), joint, row * 29 + 13)
		_draw_broken_edge(Vector2(rect.end.x, y),
				Vector2(rect.end.x + w, y), joint, row * 29 + 19)
		y += step * (0.8 + 0.4 * _hash01(row * 23 + 5))
		row += 1


## 一条断续的短缝：拆成 3 段，中间那段按散列决定画不画。
func _draw_broken_edge(from: Vector2, to: Vector2, color: Color, seed_value: int) -> void:
	var mid: float = _hash01(seed_value)
	for i in 3:
		if i == 1 and mid < 0.45:
			continue
		var t0: float = float(i) / 3.0
		var t1: float = float(i + 1) / 3.0
		draw_line(from.lerp(to, t0), from.lerp(to, t1), color, 2.0)


## 冰棱（ICE）：墙面上几道斜裂 + 一排霜点。
## 冰墙不该有「缝」，该有「裂」—— 裂纹是斜的、粗细不一，从内沿向外劈。
func _draw_ice_cracks() -> void:
	var w: float = thickness
	var joint: Color = _style_joint()
	var frost := Color(1.0, 1.0, 1.0, 0.16)

	# 裂纹：沿四条墙带每隔 ~150 像素一道，角度由散列决定，深浅两段。
	var idx: int = 0
	var x: float = rect.position.x
	while x < rect.end.x:
		_draw_crack(Vector2(x, rect.position.y - w), Vector2.DOWN, w, idx * 13 + 3, joint)
		_draw_crack(Vector2(x, rect.end.y + w), Vector2.UP, w, idx * 13 + 17, joint)
		x += 150.0
		idx += 1
	var y: float = rect.position.y
	var idy: int = 0
	while y < rect.end.y:
		_draw_crack(Vector2(rect.position.x - w, y), Vector2.RIGHT, w, idy * 13 + 29, joint)
		_draw_crack(Vector2(rect.end.x + w, y), Vector2.LEFT, w, idy * 13 + 41, joint)
		y += 150.0
		idy += 1

	# 霜点：贴内沿一圈小白点，散列取位。冰宫的墙必须有「挂着霜」的读感。
	var step: float = 48.0
	var fx: float = rect.position.x
	while fx < rect.end.x:
		if _hash01(int(fx) * 7 + 1) < 0.4:
			draw_circle(Vector2(fx + step * 0.5, rect.position.y + 6.0), 1.8, frost)
			draw_circle(Vector2(fx + step * 0.3, rect.end.y - 6.0), 1.6, frost)
		fx += step
	var fy: float = rect.position.y
	while fy < rect.end.y:
		if _hash01(int(fy) * 11 + 2) < 0.4:
			draw_circle(Vector2(rect.position.x + 6.0, fy + step * 0.5), 1.8, frost)
			draw_circle(Vector2(rect.end.x - 6.0, fy + step * 0.3), 1.6, frost)
		fy += step


## 一道斜裂纹：从起点沿 dir 方向劈进墙带，路径带两次小角度偏折。
func _draw_crack(origin: Vector2, dir: Vector2, w: float, seed_value: int,
		color: Color) -> void:
	var angle: float = (float(seed_value % 7) - 3.0) * 0.22
	var a: Vector2 = dir.rotated(angle)
	var b: Vector2 = dir.rotated(-angle * 0.7)
	var p0: Vector2 = origin
	var p1: Vector2 = p0 + a * w * 0.45
	var p2: Vector2 = p1 + b * w * 0.35
	var p3: Vector2 = p2 + a * w * 0.30
	draw_polyline(PackedVector2Array([p0, p1, p2, p3]), color, 1.6, true)


## 铸板（PLATE）：竖缝间距更大，另加两排横向接缝与铆钉。
## 青铜殿的墙是铸出来的板：板与板之间是接缝，四角有铆钉头。
func _draw_plate_seams() -> void:
	var step: float = 160.0
	var w: float = thickness
	var joint: Color = _style_joint()
	var rivet := Color(0.0, 0.0, 0.0, 0.35)

	var x: float = rect.position.x
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y - w), Vector2(x, rect.position.y), joint, 2.0)
		draw_line(Vector2(x, rect.end.y), Vector2(x, rect.end.y + w), joint, 2.0)
		x += step
	var y: float = rect.position.y
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x - w, y), Vector2(rect.position.x, y), joint, 2.0)
		draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x + w, y), joint, 2.0)
		y += step

	# 横向中线接缝 + 铆钉：上下左右四条墙带各一条。
	var mid_top: float = rect.position.y - w * 0.5
	var mid_bottom: float = rect.end.y + w * 0.5
	var mx: float = rect.position.x
	while mx < rect.end.x:
		draw_line(Vector2(mx, mid_top), Vector2(mx + step, mid_top), joint, 1.4)
		draw_circle(Vector2(mx + 8.0, mid_top), 2.2, rivet)
		draw_circle(Vector2(mx + 8.0, mid_bottom), 2.2, rivet)
		mx += step
	var mid_left: float = rect.position.x - w * 0.5
	var mid_right: float = rect.end.x + w * 0.5
	var my: float = rect.position.y
	while my < rect.end.y:
		draw_line(Vector2(mid_left, my), Vector2(mid_left, my + step), joint, 1.4)
		draw_line(Vector2(mid_right, my), Vector2(mid_right, my + step), joint, 1.4)
		draw_circle(Vector2(mid_left, my + 8.0), 2.2, rivet)
		draw_circle(Vector2(mid_right, my + 8.0), 2.2, rivet)
		my += step


## 内沿：一圈主题色细线 + 三层由深到浅的暗角，做出「墙角有阴影」的层次。
## 三层比一层渐变更省事，也不需要贴图。
func _draw_inner_rim() -> void:
	for i in 3:
		var inset: float = 6.0 + float(i) * 12.0
		var alpha: float = 0.16 - float(i) * 0.045
		var band := Rect2(rect.position + Vector2(inset, inset),
				rect.size - Vector2(inset, inset) * 2.0)
		draw_rect(band, Color(0.0, 0.0, 0.0, maxf(0.0, alpha)), false, 12.0)
	draw_rect(rect, _style_rim(), false, 2.0)


## 确定性散列：同样的输入永远得到同样的 0~1。
## 墙上的抖动必须可复现 —— _draw 会被反复调用，用随机数墙会闪。
func _hash01(seed_value: int) -> float:
	var h: int = (seed_value * 2654435761) & 0x7FFFFFFF
	h = ((h >> 13) ^ h) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0
