#!/bin/bash
# ============================================================================
# lib/merge-settings.sh — settings.json 조각(fragment) 병합 엔진 (공용)
# ----------------------------------------------------------------------------
# 사용법 (install.sh 등에서 source 후):
#   merge_settings_fragment <settings.json 경로> <fragment.json 경로>
#
# 병합 계약:
#   - hooks       : 이벤트 단위 append. 엔트리의 command 문자열이 전부 이미
#                   존재하면 추가하지 않음(멱등).
#   - permissions.allow : 배열 합집합 — 기존 순서 보존, 신규만 뒤에 추가(중복 제거).
#   - 기타 최상위 키    : 기존 값 우선(사용자 값 불변). fragment 에만 있는 키는 추가.
#   - 결과가 기존과 동일하면 무변경. 다르면 .bak(.bak.1 ...) 백업 후 쓰기.
#   - settings 파일이 없으면 fragment 를 병합 경로와 동일한 직렬화
#     (jq '.' / JSON.stringify(,null,2))로 정규화해 신규 생성
#     → 2회차 실행이 항상 unchanged 가 되도록 보장.
#   - jq 우선, 없으면 node 폴백. 둘 다 없으면 실패(return 2).
#
# 반환(전역 변수):
#   MERGE_STATUS      = created | merged | unchanged | failed
#   MERGE_BACKUP_PATH = 백업이 만들어졌을(또는 만들어질) 때 그 경로, 아니면 빈 문자열
# 환경:
#   MERGE_DRY_RUN=1   → 파일을 쓰지 않고 '[DRY RUN] Would ...' 출력만
#
# 제약: bash 3.2 호환(연관배열·소문자변환 미사용), 모든 경로 인용.
# (system-setup install.sh 의 검증된 이벤트 단위 딥머지 로직을 이식·일반화함)
# ============================================================================

MERGE_STATUS=""
MERGE_BACKUP_PATH=""

msf_log() { printf '  %s\n' "$1"; }

# <file>.bak, 이미 있으면 .bak.1 .bak.2 ...
msf_backup_path() {
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

# jq 병합 프로그램: $fragdoc[0] = fragment 문서
# - 최상위: 기존 키 순서·값 보존, fragment 에만 있는 키를 뒤에 추가(사용자 값 불변)
#   (주의: $frag + $orig 는 값은 맞지만 키 순서가 fragment-first 로 바뀌어
#    재실행 때마다 diff 가 나는 비멱등을 만든다 — reduce 로 순서를 보존한다)
# - hooks: 이벤트 단위 append + "엔트리의 command 가 전부 기존에 있으면 skip" 멱등
# - permissions.allow: 기존 순서 보존 합집합
MSF_JQ_PROG='
  $fragdoc[0] as $frag
  | . as $orig
  | (reduce ($frag | keys_unsorted[]) as $k ($orig;
      if has($k) then . else .[$k] = $frag[$k] end))
  | (if (($frag.hooks // {}) | length) > 0 then
      .hooks = (
        reduce (($frag.hooks) | keys_unsorted[]) as $ev (($orig.hooks // {});
          (.[$ev] // []) as $existing
          | ([ $existing[] | .hooks[]?.command ]) as $cmds
          | .[$ev] = ($existing + ($frag.hooks[$ev] | map(select(
              ([ .hooks[]?.command | select(($cmds | index(.)) == null) ] | length) > 0
            ))))
        )
      )
    else . end)
  | (if ((($frag.permissions // {}) | .allow) // null) != null then
      .permissions = (
        (($orig.permissions // {})) as $op
        | (reduce (($frag.permissions // {}) | keys_unsorted[]) as $k ($op;
            if has($k) then . else .[$k] = $frag.permissions[$k] end))
        | .allow = (
            (($op | .allow) // []) as $a
            | reduce (($frag.permissions.allow)[]) as $x ($a;
                if (index($x) != null) then . else . + [$x] end)
          )
      )
    else . end)
'

# node 폴백: 위 jq 프로그램과 동일 의미
MSF_NODE_PROG='
  var fs = require("fs");
  var orig = JSON.parse(fs.readFileSync(process.env.MSF_SETTINGS, "utf8"));
  var frag = JSON.parse(fs.readFileSync(process.env.MSF_FRAGMENT, "utf8"));
  var out = {}, k;
  for (k in orig) { if (Object.prototype.hasOwnProperty.call(orig, k)) out[k] = orig[k]; }
  for (k in frag) {
    if (Object.prototype.hasOwnProperty.call(frag, k) && !Object.prototype.hasOwnProperty.call(orig, k)) out[k] = frag[k];
  }
  var fh = frag.hooks || {};
  if (Object.keys(fh).length > 0) {
    var base = JSON.parse(JSON.stringify(orig.hooks || {}));
    var evs = Object.keys(fh);
    for (var i = 0; i < evs.length; i++) {
      var ev = evs[i];
      var existing = base[ev] || [];
      var cmds = Object.create(null);
      for (var a = 0; a < existing.length; a++) {
        var hs = (existing[a] && existing[a].hooks) || [];
        for (var b = 0; b < hs.length; b++) { if (hs[b] && hs[b].command) cmds[hs[b].command] = 1; }
      }
      var incoming = fh[ev] || [];
      for (var c = 0; c < incoming.length; c++) {
        var ehs = (incoming[c] && incoming[c].hooks) || [];
        var hasNew = false;
        for (var d = 0; d < ehs.length; d++) {
          if (ehs[d] && ehs[d].command && !(ehs[d].command in cmds)) { hasNew = true; break; }
        }
        if (hasNew) existing.push(incoming[c]);
      }
      base[ev] = existing;
    }
    out.hooks = base;
  }
  var fperm = frag.permissions || {};
  if (fperm.allow != null) {
    var operm = orig.permissions || {};
    var perm = {};
    for (k in operm) { if (Object.prototype.hasOwnProperty.call(operm, k)) perm[k] = operm[k]; }
    for (k in fperm) {
      if (Object.prototype.hasOwnProperty.call(fperm, k) && !Object.prototype.hasOwnProperty.call(operm, k)) perm[k] = fperm[k];
    }
    var allow = (operm.allow || []).slice();
    var fa = fperm.allow || [];
    for (var j = 0; j < fa.length; j++) { if (allow.indexOf(fa[j]) < 0) allow.push(fa[j]); }
    perm.allow = allow;
    out.permissions = perm;
  }
  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
'

# 병합 결과를 stdout 으로 출력 (jq → node 순, 둘 다 없으면 return 2)
msf_render_merged() {
  local settings="$1" fragment="$2"
  if command -v jq >/dev/null 2>&1; then
    jq --slurpfile fragdoc "$fragment" "$MSF_JQ_PROG" "$settings" 2>/dev/null
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    MSF_SETTINGS="$settings" MSF_FRAGMENT="$fragment" node -e "$MSF_NODE_PROG" 2>/dev/null
    return $?
  fi
  return 2
}

# 신규 생성용: fragment 를 병합 경로와 동일한 직렬화로 정규화해 stdout 출력
msf_normalize_fragment() {
  local fragment="$1"
  if command -v jq >/dev/null 2>&1; then
    jq '.' "$fragment" 2>/dev/null
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    MSF_FRAGMENT="$fragment" node -e 'var fs=require("fs");process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync(process.env.MSF_FRAGMENT,"utf8")),null,2)+"\n");' 2>/dev/null
    return $?
  fi
  return 2
}

merge_settings_fragment() {
  local settings="$1" fragment="$2"
  MERGE_STATUS="failed"
  MERGE_BACKUP_PATH=""

  if [ ! -f "$fragment" ]; then
    msf_log "merge 실패: fragment 파일 없음: $fragment"
    return 2
  fi

  # settings 부재 → 정규화된 fragment 로 신규 생성
  if [ ! -f "$settings" ]; then
    local normalized=""
    if ! normalized="$(msf_normalize_fragment "$fragment")" || [ -z "$normalized" ]; then
      msf_log "merge 실패: jq/node 부재 또는 fragment JSON 오류: $fragment"
      return 2
    fi
    if [ "${MERGE_DRY_RUN:-0}" = "1" ]; then
      msf_log "[DRY RUN] Would create: $settings (from $(basename "$fragment"))"
    else
      mkdir -p "$(dirname "$settings")"
      printf '%s\n' "$normalized" > "$settings"
      msf_log "write : $settings (from $(basename "$fragment"))"
    fi
    MERGE_STATUS="created"
    return 0
  fi

  # settings 존재 → 병합 (읽기만으로 결과 계산, dry-run 에서도 안전)
  local merged=""
  if ! merged="$(msf_render_merged "$settings" "$fragment")" || [ -z "$merged" ]; then
    msf_log "merge 실패: $settings + $(basename "$fragment") (jq/node 부재 또는 JSON 오류)"
    return 2
  fi

  if [ "$merged" = "$(cat "$settings")" ]; then
    MERGE_STATUS="unchanged"
    return 0
  fi

  MERGE_BACKUP_PATH="$(msf_backup_path "$settings")"
  if [ "${MERGE_DRY_RUN:-0}" = "1" ]; then
    msf_log "[DRY RUN] Would backup: $settings -> $MERGE_BACKUP_PATH"
    msf_log "[DRY RUN] Would merge : $(basename "$fragment") -> $settings"
  else
    cp -p "$settings" "$MERGE_BACKUP_PATH"
    printf '%s\n' "$merged" > "$settings"
    msf_log "merge : $settings (+$(basename "$fragment")) [backup: $MERGE_BACKUP_PATH]"
  fi
  MERGE_STATUS="merged"
  return 0
}
