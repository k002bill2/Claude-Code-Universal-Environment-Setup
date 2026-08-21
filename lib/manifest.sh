#!/bin/bash
# ============================================================================
# lib/manifest.sh — installer 파일 소유권 manifest (공용)
# ----------------------------------------------------------------------------
# settings.json 의 hooks/permissions 소유권은 lib/merge-settings.sh 가 별도로
# 추적한다. 이 파일은 그 밖의 모든 관리 파일(rules, skills, agents, commands,
# hooks 스크립트, docs 등)의 소유권을 추적한다 — install_managed_file /
# install_managed_dir(installer.sh) 이 rm -rf 로 통째 교체하지 않고, 사용자가
# 추가·수정한 파일을 안전하게 구분하기 위해 존재한다.
#
# 포맷: TSV, 1줄 1항목 — "<manifest 루트 기준 상대경로>\t<설치 시점 해시>"
#   - 글로벌 manifest 의 루트 = CLAUDE_HOME (~/.claude)
#   - 프로젝트 manifest 의 루트 = PROJECT_DIR
# 해시는 "installer 가 마지막으로 이 파일에 쓴 내용"의 해시다(소스 해시와 동일).
# 즉 manifest[relpath] == 현재 dst 파일 해시  ⇔  설치 이후 사용자가 건드리지 않음.
#
# 소유권 판정 3분류 (install_managed_file 이 사용):
#   1) manifest 에 없음                              → 소유권 불명, 보수적으로
#                                                        "사용자 파일"로 취급
#   2) manifest 에 있고 기록 해시 == 현재 dst 해시     → installer 소유, 미변경
#                                                        → 자유롭게 갱신 가능
#   3) manifest 에 있고 기록 해시 != 현재 dst 해시     → installer 소유였으나
#                                                        사용자가 수정함 → 보존
#
# 제약: bash 3.2 호환(연관배열 금지), 모든 경로 인용.
# ============================================================================

# 파일 내용 해시. shasum → sha256sum → cksum(폴백, 암호학적 보장 불필요 —
# "설치 이후 바뀌었는지" 변경 감지 용도일 뿐).
manifest_hash_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  else
    cksum "$f" 2>/dev/null | awk '{print $1 "-" $2}'
  fi
}

# manifest 경로 안전성: 관리 루트를 벗어나는 항목을 거부한다.
#
# manifest 는 프로젝트 안(<proj>/.manifest)에 있어 리포가 값을 통제할 수 있다.
# "../../어딘가" 나 절대경로 항목에 실제 해시를 맞춰 넣으면 --uninstall 과 stale
# 정리가 관리 루트 **밖** 파일을 지운다 — 임의 삭제 수단이 된다. 소비 지점마다
# 이 검사를 통과한 경로만 쓴다.
#   거부: 빈 값 · 절대경로 · 성분으로서의 '..'
#   허용: '..foo' 같은 정상 파일명 (성분 전체가 '..' 일 때만 거부)
manifest_path_safe() {
  local p="$1"
  case "$p" in
    ''|/*)        return 1 ;;
    ..|../*|*/..) return 1 ;;
    */../*)       return 1 ;;
  esac
  return 0
}

# 특정 relpath 의 기록된 해시 (없으면 빈 문자열)
manifest_get() {
  local manifest="$1" relpath="$2"
  [ -f "$manifest" ] || return 0
  awk -F '\t' -v p="$relpath" '$1 == p { v = $2 } END { if (v != "") print v }' "$manifest"
}

# 심볼릭 링크 해석 — dotfiles 로 관리되는 .manifest 를 `mv` 가 일반 파일로
# 갈아치우면 추적이 조용히 끊긴다. 링크는 보존하고 **대상 파일**을 갱신한다.
manifest_resolve_link() {
  local p="$1" t n=0
  while [ -L "$p" ] && [ "$n" -lt 32 ]; do
    t="$(readlink "$p" 2>/dev/null)" || break
    case "$t" in
      /*) p="$t" ;;
      *)  p="$(dirname "$p")/$t" ;;
    esac
    n=$((n + 1))
  done
  printf '%s' "$p"
}

# relpath 항목 upsert (원자적: tmp 에 쓰고 mv)
manifest_set() {
  local manifest="$1" relpath="$2" hash="$3"
  mkdir -p "$(dirname "$manifest")"
  local tmp
  tmp="$(mktemp "${manifest}.XXXXXX" 2>/dev/null || mktemp)" || return 1
  if [ -f "$manifest" ]; then
    awk -F '\t' -v p="$relpath" '$1 != p' "$manifest" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\t%s\n' "$relpath" "$hash" >> "$tmp"
  mv "$tmp" "$(manifest_resolve_link "$manifest")"
}

# relpath 항목 제거
manifest_remove() {
  local manifest="$1" relpath="$2"
  [ -f "$manifest" ] || return 0
  local tmp
  tmp="$(mktemp "${manifest}.XXXXXX" 2>/dev/null || mktemp)" || return 1
  awk -F '\t' -v p="$relpath" '$1 != p' "$manifest" > "$tmp"
  mv "$tmp" "$(manifest_resolve_link "$manifest")"
}

# manifest 의 모든 relpath 나열
manifest_paths() {
  local manifest="$1"
  [ -f "$manifest" ] || return 0
  awk -F '\t' 'NF >= 1 { print $1 }' "$manifest"
}

# ──────────────────────────────────────────────────────────────────────
# bounded backup: <file>.bak, .bak.1, .bak.2 ... 최대 MANIFEST_BACKUP_KEEP
# (기본 3) 개만 남기고 가장 오래된 것부터 삭제. lib/merge-settings.sh 의
# msf_prune_backups 와 동일 계약 — settings.json 이 아닌 일반 관리 파일용.
# ──────────────────────────────────────────────────────────────────────
manifest_backup_path() {
  local f="$1"
  if [ ! -e "$f.bak" ]; then
    printf '%s' "$f.bak"
    return
  fi
  local i=1
  while [ -e "$f.bak.$i" ]; do
    i=$((i + 1))
  done
  printf '%s' "$f.bak.$i"
}

manifest_mtime() {
  # 파일 mtime(epoch). GNU(stat -c) → BSD/macOS(stat -f) 순으로 시도한다.
  # macOS 의 stat 은 -c 를 모르는 옵션으로 거부(exit 1)하므로 이 순서가 안전하다.
  # 둘 다 없으면 0 을 돌려주어 "가장 오래된 것"으로 취급한다(삭제 후보 우선).
  local m
  m="$(stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null)"
  case "$m" in
    ''|*[!0-9]*) printf '0' ;;
    *)           printf '%s' "$m" ;;
  esac
}

# 같은 원본의 백업이 MANIFEST_BACKUP_KEEP 개를 넘으면 **가장 오래된 것부터** 삭제한다.
#
# 이전 구현은 `find ... | xargs -I{} ls -td {} | tail -1` 이었다. `-I{}` 는
# 인자당 ls 를 한 번씩 실행하므로 `ls -t` 의 정렬이 각 호출 안에서 파일 1개를
# 정렬하는 무의미한 연산이 된다. 결과 순서는 find 의 디렉토리 나열 순서(APFS 는
# 해시 기반이라 재현성이 없다)이고, tail -1 은 그중 임의의 하나를 고른다 —
# 최신 백업이 지워지고 오래된 것이 남는 일이 실제로 발생했다.
# 지금은 mtime 을 직접 읽어 **한 번만** 정렬하고, 오래된 순으로 excess 개를 지운다.
# 설치기가 만든 백업만 정리하기 위한 소유 색인.
#
# 이름(`<file>.bak.N`)만 보고 지우면 사용자가 같은 이름으로 만들어 둔 파일까지
# 지운다(실측: 사용자 백업 5건 중 2건 삭제). "사용자 것은 건드리지 않는다" 는
# 계약이 백업에도 적용되어야 하므로, 우리가 만든 경로를 별도 색인에 적어 두고
# **그 목록 안에서만** 상한을 적용한다.
#   색인 경로: <manifest 와 같은 디렉토리>/.manifest-backups
#   형식: 한 줄에 백업 절대경로 하나
manifest_backup_index() {
  printf '%s/.manifest-backups' "$(dirname "$1")"
}

# 경로만 적으면 소유 판정이 이름 기반이 된다 — 우리 백업이 지워진 뒤 사용자가
# 같은 이름을 재사용하면 그 사용자 파일이 "우리 것" 으로 지워진다(실측).
# 경로와 **그 시점 내용 해시**를 함께 적고, 지울 때 해시가 여전히 일치할 때만 지운다.
manifest_backup_record() {
  local manifest="$1" bak="$2" idx h
  [ -n "$manifest" ] || return 0
  idx="$(manifest_backup_index "$manifest")"
  mkdir -p "$(dirname "$idx")" 2>/dev/null || return 0
  h="$(manifest_hash_file "$bak")"
  printf '%s\t%s\n' "$bak" "$h" >> "$idx"
  return 0
}

# 색인 항목 중 "지금도 우리가 쓴 그 내용" 인 경로만 stdout 으로
manifest_owned_backups() {
  local idx="$1" bp bh
  [ -f "$idx" ] || return 0
  while IFS="$(printf '\t')" read -r bp bh; do
    [ -n "$bp" ] || continue
    [ -f "$bp" ] || continue
    [ -n "$bh" ] || continue
    [ "$(manifest_hash_file "$bp")" = "$bh" ] || continue
    printf '%s\n' "$bp"
  done < "$idx" | sort -u
}

manifest_prune_backups() {
  local f="$1"
  local keep="${MANIFEST_BACKUP_KEEP:-3}"
  case "$keep" in
    ''|*[!0-9]*) keep=3 ;;
  esac
  [ "$keep" -ge 1 ] || keep=1

  local dir base list pairs total excess victim
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  list="$(mktemp)" || return 0
  pairs="$(mktemp)" || { rm -f "$list"; return 0; }

  # -type f: 이름이 백업 형태인 사용자 **디렉토리**를 세지도, 지우지도 않는다.
  # 세기만 해도 total 이 부풀어 일반 파일이 과잉 삭제된다(실측).
  find "$dir" -maxdepth 1 -type f \( -name "${base}.bak" -o -name "${base}.bak.*" \) -print 2>/dev/null > "${list}.all"
  # 소유 색인이 있으면 그 안의 경로만 정리 대상이다. 색인이 없으면(구버전에서
  # 넘어온 상태) 아무것도 지우지 않는다 — 모르면 건드리지 않는다.
  if [ -n "${MANIFEST_BACKUP_INDEX:-}" ] && [ -f "$MANIFEST_BACKUP_INDEX" ]; then
    manifest_owned_backups "$MANIFEST_BACKUP_INDEX" > "${list}.own"
    if [ -s "${list}.own" ]; then
      grep -x -F -f "${list}.own" "${list}.all" > "$list" 2>/dev/null || : > "$list"
    else
      : > "$list"
    fi
    rm -f "${list}.own"
  else
    : > "$list"
  fi
  rm -f "${list}.all"
  total="$(wc -l < "$list" | tr -d ' ')"
  if [ "$total" -le "$keep" ]; then
    rm -f "$list" "$pairs"
    return 0
  fi
  excess=$((total - keep))

  # "<mtime>\t<path>" 를 만들고 오름차순(오래된 것 먼저) 한 번 정렬.
  while IFS= read -r victim; do
    [ -n "$victim" ] || continue
    printf '%s\t%s\n' "$(manifest_mtime "$victim")" "$victim"
  done < "$list" | sort -n -k1,1 -k2,2 > "$pairs"

  # 앞에서부터 excess 개 = 가장 오래된 것들
  while IFS= read -r victim; do
    [ "$excess" -gt 0 ] || break
    victim="${victim#*	}"
    [ -n "$victim" ] || continue
    [ -f "$victim" ] || continue          # 일반 파일만 (rm -rf 로 남의 디렉토리를 지우지 않는다)
    rm -f "$victim"
    excess=$((excess - 1))
  done < "$pairs"

  rm -f "$list" "$pairs"
}
