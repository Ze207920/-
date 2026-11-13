# 可选角色：四个可操控人物，各有不同的属性、起手武器与专属主动技能。
#
# 为什么不给每个角色写一个 Player 子类：四个人的绘制流程完全一样（Q 版一头身），
# 差异只有配色、体型和两三个小配件。拆成四个子类等于把六百行绘制代码复制四遍，
# 以后改一次造型要改四个文件；用「一张数据表 + 几个开关」表达足够清楚。
class_name CharacterData
extends Resource

## 主动技能类型。效果实现在 Player.cast_skill()，这里只做标签。
enum Skill {
	FLAME, ## 范围灼烧 + 短暂加速
	DASH,  ## 无敌突进 + 沿途斩击
	BOMB,  ## 延迟引信 + 大范围爆炸
	RUSH,  ## 短时间攻速与移速暴涨
}

@export var id: String = "wuxie"
@export var display_name: String = "吴邪"
## 一行定位，显示在选人卡片的副标题上。
@export var role: String = "均衡"
## 选人卡片的说明文字，讲清这个人的玩法取向。
@export_multiline var blurb: String = ""
## 主题色：选人卡片、技能条、技能特效都用它，保证「这个人的东西是同一个颜色」。
@export var accent: Color = Color(0.36, 0.80, 1.00)

@export_group("外观")
@export var hair_color: Color = Color(0.19, 0.235, 0.345)
@export var cloth_color: Color = Color(0.36, 0.74, 1.0)
@export var cloth_deep_color: Color = Color(0.22, 0.45, 0.76)
@export var sleeve_color: Color = Color(0.14, 0.30, 0.52)
@export var trim_color: Color = Color(0.95, 0.97, 1.0)
## 体型横向缩放。Q 版靠「宽窄反差」区分胖瘦，比改身高有效得多。
@export var body_girth: float = 1.0
## 脑后长发（小哥）。
@export var hair_long: bool = false
## 墨镜（黑瞎子）。
@export var wear_glasses: bool = false
## 肚子（王胖子）。
@export var belly: bool = false

@export_group("属性")
@export var max_health: float = 100.0
@export var move_speed: float = 195.0
## 所有武器伤害的倍率。
@export var damage_scale: float = 1.0
## 所有武器冷却的倍率，小于 1 表示更快。
@export var cooldown_scale: float = 1.0
## 受到伤害的倍率，小于 1 表示更抗打。
@export var damage_taken_scale: float = 1.0
@export var pickup_radius: float = 120.0
## 额外的全局射程，用于「远程型」角色。
@export var range_bonus: float = 0.0
@export var starting_weapon: String = "pistol"

@export_group("技能")
@export var skill: Skill = Skill.FLAME
@export var skill_name: String = "火折子"
@export_multiline var skill_blurb: String = ""
@export var skill_cooldown: float = 12.0

## 技能阶梯：Lv1 起手 + Lv5 / Lv10 各解锁一个，共 3 个封顶。
## 每个技能独立冷却。旧的 skill / skill_name / skill_blurb / skill_cooldown
## 仍然保留为起手技能的快捷入口，标题页等只读一行文字的地方不用改。
var skill_ladder: Array[SkillDef] = []

## 每 5 级一次成长。前两次加技能，之后全部变成强化。
const SKILL_UNLOCK_STEP: int = 5
const SKILL_UNLOCK_MAX: int = 10
const SKILL_COUNT_MAX: int = 3
## 强化层数封顶：不封顶的话后期冷却会趋近于零、伤害无限膨胀，难度曲线失效。
const MASTERY_MAX: int = 6
## 每层强化：冷却 ×0.92、威力 +12%。两者都乘在基础值上，不叠加写回数据表。
const MASTERY_CD_SCALE: float = 0.92
const MASTERY_POWER_SCALE: float = 0.12


## 到 level 级为止应该解锁的全部技能（最多 3 个）。
func skills_at(level: int) -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	for def: SkillDef in skill_ladder:
		if def.unlock_level <= level:
			out.append(def)
			if out.size() >= SKILL_COUNT_MAX:
				break
	return out


## 三个技能集齐后，之后每 5 级给一层强化。Lv15 → 1 层，Lv20 → 2 层……
static func mastery_at(level: int) -> int:
	return clampi((level - SKILL_UNLOCK_MAX) / SKILL_UNLOCK_STEP, 0, MASTERY_MAX)


## 下一次成长发生在几级；已满级时返回 -1，供选人界面显示"已全部解锁"。
func next_growth_level(level: int) -> int:
	var next_skill: int = -1
	for def: SkillDef in skill_ladder:
		if def.unlock_level > level:
			next_skill = def.unlock_level
			break
	var tier: int = mastery_at(level)
	if tier < MASTERY_MAX:
		var next_mastery: int = SKILL_UNLOCK_MAX + (tier + 1) * SKILL_UNLOCK_STEP
		if next_skill < 0 or next_mastery < next_skill:
			return next_mastery
	return next_skill

## 当前选中的角色 id。空串表示还没选过，此时读存档、再退回默认角色。
## 和 Game.mode 一样是静态变量：重开一局会重建整个场景，这个选择必须跨过去。
static var current_id: String = ""

static var _all: Array[CharacterData] = []


static func all() -> Array[CharacterData]:
	if _all.is_empty():
		_all = [_wu_xie(), _zhang_qi_ling(), _wang_pang_zi(), _hei_xia_zi()]
	return _all


static func count() -> int:
	return all().size()


static func at(index: int) -> CharacterData:
	var list: Array[CharacterData] = all()
	if index < 0 or index >= list.size():
		return null
	return list[index]


static func by_id(character_id: String) -> CharacterData:
	for data: CharacterData in all():
		if data.id == character_id:
			return data
	return null


static func index_of(character_id: String) -> int:
	var list: Array[CharacterData] = all()
	for i in list.size():
		if list[i].id == character_id:
			return i
	return -1


static func default_character() -> CharacterData:
	return all()[0]


## 本局应当使用的角色。第一次调用会去存档里找一次，之后一直用静态缓存。
static func selected() -> CharacterData:
	if current_id == "":
		current_id = Records.load_character()
	var found: CharacterData = by_id(current_id)
	if found != null:
		return found
	var fallback: CharacterData = default_character()
	current_id = fallback.id
	return fallback


static func set_current(character_id: String) -> void:
	if by_id(character_id) == null:
		return
	current_id = character_id
	Records.save_character(character_id)


# ---------------------------------------------------------------- 四个角色
#
# 配平思路：四个人共用同一条敌人曲线，所以强弱差距必须体现在「打法」而不是
# 「绝对强度」上 —— 谁的数值都不该甩开别人一大截，否则选人界面会变成单选题。
#   · 血量 × 移速 × 伤害 三者互相牵制（胖子血厚则慢、小哥快则脆）；
#   · 起手武器决定前两分钟的体验：手枪稳、古刀近身但爆发高；
#   · 技能冷却与效果强度成反比（胖子一发定生死，所以给 15 秒）。

## 吴邪：均衡型。血量、速度、伤害都在中线，拾取范围最大 —— 新手最容易滚起雪球。
static func _wu_xie() -> CharacterData:
	var data := CharacterData.new()
	data.id = "wuxie"
	data.display_name = "吴邪"
	data.role = "均衡 · 好上手"
	data.blurb = "身手一般，但眼睛毒、学东西快。拾取范围最大，升级速度最快。"
	data.accent = Color(0.36, 0.80, 1.00)
	data.hair_color = Color(0.19, 0.235, 0.345)
	data.cloth_color = Color(0.36, 0.74, 1.0)
	data.cloth_deep_color = Color(0.22, 0.45, 0.76)
	data.sleeve_color = Color(0.14, 0.30, 0.52)
	data.trim_color = Color(0.95, 0.97, 1.0)
	data.body_girth = 1.0
	data.max_health = 100.0
	data.move_speed = 195.0
	data.damage_scale = 1.0
	data.cooldown_scale = 1.0
	data.damage_taken_scale = 1.0
	data.pickup_radius = 152.0
	data.starting_weapon = "pistol"
	data.skill = Skill.FLAME
	data.skill_name = "火折子"
	data.skill_blurb = "吹燃火折子，灼烧并推开身边的邪物，随后两秒半健步如飞"
	data.skill_cooldown = 12.0
	data.skill_ladder = [
		SkillDef.make({"lv": 1, "name": "火折子", "effect": SkillDef.Effect.BURST,
			"cd": 12.0, "power": 34.0, "radius": 208.0, "knock": 520.0,
			"duration": 2.5, "speed": 1.35,
			"blurb": "吹燃火折子，灼烧并推开身边的邪物，随后两秒半健步如飞"}),
		SkillDef.make({"lv": 5, "name": "洛阳铲", "effect": SkillDef.Effect.VOLLEY,
			"cd": 18.0, "power": 40.0, "radius": 150.0, "distance": 160.0,
			"knock": 420.0, "blurb": "朝前方一记横扫，把堵路的邪物铲开一条路"}),
		SkillDef.make({"lv": 10, "name": "笔记残页", "effect": SkillDef.Effect.HEAL,
			"cd": 24.0, "heal": 26.0, "invuln": 0.8,
			"blurb": "照着笔记上的记号避开要害，回血并短暂免伤"}),
	]
	return data


## 张起灵：疾行近战。速度最快、身板最薄，起手就是黑金古刀（回旋刀），
## 必须贴脸打 —— 玩得好是刀刀见血，玩不好是被尸墙淹掉。
static func _zhang_qi_ling() -> CharacterData:
	var data := CharacterData.new()
	data.id = "zhangqiling"
	data.display_name = "张起灵"
	data.role = "疾行 · 近身"
	data.blurb = "跑得最快，血最少，起手就是黑金古刀。靠冲刺斩进怪堆再杀出来。"
	data.accent = Color(0.46, 0.86, 0.98)
	data.hair_color = Color(0.085, 0.095, 0.125)
	data.cloth_color = Color(0.17, 0.20, 0.27)
	data.cloth_deep_color = Color(0.10, 0.12, 0.17)
	data.sleeve_color = Color(0.07, 0.09, 0.13)
	data.trim_color = Color(0.68, 0.74, 0.84)
	data.body_girth = 0.94
	data.hair_long = true
	data.max_health = 88.0
	data.move_speed = 228.0
	data.damage_scale = 1.18
	data.cooldown_scale = 0.95
	data.damage_taken_scale = 1.0
	data.pickup_radius = 106.0
	data.starting_weapon = "blade"
	data.skill = Skill.DASH
	data.skill_name = "黑金古刀"
	data.skill_blurb = "向前突进一段并斩开沿途所有邪物，突进期间不受伤"
	data.skill_cooldown = 9.0
	data.skill_ladder = [
		SkillDef.make({"lv": 1, "name": "黑金古刀", "effect": SkillDef.Effect.DASH,
			"cd": 9.0, "power": 38.0, "distance": 320.0, "knock": 280.0,
			"invuln": 0.75, "duration": 1.2, "speed": 1.2,
			"blurb": "向前突进一段并斩开沿途所有邪物，突进期间不受伤"}),
		SkillDef.make({"lv": 5, "name": "麒麟踏", "effect": SkillDef.Effect.RING,
			"cd": 18.0, "power": 34.0, "inner": 90.0, "radius": 230.0, "knock": 600.0,
			"blurb": "踏地震开一圈，近身的邪物被推得最远"}),
		SkillDef.make({"lv": 10, "name": "发丘指", "effect": SkillDef.Effect.VOLLEY,
			"cd": 20.0, "power": 52.0, "radius": 125.0, "distance": 150.0, "knock": 300.0,
			"blurb": "两指探穴，朝前方一记精准重击"}),
	]
	return data


## 王胖子：厚血重装。血最多、跑得最慢、受伤打折，适合站着扛；
## 技能是延迟引信的炸药，用来一次性清掉糊在脸上的整片怪。
static func _wang_pang_zi() -> CharacterData:
	var data := CharacterData.new()
	data.id = "wangpangzi"
	data.display_name = "王胖子"
	data.role = "厚血 · 硬抗"
	data.blurb = "血厚、抗打、跑得慢。一颗震天雷能把整圈邪物送走。"
	data.accent = Color(0.98, 0.68, 0.35)
	data.hair_color = Color(0.16, 0.14, 0.12)
	data.cloth_color = Color(0.72, 0.60, 0.40)
	data.cloth_deep_color = Color(0.44, 0.35, 0.23)
	data.sleeve_color = Color(0.56, 0.44, 0.29)
	data.trim_color = Color(0.96, 0.91, 0.80)
	data.body_girth = 1.26
	data.belly = true
	data.max_health = 170.0
	data.move_speed = 166.0
	data.damage_scale = 0.92
	data.cooldown_scale = 1.10
	data.damage_taken_scale = 0.72
	data.pickup_radius = 122.0
	data.starting_weapon = "pistol"
	data.skill = Skill.BOMB
	data.skill_name = "震天雷"
	data.skill_blurb = "往脚下前方扔一包工兵炸药，半秒引信后炸开一大片"
	data.skill_cooldown = 15.0
	data.skill_ladder = [
		SkillDef.make({"lv": 1, "name": "震天雷", "effect": SkillDef.Effect.BOMB,
			"cd": 15.0, "power": 92.0, "radius": 250.0,
			"blurb": "往脚下前方扔一包工兵炸药，半秒引信后炸开一大片"}),
		SkillDef.make({"lv": 5, "name": "摸金护身", "effect": SkillDef.Effect.WARD,
			"cd": 20.0, "duration": 6.0, "ward": 0.55,
			"blurb": "厚膘加摸金符，六秒内受到的伤害大幅打折"}),
		SkillDef.make({"lv": 10, "name": "双管猎枪", "effect": SkillDef.Effect.VOLLEY,
			"cd": 19.0, "power": 58.0, "radius": 170.0, "distance": 190.0, "knock": 520.0,
			"blurb": "两管齐发，把正前方的邪物轰出一条路"}),
	]
	return data


## 黑瞎子：远程速射。攻速最快、射程最远，但子弹伤害平庸 —— 靠持续输出压场。
static func _hei_xia_zi() -> CharacterData:
	var data := CharacterData.new()
	data.id = "heixiazi"
	data.display_name = "黑瞎子"
	data.role = "远程 · 速射"
	data.blurb = "永远戴着墨镜笑。攻速和射程都最高，用弹幕把怪压在半路。"
	data.accent = Color(0.92, 0.36, 0.38)
	data.hair_color = Color(0.075, 0.075, 0.095)
	data.cloth_color = Color(0.13, 0.13, 0.16)
	data.cloth_deep_color = Color(0.08, 0.08, 0.11)
	data.sleeve_color = Color(0.09, 0.09, 0.12)
	data.trim_color = Color(0.78, 0.26, 0.28)
	data.body_girth = 1.0
	data.wear_glasses = true
	data.max_health = 92.0
	data.move_speed = 208.0
	data.damage_scale = 1.05
	data.cooldown_scale = 0.86
	data.damage_taken_scale = 1.0
	data.pickup_radius = 100.0
	data.range_bonus = 110.0
	data.starting_weapon = "pistol"
	data.skill = Skill.RUSH
	data.skill_name = "狂风连射"
	data.skill_blurb = "六秒内攻速接近翻倍、移速提升，把整片邪物压在半路"
	data.skill_cooldown = 16.0
	data.skill_ladder = [
		SkillDef.make({"lv": 1, "name": "狂风连射", "effect": SkillDef.Effect.BUFF,
			"cd": 16.0, "duration": 6.0, "speed": 1.3, "atk": 0.55,
			"blurb": "六秒内攻速接近翻倍、移速提升，把整片邪物压在半路"}),
		SkillDef.make({"lv": 5, "name": "夜视瞄准", "effect": SkillDef.Effect.VOLLEY,
			"cd": 18.0, "power": 62.0, "radius": 150.0, "distance": 260.0, "knock": 380.0,
			"blurb": "墨镜后的眼睛锁死远处，一枪打穿前方一片"}),
		SkillDef.make({"lv": 10, "name": "蛇沼烟雾", "effect": SkillDef.Effect.RING,
			"cd": 20.0, "power": 40.0, "inner": 100.0, "radius": 270.0, "knock": 620.0,
			"blurb": "一枚烟雾弹炸开，中距离的邪物被震得七零八落"}),
	]
	return data
