extends SceneTree
## 由同一张 AI 石板原图派生八张「关卡主题地面」，供挑战模式逐关替换。
##
## 为什么不在游戏里用 modulate 染个色了事：
##   单纯调色只是把同一块灰石换个色相，八关看起来仍是同一间墓室；
##   而每关的地貌本来就不同（腐土、沼泽、海底、冰宫、青铜、血玉、雪原），
##   需要各自的材质特征 —— 水洼、藻斑、冰裂、铜锈、血纹、雪脊。
##
## 做法是「保留原图的真实石材细节，只重映射色阶 + 叠特征层」：
##   1) 灰度化后按本关的 暗/中/亮 三段色映射（duotone），石材的颗粒与裂缝全部保留，
##      但整体色相、明度完全变成另一处地方；
##   2) 叠低频斑块（水洼、苔藓、锈斑、雪堆）与细线（冰裂、血纹、地缝）；
##   3) 腐土 / 沼泽 / 雪原因不应该有砖缝，做一次降采样回放大来「糊掉砖缝」。
##
## 所有噪声在平铺边界上首尾相接（低频网格 + 环绕平滑 + 双线性放大），
## 所以八张图都是无缝的，不会在墓室里出现周期性接缝。

const SIZE: int = 1024
const SRC: String = "res://art/floor_stone.png"
const OUT_DIR: String = "res://art/floors"
const CONTACT: String = "res://art/preview/floors_contact.png"

## 每关一套：三段色 + 柔化程度 + 特征层。
## strength 是叠加强度，power 控制斑块的「集中度」（越大越只留最浓的部分，
## 水洼这种边界清晰的东西要用 2.5 以上，浮尘一类用 1.0）。
const THEMES: Array = [
	{
		"id": "ch1", "name": "七星鲁王宫",
		"dark": Color(0.043, 0.053, 0.072), "mid": Color(0.098, 0.118, 0.152),
		"light": Color(0.196, 0.226, 0.276), "soften": 0.0, "grain": 2.0,
		"patch_color": Color(0.046, 0.056, 0.076), "patch_strength": 0.28, "patch_power": 1.8,
		"vein_color": Color(0.0, 0.0, 0.0), "vein_strength": 0.0,
		"speck_color": Color(0.30, 0.33, 0.38), "speck_strength": 0.0,
		"band_color": Color(0.0, 0.0, 0.0), "band_strength": 0.0,
		"seed": 1101,
	},
	{
		"id": "ch2", "name": "积尸地",
		"dark": Color(0.052, 0.038, 0.029), "mid": Color(0.112, 0.086, 0.062),
		"light": Color(0.205, 0.158, 0.108), "soften": 0.78, "grain": 2.6,
		"patch_color": Color(0.042, 0.031, 0.024), "patch_strength": 0.46, "patch_power": 1.5,
		"vein_color": Color(0.0, 0.0, 0.0), "vein_strength": 0.0,
		"speck_color": Color(0.36, 0.33, 0.27), "speck_strength": 0.55,
		"band_color": Color(0.0, 0.0, 0.0), "band_strength": 0.0,
		"seed": 1202,
	},
	{
		"id": "ch3", "name": "蛇沼鬼城",
		"dark": Color(0.030, 0.052, 0.042), "mid": Color(0.068, 0.108, 0.082),
		"light": Color(0.126, 0.186, 0.126), "soften": 0.82, "grain": 1.8,
		"patch_color": Color(0.030, 0.072, 0.076), "patch_strength": 0.62, "patch_power": 2.6,
		"vein_color": Color(0.10, 0.20, 0.14), "vein_strength": 0.22,
		"speck_color": Color(0.20, 0.32, 0.16), "speck_strength": 0.30,
		"band_color": Color(0.10, 0.17, 0.14), "band_strength": 0.07,
		"seed": 1303,
	},
	{
		"id": "ch4", "name": "西沙海底墓",
		"dark": Color(0.022, 0.052, 0.068), "mid": Color(0.052, 0.112, 0.132),
		"light": Color(0.108, 0.196, 0.208), "soften": 0.26, "grain": 1.6,
		"patch_color": Color(0.042, 0.104, 0.086), "patch_strength": 0.46, "patch_power": 2.0,
		"vein_color": Color(0.0, 0.0, 0.0), "vein_strength": 0.0,
		"speck_color": Color(0.17, 0.30, 0.24), "speck_strength": 0.34,
		"band_color": Color(0.12, 0.24, 0.26), "band_strength": 0.10,
		"seed": 1404,
	},
	{
		"id": "ch5", "name": "云顶天宫",
		"dark": Color(0.058, 0.078, 0.104), "mid": Color(0.118, 0.156, 0.196),
		"light": Color(0.198, 0.262, 0.316), "soften": 0.16, "grain": 1.4,
		"patch_color": Color(0.290, 0.390, 0.470), "patch_strength": 0.20, "patch_power": 2.6,
		"vein_color": Color(0.400, 0.540, 0.640), "vein_strength": 0.20, "vein_width": 0.022,
		"speck_color": Color(0.60, 0.72, 0.80), "speck_strength": 0.22,
		"band_color": Color(0.0, 0.0, 0.0), "band_strength": 0.0,
		"seed": 1505,
	},
	{
		"id": "ch6", "name": "青铜神树",
		"dark": Color(0.042, 0.046, 0.032), "mid": Color(0.098, 0.100, 0.060),
		"light": Color(0.212, 0.184, 0.104), "soften": 0.12, "grain": 1.8,
		"patch_color": Color(0.056, 0.136, 0.118), "patch_strength": 0.50, "patch_power": 1.9,
		"vein_color": Color(0.0, 0.0, 0.0), "vein_strength": 0.0,
		"speck_color": Color(0.34, 0.27, 0.12), "speck_strength": 0.45,
		"band_color": Color(0.0, 0.0, 0.0), "band_strength": 0.0,
		"seed": 1606,
	},
	{
		"id": "ch7", "name": "西王母宫",
		"dark": Color(0.070, 0.028, 0.036), "mid": Color(0.132, 0.052, 0.060),
		"light": Color(0.238, 0.094, 0.102), "soften": 0.10, "grain": 1.7,
		"patch_color": Color(0.048, 0.020, 0.026), "patch_strength": 0.34, "patch_power": 1.8,
		"vein_color": Color(0.300, 0.062, 0.060), "vein_strength": 0.26, "vein_width": 0.020,
		"speck_color": Color(0.38, 0.30, 0.14), "speck_strength": 0.40,
		"band_color": Color(0.0, 0.0, 0.0), "band_strength": 0.0,
		"seed": 1707,
	},
	{
		"id": "ch8", "name": "长白山",
		"dark": Color(0.072, 0.090, 0.110), "mid": Color(0.142, 0.176, 0.204),
		"light": Color(0.300, 0.360, 0.410), "soften": 0.72, "grain": 2.2,
		"patch_color": Color(0.286, 0.344, 0.398), "patch_strength": 0.28, "patch_power": 2.2,
		"vein_color": Color(0.052, 0.078, 0.108), "vein_strength": 0.40, "vein_width": 0.024,
		"speck_color": Color(0.52, 0.62, 0.70), "speck_strength": 0.26,
		"band_color": Color(0.40, 0.48, 0.55), "band_strength": 0.09,
		"seed": 1808,
	},
]


func _initialize() -> void:
	var base: Image = Image.load_from_file(SRC)
	if base == null:
		print("[FLOOR] 无法读取底图：", SRC)
		quit(1)
		return
	base.convert(Image.FORMAT_RGB8)
	if base.get_width() != SIZE or base.get_height() != SIZE:
		base.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)

	var stats: Dictionary = _luma_stats(base)
	print("[FLOOR] 底图 平均亮度=%.4f 标准差=%.4f" % [stats["mean"], stats["std"]])

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var made: Array[Image] = []
	for theme: Dictionary in THEMES:
		var img: Image = _make(base, stats, theme)
		var path: String = "%s/floor_%s.png" % [OUT_DIR, theme["id"]]
		var err: int = img.save_png(path)
		print("[FLOOR] %s %s → %s (err=%d)" % [theme["id"], theme["name"], path, err])
		made.append(img)

	_contact_sheet(made)
	quit(0)


## 只统计亮度与标准差：色阶映射要把石材的全部细节铺满 暗→亮 区间，
## 而这个区间的宽度必须由原图的实际动态范围决定，写死常数会让八张图
## 要么灰成一片、要么锐得像噪点。
func _luma_stats(img: Image) -> Dictionary:
	var data: PackedByteArray = img.get_data()
	var n: int = data.size() / 3
	var sum: float = 0.0
	for i in n:
		var o: int = i * 3
		sum += float(data[o]) * 0.299 + float(data[o + 1]) * 0.587 + float(data[o + 2]) * 0.114
	var mean: float = sum / float(n) / 255.0
	var acc: float = 0.0
	for i in n:
		var o: int = i * 3
		var l: float = (float(data[o]) * 0.299
				+ float(data[o + 1]) * 0.587 + float(data[o + 2]) * 0.114) / 255.0
		acc += (l - mean) * (l - mean)
	return {"mean": mean, "std": sqrt(acc / float(n))}


func _make(base: Image, stats: Dictionary, theme: Dictionary) -> Image:
	var soften: float = theme["soften"]
	var src_data: PackedByteArray = base.get_data()
	var soft_data: PackedByteArray = PackedByteArray()
	if soften > 0.001:
		# 降到 1/4 再放回：砖缝和石纹被抹平成一片模糊的底色，
		# 剩下的粗糙感交给噪声斑块补 —— 腐土、沼泽、雪地上不该出现砌砖线。
		var soft: Image = base.duplicate()
		soft.resize(SIZE / 4, SIZE / 4, Image.INTERPOLATE_BILINEAR)
		soft.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
		soft_data = soft.get_data()

	# 色阶查找表：逐像素做 lerp 太慢，先按 0~255 把三段色铺成表，循环里只查表。
	var lut: PackedFloat32Array = PackedFloat32Array()
	lut.resize(256 * 3)
	var dark: Color = theme["dark"]
	var mid: Color = theme["mid"]
	var light: Color = theme["light"]
	for k in 256:
		var v: float = float(k) / 255.0
		var c: Color = dark.lerp(mid, v * 2.0) if v < 0.5 else mid.lerp(light, (v - 0.5) * 2.0)
		lut[k * 3] = c.r * 255.0
		lut[k * 3 + 1] = c.g * 255.0
		lut[k * 3 + 2] = c.b * 255.0

	var seed_value: int = theme["seed"]
	var blob: PackedByteArray = _mask(6, seed_value, 3).get_data()
	var mid_mask: PackedByteArray = _mask(20, seed_value + 7, 2).get_data()
	var fine: PackedByteArray = _mask(46, seed_value + 13, 1).get_data()

	var patch_lut: PackedFloat32Array = _value_lut(theme["patch_power"], theme["patch_strength"])
	var vein_lut: PackedFloat32Array = _vein_lut(
			theme["vein_strength"], theme.get("vein_width", 0.045))
	var speck_lut: PackedFloat32Array = _flat_lut(theme["speck_strength"])

	var patch_c: Color = theme["patch_color"]
	var vein_c: Color = theme["vein_color"]
	var speck_c: Color = theme["speck_color"]
	var band_c: Color = theme["band_color"]
	var band_strength: float = theme["band_strength"]
	var grain: float = theme["grain"]
	var mean: float = stats["mean"]
	var span: float = maxf(0.05, float(stats["std"]) * 5.0)

	# 斜向光带（水面反光 / 风雪流线）。整像素算 sin 太贵，预先摊成 360 格。
	var wave := PackedFloat32Array()
	wave.resize(360)
	for i in 360:
		wave[i] = 0.5 + 0.5 * sin(deg_to_rad(float(i)))

	var out := PackedByteArray()
	out.resize(SIZE * SIZE * 3)

	for y in SIZE:
		var row: int = y * SIZE
		for x in SIZE:
			var i: int = (row + x) * 3
			var lum: float = (float(src_data[i]) * 0.299
					+ float(src_data[i + 1]) * 0.587 + float(src_data[i + 2]) * 0.114) / 255.0
			if soften > 0.001:
				var sl: float = (float(soft_data[i]) * 0.299
						+ float(soft_data[i + 1]) * 0.587 + float(soft_data[i + 2]) * 0.114) / 255.0
				lum = lerpf(lum, sl, soften)

			var t: float = clampf(0.5 + (lum - mean) / span, 0.0, 1.0)
			var k: int = int(t * 255.0) * 3
			var r: float = lut[k]
			var g: float = lut[k + 1]
			var b: float = lut[k + 2]

			# 大块斑（水洼 / 苔藓 / 锈斑 / 雪堆）：只取噪声最浓的部分，边界才不会糊成一团。
			var pf: float = patch_lut[blob[i]]
			if pf > 0.0:
				r = lerpf(r, patch_c.r * 255.0, pf)
				g = lerpf(g, patch_c.g * 255.0, pf)
				b = lerpf(b, patch_c.b * 255.0, pf)

			# 细线（冰裂 / 血纹 / 地缝）：噪声等值线的窄带。
			var vf: float = vein_lut[fine[i]]
			if vf > 0.0:
				r = lerpf(r, vein_c.r * 255.0, vf)
				g = lerpf(g, vein_c.g * 255.0, vf)
				b = lerpf(b, vein_c.b * 255.0, vf)

			# 稀疏亮点（骨屑 / 铜屑 / 金粉 / 冰晶）。
			if theme["speck_strength"] > 0.0:
				var h: int = ((x * 73856093) ^ (y * 19349663)) & 0x3FFFFFFF
				if (h & 1023) < 3:
					var sf: float = speck_lut[h & 255]
					r = lerpf(r, speck_c.r * 255.0, sf)
					g = lerpf(g, speck_c.g * 255.0, sf)
					b = lerpf(b, speck_c.b * 255.0, sf)

			# 斜向光带：噪声调制相位，避免看出机械的平行条纹。
			if band_strength > 0.0:
				var phase: int = (x * 9 + y * 17 + int(mid_mask[i]) / 3) % 360
				var bf: float = wave[phase] * band_strength
				r = lerpf(r, band_c.r * 255.0, bf)
				g = lerpf(g, band_c.g * 255.0, bf)
				b = lerpf(b, band_c.b * 255.0, bf)

			# 细颗粒：没有它，色阶映射会把整张图压成一块平滑的塑料。
			var n: int = ((x * 374761393 + y * 668265263) ^ (x * y)) & 0xFF
			var grain_v: float = (float(n) / 255.0 - 0.5) * grain * 2.0
			out[i] = int(clampf(r + grain_v, 0.0, 255.0))
			out[i + 1] = int(clampf(g + grain_v, 0.0, 255.0))
			out[i + 2] = int(clampf(b + grain_v, 0.0, 255.0))

	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	img.set_data(SIZE, SIZE, false, Image.FORMAT_RGB8, out)
	return img


## 生成一张周期性灰度噪声：随机格点 → 环绕平滑 → 双线性放大。
## 平滑 3 次让方块状的格点化成有机的团块；环绕取样保证左右/上下首尾相接。
func _mask(cells: int, seed_value: int, smooth_passes: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := PackedFloat32Array()
	grid.resize(cells * cells)
	for i in cells * cells:
		grid[i] = rng.randf()

	for _pass in smooth_passes:
		var next := PackedFloat32Array()
		next.resize(cells * cells)
		for y in cells:
			for x in cells:
				var total: float = 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var sx: int = (x + dx + cells) % cells
						var sy: int = (y + dy + cells) % cells
						total += grid[sy * cells + sx]
				next[y * cells + x] = total / 9.0
		grid = next

	var small := Image.create(cells, cells, false, Image.FORMAT_RGB8)
	for y in cells:
		for x in cells:
			var v: int = int(clampf(grid[y * cells + x], 0.0, 1.0) * 255.0)
			small.set_pixel(x, y, Color8(v, v, v))
	small.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	return small


## 斑块强度表：pow 让噪声向「只在最浓处出现」收拢。
func _value_lut(power: float, strength: float) -> PackedFloat32Array:
	var lut := PackedFloat32Array()
	lut.resize(256)
	for k in 256:
		var v: float = float(k) / 255.0
		lut[k] = pow(v, power) * strength
	return lut


## 细线强度表：噪声值接近 0.5 的窄带才算线，带宽 0.045 约合 2~3 像素。
func _vein_lut(strength: float, width: float) -> PackedFloat32Array:
	var lut := PackedFloat32Array()
	lut.resize(256)
	for k in 256:
		var d: float = absf(float(k) / 255.0 - 0.5)
		var edge: float = 1.0 - smoothstep(0.0, width, d)
		lut[k] = edge * strength
	return lut


func _flat_lut(strength: float) -> PackedFloat32Array:
	var lut := PackedFloat32Array()
	lut.resize(256)
	for k in 256:
		lut[k] = strength
	return lut


## 八张缩略图拼一张，方便一眼对比风格差异是否够大。
func _contact_sheet(images: Array[Image]) -> void:
	if images.is_empty():
		return
	var cell: int = 256
	var cols: int = 4
	var rows: int = int(ceil(float(images.size()) / float(cols)))
	var sheet := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in images.size():
		var thumb: Image = images[i].duplicate()
		thumb.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(thumb, Rect2i(0, 0, cell, cell),
				Vector2i((i % cols) * cell, (i / cols) * cell))
	DirAccess.make_dir_recursive_absolute("res://art/preview")
	sheet.save_png(CONTACT)
	print("[FLOOR] 对比图 → ", CONTACT)
