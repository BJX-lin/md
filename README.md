# 《第十三节课》 THE 13TH PERIOD

国产校园恐怖文字互动视觉小说（AVG）。

- 引擎：Godot Engine 4.7.1 stable
- 目标平台：Android 手机（竖屏/横屏自适应，渲染后端 Mobile）
- 时长：约 2~3 小时，4 章 + 终章，多结局
- 玩法：文本剧情 / 选项分支 / 密码锁解谜 / 线索与道具收集 / 理智与信任数值系统 / 存档读档 / 周目循环

## 直接下载

完整工程（含全部资源与工具，用 Godot 4.7.1 打开 `game/project.godot` 即可）：

```
https://github.com/BJX-lin/md/raw/arena/01a018ff-md/dist/The13thPeriod_v1.1.1_full_project.zip
```

## 目录结构

```
game/                  # Godot 工程（直接用 Godot 4.7.1 打开 game/project.godot）
├── autoload/          # 全局单例：配置 / 状态 / 剧情引擎 / 音频 / 存档 / 资源缓存 / 完整性
├── src/               # 界面与演出：标题 / 开屏 / 游戏主界面 / 密码锁 / 命名界面 等
├── story/             # 剧本（.avg DSL，共 24 个文件、560 个节点）
├── assets/            # 背景 / 立绘 / UI 贴图 / 程序化音频占位
├── tools/             # 开发工具：gen_integrity.py / check_avg.py
└── export_presets.cfg # Android / Windows / Linux 导出预设
docs/                  # 剧本全文、防破解与发行加固指南
```

## 常用开发命令

```bash
# 校验剧本（节点引用、@if 配对、@padlock 参数、未知指令）
python3 game/tools/check_avg.py game/story

# 改动核心文件后重新生成完整性清单（autoload/integrity_manifest.gd）
python3 game/tools/gen_integrity.py --write

# 无头冒烟测试（19 项：剧情引擎 / 密码锁 / 命名插值 / 条件 / 序列化）
godot --headless --path game res://tools/smoke_runner.tscn
```

## 剧本 DSL 速查

```
== 节点id                节点开始
@bg 场景 [变体]          背景      @bgm/@amb/@sfx 音乐/环境/音效
@show 角色 表情 [位置]   立绘      @fx 特效 强度
@set 变量 +N|-N|=N       数值      @flag 名 / @state 键 值
@item +id|-id            道具      @clue id  线索
@padlock 密码 成功节点 [失败节点] 提示文本     数字密码锁
@if 条件 / @elif / @else / @endif / @goto 节点 / @ending 结局id
* 选项文本 -> 目标节点              （可加 [if 条件] 隐藏 / [lock 条件] 灰显）
角色: 台词      > 旁白强调行      普通行 = 旁白
```

文本插值：`{pname}` 玩家名、`{num:truth}` 数值、`{item:item_xxx}` 道具名、
`{if 条件?A|B}` 条件文本。玩家改名后正文中的「林昼」自动替换为玩家名字。

## v1.1.1 更新（本分支）

> 追加：开屏动画取消游戏图标，统一使用官方 Godot 引擎图标（原生 boot splash 亦恢复引擎默认 Godot 标识，游戏内开屏第二段改为纯文字）；新增 AI 生成的深色雨夜氛围底图（splash_bg.png，压暗+缓慢缩放，Godot 引擎图标浮于其上，缺图自动回退纯色底）

- 游戏名更改为《第十三节课》，同步更新开屏 / 标题 / 工程配置 / 安卓包名（`com.example.the13thperiod`）与全部图标（含自适应图标）
- 开屏动画统一使用官方 Godot 引擎图标（原生 boot splash + 游戏内开屏，均带无贴图兜底），不再使用游戏图标
- 移除创意工坊（workshop / workshop_panels / content_policy），精简完整性清单
- 新增解谜系统：数字密码锁（第四章校史馆内门 0109、终章广播主控柜 2119），配合道具与线索推进
- 新增自定义角色名：新游戏前可为主角命名，正文、名牌与存档同步
- 场景图完善：新增俯瞰夜景、主控柜特写、白天旧楼等场景并接入剧本（真结局“天晴”等场景实装）
- 性能与代码清理：删除无用变量、限制回想/选择日志长度、预取清单更新
