#!/bin/zsh
# 查下載統計：依來源、版本、國家各列一張表。
# 用法：workers/download-counter/stats.sh [app]（liftoff 或 docklens，預設 liftoff）
set -euo pipefail
cd "${0:A:h}"
app="${1:-liftoff}"

# 以 --json 取結果再排成 tab 分隔表格（wrangler 的框線表格格式會隨版本變）
q() {
  npx --yes wrangler@4 d1 execute download-counter --remote --json --command "$1" 2>/dev/null |
    python3 -c 'import json,sys
rows=json.load(sys.stdin)[0]["results"]
if not rows: print("（無資料）"); sys.exit()
print("\t".join(rows[0])); [print("\t".join(str(v) for v in r.values())) for r in rows]'
}

echo "== 依來源（$app）"
q "SELECT source, COUNT(*) AS n FROM downloads WHERE app='$app' AND file LIKE '%.zip' GROUP BY source ORDER BY n DESC"
echo "== 依版本"
q "SELECT version, source, COUNT(*) AS n FROM downloads WHERE app='$app' AND file LIKE '%.zip' GROUP BY version, source ORDER BY version DESC"
echo "== 依國家"
q "SELECT country, COUNT(*) AS n FROM downloads WHERE app='$app' AND file LIKE '%.zip' GROUP BY country ORDER BY n DESC LIMIT 20"
echo "== 最近 14 天每日"
q "SELECT substr(ts,1,10) AS day, COUNT(*) AS n FROM downloads WHERE app='$app' AND file LIKE '%.zip' AND ts >= date('now','-14 day') GROUP BY day ORDER BY day"
