-- 下載紀錄表：一列一次下載（GET）。不存 IP 與完整 User-Agent。
CREATE TABLE IF NOT EXISTS downloads (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  ts      TEXT NOT NULL,  -- ISO 8601（UTC）
  app     TEXT NOT NULL,  -- 例：liftoff
  version TEXT NOT NULL,  -- 例：1.2.0 或 latest
  file    TEXT NOT NULL,  -- 例：Liftoff.zip
  source  TEXT NOT NULL,  -- homebrew / browser / cli / other，或 ?src= 指定
  country TEXT            -- Cloudflare 判定的國家代碼
);
CREATE INDEX IF NOT EXISTS idx_downloads_app_ts ON downloads (app, ts);
