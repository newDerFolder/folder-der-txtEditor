class_name TextToBbcode
extends RefCounted

## 纯文本 → 「阅读排版」BBCode。
##
## 干两件事：让一坨 .txt 在窄栏里读起来舒服（首行缩进、段间距、场景分隔行居中），
## 以及**认出章节标题**并顺带产出一份目录。
##
## 章节识别是后加的（原先 README §9 记的是"只做阅读排版、不做解析、不分章"，
## 那是当初有意的取舍，现在按需求改了）。识别规则**只用可测的启发式**，
## 不引 RegEx（本项目的约定，README §3），代价和边界写在 chapter_of() 的注释里。
##
## 拆成独立脚本的理由和 main.gd 的 _validate_name_in_dir() 一样：**纯函数，进 String 出
## String**，不碰节点也不读文件，所以不起界面就能拿它做断言。
##
## 正文字号**仍然不在这里管**（由 main.gd 通过 RichTextLabel 的主题覆盖统一管）。
## 但章节标题要"比正文大一点"，而转换器不该知道正文字号是多少 —— 所以字号由调用方通过
## opts["font_size"] **告诉**它，没传（0）就一个 [font_size] 都不发。
## 这样"不传参 = 和改动前逐字节一样"是结构性成立的。

const Palette := preload("res://scene/Previewer/PreviewTheme.gd")

## 首行缩进用的全角空格字符。缩进字宽由 opts["indent"] 定，默认 INDENT_DEFAULT 个。
##
## 这是**不能用 [indent] 代替**的：[indent] 缩进的是整个块 —— 每一行，包括自动折行出来的
## 续行。套在正文上整段都会往右挪，那不是首行缩进，读起来是错的。
## 中文排版里首行缩进就是两个字宽，直接写成字符最省事。
const INDENT_CHAR := "　"

## 默认缩进字宽（两个全角空格）。
const INDENT_DEFAULT := 2

## 允许当分隔行的符号。**限定字符集**，而不是"任意同一种字符重复 3 次"——
## 后者会把 "。。。。" 吃进来，而中文小说里那是省略号，不是分隔线。
const BREAK_SYMBOLS := "*-—=~☆★◆◇❀※×_"

## 同类符号至少要这么多个才算分隔行。1 个 "-" 是正文里的破折号，不是分隔线。
const BREAK_MIN_RUN := 3

## 分隔行的显示形式
const BREAK_TEXT := "* * *"
## 取色板而不是另写一份字面量 —— 这个色值和 MarkdownToBbcode 的 DIM_FG 是同一个，
## 以前是两处各写一遍，换主题时必然漏一处。
const BREAK_COLOR := Palette.C_DIM

## 章节标题比正文大多少像素。只有调用方给了 font_size 时才用得上。
##
## 取 4（正文 16 → 标题 20，1.25×）是对着**右栏有多窄**定的：右栏固定 274px、
## 选了"阅读宽度 180px"之后正文只剩 172px 左右，而中文字号是按像素算的 ——
## 22px 的标题一行只放得下 7 个字，一个 15 字的标题要折三行，比正文还难读。
## 1.25× 左右本来也是中文小说标题的常见比例，两头都占。
const CHAPTER_FONT_STEP := 4

# ---------------- 章节识别的规则表 ----------------

## "第 X 章" 里的单位字。这两组分开是为了给出层级（目录里的缩进）。
const CHAPTER_UNITS := "章节回"
const VOLUME_UNITS := "卷部篇集"

## 标题行的长度上限。超了就不是标题，是正文。
const CHAPTER_MAX_LEN := 30

## 中文数字 + 阿拉伯数字。`第 1024 章` 和 `第一百零三章` 都认。
const CHAPTER_NUMERALS := "零〇一二三四五六七八九十百千两万"

## 固定词开头的章节（没有"第 X 章"形式的那些）。**长的必须排在前面**，
## 否则 "番外篇" 会被 "番外" 先匹配掉、剩下个 "篇" 当标题。
const FIXED_HEADS: Array[String] = ["序章", "楔子", "引子", "尾声", "后记", "番外篇", "番外", "终章", "前言"]

## 以这些标点结尾的行**一定不是**标题：那是正文句子的收尾。
const SENTENCE_TAIL := "。！？；…"


## 把纯文本转成 BBCode。**保留旧签名**（harness 里有大量按一个参数调用的断言）。
static func to_bbcode(src: String, opts: Dictionary = {}) -> String:
	return String(to_bbcode_with_toc(src, opts)["bbcode"])


## 同上，外加一份章节目录。
##
## 返回 `{"bbcode": String, "chapters": Array[Dictionary]}`，每个章节条目是
## `{"title": String, "paragraph": int, "level": int, "source_line": int}`，
## 其中 **`paragraph` 是该标题在**输出** BBCode 里的行号** —— 也就是 RichTextLabel 里的
## 段落号（已实测：输出几行，`get_paragraph_count()` 就是几，见 README §7.20）。
## main.gd 靠它跳转：`rtl.get_paragraph_offset(paragraph)` 直接给出像素 Y。
##
## **目录是顺手产出的，不是第二趟扫描**：标题行本来就逐行过一遍，认出来时把它在 out 里的
## 下标记下来就行。所以"加目录"对 120k 字符的大文件是零额外开销。
##
## opts 支持（都有默认值，不传 = 改动前的行为）：
##   * `indent: int`     —— 首行缩进字宽，默认 2
##   * `theme: int`      —— 阅读主题 id（见 PreviewTheme.Theme），默认 DEFAULT
##   * `font_size: int`  —— 正文字号（像素）。**只影响章节标题放多大**，0 = 不发字号标签
static func to_bbcode_with_toc(src: String, opts: Dictionary = {}) -> Dictionary:
	var indent: int = int(opts.get("indent", INDENT_DEFAULT))
	var theme: int = int(opts.get("theme", Palette.Scheme.DEFAULT))
	var font_size: int = int(opts.get("font_size", 0))

	var out: Array[String] = []
	var chapters: Array[Dictionary] = []
	var lines := _normalize(src).split("\n")
	for li in lines.size():
		var line := lines[li].strip_edges()
		# 空行整个丢掉。它是**分隔符**，而视觉上的段间距由 RichTextLabel 的
		# line_separation 主题常量给 —— 留着的话每段之间会空两倍（空行 + 行距）。
		if line.is_empty():
			continue
		if _is_break_line(line):
			out.append("[center][color=%s]%s[/color][/center]" % [BREAK_COLOR, BREAK_TEXT])
			continue
		var chapter := chapter_of(line)
		if not chapter.is_empty():
			# **一行一个标题**是硬要求：一行 = RTL 里一个段落 = 目录里一个 paragraph 号。
			# [center] 放最外层 —— 和上面那行分隔线的写法一致，是已经验证过的嵌套顺序。
			var sized := "[color=%s]%s[/color]" % [Palette.C_HEADING, _escape(line)]
			if font_size > 0:
				out.append("[center][font_size=%d][b]%s[/b][/font_size][/center]" %
					[font_size + CHAPTER_FONT_STEP, sized])
			else:
				out.append("[center][b]%s[/b][/center]" % sized)
			chapters.append({
				"title": line,
				"paragraph": out.size() - 1,
				"level": int(chapter["level"]),
				"source_line": li + 1,
			})
			continue
		out.append(_indent_line(line, indent))

	# 段与段之间**不插空行**：有了首行缩进，中文书本来就是密排的，
	# 再插空行会和 line_separation 叠成双倍行距，整页就散了。
	# 这也是 paragraph 号能直接等于 out 下标的前提（没有空段落混进来）。
	return {
		"bbcode": Palette.retint("\n".join(out), theme),
		"chapters": chapters,
	}


## 这一行是不是章节标题。是 → `{"level": int}`；否 → `{}`。
##
## ## 判定顺序和每一条的理由
##
## 1. **长度上限** —— 标题不会长。"第一章 在那个下着大雨的傍晚我终于想起来了" 是正文。
## 2. **句末标点结尾一律否决** —— "我第一章就写完了。" 这种以 `。` 收尾的一定是句子。
## 3. **必须整行以章节标记开头** —— 这一条挡掉了绝大多数假阳性。
##    注意 "我第一章就写完了" 是靠**这条**挡掉的（它不以「第」开头），不是靠边界字检查。
## 4. **「第」+ 数字 + 单位字** —— 单位字必须有，所以 "第三次世界大战爆发"（`次` 不是单位）
##    和 "第2023年"（`年` 不是单位）都会被挡掉。
##
## ## 已知的边界（**有意的取舍，不是 bug**）
##
## "第一章就写完了" 这种**整行**恰好以章节形式开头的正文句子，**会被误判成标题**。
## 之所以不做"单位字后面必须是空格或行尾"这种更严的检查：中文网文的标题**极常见**
## 不带空格的写法（`第一章初见`、`第一章重生`），严检查会把这些真标题全漏掉。
## 而在"误判"和"漏判"之间，误判的后果是**一行文字被放大居中**（看得见、好改、不影响阅读），
## 漏判的后果是**功能在真实小说上看着像没生效**。所以这里偏向召回。
## 如果你确实被误判烦到了，把这条打开即可 —— 它是一行的事。
## 另外 `，` 是**允许**出现在标题里的（`第一章 你好，世界`），只有句末标点才否决。
static func chapter_of(line: String) -> Dictionary:
	if line.length() == 0 or line.length() > CHAPTER_MAX_LEN:
		return {}
	if SENTENCE_TAIL.contains(line[line.length() - 1]):
		return {}
	if _match_fixed_head(line) != "":
		return {"level": 2}
	if not line.begins_with("第"):
		return {}
	var j := 1
	while j < line.length() and _is_numeral(line[j]):
		j += 1
	if j == 1:
		return {}               # 「第」后面没有数字
	if j >= line.length():
		return {}               # 只有数字、没有单位字
	var unit := line[j]
	if VOLUME_UNITS.contains(unit):
		return {"level": 1}
	if CHAPTER_UNITS.contains(unit):
		return {"level": 2}
	return {}


## 命中最长的那个固定词。**取最长**是为了让 "番外篇" 赢过 "番外"。
static func _match_fixed_head(line: String) -> String:
	var best := ""
	for w in FIXED_HEADS:
		if line.begins_with(w) and w.length() > best.length():
			best = w
	return best


## 中文数字或阿拉伯数字。
static func _is_numeral(c: String) -> bool:
	return CHAPTER_NUMERALS.contains(c) or c.is_valid_int()


## 换行统一成 \n、制表符展开、去掉控制字符。
##
## 控制字符是**真会来的**，不是防御性代码：`.docx` 之类的二进制文件可以被"强制按文本打开"
## （main.gd 的 _on_open_as_text_confirmed），GBK 编码的中文也会带进来一堆。RichTextLabel
## 拿到这些会在控制台刷警告，排版也会乱。
static func _normalize(src: String) -> String:
	var s := src.replace("\r\n", "\n").replace("\r", "\n")
	# 制表符先展开成 4 个空格：RichTextLabel 不认识 \t，会画成一个方块。
	s = s.replace("\t", "    ")
	var parts: Array[String] = []
	# 用数组攒再一次 join：GDScript 的字符串相加在循环里是 O(n²)，
	# 几 MB 的 txt 会直接卡住主线程。
	for i in s.length():
		var code := s.unicode_at(i)
		if code < 32:
			if code == 10:      # \n
				parts.append("\n")
			continue            # 其余 C0 控制字符（含 \r \t，上面已经处理过）丢掉
		if code != 127:         # DEL
			parts.append(s[i])
	return "".join(parts)


## 把字面文本转成安全的 BBCode。
##
## **只做一件事**：把 "[" 换成 "[lb]"。RichTextLabel 没有"整段转义"的标签，也没有 `\[`
## 这种反斜杠转义（文档明说要用 [lb] / [rb] 这两个自闭合标签），所以唯一的办法就是逐字符换。
## 右方括号本身是安全的：单独一个 "]" 不构成标签，原样输出即可。
##
## **PreviewTheme.retint() 的防注入依赖这一条**：文档内容里的 `[` 全被换成 `[lb]` 之后，
## 输出串里凡是 `[color=...` 都只可能是转换器自己写的，用户伪造不出标签来。
static func _escape(src: String) -> String:
	return src.replace("[", "[lb]")


## 整行只有一种分隔符号、且凑够 BREAK_MIN_RUN 个 —— `* * *`、`---`、`☆☆☆`、`======`。
## 符号之间允许有空格（中文书里的 `* * *` 就是这么写的）。
static func _is_break_line(line: String) -> bool:
	var symbol := ""
	var count := 0
	for i in line.length():
		var c := line[i]
		if c == " " or c == INDENT_CHAR:
			continue
		if not BREAK_SYMBOLS.contains(c):
			return false
		if count == 0:
			symbol = c
		elif c != symbol:
			return false        # 混了两种符号，不是分隔行
		count += 1
	return count >= BREAK_MIN_RUN


## 首行缩进。
##
## **已经以全角空格开头的行不加** —— 作者自己缩进过了，再加两个字宽会变成四字缩进，
## 比不缩进还难看。（判断用的是常量 INDENT_CHAR，不是硬编码的字面量 ——
## 这个字面量以前是直接写在代码里的，改可配置缩进时就会漏。）
##
## 半角空格不在这里管：调用方已经 strip_edges 过了，零星的前导半角空白是排版噪音，
## "重排"这件事本身就包含把它抹平、换成统一的全角缩进。
static func _indent_line(line: String, indent: int) -> String:
	if indent <= 0 or line.begins_with(INDENT_CHAR):
		return _escape(line)
	return INDENT_CHAR.repeat(indent) + _escape(line)
