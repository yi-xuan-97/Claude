#!/bin/bash
# <xbar.title>Claude 用量徽章(本地版)</xbar.title>
# <xbar.version>v2.2-local</xbar.version>
# <xbar.author>宝贝 + Claude</xbar.author>
# <xbar.desc>纯本地估算 Claude 用量,读会话日志(CLI + Cowork),零网络请求,永不限流</xbar.desc>
# <xbar.dependencies>bash, python3</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# 官方 /api/oauth/usage 接口在 2026 年被收紧,第三方调用持续 429/403。
# 这个版本完全不碰网络,改读本机会话日志估算用量。同时扫两个来源:
#   1. Claude Code CLI 日志   ~/.claude/projects/**/*.jsonl   (时间戳字段 timestamp)
#   2. Cowork/桌面端审计日志   ~/Library/Application Support/Claude/**/audit.jsonl (字段 _audit_timestamp)
# 两者用量都计入同一个限额桶,一起算才接近官方数字。
#
# v2.2:用「5 小时 block」模型算重置时间——官方限额从你这一档第一条消息算起、整点对齐、
#       5 小时后重置(和 ccusage 一致),比单纯滚动窗口准。默认显示百分比。
# 缺点:仍是估算,不含 claude.ai 纯网页/手机端;日志本身有已知轻微少计。当趋势看。
#
# 文件名「.10s.」= 每 10 秒刷新(纯本地读盘,没有网络代价)。这是实用下限:日志按每轮对话写,
# 再低也只是反复读到同一个数。想更省改 .1m.。

# ===== 可调设置 =====
TOKEN_BUDGET=130000000  # 5 小时 token 预算(算百分比用)。0=只显 token 数。
                        # 校准:看下拉里真实 token 数 ÷ (官方当前百分比/100),填到这里重跑 install。
                        # 本地天生略低于官方(漏算纯网页/手机端),且差值会波动 1~3 点,无法完全消除。
WARN=70                 # 百分比超过变橙
CRIT=90                 # 百分比超过变红
SESSION_HOURS=5         # 官方限额窗口小时数
SCAN_ROOTS=".claude/projects:Library/Application Support/Claude"  # 相对 home,Python 里 expanduser 拼接
# ====================

PY="/usr/bin/python3"
command -v "$PY" >/dev/null 2>&1 || PY="$(command -v python3)"

TOKEN_BUDGET="$TOKEN_BUDGET" WARN="$WARN" CRIT="$CRIT" SESSION_HOURS="$SESSION_HOURS" SCAN_ROOTS="$SCAN_ROOTS" "$PY" <<'PYEOF'
import os, json, glob, datetime

BUDGET = int(os.environ.get("TOKEN_BUDGET", 0))
WARN = int(os.environ.get("WARN", 70))
CRIT = int(os.environ.get("CRIT", 90))
SESSION = datetime.timedelta(hours=float(os.environ.get("SESSION_HOURS", 5)))
HOME = os.path.expanduser("~")   # 不依赖 $HOME 环境变量
ROOTS = [os.path.join(HOME, r) for r in os.environ.get("SCAN_ROOTS", "").split(":") if r]

ORANGE, RED, GRAY = "#FF9F0A", "#FF453A", "#8E8E93"
WEEKDAY = ["周一","周二","周三","周四","周五","周六","周日"]
now = datetime.datetime.now(datetime.timezone.utc)
# 读取窗口放宽到 6 小时,确保能抓到当前 block 的起点
read_cutoff = now - datetime.timedelta(hours=6)

def parse_ts(s):
    if not s: return None
    s = str(s).strip()
    if s.endswith("Z"): s = s[:-1] + "+00:00"
    try: return datetime.datetime.fromisoformat(s)
    except Exception: return None

# ---- 收集 + 去重所有近 6 小时的 usage 条目 ----
seen = set()
entries = []   # (ts, i, o, cw, cr, is_cowork, session)
files = []
for root in ROOTS:
    if os.path.isdir(root):
        files += glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)
files = list(dict.fromkeys(files))

for fp in files:
    try:
        if datetime.datetime.fromtimestamp(os.path.getmtime(fp), datetime.timezone.utc) < read_cutoff:
            continue
    except OSError:
        continue
    is_cowork = os.path.basename(fp) == "audit.jsonl"
    try:
        with open(fp, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if '"usage"' not in line or '"input_tokens"' not in line:
                    continue
                try: e = json.loads(line)
                except Exception: continue
                msg = e.get("message")
                if not isinstance(msg, dict): continue
                u = msg.get("usage")
                if not isinstance(u, dict): continue
                ts = parse_ts(e.get("timestamp") or e.get("_audit_timestamp"))
                if ts is None or ts < read_cutoff or ts > now + datetime.timedelta(minutes=5):
                    continue
                uid = msg.get("id") or e.get("request_id") or e.get("requestId") or e.get("uuid")
                if uid:
                    if uid in seen: continue
                    seen.add(uid)
                i  = u.get("input_tokens", 0) or 0
                o  = u.get("output_tokens", 0) or 0
                cw = u.get("cache_creation_input_tokens", 0) or 0
                cr = u.get("cache_read_input_tokens", 0) or 0
                if (i + o + cw + cr) == 0: continue
                entries.append((ts, i, o, cw, cr, is_cowork,
                                e.get("session_id") or e.get("sessionId") or os.path.basename(fp)))
    except OSError:
        continue

entries.sort(key=lambda x: x[0])

# ---- 5 小时 block 检测(ccusage 风格):起点整点对齐,5h 或间隔>5h 即开新档 ----
def floor_hour(t):
    return t.replace(minute=0, second=0, microsecond=0)

blocks = []
cur = None
for ent in entries:
    t = ent[0]
    if cur is None:
        cur = {"start": floor_hour(t), "last": t, "items": [ent]}
    elif (t - cur["start"]) < SESSION and (t - cur["last"]) < SESSION:
        cur["last"] = t; cur["items"].append(ent)
    else:
        blocks.append(cur)
        cur = {"start": floor_hour(t), "last": t, "items": [ent]}
if cur: blocks.append(cur)

# 当前活跃 block = 最近的那个,且最后一条活动距今 < 5h(否则视为闲置、额度已恢复)
active = None
if blocks:
    last = blocks[-1]
    if (now - last["last"]) < SESSION and (last["start"] + SESSION) > now:
        active = last

def human(n):
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000:     return f"{n/1_000:.0f}K"
    return str(n)
def color_for(p):
    if p >= CRIT: return RED
    if p >= WARN: return ORANGE
    return None

if active:
    items = active["items"]
    ti = sum(x[1] for x in items); to = sum(x[2] for x in items)
    tcw = sum(x[3] for x in items); tcr = sum(x[4] for x in items)
    tok = ti + to + tcw + tcr
    n_cli = sum(1 for x in items if not x[5]); n_cw = sum(1 for x in items if x[5])
    sess = len(set(x[6] for x in items))
    reset_at = active["start"] + SESSION
else:
    items = []; ti = to = tcw = tcr = tok = n_cli = n_cw = sess = 0
    reset_at = None

# ---- 先算重置倒计时,菜单栏要用 ----
if reset_at is not None:
    secs = int((reset_at - now).total_seconds())
    rh, rm = max(0,secs)//3600, (max(0,secs)%3600)//60
    loc = reset_at.astimezone()
    same_day = loc.date() == datetime.datetime.now().date()
    when = loc.strftime("%H:%M") if same_day else f"{WEEKDAY[loc.weekday()]} {loc.strftime('%H:%M')}"
    badge_reset = f"{rh}h{rm:02d}m"                       # 菜单栏紧凑版
    reset_long  = f"Resets in {rh} hr {rm:02d} min · {when}"  # 下拉完整版
else:
    badge_reset = "满血"
    reset_long  = None

# ---- 菜单栏徽章:百分比 · 重置倒计时(去掉图标,干净文本) ----
if BUDGET > 0:
    pct = int(round(tok / BUDGET * 100))
    c = color_for(pct)
    head = f"{pct}%  ·  {badge_reset}"
    print(f"{head} | color={c}" if c else head)
else:
    print(f"{human(tok)}  ·  {badge_reset}")

# ---- 下拉详情 ----
print("---")
# 1) 重置倒计时——最显眼的一行
if reset_long is not None:
    print(f"{reset_long} | sfimage=clock size=14")
else:
    print(f"额度已满血 · 近 5 小时无活动 | sfimage=checkmark.circle size=13 color={GRAY}")

# 2) 进度条 + 百分比
print("---")
if BUDGET > 0:
    pctf = tok / BUDGET * 100
    filled = max(0, min(12, round(pctf/100*12)))
    bar = "▰"*filled + "▱"*(12-filled)
    c = color_for(int(round(pctf)))
    print(f"{bar}  {pctf:.0f}% | font=Menlo size=14" + (f" color={c}" if c else ""))
    print(f"{human(tok)} / {human(BUDGET)} tokens | size=11 color={GRAY}")
else:
    print(f"{human(tok)} tokens 已用 | font=Menlo size=14")

# 3) 明细
print("---")
print(f"输入 {human(ti)}　·　输出 {human(to)} | size=12 color={GRAY}")
print(f"缓存读 {human(tcr)}　·　缓存写 {human(tcw)} | size=12 color={GRAY}")
print(f"消息 {len(items)}　·　会话 {sess}　·　CLI {n_cli} / Cowork {n_cw} | size=11 color={GRAY}")

# 4) 操作
print("---")
print("在 claude.ai 查看官方用量 | href=https://claude.ai/settings/usage sfimage=safari")
print("立即刷新 | refresh=true sfimage=arrow.clockwise")
print("---")
print(f"本地估算 · 不含纯网页端 · 更新于 {datetime.datetime.now().strftime('%H:%M')} | size=11 color={GRAY}")
PYEOF
