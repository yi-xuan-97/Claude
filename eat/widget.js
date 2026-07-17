// ============================================================
// 🍚 我的一周吃什么 · iPhone 桌面小组件（Scriptable 脚本）
// 用法：App Store 装免费的 Scriptable → 新建脚本粘贴全部代码
//       → 桌面长按空白处 → 添加小组件 → 选 Scriptable → 选这个脚本
// 小、中、大三种尺寸都支持；点小组件直接打开菜单网站
// ============================================================

// ── 你可以改的配置 ──────────────────────────────
const ANCHOR = "2026-07-13";  // 第1周的周一（想手动换周就改这个日期）
const MODE = "today";         // "today" = 显示今天菜单 | "random" = 每次刷新随机抽一道
const DATA_URL = "https://yi-xuan-97.github.io/Claude/eat/meals.json";
const SITE_URL = "https://yi-xuan-97.github.io/Claude/eat/";
const PICK_URL = "https://yi-xuan-97.github.io/Claude/eat/pick.html";
// ────────────────────────────────────────────────

const fm = FileManager.local();
const cachePath = fm.joinPath(fm.cacheDirectory(), "meals-cache.json");

async function loadData() {
  try {
    const j = await new Request(DATA_URL).loadJSON();
    fm.writeString(cachePath, JSON.stringify(j));
    return j;
  } catch (e) {
    if (fm.fileExists(cachePath)) return JSON.parse(fm.readString(cachePath));
    return null;
  }
}

function todayInfo(data) {
  const a = ANCHOR.split("-");
  const anchor = new Date(parseInt(a[0]), parseInt(a[1]) - 1, parseInt(a[2]));
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let days = Math.round((today - anchor) / 86400000);
  if (days < 0) days = 0;
  const wi = Math.floor(days / 7) % data.weeks.length;
  const di = days % 7;
  return { week: data.weeks[wi], day: data.weeks[wi].days[di] };
}

// 颜色（自动适配深色模式）
const C = {
  bgTop: Color.dynamic(new Color("#FAF6EF"), new Color("#241F18")),
  bgBot: Color.dynamic(new Color("#F1E7D6"), new Color("#17140F")),
  ink:  Color.dynamic(new Color("#2A2622"), new Color("#ECE4D6")),
  soft: Color.dynamic(new Color("#6D655A"), new Color("#A99E8C")),
  clay: Color.dynamic(new Color("#B5643C"), new Color("#D98A5B")),
  sage: Color.dynamic(new Color("#5F6B49"), new Color("#93A06B")),
};

function mealRow(w, label, text, color, size) {
  const row = w.addStack();
  row.centerAlignContent();
  const b = row.addStack();
  b.backgroundColor = color;
  b.cornerRadius = 6;
  b.setPadding(2, 6, 2, 6);
  const bt = b.addText(label);
  bt.font = Font.boldSystemFont(10);
  bt.textColor = Color.white();
  row.addSpacer(7);
  const t = row.addText(text);
  t.font = Font.mediumSystemFont(size);
  t.textColor = C.ink;
  t.lineLimit = 2;
  t.minimumScaleFactor = 0.8;
}

async function makeWidget() {
  const w = new ListWidget();
  const grad = new LinearGradient();
  grad.colors = [C.bgTop, C.bgBot];
  grad.locations = [0, 1];
  w.backgroundGradient = grad;
  w.setPadding(13, 14, 13, 14);

  const data = await loadData();
  const fam = (config.widgetFamily || "medium");

  if (!data) {
    const t = w.addText("🍚 打开一次网络后就能用啦");
    t.font = Font.systemFont(13);
    t.textColor = C.soft;
    w.url = SITE_URL;
    return w;
  }

  if (MODE === "random") {
    // 随机抽一道
    const name = data.all[Math.floor(Math.random() * data.all.length)];
    const h = w.addText("🎲 今天试试");
    h.font = Font.boldSystemFont(12);
    h.textColor = C.clay;
    w.addSpacer(6);
    const n = w.addText(name);
    n.font = Font.boldSystemFont(fam === "small" ? 16 : 20);
    n.textColor = C.ink;
    n.lineLimit = 3;
    n.minimumScaleFactor = 0.7;
    w.addSpacer();
    const f = w.addText("点我换一道 / 看做法 ›");
    f.font = Font.systemFont(10);
    f.textColor = C.soft;
    w.url = PICK_URL;
  } else {
    // 今天该吃什么
    const info = todayInfo(data);
    const head = w.addStack();
    head.centerAlignContent();
    const h1 = head.addText("🍚 第" + info.week.n + "周·" + info.week.theme);
    h1.font = Font.boldSystemFont(11);
    h1.textColor = C.clay;
    head.addSpacer();
    const h2 = head.addText("周" + info.day.d);
    h2.font = Font.boldSystemFont(11);
    h2.textColor = C.soft;
    w.addSpacer(8);

    if (fam === "small") {
      const lab = w.addText("今晚吃");
      lab.font = Font.systemFont(10);
      lab.textColor = C.soft;
      w.addSpacer(3);
      const d = w.addText(info.day.dinner.replace(/ \+ /g, "\n+ "));
      d.font = Font.boldSystemFont(14);
      d.textColor = C.ink;
      d.lineLimit = 4;
      d.minimumScaleFactor = 0.7;
    } else {
      if (fam === "large") {
        mealRow(w, "早", info.day.bf, C.soft, 14);
        w.addSpacer(8);
      }
      mealRow(w, "午", info.day.lunch, C.sage, fam === "large" ? 15 : 13);
      w.addSpacer(fam === "large" ? 8 : 6);
      mealRow(w, "晚", info.day.dinner, C.clay, fam === "large" ? 16 : 13);
      w.addSpacer();
      const f = w.addText("点开看做法 · 买菜清单 ›");
      f.font = Font.systemFont(9);
      f.textColor = C.soft;
    }
    w.url = SITE_URL;
  }

  // 每小时自动刷新一次
  w.refreshAfterDate = new Date(Date.now() + 60 * 60 * 1000);
  return w;
}

const widget = await makeWidget();
if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
