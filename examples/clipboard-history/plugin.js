(() => {
  "use strict";
  const api = window.Sticker;
  const zh = (api.locale ?? "zh-Hans") === "zh-Hans";
  const t = (chinese, english) => zh ? chinese : english;
  const app = document.querySelector("#app");

  function element(tag, text) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    return node;
  }

  if (api.mode === "create" || !api.history) {
    app.append(element("p", api.mode === "create"
      ? t("创建后即可开启记录，搜索并重新复制最近的纯文本。", "After creating the sticker, start recording to search and copy recent text.")
      : t("请更新 OpenSticker 以使用剪贴板历史。", "Update OpenSticker to use Clipboard History.")));
    return;
  }

  const header = element("header");
  const toggle = element("button");
  const search = element("input");
  search.type = "search";
  search.placeholder = t("搜索历史…", "Search history…");
  search.setAttribute("aria-label", search.placeholder);
  const meta = element("div");
  meta.className = "meta";
  const status = element("span");
  status.id = "status";
  const clear = element("button", t("清空", "Clear"));
  const items = element("div");
  items.id = "items";
  header.append(element("h2", t("剪贴板历史", "Clipboard History")), toggle);
  meta.append(status, clear);
  app.append(header, search, meta, items);

  let snapshot = { authorized: false, recording: false, entries: [] };
  let copied;
  let copiedTimer;
  toggle.addEventListener("click", () => api.history.perform(snapshot.recording ? "pause" : "start"));
  clear.addEventListener("click", () => api.history.perform("clear"));
  search.addEventListener("input", render);

  function render() {
    toggle.textContent = snapshot.recording ? t("暂停", "Pause")
      : snapshot.authorized ? t("继续", "Resume") : t("开启", "Start");
    status.textContent = snapshot.recording ? t("正在记录 · 仅本次运行", "Recording · this session only")
      : snapshot.authorized ? t("已暂停", "Paused") : t("尚未开启", "Not enabled");
    clear.disabled = !snapshot.entries.length;
    const query = search.value.trim().toLowerCase();
    const entries = snapshot.entries.filter(entry => entry.text.toLowerCase().includes(query));
    items.replaceChildren();
    for (const entry of entries) {
      const button = element("button", copied === entry.id
        ? t("已复制", "Copied") : entry.text.replace(/\s+/gu, " ").trim());
      if (copied === entry.id) button.dataset.copied = "";
      button.addEventListener("click", () => {
        api.history.perform("copy", entry.id);
        copied = entry.id;
        render();
        clearTimeout(copiedTimer);
        copiedTimer = setTimeout(() => { copied = undefined; render(); }, 900);
      });
      items.append(button);
    }
    if (!entries.length) {
      items.append(element("p", query ? t("没有匹配结果", "No matches")
        : snapshot.authorized ? t("复制一段文字，它会出现在这里。", "Copied text will appear here.")
        : t("开启后，最近 50 条纯文本会保存在本次运行的内存中。", "Start to keep the last 50 plain-text entries in memory for this session.")));
    }
  }

  window.addEventListener("sticker-history", event => {
    if (JSON.stringify(event.detail) === JSON.stringify(snapshot)) return;
    snapshot = event.detail;
    render();
  });
  render();
  api.history.refresh();
  setInterval(() => api.history.refresh(), 800);
})();
