# UI 统一视觉：颜色、字体、面板样式。
#
# 字体优先用工程内自带的子集化思源黑体（assets/fonts/NotoSansSC-Subset.ttf）。
# 早先用的是 SystemFont，桌面端能靠系统回退到中文字体，但 Web 导出没有系统字体，
# 中文会整片变成方框 —— 打包字体是唯一在浏览器里也成立的做法。
# 桌面端再挂一层 SystemFont 兜底，万一以后加了文案没重新子集化也不至于掉字。
class_name UiStyle
extends RefCounted

const TEXT: Color = Color(0.94, 0.96, 0.99)
const DIM: Color = Color(0.60, 0.67, 0.76)
const ACCENT: Color = Color(0.36, 0.80, 1.00)
const HP: Color = Color(0.94, 0.30, 0.36)
const HP_LOW: Color = Color(1.00, 0.24, 0.28)
const XP: Color = Color(0.42, 0.90, 0.95)
const PANEL: Color = Color(0.06, 0.07, 0.10, 0.96)
const BORDER: Color = Color(0.26, 0.33, 0.42)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.62)

## 工程内自带的字体子集：只含源码里出现过的字，约 380 KB。
## 改了文案之后跑 python tools/build_font.py 重新生成。
const BUNDLED_FONT: String = "res://assets/fonts/NotoSansSC-Subset.ttf"

const FONT_NAMES: Array[String] = [
	"Microsoft YaHei UI",
	"Microsoft YaHei",
	"PingFang SC",
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"sans-serif",
]

static var _font: Font = null
static var _theme: Theme = null


static func font() -> Font:
	if _font == null:
		var bundled := load(BUNDLED_FONT) as FontFile
		if bundled != null:
			# Web 端没有系统字体可回退，装了也没用，跳过以免日志里冒警告。
			if not OS.has_feature("web"):
				bundled.fallbacks = [_system_font()]
			_font = bundled
		else:
			push_warning("缺少内置字体，回退到系统字体：" + BUNDLED_FONT)
			_font = _system_font()
	return _font


static func _system_font() -> SystemFont:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(FONT_NAMES)
	system.allow_system_fallback = true
	return system


## 全局主题：挂在根 Control 上，子节点自动继承字体与默认字号。
static func theme() -> Theme:
	if _theme == null:
		var built := Theme.new()
		built.default_font = font()
		built.default_font_size = 15
		_theme = built
	return _theme


## 带一像素投影的文字：纯色字压在高对比度的场景上会糊，加投影能保证可读。
static func draw_label(canvas: CanvasItem, pos: Vector2, text: String, font_size: int,
		color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var font: Font = font()
	canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, align, width, font_size, SHADOW)
	canvas.draw_string(font, pos, text, align, width, font_size, color)


## 自动换行的多行文字。draw_string 不会断行，长句必须靠这个才能不超出面板。
static func draw_paragraph(canvas: CanvasItem, pos: Vector2, text: String, font_size: int,
		color: Color, width: float, max_lines: int = -1) -> void:
	var font: Font = font()
	canvas.draw_multiline_string(font, pos + Vector2(1.0, 1.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, width, font_size, max_lines, SHADOW)
	canvas.draw_multiline_string(font, pos, text,
			HORIZONTAL_ALIGNMENT_LEFT, width, font_size, max_lines, color)


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(0.0)
	return style


static func button_style(base: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = base
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 11.0
	style.content_margin_bottom = 11.0
	return style
