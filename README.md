# FolderDerTextEditor

一个用 Godot 做的**纯文本编辑器**：左边是文件夹树，右边是编辑区。定位很明确——不追求做 VS Code，只求打开快、能顺着目录翻文件、能改能存。

- 引擎：**Godot 4.7**（`GL Compatibility` 渲染后端）
- 语言：纯 GDScript，没有 C#
- 平台：Windows（`export_presets.cfg` 只有 Windows Desktop 一项）
- 体量：业务代码就是 `page/main.tscn`（346 行）+ `page/main.gd`（3017 行，其中不小一部分是
  解释性注释）。另有 `scene/Previewer/` 下三个纯逻辑脚本：两个转换器
  （`TextToBbcode.gd` / `MarkdownToBbcode.gd`）加一个阅读主题色板 `PreviewTheme.gd`
  —— 它们不碰节点也不读文件，所以能不起界面直接拿断言验（见第 7 节）。
  另有一个框架 addon `addons/der_framework` 注册了 4 个 autoload，本应用用到其中三个：
  顶部提示 `DMessageManager`、持久化收藏夹的 `DSaveManager`（§7.17）、
  持久化阅读偏好的 `DSettingsManager`（§7.20 ⑫）

---

## 1. 跑起来

本机 PATH 上没有 `godot`。引擎是 **Steam 版**（`4.7.2.stable.steam`），在：

```
C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
```

路径里**有空格**，而且项目路径以前在这份文档里被写错过（`txtEditor` ≠ `textEditor`），
所以下面每段命令都自带一句 `GODOT=...`，**整段复制**就能跑，不用手抄路径：

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
PROJ=/c/godotProject/folder-der-textEditor

# 直接运行
"$GODOT" --path "$PROJ"

# 用编辑器打开
"$GODOT" -e --path "$PROJ"
```

导出配置已经写好，产物固定落在项目外的 `../../app/FolderDerTextEditor.exe`。

---

## 2. 改完代码怎么验证（**新接手的人先看这节**）

没有 CI、没有单元测试框架。这个项目的验证靠两招：

### 第一招：语法检查（秒级，先跑这个）

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path /c/godotProject/folder-der-textEditor \
  --check-only --script res://page/main.gd
```

**⚠️ 这条命令对 `main.gd` 永远返回 1，不代表你的代码有问题。**
`--check-only` 模式下 autoload 不会注册，所以它必定先报这一条：

```
SCRIPT ERROR: Compile Error: Identifier not found: DMessageManager
```

（`DMessageManager` 是 `addons/der_framework` 注册的 autoload，见第 3 节。加了收藏夹之后
`DSaveManager` 是同一类东西 —— 但 GDScript 撞上第一个未定义标识符就停止编译，
所以这行输出里**只会出现排在前面的那一个**，别以为另一个没问题。）

所以**别拿退出码当结论**，要看输出里有没有**别的**报错 —— 出现 `DMessageManager`
以外的 `Parse Error` / `Compile Error` 才是真问题。这招确实能抓语法错误（实测：故意写一行
非法语法，退出码 1 并报 `Parse Error`），只是没法在这种模式下给你一个"干净通过"的信号。

对不依赖 autoload 的独立脚本，退出码才是可用的：0 = 没问题。

想真正跑通一遍，用第二招（它会加载 autoload，`main.gd` 能正常编译）。

### 第二招：临时 harness（行为验证）

`--check-only` 只能告诉你"语法对"，不能告诉你"点下去会怎样"。要验行为就写一个临时的 `extends SceneTree` 脚本：

```gdscript
extends SceneTree

const FIX := "C:/Users/kldermr/AppData/Local/Temp/fdt_c"   # 测试用的临时目录

var _started := false
var _frames := 0

# 用 _process 而不是 _initialize()：autoload 只能在第一帧之后按节点名取（见坑 13），
# 而帧数上限是"协程半路抛错 → quit() 永远不执行 → 进程挂到 timeout"的兜底（见坑 14）。
func _process(_d: float) -> bool:
	_frames += 1
	if _frames > 900:
		print("!!! 超时兜底：跑到 900 帧还没收尾，多半是中途抛错了")
		quit(2)
		return true
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
	var scene = load("res://page/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame          # 必须等两帧：_process 第一帧跑在节点的 _ready() 之后、
	await process_frame          # 但 @onready 的变量要到场景真正进树才稳
	scene.set_root_dir(FIX)
	await process_frame

	# ... 这里写断言 ...
	# scene._item_path(...)、scene._is_editable_file(...) 这些私有函数可以直接调
	quit(0)
```

跑法：

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
timeout -k 5 90 "$GODOT" \
  --path /c/godotProject/folder-der-textEditor --script res://_tmp_verify.gd
```

**用完务必删掉 `_tmp_verify.gd` 和 `_tmp_verify.gd.uid`**，别留在项目里。

> **删之前先拷一份出去。** 已经发生过一次：harness 删掉之后又要改同一块功能，
> 只能回头从会话 transcript 里把当时的 `Write` + 全部 `Edit` 重放一遍捞回来
> （transcript 在 `~/.claude/projects/<项目名>/<会话 id>.jsonl`，一条工具调用一行 JSON）。
> 现在的做法是删之前 `cp` 到 `C:/Users/kldermr/AppData/Local/Temp/fdt_harness/`。
> 注意 harness 得放在项目根目录才跑得起来（路径必须是 `res://`），所以要重跑先从那儿拷回来。

### 第三招：接活着的编辑器（可选；只验逻辑时比 harness 快一轮）

`addons/godot_ai` 那套 MCP 工具在编辑器开着的时候，能直接对**运行中的游戏**求值。
改完 `main.gd` 存盘 → 编辑器里 F5 → 就能问它问题，不用写文件也不用删文件：

- 在游戏进程里跑一段 GDScript 并拿回返回值。可以直接拿到场景根
  （`get_tree().root.get_node("Main")`）、调私有函数（`_parent_dir_of(...)`）、
  读私有变量（`_nav_forward`）、断言 `root_dir`。
- **按钮要用 `button.pressed.emit()` 驱动，不要直接调处理函数** —— 前者才验得到
  "信号接上了没有"，后者只是把函数又跑了一遍。
- 游戏窗口被切到后台时主循环不推进，会返回 `EVAL_GAME_NOT_READY`。
  把窗口切到前台，或者 stop 再 run 一次。
- 别拿真实盘符当夹具 —— 不是会慢了，是断言会随机器上装了什么而变（见 §7.18 ⑥）。

**它替代不了第一招**（那个验的是编译）。至于"真实鼠标 / 键盘的输入路径"，
**第二招现在能验了**（`root.push_input()` 走真正的 `gui_input`，见下面坑 4），
所以别急着为这点开游戏、抢窗口焦点。

**它省的是"只想知道这段逻辑对不对"时的来回。** 但要小心一个反过来的陷阱：
`game_eval` 跑在游戏进程里，它的代码**不在** `main.gd` 的编译单元里，
所以它能调私有函数、但如果被调的代码本身崩了，你看到的会是一条
`EVAL_HUNG` / `GAME_NOT_READY`，而不是崩在哪一行 —— 这种时候回第二招更快。

### 写 harness 时踩过的坑（实测，按踩到的顺序）

1. **必须带窗口跑，不要加 `--headless`。** Tree 控件在 headless 下不暴露某些崩溃——历史上那次段错误就是带窗口才复现的。
2. **stdout 被重定向/管道时是块缓冲的**，进程被 `timeout` 杀掉就一个字都不剩。每条断言都同时 `print` **并追加写一个文件**（写完立刻 `close()`），这样即使挂起也能看到跑到哪一步了。
3. **类型推断的报错很啰嗦**：`var r := tree.get_item_area_rect(...)` 会报 `Cannot infer the type`，得写成 `var r: Rect2 = ...`。凡是从引擎方法拿到的返回值，习惯性加上显式类型注解，能省掉一大堆来回。
4. **合成输入可以走完整管线**：`Input.parse_input_event()` 对鼠标点击、双击（第二下带 `double_click = true`）、键盘按修饰键都有效，能端到端验真实输入路径。
   **要验 `Tree` 的鼠标路径，用 `root.push_input(InputEventMouseButton)` 而不是 `parse_input_event()`** ——
   `push_input` 会把事件真的送进 `Viewport` → `Control.gui_input`，也就是用户手点走的那条路。
   这很关键：`Tree` 在处理鼠标选择事件时会**禁止建条目**（§7.19 那个 `blocked > 0`），
   而 `item.select(0)` 是**程序化**选中，不设那个计数 —— 只用 `select()` 驱动的 harness
   会把一个必崩的改动验成全绿。位置换算：控件是 `global_position + 局部坐标`，
   `Tree` 的行位置用 `get_item_area_rect(item, 0).position`（视口坐标和窗口坐标 1:1，
   本项目 stretch 是默认的 disabled）。
   **早先这里记的"弹过 PopupMenu 之后再合成输入会挂住"是错的**，2026-09 实测推翻了：菜单开着的时候照样能合成点击、断言全过（当时那次"挂住"的真凶是第 7 条的拼错属性名）。
   真实情况是**路由**问题而不是卡死：菜单（嵌入式子窗口）开着时，事件全被它吞掉，主视口一点都收不到 ——
   所以"弹着菜单去点主界面"的用例，症状是**断言全部安静地失败**（什么都没发生），不是进程停住。详见 §7.16。
5. **合成双击时，两下之间必须 `await process_frame`。** 在同一个事件批次里连着塞两个 press，
   Tree 的行为和真实双击**不一样**（实测：连塞时 `item_selected` 一次都不发，而真实双击的第一下是会发的），
   照着它得出的结论会把你带偏 —— 这个坑真踩过，白改了一版代码。真实双击的两下相隔上百毫秒、必然跨帧，
   所以留一帧才是对的。
6. **按下之前先自检落点**：`get_item_area_rect()` 给的是**内容坐标**（不含滚动偏移），
   而合成事件要的是 Tree 局部坐标，得减掉 `get_scroll()`。算错了就会点在空气上，
   所有断言都会"失败"，看起来像功能坏了。加一句
   `tree.get_item_at_position(pos) == 目标条目` 的自检，能立刻把这类假故障和真故障分开。
7. **harness "卡住"了，先去看 stderr 里有没有 `SCRIPT ERROR`。** 编辑器二进制跑脚本时，
   脚本运行时报错（比如动态读了一个**不存在的成员**）会让进程停在那里不退，
   表现和死锁一模一样 —— 文件日志停在某一行，`timeout` 到点杀进程，退出码 124。
   这个坑花了好几轮才定位：当时写的是 `scene._rename_dialog.hide()`，而本应用里根本没有
   `_rename_dialog` 这个成员（`@onready` 的那个叫 `rename_dialog`，没有下划线前缀），
   于是先怀疑 `hide()` 有问题、再怀疑"两个弹框同时可见"有问题、又怀疑帧内重入 ——
   全错。前两个都写了最小复现（裸 `ConfirmationDialog` 一 pop 一 hide、以及两个弹框同时可见
   再 hide 其中一个）实测过，**都不卡**，所以这不是引擎的毛病，也和应用代码无关。
   **症状是"卡住"，病因是拼错了一个属性名。**
   所以：别把 stderr 丢掉（`> /dev/null 2>&1` 会让你看不见它），
   上面第 2 条的文件日志负责告诉你**停在哪一行**，stderr 负责告诉你**为什么**。

   （顺带一个省时间的结论：4.7 的 `PopupMenu` **没有 `activate_item()`**，别想着用它模拟
   "点了菜单第 N 项"。想验菜单 id 直接 `menu.get_item_id(i)` 逐个对，想验处理函数
   直接 `menu.id_pressed.emit(id)`。）
8. **看引擎自带控件的内部结构，要用 `get_children(true)`。** `FileDialog` 的整套 UI 是用
   `INTERNAL_MODE_FRONT` 加进去的**内部子节点**，默认的 `get_children()` 看不见它们 ——
   直接 `for c in dlg.get_children()` 会得到"子节点 0 个"，看着像控件根本没建出来，
   其实它好端端在那儿。想摸文件列表（那个 `ItemList`）就得把 `true` 带上。
9. **GDScript 的 lambda 对局部变量是"按值捕获"的。** 想在闭包里往外传结果，
   `var got := ""` + `cb = func(p): got = p` 是**不行的** —— 闭包改的是它自己的副本，
   外面读到的永远是空串。实测为此报了"功能没反应"的假故障，其实功能好好的。
   要么用集合类型（Dictionary / Array 是引用，能改到外面看得见的那个），
   要么干脆用具名函数 + 成员变量。
10. **往已有脚本里插代码时，缩进错了会报一个看不出因果的错。** 在 `_run()` 这种函数体中间
   粘一段**顶格**的代码，解析器会认为函数到那儿就结束了，然后在"类体"里看到
   `_log("")` 这种不合法的成员，报 `Parse Error: Unexpected identifier "_log" in class body`，
   行号还指向插进去的第一行。看起来像语法错误，其实是缩进 —— **插完先确认整段的缩进层级**，
   或者干脆用 `sed -i '213,237{/^./s/^/\t/}'` 统一补一层。
   （这个报错也很适合当"脚本压根没跑起来"的指纹：日志文件里是**上一次**跑的内容，
   别把它当成这次的结果读了。）
11. **菜单会盖住它下面约 151px —— "点另一个条目"的用例极容易点在菜单自己身上。**
   `PopupMenu` 弹在哪个点，那个点就是它的**左上角**，于是它一路盖住下面 5 行左右
   （行高 31px 时）。只有两三个条目的 fixture 里，"想点的那一行"十有八九在菜单底下，
   点出来的结果是"菜单没反应" —— 看着像功能坏了，其实那一下压根没到 Tree。
   **这个坑我踩了两次**，两次都因此改了不该改的东西。对策：
   - fixture 给足行数（这次用 10 个文件），保证总有一行**露在菜单外面**；
   - 点之前先断言落点在 `Rect2(menu.position, menu.size)` **之外**（`not cover.has_point(pos)`），
	 这一句能把"假故障"当场变成"前置条件不成立"。
12. **绝对不要合成"点击菜单项"。** `PopupMenu` 收到左键会照常发 `id_pressed`，于是
   harness 随手在菜单中央点一下，可能正好点在「在文件管理器中打开」上 ——
   那会调用 `OS.shell_show_in_file_manager()`，**在用户的机器上真弹出一个资源管理器窗口**
   （2026-09 真发生过一次，id=4 就是这么来的）。菜单动作一律用
   `menu.id_pressed.emit(MenuId.REFRESH)` 这类**安全的 id** 触发；
   真要验"点菜单里面"，先把所有项 `set_item_disabled(i, true)` 再点，
   这样只验"事件被菜单吃掉"（Tree 收不到、不载入文件），不会触发任何真实动作。
   **顺序也有讲究**：`set_item_disabled()` 必须在 `popup()` **之后** —— `_build_item_menu()`
   里是 `clear()` + `add_item()`，先禁再弹会被整个重建掉，白禁（这一步我也写反过一次）。
13. **`--script` 跑的那个主循环脚本，是在 autoload 注册之前被编译的。** 所以 harness 里
   直接写 `DSaveManager.save_path = ...` 会跟 `--check-only` 一样报
   `Compile Error: Identifier not found: DSaveManager` —— 脚本根本加载不起来，
   日志文件都不会生成，看着像"harness 写错了地方"。
   而 `main.gd` 里同样是裸写这个标识符却没事，因为它是在游戏跑起来、场景被 `instantiate()`
   的时候才编译的，那时 autoload 已经在位了。
   对策：harness 里按**节点名**取，再动态调用（`DSaveManager` / `DMessageManager` 都是
   `/root` 下的普通子节点，autoload 的本质就是这个）：

   ```gdscript
   var _dsave: Node
   # 只能在第一帧之后取：_initialize() 里 root 还没"在树里"，
   # get_node 会报 "Can't use get_node() with absolute paths from outside the active scene tree"
   func _process(_d: float) -> bool:
       if not _started:
           _started = true
           _dsave = root.get_node(NodePath("DSaveManager"))
           _run()
       return false
   ```

   顺带：`class_name` 注册的全局类（`DerSaveRes`）没有这个问题，可以直接 `new()`。
14. **`_run()` 里一旦抛错，`quit()` 就永远不会被调到，进程会挂到外层 `timeout` 为止。**
   协程断在半路，`_process` 继续返回 `false`，引擎就一直在跑 —— 症状和"死锁"一模一样。
   在 `_process` 里加个帧数上限兜底（跑到 900 帧还没收尾就 `quit(2)` 并写一行日志），
   比事后去猜"它卡在哪"省事得多。
15. **`Tree.clear()` 之后 `get_selected()` 返回的是一个已释放的 `TreeItem`，不是 `null`。**
   所以"清除之后选中项应该没了"不能写成 `assert get_selected() == null`，
   要写成"它不再等于原来那个条目"。同理，凡是会 `clear()` 重建的地方
   （`refresh_fav_tree()` / `refresh_file_tree()` / 切视图）**之前**抓到的 `TreeItem`
   **之后一律失效**，继续用会报 `previously freed is not a subclass of the expected argument class`。
16. **同一个路径反复覆写之后再 `ResourceLoader.load()`，拿到的可能是缓存里那个内存对象。**
   要验"盘上到底写了什么"，必须带 `ResourceLoader.CACHE_MODE_IGNORE`
   （`load(path, "", ResourceLoader.CACHE_MODE_IGNORE)`），否则测出来的是内存状态，
   等于没测落盘。
17. **验收藏夹之前必须先做隔离，否则会写坏用户真实的存档。**
   `DSaveManager.save_path` 默认指向 `user://DerSave/`，那是**用户自己的数据**；
   harness 里点一下"收藏"就把它覆盖了。三件事，顺序不能换：

   ```gdscript
   _dsave.save_path = "C:/Users/.../Temp/fdt_fav/saves/"   # 1. 重定向到临时目录
   DirAccess.make_dir_recursive_absolute(_dsave.save_path)
   var fresh := DerSaveRes.new()                            # 2. 换一份干净的资源
   fresh.save_name = "AutoSlot"
   _dsave.cur_res = fresh
   # 3. 之后才 load("res://page/main.tscn").instantiate()
   ```

   **必须排在 `instantiate()` 之前** —— `main.gd::_ready()` 里就要读收藏，
   晚一步就成了"先读了真存档、再改路径"，隔离是假的。
   最后再断言收尾时真实那个 `AutoSlot.tres` **逐字节没变** —— 不断言等于没隔离。
   （`cur_res` 不是 `null` 时 `save_name` 也不能是空串，`_save_favorites()` 两个都判。）
18. **`TextEdit.text_changed` 是"用户改了文本"，程序化赋值不发。** `text_edit.text = "..."` 之后
   等 40 帧都不会有信号 —— 我第一版就是照"改了文本总会发信号"写的，结果是防抖 Timer
   一次都没启动，看起来像接线断了。**验防抖只有两条路**：直接调
   `_on_preview_text_changed()`（走闸门逻辑，但绕过了信号本身）、或者
   按第 4 条真的往输入管线里灌按键（那样才连信号一起验了）。
   好消息是这条语义在**应用代码**里是有用的：`open_and_show()` 读文件那次
   不会触发重排，不需要额外的抑制标志。详见 §7.20 ⑥。
19. **`DSettingsManager` 的路径重定向不了，所以设置文件只能"备份 + 还原"。**
   `DSettingsManager.SETTINGS_PATH` 是 `const user://der_settings.tres`（不像
   `DSaveManager.save_path` 那样是个 `@export`），第 17 条那套在这里**用不了**。
   而阅读设置的持久化用例**会真的写那个文件** —— 不处理的话跑一次 harness 就把用户真实的
   阅读偏好（以及音频/画面/语言）改成测试值。做法是 `_run()` 头尾无条件各跑一次
   `_snapshot_settings_file()` / `_restore_settings_file()`：文件存在就存字节、跑完写回并
   **断言逐字节相同**；不存在就记住"本来没有"，跑完删掉测试残留。
   这是本项目测试里**唯一一处能造成真实数据损坏**的地方。
20. **harness 是主循环脚本，它在 autoload 注册之前就被编译了。**
   `--script` 跑的那个 `extends SceneTree` 里**裸写 `DSettingsManager` 会
   `Compile Error: Identifier not found`**；而 `main.gd` 是之后才 `load()` 的，它里面裸写
   完全没事（`--check-only` 报的那条 `DMessageManager` 也是同一个原因，是**假故障**）。
   取法：`root.get_node_or_null("DSettingsManager")`。
   这个差别很容易被误判成"autoload 没配好"，实际上 `project.godot` 里配着。
   同一个原因，**新建的脚本也不要裸写 `class_name`** —— 那取的是上次编辑器扫描的全局类表，
   在 `--script` 下可能是空的，用 `load()` / `preload()`（见 `_tmp_verify.gd` 文件头）。
21. **`Unexpected NUL character` 警告来自 harness 自己代码里的 `char(0)`，不是项目坏了。**
   症状：harness 输出里冒出若干条

   ```
   Unicode parsing error, some characters were replaced with � (U+FFFD): Unexpected NUL character
   ```

   **而且是打在脚本任何输出之前**，看着活像引擎/项目加载出问题。实测（六轮隔离探针）：

   - 空 `--script`、`--headless --quit` → **0 条**；
   - 只写 `var a := "x" + char(0) + "y"` 的脚本 → **2 条**；
   - 两个 `char(0)` → **4 条**。**每个含 `char(0)` 的常量表达式产生 2 条**；
   - `char(12)`（U+000C，不是 NUL）→ **0 条**，所以这是 **NUL 专属**的，不是"控制字符"。

   机制是 GDScript 对含 `char(0)` 的字符串表达式做**编译期常量折叠**，折叠出来的常量里带 NUL
   过一遍 UTF-8 解码 → 报错。因为发生在**编译期**，所以排在 `_init()` 任何语句之前，
   和"哪一行触发的"完全对不上号，非常容易往引擎/项目文件上找。
   （`_tmp_verify.gd` 里那两条是**故意**的 —— 第 259 行那段在测"转换器会不会把控制字符漏进输出串"。）

   **先自查再往项目上找**：全项目扫一遍 NUL 字节，只该命中二进制（`.png` `.ctex` `.scn`
   `.res` `.cache` `.translation` `.bin`）：

   ```bash
   find . -type f -not -path './.git/*' -print0 | xargs -0 grep -lPa '\x00'
   ```

   ⚠️ **别用 `grep -c $'\x00'` 或 `grep -c '\x00'`**：那个模式会**塌成空串**，
   于是**每个文件的每一行都算命中**（实测 `page/main.gd` "命中" 3010 行 = 全文行数，
   连没动过的 `MarkdownToBbcode.gd` 也"命中"）。这是个**假阳性**，
   照它去查会得到"整个项目全是 NUL"的荒谬结论。要 `-P` 才是真的按字节匹配。

---

## 3. 目录结构

### 活着的文件

| 路径 | 作用 |
|---|---|
| `page/main.tscn` | **主**场景。整个 UI 都在这里 |
| `page/main.gd` | **主**脚本。界面逻辑全在这里（预览的排版算法不在这里，见下两行） |
| `scene/Previewer/TextToBbcode.gd` | `.txt` → 阅读排版的 BBCode。**全 static 纯函数**，进 String 出 String，不碰节点也不读文件 |
| `scene/Previewer/MarkdownToBbcode.gd` | `.md` → BBCode。同上，块级扫描 + 递归行内扫描器 |
| `scene/Previewer/MobileNovelReader.tscn` | 右侧预览栏里那个阅读器：`VBoxContainer → ScrollContainer → RichTextLabel`。**两种预览共用它一个**（§7.20 ②） |
| `resource/folder.tres` | 主题，只设了 `TextEdit/font_sizes/font_size = 20` |
| `resource/new_code_highlighter.tres` | 语法高亮配色，挂在 TextEdit 的 `syntax_highlighter` 上 |
| `asset/bg/tsBgHF.png` | 编辑区的背景图（`TextureRect`） |
| `asset/icon/folder.png` | 目录图标 |
| `asset/icon/folderTxt.png` | **可编辑**文件的图标 |
| `asset/icon/UnsupportedEditIcon.png` | **不可编辑**文件的图标 |
| `asset/icon/saveIcon.png` `txtIcon.png` `folderIcon.png` | 工具栏按钮的图标 |
| `asset/icon/start.png` | 星星。侧边栏第二个视图按钮（收藏列表），以及文件树头部的「收藏当前文件夹」按钮 |
| `scene/SettingWin.tscn` | 设置窗口。**按钮当前是隐藏的**（见下），等于没启用 |
| `export_presets.cfg` | Windows 导出配置 |
| `addons/der_framework/` | **活着的，不是死的**。`project.godot` 里 4 个 autoload 全是它的场景：`DerMain` / `DerMessage` / `DerSave` / `DerSettings`。`main.gd` 保存成功时那行顶部提示就来自 `DMessageManager.add_top_message()`；`DSaveManager` 用来**持久化收藏夹**（见 §7.17），存档落在 `user://DerSave/AutoSlot.tres`。另外两个 autoload 被加载着但 `main.gd` 没碰 |
| `addons/der_framework/DSave/script/res/DSaveRes.gd` | 存档资源。**本项目往里面加了一个字段** `favorite_paths: Array[String]`（收藏的绝对路径）。改它是有代价的，见 §7.17 末尾 |
| `addons/godot_ai/` | 第三方 MCP 插件（Godot AI 工具链），**和编辑器业务逻辑完全无关**。它的 autoload `_mcp_game_helper` 是自己注册的 |

### 死的文件（别浪费时间研究）

| 路径 | 说明 |
|---|---|
| `scene/FileItemButton.tscn` | **没有任何地方引用**，是早期方案的残留 |
| `asset/icon/settingIcon.png` | 没被任何场景引用 |
| `asset/bg/loadingBg.png`、`asset/bg/tsBg.png` | 没被引用，只用了 `tsBgHF.png` |

> 顺带一提：光 `addons/` 两个目录加起来就有 300 多个文件，搜索时建议排除，否则结果会被淹掉。

### 侧边栏左边那排图标按钮

`VBC/SpC/HBC/VBC/` 下四个 40x40 的纯图标按钮。**它们是两类东西**，别混着改：
后两个是**开关**（显示当前在哪一边），前两个是**动作**（按一下就做一件事，没有状态）。

| 节点 | tooltip | 图标 | 种类 | 作用 |
|---|---|---|---|---|
| `VBC/SpC/HBC/VBC/Button` | `Explorer` | `folderIcon.png` | 开关 | 切回文件树 |
| `VBC/SpC/HBC/VBC/Button3` | `前往上一级文件夹` | `goParentFolderIcon.png` | 动作 | 树根切到当前目录的上一级（见 §7.18） |
| `VBC/SpC/HBC/VBC/Button4` | `前进（回到按「上一级」之前所在的文件夹）` | `goChildFolderIcon.png` | 动作 | 沿导航历史回到按「上一级」之前所在的目录 |
| `VBC/SpC/HBC/VBC/Button2` | `Stars` | `start.png` | 开关 | 切到收藏列表 |

**场景里的节点名是 `Button3` / `Button4`**（当初放进去时的名字，没改），对应关系以
`main.gd` 里那两个变量名为准：`go_parent_button` = `Button3`，`go_forward_button` = `Button4`。
按行号顺序点一遍就是上表从上到下的顺序（`HSeparator` 夹在 `Button4` 和 `Button2` 之间）。

两个**开关**都设了 `toggle_mode = true`，只用来**显示**当前在哪一边；连的是 `pressed` 信号，
处理函数是 `_set_view.bind(false/true)` —— 显式指定目标视图，不去读按钮自己的状态
（状态是 `_set_view` 用 `set_pressed_no_signal()` 同步过去的，读它就等于让显示反过来决定行为）。

两个**动作**按钮不设 `toggle_mode`，连的是**无参**的 `pressed` → `_go_to_parent` / `_go_forward`。
它们的可用状态由 `_update_nav_buttons()` 统一算，见 §7.18。

### 文件树头部那排按钮

在 `VBC/SpC/HBC/VBC2/PC/HBC/` 里（「Explorer」标题右边），作用目标**全都是 `root_dir`**（见 §6）：

| 节点 | 长什么样 | 作用 |
|---|---|---|
| `Label` | 文字「Explorer」/「收藏」 | 就是标题，唯一带 `expand` 标志的那个（挤的时候先牺牲它） |
| `NewFileButton` | 文字「新建文件」 | 在 `root_dir` 里新建文件 |
| `NewFolderButton` | 文字「新建文件夹」 | 在 `root_dir` 里新建文件夹 |
| `FavDirButton` | `start.png` 星星图标 | **开关**：收藏 / 取消收藏当前文件夹。星星亮 = 已收藏，灰 = 没收藏 |

> `Label` 的节点名在这个场景里**有两个**（另一个是工具栏上的 `v0.2`），取路径别漏了中间的 `/HBC`。
> 一行的宽度现在是**刚好放得下**（273 px，一分不剩），再往这排加东西之前先看 §7.17 ⑯。

---

## 4. `main.gd` 代码地图

文件按功能分了几块，找代码按这个顺序定位（行号会漂，以函数名为准）：

| 区域 | 关键函数 | 干什么的 |
|---|---|---|
| **配置常量**（文件头） | `TEXT_EXTENSIONS` `SKIP_DIRS` `MAX_TREE_DEPTH` `ICON_*` | 扩展名白名单、跳过的目录、深度上限（懒加载之后不再是建树的刹车，只剩"防止用户顺着软链接一路点下去"这一个用处）、图标路径 |
| **启动** | `_ready()` | 建树、读命令行参数、连信号 |
| **存/开** | `open_and_show()` `save_file()` `_on_save_as_file_selected()` | 读写文件。**所有数据风险的源头都在这一块**。三个 `FileDialog` 的 filters 在 `.tscn` 里配，见 7.15 |
| **快捷键** | `_input()` | Ctrl+S / Ctrl+Shift+S / Ctrl+O / F11 / 缩放 / 小地图 |
| **右键菜单** | `_setup_item_menu()` `_on_file_tree_gui_input()` `_on_fav_tree_gui_input()` `_open_item_menu_at()` `_on_menu_window_input()` `_build_item_menu()` `_build_fav_item_menu()` `_on_menu_id_pressed()` | 见第 6 节。**两棵树共用同一个 `file_item_menu`**，三个入口都汇到 `_open_item_menu_at(vp_pos, tree)`：两棵树的 `gui_input`（第一次右键）和菜单自己的 `window_input`（菜单开着时的右键，那时候主视口收不到输入，见 §7.16）。`tree` 参数只影响命中测试和菜单项内容，那套"丝滑"逻辑和哪棵树无关 |
| **新建文件** | `_prompt_new_file()` `_prompt_new_file_in()` `_default_new_file_name()` `_on_new_file_confirmed()` | 两个入口共用（右键目录 / 头部按钮），都落到 `_prompt_new_file_in(dir)`。默认名 `新建文件.txt`，撞名自动往后数 (2) (3) |
| **新建文件夹** | `_prompt_new_folder()` `_prompt_new_folder_in()` `_default_new_folder_name()` `_on_new_folder_confirmed()` | 和新建文件完全对称，只是用 `DirAccess.make_dir_absolute()`。默认名 `新建文件夹`（不带扩展名） |
| **头部按钮** | `_setup_explorer_buttons()` `_new_target_dir()` `_update_new_buttons()` `_update_fav_dir_button()` `_has_open_dir()` `_on_fav_dir_button_pressed()` | 「新建文件」「新建文件夹」「收藏当前文件夹」三个按钮 + 它们的可用状态。作用目标**恒等于当前打开的文件夹**（`root_dir`），规则见 §6。收藏那个是开关（亮/灰星星表示状态），挂钩点见 §7.17 ⑬ |
| **重命名** | `_prompt_rename()` `_validate_new_name()` `_on_rename_confirmed()` | 校验拆成了纯函数，方便不起弹窗就能测 |
| **名字校验** | `_validate_name_in_dir()` | 空名 / 非法字符 / 撞名 / **目标目录为空**四档，**新建文件和新建文件夹、重命名共用这一套**（`_validate_new_name()` 只是委托它），省得两边各自长歪 |
| **删除** | `_prompt_delete()` `_on_delete_confirmed()` | 走系统回收站 |
| **文件树** | `_setup_file_tree()` `set_root_dir()` `refresh_file_tree()` `_populate_dir()` | 建树、换根、刷新、填充。**`_populate_dir()` 只填一层**（懒加载，见 §7.19） |
| **懒加载 / 展开** | `_ensure_dir_loaded()` `_ensure_dir_loaded_for()` `_set_dir_collapsed()` `_on_file_tree_item_collapsed()` `_add_lazy_placeholder()` | 展开 = 填下一层的**唯一**时机。两个入口（单击/dblclick、点箭头）缺一不可，理由见 §7.19 |
| **展开状态保留** | `_collect_expanded_paths()` `_restore_expanded_paths()` | 刷新时保住用户**展开过的**目录（不是折叠的，见 §7.5） |
| **条目判定** | `_item_path()` `_item_is_dir()` `_is_editable_file()` `_is_under()` | 几个纯查询函数 |
| **点击** | `_on_file_tree_item_selected()` `_on_file_tree_item_activated()` `_activate_file_path()` `_on_open_as_text_confirmed()` | 单击 / 双击 两条不同的路。**"打开这个文件"这个动作只有一份**，就在 `_activate_file_path()`（文件树双击和收藏列表双击都走它），因为里面那两道守卫都是防丢字的，见 §7.17 |
| **收藏夹** | `_setup_fav_tree()` `refresh_fav_tree()` `_is_favorite()` `_toggle_favorite()` `_on_fav_item_activated()` `_reveal_in_file_tree()` `_load_favorites()` `_save_favorites()` `_normalize_path()` `_path_exists()` | 收藏树（代码建）、列表渲染、收藏 / 取消收藏、双击跳转、存档读写。见 §7.17 |
| **导航** | `_setup_nav_buttons()` `_go_to_parent()` `_go_forward()` `_parent_dir_of()` `_update_nav_buttons()` + `_nav_forward` | 左侧那排的「上一级 / 前进」和它们的历史栈。见 §7.18 |
| **视图切换** | `_setup_view_buttons()` `_set_view()` `_fav_view` | 在 Explorer / 收藏两块之间切，顺带换标题、藏头部三个按钮、同步两个视图图标按钮的按下态 |
| **程序化选中** | `_select_tree_item_for_path()` `_materialize_path()` `_find_child_item()` + `_suppress_dir_toggle` | 在树里定位并选中一条，顺带展开祖先链。**它会让 `item_selected` 发出来**，那一下的副作用是这条链路的设计核心，见 7.14。懒加载下定位不能按完整路径找，得从根一层层往下走（`_materialize_path()`），见 §7.19 |
| **预览面板**（文件末尾那一整段） | `_setup_preview()` `_resolve_preview_mode()` `_effective_preview_mode()` `_should_show_preview_rail()` `_update_preview()` `_render_preview()` `_set_preview_rail_visible()` `_apply_preview_font_size()` + 几个事件处理器 | 右侧按扩展名给阅读视图。**两个判模式的函数是分层的，别合并**：`_effective_preview_mode()` 管"渲染成什么"，`_should_show_preview_rail()` 管"栏在不在"——它们对"没打开文件"和"打开了不可预览的文件"给出**不同**答案，理由见 §7.20 ③ |
| **预览翻页**（夹在预览面板里） | `_walk_pages()` `_ensure_pages()` `_page_index_for()` `_invalidate_pages()` `_queue_page_refresh()` `_refresh_page_bar()` `_goto_page()` `_turn_page()` `_apply_preview_paged()` `_on_preview_rtl_gui_input()` `_resolve_pending_turn()` | 把自由滚动切成一次一屏。**`_page_index` 是权威页码**（末页页首超滚动上限会被引擎夹掉，反推会往回跳）；分页表**惰性重算 + 只置脏不每帧算**；输入全走 `preview_rtl.gui_input`，链接护栏必须"延后一步再决定"。全在 §7.20 ⑬ |

---

## 5. 核心状态

理解这几样，代码基本就通了：

### `current_file_path: String`

当前编辑器里的内容对应的磁盘文件。**空串 = 没有对应文件**（可能是新写的、也可能刚被删掉）。

它是好几处危险的枢纽：`save_file()` 直接 `FileAccess.open(current_file_path, WRITE)` **原地覆盖**。所以任何让这个路径"指错地方"的改动，都会变成数据丢失。规则：

- 重命名当前文件 → 必须同步更新它（否则 Ctrl+S 写回旧名字，凭空多一个文件）
- 删除当前文件（或它所在的目录）→ 必须置空（否则 Ctrl+S 把刚删的文件原地重建出来）

### `root_dir: String`

文件树的根目录。`set_root_dir()` 里有**同目录直接 return** 的守卫——这是防止每次点文件都重建整棵树、把所有折叠状态重置掉的关键。

### `TreeItem` 的 metadata

树里**每个条目**（目录和文件都有）都挂一个字典：

```gdscript
item.set_metadata(0, {"path": "/abs/path", "dir": true/false})
```

早期只有文件挂 metadata、目录靠 `metadata == null` 反推，导致右键菜单拿不到目录路径，所以改成了统一字典。读的时候一律走 `_item_path(item)` / `_item_is_dir(item)` 这两个助手，别直接读 `get_metadata(0)`。

> 没有 metadata 的条目是"未指定目录" / "还没有收藏" 那两个占位提示，`_item_path()` 会返回空串——
> 多处守卫靠"空串"来判断"这不是个真条目"。

### `_favorites: Array[String]`（收藏夹）

收藏的**绝对路径**，顺序 = 用户收藏的先后（列表就按这个顺序显示）。
它是内存里的**唯一真源**：收藏树的每一行都是从它重建出来的，落盘也是把它整个写进存档资源。

存全路径而不是相对路径 —— 收藏的目的就是跨目录跳，相对某个 `root_dir` 没有意义。
写进去之前一律过 `_normalize_path()`（正斜杠、`simplify_path()`、去掉结尾斜杠），
否则同一个目录从对话框选进来是 `C:/a/b/`、从树里点出来是 `C:/a/b`，会被当成两条各存一份。

配套的 `_fav_view: bool` 记录现在显示的是哪一边（见 §7.17 的 `_set_view()`）。

### `_nav_forward: Array[String]`（前进栈）

「上一级 / 前进」那颗按钮的历史。按「上一级」时把**离开的那个目录**压进来，
按「前进」弹出去回去。它只有这一对按钮会往里写。

**其他所有换根方式都会清空它** —— 清空点在 `set_root_dir()` 里，由一个 `keep_forward`
参数控制（默认 `false` = 清）。理由：从别处跳到一个新目录，等于导航历史在那里分了个叉，
旧的前进目标已经不该再回去了（浏览器的地址栏是同一个行为）。
OpenDir、Ctrl+O 打开别处的文件、双击收藏里不在当前根下的目录，全走这条清空路径。

> 连带一条：`set_root_dir()` 是**早退**的（目录没变就直接 return），那条路上前面那句
> 清空不会执行 —— 这是对的，`root_dir` 没变等于什么都没发生。但反过来，
> 任何"应该清空"的调用只要撞上早退，也就没清 —— 那同样是对的。

---

## 6. 交互行为总表

| 操作 | 目录 | 可编辑文件（`.txt` `.md` …） | 不可编辑文件（`.docx` `.pptx` …） |
|---|---|---|---|
| **单击** | 展开 / 折叠 | 载入编辑器 | **只选中高亮，不载入** |
| **双击** | 展开 / 折叠 | 载入编辑器 | **弹提醒 → 确认后按文本打开** |
| **右键** | **第一、二项「新建文件」「新建文件夹」** + 文件管理器 / **收藏** / 重命名 / 删除 / 复制路径 / 刷新 | 文件管理器 / **收藏** / 重命名 / 删除 / 复制路径 / 刷新 | 同上，**外加第一项「用默认程序打开」** |

几个反直觉的地方，都是故意的：

- **单击不可编辑的文件什么都不做**：读进来是二进制乱码，而 `current_file_path` 会被指过去，接着按 Ctrl+S 就把原文件覆盖成乱码了。
- **双击才是"强制按文本打开"**：这个入口主要给两种情况用——`.toml` / `.env` / `Dockerfile` 这类没进白名单但本来就是文本的文件；以及真想看看 `.docx` 里装了什么。会先弹一个提醒框。
- **双击目录 = 展开 / 折叠，但实现上有个弯**（详见 7.11）：Tree 把双击拆成"第一下当普通单击 + 第二下发 `item_activated`"，而第一下切没切取决于那一刻条目**是否已被选中**，所以第二下必须靠 `_toggled_path` 判断要不要补切。不判断就会在"未选中"那条路上切两次、净效果为零 —— 那正是之前"双击文件夹没反应"的原因，而且只在**已选中**的目录上才复现。
- **双击当前已打开的文件不重读**：否则顺手双击一下正在编辑的文件，没保存的改动当场被冲掉。
- **「新建文件」只对目录出现**：文件条目的上下文里没有说得通的目标目录。默认名是 `新建文件.txt`
  （`.txt` 在 `TEXT_EXTENSIONS` 白名单里，建完能直接编辑），同目录已有同名的就往后数成 `新建文件 (2).txt`。
  弹框里**预选的是主名、不含 `.txt`**（复用重命名那套 `_select_base_name_in()`），所以用户一打字就把
  "新建文件"整个替换掉、后缀留着 —— 这就是"默认 txt"落到实处的地方。
- **右键新建完会把新文件打开**（详见 7.14）：看着像副作用，其实是有意依赖的链路，别顺手把它去掉。
- **「新建文件夹」和「新建文件」一样只对目录出现**，两个入口：右键目录里的第二项，以及文件树头部
  （「Explorer」那行）对应那个按钮。默认名 `新建文件夹`，同目录已有同名的就往后数成 `新建文件夹 (2)`。
  它没有"主名 / 扩展名"可分，所以弹框里是**整段选中**（走的同一个 `_select_base_name_in()`，
  只是找不到扩展名就退化成全选）。
- **头部那排三个按钮（新建文件 / 新建文件夹 / 收藏当前文件夹）的目标都是同一个：当前打开的这个
  文件夹**（`root_dir` 本身），**和树里的选中项无关**：选中谁也不影响它，永远作用在你正开着的那个目录里。
  早先的规则是"建在选中项所在 / 旁边的目录"，被用户推翻了 —— 先前的设计要靠选中项猜意图，
  实际用起来就成了"我明明开着 A 目录，东西却跑进选中的那个子目录里了"。
  想放进子目录就走那个子目录的**右键菜单**（右键 → 新建文件 / 新建文件夹）：
  那里有明确的"对着谁操作"的上下文，比靠选中项猜可靠。
  一个目录都没打开时三个按钮**禁用**——那种状态下 `root_dir` 是空串，`path_join()` 出来的相对路径
  会把东西写到进程的工作目录（导出后是 exe 所在目录），用户根本找不着。
  可用状态在每次 `refresh_file_tree()` 里跟着重算，所以换根目录、开新目录之后不会剩下一个亮着的按钮
  （判断条件就一个 `_has_open_dir()`，三个按钮共用）。
- **「收藏当前文件夹」是个开关，不是单向的收藏**：再按一下就是取消收藏。
  所以它的状态必须**一眼看得出来**，否则用户会点第二下把自己刚存的收藏悄悄删掉。
  两处提示：星星图标**亮 / 灰**（主）和 toggle 的按下底色（次）。
  为什么不能只靠按下底色见 §7.17 ⑬。它也是"收藏当前文件夹"的**唯一**入口 ——
  树是 `hide_root = true`，当前根自己那一行根本不存在。
- **菜单开着的时候再右键另一个条目，一下就换过去**（详见 §7.16）：原来必须先左键点一下把菜单关掉，
  再右键 —— 用户的原话是"右键一个文件之后就再右键其他文件就不行，能不能改得丝滑一点"。
  现在一次右键**既关旧菜单又开新菜单**，目标直接换成新点中的那个条目。
- **菜单开着的时候左键点外面，那一下会照常作用在点到的条目上**：菜单关掉，点到的是文件就载入、
  是目录就展开 / 折叠（和没开菜单时点它一模一样，也和 VS Code 一致）。
  这是引擎自己的行为（把菜单藏掉之后，同一个按下事件会继续走到主视口），
  代码里**不要**再手动补一次点击，否则就变成"点一下触发两次"。
- **左键点在菜单「里面」是选菜单项**：事件被菜单完全吃掉，不会穿透到底下的条目 ——
  harness 里专门验了"Tree 一条信号都收不到、文件不会被载入"。
- **对着菜单已经压住的那一行再右键 = 点在菜单自己身上**，那一下由引擎处理（菜单把自己关掉）。
  没走到 `_on_menu_window_input` 的分支，也不会误开文件 —— 如实记录，不是 bug。
- **「收藏 / 取消收藏」是同一条目上的两态**，文案跟着当前状态走（已收藏就显示「取消收藏」），
  文件和目录都能收藏。数据存进框架的存档资源，跨次启动保留。
- **目录的展开状态不会因为"程序化选中"而改变**（详见 7.14.1）：重命名一个目录、或者新建一个文件夹，
  都会在树里选中它，而选中目录在别处是"切换展开 / 折叠"的意思。早先没挡这一下的时候，
  重命名一个**有内容的**目录会把它收起来 —— 里面的文件当场从树里消失。

### 收藏视图（按左边的星星按钮切过去）

| 操作 | 行为 |
|---|---|
| **单击条目** | **什么都不做**（`fav_tree` 根本没接 `item_selected`）。只有双击 / 回车才有动作 |
| **双击收藏的文件** | 打开并切回文件预览；不在当前根下时 `open_and_show()` 会把树重定到它所在目录再选中 |
| **双击收藏的文件夹** | 切回文件预览；在当前 `root_dir` 下 → **展开并选中**它；不在当前根下 → `set_root_dir(它)`（等同 OpenDir） |
| **右键条目** | 只有「取消收藏」+「在文件管理器中打开」（**没有**重命名 / 删除，理由见 §7.17） |
| **路径已不存在的条目** | 灰显 + tooltip 加一句「（路径不存在）」；双击只弹一条顶部提示，**不会**自动删掉收藏 |

- **收藏列表里的条目文本是 `文件名 — 父目录名`**（不是完整路径）。侧边栏默认只有 300 像素，
  Tree 从右边裁长文本 —— 写完整路径实测显示成 `a.txt  —  C:/Users/klderm…`，
  留下的恰好是所有条目都相同的那一截前缀，等于什么都没写，还白占半行。
  完整路径在 **tooltip** 里，鼠标一停就有；几个同名文件靠父目录名区分。
- **失效条目灰显而不是自动删除**：外接盘 / 网络盘临时断线是常有的事，
  不能因为这一次读不到就把用户存的东西清掉。右键「取消收藏」始终可用，那是用户唯一的出路。
- **切到收藏视图时头部那三个按钮全都会藏起来**：它们的语义都是"对着当前打开的那个目录做点什么"，
  收藏视图里 Explorer 整个不在，没有落脚点。
  （副作用：那一行因为少了三个比标题高的按钮而矮了 8 像素，
  收藏树因此比文件树高 8 像素 —— 正常现象，不是布局没重排。）
- **切到收藏视图 / 切回 Explorer 都不会动到另一边的状态**：树的选中项、折叠状态、
  当前打开的文件、编辑器里的内容全都不受影响（harness 里来回切 5 次逐个断言过）。

### 右侧预览栏

打开什么文件，右栏给什么阅读视图。**模式是按扩展名自动定的**：

| 打开的文件 | 右栏 | 内容 |
|---|---|---|
| 任何 `.txt` | 显示，标题 `Preview · 小说` | `TextToBbcode` 排的阅读版式：全角两格首行缩进、按字号比例放大的行距、整行 `* * *` 转成居中分隔线 |
| 任何 `.md` | 显示，标题 `Preview · Markdown` | `MarkdownToBbcode` 转成 BBCode 的渲染结果 |
| 其它（`.py` `.json` `.gd`、被强制按文本打开的 `.docx`…） | **整栏收起**，宽度还给编辑器 | 不渲染任何东西，上一次的内容被清掉 |

- **栏的收/放不是把内容藏起来，是把 `SpC` 的第三个子节点 `visible = false`** —— 剩下的可见子节点重新分宽度，编辑器当场变宽 274px（外加分隔条那 12px）。实测 `split_offsets` 会跟着重排下标（`[221, -274]` → `[221]`），所以收起前存一份、显示时原样写回，那一对是承重的、不是保险，见 §7.20 ④。
- **工具栏那颗「Preview」按钮是开关，不是"打开预览"**：按一下收起、再按一下放回来，按钮的 `button_pressed` 就是那个意图。它**只在本来就有预览的文件上有效**；开着 `.py` 时按它没有任何变化——那种文件唯一正确的状态就是收起来。
- **「更改预览器」按钮手动指定模式**，菜单三项：自动（按扩展名）/ 小说预览 / Markdown 预览。手动选择**是粘性的**（换文件不重置，换到同类文件时立刻生效），但**越不过"非 txt/md 一律收起"这条线**：给 `.py` 手动选 Markdown 也不会把栏叫出来，理由见 §7.20 ③。
- **「设置字号」按钮弹九档字号**（12 14 16 18 20 22 24 28 32，默认 16），当前档位带勾。改字号会同时铺满**五个**主题项并重算行距，见 §7.20 ①。
- **「目录」按钮开关章节目录**。目录是转换器**同一次转换免费带出来的**（它本来就在逐行过），
  不扫第二遍源文本。层级靠 `level` 嵌套：`卷/部/篇/集` 是第 1 层（`第1卷 风起`），
  `章/节/回` 是第 2 层，固定词（`序章`/`楔子`/`番外`…）算第 2 层。点一条就滚过去。
  没章节时按钮**禁用**（右栏才 274px 宽，开一个空框纯占地方）。
  - **列表重建有门控**：防抖每 200ms 重排一次、每次都会带出新的 `chapters`，但用户敲的是
    正文、章节一个都没变 —— 所以只在"章节集合真的变了"时才重建 UI（`_same_chapters()`）。
    无条件重建的话，打字时目录每 200ms 清空重填一次，选中项和展开状态全被抖掉。
  - ⚠️ 目录树**故意开着 `allow_reselect`**，和 `FileTree`/`fav_tree` 相反。那两棵关掉是因为
    "选中 → 折叠 → 树变了 → 又选中"会每帧振荡到崩（§7.1）；目录没有这个回路（选中只滚
    RichTextLabel，**不回改树**），而关掉的话"滚走了再点同一章"就点不动了 —— 那恰恰是
    目录最常用的操作。
  - **长标题在树里一定是被裁掉的，悬停提示是唯一能读全文的地方**：右栏固定 274px，每层缩进
    还要再吃十几个像素。单列 `Tree` 的列宽会撑满树宽，所以溢出部分**连横向滚动条都出不来**
    ——不是"没开横滚"，是根本没有溢出。所以 `set_tooltip_text()` 里放的是**标题全文**，
    不是段落号（只放段落号等于没有提示）。
- **齿轮按钮弹「阅读设置」**，五项各一段（组标题 + 档位）：
  行距 `0.75/1/1.25/1.5/2×`、首行缩进 `0/1/2/3/4` 字、阅读宽度 `全宽/180/220/260 px`、
  阅读主题 `默认/纸白/米黄/夜间`、翻页模式 `滚动/翻页`。当前档位带勾。
  - **五项的作用层各不相同**，分错层的症状都是"调了没反应"：行距改的是 RTL 的**主题常量**；
    翻页模式改的是外层 `ScrollContainer` 的**滚动形式**；缩进和主题要**重跑转换器**
    （它们影响吐出来的字符串）；阅读宽度改的是外层 `ScrollContainer` 的 min 宽。
    所以 setter 分成两档粒度，调字号/行距/页宽/翻页**不重跑转换器**
    （那 200ms 预算里最贵的一步）。
  - **阅读宽度只给正文列，不改右栏宽度**：`ScrollContainer` 自己 `SHRINK_CENTER` + `custom_minimum_size.x`，
    **一个场景文件都没改**（理由见 §7.20 ⑨）。页码条跟着同一份宽度走，窄栏时和正文列对齐。
  - **翻页模式**（默认**关**，= 改动前的自由滚动）：鼠标滚轮、正文左右半屏点击、
    下方页码条的 `«`/`»` 按钮都能翻。点链接不翻页。见 §7.20 ⑬。
  - **五项 + 字号 + 手动指定的预览模式全都持久化**，落在 `user://der_settings.tres`
    （走 `DSettingsManager`，不是存档那套）。重启后生效，见 §7.20 ⑫。
- **打字停 200ms 后重排**（`text_changed` + 一次性 Timer）。两道闸门省 CPU：模式是 `NONE` 时**根本不起 Timer**（所以在 `.py` 里打字不会有任何排版开销），超长文件直接给「太长」提示而不是硬排。
- **滚动位置在重排后保住**：在长文末尾打字，视图不会一路跳回顶部。
- **没打开任何文件时右栏是空壳，但仍然是可见的、也是开得掉的** —— 这是有意的：启动时右栏凭空消失是外观回退，而且那种状态下如果按模式决定栏的去留，工具栏那颗按钮就成了死键。详见 §7.20 ③。
- **Markdown 里的链接**：只放行 `http://` / `https://` / `mailto:`。其它（`javascript:`、`file://`、相对路径）渲染成不可点的蓝字 + 后面跟一段灰的原文，`meta_clicked` 里再挡一次同一个白名单。

### 白名单

能直接编辑的扩展名在 `TEXT_EXTENSIONS`（文件头那个常量）。**没有扩展名的文件（`README`、`Makefile`、`LICENSE`）也算"不可编辑"**——判断不出类型时选了保守方向：宁可少编辑一个文本文件（改名成 `.txt` 就能编辑），也不要赌一把把二进制灌进编辑器。想编辑它们用双击。

加扩展名就往那个数组里加，一处生效（图标、单击行为、菜单项都跟着变）。

---

## 7. 【重点】引擎坑位 —— 这些是实测出来的，别照直觉改回去

这一节是整个文档里最值钱的部分。下面每一条都是踩过之后在代码注释里钉住的，**改之前先读注释**。

### 7.1 `file_tree.allow_reselect` 必须保持 `false`

开了它，Tree 在重选同一项时会重复发 `item_selected`。而折叠一个**已选中**的条目会触发 Tree 内部重选 → 于是形成 `折叠 → 重选 → 折叠` 的死循环，**每帧振荡，同步处理时直接段错误崩溃**。

### 7.2 右键不能接 `item_mouse_selected`

那个信号回调里给的 `mouse_position` 实测是**屏幕坐标**（窗口在屏幕上的位置也算进去了），而 `get_item_at_position()` 要的是 Tree 局部坐标，两者对不上，喂进去永远返回 `null`。

改用 `gui_input`，里面 `event.position` 才是局部坐标。

### 7.3 右键会连带触发 `item_selected`

也就是说：右键点一个文件，如果不拦，会把它载入编辑器。所以 `_on_file_tree_item_selected()` 开头有一道 `Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)` 的守卫。

### 7.4 Godot 4 的无参 `popup()` 弹在 `(0,0)`

**它不读鼠标位置**——那是 Godot 3 的行为，网上大量文档还在那么写。必须显式给坐标：

```gdscript
file_item_menu.popup(Rect2i(file_tree.get_global_position() + event.position, Vector2i.ZERO))
```

而且 `popup(rect)` 的 `rect` 吃的是**视口局部坐标**（窗口内容坐标系），不是屏幕坐标。

### 7.5 `TreeItem.collapsed` 默认是 `false`（展开），而且它是个独立的存储位

两件事分开记：

- **默认值**：`create_item()` 出来的条目 `collapsed` 是 `false`。`_populate_dir()` 建目录条目时
  必须**显式**写 `dir_item.collapsed = true`，不写就是展开态 —— 用户点它反而会把它收起来，交互整个反。
- **它和"有没有子节点"没关系**：实测 4.7.2，在一个**空的**条目上设 `collapsed = true`，
  之后再加子条目，读回来**依然是 `true`**。所以"先折上、等展开时再填内容"是可行的 ——
  懒加载整套就压在这上面（§7.19）。
  （反过来的坑：没有子节点的条目**不画展开箭头**，见 §7.19 的占位条目。）

**保留的是"展开过的"目录，不是"折叠的"** —— 刷新时走 `_collect_expanded_paths()` /
`_restore_expanded_paths()`。懒加载之下默认态就是折叠，所以要保住的是用户点开的那些；
记反了的话，用户展开的目录会每次刷新都塌回去。

### 7.6 Tree 会静默拒绝折叠"包含当前选中项"的目录

给那个目录赋 `collapsed = true` 当场读回来还是 `false`，不报错也不发信号。通过 UI 走不到这个状态，所以不用额外处理，但写测试时会遇到（别以为是自己的 bug）。

### 7.7 Tree 的 `icon_size` 主题常量在 4.7 对绘制尺寸无效

图标是按原始尺寸画的，源图 400×400 能把整行撑爆。所以 `_make_icon()` 在**加载时**就用 `Image.resize()` 统一重采样到 15×15，而不是靠主题常量。

### 7.8 `OS.alert()` 在 Windows 上是**阻塞**的

任何埋在它后面的分支都没法从脚本里驱动（测试会直接挂住）。所以校验逻辑拆成了纯函数——典型例子是 `_validate_new_name(old_path, new_name) -> String`，返回 `""` 表示可用，否则返回给用户看的原因。

### 7.9 场景里所有节点都带 `unique_id`

这是这套 tscn 格式的必需字段（`main.tscn` 里每个节点都有，写这段时是 49 个）。**手写 tscn 加节点容易把 id 写错或写重**，所以新加的对话框（重命名的 `LineEdit`、"按文本打开"的提醒框）都是在代码里 `new()` 出来的，让 Godot 自己保存场景时落盘更安全。

**界线**：这条规矩针对的是"代码里建、用户不用在编辑器里看见"的东西（对话框、`fav_tree`）。
**露在界面上给人看的普通节点还是写进 tscn**，这样在编辑器里能直接调位置和样式 ——
头部那颗「收藏当前文件夹」的星星就是这么加的（`unique_id=1601234504`，加之前先确认没用过）。
代价：**手写 tscn 之后别在编辑器里保存这个场景**，否则你在编辑器里那份（还没有这个节点）会盖掉它。

### 7.10 `SettingButton` 的代码不在 `main.gd` 里

它用的是**内联在 `main.tscn` 里的 sub_resource GDScript**（搜 `GDScript_cee7s` 能看到），点了会 `load("res://scene/SettingWin.tscn")` 挂到按钮底下。

后果：在 `main.gd` 里 grep 是**找不到**设置按钮的处理的，别以为功能没实现。

而且该节点是 `visible = false` 的，等于整个设置窗口目前没启用。

### 7.11 Tree 的"双击"= 一次普通单击 + 一次 `item_activated`

实测（合成真实鼠标事件，两下之间留一帧）：

| 双击时条目状态 | 第一下 | 第二下 |
|---|---|---|
| 原本**没选中** | 发 `item_selected` —— 等于一次普通单击，目录会被顺势切一次 | 发 `item_activated` |
| 原本**已选中** | **什么都不发**（`allow_reselect = false` 把重选吞掉了） | 发 `item_activated` |

所以在 `item_activated` 里切换目录时，**必须先知道第一下有没有已经切过**：

- 未选中那条路：第一下已经切过了，再切一次正好抵消 → 看起来"双击没反应"
- 已选中那条路：第一下什么都没发生，这里**必须**补切一次

`_toggled_path` 就是干这个的：`gui_input` 在**非双击的**左键按下时清空它，`item_selected`
切过之后把路径写进去，`item_activated` 发现路径对得上就跳过。

> 双击的第二下（`double_click = true`）**不能**清这个变量，否则正好把要判断的东西抹掉。
> 这个 bug 只在"已选中"的目录上复现，所以单看未选中的目录会以为双击是好的。

### 7.12 展开箭头是 Tree 自己处理的，但**必须**接 `item_collapsed`

点条目前面那个三角形，Tree **原生**就会切换折叠状态，而且它**既不发 `item_selected`
也不发 `item_activated`**（实测两者都是 0 次）。

**代价是：别想着在 `gui_input` 里按鼠标位置也去切一下** —— 那样箭头会被切两次、净效果为零。
所以目录的切换只能挂信号，不能挂"按下的位置落在哪个条目上"这种判断。

懒加载之前这条路确实"完全不用管"，现在不行了：展开是**唯一**的填充时机，而点箭头不发
`item_selected` —— 不接 `item_collapsed` 的话，点箭头展开出来的目录是个**空壳**（而且不报错）。
接口在 `_on_file_tree_item_collapsed()`，那里也记着为什么它只处理"展开"那一半。
细节见 §7.19。

> 实测补充：这个版本里 `item_selected` 发 **0** 个参数（`_on_file_tree_item_selected()` 本来
> 就没参数），`item_collapsed` 发 **1** 个（那一个条目）。写测试连信号时参数个数写错会在
> emit 的那一刻报 `Method expected 1 argument(s), but called with 0` —— 信号**发了**，
> 只是回调没跑成，日志里看着像"信号没发"，很容易查错方向。

### 7.13 回车和双击在信号里长得一样，用鼠标状态区分

`item_activated` 既被"双击的第二下"触发，也被"键盘回车"触发，回调里拿不到事件、区分不出来。
用 `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)` 区分：实测双击第二下触发时它是
`true`，回车是 `false`（合成事件也准，因为按下和释放是分开发、按序处理的）。

不加这道判断，回车会不会切换目录就取决于"上一次点击是不是重选"，成了说不清的行为。
现在目录只响应鼠标，回车保持老样子（不该目录做事）。

### 7.14 `TreeItem.select()` 会发 `item_selected`，所以 `_select_tree_item_for_path()` 会**打开文件**

`TreeItem.select(column)` 不是"只改高亮状态"，它会把 `item_selected` 发出来。而本应用里
`item_selected` 的处理就是"载入编辑器"，所以 `_select_tree_item_for_path(p)` 的真实副作用是
**把 p 载入编辑器**，不只是让树里那一项亮起来。五个调用点都吃这个副作用：
`open_and_show()`（尾）`save_file()`（尾）`_on_new_file_confirmed()` `_on_new_folder_confirmed()`
`_on_rename_confirmed()`。

新建文件那一版就是这么被"惊到"的：断言写的是"新建之后编辑器内容还在"，实测
`current_file_path` 变成了新文件、编辑框被清空。**查下来这不是 bug，是有意保留的**——
本应用靠这条链路维持一个不变量：**树里的选中项和编辑器里的内容永远一致**。

为什么不去掉：新建后如果不载入，`current_file_path` 还指着上一个文件，用户新建完直接打字，
敲进去的其实是**上一个还开着的文件**，然后 Ctrl+S 就把它覆盖了 —— 静默的跨文件覆盖，
比"新建之后编辑框被清空"糟得多。真要改得先做"切换文件前询问未保存改动"。
注意这个代价不是新建独有的：点树里任何一个别的文件本来就是这行为。

顺带一个连带效果：`open_and_show()` 自己也会在结尾调它，看起来像是要无限递归，
实际停在两层 —— `_on_file_tree_item_selected()` 里有 `if path == current_file_path: return`
（`main.gd:842`），而 `open_and_show()` 早就把 `current_file_path` 设好了，
所以它自己触发的那次 `item_selected` 会当场刹车。**删那一句之前先想清楚这个刹车。**

### 7.14.1 同一件事的另一面：选中**目录**会切换它的展开状态（已修）

`_on_file_tree_item_selected()` 对目录的处理是 `item.collapsed = not item.collapsed`，
所以上面那次"程序化选中"落在目录上时，会**顺手把用户看着的那个目录翻个面**。实测（两个都验过）：

- **重命名一个目录** → 树刷新后新条目是展开的，`select()` 那一下把它切成折叠。
  后果不是"状态没保住"那么轻：一个**有内容的**目录被重命名后，内容当场从树里消失，
  用户看起来像是"重命名把里面的文件弄没了"。
- **新建文件夹** → 刚建出来的目录是折叠状态，而且它**有一个空占位子条目**撑着箭头
  （§7.19），所以空目录看起来和有内容的一样、只是点开是空的。
  它会被 `_collect_expanded_paths()` 按路径一路保住，等真有东西了，
  就是"我自己刚建的文件夹，里面的文件不见了"。
  （懒加载之后新建目录是**折叠**的，`_suppress_dir_toggle` 要防的是反向那一下 ——
  选中它会让它**展开**、把刚建的空目录摊开，同样不是用户要的。）

修法是 `_suppress_dir_toggle` 这个开关，只在 `_select_tree_item_for_path()` 里围着那一句
`item.select(0)` 打开（`main.gd:920` 附近）。三条要记住的：

- **必须紧贴着 `select()`**：信号是**同步**发的，中间不能有 `await`，也不能提前 `return`
  （现在这两句之间什么都没有，是故意的）。
- **别把它漏成全局状态**：正常点击目录必须照旧能切换。harness 里专门验了两条 ——
  收尾后开关是 `false`，以及模拟一次真实单击（先 `deselect_all()` 再 `select(0)`，绕开
  `allow_reselect = false`）仍然能切换。
- 代价是**重命名的展开状态保不住**：展开状态是按**路径**记的（`_collect_expanded_paths()`），
  路径一改名就对不上，所以重命名后的目录回来时是**折叠**的（懒加载的默认态，见 §7.19），
  里面原本展开的东西也一并收回去了。这是取舍，不是漏做 —— 换成"宁可展开"就会退回上面
  那个"内容当场消失"的坑（只不过方向反过来：变成"凭空多出来一层"）。

### 7.15 三个 FileDialog 的 filters 都改成了「所有文件」—— 几个实测出来的细节

三个对话框的定义全在 `page/main.tscn` 里（`main.gd` 只 `@onready` 拿引用，不在代码里改
filters）。原来的 `filters = ("*.txt", "*.json", "*.csv")` 现在统一成 `"*.* ; 所有文件"`。

- **`显示所有类型` 这件事，改的是「默认选中哪个」。** 实测内置对话框的下拉里本来就有一个
  `All Files (*.*)` —— Godot 自己会补上这个选项。所以改之前的问题不是"没有所有文件可选"，
  而是**默认选中 `*.txt`，每次都得手动切一下**。现在默认就是「所有文件」。
- **`打开目录` 那个对话框没什么可改**：`file_mode = FILE_MODE_OPEN_DIR` 的对话框根本不用
  filters（本来就没有），列出来的全是目录。
- **`*.*` 不匹配"没有扩展名"的文件 —— 这只影响内置对话框。** 内置对话框用 `String.matchn()`
  匹配，`"*.*".matchn("README")` 是 `false`（要求名字里得有个点）。实测：fixture 里的
  `noext` 确实列不出来，`a.txt` / `b.py` / `c.log` 都列得出来。
  但 **Windows 原生对话框的 `*.*` 是匹配全部的**（这是 Windows 自己的语义），
  而本项目 `use_native_dialog = true`，所以实际看到的是原生对话框，`noext` 之类照样显示。
  写成 `*` 能同时满足两边，但原生那边 `*` 没人验过 —— 用原生时 `*.*` 是标准的写法，别乱改。
- **已知的引擎卡死：内置对话框 + `*.*` + 不带扩展名的名字，按 OK 会挂住。** 实测：
  另存为输入 `foo_baz`（无扩展名）按 OK，进程直接停在那里（退出码 124），
  连 `file_selected` 都没发出来 —— 卡在 Godot 自己的保存处理里，本应用的代码根本没被调到
  （`_on_save_as_file_selected()` 只认路径，跟扩展名无关）。**只在内置对话框这条路上有**，
  原生对话框不走这段逻辑，所以正常使用时碰不到。真要关掉 `use_native_dialog`，先验这条。
- **另存为输入不带扩展名的名字，落盘就是不带扩展名的。** 改之前默认过滤项是 `*.txt`，
  现在没有 `*.txt` 可依据了。带扩展名输入（`foo.txt`）不受影响，实测正常落盘。
  顺带一提：不带扩展名的文件不在 `TEXT_EXTENSIONS` 白名单里，点它不会载入编辑器
  （见 §6），所以起名时把扩展名写上更省事。

### 7.16 菜单（嵌入式 `PopupMenu`）开着的时候，输入到底去了哪儿 —— 全是实测的

这一节是"右键不丝滑"那个问题的完整答案。症状：右键条目 A 弹出菜单后，再右键条目 B **没反应**
（菜单还开着、也不换目标），得先左键点一下关掉菜单，才能右键 B。要修它，先得知道开着的菜单
把事件弄到哪儿去了 —— 拿一个 `_input` 观察节点 + 菜单上的几个信号连起来量了一遍：

- **主视口一个事件都收不到。** 菜单是 `Window`（嵌入式子窗口），事件转发到它自己的视口之后，
  发往主视口的就没了：观察节点在整个菜单打开期间**一次 `_input` / `gui_input` 都没触发**。
  所以"在菜单外面又点了一下"这件事，主视口那边根本没法知道。
- **唯一的口子是 `Window.window_input`**（`PopupMenu` 上 `has_signal("window_input")` 为真），
  它会为转发到菜单的事件触发。`event.position` 是菜单**局部**坐标，
  加 `menu.position` 才是当初点下去的那个视口坐标（实测：菜单局部 `(0,-61.5)` + 菜单在 `(172,151)`
  = 用户点的 `(172,89.5)`）。`PopupMenu._input_from_window` 没有通过 `has_method` 暴露，别想着重写它。
- **引擎自己不会因为这个把你菜单关掉。** 早先看到日志里 `popup_hide` 排在 `window_input` 前面，
  以为是引擎先关、我再重弹 —— 其实那是**我自己的 `hide()`** 触发的：
  `main.gd` 的处理器是在 `_setup_item_menu()` 连的（比 harness 的探测器早），所以它会先跑，
  它发出的 `popup_hide` / `visibility_changed` 自然排在同一次 `window_input` 的日志前面。
  别被日志顺序骗了。
- **点菜单里面 vs 外面，判据要用菜单局部坐标**：`Rect2(Vector2.ZERO, menu.size).has_point(mb.position)`。
  点在里面直接 `return`，交给菜单自己处理。
- **左键点外面时，代码里只 `hide()` 就够了**：实测这一下会继续走到主视口，
  落在它盖着的那一行上（该载入的载入）。手动补发点击会变成触发两次。
- **右键点外面时，把新菜单 `call_deferred` 再弹**：一次右键既关旧菜单又开新菜单，这就是"丝滑"。
  延后是为了排在引擎在这帧的收尾之后，当场弹有被顺带关掉的风险。
- **菜单弹在哪个点，那个点就是它的左上角**，所以它自己盖住下面 151px 左右；
  "对着同一行再右键"其实是点在菜单上，引擎会把菜单关掉（见 §2 第 11 条，那个坑我踩了两次）。

对应的 harness 用例（`_tmp_rmb.gd` 那一版的思路，44 条断言全过）：
一次右键换目标 / 连换两次 / 换到目录时菜单内容跟着变成目录版（第一项是「新建文件」）/
左键点外面 = 关菜单 + 作用一次 / 左键点里面 = 完全被吃掉 / 空白处和树外面只关不弹 /
右键时绝不载入文件（`Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)` 那道守卫，见 §7.3）/
左键单击仍然正常载入（回归）。

### 7.17 收藏夹 —— 几个"必须这么写"的地方

功能：文件树里右键文件或文件夹 → 收藏；按左边的星星按钮 → 侧边栏从文件树换成收藏列表；
双击条目打开 / 跳转并切回文件预览；数据存进 `DSaveManager` 的存档资源。
另外文件树头部还有一个「收藏当前文件夹」的星星按钮（⑬⑭⑮⑯ 是它的）。

**① 收藏列表的树是代码建的，不是写进 `main.tscn` 的。**
项目的老规矩：`main.tscn` 里每个节点都带 `unique_id`，手写 tscn 容易把那个 id 写错或写重，
所以新加的对话框一律代码 `new()`（§7.9）。`fav_tree` 同理，在 `_setup_fav_tree()` 里建完
`add_child` 到 `file_tree.get_parent()`。
两个连带约束：
- 它必须是**普通成员变量**，不能是 `@onready` —— `@onready` 在 `_ready()` 之前求值，那时节点还不存在。
- `_setup_fav_tree()` 必须排在 `_setup_file_tree()` **之后**：三个图标是在那边备好的
  （`_icon_dir` / `_icon_file` / `_icon_unsupported`），先建的话行里会没图标，而且**不报错**。

**② 两棵树共用同一个 `file_item_menu`，只是参数化了"冲着哪棵树弹"。**
那套"丝滑"逻辑（§7.16）和"哪棵树"毫无关系 —— 它只看菜单自己的 `position` / `size`。
所以只做两件事：`_open_item_menu_at(vp_pos, tree)` 多收一个 `tree`（命中测试用它，不再写死 `file_tree`），
加一个成员 `_menu_source` 记住上下文给 `_build_item_menu()` 分支用。
`_on_menu_window_input()` 里那句 `call_deferred` 传的 `_menu_source` 会在**调用那一刻**求值，
拿到的正是当前这个菜单所属的树。

**③ `MenuId.FAVORITE` 追加在枚举末尾（= 8），没插在中间。**
插中间会让 `RENAME` / `DELETE` / `COPY_PATH` / `REFRESH` 全部 +1，而 §2 坑 12 和 §7.16 里
记着 `id=4` 这类硬编码数字 —— 将来照着那些数字调试会踩成"看着像功能坏了"的假故障。
菜单的**显示顺序**由 `add_item()` 的调用顺序决定，和 id 数值无关。

**④ 「打开这个文件」只剩一份实现：`_activate_file_path(path)`。**
文件树双击和收藏列表双击都调它。抽出来不是为了省代码，是因为里面有**两道防丢字的守卫**，
而 `open_and_show()` 自己一道都没有（它由调用者负责）：
- `if path == current_file_path: return` —— 少了它，双击一个正在编辑的文件就会
  用盘上的旧内容把没保存的改动当场冲掉；
- 不在 `TEXT_EXTENSIONS` 白名单里的文件必须经过 `_open_as_text_dialog` 的提醒 ——
  直接 `open_and_show()` 会绕过它，`.docx` 那类会灌一屏乱码进来，此时 Ctrl+S 就把原文件覆盖了。

**⑤ 双击收藏的文件夹不能只调 `_select_tree_item_for_path()`。**
那个函数只展开**祖先链**，目标自己的 `collapsed` 一个指头都不碰（`_suppress_dir_toggle`
正好把它压住了）—— 于是双击一个已折叠的收藏文件夹会"选中了但还是收着的"，和需求不符。
`_reveal_in_file_tree()` 里在它之后补了 `it.collapsed = false` + `scroll_to_item()`。

**⑥ 换根之后不要再调 `_select_tree_item_for_path()`。**
树根条目没有 metadata，`_item_path(root)` 恒为空串，永远找不到（白调）；
而万一将来有人给根条目加了 metadata，一次 `select()` 落到根上会把 `root.collapsed` 翻成 `true`，
在 `hide_root = true` 之下整个 Explorer 会**空掉**。

**⑦ 收藏列表的右键菜单没有「重命名 / 删除」。**
在收藏视图里点这两项，操作的是**文件系统上的真实文件**，而用户点的时候心里想的是
"这个收藏" —— 极易误删。真要用，去 Explorer 视图里点。
失效条目的「在文件管理器中打开」还必须 `set_item_disabled(true)`：路径不存在时判断不出
它当初是文件还是目录，`OS.shell_show_in_file_manager()` 会失败 → 走 `OS.alert()` →
Windows 上**阻塞**（§7.8），harness 当场挂住。「取消收藏」必须保持可用，那是用户唯一的出路。

**⑧ `refresh_fav_tree()` 只有三个挂钩点**：`_setup_fav_tree()` 尾部、`_set_view(true)` 开头、
`_toggle_favorite()` 尾部。**不要**挂到 `refresh_file_tree()` 上 —— 它在"未指定目录"那条路上
是 `return`，挂函数尾会被直接跳过。

**⑨ 视图切换用的工具栏入口都要显式 `_set_view(false)`**：`_on_open_file_selected` /
`_on_open_dir_selected` / `_on_save_as_file_selected` / `_on_open_as_text_confirmed`。
工具栏是**全视图共享**的，在收藏视图下点它，选中项其实是在**藏起来的那棵树**里被改掉的，
用户只会觉得"点了没反应"。
**不要**把这个副作用塞进 `_select_tree_item_for_path()` —— 它被 5 处调用（§7.14），
会让"新建文件"之类莫名其妙跳视图。

**⑩ `_set_view()` 里不要加"值相同就 early return"的幂等守卫。**
初始化那一次 `_set_view(false)` 会被吃掉，按钮按下态和标题就设不上。
同步按下态必须用 **`set_pressed_no_signal()`**：`set_pressed()` 会发 `toggled`，程序化同步会绕回去。

**⑪ 隐藏 / 显示同一个容器里的两棵树之后，手动 `queue_sort()` 一次。**
理论上下面的 `VBoxContainer` 会跳过隐藏的孩子，但"会不会重排"取决于 min size 有没有变，
而两棵树的 min size 可能一样 —— 不主动排一次的症状是"切过去只有半高，拖一下窗口才正常"。

**⑫ 落盘走 `DSaveManager.save_cur_res()`，代价照单全收。**
`save_cur_res()` → `save_resource()` 会顺手更新 `last_modified_timestamp`
并弹一条「存档保存成功」的顶部提示 —— 也就是**每收藏一次都会弹一条**。
`cur_res` 可能是 null（`use_auto_slot = false` 或存档被删），那时**读**不到就当空收藏夹，
**写**不了必须**说出来**（`push_warning` + 顶部提示，且只提示一次）：
"收藏了一堆、重启全没了"这种静默失败比一条错误提示糟得多。
守卫是 `if res == null or res.save_name == ""`。

> **改 addon 的公共 Resource 有个固有代价**：存过一次之后 `AutoSlot.tres` 里就带上了
> `favorite_paths`。将来若回滚这处 addon 改动，该字段会成为"孤儿属性"（加载时被忽略，不报错）。
> 老存档（没有这个字段）读进来取默认值 `[]`，其余字段照旧，不会丢 —— 实测过。

**⑬ 头部「收藏当前文件夹」的状态提示不能只靠 toggle 的按下底色。**
这个按钮是**开关**（再按一下就是取消收藏），状态看不出来用户就会点第二下、
把自己刚存的收藏悄悄删掉。而实测这个主题下 toggle 的"按下"只把按钮背景从
`(40,42,43)` 变成 `(32,34,35)`——**差 15/255**，一屏图标里根本认不出来。
（量法：两张截图逐像素比 —— `_tmp_shot.gd` 截图 + `fdt_pixdiff.py` 差分，
两个都在 `C:/Users/kldermr/AppData/Local/Temp/fdt_harness/`，不依赖任何第三方库。）
所以真正的提示是**星星图标亮 / 灰**：没收藏时 `modulate = FAV_DIR_OFF_TINT`（灰），
收藏了 `modulate = Color.WHITE`（亮黄）。改完再量，最大差从 45 涨到 371/765，一眼能认。
用 `modulate` 而不是再切一张图：主题里普通状态的底色几乎透明，乘上去看不出来。

**⑭ 这个按钮同时是"收藏当前文件夹"的唯一入口。**
树是 `hide_root = true`，当前根自己那一行**不存在**，右键永远够不着它 ——
在加这个按钮之前，用户只能先跳到父目录、再右键那个子目录来收藏它（会话里真出现过这种用法）。
所以它必须**既能加也能取消**（toggle），不能做成单向的。

**⑮ `_update_fav_dir_button()` 的挂钩点也是三处，和 `refresh_fav_tree()` 不是同一组。**
`refresh_file_tree()`（换根 / 有没有目录，跟 `_update_new_buttons()` 一起）、
`_setup_fav_tree()` 尾巴（那时收藏才读进来）、`_toggle_favorite()` 尾巴（收藏状态变了）。
两组的漏挂症状不一样：漏了 `_set_view` 那一挂是"列表不刷新"，
漏了这组是"按钮显示的和实际状态对不上"（比如换到没收藏的目录，星星还亮着）。
连带一条：`_setup_fav_tree()` 排在 `_setup_file_tree()` 之后，所以 `refresh_file_tree()` 里那次
调用发生时 `_favorites` 还是空的 —— 没关系，尾巴那次会补正。

**⑯ 加第三个按钮会把头部那一行挤到"刚好放得下"。**
实测（`_tmp_shot.gd` 打的，见 §2 末尾的留存目录）：侧边栏 273 px =
标题 65 + 新建文件 72 + 新建文件夹 88 + 星星 36 + 间隔 12。
**一分不剩**。再往这排加东西之前先看这组数字；标题是唯一带 `expand` 标志的那个，
所以再怎么挤也是先牺牲它（文字被裁），三个按钮的宽度不受影响 —— 退化方向是安全的。

### 7.18 导航（上一级 / 前进）—— 实测出来的边界

功能：左侧 `Button3` / `Button4` 两颗按钮（§3 那张表）。「上一级」把树根换成当前目录的
父目录，「前进」沿 `_nav_forward` 回到你按「上一级」之前待的地方。

**① `_parent_dir_of()` 里那两条判断的顺序不能换，而且不能只靠"存在性"检查。**
下面这张表是**实测**的（Godot 4.7.2 / Windows，`game_eval` 直接问引擎）：

| `dir` | `dir.get_base_dir()` | `DirAccess.dir_exists_absolute()` |
|---|---|---|
| `C:/Users/kldermr` | `C:/Users` | `true` |
| `C:/Users` | `C:/` | `true` |
| `C:/` | `C:/`（**是它自己**） | `true` |
| `C:` | `""` | **`true`** ⚠️ |
| `/` | `/`（**是它自己**） | `false` |
| `""` | `""` | **`true`** ⚠️ |

两个反直觉的地方：
- **`C:/` 不会退化成 `C:`** —— 它老老实实返回 `C:/`。所以"到顶"这件事在 `C:/` 上是靠
  `parent == dir` 判出来的，不是靠空串。
- **`dir_exists_absolute("")` 返回 `true`**。所以**不能**写成"算出父目录 → 检查它存在"，
  空串会被放过去，按钮就永远不禁用、点一下还切到空路径。必须先判
  `parent == "" or parent == dir`，**再**去查存在性。

顺带一条没那么要紧的：`_normalize_path("C:/")` 是 `"C:"`（它会把长度 >1 的结尾斜杠去掉），
所以 `root_dir` 最后会停在 `"C:"` 而不是 `"C:/"`。**这个不用改** —— 实测
`DirAccess.open("C:")` 和 `open("C:/")` 在这台机器上列出来的是同一批条目（都是盘符根），
而且 `set_root_dir()` 一直就是这么归一的，动它会波及 `_is_under()` 和 metadata 里的路径比较
（§5 那条"两边都按规范形式比较"）。知道有这回事就行。

**② `set_root_dir()` 多了个 `keep_forward` 参数，别顺手删掉。**
它默认 `false`（清空前进栈），只有「上一级 / 前进」这两个按钮传 `true`。
没有它的话，"前进"按一下就废：`_go_forward()` 从栈里弹出目标 → 调 `set_root_dir()` →
被清空 → 再按第二下时栈已经空了。**"按前进只能走一步"**就是漏了这个参数的症状。

**③ `_update_nav_buttons()` 的挂钩点是两处，不是一处。**

| 挂钩点 | 覆盖什么 |
|---|---|
| `refresh_file_tree()` | 换根、有没有目录，**以及"外部换根把前进栈清了"** |
| `_go_forward()` 尾部 | `pop` 之后可能压根没换根 —— `set_root_dir()` 撞上早退时不会调 `refresh_file_tree()` |

只挂第一处的话，"前进"会在一种情况下停在错误的可用状态上；只挂第二处的话，
OpenDir 换完根「前进」还亮着。位置和 `_update_new_buttons()` / `_update_fav_dir_button()`
一样，在 `refresh_file_tree()` 里那个"未指定目录"的**早退之前**。

**④ 收藏视图下按这两个按钮必须先 `_set_view(false)`。**
理由和 §7.17 ⑨ 里工具栏那几个动作完全一样：换根发生在藏起来的那棵树里，画面上什么都不变，
用户只会觉得"点了没反应"。这两颗按钮在收藏视图下**不隐藏**（藏起来的是头部那三个 ——
它们的语义是"对着当前打开的文件夹做点什么"，没有落脚点；而导航按钮作用于 `root_dir`，
收藏视图下照样成立）。

**⑤ 「前进」的目标可能已经不存在了。**
离开之后那个目录被删掉/移走，栈里就留了个死路径。`_go_forward()` 里用 `while` 跳过不存在的
目标，而不是直接 `set_root_dir()` —— 后者会把 `root_dir` 指到一个死路径上，
树变成"未指定目录"，看着像按钮坏了。

**⑥ 别拿 `C:/Users/xxx` 这种大目录做测试。**
以前这里记的是"`set_root_dir()` 会超时 10 秒"。懒加载（§7.19）之后**不慢了** ——
实测 `set_root_dir("C:")` 是 **1 ms、根层 18 条**。这条规矩改成**测试卫生**：
harness 要断言条目数、要逐层展开，用 §2 那种小临时目录才数得清；
拿真实盘符当夹具，断言会随着机器上装了什么而变。

### 7.19 懒加载：只建一层，展开时才填（修掉了「打开 C 盘卡死」）

以前 `_populate_dir()` 是**同步递归**扫全树的（深度上限 `MAX_TREE_DEPTH = 12`），
打开 `C:\` 会把整个盘建完 —— 几十万个条目，界面和内存一起被拖死（原 §8.7）。

现在 `_populate_dir()` 到 `for n in sub_dirs:` 那里**就停了**：每个子目录只建出它自己
那一行，里面的东西等用户点开再建。**递归就是在这儿被砍掉的**，不是靠某个开关关掉的。

### 三条主线

**① 目录条目记着"下一层建了没"。**
metadata 多一个 `loaded`（还有 `depth` —— 懒加载之后 `_populate_dir()` 不再从根一路递归下来，
每一层得自己知道有多深，`MAX_TREE_DEPTH` 那道守卫要它）。`_ensure_dir_loaded(item)` 是
**唯一**往树里填下一层的地方。

判据必须是 `loaded` 这个**位**，不能是"有没有子条目"：空目录建完也是空的，
拿子条目数当判据会让它每次点开都重扫一遍磁盘。

**② 展开有两个入口，缺一不可。**

| 入口 | 什么时候走 | 行为 |
|---|---|---|
| `_set_dir_collapsed(item, collapsed, build_now)` | 单击 / 双击 / 程序化定位 / 恢复展开状态 | `build_now = true`（程序化）同步建；`false`（鼠标点的）**不建**，靠下面那个信号 |
| `_on_file_tree_item_collapsed(item)` | 引擎自己翻 `collapsed` 时（**点箭头**）；以及上面赋值带出来的那一下 | 只处理"展开"那一半，帧末补建 |

**③ 补建必须等一帧。** 这是 `build_now` 存在的全部理由，也是这个改动里最危险的一条：

```
Tree 处理鼠标选择事件的过程中禁止建条目，硬来会是这样（实测）：
    Condition "blocked > 0" is true. Returning: nullptr
    scene/gui/tree.cpp:5614 @ create_item()
后果不止"没建出来" —— create_item 返回 null，紧跟着的 set_text 就崩在 null 上，
整个游戏进程停在断点。
```

所以鼠标点出来的展开走 `_ensure_dir_loaded_for.call_deferred(路径)`。
**传路径而不是 TreeItem**：等这一帧的工夫里树可能被整个重建过（刷新 / 换根 / 改名），
攥着一个已经释放的条目去调用会报 freed object。

> **坑中坑：这条 harness 默认验不出来。**
> §2 的 harness 用 `select()` 驱动，那是**程序化**选中，不设那个 `blocked` 计数，怎么跑都是绿的。
> 只有真的往树里发一次鼠标点击才现形。harness 里补了第 10 / 12 节，用
> `root.push_input(InputEventMouseButton)` 走真正的 `Tree.gui_input` —— 那是 harness 唯一能
> 碰到 `blocked` 那条路的方式，`_click_at()` 就是干这个的。§2 那段"第二招验不了它"的教训在这。

### 占位子条目：不是装饰，是必需的

**Tree 按"条目有没有子节点"决定画不画展开箭头**，空条目压根不画。不挂占位的话，
用户刚打开一个文件夹看到的是一**列没有任何三角的目录** —— 看着像坏了，
而且"点小三角展开"这个习惯动作根本没有落点。

所以 `_populate_dir()` 给每个新目录挂一个占位（`_add_lazy_placeholder()`），
`_ensure_dir_loaded()` 展开时 `remove_child()` + `free()` 掉换真内容。
目录真是空的话清完就没子节点了、箭头随之消失 —— 空目录本来就不该有箭头。

占位**没有 metadata**（`_item_path()` 返回空串），所以右键菜单、展开状态收集这些按路径认条目的
地方都会自动跳过它，不用到处加判断。它还是 `set_selectable(false)` 的，点不中。

**实测 A/B（harness 第 11 节，真鼠标点）**，同一个位置 `+2px`：

| | 信号 | 选中这一行？ |
|---|---|---|
| 挂着占位 | `["collapsed"]` | 否 —— 引擎自己翻的 |
| 摘掉占位 | `["collapsed", "selected"]` | **是** —— 退化成点整行 |

判据是**有没有 `selected`**：有三角时引擎自己翻、不选中；没三角时只能选中整行
（`collapsed` 两种情况下都会发，后一种是我们自己的代码翻的，别拿它当判据）。
另外整行点击在 `+15px` 以内都算三角，`+200px` 才是选中整行。

### 顺带改掉的

- **刷新保留的是"展开过的"目录**（`_collect_expanded_paths()` / `_restore_expanded_paths()`），
  和以前反过来了 —— 见 §7.5。
- **`_find_tree_item()` 拆成了 `_materialize_path()` + `_find_child_item()`。**
  懒加载下目标那一层还没建，不能按完整路径找；只能从根一层层往下走，每层手里只有名字。
  所以每往下走一层先 `_ensure_dir_loaded(parent)`，**顺序不能反**。
- **`_ensure_dir_loaded()` 里没有 `clear_children()` 这个方法。** TreeItem 只有
  `remove_child()`，而且它**不负责释放**（4.7 文档原话："This does not free the TreeItem"），
  得自己补 `free()`，不然每展开一个目录就漏一个 Object。

### 别改回去的地方

- **`_set_dir_collapsed(build_now = false)` 里不要自己再 `call_deferred` 一次。** 赋值
  `collapsed` 就会发 `item_collapsed`，那个信号会去排；自己再排一遍就是每展开一次多跑一趟
  `_materialize_path`（无害但白费）。
- **`_on_file_tree_item_collapsed()` 里"只处理展开那一半"的判断不能删。** `_populate_dir()`
  给每个新建的目录条目设 `collapsed = true` 也会发这个信号 —— 不挡的话一建树就把整棵树全展开了。
- **占位和 `collapsed = true` 的先后不能反**：先设 `collapsed` 再挂占位，挂上去时才是折着的。

### 7.20 预览面板 —— 实测出来的十二条

#### ① 字号要铺满**五个**主题项；而且项目里没有任何字体文件

`RichTextLabel` 的字号不是一个属性，是**五个各带默认值的独立主题项**：

```
normal_font_size  bold_font_size  italics_font_size  bold_italics_font_size  mono_font_size
```

只改 `normal_font_size` 的话，**加粗标题会停在默认字号**——把正文调到 24，一级标题
反而比正文小。`_apply_preview_font_size()` 里那个循环遍历的就是这五个。
（`line_separation` 是主题**常量**不是字号项，走 `add_theme_constant_override`，别混。）
行距 = `round(字号 × 比例)`，比例随模式走（小说 0.55、Markdown 0.30）。

同一个坑的另一面：**这个项目里一个字体文件都没有**（`resource/folder.tres` 只有一行
`TextEdit/font_sizes/font_size = 20`）。所以 `[code]` **换不出等宽字体** —— 代码块和正文
用的是同一套字，只差字体大小。代码块因此只能靠**底色 + 颜色**跟正文区分
（`CODE_BG = #1e2124`）。这是取舍不是 bug：要真等宽就得往项目里塞一个字体文件，
那会让导出的包变大，而且正文的中文字体也得跟着挑。

#### ② 两个预览共用一个 viewer 文件

`scene/Previewer/` 下面只有**一个** `MobileNovelReader.tscn`
（`VBoxContainer → ScrollContainer → RichTextLabel`），两种模式都用它。
原本还打算给 Markdown 单独建一个 `MarkdownPreview.tscn`，写完发现两个文件的树会**逐字节相同** ——
两种模式的差别只在于**调哪个纯函数生成字符串**。
那个文件后来确实建出来了，但一直是**只有一个 `VBoxContainer`、零子节点的空壳**，
已于本次一并 `git rm`（它唯一还活着的地方是 `.godot/editor/editor_layout.cfg` 的
"最近打开的场景"记录，那不算引用）。留两个就是两份要同步的状态：
字号要应用两遍、切模式时滚动位置会在两个 RTL 之间丢。多出来的那份还会踩 §3 里
"死的文件"的定义。

**代价**：文件名带 `Novel` 却也在渲染 Markdown。将来要改名就是 `main.tscn` 里
一行 `ext_resource path=` 的事。

#### ③ 手动覆盖**越不过**"非 txt/md 一律收起"；而"没打开文件"是另一回事

`_effective_preview_mode()` 的顺序本身就是需求：

```gdscript
var auto := _resolve_preview_mode(current_file_path)
if auto == PreviewMode.NONE:
    return PreviewMode.NONE      # ← 手动覆盖在这里被拦住
```

自动判出 `NONE` 就**一律 `NONE`**。这条是"非预览文件收起右栏"的绝对保证 ——
被强制按文本打开的 `.docx` 不会因为用户上次手动选了 Markdown 就把一屏乱码排进阅读器。

但有个相邻的路必须**分开**判：**"没打开任何文件" ≠ "打开了不可预览的文件"**。
第一版把两者都判成"收起"，后果有两个：

1. 启动时右栏凭空消失（和改动前不一样，是外观回退）；
2. 工具栏那颗 Preview 按钮变成**死键** —— 模式恒为 `NONE`，栏既开不出来也关不掉。

所以拆成两个函数，它们对这两种输入给出**不同**答案：

| | `_effective_preview_mode()`（渲染成什么） | `_should_show_preview_rail()`（栏在不在） |
|---|---|---|
| 没打开文件 | `NONE` | **`true`**（空壳，但要看得见、开得掉） |
| 打开了 `.py` | `NONE` | `false`（收起） |

配套的还有那条防抖闸门：`_on_preview_text_changed()` 里判的是**模式**，不是
`preview_rail.visible` —— 在"没文件、栏是空壳"那个状态下 `visible` 是 `true`，
按可见性判的话随手敲几个字就会把内容排进一个本该空着的栏里。

#### ④ 隐藏 SplitContainer 的子节点会让 `split_offsets` **重排下标**（这是设计里最大的未知点）

需求要求"非预览文件把整个右栏收起来、宽度还给编辑器"。做法是
`preview_rail.visible = false` —— `SpC` 的第三个子节点不可见，剩下的两个重新分宽度。

**文档没写死**隐藏子节点之后 `split_offsets` 会怎么样，所以这是唯一可能推翻设计的地方，
第一个测的就是它。实测结论（1920 宽的窗口，`separation = 12`）：

| | `split_offsets` | 布局 |
|---|---|---|
| 三栏全在 | `[221, -274]` | `221 + 12 + 1401 + 12 + 274 = 1920` |
| 右栏隐藏 | **`[221]`** | `221 + 12 + 1687 = 1920` |

**下标真的重排了** —— 偏移表从两项缩成一项。所以"收起前 `duplicate()` 存一份、
显示时原样写回"那一对**是承重的，不是保险**：不存的话重新显示时 `split_offsets`
只剩一项，右栏宽度会变成一个凑出来的默认值。

另外注意编辑器吃下的是**右栏 274 + 分隔条 12 = 286**，不是 274。按 274 断言的话
测试会莫名其妙地红（我第一版就是这么红的）。

收尾补一句 `queue_sort()`，和 `_set_view()` 同理由。万一哪天这条路走不通，
退路是把右栏的 `custom_minimum_size.x` 设 0 再把 `split_offsets[1]` 推到 0。

#### ⑤ `fit_content = true` 是承重的；滚动位置在外层 ScrollContainer 上

`RichTextLabel` 上必须开着 `fit_content = true`。`ScrollContainer` 算滚动范围看的是
子节点的 `get_combined_minimum_size()`，而 RTL 默认不按内容撑高 —— **不开的话滚动条
怎么调都没反应**，内容会被裁掉。配套的还有 `scroll_active = false`
（不然 RTL 自己把滚轮吃掉，外层收不到）。

滚动位置因此落在**外层 `ScrollContainer`** 上（`fit_content` 让 RTL 正好和内容等高，
RTL 自己没有可滚的余量）。而 `rtl.text = bb` 会把滚动复位，所以 `_render_preview()`
里存 `scroll_vertical`、赋值后用 `set_deferred` 写回。不保的话，在长文末尾打字时
视图会**一路跳回顶部**——这是这类"重排"功能最典型的坏症状。

#### ⑥ `TextEdit.text_changed` **只在用户输入时发**，程序化 `.text =` 不发

写 harness 时在这条上耗掉了一整轮：`text_edit.text = "..."` 之后等了 40 帧，
防抖 Timer 一次都没启动过。`text_changed` 的语义是"**用户**改了文本"，程序化赋值
（包括 `open_and_show()` 里读文件那次）**不发**这个信号。

两个后果：

- **好事**：`open_and_show()` 不需要额外的抑制标志去防"载入文件时触发一次重排"，
  引擎已经帮我们挡了。
- **坑**：harness 里**没法**靠给 `.text` 赋值来验防抖。要么直接调
  `_on_preview_text_changed()` 走闸门逻辑、要么**真的往输入管线里灌按键**。
  后者在 live 编辑器里是可行的：`Input.parse_input_event()` 灌一个 `InputEventKey`
  进去，5 次击键 → `text_changed` 发了 5 次 —— 那样才是**真的**在验这条路。

  （`game_manage` 的 `input_key` 实测**到不了** `TextEdit`，得用
  `game_eval` 里调 `Input.parse_input_event()`。）

#### ⑦ RichTextLabel 对**不存在的标签**不报错，直接当字面量画出来

这条决定了该怎么验预览。两个实测结论：

- **不存在的标签静默变成可见文本。** 我一度想用 `[codeblock]` 来排代码块 ——
  **4.7 里没有这个标签**（那是 RichTextEffect / 插件生态里常见的东西，不是内置的）。
  写进去不报错、不警告，用户看到的是一屏字面的 `[codeblock]`。
  这一轮实际可用的标签是这些：
  `[b] [i] [s] [u] [code] [font_size=N] [color=] [bgcolor=] [indent] [ul] [ol type=1] [url=] [center] [hr] [lb] [rb]`。

- **不支持交叉嵌套，只支持严格嵌套。** `[b]a[i]b[/b]c[/i]` 这种会错乱。
  所以 `MarkdownToBbcode` 的**递归**行内扫描器不只是为了好写：
  递归天然产出严格嵌套的串，串 regex 替换（`**粗**` 和 `*斜*` 互相咬）产不出。

因此**验证预览不能只看"没报错"**，得看 `get_parsed_text()`（拿到的是**可见文本**）——
字面量残留、标签没闭合、编了个不存在的标签，全都在那里面现形。
这是第一张网。第二张网是 `logs_read(source="game")`，RichTextLabel 对能识别的
结构问题（比如闭合不配对）会推警告，跑一遍日志里必须是干净的。

#### ⑧ 跳转用 `get_paragraph_offset()`，**不要**自己估算折行

目录跳转的全部实现就一行：

```gdscript
sc.set_deferred("scroll_vertical", int(rtl.get_paragraph_offset(p)))
```

`get_paragraph_offset(k)` 返回第 k 段的垂直像素偏移，而且**跟随折行**：同一个文档，
宽度 274→160 时第 3 段的偏移从 **595 变成 1094**。它还**不依赖 `fit_content`**
（`true`/`false` 下值都是 595，实测）。

三条**先用探针证伪、再也没必要走**的路：

- ❌ **`scroll_to_paragraph()`**：预览的 RTL 是 `fit_content = true` + `scroll_active = false`，
  高度正好等于内容高度、自身滚动余量为 0，在这套结构上调它是**空转**。实测把它放到
  `scroll_active = true` + `fit_content = false` + 滚动范围已放开的情况下，`scroll_to_paragraph(3)`
  之后 value **立刻读是 0、等 4 帧后还是 0** —— 不是"需要等帧"，是这条路根本不存在。
- ❌ **按字体度量自己累加折行**：不需要了。顺带记一句备查：`get_theme_font("normal_font")`
  名字是**对的**（拿到 `Open Sans SemiBold`），真要走估算也不是死路。
- ✅ **`get_paragraph_count()` == 输出 BBCode 的行数**（一个 `\n` 一个段落），
  所以转换器里"标题在输出串的第几行"可以直接当段落号用，不需要任何换算。

⚠️ 但**仍然必须 `set_deferred`**：`text` 刚换掉时 `ScrollContainer` 的滚动上限还是旧文本的
高度，直接写会被按旧上限夹一次。另外 Y 要在**最终宽度确定之后**读 —— 这正是它跟随折行的代价。

#### ⑨ 阅读宽度：`ScrollContainer` 的 min 宽 + 居中，**零场景改动**

定宽 = `size_flags_horizontal = SIZE_SHRINK_CENTER(4)` + `custom_minimum_size.x = w`。

- ⚠️ **`SC` 的 `min.x` 默认只有 1**（实测 `RTL.min = (1, 5)`）。所以这两条**必须成对**设：
  单设居中会把 `SC` 塌成 1px 宽，而且**不报错**。定宽 160 时实测
  `SC.size.x = 160 / min.x = 160 / RTL.size.x = 152` —— 差的 8px 是竖滚动条，
  即"页宽 180"实际给正文 ~172px。
- **不去插节点**，两个候选方案都是**静默**坏掉：
  - 在 `SC` 和 `RTL` **之间**插一层 → `preview_rtl.get_parent() as ScrollContainer` 会拿到
    **null**（`as` 失败返回 null，不抛错），滚动保活当场失效，症状正是 ⑤ 那条"长文末尾
    打字视图跳回顶部"。
  - 在 `SC` **上面**插 `CenterContainer` / 直接改 `preview_rail.custom_minimum_size.x` →
    min size 向上传播，和 `split_offsets` 的存/恢复（④）反复打架，窗口变窄时还会形成拉锯。
- **档位必须是绝对像素、且 ≤ 右栏宽度（274）**：按字号推导的话，274px 的栏里绝大多数档位
  会 clamp 到同一个值、看着像功能坏了。
- **"名义值"和"应用值"要分开**：`custom_minimum_size.x` 会向上传播成 `preview_rail` 的 min size。
  持久化的是**名义值** `_preview_page_width`，实际写入的是 `min(名义值, preview_split.size.x)`
  —— 这个 clamp **不写回**名义值，否则用户把分隔条拖窄一次就把自己选的页宽永久改掉了。
  宽度一律从 `preview_split.size.x` 派生，**不读 `preview_rail.size.x`**（那正是会被自己的
  min 宽影响的那个值）。
- **两条不要碰**：`preview_split.split_offsets`（那是用户拖分隔条的结果，④ 的存/恢复会整份
  `duplicate()` 覆盖掉你写进去的）；`preview_rail.custom_minimum_size.x`（同上打架）。

#### ⑩ 阅读主题：**两处真源必须同时改**（这是最容易做半截的一处）

`[color=...]` 的优先级**高于** RTL 的主题项 `default_color`。而 `MarkdownToBbcode` 把 8 个颜色
**直接拼进了输出串**（共 10 处输出行：代码块底色 `L109`、`[hr]` 的 `L122`、标题 `L132`、
行内代码的底色+字色 `L279`、图片 alt 的灰 `L294`、链接 `L311/L364/L369`、不可点链接目标的灰
`L366`、引用 `L585`）。加上 `TextToBbcode` 的分隔线色和 `main.gd` 里那句「文件太长」的灰，
同一个色值散过**三份**。

→ 只调 `add_theme_color_override("default_color", ...)` 的话，**上面 10 处一处都不会变**，
只有没被 `[color]` 包住的正文会变 —— 看着像"主题只生效了一半"。

解法是 `scene/Previewer/PreviewTheme.gd` 当**单一真源**，同时提供两条路：
`apply_to(rtl, theme)`（节点主题项）和 `retint(bb, theme)`（输出串换色）。

- **`retint` 为什么安全**（这是它能成立的前提）：两个转换器的 `_escape()` 把文档内容里
  **每一个** `[` 都换成了 `[lb]`，所以成品串里凡是 `[color=` 开头的地方，都只可能是转换器
  自己吐出来的。截取的是**完整标签形式**（`[color=#7aa2f7]`），**不替换裸色值** ——
  否则代码块里恰好写着这个 hex 就会被误染。
- **`DEFAULT` 主题必须原样返回**（`retint` 直接 early-return）：这样"默认外观逐字节等于
  改动前"是**结构性保证**，不是靠人肉核对色值有没有写错。
- ⚠️ **`DEFAULT` 的 `sel` / `sel_text` 必须是 `Color` 而不是 hex**。内建值是
  `selection_color = (0.1, 0.1, 1.0, 0.8)`、`font_selected_color = (0, 0, 0, 0)`，
  而 `0.1` 写成 hex 只能得到 `#1a`（26/255 ≈ 0.10196 ≠ 0.1）—— 于是"默认主题零变化"
  会**差在最后一位**，而 `Color == Color` 是逐浮点比较。第一版就是照"更合理"的直觉写成
  `#4a5a7a` / `#ffffff` 的，那等于**把默认外观改了**。harness 里钉着三条逐值比较。
- ⚠️ **`apply_to()` 对 `DEFAULT` 也要显式跑一遍**，不能 early-return：用户从"夜间"切回
  "默认"时，必须把上一套覆盖**清掉**（尤其是背景 `StyleBox`，留着会盖住底图）。
- **主题够不到的地方**：目录树和工具栏按钮不是 `RichTextLabel`，吃不到 `default_color`，
  本次有意保持原样。

#### ⑪ `PopupMenu` 的 `add_separator()` 给的是**字面量 -1**，不是自动 id

`add_item(label, -1)` 会把 -1 换算成"当前条目数"，但 **`add_separator()` 不会** ——
它的 id 就是 `-1`（实测三个分隔线全是 `-1`，多个分隔线会互相"重复 id"）。

所以菜单 id 的编解码（`READING_ID_*` 那组常量 + `_reading_is_current()` +
`_on_preview_reading_id_pressed()`）里：

- **组标题**用保留 id `READING_ID_HEADER = -2`，**不能图省事用 `add_item(label)` 的自动 id**
  —— 自动 id 从 **0** 开始，正好撞上"行距"段的 0 号档；而组标题是 disabled 的，
  **撞了既不报错也点不动**，只会在打勾时拿标题的 id 去索引档位表。
  取 -2 而不是 -1：-1 是 `add_item` 的"请自动分配"哨兵值。
- **分隔线**在打勾时要 `is_item_separator(i)` 跳过；处理器里靠 `if id < 0: return` 兜住。
- **`_sync_preview_menu_checks()` 必须三个菜单各认各的**。它原来是"mode 菜单 early-return，
  其余一律当字号菜单"——加第三个菜单后，阅读菜单的 id `0..4` 会被拿去索引
  `PREVIEW_FONT_SIZES` **打错勾**，id `≥9`（比如行距档 12）直接**下标越界报错**。
  最后一个分支才是字号，并且带上下界检查。

#### ⑫ 阅读偏好走 `DSettingsManager`，**加载是 deferred 的，必须跟着 deferred**

五项可调 + 字号 + 手动预览模式**全部持久化**，落在 `user://der_settings.tres`
（`DSettingsManager`）。这个选择本身是重要的：阅读偏好语义上是**设置**不是**存档进度**，
走存档会刷 `last_modified_timestamp`、污染收藏夹的"最近修改"排序。

**这一个时序坑值得单独记**：`der_settings.gd::_ready()` 里是
`call_deferred("_send_ready_message")` → `call_deferred("_load_or_create")`，
**`_setup_preview()` 里同步读 `DSettingsManager.settings` 必然拿到 `null`**
（read 侧还没跑，deferred 队列要等主场景 `_ready()` 跑完才 flush）。
所以读侧也 `call_deferred("_load_reading_settings")` —— 塞进同一条 FIFO，
排在 `_load_or_create` 后面，顺序由引擎保证。

两个**不能靠信号兜底**的理由：

- `_load_or_create()` 在**首启动**（文件不存在）时会走 `save_settings()` 并发
  `settings_changed`；**文件已存在时则不发**。发不发取决于文件在不在，不能拿它当加载完成的通知。
- 读侧的最后一步**必须**是"完整重渲染"（`_apply_preview_font_size()` + `_update_preview()`）。
  少了这步，持久化的值**永远不会生效** —— 不是"第一帧用默认值"那么轻，是**永久**。

**反面教材在 addon 自己身上**：`DSettings/scene/control/language_item_button.gd` 的
`_pressed()` 只改字段、**没调 `save_settings()`** —— 语言选择其实不落盘。别照抄那个形状。

#### ⑬ 翻页模式：`SCROLL_MODE_SHOW_NEVER` + 按页写 `scroll_vertical`

翻页是**纯表现层**的：同一份 BBCode，换个滚法。所以 `scene/Previewer/*.gd` 一行没改，
两个 `.tscn` 一行没改，页码条是在 `_setup_preview()` 里用代码建的
（`MobileNovelReader` 的子节点，**不是** `SC` 和 `RTL` 之间 —— 那是 §7.20 ⑤ 的红线）。

- **`SHOW_NEVER` 是"能滚但不画滚条"**（`SCROLL_MODE_DISABLED` 才是关掉滚动，不能用）。
  `scroll_vertical` 仍然可写可读，所以现有的两处滚动保活逻辑原样有效。
  `get_v_scroll_bar()` 返回的是引擎内部节点，**只能藏不能删**（文档明说 free 它会崩），
  所以一律走 `vertical_scroll_mode`，绝不 `queue_free()` 那个 bar。
- ⚠️ **切换会改折行，分页表必须在切换之后重算**：藏掉滚条后 `RTL` 宽出**正好 8px**
  （滚条原来的位置），同一份文档的内容高从 356000 掉到 323669。**在切换前算的表是废的。**
  这条也是"别被单一读数骗到"的现场：`AUTO` 和 `SHOW_NEVER` 的
  `get_v_scroll_bar().max_value` 不一样，看着像 `SHOW_NEVER` 收缩了滚动范围，
  其实那个差值**正好就是重新折行的高度差** —— 两个配置的 RTL 宽度本来就差 8px，
  不是同一个基准。要归因就得把两个变量分离开测。
- **页首对齐到段落起点，宁可重复一段、绝不切断一行**。纯按屏高切会把一行字拦腰切开，
  页首半行 —— 那不是翻页，是跳着滚。走查用一次前进式扫描，O(段落数)：
  `cand > cur` 是显式护栏（严格递增），单段高于整页时落到 `cur + h` 兜底仍然前进一屏，
  回退量 ≤ 一个段高而前进量 ≥ `h - 段高`，所以**一定收敛**。
  别"优化"成 `next = cur + h`，那就又切半行了。
  实测 12 万字符（`PREVIEW_MAX_CHARS` 上限）→ 5958 段落 / 1192 页，
  走查本身 **10.19ms**（同一份文档排版要 1092ms）。
- **`_page_index` 是权威页码，绝不从 `scroll_vertical` 反推**：**末页页首
  861490 > 可滚上限 861057**，引擎会把 `scroll_vertical` 夹回上限，
  反推会算出 `index - 1`，症状是"在第 16 页按下一页，页码跳到 15"。
  只在表重建时用 `_page_index_for(scroll_vertical)` 认一次。
- **分页表惰性重算，且只置脏不每帧算**：`SC.resized` 只 `_invalidate_pages()` +
  `_queue_page_refresh()`。拖分隔条会连发 `resized`，每帧跑一遍全篇走查会把拖动拖卡。
- **输入全走 `preview_rtl.gui_input`**：默认（滚动）模式下处理器直接 early-return
  且**不 accept**，滚轮照旧落到外层 `SC`，行为一个字不变。翻页模式下
  `accept_event()` 能挡住祖先 `SC`（已实测：不 accept 时外层 0 → 108，accept 后 0 → 0），
  前提 `rtl.mouse_filter == STOP`。8px 位移阈值用来分"点击"和"拖拽选字"。
- ⚠️ **链接护栏只能"先记下、延后一步再决定"**，两个看起来更自然的写法都是死的：
  - `RichTextLabel.is_meta_hovered()` **在 4.7 里不存在**；把 meta 方法全列出来，
    没有任何一个能回答"鼠标下的字是不是链接"；
  - 鼠标**精确落在链接上**时 `meta_hover_started/ended` **一次都不发**。
  实测事件次序是 `["gui_input:press", "gui_input:release", "meta_clicked", "deferred"]`
  —— `meta_clicked` 排在 **`gui_input` 之后**（不是直觉上的之前）。所以"`meta_clicked`
  置标志、点击处理器读标志"这种写法护栏**永远失效**，而且**不报错**：
  症状是"点链接既开浏览器又翻一页"。
  实际做法是抬手时不立刻翻，把方向登记下来 `call_deferred` 出去，
  到那一步再看 `_preview_meta_clicked_frame`（由**已有的**外链处理器置位）。
  `deferred` 排在 `meta_clicked` 之后，所以这一步一定看得到本次点击的结果。
- ⚠️ **`◀`/`▶` 不能用，用 `«`/`»`**：项目里一个字体文件都没有（走内建 Open Sans），
  逐字实测 `◀ ▶ ▲ ▼ ← → ▏ ★ ※` **全部无字形**（连兜底字体也没有）→ 一定渲染成豆腐块；
  有的是 `› « »`。`◀` 是最自然的写法，也是**一定会坏**的写法 ——
  项目没有字体文件这件事，只有真去问 `font.has_char()` 才会发现。
- 页码条和工具栏一样**不是 `RichTextLabel`**，吃不到 `default_color`（同 §9 那条）。

---

## 8. 已知问题

### 8.1 Ctrl+Shift+S 会先原地保存一次（已验证）

`_input()` 里两个 `if` 是并列的，不是 `elif`：

- 第一个判断"Ctrl+S"时写的是 `event.keycode == KEY_S and ... Input.is_key_pressed(KEY_CTRL)`，**它没排除 Shift**；
- 所以按 Ctrl+Shift+S 时第一个分支也成立，`save_file()` 先执行，然后才弹另存为对话框。

实测确认：按完之后磁盘上的文件内容**已经被改写了**。

平时的后果是"多写一次同样的内容"，无害；但如果在**没有打开任何文件**的状态下按，会先弹一个阻塞的「没有打开任何文件」提示框——这个比较烦人。修法是在第一个条件里加上 `and not Input.is_key_pressed(KEY_SHIFT)`。

### 8.2 强制按文本打开后 Ctrl+S 会损坏原文件

双击 `.docx` 打开后，`current_file_path` 指向那个 docx，此时 Ctrl+S 会用编辑器里的乱码**覆盖原文件**，不可逆。

打开前的提醒框已经把这个风险讲清楚了，**没有做硬拦截**——理由是 `.toml` / `.env` 这类文件本来就要能正常保存，硬拦会让它们每次保存都被问一遍。

如果想加兜底，可以在 `save_file()` 里判断当前文件不在白名单时改成弹确认框（「另存为」不受限）。

### 8.3 没有编码处理

`open_and_show()` 用的是 `FileAccess.get_as_text()`，非 UTF-8 的文件（比如 GBK 编码的中文 txt）会显示成乱码，保存回去会把原编码也改掉。没做编码检测。

### 8.4 大文件会卡

整个文件一次读进 `TextEdit`，没有分块或虚拟滚动。几 MB 的文件就会明显卡顿。

### 8.5 每收藏一次都会弹一条「存档保存成功」

收藏走的是框架的 `DSaveManager.save_cur_res()`，而它内部还会弹一条顶部提示、
顺手更新 `last_modified_timestamp`（详见 §7.17 ⑫）。功能没问题，只是有点吵 ——
这是"复用框架现成的存档接口"换来的，不是 bug。

### 8.6 收藏列表里长路径看不全

条目文本是 `文件名 — 父目录名`，完整路径在 tooltip 里。侧边栏默认只有 300 像素，
写完整路径也只会被 Tree 从右边裁成前缀，所以选了"只看父目录名"。
想要更多信息可以拖宽侧边栏（拖宽不会让文本变长，得改 `refresh_fav_tree()` 里的拼法）。

### 8.7 打开大目录会卡住整个界面 —— **已修**（改成懒加载，见 §7.19）

原来的症状：`_populate_dir()` 是**同步递归**的（深度上限 `MAX_TREE_DEPTH = 12`），
`set_root_dir()` 会一直阻塞到整棵树建完。实测对 `C:/Users/kldermr`（用户主目录，
里面有 `AppData`、`Documents` 这些）调一次，`game_eval` **10 秒内没有返回**，
日志里没有任何报错 —— 是慢，不是崩。

这个毛病在加「上一级」之前就有（OpenDir 到任何一个大目录都会触发），但「上一级」让它更容易撞上：
从深层目录一路往上点，随时会经过一个巨大的目录 —— 用户报的就是"打开 C 盘、或者按上一级回到
C 盘，编辑器卡死"。

**现在**：`_populate_dir()` 只建一层，子目录展开时才填。实测同一件事：

| | 实测 |
|---|---|
| `set_root_dir("C:")` | **1 ms**，根层 **18 条**（= `C:\` 的真实顶层条目数），整棵树真条目数 == 根层真条目数 |
| 从 `page` 目录按「上一级」一下下点到 `C:` | 3 下，单次最慢 **13 ms**，到顶后按钮自动禁用 |
| 到 C 盘之后树的状态 | 仍然只建了一层，没有任何目录被展开 |

代价（这是设计取舍，不是漏做）：**打开一个项目文件夹不再自动展开全部，得逐层点**，
而且"记住折叠状态"逻辑反了过来（改成记住**展开过的**目录，见 §7.5）。
换来的是打开任何目录都是常数开销。

harness 里第 8 / 12 节就钉着这两个数（`_tmp_verify.gd`，见 §2）。

**下一个会撞上的类似问题在 §8.4**（大文件整篇读进 `TextEdit`）—— 同一个形状的坑，
只是换成了文件内容而不是目录树。

---

## 9. 明确没做的（别以为是漏了）

- 在**空白处**右键弹菜单（现在只有对着条目右键才有菜单）。头部那三个按钮算是部分替代 ——
  它们打在**当前打开的文件夹**里（见 §6），但"在某个空白位置右键、把目标目录定在那儿"还是没有
- 收藏的排序 / 拖拽调整顺序 / 分组 —— 顺序就是收藏的先后，不能改
- 收藏列表里新建文件、重命名、删除（只做了「取消收藏」+「在文件管理器中打开」，理由见 §7.17 ⑦）
- 收藏按钮上的数量角标、收藏的导入导出
- 新建时选扩展名（现在固定 `.txt`；想建 `.md` / `.json` 只能在弹框里把后缀改掉）
- 在选中目录打开终端
- 永久删除——只有回收站一条路（`OS.move_to_trash`）
- 多选批量操作
- 查找 / 替换、撤销栈以外的编辑增强
- 设置窗口（UI 建好了，按钮是隐藏的）
- 标签页 / 多文件同时打开——**同时只有一个文件**
- 预览相关的这几个（都是有意砍的，不是漏了）：
  - txt 的**阅读进度**（"读到第几章 / 百分之多少"）——**章节识别和目录已经做了**（见 §6），
    进度条没做。当初这里是"不做解析、不分章"一句写死的，那条取舍已经**推翻**了
  - 章节识别的**完全准确**：只用启发式（`第` + 数字 + `章节回卷部篇集` + 一张固定词表）。
    已知会误判整行恰好以章节形式开头的正文句子（`第一章就写完了`），**这是有意的**——
    收紧边界检查会把 `第一章初见` 这类网文常态标题成片漏掉，见 `TextToBbcode.chapter_of()` 的注释
  - 目录里的**搜索 / 跳到指定章 / 拖拽排序**，目录也不显示章号（就是原文那行）
  - Markdown 的 **setext 标题**（`===` 下划线那种）、**表格**、**HTML 块**、**脚注**、**引用式链接**（`[x][1]` + `[1]: url`）
  - **嵌套列表**：`- a` / `  - b` 用 `[indent]` + 换字形表达层级，**不用嵌套 `[ul]`**（RichTextLabel 的列表块不能可靠嵌套）。也因此 `* * *` 这类整行分隔符在 Markdown 里必须是"整行 3 个以上同类标记"才认，否则和列表项咬
  - **`.markdown` 扩展名不认**（只认 `.md`；要加就是 `PREVIEW_EXT_MODE` 里一个键）
  - 阅读主题**只作用于正文区域**：目录树、工具栏按钮和翻页模式的页码条都不是
    `RichTextLabel`，吃不到 `default_color`，本次有意让它们保持原样（别当 bug 报）
  - **代码块没有真正的等宽字体**：项目里一个字体文件都没有，`[code]` 换不出等宽，代码块只能靠**底色 + 颜色**和正文区分（§7.20 ①）
  - 预览与编辑器之间**没有双向定位**（点预览里的链接能开浏览器，但不开编辑器里的对应行）
  - **翻页模式没有键盘快捷键**（PageUp/PageDown、左右方向键一律不做）。理由是
    `_input()`（`main.gd:381`）跑在 GUI 分发**之前**、且拿不到焦点信息，
    要在那里接翻页键就必须和编辑区 `TextEdit` 抢按键（TextEdit 独占焦点）。
    不做，这条冲突就不存在 —— 翻页只有鼠标滚轮、左右半屏点击、`«`/`»` 三个入口。

---

## 10. 快捷键与状态

| 键 | 作用 |
|---|---|
| `Ctrl+S` | 保存（原地覆盖 `current_file_path`） |
| `Ctrl+Shift+S` | 另存为（**注意 8.1**） |
| `Ctrl+O` | 打开文件。对话框过滤 `*.txt *.json *.csv` |
| `F11` | 专注模式（藏起上下两条工具栏） |
| `Ctrl` + `=` / `-` | 字号增减（按住会连续变化），也可以 `Ctrl` + 滚轮 |
| `Ctrl+M` | 开关 TextEdit 的小地图 |
| 左侧竖排 tooltip `Explorer` | 切回 **Explorer**（文件树）视图 |
| 左侧竖排 tooltip `前往上一级文件夹` | 树根切到当前目录的上一级。**没有上一级时禁用**（没开目录 / 已经到盘符根） |
| 左侧竖排 tooltip `前进（…）` | 沿导航历史回到按「上一级」之前所在的目录。**没得回时禁用**。任何其他换根方式都会清空这段历史（见 §5 / §7.18） |
| 左侧竖排 tooltip `Stars` | 切到 **收藏** 视图 |
| 「Explorer」标题右边的星星按钮 | **收藏 / 取消收藏当前文件夹**（开关，见 §6 / §7.17 ⑬⑭）。没打开文件夹时禁用 |

输入动作定义在 `project.godot` 的 `[input]` 段：`ui_save` `f11` `zoom_up` `zoom_down` `map`。

窗口启动即最大化（`display/window/size/mode=2`）。`run/max_fps=144`，物理引擎设成了 `Dummy`（这不是游戏，物理没意义）。

底部状态栏左侧的字符数由 `_process()` **每帧**刷新——所以别指望往 `Label3` 上挂临时提示，会被覆盖掉。
