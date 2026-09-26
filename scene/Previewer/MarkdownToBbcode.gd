class_name MarkdownToBbcode
extends RefCounted

## 常见 Markdown → BBCode。自写，**不引第三方库**（本项目的约定，README §3）。
##
## ## 架构：为什么必须分两趟
##
## 这里是「**先一趟块级扫描，再一个递归行内扫描器**」，**不是**一串 regex 替换。
## 替换式的写法看着短，但三件事会同时坏掉：
##
##   1. `**粗**` 和 `*斜*` 互相咬。逐条替换时 `**a**` 会先被 `*` 的规则吃成 `*` + `*a*` + `*`。
##   2. 代码块里的 `#`、`>`、`-` 会被当成标题 / 引用 / 列表 —— 除非你先把它整块摘出去。
##   3. 转义会被做两遍（先转义再加标签，标签里的 `[` 又挨一次），
##      或者漏掉一遍（行内代码里的 `[` 没转义，直接变成标签被吃掉）。
##
## 递归扫描器还把「严格嵌套」这件事变成了**结构上的必然**：内层永远在外层闭合之前完整
## 吐出来。RichTextLabel **不支持交叉嵌套标签**（`[b]a[i]b[/b]c[/i]` 是无效的），
## 所以这不是讲究，是硬要求。
##
## ## 故意不支持
##
## setext 标题（`===` 下划线式）、表格、HTML 块、脚注、引用式链接、嵌套 `[ul]`。
## 理由和替代做法写在各处的注释里，汇总在 README §9。

# ---------------- 配色 ----------------

# 项目里**一个字体文件都没有**（resource/folder.tres 只有一行 TextEdit 字号），
# 而 [code] 换出等宽字体是需要自定义字体的（Godot 文档明说，没有就退回普通字体）。
# 所以代码的"像代码"只能靠底色和颜色做出来 —— 这些常量就是干这个的。
#
# **色值本身不在这里写**，全部来自 PreviewTheme（单一真源）。下面这些只是"默认主题下的
# 取色"的别名 —— 留着它们是为了让这 10 处拼串保持可读，而不是让色值散成两份。
#
# **换肤也不是在这里做的**：转换器照旧只吐默认色，最后由 PreviewTheme.retint() 把成品串
# 里的标签形式一次性换成主题色。这样色板就不必穿透传给下面 6 个子函数
# （base_font_size 就是这么传的，已经传到了 8 个点，再加一个参数是 16 处改动）。
# 为什么"换成品串"是安全的、而不是"把裸色值 replace 一遍"，见 PreviewTheme 的文件头。
const Palette := preload("res://scene/Previewer/PreviewTheme.gd")

const CODE_BG := Palette.C_CODE_BG          # 代码块整块的底色
const INLINE_CODE_BG := Palette.C_INLINE_CODE_BG   # 行内代码的底色
const INLINE_CODE_FG := Palette.C_INLINE_CODE_FG   # 行内代码的字色
const LINK_FG := Palette.C_LINK
const QUOTE_FG := Palette.C_QUOTE
const HEADING_FG := Palette.C_HEADING
const DIM_FG := Palette.C_DIM    # "点不动"的东西：不可点的链接目标、其它说明
const HR_COLOR := Palette.C_HR

## 标题字号相对正文的**增量**（h1..h6）。
##
## RichTextLabel 的 [font_size=N] 是**绝对像素**，没有 em / rem —— 所以标题字号只能由
## 调用方传进来的正文字号推算。写死像素的话，用户把正文字号调到 24，标题会反而变小。
const HEADING_STEP: Array[int] = [10, 7, 5, 3, 2, 1]

## 引用块左边那根竖条。Godot 没有 blockquote 标签，竖线 + 暗色文字是标准替代品。
const QUOTE_BAR := "▏"

## 代码块整块套一层缩进，让它和正文分开一点。用 [indent] 而不是前导空格：
## 空格会被 RichTextLabel 原样保留，但和块内的真实缩进混在一起就分不清了。
const CODE_INDENT_OPEN := "[indent]"
const CODE_INDENT_CLOSE := "[/indent]"


## 把 Markdown 转成 BBCode。**保留旧签名**（harness 里大量按老形式调用）。
static func to_bbcode(src: String, base_font_size: int = 16) -> String:
	return String(to_bbcode_with_toc(src, base_font_size)["bbcode"])


## 同上，外加一份章节目录（标题在**输出**里的段落号）。
##
## base_font_size 是正文的基准字号（像素），只用来推标题字号 —— 正文本身的字号不在这里设，
## 由 main.gd 的主题覆盖统一管。
##
## theme 只做一件收尾工作：把成品串里的标签形式换成主题色（PreviewTheme.retint）。
## 默认主题下是**原样返回**，所以"不传 theme = 和改动前逐字节一样"是结构性的。
##
## `paragraph` 是给 main.gd 跳转用的：`rtl.get_paragraph_offset(paragraph)` 直接给像素 Y。
## **md 这边不能像 txt 那样拿"输出数组的下标"当段落号** —— md 的块本身就是多行的
## （列表、代码块、引用），块之间还用空行分隔，所以段落号必须**数换行**得到。
## 下面那个前缀和就是在不切子串的前提下把这件事做成一遍 O(n)（切子串会是 O(n·标题数)）。
static func to_bbcode_with_toc(src: String, base_font_size: int = 16,
		theme: int = Palette.Scheme.DEFAULT) -> Dictionary:
	var lines := _normalize(src).split("\n")
	var out: Array[String] = []
	## 标题暂存：[输出块下标, 标题, 层级, 源行号]。块下标要等 out 攒完才能换算成段落号。
	var marks: Array[Dictionary] = []
	var i := 0
	while i < lines.size():
		var line: String = lines[i]

		# ① 围栏代码块 —— **必须排在最前**。
		#
		# 这不是"顺手先处理一下"：块里的 `#`、`>`、`-`、`*` 全是字面量，而它们能被误判成
		# 标题 / 引用 / 列表的唯一机会，就在下面那几个块级判定里。整块在这里被吞掉之后，
		# 它们**根本进不了**行内扫描器 —— 这才是"代码块里的井号不当标题"的实现方式，
		# 而不是给代码块开后门加特例。
		var fence := _fence_info(line)
		if fence != "":
			var body: Array[String] = []
			i += 1
			while i < lines.size() and not _is_fence_close(lines[i], fence):
				body.append(lines[i])
				i += 1
			if i < lines.size():
				i += 1      # 吃掉收尾围栏；作者没写收尾的话就一路吃到文件尾
			# 体内容**只做 BBCode 转义**，不再走任何 markdown 规则。
			# 缩进原样保留：RichTextLabel 不像 HTML 那样折叠空白，所以这里不需要 <pre> 的对应物。
			out.append(CODE_INDENT_OPEN + "[bgcolor=%s][code]%s[/code][/bgcolor]" % [
				CODE_BG, _escape("\n".join(body))] + CODE_INDENT_CLOSE)
			continue

		# ② 空行丢掉。段间距交给 line_separation，留着会双倍。
		if line.strip_edges().is_empty():
			i += 1
			continue

		# ③ 水平线。**排在列表前面**，而且要求整行只有标记符 ——
		#    这两条合起来才是 `- item`（列表）和 `---`（分割线）分得开的原因。
		if _is_hr(line):
			# 用 Palette.HR_ATTR 拼而不是把整条标签写在这里：retint 的替换目标就是它，
			# 两处各写一份的话，改了属性顺序就会**静默**换不了色（匹配不上，不报错）。
			out.append(Palette.HR_ATTR + HR_COLOR + "]")
			i += 1
			continue

		# ④ ATX 标题
		var level := _heading_level(line)
		if level > 0:
			var text := _heading_text(line)
			var size: int = base_font_size + HEADING_STEP[level - 1]
			out.append("[font_size=%d][b][color=%s]%s[/color][/b][/font_size]" % [
				size, HEADING_FG, _inline(text, base_font_size)])
			marks.append({"block": out.size() - 1, "title": _plain_title(text),
				"level": level, "source_line": i + 1})
			i += 1
			continue

		# ⑤ 引用块：连续的 "> " 行。块内允许空行，只要后面还跟着引用行。
		if int(_split_quote(line)["depth"]) > 0:
			var quote: Array[String] = []
			var blanks := 0
			while i < lines.size():
				var q := _split_quote(lines[i])
				if int(q["depth"]) > 0:
					while blanks > 0:
						quote.append("")
						blanks -= 1
					quote.append(_quote_line(q, base_font_size))
					i += 1
				elif lines[i].strip_edges().is_empty():
					blanks += 1
					i += 1
				else:
					break
			out.append("\n".join(quote))
			continue

		# ⑥ 列表：连续的同类型列表行合成一个块
		var item := _match_list_item(line)
		if not item.is_empty():
			var kind: String = item["kind"]
			var base_indent: int = item["indent"]
			var items: Array[Dictionary] = []
			while i < lines.size():
				var it := _match_list_item(lines[i])
				if it.is_empty():
					# 续行：比当前项缩进更深、又不是任何块的开始 —— 接到上一项后面。
					# 不接的话，"一行写不完、下一行接着写"的列表项会被切成两个条目，
					# 而且第二段会丢掉项目符号变成普通段落。
					if items.is_empty() or _is_block_start(lines[i]):
						break
					var cont: String = lines[i]
					var lead := cont.length() - cont.lstrip(" \t").length()
					if lead <= int(items[-1]["indent"]):
						break
					items[-1]["text"] = str(items[-1]["text"]) + " " + cont.strip_edges()
					i += 1
					continue
				# 换标记类型（ul ↔ ol）或者缩进退回到更浅 = 这个列表到头了
				if it["kind"] != kind or int(it["indent"]) < base_indent:
					break
				items.append(it)
				i += 1
			out.append(_render_list(kind, base_indent, items, base_font_size))
			continue

		# ⑦ 段落：一直攒到下一个块开始为止。
		#
		# 行与行之间**用空格连接**（markdown 的软换行规则）：.md 源码里的换行是为了让人
		# 读源码时好读，不是为了在浏览器里断行。274px 的窄栏里重排一次，比照搬硬折行好看得多。
		# 行尾两个空格或一个反斜杠才是硬换行，那个保留（见 _join_soft）。
		var buf: Array[String] = []
		while i < lines.size() and not _is_block_start(lines[i]):
			buf.append(lines[i].lstrip(" \t"))
			i += 1
		if buf.is_empty():
			# 兜底：_is_block_start 说"是块"，但没有哪个分支接手它 —— 那就是死循环。
			# 真发生的话整个编辑器会卡死，宁可跳过一个字符。
			i += 1
			continue
		out.append(_inline(_join_soft(buf), base_font_size))

	# 块与块之间空一行。块内部的换行（列表条目之间、代码块内部）都是单个 \n，
	# 所以这个 "\n\n" 就是段落间距。
	var joined := "\n\n".join(out)

	# 块下标 → 段落号。前缀和一遍算完：`block_nl[k]` = 第 k 块**开头之前**的换行总数。
	# 递推里那个 +2 就是块之间那两个 \n。RichTextLabel 是"一个 \n 一个段落"，
	# 所以这个计数就是 get_paragraph_offset() 要的段落号（已实测，见 README §7.20）。
	var block_nl: Array[int] = []
	var acc := 0
	for k in out.size():
		block_nl.append(acc)
		acc += out[k].count("\n") + 2
	var chapters: Array[Dictionary] = []
	for m in marks:
		chapters.append({
			"title": m["title"],
			"paragraph": block_nl[int(m["block"])],
			"level": m["level"],
			"source_line": m["source_line"],
		})
	# retint 只换标签里的色值，**不动换行**，所以上面算出来的段落号在换肤后依然成立。
	return {"bbcode": Palette.retint(joined, theme), "chapters": chapters}


## 目录里显示的标题文本：把行内标记符去掉。
##
## 目录项和正文里那个标题是**两处渲染**：正文那份走 `_inline()`（真的加粗变色），
## 目录这份只显示文字。不去掉标记符的话，目录里会赫然写着 `**第一章**`。
##
## 只删标记字符，不做链接解析之类的 —— 目录只是用来认路的，够用就行，
## 不值得为它再引一套和 `_inline()` 平行的解析逻辑（两套逻辑就会有两套 bug）。
static func _plain_title(s: String) -> String:
	return s.replace("`", "").replace("*", "").replace("_", "").replace("~", "").strip_edges()


# ---------------- 行内扫描器 ----------------

## 行内文本 → BBCode。
##
## 逐字符往右走，每一步在当前这个位置**按固定顺序**试各种结构，第一个成立的赢。
## **顺序本身是逻辑**，不能调换，关键的两处：
##
##   * `**` 必须排在 `*` 前面。`***both***` 于是走成"先吃掉 **，内层递归再吃 *"，
##     自然得到 `[b][i]both[/i][/b]`。反过来 `**` 会被拆成两个单星号。
##   * 行内代码必须排在链接 / 强调前面。代码里的 `*` 和 `[` 是字面量，晚一步就会被解析掉。
static func _inline(s: String, base_size: int) -> String:
	var out: Array[String] = []
	var i := 0
	while i < s.length():
		i = _inline_at(s, i, base_size, out)
	return "".join(out)


## 处理 s[i] 处的一个结构，把结果写进 out，返回**下一个要处理的下标**。
##
## 返回值必须永远 > i，否则外层 while 会原地打转。最后那个兜底分支就是保证这条的。
static func _inline_at(s: String, i: int, base_size: int, out: Array[String]) -> int:
	var c := s[i]

	# ① 反斜杠转义。`\*` 要吐出字面的 `*`，绝不能变成斜体分隔符。
	#    只对 ASCII 标点生效（CommonMark 的规则）：`C:\dir` 里的反斜杠要原样留着，
	#    不然 Windows 路径会少一个字符。
	if c == "\\" and i + 1 < s.length() and _is_ascii_punct(s[i + 1]):
		out.append(_escape(s[i + 1]))
		return i + 2

	# ② 行内代码。**里面的内容不再做任何行内解析** ——
	#    这就是"代码里的 * 和 [ 是字面量"的实现方式。
	if c == "`":
		var run := 1
		while i + run < s.length() and s[i + run] == "`":
			run += 1
		var close := _find_backtick_run(s, i + run, run)
		if close >= 0:
			var inner := s.substr(i + run, close - (i + run))
			out.append("[bgcolor=%s][color=%s][code]%s[/code][/color][/bgcolor]" % [
				INLINE_CODE_BG, INLINE_CODE_FG, _escape(inner)])
			return close + run
		# 没有配对的收尾：原样吐出来。要是把后面全当代码吞掉，一行漏个反引号
		# 就会让剩下的半篇文章变色。
		out.append(_escape(s.substr(i, run)))
		return i + run

	# ③ 图片 ![alt](url)。**不做图片渲染**（README §9）：显示暗色的 alt，
	#    至少比原样吐一串 `![...](...)` 可读。
	if c == "!" and s.substr(i, 2) == "![":
		var alt_end := s.find("]", i + 2)
		if alt_end > 0 and s.substr(alt_end + 1, 1) == "(":
			var paren := s.find(")", alt_end + 2)
			if paren > 0:
				var alt := s.substr(i + 2, alt_end - i - 2)
				out.append("[color=%s]🖼 %s[/color]" % [DIM_FG, _escape(alt)])
				return paren + 1

	# ④ 链接 [label](url "title")
	if c == "[":
		var end := _link_at(s, i, base_size, out)
		if end >= 0:
			return end
		# 不是链接 —— 落到最后的字面量分支，会被转义成 [lb]

	# ⑤ 自动链接 <https://…>。用尖括号写的裸 URL。
	if c == "<":
		var gt := s.find(">", i + 1)
		if gt > i:
			var inner := s.substr(i + 1, gt - i - 1)
			if safe_url(inner) != "":
				out.append("[url=%s][color=%s]%s[/color][/url]" % [
					_encode_url_attr(inner), LINK_FG, _escape(inner)])
				return gt + 1

	# ⑥ 粗体。**必须在斜体前面**，见 _inline 的注释。
	if s.substr(i, 2) == "**" or s.substr(i, 2) == "__":
		var bold := _emphasis(s, i, 2, s.substr(i, 2), base_size, out, "b", false)
		if bold >= 0:
			return bold

	# ⑦ 斜体。两个前提：
	#
	#    a) **开标记必须"恰好一个"**。`**` 没配成对的时候（`**unclosed`）绝不能退化成
	#       单星号再试一次 —— 那样第二个星号会被当成闭合符，配出一对空内容，
	#       吐出个 `[i][/i]unclosed`。`***both***` 由上面那条先接走，不受影响。
	#    b) `_` 要加"词字符"守卫，否则 snake_case_name 会被斜体切碎。
	if c == "*" or c == "_":
		if i + 1 >= s.length() or s[i + 1] != c:
			var ital := _emphasis(s, i, 1, c, base_size, out, "i", c == "_")
			if ital >= 0:
				return ital

	# ⑧ 删除线
	if s.substr(i, 2) == "~~":
		var strike := _emphasis(s, i, 2, "~~", base_size, out, "s", false)
		if strike >= 0:
			return strike

	# ⑨ 其余一律字面量。**这是兜底，必须永远推进一格。**
	out.append(_escape(c))
	return i + 1


## 在 s[i] 处尝试解析 `[label](url "title")`。
##
## 成功：写进 out，返回右括号之后的下标。不是链接：返回 -1（调用方退化成字面量）。
static func _link_at(s: String, i: int, base_size: int, out: Array[String]) -> int:
	var close := s.find("]", i + 1)
	if close < 0 or close + 1 >= s.length() or s[close + 1] != "(":
		return -1
	var paren := s.find(")", close + 2)
	if paren < 0:
		return -1
	var label := s.substr(i + 1, close - i - 1)
	var target := s.substr(close + 2, paren - close - 2).strip_edges()
	# 去掉可能存在的 title：`url "标题"`
	var sp := target.find(" ")
	if sp > 0:
		target = target.substr(0, sp)
	var url := safe_url(target)
	if url == "":
		# 不可点的链接：照样用链接色显示 label，后面补一行灰字带上目标。
		# 这是个"看得见但点不动"的状态，比"点了没反应"清楚得多 ——
		# README §6 反复记过那种失败（点了没反应 = 看着像功能坏了）。
		out.append("[color=%s]%s[/color]" % [LINK_FG, _escape(label)])
		if label != target:
			out.append(" [color=%s](%s)[/color]" % [DIM_FG, _escape(target)])
		return paren + 1
	out.append("[url=%s][color=%s]%s[/color][/url]" % [
		_encode_url_attr(url), LINK_FG, _inline(label, base_size)])
	return paren + 1


## 在 s[i] 处尝试配对一段成对分隔符（粗体 / 斜体 / 删除线）。
##
## 成功：写进 out，返回**闭合符之后**的下标。不成立：返回 -1，调用方会把开分隔符当字面量吐出来
## —— 这是"输入不配对时不会失控染色"的保证，漏一个 `*` 不该让后半篇全变斜体。
##
## wordy = true 时按"词内不生效"规则两头都查（给 `_` 用，保住 snake_case_name）。
static func _emphasis(s: String, i: int, width: int, delim: String,
		base_size: int, out: Array[String], tag: String, wordy: bool) -> int:
	var start := i + width
	if start >= s.length():
		return -1
	# 开分隔符后面不能是空白：`a * b * c` 里的星号是乘号或者列表符，不是强调。
	var after := s[start]
	if after == " " or after == "\t" or after == "\n":
		return -1
	# `_` 的左守卫：前面紧跟词字符就不算（`snake_case` 的开头那个下划线）。
	if wordy and i > 0 and _is_word_char(s[i - 1]):
		return -1
	var close := _find_close(s, start, delim, wordy)
	if close < 0:
		return -1
	var inner := s.substr(start, close - start)
	out.append("[" + tag + "]" + _inline(inner, base_size) + "[/" + tag + "]")
	return close + delim.length()


## 从 from 开始找 delim 的**闭合位置**。找不到返回 -1。
##
## 闭合位置取的是"这一串同种字符的**末尾**对齐"，不是第一个出现的位置：
## `***both***` 里开头的 `**` 要配的是结尾三个星号中的**后两个**（最前面那个留给外层的 `*`）。
## 取前两个的话，最后一个星号会落成字面量，正文尾巴上莫名其妙多一个 `*`。
static func _find_close(s: String, from: int, delim: String, wordy: bool) -> int:
	var ch := delim[0]
	var pos := from
	while pos < s.length():
		pos = s.find(ch, pos)
		if pos < 0:
			return -1
		var run_end := pos
		while run_end < s.length() and s[run_end] == ch:
			run_end += 1
		var close := run_end - delim.length()
		# `close > from` 而不是 `>=`：内容**不能为空**。`close == from` 意味着闭合符
		# 就压在内容起点上，配出来的是 `[i][/i]` 这种空心标签。
		if close > from:
			# 闭合符**前面**不能是空白（`*斜 *` 里那个空格属于正文）
			if close > 0 and (s[close - 1] == " " or s[close - 1] == "\t"):
				pos = run_end
				continue
			# `_` 的右守卫：后面紧跟词字符就不算闭合（`a_b_c` 整串保持不变）
			if wordy and run_end < s.length() and _is_word_char(s[run_end]):
				pos = run_end
				continue
			return close
		pos = run_end
	return -1


## 找一串**恰好 n 个**反引号。行内代码的分隔符必须等长，这是 CommonMark 的规则：
## ``` ``a`b`` ``` 里那个单反引号是内容的一部分，不是收尾。
static func _find_backtick_run(s: String, from: int, n: int) -> int:
	var pos := from
	while pos < s.length():
		pos = s.find("`", pos)
		if pos < 0:
			return -1
		var run_end := pos
		while run_end < s.length() and s[run_end] == "`":
			run_end += 1
		if run_end - pos == n:
			return pos
		pos = run_end
	return -1


## 链接白名单。**只放行这三个协议。**
##
## 渲染出来的链接是**可点的**，最终会走到 OS.shell_open —— 那等于把 .md 文件里的任意字符串
## 交给系统去启动。`javascript:`、`file://`、以及 `other.md` 这种相对路径一律拒绝。
##
## **公开**（不带下划线）是因为 main.gd 的 meta_clicked 处理器要用**同一个**白名单再挡一次：
## meta 是从文档内容带过来的，不是我们给的，转换器那道只是"别做成链接"，
## 这道才是"别真的开"。
static func safe_url(raw: String) -> String:
	var s := raw.strip_edges()
	var lower := s.to_lower()
	if lower.begins_with("http://") or lower.begins_with("https://") \
			or lower.begins_with("mailto:"):
		return s
	return ""


## 把 url 塞进 `[url=...]` 之前，先编码掉会破坏标签本身的字符。
## `]` 会提前闭合标签、`"` 会截断属性值、`[` 会和后面的配对检查打架。
## `%` 要先换，否则会把后面换出来的 `%5B` 再换一次。
static func _encode_url_attr(url: String) -> String:
	return url.replace("%", "%25").replace("[", "%5B") \
		.replace("]", "%5D").replace("\"", "%22")


# ---------------- 块级判定的工具 ----------------

## 把字面文本转成安全的 BBCode。**只做一件事**：`[` → `[lb]`（同 TextToBbcode._escape）。
static func _escape(src: String) -> String:
	return src.replace("[", "[lb]")


## 换行统一成 \n、制表符展开、去掉控制字符（理由同 TextToBbcode._normalize）。
static func _normalize(src: String) -> String:
	var s := src.replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ")
	var parts: Array[String] = []
	for i in s.length():
		var code := s.unicode_at(i)
		if code < 32:
			if code == 10:
				parts.append("\n")
			continue
		if code != 127:
			parts.append(s[i])
	return "".join(parts)


## 是不是围栏行。是就返回围栏标记本身（"```" / "~~~~"），不是就返回 ""。
## 行首最多允许 3 格缩进 —— 再多就是"缩进代码块"，是另一回事。
static func _fence_info(line: String) -> String:
	var s := line.lstrip(" \t")
	if s.length() < 3 or line.length() - s.length() > 3:
		return ""
	var c := s[0]
	if c != "`" and c != "~":
		return ""
	var run := 0
	while run < s.length() and s[run] == c:
		run += 1
	return s.substr(0, run) if run >= 3 else ""


## 是不是收尾围栏：同一种符号、**不短于**开围栏、后面没有别的东西。
static func _is_fence_close(line: String, fence: String) -> bool:
	var s := line.strip_edges()
	if s.length() < fence.length():
		return false
	for i in s.length():
		if s[i] != fence[0]:
			return false
	return true


## 水平线：整行（允许最多 3 格缩进）只有一种标记符、且 ≥3 个，符号之间可以有空格。
## `---` / `- - -` / `***` / `___` 都算；`- item` 不算（那个 `i` 不是标记符）。
static func _is_hr(line: String) -> bool:
	var s := line.strip_edges()
	if s.is_empty():
		return false
	var symbol := ""
	var count := 0
	for i in s.length():
		var c := s[i]
		if c == " ":
			continue
		if c != "-" and c != "*" and c != "_":
			return false
		if count == 0:
			symbol = c
		elif c != symbol:
			return false        # 混了两种标记符，不是分割线
		count += 1
	return count >= 3


## ATX 标题的层级（1..6）。不是标题返回 0。
## 后面必须跟空白：`#标签` 不是标题（不然正文里的井号会被吃掉）。
static func _heading_level(line: String) -> int:
	var s := line.lstrip(" \t")
	if line.length() - s.length() > 3:
		return 0
	var n := 0
	while n < s.length() and s[n] == "#":
		n += 1
	if n < 1 or n > 6:
		return 0
	if n < s.length() and s[n] != " " and s[n] != "\t":
		return 0
	return n


## 剥掉标题标记，返回标题文字（去掉可选的收尾 `#`）。
static func _heading_text(line: String) -> String:
	return line.strip_edges().lstrip("#").strip_edges().rstrip("#").strip_edges()


## 剥掉引用标记。返回 {"depth": int, "text": String}，depth == 0 表示不是引用行。
## `> > 文字` 的 depth 是 2，text 是 "文字"。
static func _split_quote(line: String) -> Dictionary:
	var s := line.lstrip(" \t")
	if line.length() - s.length() > 3:
		return {"depth": 0, "text": line}
	var depth := 0
	while s.begins_with(">"):
		s = s.substr(1)
		if s.begins_with(" "):
			s = s.substr(1)
		depth += 1
	return {"depth": depth, "text": s}


## 引用块里的一行：竖条 + 内容。
static func _quote_line(q: Dictionary, base_size: int) -> String:
	var text: String = q["text"]
	if text.strip_edges().is_empty():
		return ""
	var bars := QUOTE_BAR.repeat(int(q["depth"]))
	return "[color=%s]%s %s[/color]" % [QUOTE_FG, bars, _inline(text, base_size)]


## 列表项。不是列表行返回 {}；否则返回 {kind, indent, marker, text}。
## kind 是 "ul" / "ol"，indent 是缩进宽度（制表符按 4 格算）。
static func _match_list_item(line: String) -> Dictionary:
	var indent := 0
	var i := 0
	while i < line.length():
		if line[i] == " ":
			indent += 1
		elif line[i] == "\t":
			indent += 4
		else:
			break
		i += 1
	if i >= line.length():
		return {}
	var c := line[i]
	if c == "-" or c == "+" or c == "*":
		# 标记符后面必须跟空白。`-x` 是正文，`-` 单独出现也不是列表。
		if i + 1 < line.length() and (line[i + 1] == " " or line[i + 1] == "\t"):
			return {"kind": "ul", "indent": indent, "marker": c,
				"text": line.substr(i + 2).strip_edges()}
		return {}
	if c.is_valid_int():
		var j := i
		while j < line.length() and line[j].is_valid_int():
			j += 1
		if j < line.length() and (line[j] == "." or line[j] == ")"):
			if j + 1 < line.length() and (line[j + 1] == " " or line[j + 1] == "\t"):
				return {"kind": "ol", "indent": indent, "marker": line.substr(i, j - i + 1),
					"text": line.substr(j + 2).strip_edges()}
	return {}


## 把一组列表项渲染成 [ul] / [ol]。
##
## 条目之间用**换行**分开 —— 这是这两个标签的契约：RichTextLabel 靠换行切分条目，
## 全写在一行的话所有条目会挤成一段。
##
## **嵌套不用嵌套的 [ul]。** 文档没说支持，不拿没验证过的语法去赌 —— 用已经确认存在的
## [indent] 表达层级（层级越深，缩进越多）。代价是嵌套的条目拿到的是同一套自动项目符号，
## 光看符号分不出第几层；在这个尺寸的栏里够用了，README §9 记着这条。
static func _render_list(kind: String, base_indent: int, items: Array, base_size: int) -> String:
	var open_tag := "[ul]" if kind == "ul" else "[ol type=1]"
	var close_tag := "[/ul]" if kind == "ul" else "[/ol]"
	var lines: Array[String] = []
	for it in items:
		# 每两级缩进算一层：markdown 的嵌套缩进习惯是 2 格，也可能写成 4 格。
		# 这里**故意用整除**（3 格缩进算一层、向下取整，不是 1.5 层）——
		# 警告是有意压掉的，别把它当成笔误改掉。
		@warning_ignore("integer_division")
		var level: int = max(0, (int(it["indent"]) - base_indent) / 2)
		var body := _inline(it["text"], base_size)
		if level > 0:
			lines.append("[indent]".repeat(level) + body + "[/indent]".repeat(level))
		else:
			lines.append(body)
	# 不用自己画项目符号：RichTextLabel 的 [ul]/[ol] 会自己加，
	# 我们再画一个就会变成 "• • 文字"。
	return open_tag + "\n" + "\n".join(lines) + "\n" + close_tag


## 这一行是不是某个块的开始。段落攒行的时候用它决定在哪里断。
static func _is_block_start(line: String) -> bool:
	var s := line.strip_edges()
	if s.is_empty():
		return true
	return _fence_info(line) != "" or _is_hr(line) or _heading_level(line) > 0 \
		or int(_split_quote(line)["depth"]) > 0 or not _match_list_item(line).is_empty()


## 段落里的软换行合并。行尾**两个空格**或一个**反斜杠**是 markdown 的硬换行写法，
## 这里转成真正的换行；其余行尾接一个空格（软换行合并成一行）。
static func _join_soft(lines: Array) -> String:
	var out: Array[String] = []
	var last := lines.size() - 1
	for k in lines.size():
		var line: String = lines[k]
		if k == last:
			out.append(line.rstrip("\\").rstrip(" "))
			continue
		if line.ends_with("  ") or line.ends_with("\\"):
			out.append(line.rstrip("\\").rstrip(" ") + "\n")
		else:
			out.append(line + " ")
	return "".join(out)


## 词字符：字母、数字、下划线、以及任何 Unicode 的"字"（中文也算）。
## 只用来给 `_` 加守卫 —— 它的斜体规则是"词内不生效"，
## 这样 snake_case_name / 变量_后缀 才不会被斜体切碎。
static func _is_word_char(c: String) -> bool:
	return c.is_valid_identifier() or c.is_valid_int()


## 是不是 ASCII 标点。反斜杠转义只对这类字符生效（CommonMark 的规则）。
static func _is_ascii_punct(c: String) -> bool:
	return "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(c)
