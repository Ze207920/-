# 关卡主题：把「这一关长在哪儿」收敛到一个对象里。
#
# 挑战模式八关的地点差异很大 —— 鲁王宫是青石墓道、积尸地是腐土、蛇沼是泥浆、
# 海底墓浸在水里、云顶天宫结着寒冰、青铜神树爬满铜绿、西王母宫是血玉、
# 长白山埋在风雪里。地面贴图、四壁配色、氛围罩色、碎石材质都从这里取，
# 各系统（Game / ArenaWalls / Obstacle）只认这一个对象，不再各自散配颜色。
#
# 生存模式（level == null）用 tomb：就是最初那间青灰墓室，一切照旧。
class_name ArenaTheme
extends RefCounted

## 墙带的画法。石墓砌砖、荒土垒石、寒冰开裂、青铜铸板，观感完全不同。
enum WallStyle {
	BRICK,  ## 规整砖缝（默认墓室）。
	ROUGH,  ## 断续垒石：缝时断时续，石块大小不一。
	ICE,    ## 冰棱裂缝 + 霜点。
	PLATE,  ## 铸板：横缝 + 铆钉。
}

## 底面贴图。全部在导出前由 art/make_arena_floors.gd 生成，缺一张就编译报错，
## 正好把「改了生成器忘了重跑」拦在打包阶段。
const TEX_TOMB: Texture2D = preload("res://art/floor_stone.png")
const TEX_CH1: Texture2D = preload("res://art/floors/floor_ch1.png")
const TEX_CH2: Texture2D = preload("res://art/floors/floor_ch2.png")
const TEX_CH3: Texture2D = preload("res://art/floors/floor_ch3.png")
const TEX_CH4: Texture2D = preload("res://art/floors/floor_ch4.png")
const TEX_CH5: Texture2D = preload("res://art/floors/floor_ch5.png")
const TEX_CH6: Texture2D = preload("res://art/floors/floor_ch6.png")
const TEX_CH7: Texture2D = preload("res://art/floors/floor_ch7.png")
const TEX_CH8: Texture2D = preload("res://art/floors/floor_ch8.png")

var id: String = "tomb"
## 地面贴图（世界尺寸下按 Game.FLOOR_SCALE 缩放平铺）。
var floor_texture: Texture2D = TEX_TOMB
## 盖在整个场地上的氛围罩色。alpha 压得很低，只够把整间墓室
## 「染色」成这一关的光线 —— 冰宫偏冷、血玉偏暗红，一眼区分。
var ambient: Color = Color(0.55, 0.70, 1.00, 0.05)
## 四壁。
var wall_style: WallStyle = WallStyle.BRICK
var wall_top: Color = Color(0.30, 0.31, 0.36)
var wall_side: Color = Color(0.21, 0.22, 0.26)
var wall_bottom: Color = Color(0.12, 0.13, 0.16)
var wall_joint: Color = Color(0.10, 0.11, 0.14, 0.55)
## 内沿高光：贴着可走区域的一圈，颜色跟本关的主题色走。
var wall_rim: Color = Color(0.42, 0.78, 0.92, 0.28)
## 碎石（随机障碍）的三段色。冰关是冰块、铜关是铜片、雪关是冻岩。
var rock_base: Color = Color(0.39, 0.41, 0.45)
var rock_light: Color = Color(0.56, 0.58, 0.62)
var rock_dark: Color = Color(0.23, 0.25, 0.28)


## 按关卡取主题。level 为 null 时是生存模式，永远用最初的墓室。
static func for_level(level: ChallengeData) -> ArenaTheme:
	if level == null:
		return _make("tomb", TEX_TOMB,
				Color(0.55, 0.70, 1.00, 0.05),
				WallStyle.BRICK,
				Color(0.30, 0.31, 0.36), Color(0.21, 0.22, 0.26),
				Color(0.12, 0.13, 0.16), Color(0.10, 0.11, 0.14, 0.55),
				Color(0.42, 0.78, 0.92, 0.28),
				Color(0.39, 0.41, 0.45), Color(0.56, 0.58, 0.62), Color(0.23, 0.25, 0.28))
	match level.id:
		"ch1":
			return _make("ch1", TEX_CH1,
					Color(0.50, 0.66, 0.95, 0.05),
					WallStyle.BRICK,
					Color(0.28, 0.30, 0.36), Color(0.19, 0.21, 0.26),
					Color(0.11, 0.12, 0.16), Color(0.09, 0.10, 0.14, 0.55),
					Color(0.45, 0.62, 0.92, 0.28),
					Color(0.37, 0.40, 0.45), Color(0.54, 0.57, 0.62), Color(0.21, 0.23, 0.27))
		"ch2":
			return _make("ch2", TEX_CH2,
					Color(0.90, 0.66, 0.42, 0.05),
					WallStyle.ROUGH,
					Color(0.26, 0.20, 0.14), Color(0.17, 0.13, 0.10),
					Color(0.10, 0.08, 0.06), Color(0.08, 0.06, 0.05, 0.60),
					Color(0.78, 0.58, 0.34, 0.26),
					Color(0.34, 0.27, 0.20), Color(0.48, 0.39, 0.30), Color(0.19, 0.15, 0.11))
		"ch3":
			return _make("ch3", TEX_CH3,
					Color(0.40, 0.85, 0.52, 0.06),
					WallStyle.ROUGH,
					Color(0.17, 0.23, 0.16), Color(0.12, 0.16, 0.11),
					Color(0.07, 0.09, 0.07), Color(0.05, 0.07, 0.05, 0.60),
					Color(0.46, 0.78, 0.42, 0.26),
					Color(0.26, 0.33, 0.24), Color(0.38, 0.47, 0.34), Color(0.14, 0.18, 0.13))
		"ch4":
			return _make("ch4", TEX_CH4,
					Color(0.30, 0.78, 0.95, 0.07),
					WallStyle.BRICK,
					Color(0.14, 0.24, 0.28), Color(0.10, 0.17, 0.21),
					Color(0.06, 0.10, 0.13), Color(0.04, 0.08, 0.10, 0.60),
					Color(0.36, 0.76, 0.86, 0.30),
					Color(0.26, 0.36, 0.40), Color(0.38, 0.52, 0.56), Color(0.13, 0.19, 0.22))
		"ch5":
			return _make("ch5", TEX_CH5,
					Color(0.60, 0.84, 1.00, 0.08),
					WallStyle.ICE,
					Color(0.28, 0.38, 0.48), Color(0.20, 0.27, 0.35),
					Color(0.12, 0.16, 0.22), Color(0.08, 0.12, 0.18, 0.55),
					Color(0.64, 0.90, 1.00, 0.34),
					Color(0.52, 0.65, 0.78), Color(0.74, 0.86, 0.95), Color(0.32, 0.42, 0.52))
		"ch6":
			return _make("ch6", TEX_CH6,
					Color(0.42, 0.88, 0.68, 0.06),
					WallStyle.PLATE,
					Color(0.25, 0.25, 0.15), Color(0.17, 0.17, 0.10),
					Color(0.10, 0.10, 0.06), Color(0.07, 0.08, 0.05, 0.60),
					Color(0.44, 0.82, 0.62, 0.28),
					Color(0.40, 0.37, 0.24), Color(0.56, 0.52, 0.34), Color(0.22, 0.21, 0.13))
		"ch7":
			return _make("ch7", TEX_CH7,
					Color(0.95, 0.42, 0.42, 0.06),
					WallStyle.BRICK,
					Color(0.25, 0.13, 0.15), Color(0.17, 0.09, 0.11),
					Color(0.09, 0.05, 0.06), Color(0.07, 0.03, 0.04, 0.60),
					Color(0.85, 0.34, 0.36, 0.30),
					Color(0.34, 0.21, 0.23), Color(0.50, 0.32, 0.34), Color(0.18, 0.11, 0.13))
		"ch8":
			return _make("ch8", TEX_CH8,
					Color(0.68, 0.84, 1.00, 0.07),
					WallStyle.ICE,
					Color(0.34, 0.42, 0.50), Color(0.24, 0.30, 0.37),
					Color(0.13, 0.16, 0.21), Color(0.09, 0.12, 0.16, 0.55),
					Color(0.58, 0.82, 1.00, 0.30),
					Color(0.44, 0.52, 0.62), Color(0.62, 0.72, 0.82), Color(0.25, 0.31, 0.40))
		_:
			return for_level(null)


static func _make(theme_id: String, texture: Texture2D, ambient_value: Color,
		style: WallStyle, top: Color, side: Color, bottom: Color, joint: Color,
		rim: Color, rock_base_value: Color, rock_light_value: Color,
		rock_dark_value: Color) -> ArenaTheme:
	var theme := ArenaTheme.new()
	theme.id = theme_id
	theme.floor_texture = texture
	theme.ambient = ambient_value
	theme.wall_style = style
	theme.wall_top = top
	theme.wall_side = side
	theme.wall_bottom = bottom
	theme.wall_joint = joint
	theme.wall_rim = rim
	theme.rock_base = rock_base_value
	theme.rock_light = rock_light_value
	theme.rock_dark = rock_dark_value
	return theme
