/**
 * 下載計數轉址器（Cloudflare Worker）
 *
 * 用途：把下載網址 `https://dl.ailoop.uk/<app>/<version>/<檔名>` 記一筆到 D1，
 * 再 302 轉到 GitHub Release 的實際檔案。GitHub 只給總下載數、分不出來源，
 * 經過這裡才能區分 Homebrew 與瀏覽器下載、各版本與國家。
 *
 * 隱私：不存 IP、不存完整 User-Agent，只存「來源類別」與 Cloudflare 判定的國家代碼。
 * 記錄失敗不影響下載——寫入放在 waitUntil 裡，轉址永遠先回。
 */

/** 允許轉址的 App 與對應 GitHub repo；不在表內的一律 404，避免被當成開放轉址器。 */
const APPS = {
  liftoff: { repo: "firstfu/Liftoff", files: ["Liftoff.zip", "Liftoff.zip.sha256"] },
  docklens: { repo: "firstfu/DockLens-app", files: ["DockLens.zip", "DockLens.zip.sha256"] },
};

/** 版本字串只接受 `1.2.3` 這種格式，擋掉路徑注入。 */
const VERSION_RE = /^\d+\.\d+\.\d+$/;

/**
 * 依 User-Agent 粗分下載來源。
 * @param {string} ua 請求的 User-Agent（可能為空字串）
 * @returns {"homebrew"|"browser"|"cli"|"other"} 來源類別
 */
function classify(ua) {
  // Homebrew 下載時的 UA 形如 "Homebrew/4.x.x (Macintosh; ...) curl/8.x"
  if (/Homebrew\//i.test(ua)) return "homebrew";
  if (/Mozilla\//.test(ua)) return "browser";
  if (/curl\/|Wget\//i.test(ua)) return "cli";
  return "other";
}

export default {
  /**
   * @param {Request} request 進來的請求
   * @param {{ DB: D1Database }} env D1 綁定
   * @param {ExecutionContext} ctx 用來在回應送出後才寫入
   * @returns {Promise<Response>} 302 轉到 GitHub，或 404
   */
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // 路徑：/<app>/<version|latest>/<file>
    const [appName, version, file] = url.pathname.split("/").filter(Boolean);
    const app = APPS[appName];
    const versionOK = version === "latest" || VERSION_RE.test(version ?? "");
    if (!app || !versionOK || !app.files.includes(file)) {
      return new Response("Not found\n", { status: 404 });
    }

    const target =
      version === "latest"
        ? `https://github.com/${app.repo}/releases/latest/download/${file}`
        : `https://github.com/${app.repo}/releases/download/v${version}/${file}`;

    // HEAD 是連結檢查器／livecheck 在探測，不算下載
    if (request.method === "GET") {
      const source = url.searchParams.get("src") || classify(request.headers.get("User-Agent") || "");
      ctx.waitUntil(
        env.DB.prepare(
          "INSERT INTO downloads (ts, app, version, file, source, country) VALUES (?, ?, ?, ?, ?, ?)"
        )
          .bind(new Date().toISOString(), appName, version, file, source.slice(0, 32), request.cf?.country ?? null)
          .run()
          .catch((e) => console.error("D1 insert failed", e))
      );
    }

    return Response.redirect(target, 302);
  },
};
