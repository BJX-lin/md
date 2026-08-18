# 《晚自习之后》 After Evening Study

国产校园恐怖文字互动视觉小说（AVG）· **完整版**
按 `a.md` / `b.md` / `c.md` / `d.md` / `e.md` / `f.md` 六份策划开发文档实现。

> **引擎：Godot Engine 4.7.1 stable（Mobile 渲染后端 / 手机端竖横屏自适应）**
> 内容分级提示：含惊吓演出、血腥与伤害描写、火灾/死亡/自杀相关情节、压抑主题。
> 游戏内可随时调节「血腥表现（关闭 / 温和 / 完整）」「强闪光」「画面震动」。

---

## 一、目录结构

```
md/
├─ game/                      ← Godot 4.7.1 工程（用 Godot 打开这个目录）
│  ├─ project.godot
│  ├─ main.tscn
│  ├─ autoload/               全局单例
│  │  ├─ config.gd            变量区间 / 角色表 / 阈值表 / 调色板
│  │  ├─ game_state.gd        数值·标记·状态机·道具·线索·章节结算·结局判定
│  │  ├─ story_engine.gd      .avg 剧本 DSL 解析器 + 运行时虚拟机
│  │  ├─ audio_director.gd    程序化音频合成（无需任何音频文件）
│  │  └─ save_system.gd       8 手动槽 + 自动存档 + 设置 + 跨周目数据
│  ├─ src/
│  │  ├─ app.gd               应用根节点 / 界面路由
│  │  ├─ art/                 程序化美术（无需任何图片文件）
│  │  │  ├─ bg_painter.gd     18 个场景的代码绘制背景
│  │  │  ├─ actor_painter.gd  6 名角色的代码绘制立绘 + 表情 + 血腥表现
│  │  │  └─ effects_layer.gd  19 种全屏演出特效
│  │  └─ ui/                  标题 / 游戏 / 结局界面 + 各类菜单浮层
│  └─ story/                  ★ 剧本（9 个 .avg 文件，325 节点）
│     ├─ 00_prologue.avg      序章
│     ├─ 10_ch1.avg           第一章《转入》
│     ├─ 15_ch1_side.avg      第一章 自由调查支线
│     ├─ 20_ch2.avg           第二章《旧楼》
│     ├─ 25_ch2_side.avg      第二章 值班室之夜（老秦线）
│     ├─ 30_ch3.avg           第三章《熄灯》
│     ├─ 35_ch3_side.avg      第三章 熄灯后夜间探索
│     ├─ 40_ch4.avg           第四章《照片》
│     └─ 50_final.avg         终章《点名》+ 五结局
│
├─ tools/
│  ├─ validate_story.py       剧本静态校验（断链 / 死路 / 未知指令 / 可达性）
│  ├─ check_gdscript.py       GDScript 静态检查（括号 / 路径 / 单例 / 信号）
│  ├─ simulate.py             剧情运行时模拟器（随机通关 + 结局可达性验证）
│  ├─ check_text.py           正文质量检查（外文混入 / 占位符 / 标点 / 重复行）
│  ├─ check_assets.py         美术覆盖率与待生成清单
│  ├─ asset_manifest.py       94 张美术资源总清单 + 生图提示词
│  ├─ make_sprite.py          立绘后处理（白底转 alpha / 去重影 / 归位）
│  └─ preview/                浏览器试玩版（与 Godot 工程同一套剧本）
│
└─ a.md ~ f.md                原始策划开发文档
```

---

## 二、怎么跑起来

### 方式 A：Godot 编辑器（正式工程）

1. 下载 Godot Engine **4.7.1 stable**（标准版即可，无需 .NET 版）。
2. 启动 Godot → `导入` → 选择本仓库的 **`game/project.godot`**。
3. 按 `F5` 运行。

工程**不依赖任何外部素材文件**——背景、立绘、特效、BGM、音效全部在运行时由代码生成，
所以克隆下来就能直接跑，不会出现「资源丢失」报错。

### 方式 B：浏览器试玩（无需安装 Godot）

```bash
python3 -m http.server 8080 --directory tools/preview
# 打开 http://localhost:8080
```

这是 Godot 工程的浏览器等价实现，**读取的是同一份 `story/*.avg` 剧本**，
变量系统、章节结算、结局判定逻辑与 GDScript 版本逐行对应，用来快速试玩与校对剧情。

### 方式 C：导出 Android APK

1. Godot 编辑器 → `编辑器` → `管理导出模板` → 下载 4.7.1 的模板。
2. `编辑器设置` → `导出/Android` 里配置 Android SDK 与 debug keystore。
3. `项目` → `导出` → 添加 **Android** 预设 → `导出项目`。

工程已按手机端配置好：Mobile 渲染后端、`emulate_mouse_from_touch`、
1280×720 基准分辨率 + `canvas_items` 拉伸 + `expand` 宽高比（横竖屏都不会裁切）。

---

## 三、剧本 DSL（`.avg`）

剧本是纯文本，策划可以直接改，不用碰代码。

```avg
== ch1_s1_a                      节点定义
@bg classroom night              背景（第二个参数是变体：day/dusk/night/dark/rain/blood/fire）
@bgm bgm_horror  @amb amb_rain   音乐 / 环境音
@sfx sfx_knock_pattern           音效
@fx heartbeat 1.2                全屏特效（19 种）
@show liangye terrified left     立绘（角色 / 表情 / 位置）
@hide zhouxu   @clearchars       收起立绘
@set truth +2                    数值增减（自动按 config.gd 的区间钳制）
@flag flag_gave_up_roommate      置位剧情标记
@state liangye_state fear_alive  设置状态机
@item +item_page109              获得 / 失去道具
@clue clue_dont_answer           解锁线索
@note 别替我答到。               纸条式弹窗（\n 换行）
@roster                          弹出动态名单（内容随当前状态变化）
@title 南栖中学                  大字幕
@chapter 3 熄灯                  章节卡
@settle 2                        执行第二章结算
@autosave                        自动存档
@wait 1.2                        停顿
@if truth>=15 / @elif / @else / @endif      条件分支
@goto ch2_start                  跳转
@goto __ending__                 按判定表分流到对应结局
@ending auto                     结束并结算

liangye(fear)：我倒希望是。      角色台词（角色键 + 可选表情）
> 他为什么不敢弯腰？             旁白强调行
教室里风扇嘎吱嘎吱地摇。          普通旁白

* “你继续说。” -> ch1_s3_a       选项（-> 目标节点）
    @set truth +2                缩进的 @ 行 = 该选项的即时效果
    @set trust_liangye +1
* [if flag_shenhe_name_full] “沈禾，是你吗？” -> ch2_door_d     条件满足才显示
* [lock item:item_roster_core] 把名单摊开 -> final_s3_c         不满足则灰显并提示原因
```

条件表达式支持 `and` / `or` / `!`，原子形式：
`truth>=15`、`flag_xxx`、`item:item_admin_key`、`clue:clue_page109`、
`state:liangye_end_state==present_anchor`、`visited:ch2_duty`、`death:梁野`、`gore>=1`、`cycles>=1`。

---

## 四、系统实现对照（文档 → 代码）

| 文档要求 | 实现位置 |
|---|---|
| 全局数值变量表（f.md 1.1） | `config.gd:NUM_RANGE / NUM_DEFAULT`，16 项，自动钳制 |
| 布尔标记表（f.md 1.2） | `game_state.gd:flags`，剧本里 `@flag` 直接置位 |
| 状态枚举表（f.md 1.3） | `config.gd:ENUM_DEFAULT`，10 个状态机键 |
| 角色状态机（f.md 二） | `settle_chapter_1~4()` 逐条实现迁移条件 |
| 关系变化规则（f.md 三） | 落在各选项的 `@set trust_xxx` 上 |
| 数值阈值效果（f.md 六） | `config.gd:TH_TRUTH / TH_SANITY` + 状态面板解读 |
| 五结局判定伪代码（f.md 七 / e.md 七） | `can_true_end()` / `can_bittersweet_exchange()` / `can_destroyer()` / `can_manager()` / `determine_ending()`，与文档逐行一致 |
| 章节场景总表（f.md 四） | `story/*.avg` 的节点划分 |
| 音频安全播放（e.md 八·方案B） | `audio_director.gd` 全程序化合成，永远不会因缺文件报错 |
| 无 CG 美术方案（e.md 美术表） | `bg_painter.gd` / `actor_painter.gd` 全代码绘制 |
| 立绘表情配置（e.md 立绘表） | `actor_painter.gd:_draw_face()`，8 组表情 + 角色专属发型/特征 |

### 剧情伏笔与规则（贯穿全篇）
- **违纪记录表** → 上一轮循环的看守记录（管理者结局回收）
- **第 109 页被撕** → 第 109 次重排
- **「别替我答到」** → 终章解局核心，代答满三次视同替补
- **许清不穿鞋** → 五年前锁门的人，本人也没出去
- **周叙补名字** → 火灾当晚念全名字导致开门
- **名单术语**：在册 / 待定 / 删除未完成 → 终章拿规则反打规则
- **重复的你** → 主角是被反复描出来的替补
- **梁野的借书卡** → 情感锚 / 保命 / 名字作废证明

---

## 五、五个结局

| 结局 | 硬条件（`game_state.gd` 实现） |
|---|---|
| **真结局《点名停止》** | `truth_state=complete` + 写回沈禾名字 + 夜间核对名单 + `save_route_score≥5` + 掌握完整术语 + 具备改写广播条件 + 没放弃梁野 + 梁野在场 |
| **遗憾结局《留堂》** | `save_route_score≥4` + 可改写广播，且（梁野缺席 / 术语不全 / 主动坐下） |
| **毁灭结局《焚校》** | `end_cycle_score≥5` + 可改写广播 + 触发点火 |
| **管理者结局《管理员》** | `control_route_score≥5`，或放弃室友且 `≥4` |
| **空席结局《到》** | 以上都不满足（保底） |

跨周目：通关后标题会显示「这是第 N 次重排」，新周目初始 `memory_echo` 更高（既视感文本更多）。

---

## 六、开发工具

```bash
python3 tools/validate_story.py    # 剧本校验：断链、死路、未知指令/角色/道具/线索、可达性
python3 tools/check_gdscript.py    # 代码检查：括号配平、preload 路径、单例、信号、缩进
python3 tools/simulate.py --runs 800           # 随机通关 800 次 + 定向真结局验证
python3 tools/check_text.py                    # 正文质量：外文混入、占位符、标点、重复
python3 tools/check_assets.py --todo           # 美术待办清单
```

当前状态：

```
剧本   : 11 个文件 / 373 节点 / 4056 行台词 / 76 个选择场景 / 610 条跳转边
正文   : 58176 字（不含指令）                              —— 0 错误
代码   : 17 个 GDScript / 约 5400 行                       —— 0 错误 0 警告
美术   : 6 张 AI 立绘 + 1 张场景（其余按 asset_manifest 待补，缺图自动回退）
模拟   : 随机通关 800 次全部到达结局，五结局均可达，
         真结局定向策略 60/60，数值无越界，无死循环
```

> 修改剧本后请先跑 `validate_story.py` 与 `simulate.py`，
> 前者保证不会跳到不存在的节点，后者保证没有死循环、没有「全部选项都被锁死」的绝境。

同步浏览器试玩版的剧本：

```bash
cp game/story/*.avg tools/preview/data/
```


---

## 七、后续可扩展方向

- **美术升级**：`bg_painter.gd` / `actor_painter.gd` 是纯绘制实现，可平滑替换成 AI 生成的 PNG 背景与立绘（按 e.md 的命名规范放进 `game/assets/`，改绘制函数为 `draw_texture_rect` 即可）。
- **中文字体**：把字体文件放到 `game/assets/fonts/main.ttf`，`theme_builder.gd` 会自动优先使用；否则回退到系统 CJK 字体。
- **配音**：`audio_director.gd` 已预留角色音色（`Cfg.CHARACTERS.pitch`），接真人语音时按 `角色_场景_序号` 命名替换 `play_blip` 即可。
- **文本量扩充**：f.md 建议完整商用体量 18~28 万字，当前主干约 3.5 万字，可按 `story/*.avg` 的节点结构继续在各场景内加写。
