#!/bin/bash
# ============================================================================
# install.sh — Claude Code 최소 생존 셋업 설치기
# ----------------------------------------------------------------------------
# 사용법: ./install.sh <target-project-dir>
#
# 설치하는 것 (최소 생존 셋업만):
#   .claude/commands/{dev-docs,update-dev-docs,resume,save-and-compact}.md
#   .claude/hooks/{skill-activator.sh, pre-compact-reminder.sh}   (chmod +x)
#   .claude/skill-rules.json        (advisory 예시 규칙 — 최초 1회만, 이후 사용자 소유)
#   .claude/settings.json           (실제 동작하는 훅 2개만 배선 — 이벤트 단위 딥머지)
#   .claude/MODELS.md               (모델 ID SSOT)
#   CLAUDE.md                       (템플릿 최소본, 이미 있으면 스킵)
#   dev/active/.gitkeep
#
# 설치하지 않는 것 (의도적 제외):
#   - GSD / Gstack (별도 서드파티 스킬 팩 — 필요 시 각자 설치)
#   - 강제 다중에이전트 / 3역할 훅 / 페르소나 시뮬레이션
#   - PM2 / git worktree 자동화 (필요 시 수동 구성)
#   - deny 반환 PreToolUse 강제 훅 (본 셋업의 훅은 전부 advisory)
#
# 훅 성격: 여기서 배선하는 UserPromptSubmit(skill-activator) / PreCompact 훅은
#          stdout 리마인더만 내보내는 advisory 훅이다. 작업/도구를 차단하지 않는다.
#          (UserPromptSubmit 이벤트 자체는 exit 2 또는 {"decision":"block"} 로 차단
#           가능하고, 특정 도구 거부는 PreToolUse 의 permissionDecision:"deny" 가
#           담당하지만, 본 셋업은 그중 어느 차단 경로도 배선하지 않는다.)
#
# 참고: 아래 skill-activator.sh 내용은 문서(claude_code_setup_prompt.md)의
#       STEP 6 스크립트와 글자 그대로 동일해야 한다 (jq→node→shell 폴백 포함).
# ============================================================================

set -euo pipefail

# ---- 요약 추적용 배열 (bash 3.2: 빈 배열 순회는 반드시 길이 가드) --------------
INSTALLED=()
SKIPPED=()
BACKED_UP=()
UNCHANGED=()

log() { printf '  %s\n' "$1"; }

# ---- 인자 검증 --------------------------------------------------------------
if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <target-project-dir>" >&2
  exit 1
fi

TARGET="$1"

if [ ! -d "$TARGET" ]; then
  echo "[install] 대상 디렉토리가 없어 생성합니다: $TARGET"
  mkdir -p "$TARGET"
fi

# 절대경로로 정규화 (로그 가독성)
TARGET="$(cd "$TARGET" && pwd)"
CLAUDE_DIR="$TARGET/.claude"

echo "[install] 대상: $TARGET"

# ---- 도구 감지 --------------------------------------------------------------
HAVE_JQ=0
HAVE_NODE=0
if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; fi
if command -v node >/dev/null 2>&1; then HAVE_NODE=1; fi

if [ "$HAVE_JQ" -eq 1 ]; then
  echo "[install] jq 감지됨 — settings 병합/skill-activator 는 jq 경로로 동작."
elif [ "$HAVE_NODE" -eq 1 ]; then
  echo "[install] jq 없음 → node 폴백으로 settings 병합/파싱을 수행합니다."
else
  echo "[install] 경고: jq·node 모두 없음 — settings 자동 병합 불가(기존 파일이 있으면 수동 병합 안내)."
fi

# ---- 백업 경로 계산: <file>.bak, 이미 있으면 .bak.1 .bak.2 ... ---------------
backup_path() {
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

# ---- 관리 파일 설치: 내용이 같으면 백업·쓰기 생략(멱등), 다를 때만 백업 후 갱신 -----
# stdin 으로 파일 내용을 받는다.
install_managed() {
  local path="$1"
  local content
  content="$(cat)"
  mkdir -p "$(dirname "$path")"
  if [ -e "$path" ]; then
    if [ "$content" = "$(cat "$path")" ]; then
      log "unchanged: $path"
      UNCHANGED+=("$path")
      return
    fi
    local bak
    bak="$(backup_path "$path")"
    cp -p "$path" "$bak"
    log "backup: $path -> $bak"
    BACKED_UP+=("$path -> $bak")
  fi
  printf '%s\n' "$content" > "$path"
  log "write : $path"
  INSTALLED+=("$path")
}

# ---- 존재하면 절대 덮지 않는 설치 (CLAUDE.md, skill-rules.json 용) -------------
install_skip_if_exists() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  if [ -e "$path" ]; then
    cat > /dev/null   # stdin 소비
    log "skip  : $path (이미 존재 — 덮지 않음)"
    SKIPPED+=("$path (이미 존재)")
    return
  fi
  cat > "$path"
  log "write : $path"
  INSTALLED+=("$path")
}

# ===========================================================================
# 1. .claude/commands/*.md  (dev/active/<task>/ 3파일 시스템 슬래시커맨드)
# ===========================================================================
install_managed "$CLAUDE_DIR/commands/dev-docs.md" <<'DEVDOCS_EOF'
---
description: Create comprehensive dev docs for approved plan
---

Based on the approved plan, create three development documents:

1. Create `dev/active/$ARGUMENTS/[task-name]-plan.md`
   - Copy the full approved plan
   - Add timeline and phases
   - Include success metrics

2. Create `dev/active/$ARGUMENTS/[task-name]-context.md`
   - List all relevant files
   - Document key architectural decisions
   - Note any constraints or dependencies
   - Add "Next Steps" section
   - Timestamp: current date

3. Create `dev/active/$ARGUMENTS/[task-name]-tasks.md`
   - Convert plan into detailed checklist
   - Group by component/service
   - Use checkbox format [ ] / [x]
   - Add completion counts per section

$ARGUMENTS is the task name (e.g., user-dashboard).
If not provided, ask the user for the task name.
DEVDOCS_EOF

install_managed "$CLAUDE_DIR/commands/update-dev-docs.md" <<'UPDATE_EOF'
---
description: Update dev docs before context compaction or session end
---

Find the active dev docs in `dev/active/` and update:

1. **context.md**:
   - Update "Last Updated" timestamp
   - Add any new decisions made this session
   - Update "Current Issues" section
   - Revise "Next Steps" based on progress

2. **tasks.md**:
   - Mark completed items with [x]
   - Add any new tasks discovered
   - Update completion counts
   - Reorder by priority if needed

3. **Add session summary** (append to context.md):
   - What was accomplished
   - Any blockers encountered
   - Critical next actions

Keep updates concise but comprehensive.
UPDATE_EOF

install_managed "$CLAUDE_DIR/commands/resume.md" <<'RESUME_EOF'
---
description: Resume work from dev docs after session restart or compaction
---

Resume the current development task:

1. Find active task in `dev/active/`
2. Read all three files:
   - plan.md → understand the overall plan
   - context.md → understand current state and decisions
   - tasks.md → identify next uncompleted tasks
3. Summarize:
   - Overall progress (X/Y tasks complete)
   - What was last worked on
   - What should be done next
4. Ask user to confirm the next steps before proceeding

If multiple active tasks exist, list them and ask which to resume.
RESUME_EOF

install_managed "$CLAUDE_DIR/commands/save-and-compact.md" <<'SAVE_EOF'
---
description: Save context to dev docs and run /compact
---

Before compaction, save all progress:

1. Run the /update-dev-docs workflow (update context.md, tasks.md)
2. Save any important decisions or learnings to memory if applicable
3. Confirm save is complete
4. Then run /compact

This ensures no context is lost during compaction.
SAVE_EOF

# ===========================================================================
# 2. .claude/hooks/*.sh
#    skill-activator.sh 는 문서 STEP 6 과 글자 그대로 동일 (jq→node→shell 폴백 포함)
# ===========================================================================
install_managed "$CLAUDE_DIR/hooks/skill-activator.sh" <<'ACTIVATOR_EOF'
#!/bin/bash
# Skills Auto-Activator
# Usage: skill-activator.sh "<prompt>"   (또는 stdin 으로 UserPromptSubmit JSON 전달)
# 프롬프트 소싱: $1 인자 우선, 없으면 stdin JSON(.prompt). 실제 UserPromptSubmit 는 stdin JSON 계약.
# advisory 훅: 관련 스킬을 stdout 리마인더로 추천할 뿐 작업을 차단하지 않는다.

PROMPT="$1"

# 프롬프트 소싱: $1 인자 우선. 없으면 stdin(파이프)에서 UserPromptSubmit JSON 을 읽는다.
# 실제 Claude Code UserPromptSubmit 훅은 프롬프트를 stdin JSON({"prompt":"..."})으로 전달하며
# $PROMPT 환경변수를 보장하지 않는다 — 따라서 stdin 폴백이 반드시 필요하다.
# 파싱 우선순위: jq → node(JSON.parse, 포맷 무관) → sed(최후 best-effort).
if [ -z "$PROMPT" ] && [ ! -t 0 ]; then
  RAW="$(cat)"
  if command -v jq >/dev/null 2>&1; then
    PROMPT="$(printf '%s' "$RAW" | jq -r '.prompt // empty' 2>/dev/null)"
  fi
  if [ -z "$PROMPT" ] && command -v node >/dev/null 2>&1; then
    PROMPT="$(printf '%s' "$RAW" | node -e 'let d="";process.stdin.on("data",function(c){d+=c;}).on("end",function(){try{process.stdout.write(String(JSON.parse(d).prompt||""));}catch(e){}});' 2>/dev/null)"
  fi
  if [ -z "$PROMPT" ]; then
    # best-effort 셸 폴백: 한 줄 "prompt":"..." 만 대략 추출(정밀 파싱 아님).
    PROMPT="$(printf '%s' "$RAW" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
  fi
  if [ -z "$PROMPT" ]; then
    PROMPT="$RAW"
  fi
fi

# skill-rules.json 위치: CLAUDE_PROJECT_DIR/.claude(설치기 레이아웃) → 훅과 같은 폴더
# (문서 레이아웃) → 훅 상위 .claude/ 루트 순으로 존재하는 첫 파일을 사용.
HOOK_DIR="$(dirname "$0")"
RULES_FILE=""
for cand in \
  "${CLAUDE_PROJECT_DIR:-}/.claude/skill-rules.json" \
  "$HOOK_DIR/skill-rules.json" \
  "$HOOK_DIR/../skill-rules.json"; do
  if [ -f "$cand" ]; then RULES_FILE="$cand"; break; fi
done
if [ -z "$RULES_FILE" ]; then
  exit 0
fi

MATCHED=""

if command -v jq >/dev/null 2>&1; then
  # jq 경로: 짧은(≤3자) ASCII 키워드는 단어 경계, 그 외/한글은 substring (배열 포맷 무관).
  MATCHED=$(jq -r --arg prompt "$PROMPT" '
    ($prompt | ascii_downcase) as $p |
    .rules[] |
    select(
      any(.keywords[];
        (ascii_downcase) as $kw |
        if (($kw | length) <= 3) and ($kw | test("^[ -~]+$"))
        then ($p | test("(^|[^a-z0-9])" + $kw + "([^a-z0-9]|$)"))
        else ($p | contains($kw))
        end)
    ) |
    "\(.priority | ascii_upcase): \(.skillName)"
  ' "$RULES_FILE" 2>/dev/null | sort -u)
elif command -v node >/dev/null 2>&1; then
  # node 폴백: JSON.parse 로 포맷 무관하게 .rules[] 를 읽어 키워드 매칭.
  MATCHED=$(RULES_FILE="$RULES_FILE" PROMPT="$PROMPT" node -e '
    var fs=require("fs");
    try{
      var data=JSON.parse(fs.readFileSync(process.env.RULES_FILE,"utf8"));
      var rules=(data&&data.rules)||[];
      var p=String(process.env.PROMPT||"").toLowerCase();
      var out={};
      for(var i=0;i<rules.length;i++){
        var r=rules[i]||{};
        var kws=r.keywords||[];
        for(var j=0;j<kws.length;j++){
          var kw=String(kws[j]).toLowerCase();
          var hit;
          if(kw.length<=3 && /^[\x20-\x7e]+$/.test(kw)){
            var esc=kw.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
            hit=new RegExp("(^|[^a-z0-9])"+esc+"([^a-z0-9]|$)").test(p);
          }else{
            hit=p.indexOf(kw)>=0;
          }
          if(hit){
            out[String(r.priority||"").toUpperCase()+": "+r.skillName]=1; break;
          }
        }
      }
      process.stdout.write(Object.keys(out).sort().join("\n"));
    }catch(e){}
  ' 2>/dev/null)
else
  # 최후 shell best-effort: jq·node 둘 다 없을 때만. keywords 가 한 줄 배열이라고
  # 가정하고 라인 단위로 훑는다(멀티라인 배열/콤마 포함 키워드는 매칭 못 할 수 있음).
  PROMPT_LC=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')
  MATCHED=$(awk -v prompt="$PROMPT_LC" '
    /"skillName"/ { name=$0; sub(/.*"skillName"[^"]*"/,"",name); sub(/".*/,"",name) }
    /"priority"/  { prio=$0; sub(/.*"priority"[^"]*"/,"",prio);  sub(/".*/,"",prio) }
    /"keywords"/  {
      kw=$0; sub(/.*\[/,"",kw); sub(/\].*/,"",kw)
      n=split(kw, arr, ",")
      for (i=1;i<=n;i++) {
        k=arr[i]
        gsub(/^[ \t"]+/,"",k); gsub(/[ \t"]+$/,"",k)
        kl=tolower(k)
        if (kl == "") continue
        if (length(kl) <= 3 && kl !~ /[^ -~]/) {
          if (match(prompt, "(^|[^[:alnum:]])" kl "([^[:alnum:]]|$)")) { print toupper(prio) ": " name; break }
        } else {
          if (index(prompt, kl) > 0) { print toupper(prio) ": " name; break }
        }
      }
    }
  ' "$RULES_FILE" | sort -u)
fi

if [ -n "$MATCHED" ]; then
  echo "[SKILLS ACTIVATED]"
  echo "$MATCHED"
  echo "(advisory: 위 스킬 참조 권장 — 이 훅은 리마인더일 뿐 작업을 차단하지 않음)"
fi
ACTIVATOR_EOF
chmod +x "$CLAUDE_DIR/hooks/skill-activator.sh"

install_managed "$CLAUDE_DIR/hooks/pre-compact-reminder.sh" <<'PRECOMPACT_EOF'
#!/bin/bash
# Pre-Compaction Reminder — 컨텍스트 압축 직전 스킬/Dev Docs 상태를 stdout 으로
# 리마인더 출력(advisory). 경로는 CLAUDE_PROJECT_DIR 로 앵커링(없으면 cwd).

ROOT="${CLAUDE_PROJECT_DIR:-.}"

echo "[PRE-COMPACT REMINDER]"

# 사용 가능한 스킬 목록
if [ -d "$ROOT/.claude/skills" ]; then
  SKILLS=$(ls -d "$ROOT"/.claude/skills/*/ 2>/dev/null | xargs -I{} basename {})
  if [ -n "$SKILLS" ]; then
    echo "Available skills: $SKILLS"
  fi
fi

# 활성 Dev Docs 확인
if [ -d "$ROOT/dev/active" ]; then
  ACTIVE=$(ls "$ROOT/dev/active" 2>/dev/null)
  if [ -n "$ACTIVE" ]; then
    echo "Active dev docs: $ACTIVE"
    echo "Run: '/resume' to continue work"
  fi
fi
PRECOMPACT_EOF
chmod +x "$CLAUDE_DIR/hooks/pre-compact-reminder.sh"

# ===========================================================================
# 3. .claude/skill-rules.json  (advisory 예시 규칙; 최초 1회만 — 이후 사용자 소유)
#    keywords 는 skill-activator.sh 의 shell 폴백을 위해 한 줄 배열로 둔다.
# ===========================================================================
install_skip_if_exists "$CLAUDE_DIR/skill-rules.json" <<'RULES_EOF'
{
  "rules": [
    {
      "skillName": "code-reviewer",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["review", "PR", "pull request", "코드 리뷰", "검토"]
    },
    {
      "skillName": "frontend-dev-guidelines",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["react", "component", "hooks", "frontend"]
    },
    {
      "skillName": "backend-dev-guidelines",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["backend", "api endpoint", "endpoint", "service"]
    },
    {
      "skillName": "dev-docs",
      "priority": "medium",
      "enforcement": "suggest",
      "keywords": ["dev docs", "plan", "대규모", "컨텍스트"]
    }
  ]
}
RULES_EOF

# ===========================================================================
# 4. .claude/settings.json  (동작하는 advisory 훅 2개만 — 이벤트 단위 딥머지)
#    기존 .hooks 는 보존하고 UserPromptSubmit/PreCompact 배열에 우리 엔트리를
#    append 하되, 동일 command 가 이미 있으면 skip(멱등). 경로는 CLAUDE_PROJECT_DIR 앵커.
#    enforcement 강제(deny)는 미구현 — 배선 훅은 전부 advisory.
# ===========================================================================
SETTINGS_JSON=$(cat <<'SETTINGS_EOF'
{
  "model": "claude-sonnet-5",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/skill-activator.sh\"" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-compact-reminder.sh\"" }
        ]
      }
    ]
  }
}
SETTINGS_EOF
)

# 이벤트 단위 딥머지 jq 프로그램: 기존 .hooks 보존 + 우리 이벤트 배열에 append,
# 단 동일 command 가 이미 존재하면 추가하지 않음(멱등). 다른 이벤트는 손대지 않음.
JQ_MERGE='
  . as $orig
  | ($orig.hooks // {}) as $base
  | reduce ($new.hooks | keys[]) as $ev (
      $base;
      (.[$ev] // []) as $existing
      | ([ $existing[] | .hooks[]?.command ]) as $existingcmds
      | ($new.hooks[$ev]
          | map(select( (.hooks[0].command) as $c | ($existingcmds | index($c)) | not ))
        ) as $toadd
      | .[$ev] = ($existing + $toadd)
    )
  | $orig + { hooks: . }
'

# node 폴백용 병합 스크립트(위 jq 와 동일 의미).
NODE_MERGE='
  var fs=require("fs");
  var orig=JSON.parse(fs.readFileSync(process.env.SETTINGS_PATH,"utf8"));
  var add=JSON.parse(process.env.SETTINGS_JSON);
  var base=orig.hooks||{};
  var evs=Object.keys(add.hooks||{});
  for(var i=0;i<evs.length;i++){
    var ev=evs[i];
    var existing=base[ev]||[];
    var cmds={};
    for(var a=0;a<existing.length;a++){
      var hs=(existing[a]&&existing[a].hooks)||[];
      for(var b=0;b<hs.length;b++){ if(hs[b]&&hs[b].command) cmds[hs[b].command]=1; }
    }
    var incoming=add.hooks[ev]||[];
    for(var c=0;c<incoming.length;c++){
      var cmd=incoming[c]&&incoming[c].hooks&&incoming[c].hooks[0]&&incoming[c].hooks[0].command;
      if(!(cmd in cmds)) existing.push(incoming[c]);
    }
    base[ev]=existing;
  }
  orig.hooks=base;
  process.stdout.write(JSON.stringify(orig,null,2)+"\n");
'

merge_settings() {
  # stdout 으로 병합 결과 JSON 을 출력, 성공 시 exit 0. jq→node 순.
  if [ "$HAVE_JQ" -eq 1 ]; then
    jq --argjson new "$SETTINGS_JSON" "$JQ_MERGE" "$SETTINGS_PATH" 2>/dev/null
    return $?
  fi
  if [ "$HAVE_NODE" -eq 1 ]; then
    SETTINGS_PATH="$SETTINGS_PATH" SETTINGS_JSON="$SETTINGS_JSON" node -e "$NODE_MERGE" 2>/dev/null
    return $?
  fi
  return 2
}

# 신규 settings 를 병합 경로와 동일한 직렬화로 정규화(멱등성: 최초 write 포맷 ==
# 이후 재실행 병합 결과 포맷). jq·node 없으면 리터럴 그대로 반환.
normalize_settings() {
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$SETTINGS_JSON" | jq '.' 2>/dev/null && return 0
  elif [ "$HAVE_NODE" -eq 1 ]; then
    SETTINGS_JSON="$SETTINGS_JSON" node -e 'process.stdout.write(JSON.stringify(JSON.parse(process.env.SETTINGS_JSON),null,2)+"\n")' 2>/dev/null && return 0
  fi
  printf '%s\n' "$SETTINGS_JSON"
}

SETTINGS_PATH="$CLAUDE_DIR/settings.json"
mkdir -p "$CLAUDE_DIR"
if [ -e "$SETTINGS_PATH" ]; then
  merged=""
  if merged="$(merge_settings)" && [ -n "$merged" ]; then
    if [ "$merged" = "$(cat "$SETTINGS_PATH")" ]; then
      log "unchanged: $SETTINGS_PATH (이미 우리 훅 배선됨)"
      UNCHANGED+=("$SETTINGS_PATH")
    else
      bak="$(backup_path "$SETTINGS_PATH")"
      cp -p "$SETTINGS_PATH" "$bak"
      log "backup: $SETTINGS_PATH -> $bak"
      BACKED_UP+=("$SETTINGS_PATH -> $bak")
      printf '%s\n' "$merged" > "$SETTINGS_PATH"
      log "merge : $SETTINGS_PATH (이벤트 단위 딥머지, 기존 훅 보존)"
      INSTALLED+=("$SETTINGS_PATH (merged)")
    fi
  else
    # jq·node 둘 다 없음(또는 병합 실패) + 기존 settings 존재 → 조용한 skip 금지.
    echo ""
    echo "  !! settings.json 자동 병합 불가 (jq·node 없음). 아래 hooks 항목을"
    echo "     $SETTINGS_PATH 의 \"hooks\" 에 수동으로 병합하세요:"
    echo "  ---8<--- 수동 병합 대상 (UserPromptSubmit / PreCompact append) ---8<---"
    printf '%s\n' "$SETTINGS_JSON" | sed 's/^/     /'
    echo "  --->8------------------------------------------------------------->8---"
    log "SKIPPED: $SETTINGS_PATH (수동 병합 필요 — 위 스니펫 참조)"
    SKIPPED+=("$SETTINGS_PATH (수동 병합 필요 — 자동 병합 불가)")
  fi
else
  printf '%s\n' "$(normalize_settings)" > "$SETTINGS_PATH"
  log "write : $SETTINGS_PATH"
  INSTALLED+=("$SETTINGS_PATH")
fi

# ===========================================================================
# 5. .claude/MODELS.md  (모델 ID SSOT)
# ===========================================================================
install_managed "$CLAUDE_DIR/MODELS.md" <<'MODELS_EOF'
# MODELS.md — 모델/CLI 단일 진실 소스(SSOT)

> 이 파일이 이 프로젝트의 모델 ID·CLI 버전 SSOT 입니다.
> 다른 문서·설정은 값을 중복 기재하지 말고 **이 파일을 참조**하세요.

| 역할 | 모델 | API ID |
|------|------|--------|
| 플래그십 (복잡 추론, 1M 변형 존재) | Opus 4.8 | `claude-opus-4-8` |
| 최상위 추론 / 장기 에이전트 | Fable 5 | `claude-fable-5` |
| 코딩 / 에이전트 메인 (1M) | Sonnet 5 | `claude-sonnet-5` |
| 경량 / 빠른 반복 (200K) | Haiku 4.5 | `claude-haiku-4-5-20251001` |

- Claude Code CLI: `v2.1.210`
MODELS_EOF

# ===========================================================================
# 6. CLAUDE.md  (템플릿 최소본 — 이미 있으면 절대 덮지 않음)
# ===========================================================================
install_skip_if_exists "$TARGET/CLAUDE.md" <<'CLAUDEMD_EOF'
# CLAUDE.md

## Project Overview

**[프로젝트명]** - [한 줄 설명]

## Quick Start

```bash
# 설치 / 개발서버 / 테스트 명령을 여기에 (Claude가 추측할 수 없는 것만)
```

## Architectural Decisions

- [프로젝트 특유의 패턴 — Claude가 코드만 봐서는 모르는 것]

## Gotchas

- [Claude가 반복적으로 틀리는 것]

## Commands

- `/dev-docs <task>` — 승인된 계획으로 dev/active/<task>/ 3파일 생성
- `/update-dev-docs` — 압축/세션 종료 전 dev docs 갱신
- `/resume` — dev docs 에서 작업 재개
- `/save-and-compact` — 저장 후 /compact

## Skill Routing

- `UserPromptSubmit` 훅(`skill-activator.sh`)이 `.claude/skill-rules.json` 키워드로
  관련 스킬을 **advisory 리마인더**로 추천합니다 (작업을 차단하지 않음).

## Reference

- 모델/CLI SSOT: `.claude/MODELS.md`
CLAUDEMD_EOF

# ===========================================================================
# 7. dev/active/.gitkeep  (없을 때만 touch, 백업/덮어쓰기 없음)
# ===========================================================================
GITKEEP_PATH="$TARGET/dev/active/.gitkeep"
mkdir -p "$(dirname "$GITKEEP_PATH")"
if [ -e "$GITKEEP_PATH" ]; then
  log "unchanged: $GITKEEP_PATH"
  UNCHANGED+=("$GITKEEP_PATH")
else
  touch "$GITKEEP_PATH"
  log "write : $GITKEEP_PATH"
  INSTALLED+=("$GITKEEP_PATH")
fi

# ===========================================================================
# 요약 출력
# ===========================================================================
echo ""
echo "==================== 설치 요약 ===================="

echo "설치/갱신됨 (${#INSTALLED[@]}):"
if ((${#INSTALLED[@]})); then
  for x in "${INSTALLED[@]}"; do printf '  + %s\n' "$x"; done
else
  echo "  (없음)"
fi

echo "변경 없음 (${#UNCHANGED[@]}):"
if ((${#UNCHANGED[@]})); then
  for x in "${UNCHANGED[@]}"; do printf '  = %s\n' "$x"; done
else
  echo "  (없음)"
fi

echo "백업됨 (${#BACKED_UP[@]}):"
if ((${#BACKED_UP[@]})); then
  for x in "${BACKED_UP[@]}"; do printf '  ~ %s\n' "$x"; done
else
  echo "  (없음)"
fi

echo "스킵됨 (${#SKIPPED[@]}):"
if ((${#SKIPPED[@]})); then
  for x in "${SKIPPED[@]}"; do printf '  - %s\n' "$x"; done
else
  echo "  (없음)"
fi

echo "--------------------------------------------------"
echo "다음 단계:"
echo "  1) 배선된 훅은 전부 advisory(리마인더)입니다 — 작업/도구를 차단하지 않습니다."
echo "     실제 도구 차단이 필요하면 deny 반환 PreToolUse 훅을 별도 구성하세요."
echo "  2) jq(권장) 또는 node 가 있으면 skill-activator/settings 병합이 정확히 동작합니다."
echo "  3) 모델/CLI 값은 .claude/MODELS.md(SSOT)를 참조하세요."
echo "  4) settings.json 이 이미 있었다면 백업본과 병합 결과를 확인하세요."
echo "=================================================="
