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
#   1b. ~/.claude/agents/<repo 소유>.md → global/agents/
#   2. ~/.claude/skills/<repo 소유 스킬> → global/skills/  (심볼릭링크는 스킵)
#   3. ~/.claude/settings.json 의 skillOverrides
#                                      → global/settings-fragments/skill-overrides.json
#   4. ~/.claude/CLAUDE.md 마커 블록   → advisor 설치기 heredoc
#      (기본은 드리프트 "보고"만. --write-claude-block 명시 시에만 갱신)
#   5. ~/.claude/hooks/advisor-context-budget.js → 설치기 ADVCTXJS heredoc
#      활성 statusline 의 ctx-budget 마커 블록   → 설치기 CTXBRIDGE heredoc
#      (기본은 드리프트 "보고"만. --write-hook-blocks 명시 시에만 갱신)
#
# 왜 5 가 필요한가: 4 까지만 있던 시절 이 둘이 역동기화 대상이 아니어서
# 라이브 훅이 두 세대 앞선 채(창 비례 임계 + GSD 분기 갱신) 설치기 heredoc 은
# 고정 임계(51133/59000)에 머물렀다. 그 상태로 install.sh 를 재실행하면
# 라이브가 조용히 롤백된다 — 이 스크립트가 없애려던 바로 그 회귀다 (2026-08-21).
#
# 하지 않는 것 (파괴적 결정은 사람이 한다):
#   - 라이브에서 삭제된 스킬을 repo 에서 자동 삭제하지 않는다 — 경고만 출력.
#   - repo 에 없는 라이브 스킬을 새로 추적하지 않는다 (플러그인/개인 실험 다수).
#
# Usage: scripts/sync-from-live.sh [--dry-run]
#          [--write-claude-block] [--write-hook-blocks] [--write-blocks]
#        --write-blocks 는 위 두 쓰기 플래그를 모두 켠다.
# 제약: bash 3.2 호환, 모든 경로 인용. jq 없으면 3·4·5 는 스킵(경고).
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="${HOME}/.claude"
RULES_DST="${SCRIPT_DIR}/global/rules"
AGENTS_DST="${SCRIPT_DIR}/global/agents"
SKILLS_DST="${SCRIPT_DIR}/global/skills"
OVERRIDES_DST="${SCRIPT_DIR}/global/settings-fragments/skill-overrides.json"
ADVISOR_INSTALLER="${SCRIPT_DIR}/docs/codex-advisor-worker-bundle/install.sh"

DRY_RUN=false
WRITE_CLAUDE_BLOCK=false
WRITE_HOOK_BLOCKS=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)            DRY_RUN=true; shift ;;
    --write-claude-block) WRITE_CLAUDE_BLOCK=true; shift ;;
    --write-hook-blocks)  WRITE_HOOK_BLOCKS=true; shift ;;
    # 우산 플래그: heredoc 스플라이스 3종을 한 번에 켠다.
    --write-blocks)       WRITE_CLAUDE_BLOCK=true; WRITE_HOOK_BLOCKS=true; shift ;;
    -h|--help)
      sed -n '4,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
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

# 역방향 점검: repo 가 가진 rule 이 라이브에서 사라졌는지.
# 위 루프는 라이브를 순회하므로 삭제된 rule 은 방문조차 되지 않는다 — 별도 패스가 필요하다.
# (skills 루프가 repo 소유분을 순회해 WARN 을 낼 수 있는 것과 같은 이유.)
for f in "${RULES_DST}/"*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  if [ ! -f "${CLAUDE_HOME}/rules/${name}" ]; then
    note "WARN: ${name} 이 라이브에 없음 — 사용자가 삭제했다면 repo 에서도 제거하세요 (자동 삭제 안 함)."
  fi
done

# ── 2. agents (repo 가 이미 소유한 에이전트만) ───────────────────────────
# rules 루프처럼 라이브를 순회하면 안 된다 — 라이브에는 조언자 번들이 만든
# architect/worker 와 gsd-* 수십 개가 있어 전부 페이로드로 딸려온다.
echo "▶ agents: ~/.claude/agents → global/agents (repo 소유분만)"
for f in "${AGENTS_DST}/"*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  src="${CLAUDE_HOME}/agents/${name}"
  if [ ! -f "$src" ]; then
    note "WARN: ${name} 이 라이브에 없음 — 사용자가 삭제했다면 repo 에서도 제거하세요 (자동 삭제 안 함)."
  elif cmp -s "$src" "$f"; then
    note "UNCHANGED: ${name}"
  elif $DRY_RUN; then
    note "[DRY RUN] Would sync: ${name}"
  else
    cp "$src" "$f"
    note "SYNCED: ${name}"
  fi
done

# ── 3. skills (repo 가 이미 소유한 스킬만) ────────────────────────────────
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

# ── 4. skillOverrides 스냅샷 ─────────────────────────────────────────────
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

# ── 5. CLAUDE.md 마커 블록 → advisor heredoc ─────────────────────────────
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

# ── 6. 훅 JS / statusline 브리지 → advisor 설치기 heredoc ────────────────
# 4 와 같은 규율을 두 번 더 적용한다: 앵커 1쌍 검증 → 동일하면 UNCHANGED →
# 다르면 기본은 보고만, 플래그가 있을 때만 스플라이스 + `bash -n` 게이트.
# 4 의 인라인 구현은 검증된 코드라 건드리지 않는다(회귀 위험). 공통화는 이 절 안에서만 한다.
#
# $1=라벨  $2=라이브 본문 파일  $3=heredoc 여는 줄(고정 문자열)  $4=터미네이터 라벨
#   $5=본문 검증기 (node|bash) — heredoc 안의 payload 를 실제로 파싱한다
sync_heredoc_block() {
  shb_label="$1"; shb_live_raw="$2"; shb_open="$3"; shb_term="$4"; shb_check="$5"

  # 앵커는 정확히 1개씩이어야 한다 — 아니면 어떤 쓰기도 하지 않는다.
  shb_on="$(grep -cF "$shb_open" "$ADVISOR_INSTALLER" || true)"
  shb_tn="$(grep -c "^${shb_term}\$" "$ADVISOR_INSTALLER" || true)"
  if [ "$shb_on" != "1" ] || [ "$shb_tn" != "1" ]; then
    note "WARN: ${shb_label} 앵커 비정상(여는줄 ${shb_on}, 터미네이터 ${shb_tn}) — 변경 안 함"
    return 0
  fi

  # 라이브 본문을 '끝 개행 보장' 형태로 정규화한다. 비교와 쓰기가 **같은 바이트**를 봐야
  # 멱등이 성립한다 — 쓰기 경로에서만 개행을 붙이면 repo 에는 있고 라이브에는 없어
  # 다음 실행이 매번 드리프트로 오판하고 설치기를 다시 쓴다.
  # (끝 개행이 없으면 터미네이터가 마지막 줄에 붙어 heredoc 이 닫히지 않는다.)
  shb_live="$(mktemp)"
  cat "$shb_live_raw" > "$shb_live"
  if [ -s "$shb_live" ] && [ "$(tail -c1 "$shb_live" | wc -l | tr -d ' ')" -eq 0 ]; then
    printf '\n' >> "$shb_live"
  fi

  # 라이브 본문에 터미네이터 단독 줄이 있으면 스플라이스가 heredoc 을 조기 종료시킨다.
  if grep -q "^${shb_term}\$" "$shb_live"; then
    note "WARN: ${shb_label} 라이브 본문에 '${shb_term}' 단독 줄 — heredoc 충돌, 변경 안 함"
    rm -f "$shb_live"; return 0
  fi

  shb_o="$(grep -nF "$shb_open" "$ADVISOR_INSTALLER" | cut -d: -f1)"
  shb_t="$(grep -n "^${shb_term}\$" "$ADVISOR_INSTALLER" | cut -d: -f1)"
  if [ "$shb_o" -ge "$shb_t" ]; then
    note "WARN: ${shb_label} 앵커 순서 역전(여는줄 ${shb_o} >= 터미네이터 ${shb_t}) — 변경 안 함"
    rm -f "$shb_live"; return 0
  fi

  shb_repo="$(mktemp)"
  sed -n "$((shb_o + 1)),$((shb_t - 1))p" "$ADVISOR_INSTALLER" > "$shb_repo"
  if cmp -s "$shb_repo" "$shb_live"; then
    note "UNCHANGED: ${shb_label}"
    rm -f "$shb_repo" "$shb_live"; return 0
  fi
  rm -f "$shb_repo"

  if ! $WRITE_HOOK_BLOCKS; then
    note "DRIFT 감지: ${shb_label} 이 라이브와 다릅니다."
    note "  갱신하려면: scripts/sync-from-live.sh --write-hook-blocks"
    rm -f "$shb_live"; return 0
  fi
  if $DRY_RUN; then
    note "[DRY RUN] Would splice: ${shb_label} <- 라이브 ($(wc -l < "$shb_live" | tr -d ' ')줄)"
    rm -f "$shb_live"; return 0
  fi

  # payload 자체를 파싱한다. 바깥 `bash -n` 은 quoted heredoc(<<'X') 본문을 불투명
  # 문자열로 보므로 깨진 JS·셸이 들어가도 통과한다 — 그대로 두면 '검증했다'는 착각 아래
  # 깨진 모니터를 설치하는 설치기가 만들어진다.
  # 검증 수단이 없으면 진행하지 않는다: 여기서 잘못 쓰면 재설치가 라이브를 깨뜨린다.
  case "$shb_check" in
    node)
      if ! command -v node >/dev/null 2>&1; then
        note "WARN: ${shb_label} node 없음 — payload 검증 불가, 변경 안 함"
        rm -f "$shb_live"; return 0
      fi
      if ! node --check "$shb_live" 2>/dev/null; then
        note "WARN: ${shb_label} 라이브 본문이 유효한 JS 가 아님 — 변경 안 함"
        rm -f "$shb_live"; return 0
      fi ;;
    bash)
      if ! bash -n "$shb_live" 2>/dev/null; then
        note "WARN: ${shb_label} 라이브 본문이 유효한 셸 조각이 아님 — 변경 안 함"
        rm -f "$shb_live"; return 0
      fi ;;
  esac

  # shb_live 는 이미 끝 개행이 보장된 정규화본이다(위 참조).
  shb_tmp="$(mktemp)"
  sed -n "1,${shb_o}p" "$ADVISOR_INSTALLER" > "$shb_tmp"
  cat "$shb_live" >> "$shb_tmp"
  sed -n "${shb_t},\$p" "$ADVISOR_INSTALLER" >> "$shb_tmp"
  if bash -n "$shb_tmp" 2>/dev/null; then
    mv "$shb_tmp" "$ADVISOR_INSTALLER"
    chmod +x "$ADVISOR_INSTALLER"
    note "SYNCED: ${shb_label} ($(wc -l < "$shb_live" | tr -d ' ')줄)"
  else
    rm -f "$shb_tmp"
    note "WARN: ${shb_label} 스플라이스 결과가 bash -n 실패 — 변경 안 함"
  fi
  rm -f "$shb_live"
}

echo "▶ 훅/브리지 블록: 라이브 → advisor 설치기 heredoc"
if [ ! -f "$ADVISOR_INSTALLER" ]; then
  note "스킵: advisor 설치기 없음"
else
  # 5-1. 훅 JS — 파일 전체가 heredoc 본문이다.
  LIVE_HOOK="${CLAUDE_HOME}/hooks/advisor-context-budget.js"
  if [ ! -f "$LIVE_HOOK" ]; then
    note "스킵: 라이브 훅 없음 (${LIVE_HOOK})"
  else
    sync_heredoc_block "훅 JS(ADVCTXJS)" "$LIVE_HOOK" "<<'ADVCTXJS'" "ADVCTXJS" "node"
  fi

  # 5-2. statusline 브리지 — 마커 '사이'만 heredoc 본문이다(마커 줄 자체는 설치기가 붙인다).
  # statusline 경로를 하드코딩하지 않는다 — 설치기와 같이 settings.json 에서 해석한다.
  # 다만 판정 기준은 설치기와 다르다: 설치기는 '삽입할 자격'(CURRENT_USAGE=·input= 앵커)을 보고,
  # 여기서는 '이미 삽입된 블록'을 찾으므로 ctx-budget 마커 유무가 정확한 기준이다.
  if ! command -v jq >/dev/null 2>&1; then
    note "스킵: jq 없음 — 브리지 블록"
  elif [ ! -f "${CLAUDE_HOME}/settings.json" ]; then
    note "스킵: ~/.claude/settings.json 없음 — 브리지 블록"
  else
    SL_CMD="$(jq -r '.statusLine.command // ""' "${CLAUDE_HOME}/settings.json" 2>/dev/null || true)"
    SL_SCRIPT=""
    # 래퍼 커맨드("bash ~/x.sh", "env FOO=1 ~/x.sh") 대응 — 토큰을 순회한다.
    # 읽기 전용이므로 심링크는 그대로 따라간다(해석 불필요).
    for tok in $SL_CMD; do
      case "$tok" in
        '~/'*)       tok="${HOME}/${tok#\~/}" ;;
        '$HOME/'*)   tok="${HOME}/${tok#\$HOME/}" ;;
        '${HOME}/'*) tok="${HOME}/${tok#\$\{HOME\}/}" ;;
      esac
      [ -f "$tok" ] || continue
      grep -q 'codex-advisor-worker-bundle:ctx-budget:start' "$tok" 2>/dev/null || continue
      SL_SCRIPT="$tok"; break
    done
    if [ -z "$SL_SCRIPT" ]; then
      note "스킵: statusLine 커맨드에서 ctx-budget 마커를 가진 스크립트를 찾지 못함"
    else
      BS_N="$(grep -c 'codex-advisor-worker-bundle:ctx-budget:start' "$SL_SCRIPT" || true)"
      BE_N="$(grep -c 'codex-advisor-worker-bundle:ctx-budget:end' "$SL_SCRIPT" || true)"
      if [ "$BS_N" != "1" ] || [ "$BE_N" != "1" ]; then
        note "WARN: 브리지 마커 비정상(start ${BS_N}, end ${BE_N}) in ${SL_SCRIPT} — 변경 안 함"
      else
        BS="$(grep -n 'codex-advisor-worker-bundle:ctx-budget:start' "$SL_SCRIPT" | cut -d: -f1)"
        BE="$(grep -n 'codex-advisor-worker-bundle:ctx-budget:end' "$SL_SCRIPT" | cut -d: -f1)"
        if [ "$BS" -ge "$BE" ]; then
          note "WARN: 브리지 마커 순서 역전 in ${SL_SCRIPT} — 변경 안 함"
        else
          LIVE_BRIDGE="$(mktemp)"
          sed -n "$((BS + 1)),$((BE - 1))p" "$SL_SCRIPT" > "$LIVE_BRIDGE"
          sync_heredoc_block "브리지(CTXBRIDGE)" "$LIVE_BRIDGE" "<<'CTXBRIDGE'" "CTXBRIDGE" "bash"
          rm -f "$LIVE_BRIDGE"
        fi
      fi
    fi
  fi
fi

echo ""
echo "완료. 설치 전 권장 절차: sync-from-live.sh → git diff 검토 → install.sh"
