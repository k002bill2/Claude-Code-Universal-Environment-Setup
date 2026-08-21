#!/bin/bash
# ============================================================================
# lib/merge-settings.sh — settings.json 조각(fragment) 병합 엔진 (공용)
# ----------------------------------------------------------------------------
# 사용법 (install.sh 등에서 source 후):
#   merge_settings_fragment   <settings.json 경로> <fragment.json 경로>
#   unmerge_settings_fragment <settings.json 경로> <fragment id>
#
# ── 소유권(ownership) 모델 ─────────────────────────────────────────────
# hook 의 identity 는 (event, matcher, command) 세 값이다. matcher 는 부재 시
# "" 로 정규화하고, 탭·개행은 공백으로 정규화한다. 이 identity 가 곧 기본키라
# "추가 / 중복제거 / 제거" 가 모두 같은 연산으로 표현된다.
#
#   - 추가 : 같은 (event, matcher) 엔트리가 있으면 그 hooks[] 에 없는 command 만
#            더한다. 없으면 엔트리를 새로 append 한다.
#            → 부분중복(같은 엔트리를 통째로 다시 붙여 command 가 두 번 실행)이
#              구조적으로 불가능하다.
#   - 제거 : manifest 에 기록된 "이전 설치가 소유한" identity 중 이번 fragment 에
#            없는 것만 지운다. 사용자가 직접 넣은 hook 은 manifest 에 없으므로
#            절대 지워지지 않는다.
#   - permissions.allow 도 같은 규칙(문자열 자체가 identity).
#
# manifest 파일(MERGE_MANIFEST)의 레코드 형식(탭 구분):
#   <fragment-id>\thook\t<event>\t<matcher>\t<command>
#   <fragment-id>\tperm\tallow\t<rule>
# fragment-id 는 fragment 파일의 basename 이다.
#
# MERGE_LEGACY_REMOVALS: manifest 가 아직 없는 기존 설치를 보수적으로 이주시키기
#   위한 목록. "구버전 installer 가 소유했던 것으로 확정된" identity 만 넣는다
#   (id 접두 없는 레코드, 개행 구분). manifest 가 이미 있으면 무시한다 —
#   한 번 이주한 뒤에는 manifest 가 유일한 소유 근거다.
#
# ── 그 밖의 계약 ────────────────────────────────────────────────────────
#   - 기타 최상위 키(env, model, plugins, mcp, sandbox, permissions.deny/ask ...)
#     : 기존 값 우선, 키 순서 보존. fragment 에만 있는 키는 뒤에 추가.
#   - settings 가 없으면 빈 객체에서 시작해 같은 병합 경로를 탄다
#     → 신규 생성 결과와 재실행 병합 결과의 직렬화가 항상 일치(멱등).
#   - 결과가 기존과 동일하면 무변경. 다르면 백업 후 쓰기.
#   - 백업은 bounded: 같은 파일당 최대 MERGE_BACKUP_KEEP(기본 3)개만 남긴다.
#   - jq 우선, 실패하거나 없으면 node 폴백. 둘 다 실패하면 return 2 (fail-closed:
#     malformed JSON 이면 대상 파일을 건드리지 않고 실패를 반환한다).
#   - jq 경로와 node 폴백은 같은 입력에 대해 바이트 동일한 결과를 낸다.
#
# 반환(전역 변수):
#   MERGE_STATUS      = created | merged | unchanged | failed
#   MERGE_BACKUP_PATH = 백업이 만들어졌을(또는 만들어질) 때 그 경로, 아니면 빈 문자열
#   MERGE_NEW_RECORDS = 이번에 소유하게 된 manifest 레코드(개행 구분, id 접두 포함)
# 환경:
#   MERGE_DRY_RUN=1        → 파일을 쓰지 않고 '[DRY RUN] Would ...' 출력만
#   MERGE_MANIFEST=<path>  → 소유권 manifest 경로 (미설정이면 소유 추적 없음)
#   MERGE_LEGACY_REMOVALS  → 위 참조
#   MERGE_BACKUP_KEEP=<n>  → 백업 보존 개수 (기본 3)
#
# 제약: bash 3.2 호환(연관배열·소문자변환 미사용), 모든 경로 인용.
# ============================================================================

MERGE_STATUS=""
MERGE_BACKUP_PATH=""
MERGE_NEW_RECORDS=""

msf_log() { printf '  %s\n' "$1"; }

# ──────────────────────────────────────────────────────────────────────
# 백업: <file>.bak → .bak.1 → .bak.2 ... 그리고 bounded retention
# ──────────────────────────────────────────────────────────────────────
# 원자적 교체(mv)는 임시 파일의 모드를 그대로 가져온다. 의도적으로 0600 으로
# 둔 settings.json 이 업그레이드 한 번에 0644 가 되면 안 된다.
# settings.json 이 심볼릭 링크(dotfiles 관리)면 `mv` 가 링크를 일반 파일로
# 대체해 링크가 조용히 끊긴다. 링크는 사용자가 의도해서 만든 것이므로 보존하고
# **대상 파일**을 갱신한다. 순환 링크는 32회에서 포기한다.
# 방금 만든 백업으로 settings 를 되돌린다 (기록 실패 시 부분 적용 방지).
msf_restore_from_backup() {
  local settings="$1"
  [ -n "${MERGE_BACKUP_PATH:-}" ] || return 0
  [ -f "$MERGE_BACKUP_PATH" ] || return 0
  [ "${MERGE_DRY_RUN:-0}" = "1" ] && return 0
  cp -p "$MERGE_BACKUP_PATH" "$(msf_resolve_link "$settings")" 2>/dev/null || true
  return 0
}

msf_resolve_link() {
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

msf_copy_mode() {
  local src="$1" dst="$2" m
  [ -f "$src" ] || return 0
  m="$(stat -c '%a' "$src" 2>/dev/null || stat -f '%Lp' "$src" 2>/dev/null)" || return 0
  case "$m" in
    ''|*[!0-7]*) return 0 ;;
  esac
  chmod "$m" "$dst" 2>/dev/null || true
  return 0
}

# `-e` 는 깨진 링크에 거짓이다. 링크만 있는 경로를 빈 슬롯으로 골라 `cp -p` 가
# 링크를 따라 관리 루트 밖을 덮어쓰는 것을 막으려면 `-L` 도 함께 봐야 한다.
msf_backup_path() {
  local f="$1"
  if [ ! -e "$f.bak" ] && [ ! -L "$f.bak" ]; then
    printf '%s' "$f.bak"
    return
  fi
  local i=1
  while [ -e "$f.bak.$i" ] || [ -L "$f.bak.$i" ]; do
    i=$((i + 1))
  done
  printf '%s' "$f.bak.$i"
}

# 같은 원본의 백업이 MERGE_BACKUP_KEEP 개를 넘으면 오래된 것부터 삭제한다.
# (무한 .bak 증식 방지 — 오래됨의 기준은 mtime)
msf_mtime() {
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

# 같은 원본의 백업이 MERGE_BACKUP_KEEP 개를 넘으면 **가장 오래된 것부터** 삭제한다.
#
# 이전 구현은 `find ... | xargs -I{} ls -td {} | tail -1` 이었다. `-I{}` 는
# 인자당 ls 를 한 번씩 실행하므로 `ls -t` 의 정렬이 각 호출 안에서 파일 1개를
# 정렬하는 무의미한 연산이 된다. 결과 순서는 find 의 디렉토리 나열 순서(APFS 는
# 해시 기반이라 재현성이 없다)이고, tail -1 은 그중 임의의 하나를 고른다 —
# 최신 백업이 지워지고 오래된 것이 남는 일이 실제로 발생했다.
# 지금은 mtime 을 직접 읽어 **한 번만** 정렬하고, 오래된 순으로 excess 개를 지운다.
# settings 백업도 "설치기가 만든 것" 만 정리한다 (lib/manifest.sh 와 같은 계약).
# 이름만 보고 지우면 사용자가 같은 이름으로 둔 파일을 지운다.
msf_backup_index() {
  [ -n "${MERGE_MANIFEST:-}" ] || { printf ''; return 0; }
  printf '%s/.settings-backups' "$(dirname "$MERGE_MANIFEST")"
}

# 이식 가능한 내용 해시 (lib/manifest.sh 를 source 하지 않는 경로에서도 쓰인다)
msf_hash_file() {
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

# 경로만으로는 소유를 말할 수 없다 — 우리 백업이 지워진 뒤 사용자가 같은 이름을
# 재사용하면 그 파일이 "우리 것" 으로 지워진다. 경로 + 그 시점 해시를 적는다.
msf_backup_record() {
  local bak="$1" idx h
  idx="$(msf_backup_index)"
  [ -n "$idx" ] || return 0
  mkdir -p "$(dirname "$idx")" 2>/dev/null || return 0
  h="$(msf_hash_file "$bak")"
  printf '%s\t%s\n' "$bak" "$h" >> "$idx"
  return 0
}

msf_owned_backups() {
  local idx="$1" bp bh
  [ -f "$idx" ] || return 0
  while IFS="$(printf '\t')" read -r bp bh; do
    [ -n "$bp" ] || continue
    [ -f "$bp" ] || continue
    [ -n "$bh" ] || continue
    [ "$(msf_hash_file "$bp")" = "$bh" ] || continue
    printf '%s\n' "$bp"
  done < "$idx" | sort -u
}

msf_prune_backups() {
  local f="$1"
  local keep="${MERGE_BACKUP_KEEP:-3}"
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
  local idx; idx="$(msf_backup_index)"
  if [ -n "$idx" ] && [ -f "$idx" ]; then
    msf_owned_backups "$idx" > "${list}.own"
    if [ -s "${list}.own" ]; then
      grep -x -F -f "${list}.own" "${list}.all" > "$list" 2>/dev/null || : > "$list"
    else
      : > "$list"
    fi
    rm -f "${list}.own"
  else
    # 색인을 못 쓰면(생성 실패·디렉토리 등) **아무것도 지우지 않는다**.
    # "전부 우리 것" 으로 되돌아가면 사용자가 만든 settings.json.bak* 가
    # 상한을 넘는 순간 삭제된다 — 모르면 건드리지 않는 쪽이 맞다.
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
    printf '%s\t%s\n' "$(msf_mtime "$victim")" "$victim"
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

# ──────────────────────────────────────────────────────────────────────
# 레코드 추출: fragment 가 선언하는 소유 identity 목록 (탭 구분, 개행 구분)
# ──────────────────────────────────────────────────────────────────────
MSF_JQ_EXTRACT='
  def nrm: (. // "") | tostring | gsub("[\t\n]"; " ");
  [ ( (.hooks // {}) | to_entries[] as $e
      | $e.key as $ev
      | ($e.value // [])[] as $entry
      | ($entry.matcher | nrm) as $mt
      | (($entry.hooks // [])[] | select(.command != null))
      | "hook\t" + $ev + "\t" + $mt + "\t" + (.command | nrm) ),
    ( ((.permissions.allow // [])[] | tostring) | "perm\tallow\t" + . )
  ] | unique | .[]
'

MSF_NODE_EXTRACT='
  var fs = require("fs");
  function nrm(s) { return String(s == null ? "" : s).replace(/[\t\n]/g, " "); }
  var frag = JSON.parse(fs.readFileSync(process.env.MSF_FRAGMENT, "utf8"));
  var out = [];
  var fh = frag.hooks || {};
  Object.keys(fh).forEach(function (ev) {
    (fh[ev] || []).forEach(function (entry) {
      var mt = nrm(entry && entry.matcher);
      ((entry && entry.hooks) || []).forEach(function (hk) {
        if (hk && hk.command != null) out.push("hook\t" + ev + "\t" + mt + "\t" + nrm(hk.command));
      });
    });
  });
  (((frag.permissions || {}).allow) || []).forEach(function (r) {
    out.push("perm\tallow\t" + String(r));
  });
  out = out.filter(function (v, i) { return out.indexOf(v) === i; }).sort();
  process.stdout.write(out.join("\n") + (out.length ? "\n" : ""));
'

# ──────────────────────────────────────────────────────────────────────
# 병합 프로그램
#   $fragdoc[0] = fragment 문서
#   $removals   = 제거 대상 레코드(탭 구분 줄바꿈 텍스트)
# ──────────────────────────────────────────────────────────────────────
MSF_JQ_MERGE='
  def nrm: (. // "") | tostring | gsub("[\t\n]"; " ");

  $fragdoc[0] as $frag
  | . as $orig
  | ($removals | split("\n") | map(select(length > 0)) | map(split("\t"))) as $rm
  | ($rm | map(select(.[0] == "hook"))) as $rmh
  | ($rm | map(select(.[0] == "perm" and .[1] == "allow")) | map(.[2])) as $rmp

  # 1) 최상위: 기존 키 순서·값 보존, fragment 에만 있는 키를 뒤에 추가.
  #    hooks / permissions 는 아래 전용 로직이 소유하므로 여기서 통째 복사하지
  #    않는다 — 통째로 복사하면 identity 병합을 우회해 조각 내부 중복이 그대로
  #    settings 에 들어간다.
  | (reduce ($frag | keys_unsorted[]
             | select(. != "hooks" and . != "permissions")) as $k ($orig;
      if has($k) then . else .[$k] = $frag[$k] end)) as $base

  # 2a) hooks: 소유 stale identity 제거 → 빈 엔트리·빈 이벤트 정리
  #     제거는 identity 당 **1개만** 한다. 사용자가 같은 identity 를 하나 더 넣어
  #     두었을 때 전부 지우면 사용자 것까지 사라진다.
  | ( $rmh | map(.[1] + "\u001f" + .[2] + "\u001f" + .[3]) ) as $rmkeys
  | ( [ (($base.hooks // {}) | to_entries[]) as $e
        | range(0; ($e.value | length)) as $i
        | range(0; ((($e.value[$i].hooks) // []) | length)) as $j
        | { k: ($e.key + "\u001f" + (($e.value[$i].matcher) | nrm)
                       + "\u001f" + (($e.value[$i].hooks[$j].command) | nrm)),
            p: ($e.key + "\u001f" + ($i | tostring) + "\u001f" + ($j | tostring)) } ] ) as $flat
  | ( reduce $flat[] as $f ({used: {}, drop: []};
        if (($rmkeys | index($f.k)) != null) and ((.used[$f.k] // 0) == 0)
        then (.used[$f.k] = 1 | .drop += [$f.p])
        else . end ) | .drop ) as $drop
  | (($base.hooks // {})
      | with_entries(
          .key as $ev
          | .value = ( (.value // []) | to_entries
              | map( .key as $i | .value as $entry
                     | $entry + { hooks: ( (($entry.hooks) // []) | to_entries
                         | map( select( ($drop
                             | index($ev + "\u001f" + ($i | tostring) + "\u001f" + (.key | tostring))) == null )
                                | .value ) ) } )
              | map(select(((.hooks // []) | length) > 0)) )
        )
      | with_entries(select(((.value // []) | length) > 0))
    ) as $h1

  # 2b) hooks: fragment identity 추가 (같은 matcher 엔트리에 command 단위 병합)
  | (reduce (($frag.hooks // {}) | keys_unsorted[]) as $ev ($h1;
       reduce (($frag.hooks[$ev] // [])[]) as $fentry (.;
         ($fentry.matcher | nrm) as $mt
         | reduce (($fentry.hooks // [])[]) as $fhook (.;
             ($fhook.command | nrm) as $cmd
             | (.[$ev] // []) as $arr
             | ([ $arr | to_entries[] | select((.value.matcher | nrm) == $mt) ] | first) as $slot
             | if $slot == null then
                 .[$ev] = ($arr + [ ($fentry + { hooks: [ $fhook ] }) ])
               elif ((($slot.value.hooks // []) | map(.command | nrm) | index($cmd)) != null) then
                 .
               else
                 .[$ev] = ($arr | (.[$slot.key] |= (.hooks = ((.hooks // []) + [ $fhook ]))))
               end
           )
       )
     )) as $h2

  # 3) permissions: allow 는 (제거 후) 합집합, 나머지 키는 기존 값 우선
  | (($base.permissions // {})) as $p0
  | (if ($frag.permissions != null) then
       (reduce (($frag.permissions) | keys_unsorted[]) as $k ($p0;
          if has($k) then . else .[$k] = $frag.permissions[$k] end))
     else $p0 end) as $p1
  | (if (($p1 | has("allow")) or (($frag.permissions.allow // null) != null)) then
       ($p1 | .allow = ( ((.allow // []) | map(. as $x | select(($rmp | index($x)) == null)))
                         | reduce (($frag.permissions.allow // [])[]) as $x (.;
                             if (index($x) != null) then . else . + [ $x ] end) ))
     else $p1 end) as $p2

  # 4) 조립: 원래 없었고 지금도 비어 있으면 키를 만들지 않는다
  | $base
  | (if (($h2 | length) > 0) or ($base | has("hooks")) then .hooks = $h2 else . end)
  | (if (($p2 | length) > 0) or ($base | has("permissions")) then .permissions = $p2 else . end)
'

MSF_NODE_MERGE='
  var fs = require("fs");
  function nrm(s) { return String(s == null ? "" : s).replace(/[\t\n]/g, " "); }

  var orig = JSON.parse(fs.readFileSync(process.env.MSF_SETTINGS, "utf8"));
  var frag = JSON.parse(fs.readFileSync(process.env.MSF_FRAGMENT, "utf8"));
  var removalsRaw = "";
  if (process.env.MSF_REMOVALS) {
    try { removalsRaw = fs.readFileSync(process.env.MSF_REMOVALS, "utf8"); } catch (e) { removalsRaw = ""; }
  }
  var rm = removalsRaw.split("\n").filter(function (l) { return l.length > 0; })
                      .map(function (l) { return l.split("\t"); });
  var rmHooks = rm.filter(function (r) { return r[0] === "hook"; });
  var rmPerms = rm.filter(function (r) { return r[0] === "perm" && r[1] === "allow"; })
                  .map(function (r) { return r[2]; });
  function has(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }

  // 1) 최상위: 기존 순서·값 보존 + fragment 신규 키
  //    (hooks / permissions 는 아래 전용 로직 소유 — jq 경로와 동일 의미)
  var base = {}, k;
  for (k in orig) { if (has(orig, k)) base[k] = orig[k]; }
  for (k in frag) {
    if (has(frag, k) && !has(orig, k) && k !== "hooks" && k !== "permissions") base[k] = frag[k];
  }

  // 2a) hooks 제거
  var h = JSON.parse(JSON.stringify(base.hooks || {}));
  var h1 = {};
  // 제거는 identity 당 1개만 (jq 경로와 동일 의미)
  var rmKeys = rmHooks.map(function (r) { return r[1] + "\u001f" + r[2] + "\u001f" + r[3]; });
  var rmUsed = {};
  Object.keys(h).forEach(function (ev) {
    var kept = (h[ev] || []).map(function (entry) {
      var mt = nrm(entry && entry.matcher);
      var hooks = ((entry && entry.hooks) || []).filter(function (hk) {
        var key = ev + "\u001f" + mt + "\u001f" + nrm(hk && hk.command);
        if (rmKeys.indexOf(key) >= 0 && !rmUsed[key]) { rmUsed[key] = 1; return false; }
        return true;
      });
      var copy = {};
      for (var kk in entry) { if (has(entry, kk)) copy[kk] = entry[kk]; }
      copy.hooks = hooks;
      return copy;
    }).filter(function (entry) { return (entry.hooks || []).length > 0; });
    if (kept.length > 0) h1[ev] = kept;
  });

  // 2b) hooks 추가 (identity = event + matcher + command)
  var fh = frag.hooks || {};
  Object.keys(fh).forEach(function (ev) {
    (fh[ev] || []).forEach(function (fentry) {
      var mt = nrm(fentry && fentry.matcher);
      ((fentry && fentry.hooks) || []).forEach(function (fhook) {
        var cmd = nrm(fhook && fhook.command);
        var arr = h1[ev] || [];
        var slot = -1;
        for (var i = 0; i < arr.length; i++) {
          if (nrm(arr[i] && arr[i].matcher) === mt) { slot = i; break; }
        }
        if (slot < 0) {
          var copy = {};
          for (var kk in fentry) { if (has(fentry, kk)) copy[kk] = fentry[kk]; }
          copy.hooks = [ fhook ];
          arr = arr.concat([ copy ]);
          h1[ev] = arr;
        } else {
          var existing = (arr[slot].hooks || []).map(function (x) { return nrm(x && x.command); });
          if (existing.indexOf(cmd) < 0) {
            arr[slot].hooks = (arr[slot].hooks || []).concat([ fhook ]);
          }
        }
      });
    });
  });

  // 3) permissions
  var p0 = base.permissions || {};
  var p1 = {};
  for (k in p0) { if (has(p0, k)) p1[k] = p0[k]; }
  var fperm = frag.permissions;
  if (fperm != null) {
    for (k in fperm) { if (has(fperm, k) && !has(p0, k)) p1[k] = fperm[k]; }
  }
  var fragAllow = (fperm && fperm.allow != null) ? fperm.allow : null;
  if (has(p1, "allow") || fragAllow != null) {
    var allow = (p1.allow || []).filter(function (x) { return rmPerms.indexOf(x) < 0; });
    (fragAllow || []).forEach(function (x) { if (allow.indexOf(x) < 0) allow.push(x); });
    p1.allow = allow;
  }

  // 4) 조립
  var out = {};
  for (k in base) { if (has(base, k)) out[k] = base[k]; }
  if (Object.keys(h1).length > 0 || has(base, "hooks")) out.hooks = h1;
  if (Object.keys(p1).length > 0 || has(base, "permissions")) out.permissions = p1;
  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
'

# ──────────────────────────────────────────────────────────────────────
# 엔진 실행 (jq 우선 → node 폴백). 둘 다 실패하면 비영(非零) 반환.
# ──────────────────────────────────────────────────────────────────────
msf_extract_records() {
  local fragment="$1" out=""
  if command -v jq >/dev/null 2>&1; then
    if out="$(jq -r "$MSF_JQ_EXTRACT" "$fragment" 2>/dev/null)"; then
      printf '%s' "$out"
      [ -z "$out" ] || printf '\n'
      return 0
    fi
  fi
  if command -v node >/dev/null 2>&1; then
    if out="$(MSF_FRAGMENT="$fragment" node -e "$MSF_NODE_EXTRACT" 2>/dev/null)"; then
      printf '%s' "$out"
      return 0
    fi
  fi
  return 2
}

msf_render_merged() {
  local settings="$1" fragment="$2" removals="$3" out=""
  if command -v jq >/dev/null 2>&1; then
    if out="$(jq --slurpfile fragdoc "$fragment" --rawfile removals "$removals" \
                 "$MSF_JQ_MERGE" "$settings" 2>/dev/null)" && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  if command -v node >/dev/null 2>&1; then
    if out="$(MSF_SETTINGS="$settings" MSF_FRAGMENT="$fragment" MSF_REMOVALS="$removals" \
                node -e "$MSF_NODE_MERGE" 2>/dev/null)" && [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  return 2
}

# ──────────────────────────────────────────────────────────────────────
# manifest 헬퍼
# ──────────────────────────────────────────────────────────────────────
# manifest 에서 특정 fragment id 가 소유한 레코드(id 접두 제거)를 stdout 으로
# 다른 fragment id 가 아직 소유하고 있는 identity 목록.
# 두 조각이 같은 identity 를 선언할 수 있다. 한쪽을 제거한다고 공유분까지 지우면
# 아직 살아 있는 조각의 배선이 끊긴다.
msf_records_owned_by_others() {
  local manifest="$1" id="$2"
  [ -f "$manifest" ] || return 0
  awk -F '\t' -v id="$id" 'NF >= 2 && $1 != id {
      line = $2
      for (i = 3; i <= NF; i++) line = line "\t" $i
      print line
  }' "$manifest" | sort -u
}

# $1 = 제거 후보 파일(제자리 수정), $2 = manifest, $3 = 이번 fragment id
msf_drop_other_owned() {
  local file="$1" manifest="$2" id="$3" others
  [ -s "$file" ] || return 0
  others="${file}.others"
  msf_records_owned_by_others "$manifest" "$id" > "$others"
  if [ -s "$others" ]; then
    grep -F -x -v -f "$others" "$file" > "${file}.keep" 2>/dev/null || : > "${file}.keep"
    mv "${file}.keep" "$file"
  fi
  rm -f "$others"
  return 0
}

msf_manifest_records() {
  local manifest="$1" id="$2"
  [ -f "$manifest" ] || return 0
  # 첫 필드가 정확히 id 인 줄만. awk 로 탭 필드 분해(경로에 공백 있어도 안전).
  awk -F '\t' -v id="$id" 'NF >= 2 && $1 == id {
      line = $2
      for (i = 3; i <= NF; i++) line = line "\t" $i
      print line
  }' "$manifest"
}

# manifest 에서 특정 fragment id 의 줄을 모두 제거한 결과를 stdout 으로
msf_manifest_without() {
  local manifest="$1" id="$2"
  [ -f "$manifest" ] || return 0
  awk -F '\t' -v id="$id" 'NF >= 1 && $1 != id { print }' "$manifest"
}

# ──────────────────────────────────────────────────────────────────────
# 핵심: fragment 병합
# ──────────────────────────────────────────────────────────────────────
merge_settings_fragment() {
  local settings="$1" fragment="$2"
  MERGE_STATUS="failed"
  MERGE_BACKUP_PATH=""
  MERGE_NEW_RECORDS=""

  if [ ! -f "$fragment" ]; then
    msf_log "merge 실패: fragment 파일 없음: $fragment"
    return 2
  fi

  local manifest="${MERGE_MANIFEST:-}"
  local frag_id
  frag_id="$(basename "$fragment")"

  # 작업용 임시 디렉토리 (실패해도 원본 무변경 보장)
  local tmpdir
  tmpdir="$(mktemp -d)" || { msf_log "merge 실패: 임시 디렉토리 생성 불가"; return 2; }

  # 경로가 존재하는데 일반 파일이 아니면(디렉토리 등) `mv` 가 그 **안으로** 옮기고도
  # "생성 성공" 으로 보고한다 — 정작 쓸 수 있는 settings.json 은 없는 상태다.
  if [ -e "$settings" ] && [ ! -f "$settings" ]; then
    rm -rf "$tmpdir"
    msf_log "merge 실패: settings 경로가 일반 파일이 아님: $settings"
    return 2
  fi

  local base_settings="$settings"
  local creating=false
  if [ ! -f "$settings" ]; then
    creating=true
    base_settings="${tmpdir}/empty-settings.json"
    printf '{}\n' > "$base_settings"
  fi

  # 1) 이번 fragment 가 선언하는 소유 레코드
  local new_records=""
  if ! new_records="$(msf_extract_records "$fragment")"; then
    rm -rf "$tmpdir"
    msf_log "merge 실패: fragment JSON 오류 또는 jq/node 부재: $fragment"
    return 2
  fi
  printf '%s' "$new_records" > "${tmpdir}/new.txt"

  # 2) 이전 소유 레코드 = manifest(있으면) / 없으면 legacy 이주 목록
  local prev_file="${tmpdir}/prev.txt"
  : > "$prev_file"
  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    msf_manifest_records "$manifest" "$frag_id" > "$prev_file"
  fi
  # 이 조각의 소유 기록이 하나도 없으면 = 아직 이주하지 않은 구버전 설치.
  # 파일 존재 여부로 판정하면 안 된다 — manifest 파일은 "첫 조각" 병합에서 생기므로,
  # 같은 실행의 2번째·3번째 조각은 파일이 이미 있다는 이유로 이주에서 누락된다
  # (광범위 권한의 출처인 cli-orchestration.json 이 정확히 그 2번째다).
  if [ ! -s "$prev_file" ] && [ -n "${MERGE_LEGACY_REMOVALS:-}" ]; then
    printf '%s\n' "$MERGE_LEGACY_REMOVALS" > "$prev_file"
  fi

  # 2b) 이번 fragment 가 선언한 identity 중 "병합 전 settings 에 이미 있었고, 우리가
  #     소유한 적도 없는" 것 = 사용자가 직접 넣은 것. 소유로 기록하면 --uninstall 이
  #     사용자 항목을 지운다(README Uninstall Policy 의 보존 계약 위반).
  #     prev 를 빼는 것이 핵심이다 — 빼지 않으면 2회차 실행에서 "이미 settings 에
  #     있으니 사용자 것"으로 오판해 소유 기록이 통째로 비고 uninstall 이 무력화된다.
  local present_file="${tmpdir}/present.txt" foreign_file="${tmpdir}/foreign.txt"
  : > "$present_file"
  : > "$foreign_file"
  msf_extract_records "$base_settings" > "$present_file" 2>/dev/null || : > "$present_file"
  if [ -s "$present_file" ]; then
    if [ -s "$prev_file" ]; then
      grep -F -x -v -f "$prev_file" "$present_file" > "$foreign_file" 2>/dev/null || true
    else
      cp "$present_file" "$foreign_file"
    fi
  fi

  # 3) 제거 대상 = 이전 소유 - 이번 소유
  local removals_file="${tmpdir}/removals.txt"
  : > "$removals_file"
  if [ -s "$prev_file" ]; then
    grep -F -x -v -f "${tmpdir}/new.txt" "$prev_file" > "$removals_file" 2>/dev/null || true
    # new.txt 가 비어 있으면 grep -f 가 전부를 매치로 볼 수 있어 결과가 빈다.
    if [ ! -s "${tmpdir}/new.txt" ]; then
      cp "$prev_file" "$removals_file"
    fi
  fi

  # 3b) 다른 조각이 아직 소유한 identity 는 지우지 않는다
  msf_drop_other_owned "$removals_file" "$manifest" "$frag_id"

  # 4) 병합 결과 계산 (읽기만 — dry-run 에서도 안전)
  local merged=""
  if ! merged="$(msf_render_merged "$base_settings" "$fragment" "$removals_file")" \
     || [ -z "$merged" ]; then
    rm -rf "$tmpdir"
    msf_log "merge 실패: $settings + ${frag_id} (jq/node 부재 또는 JSON 오류)"
    return 2
  fi

  # 5) manifest 갱신 내용 준비 (id 접두 부착)
  #    소유 집합 = 이번 fragment 의 identity - 사용자가 이미 갖고 있던 것
  local owned_file="${tmpdir}/owned.txt"
  : > "$owned_file"
  if [ -s "${tmpdir}/new.txt" ]; then
    if [ -s "$foreign_file" ]; then
      grep -F -x -v -f "$foreign_file" "${tmpdir}/new.txt" > "$owned_file" 2>/dev/null || true
    else
      cp "${tmpdir}/new.txt" "$owned_file"
    fi
  fi
  local new_manifest_lines=""
  if [ -s "$owned_file" ]; then
    new_manifest_lines="$(awk -v id="$frag_id" 'length($0) > 0 { print id "\t" $0 }' "$owned_file")"
  fi
  MERGE_NEW_RECORDS="$new_manifest_lines"

  # 6) 무변경 판정
  if ! $creating && [ "$merged" = "$(cat "$settings")" ]; then
    if ! msf_write_manifest "$manifest" "$frag_id" "$new_manifest_lines" "$tmpdir"; then
      rm -rf "$tmpdir"; return 2
    fi
    rm -rf "$tmpdir"
    MERGE_STATUS="unchanged"
    return 0
  fi

  # 7) 쓰기 (백업 → 원자적 교체 → bounded prune)
  if $creating; then
    if [ "${MERGE_DRY_RUN:-0}" = "1" ]; then
      msf_log "[DRY RUN] Would create: $settings (from ${frag_id})"
    else
      mkdir -p "$(dirname "$settings")"
      printf '%s' "$merged" > "${tmpdir}/out.json"
      mv "${tmpdir}/out.json" "$(msf_resolve_link "$settings")"
      msf_log "write : $settings (from ${frag_id})"
    fi
    if ! msf_write_manifest "$manifest" "$frag_id" "$new_manifest_lines" "$tmpdir"; then
      # 이번 실행이 만든 파일이므로 지워서 "아무 일도 없었던" 상태로 되돌린다.
      [ "${MERGE_DRY_RUN:-0}" = "1" ] || rm -f "$(msf_resolve_link "$settings")"
      rm -rf "$tmpdir"; return 2
    fi
    rm -rf "$tmpdir"
    MERGE_STATUS="created"
    return 0
  fi

  MERGE_BACKUP_PATH="$(msf_backup_path "$settings")"
  if [ "${MERGE_DRY_RUN:-0}" = "1" ]; then
    msf_log "[DRY RUN] Would backup: $settings -> $MERGE_BACKUP_PATH"
    msf_log "[DRY RUN] Would merge : ${frag_id} -> $settings"
  else
    if [ -L "$MERGE_BACKUP_PATH" ]; then
      rm -rf "$tmpdir"
      msf_log "merge 실패: 백업 경로가 심볼릭 링크 — 따라가지 않음: $MERGE_BACKUP_PATH"
      return 2
    fi
    cp -p "$settings" "$MERGE_BACKUP_PATH"
    msf_backup_record "$MERGE_BACKUP_PATH"
    printf '%s' "$merged" > "${tmpdir}/out.json"
    msf_copy_mode "$settings" "${tmpdir}/out.json"
    mv "${tmpdir}/out.json" "$(msf_resolve_link "$settings")"
    msf_prune_backups "$settings"
    msf_log "merge : $settings (+${frag_id}) [backup: $MERGE_BACKUP_PATH]"
  fi
  if ! msf_write_manifest "$manifest" "$frag_id" "$new_manifest_lines" "$tmpdir"; then
    # settings 는 이미 바뀌었다. 기록을 남기지 못하면 그 훅들은 영원히 uninstall
    # 대상이 되지 못하므로, 부분 적용을 남기지 말고 직전 상태로 되돌린다.
    msf_restore_from_backup "$settings"
    rm -rf "$tmpdir"; return 2
  fi
  rm -rf "$tmpdir"
  MERGE_STATUS="merged"
  return 0
}

# manifest 파일에서 이 fragment id 의 줄을 교체한다 (dry-run 은 쓰지 않음)
# 실패를 반드시 반환한다. 기록이 없으면 그 hooks/permissions 는 영원히 --uninstall
# 대상이 되지 못하는데, 조용히 성공으로 보고하면 그 상태가 정상처럼 보인다.
msf_write_manifest() {
  local manifest="$1" id="$2" lines="$3" tmpdir="$4"
  [ -n "$manifest" ] || return 0
  [ "${MERGE_DRY_RUN:-0}" = "1" ] && return 0
  # 경로가 일반 파일이 아니면(예: 디렉토리) `mv` 는 실패하지 않고 그 **안으로**
  # 옮긴다. 그러면 [ -f "$manifest" ] 가 영원히 거짓이라 소유 기록이 조용히 사라진다.
  if [ -e "$manifest" ] && [ ! -f "$manifest" ]; then
    msf_log "merge 실패: 소유 기록 경로가 일반 파일이 아님: $manifest"
    return 1
  fi
  local tmp="${tmpdir}/manifest.txt"
  : > "$tmp" || return 1
  if [ -f "$manifest" ]; then
    msf_manifest_without "$manifest" "$id" > "$tmp" || return 1
  fi
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines" >> "$tmp" || return 1
  fi
  mkdir -p "$(dirname "$manifest")" || return 1
  mv "$tmp" "$(msf_resolve_link "$manifest")" 2>/dev/null || {
    msf_log "merge 실패: 소유 기록을 쓸 수 없음: $manifest"
    return 1
  }
  # 실제로 일반 파일로 자리잡았는지 확인한다 (mv 가 성공해도 위치가 다를 수 있다)
  [ -f "$manifest" ] || {
    msf_log "merge 실패: 소유 기록이 기대한 자리에 없음: $manifest"
    return 1
  }
  return 0
}

# ──────────────────────────────────────────────────────────────────────
# uninstall: 이 fragment id 가 소유한 모든 identity 를 settings 에서 제거
#   (사용자 hook·사용자 allow·알 수 없는 키는 건드리지 않는다)
# ──────────────────────────────────────────────────────────────────────
unmerge_settings_fragment() {
  local settings="$1" frag_id="$2"
  MERGE_STATUS="failed"
  MERGE_BACKUP_PATH=""
  MERGE_NEW_RECORDS=""

  local manifest="${MERGE_MANIFEST:-}"
  if [ -z "$manifest" ] || [ ! -f "$manifest" ]; then
    MERGE_STATUS="unchanged"
    return 0
  fi
  if [ ! -f "$settings" ]; then
    MERGE_STATUS="unchanged"
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)" || return 2

  msf_manifest_records "$manifest" "$frag_id" > "${tmpdir}/removals.txt"
  msf_drop_other_owned "${tmpdir}/removals.txt" "$manifest" "$frag_id"
  if [ ! -s "${tmpdir}/removals.txt" ]; then
    rm -rf "$tmpdir"
    MERGE_STATUS="unchanged"
    return 0
  fi

  printf '{}\n' > "${tmpdir}/empty-frag.json"
  local merged=""
  if ! merged="$(msf_render_merged "$settings" "${tmpdir}/empty-frag.json" "${tmpdir}/removals.txt")" \
     || [ -z "$merged" ]; then
    rm -rf "$tmpdir"
    msf_log "unmerge 실패: $settings (JSON 오류 또는 jq/node 부재)"
    return 2
  fi

  if [ "$merged" = "$(cat "$settings")" ]; then
    if ! msf_write_manifest "$manifest" "$frag_id" "" "$tmpdir"; then
      rm -rf "$tmpdir"; return 2
    fi
    rm -rf "$tmpdir"
    MERGE_STATUS="unchanged"
    return 0
  fi

  MERGE_BACKUP_PATH="$(msf_backup_path "$settings")"
  if [ "${MERGE_DRY_RUN:-0}" = "1" ]; then
    msf_log "[DRY RUN] Would remove ${frag_id} hooks/permissions from: $settings"
  else
    if [ -L "$MERGE_BACKUP_PATH" ]; then
      rm -rf "$tmpdir"
      msf_log "merge 실패: 백업 경로가 심볼릭 링크 — 따라가지 않음: $MERGE_BACKUP_PATH"
      return 2
    fi
    cp -p "$settings" "$MERGE_BACKUP_PATH"
    msf_backup_record "$MERGE_BACKUP_PATH"
    printf '%s' "$merged" > "${tmpdir}/out.json"
    msf_copy_mode "$settings" "${tmpdir}/out.json"
    mv "${tmpdir}/out.json" "$(msf_resolve_link "$settings")"
    msf_prune_backups "$settings"
    msf_log "unmerge : $settings (-${frag_id}) [backup: $MERGE_BACKUP_PATH]"
  fi
  if ! msf_write_manifest "$manifest" "$frag_id" "" "$tmpdir"; then
    msf_restore_from_backup "$settings"
    rm -rf "$tmpdir"; return 2
  fi
  rm -rf "$tmpdir"
  MERGE_STATUS="merged"
  return 0
}
