#!/bin/bash
# ============================================================================
# post-tool-failure.sh — PostToolUseFailure 훅 (advisory)
# ----------------------------------------------------------------------------
# 출처: docs/Claude code system setup/Skills 자동 활성화 시스템.md
#       "Step 5: PostToolUseFailure Hook" (postToolUseFailure.ts 개념)
#       — PostToolUseFailure 는 도구 호출 실패 시 발화한다("세션 비정상 종료" 아님).
#
# 계약(Claude Code 훅):
#   - stdin 으로 PostToolUseFailure 이벤트 JSON 을 받는다.
#   - stdout 출력은 advisory 컨텍스트로 주입된다.
#   - 항상 exit 0.
#   - jq 또는 pm2 가 없으면 조용한 no-op (graceful).
#
# 개념 대비 의도적 단순화:
#   - 이 훅은 pm2-hooks 조각(--with-pm2) 소속이므로 pm2 가 없으면 아무것도
#     출력하지 않는다. 문서의 무조건 체크리스트 출력은 pm2 게이트 아래로 옮겼다.
#   - pm2 jlist 는 유계 실행(기본 10초, CLAUDE_HOOK_PM2_TIMEOUT).
#
# 제약: bash 3.2 호환, 모든 경로 인용.
# ============================================================================

# jq/pm2 부재 → 조용한 no-op. (stdin 을 소비하기 전에 가장 먼저 판정한다.)
command -v jq  >/dev/null 2>&1 || exit 0
command -v pm2 >/dev/null 2>&1 || exit 0

INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat)"
fi

TOOL_NAME=""
if [ -n "$INPUT" ]; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
fi

echo "[TOOL EXECUTION FAILED]"
if [ -n "$TOOL_NAME" ]; then
  echo "실패한 도구: ${TOOL_NAME}"
fi
echo "확인 순서: 1) 도구 이름·인자  2) .claude/settings.json 의 permissions  3) 의존성 설치(jq, node 등)"

PM2_TIMEOUT="${CLAUDE_HOOK_PM2_TIMEOUT:-10}"

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

PROBLEMS="$(jq -r '
  [ .[]? | select(((.pm2_env.status // "") != "online"))
    | "  - \(.name // "unknown"): \(.pm2_env.status // "unknown")" ] | .[]
' "$OUT_FILE" 2>/dev/null)"

if [ -n "$PROBLEMS" ]; then
  echo "PM2 서비스 이상:"
  printf '%s\n' "$PROBLEMS"
fi
echo "(advisory: 리마인더일 뿐 작업을 차단하지 않음)"

exit 0
