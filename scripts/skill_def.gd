# 单个主动技能的定义。
#
# 以前四个角色各有一个写死在 Player.cast_skill() 里的分支，要加技能就得往
# switch 里继续堆 case。现在把「技能」变成数据：名字、解锁等级、冷却、效果类型、
# 以及一组效果参数，执行器只认 Effect 枚举，不认具体角色。
# 于是每升 5 级解锁一个新技能只需要在角色表里多加一行配置。
class_name SkillDef
extends Resource

## 效果类型。数值差异全部放在下面的参数里，执行器只有这八种分支。
enum Effect {
	BURST,   ## 以自身为圆心的范围伤害 + 击退
	DASH,    ## 向前突进，斩开沿途目标，期间无敌
	BOMB,    ## 在身前放一枚延迟引信炸药
	BUFF,    ## 临时攻速 / 移速增益
	HEAL,    ## 回血 + 短暂无敌
	WARD,    ## 临时减伤（可附带移速）
	RING,    ## 环形冲击：只打中距离一圈，贴脸的反而漏掉
	VOLLEY,  ## 朝面朝方向的扇形（用前方偏移圆近似）打击 + 击退
}

## 解锁所需等级。1 是起手技能，之后每 5 级一个。
var unlock_level: int = 1
var id: String = ""
var name: String = "技能"
var blurb: String = ""
var effect: Effect = Effect.BURST
var cooldown: float = 12.0

## 伤害类参数。
var power: float = 0.0
var radius: float = 0.0
var inner_radius: float = 0.0
var knockback: float = 0.0
## 朝前方偏移多远结算（VOLLEY），或突进距离（DASH）。
var distance: float = 0.0

## 增益类参数。
var duration: float = 0.0
var speed_scale: float = 1.0
var cooldown_scale: float = 1.0
var heal_amount: float = 0.0
var invuln: float = 0.0
## WARD 期间的受伤倍率，0.5 表示伤害减半。
var reduction: float = 1.0


## 用字典建一条技能定义。字典比十几个带默认值的参数好读，
## 每条配置一眼能看到「这招改了哪几项」，没写的参数走上面的默认值。
static func make(cfg: Dictionary) -> SkillDef:
	var def := SkillDef.new()
	def.unlock_level = int(cfg.get("lv", 1))
	def.name = String(cfg.get("name", "技能"))
	def.id = String(cfg.get("id", def.name))
	def.blurb = String(cfg.get("blurb", ""))
	def.effect = int(cfg.get("effect", Effect.BURST)) as Effect
	def.cooldown = float(cfg.get("cd", 12.0))
	def.power = float(cfg.get("power", 0.0))
	def.radius = float(cfg.get("radius", 0.0))
	def.inner_radius = float(cfg.get("inner", 0.0))
	def.knockback = float(cfg.get("knock", 0.0))
	def.distance = float(cfg.get("distance", 0.0))
	def.duration = float(cfg.get("duration", 0.0))
	def.speed_scale = float(cfg.get("speed", 1.0))
	def.cooldown_scale = float(cfg.get("atk", 1.0))
	def.heal_amount = float(cfg.get("heal", 0.0))
	def.invuln = float(cfg.get("invuln", 0.0))
	def.reduction = float(cfg.get("ward", 1.0))
	return def


## 供 UI 用的一行说明：解锁等级 + 名字。
func tier_text() -> String:
	return "Lv%-2d %s" % [unlock_level, name]
