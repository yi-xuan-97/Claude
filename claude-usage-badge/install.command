#!/bin/bash
# Claude 用量徽章(本地版)一键安装
# 双击运行(或终端: bash install.command)
# 纯本地估算,不碰网络。做三件事:试跑一次 → 装 SwiftBar(如无)→ 装入插件并启动。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/claude-usage-local.10s.sh"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo
bold "== Claude 用量徽章(本地版)安装 =="
echo "  纯本地读 Claude Code 会话日志估算用量,零网络请求,永不限流。"
echo

# ---------- 1. 试跑 ----------
bold "[1/3] 试跑一次"
chmod +x "$PLUGIN_SRC" 2>/dev/null
FIRST_LINE="$(bash "$PLUGIN_SRC" 2>/dev/null | head -n 1)"
if [ -n "$FIRST_LINE" ]; then
  ok "脚本输出:$FIRST_LINE"
else
  warn "脚本没输出,装好后再排查(见 README)"
fi
echo

# ---------- 2. 安装 SwiftBar ----------
bold "[2/3] 检查 SwiftBar"
if [ -d "/Applications/SwiftBar.app" ] || [ -d "$HOME/Applications/SwiftBar.app" ]; then
  ok "SwiftBar 已安装"
elif command -v brew >/dev/null 2>&1; then
  echo "  用 Homebrew 安装 SwiftBar(免费开源)..."
  if brew install --cask swiftbar; then
    ok "SwiftBar 安装完成"
  else
    fail "Homebrew 安装失败,请手动下载: https://swiftbar.app"
    read -r -p "按回车退出..."; exit 1
  fi
else
  echo "  没有 Homebrew,从 GitHub 下载 SwiftBar..."
  ZIP_URL="$(curl -fsSL https://api.github.com/repos/swiftbar/SwiftBar/releases/latest \
    | /usr/bin/python3 -c 'import sys,json;print(next((a["browser_download_url"] for a in json.load(sys.stdin).get("assets",[]) if a["name"].lower().endswith(".zip")),""))' 2>/dev/null)"
  if [ -n "$ZIP_URL" ] && curl -fL -o /tmp/SwiftBar.zip "$ZIP_URL"; then
    ditto -xk /tmp/SwiftBar.zip /Applications && rm -f /tmp/SwiftBar.zip
    [ -d "/Applications/SwiftBar.app" ] && ok "SwiftBar 已装到 /Applications" || { fail "解压失败,手动下载: https://swiftbar.app"; read -r -p "按回车退出..."; exit 1; }
  else
    fail "下载失败,请手动装: https://swiftbar.app ,装好后重跑本脚本"
    read -r -p "按回车退出..."; exit 1
  fi
fi
echo

# ---------- 3. 装入插件并启动 ----------
bold "[3/3] 装入插件并启动 SwiftBar"
mkdir -p "$PLUGIN_DIR"
defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR" 2>/dev/null
rm -f "$PLUGIN_DIR"/claude-usage*.sh   # 清掉任何旧版本,避免重复徽章
cp "$PLUGIN_SRC" "$PLUGIN_DIR/"
chmod +x "$PLUGIN_DIR/claude-usage-local.10s.sh"
ok "插件已放入:$PLUGIN_DIR"
# 让 SwiftBar 重新加载插件目录(如果已在运行,确保换上新版而非缓存)
osascript -e 'quit app "SwiftBar"' 2>/dev/null; sleep 1
open -a SwiftBar
ok "SwiftBar 已启动"
echo
bold "完成!菜单栏右上角应出现「✳ 5h ..%」徽章。"
echo "  · 若 SwiftBar 问插件文件夹 → 选 $PLUGIN_DIR"
echo "  · 显示当前 5 小时档的百分比 + 重置时间,点徽章看明细"
echo "  · 每 10 秒自动刷新;想立刻更新就点徽章→立即刷新"
echo
read -r -p "按回车关闭本窗口..."
