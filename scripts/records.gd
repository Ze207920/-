# 最佳记录：把最长存活时间与击杀数存到 user:// 下，重启后仍能读到。
#
# 只在有真实显示环境时写入。headless 下（自动化平衡仿真）玩家不是人，
# 写进去会覆盖掉玩家自己的成绩 —— 这类"测试污染存档"的坑很难事后发现。
class_name Records
extends RefCounted

const PATH: String = "user://records.cfg"
const SECTION: String = "best"
## 挑战模式的每一关各占一个 section，前缀固定，方便以后整段清理或统计。
const CHALLENGE_PREFIX: String = "challenge_"
## 上次选的角色。单独一节，和成绩分开，方便以后清空成绩但保留偏好。
const CHARACTER_SECTION: String = "player"

## 测试用的总开关。截图脚本会用真实窗口跑一局（存活几秒就死），
## 若不禁用，这一局的 00:04 会覆盖玩家真实的成绩。
static var enabled: bool = true


static func is_available() -> bool:
	return enabled and DisplayServer.get_name() != "headless"


## 读取最佳记录；没有存档或存档损坏时返回零值。
static func load_best() -> Dictionary:
	var empty: Dictionary = {"time": 0.0, "kills": 0, "level": 1}
	if not is_available():
		return empty
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return empty
	return {
		"time": maxf(0.0, float(config.get_value(SECTION, "time", 0.0))),
		"kills": maxi(0, int(config.get_value(SECTION, "kills", 0))),
		"level": maxi(1, int(config.get_value(SECTION, "level", 1))),
	}


## 提交一局成绩。只有超过历史最佳才写入，返回是否刷新了纪录。
static func submit(time: float, kills: int, level: int) -> bool:
	if not is_available():
		return false
	var best: Dictionary = load_best()
	if time <= float(best["time"]):
		return false
	var config := ConfigFile.new()
	config.set_value(SECTION, "time", time)
	config.set_value(SECTION, "kills", kills)
	config.set_value(SECTION, "level", level)
	config.save(PATH)
	return true


# ---------------------------------------------------------------- 挑战模式

static func _challenge_section(level_id: String) -> String:
	return CHALLENGE_PREFIX + level_id


## 读某一关的记录：{"cleared": 是否通关过, "time": 最佳存活秒数, "kills": 最佳击杀}。
static func challenge_record(level_id: String) -> Dictionary:
	var empty: Dictionary = {"cleared": false, "time": 0.0, "kills": 0}
	if not is_available():
		return empty
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return empty
	var section: String = _challenge_section(level_id)
	return {
		"cleared": bool(config.get_value(section, "cleared", false)),
		"time": maxf(0.0, float(config.get_value(section, "time", 0.0))),
		"kills": maxi(0, int(config.get_value(section, "kills", 0))),
	}


static func challenge_cleared(level_id: String) -> bool:
	return bool(challenge_record(level_id)["cleared"])


## 提交一关的成绩，返回是否刷新了纪录（首次通关也算）。
## 「已通关」是不可回退的标记：之后打得更差也不会把通关状态抹掉，
## 否则玩家偶然一次失误就掉回没通关，下一关又被锁上。
static func submit_challenge(level_id: String, cleared: bool, time: float, kills: int) -> bool:
	if not is_available():
		return false
	var best: Dictionary = challenge_record(level_id)
	var was_cleared: bool = bool(best["cleared"])
	var improved: bool = (cleared and not was_cleared) or time > float(best["time"])
	if not improved:
		return false

	var config := ConfigFile.new()
	# 先读再改：一局只写自己那一节，其它关卡的记录必须原样保留。
	# 首次运行时文件不存在，load 会返回错误 —— 那是正常情况，不用管。
	config.load(PATH)
	var section: String = _challenge_section(level_id)
	config.set_value(section, "cleared", was_cleared or cleared)
	config.set_value(section, "time", maxf(float(best["time"]), time))
	config.set_value(section, "kills", maxi(int(best["kills"]), kills))
	config.save(PATH)
	return true


# ---------------------------------------------------------------- 角色选择

## 上次选用的角色 id；没存过或读不到时返回空串，由 CharacterData 退回默认角色。
static func load_character() -> String:
	if not is_available():
		return ""
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return ""
	return String(config.get_value(CHARACTER_SECTION, "character", ""))


## 记住这次的选择。只在选人界面确认时写一次，不是每局都写。
static func save_character(character_id: String) -> void:
	if not is_available() or character_id == "":
		return
	var config := ConfigFile.new()
	# 先读再改：这一段只动角色字段，成绩与挑战进度必须原样保留。
	config.load(PATH)
	config.set_value(CHARACTER_SECTION, "character", character_id)
	config.save(PATH)
