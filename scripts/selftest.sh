#!/bin/zsh
# selftest.sh：以 open 啟動 Liftoff 自我測試（讓 TCC 以 Liftoff 自身身分判斷權限），同步錄下日誌並印出報告
# 用法：scripts/selftest.sh [App 路徑] [模式]；模式 preview = 只測視窗縮圖預覽（report-preview.json）
set -u
APP=${1:-build/Build/Products/Debug/Liftoff.app}
MODE=${2:-full}
FLAG=--selftest
REPORT=report.json
if [[ $MODE == preview ]]; then FLAG=--selftest-preview; REPORT=report-preview.json; fi
OUT=~/Library/Caches/com.firstfu.Liftoff/selftest
LOG=${TMPDIR:-/tmp}/liftoff-selftest.log
pkill -x Liftoff; sleep 0.5
/usr/bin/log stream --predicate 'subsystem == "com.firstfu.Liftoff"' --level debug --style compact > "$LOG" 2>&1 &
LOGPID=$!
sleep 1
open -n "$APP" --args $FLAG
for i in $(seq 1 90); do sleep 1; pgrep -x Liftoff >/dev/null || break; done
sleep 1; kill $LOGPID 2>/dev/null
sed -E 's/^[0-9-]+ ([0-9:.]+) +[A-Za-z]+ +Liftoff\[[0-9:a-f]+\] /\1 /' "$LOG" | grep -v "^Filtering\|^Timestamp"
echo "=== report ==="; cat $OUT/$REPORT
