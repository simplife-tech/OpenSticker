(() => {
  "use strict";
  const api = window.Sticker;
  const t = (zh, en) => api.locale === "en" ? en : zh;
  const app = document.querySelector("#app");
  const title = document.createElement("h2");
  title.textContent = t("共享配置示例", "Shared Settings Example");
  const button = document.createElement("button");
  button.textContent = t("检查配置", "Check Settings");
  const results = document.createElement("ul");
  results.setAttribute("aria-live", "polite");
  app.append(title, button, results);

  button.addEventListener("click", async () => {
    button.disabled = true;
    results.replaceChildren();
    try {
      for (const key of ["example/username", "example/password", "example/api_key"]) {
        const row = document.createElement("li");
        let status;
        try {
          status = await api.config.get(key) === null
            ? t("未配置", "Not configured")
            : t("已配置", "Configured");
        } catch {
          status = t("未授权或无法读取", "No access or unreadable");
        }
        row.textContent = key + " · " + status;
        results.append(row);
      }
    } finally {
      button.disabled = false;
    }
  });
})();
