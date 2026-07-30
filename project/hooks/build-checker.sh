#!/bin/bash
# ============================================================================
# build-checker.sh — PostToolUse 훅 (advisory)
# ----------------------------------------------------------------------------
# 출처: docs/Claude code system setup/Skills 자동 활성화 시스템.md
#       "Step 6: Build Checker Hook" (buildChecker.ts 개념)
#
# 계약(Claude Code 훅):
#   - stdin 으로 PostToolUse 이벤트 JSON 을 받는다 (.tool_input.file_path 사용).
#   - stdout 출력은 advisory 컨텍스트로 주입된다.
#   - 항상 exit 0 — 도구 실행 결과를 뒤집지 않는다.
#   - jq 가 없으면 조용한 no-op (graceful).
#
# 개념 대비 의도적 단순화:
#   - `npm run build` 대신 타입 검사(tsc --noEmit)만 수행 — 훅은 매 편집마다
#     발화하므로 전체 빌드는 비용이 과하다.
#   - `npx tsc` 를 쓰지 않는다. npx 는 로컬에 typescript 가 없으면 레지스트리에서
#     내려받는다(훅이 네트워크를 타는 사고). 반드시 node_modules/.bin/tsc 가
#     실행 가능할 때만 그 바이너리를 직접 실행하고, 아니면 no-op.
#   - 타임아웃(기본 20초, CLAUDE_HOOK_BUILD_TIMEOUT) 초과 시 프로세스를 종료하고
#     안내만 출력한다.
#
# 제약: bash 3.2 호환(coreutils timeout 비의존), 모든 경로 인용.
# ============================================================================

# jq 부재 → 조용한 no-op. (stdin 을 소비하기 전에 가장 먼저 판정한다.)
command -v jq >/dev/null 2>&1 || exit 0

INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat)"
fi
[ -n "$INPUT" ] || exit 0

# 편집 대상이 TypeScript 파일일 때만 동작
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# 프로젝트 루트 앵커: CLAUDE_PROJECT_DIR → stdin 의 .cwd → 현재 디렉토리
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
fi
[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || exit 0

# 해당 프로젝트일 때만: package.json + tsconfig.json + 로컬 tsc 바이너리
[ -f "${ROOT}/package.json" ]  || exit 0
[ -f "${ROOT}/tsconfig.json" ] || exit 0
TSC_BIN="${ROOT}/node_modules/.bin/tsc"
[ -x "$TSC_BIN" ] || exit 0

BUILD_TIMEOUT="${CLAUDE_HOOK_BUILD_TIMEOUT:-20}"

OUT_FILE="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$OUT_FILE"' EXIT INT TERM

# 유계 실행: coreutils timeout 이 없는 macOS 기본 환경을 가정한다.
# 서브셸에서 exec 로 대체해 PID 가 tsc 자신이 되게 한다(래퍼가 남으면 kill 이 헛돈다).
( cd "$ROOT" && exec "$TSC_BIN" --noEmit -p "${ROOT}/tsconfig.json" ) > "$OUT_FILE" 2>&1 &
BUILD_PID=$!
WAITED=0
TIMED_OUT=false
while kill -0 "$BUILD_PID" 2>/dev/null; do
  if [ "$WAITED" -ge "$BUILD_TIMEOUT" ]; then
    kill -TERM "$BUILD_PID" 2>/dev/null
    sleep 1
    kill -KILL "$BUILD_PID" 2>/dev/null
    TIMED_OUT=true
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
wait "$BUILD_PID" 2>/dev/null
BUILD_RC=$?

if $TIMED_OUT; then
  echo "[BUILD CHECK] 타입 검사가 ${BUILD_TIMEOUT}초 내에 끝나지 않아 중단했습니다 (advisory)."
  exit 0
fi

ERROR_COUNT="$(grep -cE 'error TS[0-9]+' "$OUT_FILE" 2>/dev/null | tr -d ' ')"
[ -n "$ERROR_COUNT" ] || ERROR_COUNT=0

if [ "$ERROR_COUNT" -eq 0 ]; then
  if [ "$BUILD_RC" -eq 0 ]; then
    echo "[BUILD CHECK] 타입 오류 없음 (tsc --noEmit)"
  else
    echo "[BUILD CHECK] tsc 실행이 실패했습니다 (exit ${BUILD_RC}) — tsconfig/의존성을 확인하세요 (advisory)."
  fi
elif [ "$ERROR_COUNT" -lt 5 ]; then
  echo "[BUILD CHECK] TypeScript 오류 ${ERROR_COUNT}건:"
  grep -E 'error TS[0-9]+' "$OUT_FILE" 2>/dev/null | head -n 5
  echo "(advisory: 계속 진행하기 전에 위 오류를 수정하세요)"
else
  echo "[BUILD CHECK] TypeScript 오류 ${ERROR_COUNT}건 발생 — 개별 수정보다 일괄 해결을 검토하세요."
  grep -E 'error TS[0-9]+' "$OUT_FILE" 2>/dev/null | head -n 3
  echo "(advisory: 상위 3건만 표시)"
fi

exit 0
