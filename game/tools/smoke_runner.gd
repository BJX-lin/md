extends Node
## 冒烟测试：驱动 StoryEngine 验证 padlock / 命名插值 / 条件 / 剧情跳转 / 序列化。
## 用法：godot --headless --path game --script res://tools/smoke_test.gd
## 退出码：0 全部通过，1 存在失败。

var _frame := 0
var _fail := 0
var _lines: Array = []

func _ready() -> void:
	_run()
	get_tree().quit(1 if _fail > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _collect() -> void:
	StoryEngine.line_ready.connect(func(l: Dictionary):
		_lines.append(String(l.get("who", "")) + "|" + String(l.get("text", "")))
	)

func _drain(max_steps := 40) -> void:
	var i := 0
	while i < max_steps:
		if StoryEngine.waiting_choice or not StoryEngine.running:
			return
		StoryEngine.advance()
		i += 1

func _run() -> void:
	print("SMOKE: StoryEngine nodes = ", StoryEngine.nodes.size())
	_check(StoryEngine.nodes.size() == 560, "560 个剧情节点已解析")
	_check(StoryEngine.nodes.has("ch4_inner_lock"), "第四章密码锁节点存在")
	_check(StoryEngine.nodes.has("final_cabinet_lock"), "终章密码锁节点存在")

	# 1) 文本插值：玩家改名后「林昼」应被替换
	GameState.player_name = "江晚"
	_collect()
	StoryEngine.start("ch1_s2_b")   # me/zhouxu 台词含 林昼
	_drain()
	var joined := " / ".join(_lines)
	_check(joined.contains("江晚"), "正文中的林昼被替换为玩家名")
	_check(joined.contains("zhouxu|江晚。"), "周叙台词显示玩家名")

	# 2) 密码锁：成功路径
	StoryEngine.start("ch4_inner_lock")
	_drain()
	_check(not StoryEngine._padlock.is_empty(), "进入密码锁节点后引擎挂起")
	_check(String(StoryEngine._padlock.get("code", "")) == "0109", "第四章密码为 0109")
	StoryEngine.padlock_done(true)
	_check(GameState.current_node == "ch4_wall_open", "密码正确 -> 跳到 ch4_wall_open（实际 %s）" % GameState.current_node)

	# 3) 密码锁：失败路径
	StoryEngine.start("ch4_inner_lock")
	_drain()
	StoryEngine.padlock_done(false)
	_check(GameState.current_node == "ch4_inner_lock_fail", "密码错误 -> 跳到失败节点（实际 %s）" % GameState.current_node)

	# 4) 终章密码锁 2119
	StoryEngine.start("final_cabinet_lock")
	_drain()
	_check(String(StoryEngine._padlock.get("code", "")) == "2119", "终章密码为 2119")
	StoryEngine.padlock_done(true)
	_check(GameState.current_node == "final_cabinet_open", "终章密码正确 -> final_cabinet_open")

	# 5) final_a_broadcast 可自然推进到密码锁
	StoryEngine.start("final_a_broadcast")
	_drain()
	_check(not StoryEngine._padlock.is_empty(), "final_a_broadcast 推进到密码锁")

	# 6) 存档序列化包含玩家名
	var d := GameState.to_dict()
	_check(String(d.get("player_name", "")) == "江晚", "to_dict 包含玩家名")
	GameState.player_name = "林昼"
	GameState.from_dict(d)
	_check(GameState.player_name == "江晚", "from_dict 恢复玩家名")

	# 7) {pname} 插值
	var out := StoryEngine._resolve_text("你叫{pname}，高二三班。")
	_check(out == "你叫江晚，高二三班。", "{pname} 插值（%s）" % out)

	# 8) 条件求值
	GameState.set_flag("flag_test", true)
	_check(StoryEngine.eval_cond("flag_test and truth>=0"), "条件求值 flag and num")
	_check(not StoryEngine.eval_cond("item:item_admin_key"), "条件求值：未持有道具")
	GameState.add_item("item_admin_key")
	_check(StoryEngine.eval_cond("item:item_admin_key"), "条件求值：持有道具")

	# 9) 回顾长度封顶
	for i in 500:
		StoryEngine._append_history("me", "第 %d 行" % i)
	_check(GameState.history.size() == 400, "回想记录封顶 400（实际 %d）" % GameState.history.size())

	print("SMOKE: done, failures = ", _fail)
