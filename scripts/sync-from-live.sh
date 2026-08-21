#!/bin/bash
set -euo pipefail

# ============================================================================
# scripts/sync-from-live.sh — 라이브 하네스(~/.claude) → 리포 역동기화
# ----------------------------------------------------------------------------
# 왜 존재하나: 이 리포는 라이브 하네스의 "설치 가능한 스냅샷"이다. 라이브가
# 앞서 진화한 상태에서 install.sh 를 재실행하면 라이브가 구버전으로 롤백된다
# (2026-08-20 감사에서 확인된 P1 회귀 경로). 설치 전에 이 스크립트로 스냅샷을
# 라이브 기준으로 갱신하면 그 회귀가 구조적으로 사라진다.
#
# 동기화 대상 (방향은 전부 live → repo, 라이브는 읽기만 한다):
#   1. ~/.claude/rules/*.md            → global/rules/
#   2. ~/.claude/skills/<repo 소유 스킬> → global/skills/  (심볼릭링크는 스킵)
#   3. ~/.claude/settings.json 의 skillOverrides
#                                      → global/settings-fragments/skill-overrides.json
#   4. ~/.claude/CLAUDE.md 마커 블록   → advisor 설치기 heredoc
#      (기본은 드리프트 "보고"만. --write-claude-block 명시 시에만 갱신)
#
# 하지 않는 것 (파괴적 결정은 사람이 한다):
#   - 라이브에서 삭제된 스킬을 repo 에서 자동 삭제하지 않는다 — 경고만 출력.
#   - repo 에 없는 라이브 스킬을 새로 추적하지 않는다 (플러그인/개인 실험 다수).
#
# Usage: scripts/sync-from-live.sh [--dry-run] [--write-claude-block]
# 제약: bash 3.2 호환, 모든 경로 인용. jq 없으면 3·4 는 스킵(경고).
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="${HOME}/.claude"
RULES_DST="${SCRIPT_DIR}/global/rules"
SKILLS_DST="${SCRIPT_DIR}/global/skills"
OVERRIDES_DST="${SCRIPT_DIR}/global/settings-fragments/skill-overrides.json"
ADVISOR_INSTALLER="${SCRIPT_DIR}/docs/codex-advisor-worker-bundle/install.sh"

DRY_RUN=false
WRITE_CLAUDE_BLOCK=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)            DRY_RUN=true; shift ;;
    --write-claude-block) WRITE_CLAUDE_BLOCK=true; shift ;;
    -h|--help)
      sed -n '4,29p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

note() { printf '  %s\n' "$1"; }

# ── 1. rules ─────────────────────────────────────────────────────────────
echo "▶ rules: ~/.claude/rules → global/rules"
if [ -d "${CLAUDE_HOME}/rules" ]; then
  for f in "${CLAUDE_HOME}/rules/"*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    dst="${RULES_DST}/${name}"
    if [ -f "$dst" ] && cmp -s "$f" "$dst"; then
      note "UNCHANGED: ${name}"
    elif $DRY_RUN; then
      note "[DRY RUN] Would sync: ${name}"
    else
      cp "$f" "$dst"
      note "SYNCED: ${name}"
    fi
  done
else
  note "스킵: ${CLAUDE_HOME}/rules 없음"
fi

# ── 2. skills (repo 가 이미 소유한 스킬만) ────────────────────────────────
echo "▶ skills: ~/.claude/skills → global/skills (repo 소유분만)"
for d in "${SKILLS_DST}/"*/; do
  [ -d "$d" ] || continue
  name="$(basename "${d%/}")"
  src="${CLAUDE_HOME}/skills/${name}"
  if [ -L "$src" ]; then
    note "SKIP(심볼릭링크): ${name} — 설치기 소유 부적합. 페이로드에서 제거를 검토하세요."
  elif [ ! -d "$src" ]; then
    note "WARN: ${name} 이 라이브에 없음 — 사용자가 삭제했다면 repo 에서도 제거하세요 (자동 삭제 안 함)."
  elif diff -rq "$src" "${d%/}" >/dev/null 2>&1; then
    note "UNCHANGED: ${name}"
  elif $DRY_RUN; then
    note "[DRY RUN] Would sync: ${name}/"
  else
    rm -rf "${d%/}"
    cp -R "$src" "${d%/}"
    find "${d%/}" -name '.DS_Store' -delete 2>/dev/null || true
    note "SYNCED: ${name}/"
  fi
done

# ── 3. skillOverrides 스냅샷 ─────────────────────────────────────────────
echo "▶ skillOverrides: ~/.claude/settings.json → skill-overrides.json"
if ! command -v jq >/dev/null 2>&1; then
  note "스킵: jq 없음"
elif [ ! -f "${CLAUDE_HOME}/settings.json" ]; then
  note "스킵: ~/.claude/settings.json 없음"
elif ! jq -e '.skillOverrides' "${CLAUDE_HOME}/settings.json" >/dev/null 2>&1; then
  note "스킵: 라이브에 skillOverrides 키 없음 (빈 스냅샷으로 덮지 않는다)"
else
  NEW_SNAP="$(jq '{skillOverrides}' "${CLAUDE_HOME}/settings.json")"
  if [ -f "$OVERRIDES_DST" ] && [ "$NEW_SNAP" = "$(cat "$OVERRIDES_DST")" ]; then
    note "UNCHANGED: skill-overrides.json"
  elif $DRY_RUN; then
    note "[DRY RUN] Would sync: skill-overrides.json ($(printf '%s' "$NEW_SNAP" | jq '.skillOverrides | length')개 항목)"
  else
    printf '%s\n' "$NEW_SNAP" > "$OVERRIDES_DST"
    note "SYNCED: skill-overrides.json ($(jq '.skillOverrides | length' "$OVERRIDES_DST")개 항목)"
  fi
fi

# ── 4. CLAUDE.md 마커 블록 → advisor heredoc ─────────────────────────────
echo "▶ CLAUDE.md 블록: ~/.claude/CLAUDE.md → advisor 설치기 heredoc"
LIVE_MD="${CLAUDE_HOME}/CLAUDE.md"
if [ ! -f "$LIVE_MD" ] || [ ! -f "$ADVISOR_INSTALLER" ]; then
  note "스킵: 라이브 CLAUDE.md 또는 advisor 설치기 없음"
else
  # 앵커는 정확히 1개씩이어야 한다 — 아니면 어떤 쓰기도 하지 않는다.
  OPEN_N="$(grep -c "<<'CLAUDEMD'" "$ADVISOR_INSTALLER" || true)"
  TERM_N="$(grep -c '^CLAUDEMD$' "$ADVISOR_INSTALLER" || true)"
  S_N="$(grep -c 'codex-advisor-worker-bundle:start' "$LIVE_MD" || true)"
  E_N="$(grep -c 'codex-advisor-worker-bundle:end' "$LIVE_MD" || true)"
  if [ "$OPEN_N" != "1" ] || [ "$TERM_N" != "1" ] || [ "$S_N" != "1" ] || [ "$E_N" != "1" ]; then
    note "WARN: 앵커 비정상(heredoc ${OPEN_N}/${TERM_N}, live 마커 ${S_N}/${E_N}) — 수동 확인 필요, 변경 안 함"
  else
    OPEN="$(grep -n "<<'CLAUDEMD'" "$ADVISOR_INSTALLER" | cut -d: -f1)"
    TERM="$(grep -n '^CLAUDEMD$' "$ADVISOR_INSTALLER" | cut -d: -f1)"
    S="$(grep -n 'codex-advisor-worker-bundle:start' "$LIVE_MD" | cut -d: -f1)"
    E="$(grep -n 'codex-advisor-worker-bundle:end' "$LIVE_MD" | cut -d: -f1)"
    LIVE_BLOCK="$(sed -n "$((S+1)),$((E-1))p" "$LIVE_MD")"
    REPO_BLOCK="$(sed -n "$((OPEN+1)),$((TERM-1))p" "$ADVISOR_INSTALLER")"
    if printf '%s\n' "$LIVE_BLOCK" | grep -q '^CLAUDEMD$'; then
      note "WARN: 라이브 블록에 'CLAUDEMD' 단독 줄 — heredoc 터미네이터 충돌, 변경 안 함"
    elif [ "$LIVE_BLOCK" = "$REPO_BLOCK" ]; then
      note "UNCHANGED: heredoc 블록"
    elif ! $WRITE_CLAUDE_BLOCK; then
      note "DRIFT 감지: 라이브 블록과 heredoc 이 다릅니다."
      note "  갱신하려면: scripts/sync-from-live.sh --write-claude-block"
    elif $DRY_RUN; then
      note "[DRY RUN] Would splice: heredoc <- live 블록 ($((E-1-S))줄)"
    else
      T="$(mktemp)"
      sed -n "1,${OPEN}p" "$ADVISOR_INSTALLER" > "$T"
      printf '%s\n' "$LIVE_BLOCK" >> "$T"
      sed -n "${TERM},\$p" "$ADVISOR_INSTALLER" >> "$T"
      if bash -n "$T" 2>/dev/null; then
        mv "$T" "$ADVISOR_INSTALLER"
        chmod +x "$ADVISOR_INSTALLER"
        note "SYNCED: heredoc 블록 ($((E-1-S))줄)"
      else
        rm -f "$T"
        note "WARN: 스플라이스 결과가 bash -n 실패 — 변경 안 함"
      fi
    fi
  fi
fi

echo ""
echo "완료. 설치 전 권장 절차: sync-from-live.sh → git diff 검토 → install.sh"
