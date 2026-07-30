#!/bin/bash
# ============================================================================
# stop-self-check.sh — Stop 이벤트 훅 (advisory)
# ----------------------------------------------------------------------------
# 출처: docs/Claude code system setup/Skills 자동 활성화 시스템.md
#       "Step 3: Stop / PostToolUseFailure Event Hook" (stopEvent.ts 개념)
#
# 계약(Claude Code 훅):
#   - stdin 으로 Stop 이벤트 JSON 을 받는다.
#   - stdout 출력은 advisory 컨텍스트로 주입된다.
#   - 항상 exit 0 — 세션을 절대 차단하지 않는다.
#   - jq 가 없으면 조용한 no-op (graceful).
#
# 개념 대비 의도적 단순화:
#   - TS 개념의 context.getEditedFiles() 는 bash 에 없다. 대신 git 작업트리의
#     변경분(unstaged + staged + untracked)을 "편집된 파일"의 근사로 쓴다.
#     git 저장소가 아니면 no-op.
#   - 파일 스캔은 3중 상한(파일 수 50개 / 파일당 256KB / 전체 경과 3초)까지만.
#     바이너리는 grep -I 로 제외. Stop 이벤트가 대형 파일 때문에 지연되면 안 된다.
#
# 제약: bash 3.2 호환, 모든 경로 인용.
# ============================================================================

# jq 부재 → 조용한 no-op. (stdin 을 소비하기 전에 가장 먼저 판정한다.)
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat)"
fi

# 재진입 방지: 이 훅 때문에 계속된 세션이면 조용히 종료
if [ -n "$INPUT" ]; then
  STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  if [ "$STOP_ACTIVE" = "true" ]; then
    exit 0
  fi
fi

# 프로젝트 루트 앵커: CLAUDE_PROJECT_DIR → stdin 의 .cwd → 현재 디렉토리
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] && [ -n "$INPUT" ]; then
  ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
fi
[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || exit 0

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$TOP" ] || exit 0

MAX_FILES="${CLAUDE_HOOK_MAX_FILES:-50}"
# 파일 수만으로는 스캔 비용이 묶이지 않는다(대형 텍스트 1개로도 지연). 크기·시간도 묶는다.
MAX_BYTES="${CLAUDE_HOOK_MAX_BYTES:-262144}"   # 파일당 상한(256KB). 초과분은 스킵
MAX_SECONDS="${CLAUDE_HOOK_MAX_SECONDS:-3}"    # 전체 스캔 경과 상한(초). 초과 시 조기 종료
case "$MAX_BYTES" in ''|*[!0-9]*) MAX_BYTES=262144 ;; esac
case "$MAX_SECONDS" in ''|*[!0-9]*) MAX_SECONDS=3 ;; esac

CHANGED_LIST="$(mktemp 2>/dev/null)" || exit 0
EXISTING_LIST="$(mktemp 2>/dev/null)" || { rm -f "$CHANGED_LIST"; exit 0; }
trap 'rm -f "$CHANGED_LIST" "$EXISTING_LIST"' EXIT INT TERM

# 변경 파일 수집. 커밋이 0개인 저장소에서도 안전하도록 HEAD 를 참조하지 않는다.
{
  git -C "$TOP" diff --name-only 2>/dev/null
  git -C "$TOP" diff --cached --name-only 2>/dev/null
  git -C "$TOP" ls-files --others --exclude-standard 2>/dev/null
} | sort -u | head -n "$MAX_FILES" > "$CHANGED_LIST"

# 삭제된 파일은 diff 목록에 남으므로 실제 존재하는 것만 남긴다.
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "${TOP}/${rel}" ] || continue
  printf '%s\n' "${TOP}/${rel}" >> "$EXISTING_LIST"
done < "$CHANGED_LIST"

FILE_COUNT="$(wc -l < "$EXISTING_LIST" 2>/dev/null | tr -d ' ')"
[ -n "$FILE_COUNT" ] || FILE_COUNT=0
[ "$FILE_COUNT" -gt 0 ] || exit 0

# 리스크 패턴 4종. 패턴마다 전체 파일을 훑으면 스캔이 4배가 되므로 grep -E
# 교대(alternation)로 묶어 파일당 단일 패스로 읽고, 매치 문자열을 뒤에서 분류한다.
PAT_TRY='try[[:space:]]*\{'
PAT_ASYNC='async[[:space:]]'
PAT_PRISMA='prisma\.'
PAT_THROW='throw[[:space:]]'
PAT_ALL="${PAT_TRY}|${PAT_ASYNC}|${PAT_PRISMA}|${PAT_THROW}"

FOUND_TRY=0
FOUND_ASYNC=0
FOUND_PRISMA=0
FOUND_THROW=0
SCANNED=0
SKIPPED=0
TIME_CAPPED=0

# 단일 패스 결과(매치된 문자열들)를 패턴별 플래그로 되돌린다.
# 파이프라인 밖에서 대입하므로 서브셸 문제 없음(bash 3.2).
classify_hits() {
  if [ "$FOUND_TRY" -eq 0 ] && printf '%s\n' "$1" | grep -qE -e "$PAT_TRY"; then
    FOUND_TRY=1
  fi
  if [ "$FOUND_ASYNC" -eq 0 ] && printf '%s\n' "$1" | grep -qE -e "$PAT_ASYNC"; then
    FOUND_ASYNC=1
  fi
  if [ "$FOUND_PRISMA" -eq 0 ] && printf '%s\n' "$1" | grep -qE -e "$PAT_PRISMA"; then
    FOUND_PRISMA=1
  fi
  if [ "$FOUND_THROW" -eq 0 ] && printf '%s\n' "$1" | grep -qE -e "$PAT_THROW"; then
    FOUND_THROW=1
  fi
}

SECONDS=0
while IFS= read -r f; do
  [ -n "$f" ] || continue

  # 경과 상한 초과 → 남은 파일은 읽지 않고 스킵으로만 집계한다(조기 종료).
  if [ "$SECONDS" -ge "$MAX_SECONDS" ]; then
    TIME_CAPPED=1
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # 크기 상한. stat 은 BSD/GNU 플래그가 갈리므로 이식성 위해 wc -c 를 쓴다.
  SIZE="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
  case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
  if [ "$SIZE" -gt "$MAX_BYTES" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  SCANNED=$((SCANNED + 1))
  HITS="$(grep -ohIE -e "$PAT_ALL" "$f" 2>/dev/null | sort -u)"
  [ -n "$HITS" ] || continue
  classify_hits "$HITS"
done < "$EXISTING_LIST"

REMINDERS=""
add_reminder() {
  REMINDERS="${REMINDERS}  ? $1"$'\n'
}

[ "$FOUND_TRY" -eq 1 ]    && add_reminder "에러 처리(try/catch)를 추가했나요? 실패 경로가 로깅되나요?"
[ "$FOUND_ASYNC" -eq 1 ]  && add_reminder "async 작업의 await·에러 전파가 올바른가요?"
[ "$FOUND_PRISMA" -eq 1 ] && add_reminder "Prisma 호출이 repository 패턴 안에 감싸져 있나요?"
[ "$FOUND_THROW" -eq 1 ]  && add_reminder "throw 한 에러가 상위에서 처리·리포팅(Sentry 등)되나요?"

# 스킵 표기를 리마인더 블록 안에 두는 것은 의도적 선택이다 — 매치 0건인데
# "부분 스캔이었다"는 사실만으로 매 Stop 마다 잡음을 내지 않는다(advisory 계약 우선).
if [ -n "$REMINDERS" ]; then
  echo "[STOP SELF-CHECK]"
  echo "변경 감지: ${FILE_COUNT}개 파일 (git 작업트리 기준) · 스캔 ${SCANNED}개"
  printf '%s' "$REMINDERS"
  if [ "$SKIPPED" -gt 0 ]; then
    if [ "$TIME_CAPPED" -eq 1 ]; then
      echo "(스캔 상한: ${SKIPPED}개 파일 스킵 — ${MAX_SECONDS}초 경과 또는 ${MAX_BYTES}바이트 초과)"
    else
      echo "(스캔 상한: ${SKIPPED}개 파일 스킵 — ${MAX_BYTES}바이트 초과)"
    fi
  fi
  echo "(advisory: 리마인더일 뿐 작업을 차단하지 않음)"
fi

exit 0
