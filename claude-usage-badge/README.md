# Claude 用量徽章（本地版）

菜单栏常驻小徽章，随时估算 Claude Code 最近 5 小时用了多少，不用开网页翻。

```
✳ 5h 45K        ← 最近 5 小时消耗的 token,点开看明细
```

## 为什么是「本地版」

最初这个工具走官方的 `/api/oauth/usage` 接口（和 Claude Code 里 `/usage` 同源）。但 2026 年 Anthropic 收紧了第三方对该接口的访问，你的账号实测持续 429 → 403，整个社区都在报这个问题。所以改成**纯本地方案**：直接读 Claude Code 写在本机的会话日志，零网络请求。

| | 旧·API 版 | 现·本地版 |
|---|---|---|
| 数据来源 | 官方用量接口 | 本机 `~/.claude/projects/**/*.jsonl` |
| 网络请求 | 有，会被限流/封 | **无，永不限流** |
| 覆盖范围 | 全平台（网页+Code） | **Claude Code CLI + Cowork**（不含纯网页/手机端） |
| 精度 | 官方精确值 | 估算（token 计数，趋势准、绝对值有出入） |

诚实地说：本地版是**估算**。它看 Claude Code CLI + Cowork 的本地日志（不含 claude.ai 纯网页/手机端），而且日志本身有已知的轻微少计问题。当**趋势和相对高低**看很好用，别当成精确的官方百分比。

## 安装

双击 `install.command`。或终端：

```bash
bash ~/Documents/GitHub/Claude/claude-usage-badge/install.command
```

会自动：试跑 → 没有 SwiftBar 就装 → 放入插件并启动。本地版不需要任何授权或登录。

## 工作原理（教学向）

1. **日志**：两个来源都写本机磁盘——Claude Code CLI 写 `~/.claude/projects/**/*.jsonl`（时间戳字段 `timestamp`）；Cowork/桌面端写 `~/Library/Application Support/Claude/**/audit.jsonl`（时间戳字段 `_audit_timestamp`）。两者每条 assistant 消息都有 `message.usage`（输入/输出/缓存读/缓存写四类 token）。
2. **聚合**：脚本同时扫这两个目录，挑出最近 5 小时（滚动窗口）的消息，按消息 id 去重（日志会把同一条流式写好几遍），把四类 token 相加。下拉菜单里「来源」一行会显示各算了多少条。
3. **展示**：[SwiftBar](https://swiftbar.app)（免费开源）把脚本输出渲染成菜单栏项目。文件名 `.10s.` = 每 10 秒刷新（纯本地，刷多勤都没代价）。

整个工具就一个带中文注释的 shell 脚本 `claude-usage-local.10s.sh`，可打开学习。

## 百分比与重置时间

徽章默认显示 `✳ 5h 11%`，点开下拉能看到进度条和 **「⏱ N 小时后重置 · HH:MM」**（你的本地时间）。

**重置怎么算的**：官方 5 小时限额不是滚动窗口，而是从你这一档**第一条消息所在整点**算起、5 小时后重置（和 ccusage 的「5 小时 block」一致）。脚本据此推算重置时刻；若最近 5 小时没用过，会显示「额度已满血」。

**百分比怎么校准**：`TOKEN_BUDGET` 默认 `147000000`，是按「16.2M token ≈ 官方 11%」反推的。想更准：

1. 看徽章下拉里当前真实 token 数（如 18.5M），同时看官方 claude.ai 用量页的百分比（如 13%）。
2. 算 `TOKEN_BUDGET = 真实token ÷ (百分比/100)`，例 `18.5M ÷ 0.13 ≈ 142M`。
3. 填进脚本顶部 `TOKEN_BUDGET=`，重跑 `install.command`。

想退回只显 token 数：把 `TOKEN_BUDGET` 设为 `0`。`WARN`/`CRIT`（默认 70/90）控制橙/红变色。

## 自定义

| 变量 | 默认 | 作用 |
|---|---|---|
| `WINDOW_HOURS` | 5 | 滚动窗口小时数 |
| `TOKEN_BUDGET` | 0 | 5 小时 token 预算，0=只显数字，>0=显百分比 |
| `WARN` / `CRIT` | 70 / 90 | 百分比变橙 / 变红阈值 |

刷新频率：默认 10 秒（文件名 `.10s.`，实用下限）。想更省改 `.1m.`。日志按每轮对话写入，再低于 10 秒只是反复读到同一个数。

## 故障排查

| 现象 | 处理 |
|---|---|
| `✳ 无日志` | 还没用过 Claude Code，或日志不在默认路径。用 Claude Code 聊几句即可 |
| token 数偏低 | 正常——Claude Code 日志有已知少计问题，且只统计 Code 不含网页端 |
| 菜单栏没出现 | SwiftBar → Preferences 确认插件目录是 `~/Library/Application Support/SwiftBar/Plugins` |

**更新插件**：改了脚本后重跑 `install.command` 即可覆盖。

## 卸载

```bash
rm "$HOME/Library/Application Support/SwiftBar/Plugins/claude-usage-local.10s.sh"
```

本地版纯读日志、不发任何网络请求、不碰你的登录凭证，无条款风险。
