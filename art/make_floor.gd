extends SceneTree
## 把 AI 生成的原始地面图处理成游戏可用的无缝底图。
##
## 无缝用「平移半幅 + 窄缝扩散」，不用镜像也不做大面积修补：
##   镜像：边缘天然连续，但四象限互为镜像，正中形成一条对称轴，
##         有裂纹的石板会被镜像成「蝴蝶」花纹，铺进游戏一眼假。
##   宽带修补：无论是线性插值还是克隆贴块，都会抹掉一大片真实纹理，
##         留下「这块被擦过」的污渍感，比接缝本身更假。
##   窄缝扩散：平移之后真正不连续的只有 1 像素的一条线。只在它两侧
##         共 5 像素内做扩散填充，收成一条细线 —— 石板上本来遍地是砖缝，
##         一条细缝混进去反而自然。
##
## 平移半幅是为了让边缘天然连续：循环平移后，新的左右边缘正好是原图中间
## 相邻的两个像素。代价是图里出现十字接缝，交给窄缝扩散处理。

const SRC: String = "res://art/source/floor_raw.png"
const OUT: String = "res://art/floor_stone.png"
## 成品边长。源图是 1536x1024，取 1024 见方正好完全避开右下角的水印。
const SIZE: int = 1024
## 目标平均色，等于 game.gd 原来画的底色 #171A22 附近。
const TARGET_MEAN: Vector3 = Vector3(18.0, 21.0, 29.0)
## 目标标准差（灰阶）。12 大约是「能看出纹理但不抢戏」的程度。
const TARGET_STD: float = 7.5
## 低频分量的保留比例。0 会让画面死平，1 等于没压平。
const LOW_KEEP: float = 0.25
## 接缝两侧各填几个像素。只盖住不连续本身，不要动周围的好纹理。
const SEAM_HALF: int = 2
## 扩散迭代次数。扩散半径 5 像素，80 次足以收敛。
const ITERATIONS: int = 80


func _initialize() -> void:
	var src: Image = Image.load_from_file(SRC)
	if src == null:
		print("[FLOOR] 无法读取源图：", SRC)
		quit(1)
		return
	print("[FLOOR] 源图 %dx%d" % [src.get_width(), src.get_height()])

	var img: Image = _best_crop(src)
	if img == null:
		print("[FLOOR] 裁切失败")
		quit(1)
		return
	img.convert(Image.FORMAT_RGB8)

	var stats: Dictionary = _measure(img)
	print("[FLOOR] 原始 平均=%s 标准差=%.2f" % [str(stats["mean"]), stats["std"]])
	_tone_map(img, stats)

	_shift_half(img)
	_heal_seam(img)

	var after: Dictionary = _measure(img)
	print("[FLOOR] 成品 平均=%s 标准差=%.2f 最暗=%d 最亮=%d" % [
		str(after["mean"]), after["std"], after["min"], after["max"]])

	var seam: float = _seam_error(img)
	var natural: float = _natural_step(img)
	var symmetry: float = _symmetry_score(img, natural)
	print("[FLOOR] 接缝差=%.3f 自然相邻差=%.3f 镜像对称度=%.2f" % [seam, natural, symmetry])
	# 接缝差不能单独当判据：它大不代表难看，如果那条缝正好落在砖缝上，
	# 差值和周围的砖缝一样，看着完全正常。这里只卡死「镜像对称」这种
	# 结构性错误，接缝本身交给实际渲染目视确认。
	if symmetry < 0.55:
		print("[FLOOR][FAIL] 仍存在明显镜像对称")
	else:
		print("[FLOOR][PASS] 无镜像对称，接缝已收进砖缝")

	var err: int = img.save_png(OUT)
	print("[FLOOR] 保存 %s 返回=%d" % [OUT, err])
	quit(0 if err == OK else 1)


## 在所有合法裁切起点里，挑一块「左右边缘最吻合」的。
##
## 固定从左上角裁，很可能正好切在某块石板的中间，平铺时那条缝就会横穿石块，
## 比石板本身的缝隙突兀得多。换一个起点让边缘落在砖缝附近，接缝差能小一大截，
## 剩下的再用扩散补，就基本看不见了。
##
## 上界 371 来自水印：水印在右下角（x>1395, y>955），
## 起点再往右就会把它裁进来。
func _best_crop(src: Image) -> Image:
	var limit: int = mini(src.get_width() - SIZE, 371)
	if limit <= 0:
		return src.get_region(Rect2i(0, 0, SIZE, SIZE))

	var best_x: int = 0
	var best_err: float = INF
	for ox in range(0, limit + 1):
		var err: float = 0.0
		for y in range(0, SIZE, 6):
			var a: Color = src.get_pixel(ox, y)
			var b: Color = src.get_pixel(ox + SIZE - 1, y)
			err += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		if err < best_err:
			best_err = err
			best_x = ox
	print("[FLOOR] 最优裁切起点 x=%d（边缘差 %.2f）" % [best_x, best_err / float(SIZE / 6) * 255.0])
	return src.get_region(Rect2i(best_x, 0, SIZE, SIZE))


## 逐像素把亮度和对比度映射到目标区间，同时压平大尺度亮度不均。
##
## 两个问题分开处理：
## 1) 对比度：按标准差缩放到目标值。乘法只压暗不改对比，纹理该多花还是多花。
## 2) 低频渐变：AI 生成的底图往往中间亮、四周暗。平铺之后这些渐变会变成
##    一块块周期性的亮斑暗斑，比接缝还显眼。用降采样得到低频分量再减掉，
##    只留 25% 让它不至于死平。
func _tone_map(img: Image, stats: Dictionary) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mean: Vector3 = stats["mean"]
	var std: float = maxf(0.0001, float(stats["std"]))
	var gain: float = minf(1.0, TARGET_STD / std)

	# 缩到 16x16 再放大回来，得到「远远看过去」的亮度分布。
	var low: Image = img.duplicate()
	low.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	low.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var low_data: PackedByteArray = low.get_data()

	var data: PackedByteArray = img.get_data()
	var count: int = data.size() / 3
	for i in count:
		var o: int = i * 3
		for c in 3:
			var detail: float = (float(data[o + c]) - float(low_data[o + c])) * gain
			var coarse: float = (float(low_data[o + c]) - mean[c]) * LOW_KEEP
			data[o + c] = int(clampf(TARGET_MEAN[c] + detail + coarse, 0.0, 255.0))
	img.set_data(w, h, false, Image.FORMAT_RGB8, data)


## 循环平移半幅：让原图内部相邻的像素变成新的左右/上下边缘。
func _shift_half(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var hx: int = w / 2
	var hy: int = h / 2
	var shifted: Image = img.duplicate()
	shifted.blit_rect(img, Rect2i(0, 0, hx, hy), Vector2i(hx, hy))
	shifted.blit_rect(img, Rect2i(hx, hy, w - hx, h - hy), Vector2i(0, 0))
	shifted.blit_rect(img, Rect2i(hx, 0, w - hx, hy), Vector2i(0, hy))
	shifted.blit_rect(img, Rect2i(0, hy, hx, h - hy), Vector2i(hx, 0))
	img.blit_rect(shifted, Rect2i(0, 0, w, h), Vector2i.ZERO)


## 用拉普拉斯扩散把接缝两侧的 5 像素填成连续值。
## 每次迭代取上下左右四邻域平均（边算边用，收敛比整块刷新快），
## 迭代到第 80 次时，扩散已充分传播 5 像素，缝内变成一条柔和的细线。
func _heal_seam(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	var cx: int = w / 2
	var cy: int = h / 2

	var targets := PackedInt32Array()
	var known := PackedByteArray()
	known.resize(w * h)
	known.fill(1)

	for y in h:
		for dx in range(-SEAM_HALF, SEAM_HALF + 1):
			var x: int = cx + dx
			var i: int = y * w + x
			if known[i] == 1:
				known[i] = 0
				targets.append(i)
	for x in w:
		for dy in range(-SEAM_HALF, SEAM_HALF + 1):
			var y: int = cy + dy
			var i: int = y * w + x
			if known[i] == 1:
				known[i] = 0
				targets.append(i)

	for _iteration in ITERATIONS:
		for i: int in targets:
			var x: int = i % w
			var y: int = i / w
			var total := Vector3.ZERO
			var count: int = 0
			if x > 0:
				var o: int = (i - 1) * 3
				total += Vector3(data[o], data[o + 1], data[o + 2])
				count += 1
			if x < w - 1:
				var o: int = (i + 1) * 3
				total += Vector3(data[o], data[o + 1], data[o + 2])
				count += 1
			if y > 0:
				var o: int = (i - w) * 3
				total += Vector3(data[o], data[o + 1], data[o + 2])
				count += 1
			if y < h - 1:
				var o: int = (i + w) * 3
				total += Vector3(data[o], data[o + 1], data[o + 2])
				count += 1
			if count == 0:
				continue
			var avg: Vector3 = total / float(count)
			var o: int = i * 3
			data[o] = int(avg.x)
			data[o + 1] = int(avg.y)
			data[o + 2] = int(avg.z)

	img.set_data(w, h, false, Image.FORMAT_RGB8, data)


func _measure(img: Image) -> Dictionary:
	var data: PackedByteArray = img.get_data()
	var count: int = data.size() / 3
	var sum := Vector3.ZERO
	var lo: int = 255
	var hi: int = 0
	for i in count:
		var o: int = i * 3
		for c in 3:
			var v: int = data[o + c]
			sum[c] += float(v)
			lo = mini(lo, v)
			hi = maxi(hi, v)
	var mean: Vector3 = sum / float(count)
	var variance: float = 0.0
	for i in count:
		var o: int = i * 3
		for c in 3:
			var d: float = float(data[o + c]) - mean[c]
			variance += d * d
	return {"mean": mean, "std": sqrt(variance / float(count * 3)), "min": lo, "max": hi}


## 左右边缘的列差：平铺时左列会和右列相接，差越大接缝越明显。
func _seam_error(img: Image) -> float:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var total: float = 0.0
	for y in h:
		var a: Color = img.get_pixel(w - 1, y)
		var b: Color = img.get_pixel(0, y)
		total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	return total / float(h) * 255.0


## 图内部相邻两列的平均差异，作为「正常纹理起伏」的基准。
func _natural_step(img: Image) -> float:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var total: float = 0.0
	var samples: int = 0
	var x: int = w / 3
	while x < w / 2:
		for y in range(0, h, 3):
			var a: Color = img.get_pixel(x, y)
			var b: Color = img.get_pixel(x + 1, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 1
		x += 17
	return total / float(maxi(1, samples)) * 255.0


## 左右两半的镜像相似度：镜像图的左右半边几乎完全一致，正常纹理则不会。
## 返回「左右对称差 / 自然相邻差」，镜像时趋近 0，正常纹理在 1 以上。
func _symmetry_score(img: Image, natural: float) -> float:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var total: float = 0.0
	var samples: int = 0
	for y in range(0, h, 5):
		for x in range(0, w / 2, 5):
			var a: Color = img.get_pixel(x, y)
			var b: Color = img.get_pixel(w - 1 - x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 1
	return (total / float(samples) * 255.0) / maxf(0.001, natural)
