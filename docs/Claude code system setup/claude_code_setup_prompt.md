---
tags:
  - claude
  - setup
---

# Claude Code 통합 시스템 구축 프롬프트
## Parallel Agents + Skills 활성화 + Dev Docs 통합

---

## 📋 사용법

아래 프롬프트를 Claude Code CLI에 그대로 붙여넣으세요.
참조 파일이 반드시 같은 디렉토리에 위치해야 합니다:

```
your-project/
└── Parallel_Agents_Safety_Protocol_v3_1_0.md  ← 이 파일 필요
```

---

> ✅ **권장(원샷) 설치**: 최소 생존 셋업(`.claude/` 커맨드·훅·`settings.json`·`skill-rules.json`)은 같은 폴더의 **`./install.sh <target-project-dir>`** 한 번으로 설치됩니다(멱등, 기존 `settings.json` 은 이벤트 단위로 딥머지). 아래의 STEP 1–8 수동 절차는 **동등한 대안**으로, 각 파일을 직접 이해·수정하고 싶을 때 사용하세요.

## 🚀 Claude Code에 입력할 프롬프트

```
첨부 파일 `Parallel_Agents_Safety_Protocol_v3_1_0.md`를 완전히 읽고,
아래 명세에 따라 Claude Code 통합 시스템을 구축해줘.

이 시스템은 3대 핵심 시스템을 한번에 구축합니다:
  A. Parallel Agents (멀티에이전트 안전 프로토콜)
  B. Skills 자동 활성화 (Hook 기반 스킬 강제 적용)
  C. Dev Docs (대규모 작업 컨텍스트 관리)

---

## 📌 사전 지시사항

1. 작업 시작 전 파일을 반드시 먼저 끝까지 읽어라 (view tool 사용)
2. pseudocode / TypeScript 예시 코드는 "구현 참조용"이므로 실제 파일로 생성하지 마라
3. 모든 파일 생성 전 디렉토리가 없으면 먼저 생성하라
4. 완료 후 반드시 생성된 파일 목록과 구조를 보고하라
5. 모델 string은 문서의 표기와 무관하게 실제 API string을 사용하라 (※ 2026-06-16 갱신):
   - opus → claude-opus-4-8              # 최신 플래그십 (1M 컨텍스트 변형 존재)
   - fable → claude-fable-5             # 신규 세대
   - sonnet → claude-sonnet-5          # 코딩/에이전트 메인 (1M)
   - haiku → claude-haiku-4-5-20251001   # 경량/빠른 반복 (200K)
6. Hook command는 bash 스크립트(.sh)로 작성하라 (node/ts 아님)
7. settings.json은 하나의 파일에 모든 시스템의 hooks를 통합하라

---

## 🏗️ 생성할 파일 목록 (순서대로)

═══════════════════════════════════════
## PART A: Parallel Agents 시스템
═══════════════════════════════════════

### STEP 1: 설정 파일 (통합)

**파일**: `.claude/settings.json`
**근거**: 프로토콜 Appendix A6 + Skills 활성화 + Dev Docs hooks
**내용 요구사항**:
- permissions.allow / deny 섹션 (Appendix A6 기준)
- maxTokens: 16000
- `model` 키는 넣지 않는다 — 모델 선택은 사용자/CLI(`/model`)의 몫이다

hooks 섹션은 아래 3개 시스템을 모두 통합 (2026-05 기준 유효 이벤트):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/skill-activator.sh\""
        }]
      }
    ],
    "PreToolUse": [],
    "PostToolUse": [],
    "PostToolUseFailure": [],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/pre-compact-reminder.sh\""
        }]
      }
    ],
    "Stop": [],
    "Notification": [],
    "SessionStart": [],
    "SessionEnd": [],
    "SubagentStart": [],
    "SubagentStop": [],
    "PermissionRequest": [],
    "Setup": []
  }
}
```

**참고**: 위 예시에서 실제로 배선하는 이벤트는 `UserPromptSubmit`(advisory skill-activator)와 `PreCompact`(pre-compact 리마인더) 둘뿐이다. 나머지 이벤트 키는 빈 배열 placeholder다. 이벤트 이름은 현재 설치 환경의 `/help` 또는 시스템 프롬프트 hooks 스키마로 확인하라 — 유효하지 않은 이름을 쓰면 hook이 등록되지 않는다.

---

### STEP 2: Agent 파일들

모든 agent 파일의 공통 규칙:
- 저장 위치: `.claude/agents/`
- 파일 형식: Markdown with YAML frontmatter
- frontmatter 필수 필드: name, description, model, effort, maxTurns, disallowedTools
- System Prompt는 한국어/영어 병행 작성

---

**파일**: `.claude/agents/primary-coordinator.md`
**근거**: 문서 Section 3.1 + Section 2.5 (Agent Hierarchy) + Appendix A4
**frontmatter**:
- model: claude-opus-4-8
- effort: high
- maxTurns: 50
- disallowedTools: ["Bash(rm -rf *)", "Bash(sudo *)"]
**System Prompt 포함 내용**:
- 태스크 분해 및 Secondary Agent 배분 프로세스
- Dynamic Reallocation 트리거 조건 (30% 이탈 시)
- 파일 Lock 획득/해제 절차 (Section 4.1 기반)
- Secondary Agent 결과물 검증 후 present_files 사용 원칙
- SendMessage 패턴으로 실행 중 에이전트와 통신하는 방법
- 에러 발생 시 사용자에게 보고하는 형식 (Section 9.2 예시 참조)
- 윤리적 우려 발생 시 즉시 중단 후 사용자에게 알리는 절차

---

**파일**: `.claude/agents/code-explorer.md`
**근거**: 문서 내장 에이전트 타입 `Explore`/`general-purpose` (v3.1.0의 `feature-dev:code-explorer` 대체) + Section 3.2
**frontmatter**:
- model: claude-sonnet-5
- effort: medium
- maxTurns: 30
- disallowedTools: ["Bash(rm *)", "Bash(sudo *)", "Write"]
**System Prompt 포함 내용**:
- 코드베이스 분석 및 탐색 전문 에이전트임을 명시
- Read-only 원칙: 파일 수정 불가, 분석/보고만 수행
- 능력 초과 태스크 수신 시 Primary에 즉시 에스컬레이션
- 분석 결과 보고 형식 (Section 5.1 status reporting format 참조)

---

**파일**: `.claude/agents/code-reviewer.md`
**근거**: 문서 내장 에이전트 타입 `code-reviewer` (v3.1.0의 `feature-dev:code-reviewer` 대체) + Section 3.2
**frontmatter**:
- model: claude-sonnet-5
- effort: high
- maxTurns: 30
- disallowedTools: ["Bash(rm *)", "Bash(sudo *)"]
**System Prompt 포함 내용**:
- 코드 리뷰 전문: 보안, 성능, 가독성, 아키텍처 관점
- Cross-Agent Verification 역할 수행 (Section 8.2 기반)
- Critical 이슈 발견 시 Ethical Veto 발동 절차
- 리뷰 결과 보고 형식 (LGTM / Minor / Major / Critical 분류)

---

**파일**: `.claude/agents/verify-agent.md`
**근거**: 문서 내장 에이전트 타입 `verify-agent` + Section 8 (Validation and QA)
**frontmatter**:
- model: claude-sonnet-5
- effort: high
- maxTurns: 20
- disallowedTools: ["Bash(rm *)", "Bash(sudo *)"]
**System Prompt 포함 내용**:
- Fresh context에서 독립적으로 빌드/테스트 검증 수행
- Pre/Mid/Post Execution Validation 체크리스트 (Section 8.1) 수행
- 검증 실패 시 Primary에 즉시 에스컬레이션
- 파일 무결성 검증 (checksum 방식) 수행
- 검증 결과 PASS / WARN / FAIL 형식으로 보고

---

**파일**: `.claude/agents/code-architect.md`
**근거**: 문서 내장 에이전트 타입 `architect` (v3.1.0의 `feature-dev:code-architect` 대체)
**frontmatter**:
- model: claude-opus-4-8
- effort: high
- maxTurns: 40
- disallowedTools: ["Bash(rm -rf *)", "Bash(sudo *)"]
**System Prompt 포함 내용**:
- 시스템 아키텍처 설계 전문 에이전트
- 구현 전 설계 검토, 의존성 분석, 리스크 평가
- Primary Coordinator와 협력하여 태스크 분해 전략 수립
- 아키텍처 결정 사항 문서화 및 Primary 승인 요청

---

### STEP 3: CLAUDE.md (프로젝트 루트)

**파일**: `CLAUDE.md`
**요구사항**: 120줄 이내로 핵심만 요약. 전체 프로토콜 내용을 복붙하지 말 것.
**포함할 섹션**:

1. **시스템 개요** (3줄): 이 프로젝트의 멀티에이전트 프로토콜 버전과 목적
2. **Agent 역할 요약표** (간단한 마크다운 테이블):
   - primary-coordinator / code-explorer / code-reviewer / verify-agent / code-architect
   - 각각의 한 줄 역할 설명
3. **핵심 안전 원칙** (5개 이내 bullet):
   - Data Integrity 우선
   - Secondary Agent는 Primary 승인 없이 공유 파일 수정 불가
   - 윤리적 우려 발생 시 즉시 중단
   - 능력 초과 태스크는 즉시 에스컬레이션
   - 파일 생성/편집 전 반드시 해당 SKILL.md 먼저 읽기
4. **Agent 실행 패턴 치트시트**:
   - run_in_background 패턴
   - worktree isolation 패턴
   - SendMessage 패턴
   - Workflow 도구로 멀티에이전트 오케스트레이션 가능 (agent()/parallel()/pipeline() 등 전역 함수)
5. **Dev Docs 워크플로우**:
   - /dev-docs → 구현 → /update-dev-docs → /compact 사이클
   - dev/active/[task-name]/ 3-파일 구조 설명
6. **Skills 활성화**:
   - UserPromptSubmit hook으로 자동 스킬 매칭
   - skill-rules.json에서 트리거 규칙 관리
7. **전체 프로토콜 참조**: `docs/Parallel_Agents_Safety_Protocol_v3_1_0.md`

---

### STEP 4: 문서 보관

**작업**: 원본 프로토콜 파일을 `docs/` 디렉토리로 복사

```
docs/Parallel_Agents_Safety_Protocol_v3_1_0.md
```

---

═══════════════════════════════════════
## PART B: Skills 자동 활성화 시스템
═══════════════════════════════════════

### STEP 5: Skills 트리거 규칙

**파일**: `.claude/hooks/skill-rules.json`
**목적**: 모든 스킬의 트리거 키워드와 의도 패턴 정의
**내용**:
```json
{
  "rules": [
    {
      "skillName": "code-reviewer",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["review", "PR", "pull request", "코드 리뷰", "검토"],
      "intentPatterns": ["(review|check|audit).*?(code|PR|changes)"]
    },
    {
      "skillName": "frontend-dev-guidelines",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["react", "component", "hooks", "state", "frontend"],
      "intentPatterns": ["(create|build|make).*?(component|page|screen)"]
    },
    {
      "skillName": "backend-dev-guidelines",
      "priority": "high",
      "enforcement": "suggest",
      "keywords": ["backend", "controller", "service", "api endpoint", "endpoint"],
      "intentPatterns": ["(create|add).*?(route|endpoint|controller)"]
    },
    {
      "skillName": "database-verification",
      "priority": "critical",
      "enforcement": "block",
      "keywords": ["database", "migration", "schema", "prisma"],
      "intentPatterns": [".*?(alter|modify|change|drop).*?table"]
    }
  ]
}
```

**주의**: 위는 예시 규칙이다. 프로젝트에 실제 `.claude/skills/` 디렉토리가 있다면,
그 스킬들을 기반으로 규칙을 생성하라. 없다면 위 예시를 기본값으로 사용하라.

> ⚠️ **advisory 정정**: `enforcement` 필드는 이 셋업의 `skill-activator.sh`(advisory 훅)에서 **작업을 차단하지 않는다** — 표시 문구 용도이며, 미사용에 가깝다(reserved/미구현). 정확한 계약: `UserPromptSubmit` **이벤트 자체**는 exit 2 또는 `{"decision":"block","reason":...}` 로 프롬프트를 거부할 수 있고, 특정 **도구** 거부는 `PreToolUse` 훅의 `hookSpecificOutput.permissionDecision:"deny"` 가 담당한다. **본 셋업의 skill-activator.sh 는 exit 0 + stdout(컨텍스트 주입)뿐이라 advisory 이며, 어느 차단 경로도 배선하지 않는다.**

---

### STEP 6: Skills 활성화 Hook 스크립트

**파일**: `.claude/hooks/skill-activator.sh`
**목적**: UserPromptSubmit에서 실행. 프롬프트를 분석하여 관련 스킬 추천
**동작**:
1. skill-rules.json을 읽는다
2. 입력된 프롬프트($1)에서 키워드 매칭
3. 매칭된 스킬을 priority 순으로 정렬
4. 결과를 stdout으로 출력 (Claude가 system-reminder로 수신)

**스크립트 구조**:
```bash
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
```

**주의**: 스크립트에 실행 권한(chmod +x)을 부여하라. 위 스크립트는 jq가 없으면 node(JSON.parse)로, node 도 없으면 awk best-effort 폴백으로 키워드를 매칭한다. 이 스크립트의 정본(byte-identical)은 `install.sh` 의 skill-activator.sh 히어독이며, 양쪽은 항상 동일하게 유지해야 한다.

---

### STEP 7: Pre-Compact 리마인더 스크립트

**파일**: `.claude/hooks/pre-compact-reminder.sh`
**목적**: PreCompact에서 실행. 컨텍스트 압축 *직전* 사용 가능한 스킬과 Dev Docs 상태를 출력하여, 압축 후 새 컨텍스트에 보존되도록 함.
**스크립트 구조**:
```bash
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
```

**주의**: 스크립트에 실행 권한(chmod +x)을 부여하라.

---

═══════════════════════════════════════
## PART C: Dev Docs 시스템
═══════════════════════════════════════

### STEP 8: Dev Docs 디렉토리 구조

**작업**: 아래 디렉토리를 생성하라 (파일 없이 디렉토리만)
```
dev/
├── active/        # 진행 중인 작업
└── completed/     # 완료된 작업 아카이브
```

빈 디렉토리가 git에서 추적되도록 각 디렉토리에 `.gitkeep` 파일을 생성하라.

---

### STEP 9: Dev Docs Custom Commands

**파일**: `.claude/commands/dev-docs.md`
**내용**:
```markdown
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
```

---

**파일**: `.claude/commands/update-dev-docs.md`
**내용**:
```markdown
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
```

---

**파일**: `.claude/commands/resume.md`
**내용**:
```markdown
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
```

---

**파일**: `.claude/commands/save-and-compact.md`
**내용**:
```markdown
---
description: Save context to dev docs and run /compact
---

Before compaction, save all progress:

1. Run the /update-dev-docs workflow (update context.md, tasks.md)
2. Save any important decisions or learnings to memory if applicable
3. Confirm save is complete
4. Then run /compact

This ensures no context is lost during compaction.
```

---

## ✅ 완료 조건

모든 파일 생성 후 아래 형식으로 보고하라:

```
## 통합 시스템 구축 완료 보고

### PART A: Parallel Agents
.claude/
├── settings.json              ✅  (통합 hooks 포함)
└── agents/
    ├── primary-coordinator.md     ✅
    ├── code-explorer.md           ✅
    ├── code-reviewer.md           ✅
    ├── verify-agent.md            ✅
    └── code-architect.md          ✅
CLAUDE.md                      ✅  (3대 시스템 요약)
docs/
└── Parallel_Agents_Safety_Protocol_v3_1_0.md  ✅

### PART B: Skills 자동 활성화
.claude/hooks/
├── skill-rules.json               ✅
├── skill-activator.sh             ✅  (chmod +x)
└── pre-compact-reminder.sh        ✅  (chmod +x)

### PART C: Dev Docs
dev/
├── active/.gitkeep                ✅
└── completed/.gitkeep             ✅
.claude/commands/
├── dev-docs.md                    ✅
├── update-dev-docs.md             ✅
├── resume.md                      ✅
└── save-and-compact.md            ✅

### 주의사항 / 조정 사항
(문서와 실제 Claude Code API 간 불일치 발견 시 여기에 기록)
(hooks command format 검증 결과 기록)

### 다음 권장 작업
1. Skills 디렉토리에 프로젝트별 스킬 추가: .claude/skills/[skill-name]/SKILL.md
2. skill-rules.json에 실제 스킬 트리거 규칙 추가
3. 테스트: "Create a React component" 프롬프트로 스킬 활성화 확인
4. 테스트: /dev-docs my-feature 로 Dev Docs 생성 확인
5. 멀티에이전트 테스트: 간단한 2-에이전트 태스크 실행
```

---

## ⚠️ 주의사항 (작업 중 확인할 것)

- `SendMessage`, `isolation: "worktree"`, `run_in_background` 등 v3.1.0 신규 API는
  현재 Claude Code 버전에서 지원 여부를 먼저 확인하고, 미지원 시 주석으로 표시할 것
- settings.json의 hooks command는 반드시 실행 가능한 경로를 사용할 것
- hook 스크립트(.sh)에 반드시 chmod +x 실행 권한 부여
- agent frontmatter의 model string은 실제 API string 기준으로 작성
- Dev Docs 명령어의 $ARGUMENTS는 Claude Code가 자동으로 치환하는 변수임
- jq가 설치되지 않은 환경에서도 skill-activator.sh가 에러 없이 동작하도록 방어 처리
```

---

## 📁 예상 최종 디렉토리 구조

```
your-project/
├── CLAUDE.md
├── .claude/
│   ├── settings.json
│   ├── agents/
│   │   ├── primary-coordinator.md
│   │   ├── code-explorer.md
│   │   ├── code-reviewer.md
│   │   ├── verify-agent.md
│   │   └── code-architect.md
│   ├── hooks/
│   │   ├── skill-rules.json
│   │   ├── skill-activator.sh
│   │   └── pre-compact-reminder.sh
│   └── commands/
│       ├── dev-docs.md
│       ├── update-dev-docs.md
│       ├── resume.md
│       └── save-and-compact.md
├── dev/
│   ├── active/.gitkeep
│   └── completed/.gitkeep
└── docs/
    └── Parallel_Agents_Safety_Protocol_v3_1_0.md
```

---

## 🔄 시스템 간 연계 흐름

```
[사용자 프롬프트 입력]
       │
       ▼
[UserPromptSubmit Hook]
  skill-activator.sh → 관련 스킬 추천
       │
       ▼
[Claude 작업 수행]
  - Agent 배분 (Primary Coordinator)
  - 스킬 참조하며 코드 작성
  - Dev Docs 참조하며 방향 유지
       │
       ▼
[PreCompact Hook]
  pre-compact-reminder.sh → 스킬/Dev Docs 상태 안내 + 저장 요청
       │
       ▼
[세션 재시작]
  /resume → Dev Docs에서 컨텍스트 복원
```

---

*Generated for: Parallel Agents Safety Protocol v3.1.0 + Skills Activation + Dev Docs*
*Claude Code v2.1.210 (2026-07 기준) 환경 | 통합 시스템 v1.1*
*Models: Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5*
