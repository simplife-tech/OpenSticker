(() => {
  "use strict";

  const api = window.Sticker;
  const zh = (api.locale ?? "zh-Hans") === "zh-Hans";
  const t = (chinese, english) => zh ? chinese : english;

  function parseTime(input) {
    const text = input.trim();
    if (!text) return null;

    const timestamp = /^([+-]?\d+)\s*(ms|s)?$/i.exec(text);
    if (timestamp) {
      const [, digits, unit] = timestamp;
      const number = Number(digits);
      if (!Number.isSafeInteger(number)) return null;
      // Short historical millisecond values can be disambiguated with an explicit suffix.
      const asMilliseconds = unit ? unit.toLowerCase() === "ms" : Math.abs(number) >= 1e10;
      const date = new Date(number * (asMilliseconds ? 1 : 1000));
      return Number.isFinite(date.getTime()) ? date : null;
    }

    const match = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|[+-]\d{2}:?\d{2})?)?$/i.exec(text);
    if (!match) return null;
    const [, y, m, d, h = "0", min = "0", s = "0", fraction = "", zone] = match;
    const [year, month, day, hour, minute, second] = [y, m, d, h, min, s].map(Number);
    const millis = Number(fraction.padEnd(3, "0"));
    const date = new Date(0);
    if (zone) {
      date.setUTCFullYear(year, month - 1, day);
      date.setUTCHours(hour, minute, second, millis);
      if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day ||
          date.getUTCHours() !== hour || date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) return null;
      if (zone.toUpperCase() !== "Z") {
        const offset = zone.slice(1).replace(":", "");
        const hours = Number(offset.slice(0, 2));
        const minutes = Number(offset.slice(2));
        if (hours > 23 || minutes > 59) return null;
        const sign = zone.startsWith("-") ? -1 : 1;
        date.setTime(date.getTime() - sign * (hours * 60 + minutes) * 60_000);
      }
      return date;
    }

    date.setFullYear(year, month - 1, day);
    date.setHours(hour, minute, second, millis);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day ||
        date.getHours() !== hour || date.getMinutes() !== minute || date.getSeconds() !== second) return null;
    return date;
  }

  function readable(date, includeMilliseconds = false) {
    const pad = (value, width = 2) => String(value).padStart(width, "0");
    const year = date.getFullYear();
    const yearText = year >= 0 && year <= 9999 ? pad(year, 4) : String(year);
    const calendar = [yearText, pad(date.getMonth() + 1), pad(date.getDate())].join("-");
    const clock = [date.getHours(), date.getMinutes(), date.getSeconds()].map(value => pad(value)).join(":");
    const fraction = includeMilliseconds ? "." + pad(date.getMilliseconds(), 3) : "";
    return calendar + " " + clock + fraction;
  }

  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  }

  const app = document.querySelector("#app");
  const header = element("header");
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const zoneLabel = element("span", t("本地时间", "Local time"), "zone");
  zoneLabel.title = zone;
  header.append(element("h2", t("时间戳转换", "Timestamp Converter")), zoneLabel);

  const form = element("form");
  const input = element("input");
  input.type = "text";
  input.spellcheck = false;
  input.placeholder = t("时间戳或日期时间", "Timestamp or date");
  input.setAttribute("aria-label", input.placeholder);
  input.value = api.get("input");
  const now = element("button", t("现在", "Now"), "now");
  now.type = "button";
  form.append(input, now);
  const result = element("div", "", "results");
  const hint = element("p");
  hint.id = "hint";
  hint.setAttribute("aria-live", "polite");
  app.append(header, form, result, hint);

  const examples = t("也可在数字后加 s 或 ms 指定单位。", "Add s or ms to specify the unit.");
  let feedbackTimer;

  function row(label, value) {
    const button = element("button", "", "row");
    button.type = "button";
    button.append(element("span", label, "label"), element("span", value, "value"));
    const icon = element("span", "⧉", "copy-icon");
    icon.setAttribute("aria-hidden", "true");
    button.append(icon);
    button.title = t("复制", "Copy") + " " + value;
    button.addEventListener("click", () => {
      api.copy(value);
      hint.textContent = t("已复制", "Copied");
      clearTimeout(feedbackTimer);
      feedbackTimer = setTimeout(() => { hint.textContent = ""; }, 900);
    });
    return button;
  }

  function render() {
    clearTimeout(feedbackTimer);
    result.replaceChildren();
    const date = parseTime(input.value);
    if (!date) {
      hint.textContent = input.value.trim()
        ? t("请输入时间戳或 YYYY-MM-DD HH:mm:ss。", "Enter a timestamp or YYYY-MM-DD HH:mm:ss.")
        : examples;
      return;
    }
    hint.textContent = "";
    const milliseconds = date.getTime();
    result.append(row(t("时间", "Date"), readable(date)),
                  row(t("时间（毫秒）", "Date (ms)"), readable(date, true)),
                  row(t("秒", "s"), String(Math.floor(milliseconds / 1000))),
                  row(t("毫秒", "ms"), String(milliseconds)));
  }

  function update() {
    api.set("input", input.value);
    render();
  }

  input.addEventListener("input", update);
  now.addEventListener("click", () => {
    input.value = String(Math.floor(Date.now() / 1000));
    update();
  });
  form.addEventListener("submit", event => event.preventDefault());
  render();
})();
