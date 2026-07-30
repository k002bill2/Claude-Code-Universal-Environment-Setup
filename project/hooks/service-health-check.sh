#!/bin/bash
# ============================================================================
# service-health-check.sh — Stop 훅 (advisory) / 수동 실행 가능
# ----------------------------------------------------------------------------
# 출처: docs/Claude code system setup/PM2 백엔드 디버깅.md
#       "🪝 PM2 + Hooks 연동 — 서비스 상태 체크 Hook" (serviceHealthCheck.ts)
#       문서의 onStopEvent 를 그대로 따라 Stop 이벤트에 배선한다.
#
# 계약(Claude Code 훅):
#   - stdin 으로 Stop 이벤트 JSON 을 받는다(내용은 사용하지 않아도 무해).
#   - stdout 출력은 advisory 컨텍스트로 주입된다.
#   - 항상 exit 0.
#   - jq 또는 pm2 가 없으면 조용한 no-op (graceful).
#   - 터미널에서 인자·stdin 없이 직접 실행해도 동일하게 동작한다.
#
# 판정 기준(문서와 동일): status != online 이거나 restart_time > 5 인 서비스.
#
# 제약: bash 3.2 호환, 모든 경로 인용.
# ============================================================================

# jq/pm2 부재 → 조용한 no-op. (stdin 을 소비하기 전에 가장 먼저 판정한다.)
command -v jq  >/dev/null 2>&1 || exit 0
command -v pm2 >/dev/null 2>&1 || exit 0

if [ ! -t 0 ]; then
  cat > /dev/null   # stdin JSON 소비 (필드는 사용하지 않음)
fi

PM2_TIMEOUT="${CLAUDE_HOOK_PM2_TIMEOUT:-10}"
RESTART_THRESHOLD="${CLAUDE_HOOK_PM2_RESTART_THRESHOLD:-5}"

OUT_FILE="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$OUT_FILE"' EXIT INT TERM

# 유계 실행: coreutils timeout 비의존. exec 로 PID 를 pm2 자신으로 만든다.
( exec pm2 jlist ) > "$OUT_FILE" 2>/dev/null &
PM2_PID=$!
WAITED=0
while kill -0 "$PM2_PID" 2>/dev/null; do
  if [ "$WAITED" -ge "$PM2_TIMEOUT" ]; then
    kill -TERM "$PM2_PID" 2>/dev/null
    sleep 1
    kill -KILL "$PM2_PID" 2>/dev/null
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
wait "$PM2_PID" 2>/dev/null

PROBLEMS="$(jq -r --argjson threshold "$RESTART_THRESHOLD" '
  [ .[]? | select(((.pm2_env.status // "") != "online") or ((.pm2_env.restart_time // 0) > $threshold))
    | "  - \(.name // "unknown"): \(.pm2_env.status // "unknown") (재시작 \(.pm2_env.restart_time // 0)회)" ] | .[]
' "$OUT_FILE" 2>/dev/null)"

if [ -n "$PROBLEMS" ]; then
  echo "[SERVICE HEALTH CHECK]"
  echo "PM2 서비스 이상 감지:"
  printf '%s\n' "$PROBLEMS"
  echo "확인: pm2 logs <name> --lines 200 / pm2 restart <name>"
  echo "(advisory: 리마인더일 뿐 작업을 차단하지 않음)"
fi

exit 0
