# FolderDerTextEditor

一个用 Godot 做的**纯文本编辑器**：左边是文件夹树，右边是编辑区。定位很明确——不追求做 VS Code，只求打开快、能顺着目录翻文件、能改能存。

- 引擎：**Godot 4.7**（`GL Compatibility` 渲染后端）
- 语言：纯 GDScript，没有 C#
- 平台：Windows（`export_presets.cfg` 只有 Windows Desktop 一项）
- 体量：业务代码就是 `page/main.tscn` + `page/main.gd`（约 970 行，其中不小一部分是解释性注释）。
  另有一个框架 addon `addons/der_framework` 注册了 4 个 autoload，但本应用只用到其中
  一个顶部提示接口（见第 3 节）

---

## 1. 跑起来

本机 PATH 上没有 `godot`，引擎在：

```
C:/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe
```

```bash
# 直接运行
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" --path /c/godotProject/folder-der-txtEditor

# 用编辑器打开
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" -e --path /c/godotProject/folder-der-txtEditor
```

导出配置已经写好，产物固定落在项目外的 `../../app/FolderDerTextEditor.exe`。

---

## 2. 改完代码怎么验证（**新接手的人先看这节**）

没有 CI、没有单元测试框架。这个项目的验证靠两招：

### 第一招：语法检查（秒级，先跑这个）

```bash
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" \
  --headless --path /c/godotProject/folder-der-txtEditor \
  --check-only --script res://page/main.gd
```

**⚠️ 这条命令对 `main.gd` 永远返回 1，不代表你的代码有问题。**
`--check-only` 模式下 autoload 不会注册，所以它必定先报这一条：

```
SCRIPT ERROR: Compile Error: Identifier not found: DMessageManager
```

（`DMessageManager` 是 `addons/der_framework` 注册的 autoload，见第 3 节。）

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

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene = load("res://page/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame          # 必须等：_initialize() 跑在节点的 _ready() 之前，
	await process_frame          # 不等的话 @onready 的变量还是 null
	scene.set_root_dir(FIX)
	await process_frame

	# ... 这里写断言 ...
	# scene._item_path(...)、scene._is_editable_file(...) 这些私有函数可以直接调
	quit(0)
```

跑法：

```bash
timeout -k 5 90 "/c/.../Godot_v4.7-stable_win64.exe" \
  --path /c/godotProject/folder-der-txtEditor --script res://_tmp_verify.gd
```

**用完务必删掉 `_tmp_verify.gd` 和 `_tmp_verify.gd.uid`**，别留在项目里。

### 写 harness 时踩过的坑（实测，按踩到的顺序）

1. **必须带窗口跑，不要加 `--headless`。** Tree 控件在 headless 下不暴露某些崩溃——历史上那次段错误就是带窗口才复现的。
2. **stdout 被重定向/管道时是块缓冲的**，进程被 `timeout` 杀掉就一个字都不剩。每条断言都同时 `print` **并追加写一个文件**（写完立刻 `close()`），这样即使挂起也能看到跑到哪一步了。
3. **类型推断的报错很啰嗦**：`var r := tree.get_item_area_rect(...)` 会报 `Cannot infer the type`，得写成 `var r: Rect2 = ...`。凡是从引擎方法拿到的返回值，习惯性加上显式类型注解，能省掉一大堆来回。
4. **合成输入可以走完整管线**：`Input.parse_input_event()` 对鼠标点击、双击（第二下带 `double_click = true`）、键盘按修饰键都有效，能端到端验真实输入路径。
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

---

## 3. 目录结构

### 活着的文件

| 路径 | 作用 |
|---|---|
| `page/main.tscn` | 唯一的场景。整个 UI 都在这里 |
| `page/main.gd` | 唯一的脚本。全部逻辑 |
| `resource/folder.tres` | 主题，只设了 `TextEdit/font_sizes/font_size = 20` |
| `resource/new_code_highlighter.tres` | 语法高亮配色，挂在 TextEdit 的 `syntax_highlighter` 上 |
| `asset/bg/tsBgHF.png` | 编辑区的背景图（`TextureRect`） |
| `asset/icon/folder.png` | 目录图标 |
| `asset/icon/folderTxt.png` | **可编辑**文件的图标 |
| `asset/icon/UnsupportedEditIcon.png` | **不可编辑**文件的图标 |
| `asset/icon/saveIcon.png` `txtIcon.png` `folderIcon.png` | 工具栏按钮的图标 |
| `scene/SettingWin.tscn` | 设置窗口。**按钮当前是隐藏的**（见下），等于没启用 |
| `export_presets.cfg` | Windows 导出配置 |
| `addons/der_framework/` | **活着的，不是死的**。`project.godot` 里 4 个 autoload 全是它的场景：`DerMain` / `DerMessage` / `DerSave` / `DerSettings`。`main.gd` 保存成功时那行顶部提示就来自 `DMessageManager.add_top_message()`（`main.gd:182`），**这是本应用唯一用到它的地方**；另外三个 autoload 被加载着但 `main.gd` 没碰 |
| `addons/godot_ai/` | 第三方 MCP 插件（Godot AI 工具链），**和编辑器业务逻辑完全无关**。它的 autoload `_mcp_game_helper` 是自己注册的 |

### 死的文件（别浪费时间研究）

| 路径 | 说明 |
|---|---|
| `scene/FileItemButton.tscn` | **没有任何地方引用**，是早期方案的残留 |
| `main.tscn` 里的 `VBC/SpC/HBC/VBC/Button` | 文件树左边那个 40x40 的纯图标按钮（`icon = folderIcon`）。**没连任何信号、`main.gd` 里没有 `_on_..._pressed`**，按下去什么都不会发生。同级的 `VBC` 容器里只有它一个孩子 |
| `asset/icon/settingIcon.png` | 没被任何场景引用 |
| `asset/bg/loadingBg.png`、`asset/bg/tsBg.png` | 没被引用，只用了 `tsBgHF.png` |

> 顺带一提：光 `addons/` 两个目录加起来就有 300 多个文件，搜索时建议排除，否则结果会被淹掉。

---

## 4. `main.gd` 代码地图

文件按功能分了几块，找代码按这个顺序定位（行号会漂，以函数名为准）：

| 区域 | 关键函数 | 干什么的 |
|---|---|---|
| **配置常量**（文件头） | `TEXT_EXTENSIONS` `SKIP_DIRS` `MAX_TREE_DEPTH` `ICON_*` | 扩展名白名单、跳过的目录、递归深度上限、图标路径 |
| **启动** | `_ready()` | 建树、读命令行参数、连信号 |
| **存/开** | `open_and_show()` `save_file()` `_on_save_as_file_selected()` | 读写文件。**所有数据风险的源头都在这一块**。三个 `FileDialog` 的 filters 在 `.tscn` 里配，见 7.15 |
| **快捷键** | `_input()` | Ctrl+S / Ctrl+Shift+S / Ctrl+O / F11 / 缩放 / 小地图 |
| **右键菜单** | `_setup_item_menu()` `_on_file_tree_gui_input()` `_open_item_menu_at()` `_on_menu_window_input()` `_build_item_menu()` `_on_menu_id_pressed()` | 见第 6 节。两个入口都汇到 `_open_item_menu_at(vp_pos)`：Tree 的 `gui_input`（第一次右键）和菜单自己的 `window_input`（菜单开着时的右键，那时候主视口收不到输入，见 §7.16） |
| **新建文件** | `_prompt_new_file()` `_prompt_new_file_in()` `_default_new_file_name()` `_on_new_file_confirmed()` | 两个入口共用（右键目录 / 头部按钮），都落到 `_prompt_new_file_in(dir)`。默认名 `新建文件.txt`，撞名自动往后数 (2) (3) |
| **新建文件夹** | `_prompt_new_folder()` `_prompt_new_folder_in()` `_default_new_folder_name()` `_on_new_folder_confirmed()` | 和新建文件完全对称，只是用 `DirAccess.make_dir_absolute()`。默认名 `新建文件夹`（不带扩展名） |
| **头部按钮** | `_setup_explorer_buttons()` `_new_target_dir()` `_update_new_buttons()` | 「新建文件」「新建文件夹」两个按钮 + 它们的可用状态。目标目录**恒等于当前打开的文件夹**（`root_dir`），规则见 §6 |
| **重命名** | `_prompt_rename()` `_validate_new_name()` `_on_rename_confirmed()` | 校验拆成了纯函数，方便不起弹窗就能测 |
| **名字校验** | `_validate_name_in_dir()` | 空名 / 非法字符 / 撞名 / **目标目录为空**四档，**新建文件和新建文件夹、重命名共用这一套**（`_validate_new_name()` 只是委托它），省得两边各自长歪 |
| **删除** | `_prompt_delete()` `_on_delete_confirmed()` | 走系统回收站 |
| **文件树** | `_setup_file_tree()` `set_root_dir()` `refresh_file_tree()` `_populate_dir()` | 建树、换根、刷新、递归填充 |
| **折叠状态** | `_collect_collapsed_paths()` `_restore_collapsed_paths()` | 刷新时保住用户的折叠状态 |
| **条目判定** | `_item_path()` `_item_is_dir()` `_is_editable_file()` `_is_under()` | 几个纯查询函数 |
| **点击** | `_on_file_tree_item_selected()` `_on_file_tree_item_activated()` `_on_open_as_text_confirmed()` | 单击 / 双击 两条不同的路 |
| **程序化选中** | `_select_tree_item_for_path()` + `_suppress_dir_toggle` | 在树里定位并选中一条，顺带展开祖先链。**它会让 `item_selected` 发出来**，那一下的副作用是这条链路的设计核心，见 7.14 |

---

## 5. 三个核心状态

理解这三样，代码基本就通了：

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

> 没有 metadata 的条目是"未指定目录"那个占位提示，`_item_path()` 会返回空串——多处守卫靠"空串"来判断"这不是个真条目"。

---

## 6. 交互行为总表

| 操作 | 目录 | 可编辑文件（`.txt` `.md` …） | 不可编辑文件（`.docx` `.pptx` …） |
|---|---|---|---|
| **单击** | 展开 / 折叠 | 载入编辑器 | **只选中高亮，不载入** |
| **双击** | 展开 / 折叠 | 载入编辑器 | **弹提醒 → 确认后按文本打开** |
| **右键** | **第一、二项「新建文件」「新建文件夹」** + 文件管理器 / 重命名 / 删除 / 复制路径 / 刷新 | 文件管理器 / 重命名 / 删除 / 复制路径 / 刷新 | 同上，**外加第一项「用默认程序打开」** |

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
  （「Explorer」那行）的两个按钮。默认名 `新建文件夹`，同目录已有同名的就往后数成 `新建文件夹 (2)`。
  它没有"主名 / 扩展名"可分，所以弹框里是**整段选中**（走的同一个 `_select_base_name_in()`，
  只是找不到扩展名就退化成全选）。
- **头部两个按钮的目标目录 = 当前打开的这个文件夹**（`root_dir` 本身），**和树里的选中项无关**：
  选中谁也不影响它，永远建在你正开着的那个目录里。
  早先的规则是"建在选中项所在 / 旁边的目录"，被用户推翻了 —— 先前的设计要靠选中项猜意图，
  实际用起来就成了"我明明开着 A 目录，东西却跑进选中的那个子目录里了"。
  想放进子目录就走那个子目录的**右键菜单**（右键 → 新建文件 / 新建文件夹）：
  那里有明确的"对着谁操作"的上下文，比靠选中项猜可靠。
  一个目录都没打开时两个按钮**禁用**——那种状态下 `root_dir` 是空串，`path_join()` 出来的相对路径
  会把东西写到进程的工作目录（导出后是 exe 所在目录），用户根本找不着。
  禁用状态在每次 `refresh_file_tree()` 里跟着重算，所以换根目录、开新目录之后不会剩下一个亮着的按钮。
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
- **目录的展开状态不会因为"程序化选中"而改变**（详见 7.14.1）：重命名一个目录、或者新建一个文件夹，
  都会在树里选中它，而选中目录在别处是"切换展开 / 折叠"的意思。早先没挡这一下的时候，
  重命名一个**有内容的**目录会把它收起来 —— 里面的文件当场从树里消失。

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

### 7.5 `TreeItem.collapsed` 默认是 `false`（展开）

所以 `refresh_file_tree()` 里保留的是**被折叠的**路径集合，不是展开的。记反了的话保存逻辑会变成空操作，用户手动折叠的目录会每次刷新都弹开。

### 7.6 Tree 会静默拒绝折叠"包含当前选中项"的目录

给那个目录赋 `collapsed = true` 当场读回来还是 `false`，不报错也不发信号。通过 UI 走不到这个状态，所以不用额外处理，但写测试时会遇到（别以为是自己的 bug）。

### 7.7 Tree 的 `icon_size` 主题常量在 4.7 对绘制尺寸无效

图标是按原始尺寸画的，源图 400×400 能把整行撑爆。所以 `_make_icon()` 在**加载时**就用 `Image.resize()` 统一重采样到 15×15，而不是靠主题常量。

### 7.8 `OS.alert()` 在 Windows 上是**阻塞**的

任何埋在它后面的分支都没法从脚本里驱动（测试会直接挂住）。所以校验逻辑拆成了纯函数——典型例子是 `_validate_new_name(old_path, new_name) -> String`，返回 `""` 表示可用，否则返回给用户看的原因。

### 7.9 场景里所有节点都带 `unique_id`

这是这套 tscn 格式的必需字段（`main.tscn` 里 44 个节点全都有）。**手写 tscn 加节点容易把 id 写错或写重**，所以新加的对话框（重命名的 `LineEdit`、"按文本打开"的提醒框）都是在代码里 `new()` 出来的，让 Godot 自己保存场景时落盘更安全。

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

### 7.12 展开箭头是 Tree 自己处理的，别插手

点条目前面那个三角形，Tree **原生**就会切换折叠状态，而且它**既不发 `item_selected`
也不发 `item_activated`**（实测两者都是 0 次）。

好处是这条路完全不用我们管。代价是：**别想着在 `gui_input` 里按鼠标位置也去切一下** —— 那样
箭头会被切两次、净效果为零。所以目录的切换只能挂在 `item_selected` / `item_activated` 上，
不能挂在"按下的位置落在哪个条目上"这种判断上。

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
- **新建文件夹** → 刚建出来的目录是折叠状态。空目录看不出来（没子项就没那个箭头），
  但折叠状态会被 `_collect_collapsed_paths()` 按路径一路保住，等它里面真有东西了，
  就是"我自己刚建的文件夹，里面的文件不见了"。

修法是 `_suppress_dir_toggle` 这个开关，只在 `_select_tree_item_for_path()` 里围着那一句
`item.select(0)` 打开（`main.gd:920` 附近）。三条要记住的：

- **必须紧贴着 `select()`**：信号是**同步**发的，中间不能有 `await`，也不能提前 `return`
  （现在这两句之间什么都没有，是故意的）。
- **别把它漏成全局状态**：正常点击目录必须照旧能切换。harness 里专门验了两条 ——
  收尾后开关是 `false`，以及模拟一次真实单击（先 `deselect_all()` 再 `select(0)`，绕开
  `allow_reselect = false`）仍然能切换。
- 代价是**重命名的展开状态保不住**：折叠状态是按**路径**记的（`_collect_collapsed_paths()`），
  路径一改名就对不上，所以重命名后的目录一律是展开的。这是取舍，不是漏做 ——
  换成"宁可收起来"就会退回上面那个"内容消失"的坑。

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

---

## 9. 明确没做的（别以为是漏了）

- 在**空白处**右键弹菜单（现在只有对着条目右键才有菜单）。头部那两个按钮算是部分替代 ——
  它们打在**当前打开的文件夹**里（见 §6），但"在某个空白位置右键、把目标目录定在那儿"还是没有
- 头部那个 40x40 的纯图标按钮还没接上（见 §3 死的文件），它长得像是要给某个功能留的位置
- 新建时选扩展名（现在固定 `.txt`；想建 `.md` / `.json` 只能在弹框里把后缀改掉）
- 在选中目录打开终端
- 永久删除——只有回收站一条路（`OS.move_to_trash`）
- 多选批量操作
- 查找 / 替换、撤销栈以外的编辑增强
- 设置窗口（UI 建好了，按钮是隐藏的）
- 标签页 / 多文件同时打开——**同时只有一个文件**

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

输入动作定义在 `project.godot` 的 `[input]` 段：`ui_save` `f11` `zoom_up` `zoom_down` `map`。

窗口启动即最大化（`display/window/size/mode=2`）。`run/max_fps=144`，物理引擎设成了 `Dummy`（这不是游戏，物理没意义）。

底部状态栏左侧的字符数由 `_process()` **每帧**刷新——所以别指望往 `Label3` 上挂临时提示，会被覆盖掉。
