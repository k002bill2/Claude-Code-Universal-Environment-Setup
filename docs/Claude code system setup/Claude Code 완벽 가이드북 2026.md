---
tags:
  - claude
  - setup
---

# Claude Code 완벽 가이드북 2026
#claude-code #ai-coding #development #guide

> 작성일: 2026-05-16 (재최신화, 기존: 2026-03-18)
> 환경: macOS (VS Code, Cursor 등 호환)
> Claude Code: v2.1.210 | Models: Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5
> Claude Code 경험: 초보자 ~ 중급자용

## 📌 개요

Claude Code는 Anthropic이 개발한 터미널 기반 AI 코딩 도구로, 2026년 현재 가장 강력한 AI 개발 어시스턴트입니다. 이 가이드는 **macOS 환경**에서 Claude Code를 시작하는 개발자를 위한 완벽한 설정 및 활용 가이드입니다.

## 🎯 2026년 핵심 기능

### 1. Agent Skills (에이전트 스킬) 🌟
- **정의**: 재사용 가능한 모듈형 기능 패키지
- **구성**: SKILL.md 파일로 정의되는 도메인별 전문 지식
- **작동**: Progressive Disclosure - Claude가 필요시 자동 로드
- **캐릭터 버짓**: 컨텍스트 윈도우의 약 2%까지 스킬 콘텐츠 스케일링
- **번들 리소스**: scripts/, references/, assets/ 하위 디렉토리로 보조 파일 구조화
- **활성화 개선**: v2.1.x에서 스킬 인식 및 자동 로드 성능 대폭 향상
- **장점**: 컨텍스트 효율성, 재사용성, 팀 공유 가능

### 2. Sub-agents (서브 에이전트) 🤖
- **정의**: 특정 작업 전문 AI 어시스턴트
- **특징**: 독립된 컨텍스트 윈도우 보유
- **작동**: 자동 태스크 위임 시스템
- **모델 선택**: sonnet, opus, haiku, inherit
- **신규 옵션**:
  - `effort`: 에이전트 추론 강도 (low/medium/high)
  - `maxTurns`: 최대 턴 수 제한
  - `disallowedTools`: 사용 금지 도구 목록
  - `hooks`: 에이전트별 훅 설정
  - `memory`: 메모리 스코프 (user/project/local)
- **SendMessage**: 실행 중인 에이전트에 메시지 전송 (resume 대체)
- **Worktree 격리**: `isolation: "worktree"`로 독립된 Git worktree에서 실행

### 3. 플러그인 시스템 (신규) 🔌
- **정의**: Claude Code 기능을 확장하는 모듈 패키지
- **구성**: plugin.json 매니페스트 + skills/agents/commands/hooks 번들
- **마켓플레이스**: 커뮤니티 플러그인 검색 및 설치
- **데이터**: `${CLAUDE_PLUGIN_DATA}` 환경변수로 플러그인 데이터 디렉토리 접근
- **자동 발견**: .claude/plugins/ 디렉토리의 플러그인 자동 로드

### 4. 영구 메모리 시스템 (신규) 🧠
- **정의**: 세션 간 영속 정보를 저장하는 파일 기반 메모리
- **스코프**: user (사용자), project (프로젝트), local (로컬)
- **타입**: user, feedback, project, reference 4가지
- **관리**: `/memory` 명령어로 조회 및 관리
- **자동 메모리**: `autoMemoryDirectory` 설정으로 자동 저장 디렉토리 지정
- **구조**: MEMORY.md 인덱스 + 개별 메모리 파일 (frontmatter 포함)

### 5. Background Tasks & Hooks ⚙️
- **백그라운드**: Ctrl+B로 프로세스 실행
- **Hooks 종류** (v2.1.210 전체 목록):
  - PreToolUse: 도구 사용 전
  - PostToolUse: 도구 사용 후
  - **PostToolUseFailure**: 도구 실행 실패 시
  - UserPromptSubmit: 사용자 프롬프트 전처리
  - Notification: 알림 발생 시
  - SessionStart / SessionEnd: 세션 생애주기
  - Stop: 세션 정상 종료 시
  - **SubagentStart**: 서브에이전트 시작 시 (신규)
  - SubagentStop: 서브에이전트 종료 시
  - PreCompact: 컨텍스트 압축 직전
  - **PermissionRequest**: 권한 요청 시 (신규)
  - **Setup**: 초기 셋업 시 (신규)
- **주의**: 이벤트 이름은 위 목록 기준. 유효하지 않은 이름을 쓰면 hook이 등록되지 않으니, 현재 설치 환경의 `/help` 또는 시스템 프롬프트 hooks 스키마로 확인하세요.
- **활용**: CI/CD 통합, 자동화, 품질 게이트

### 6. Personas & Frameworks 🎭
- **주요 프레임워크**:
  - SuperClaude: 메타 프로그래밍 설정 프레임워크
  - BMAD: 아키텍처 중심 개발 방법론
  - Claude Flow: 엔터프라이즈급 오케스트레이션
- **활용**: 특화된 개발 방법론 적용

## 🔥 실전 핵심 인사이트

> "Claude는 극도로 자신감 넘치는 주니어 개발자 with 심각한 건망증" - Reddit u/JokeGold5455

### 가장 중요한 4가지
1. **Planning Mode는 선택이 아닌 필수** - 계획 없이 시작하면 망함
2. **Skills + 플러그인 시스템** - Skills 만들기만 하면 안 씀 → Hook 또는 플러그인으로 강화
3. **Dev Docs 3-파일 시스템** - Claude가 길 잃는 것 방지
4. **메모리 시스템 활용** - 세션 간 맥락 유지의 핵심

## 📋 필수 문서 체크리스트

### Level 1: 핵심 설정 문서
```
your-project/
├── CLAUDE.md                    # ⭐ 프로젝트 가이드라인 (가장 중요)
├── .mcp.json                    # MCP 서버 연결 설정
├── .claude/
│   └── settings.json            # 권한, 훅, 모델 설정
└── PRD.md                       # 프로젝트 요구사항
```

### Level 2: Skills & Agents 문서
```
├── .claude/
│   ├── skills/                  # 🌟 Agent Skills
│   │   ├── code-reviewer/
│   │   │   ├── SKILL.md
│   │   │   └── resources/       # 번들 리소스
│   │   ├── test-runner/
│   │   │   └── SKILL.md
│   │   └── docs-generator/
│   │       └── SKILL.md
│   ├── agents/                  # 🤖 Sub-agents
│   │   ├── frontend-specialist.md
│   │   ├── backend-architect.md
│   │   └── test-engineer.md
│   └── commands/                # 커스텀 명령어
│       ├── review.md
│       ├── deploy.md
│       └── test.md
```

### Level 3: 플러그인 & 메모리
```
├── .claude/
│   ├── plugins/                 # 🔌 플러그인 디렉토리
│   │   └── my-plugin/
│   │       ├── plugin.json      # 매니페스트
│   │       ├── skills/
│   │       ├── agents/
│   │       └── hooks/
│   └── memory/                  # 🧠 프로젝트 메모리
│       ├── MEMORY.md            # 인덱스
│       └── *.md                 # 개별 메모리 파일
```

### Level 4: Dev Docs (대규모 작업 필수)
```
├── dev/
│   └── active/                  # 진행 중인 작업
│       └── [task-name]/
│           ├── [task-name]-plan.md     # 승인된 계획
│           ├── [task-name]-context.md  # 핵심 결정사항
│           └── [task-name]-tasks.md    # 체크리스트
```

## 🚀 단계별 설정 가이드

### Phase 1: 기본 환경 구성 (macOS)

#### 1.1 필수 도구 설치
```bash
# Homebrew 설치 (macOS 패키지 매니저)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Node.js 설치 (필수 - v20 이상)
brew install node
# 또는 https://nodejs.org 에서 LTS 버전 다운로드

# Git 설치 (macOS는 기본 포함, 최신 버전 원할 경우)
brew install git

# IDE 설치 (선택)
# VS Code: https://code.visualstudio.com/
# Cursor: https://cursor.sh/
```

#### 1.2 Claude Code CLI 설치
```bash
# npm을 통한 설치
npm install -g @anthropic-ai/claude-code

# 버전 확인 (2026-07 기준 최신: v2.1.210)
claude --version

# 실행 및 로그인
claude
/login  # 브라우저 인증

# 또는 API 키 설정 (macOS)
export ANTHROPIC_API_KEY="your-api-key"
# 영구 설정: ~/.zshrc 또는 ~/.bash_profile에 추가
```

#### 1.3 VS Code Extension 설치
- VS Code 마켓플레이스에서 "Claude Code" 검색
- 설치 후 여러 pane에서 동시 실행 가능

### Phase 2: Agent Skills 생성 🌟

#### 2.1 Skill 생성 방법
```bash
# 방법 1: skill-creator 사용 (권장)
claude
"Use the skill-creator skill to help me create a new skill for [your task]"

# 방법 2: 수동 생성
mkdir -p .claude/skills/your-skill-name
```

#### 2.2 SKILL.md 템플릿 예시

##### Code Reviewer Skill
```markdown
---
name: code-reviewer
description: Comprehensive code review for quality, security, and maintainability. Use when reviewing pull requests, code changes, or when code quality checks are needed.
---

# Code Review Skill

## Purpose
Perform thorough code reviews focusing on:
- Code quality and readability
- Security vulnerabilities
- Performance optimization
- Test coverage
- Documentation completeness

## Instructions

### 1. Initial Analysis
- Read all changed files
- Identify the type of changes (feature, bugfix, refactor)
- Check for breaking changes

### 2. Quality Checks
\`\`\`python
def review_checklist():
    checks = {
        "error_handling": check_error_handling(),
        "input_validation": check_input_validation(),
        "sql_injection": check_sql_injection(),
        "memory_leaks": check_memory_management(),
        "test_coverage": check_test_coverage()
    }
    return checks
\`\`\`

### 3. Feedback Format
- 🟢 **Good**: Well-implemented features
- 🟡 **Suggestion**: Improvements
- 🔴 **Issue**: Must fix before merge

## Resources
- resources/style-guide.md
- resources/security-checklist.md
- resources/performance-tips.md
```

#### 2.3 번들 리소스 구조 (신규)
```
.claude/skills/code-reviewer/
├── SKILL.md                # 메인 스킬 파일
├── scripts/                # 실행 가능한 스크립트
│   └── lint-check.sh
├── references/             # 참고 문서
│   ├── style-guide.md
│   └── security-checklist.md
└── assets/                 # 정적 리소스
    └── templates/
```

### Phase 3: Sub-agents 설정 🤖

#### 3.1 Sub-agent 생성
```bash
# 인터랙티브 생성
/agents

# 옵션 선택:
# 1. Create new agent
# 2. Choose project-specific (.claude/agents/)
# 3. Define purpose and tools
# 4. Select color for visual identification
```

#### 3.2 Frontend Specialist Agent 예시 (v2.1.210 형식)
```markdown
---
name: frontend-specialist
description: React/Next.js component development, optimization, and testing
tools: Edit, Write, Read, Grep, Glob, Bash
model: sonnet-5
# 참고: effort/maxTurns/disallowedTools는 환경별 지원 차이가 있어 권장 X.
# 대신 tools 화이트리스트로 제한하는 것이 안전합니다.
---

# Frontend Development Specialist

You are a senior frontend engineer specializing in React and Next.js applications.

## Core Responsibilities
1. Component architecture and development
2. Performance optimization
3. Accessibility compliance
4. Responsive design implementation
5. State management

## Development Standards

### Component Structure
\`\`\`tsx
interface ComponentProps {
  // Define all props with proper types
}

const Component: React.FC<ComponentProps> = ({ ...props }) => {
  // Hook usage at the top
  // Business logic
  // Return JSX
}
\`\`\`

### Performance Guidelines
- Use React.memo for expensive components
- Implement lazy loading for routes
- Optimize bundle size with code splitting
- Use Next.js Image component for images

## Testing Requirements
- Unit tests for all utilities
- Component testing with React Testing Library
- E2E tests for critical user flows
- Minimum 80% code coverage
```

#### 3.3 내장 에이전트 타입 (v2.1.210, 플랫 빌트인 + 플러그인 스코프 공존)
| 타입 | 용도 |
|------|------|
| `general-purpose` | 범용 작업 (기본) |
| `Explore` | 코드베이스 탐색 (quick/medium/very thorough) |
| `Plan` | 구현 계획 설계 |
| `planner` | 복잡한 기능/리팩토링 계획 |
| `architect` | 시스템 아키텍처 설계 |
| `code-reviewer` | 코드 리뷰 (보안 + 품질) |
| `security-reviewer` | 보안 취약점 전문 |
| `test-automation-specialist` | 빌드/테스트 검증 (fresh context) |
| `build-error-resolver` | TypeScript/빌드 에러 수정 |
| `code-simplifier` | 가독성/일관성 리팩토링 |
| `tdd-guide` | TDD 워크플로우 가이드 |
| `cli-orchestrator` | CLI 파이프라인 오케스트레이션 |
| `claude` | 위에 맞지 않는 catch-all |

**v2.1.78 → v2.1.143 변경**: `feature-dev:` 네임스페이스 제거, `verify-agent` → `test-automation-specialist`.

> **네임스페이스 정정 (※ 2026-06-16 갱신)**: 빌트인 에이전트 타입은 위처럼 플랫(네임스페이스 없는) 이름으로 노출되지만, 이것이 "네임스페이스 완전 평탄화"를 의미하지는 않습니다. 정확히는 **플랫 빌트인 + 플러그인 스코프(`ecc:*`) 공존** 구조입니다. 플러그인이 제공하는 에이전트는 `ecc:` 같은 네임스페이스로 함께 노출됩니다(예: `ecc:architect`, `ecc:python-reviewer`). 즉 빌트인은 평탄하게, 플러그인 에이전트는 스코프를 붙여 구분합니다.

### Phase 4: Hooks & Automation ⚙️

#### 4.1 .claude/settings.json 설정
```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write(src/**)",
      "Write(tests/**)",
      "Bash(npm *)",
      "Bash(git *)"
    ],
    "deny": [
      "Read(.env*)",
      "Write(*.prod.*)",
      "Bash(rm -rf *)",
      "Bash(sudo *)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write(*.py)",
        "hooks": [{
          "type": "command",
          "command": "python -m black \"$file\" && python -m pylint \"$file\""
        }]
      },
      {
        "matcher": "Edit(*test*)",
        "hooks": [{
          "type": "command",
          "command": "npm test -- --coverage"
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "git status && echo 'Session completed'"
        }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo '⚠️ Tool execution failed' >> .claude/logs/failures.log"
        }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo '📦 Context will be compacted - check dev docs for continuity'"
        }]
      }
    ]
  },
  "maxTokens": 16000
}
```

> **모델 ID 주의**: `settings.json` 에 `model` 키를 박지 마세요. 설치기는 이 키를 절대 주입하지 않으며, 모델 선택은 Claude Code CLI(`/model`)와 사용자 설정의 몫입니다. 문서에 값을 고정하면 모델 세대가 바뀔 때마다 조용히 낡습니다.

#### 4.2 Background Tasks 활용
```bash
# 개발 서버 백그라운드 실행
Ctrl+B npm run dev

# 로그 모니터링
Ctrl+B tail -f logs/app.log

# 테스트 watch 모드
Ctrl+B npm test -- --watch
```

### Phase 5: MCP 서버 통합

#### 5.1 .mcp.json 설정
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "./src", "./tests", "./docs"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

> 허용 경로는 `ALLOWED_PATHS` 환경변수가 아니라 **positional 인자**로 전달합니다.
>
> 업스트림 `modelcontextprotocol/servers` 가 Puppeteer·PostgreSQL 레퍼런스 서버를
> [아카이브](https://github.com/modelcontextprotocol/servers-archived)했고 npm 에서도
> deprecated 입니다. 브라우저 자동화는 유지보수 중인 `@playwright/mcp` 를 쓰고,
> DB 접속은 공식 후속이 없으므로 사용 중인 벤더의 MCP 서버(Supabase·Neon 등)를
> 직접 추가하세요. 동일한 구성이 `project/mcp.json.example` 에 있습니다.

### Phase 6: 플러그인 설정 (신규) 🔌

#### 6.1 플러그인 구조
```
.claude/plugins/my-plugin/
├── plugin.json              # 매니페스트 (필수)
├── skills/                  # 스킬 번들
│   └── my-skill/SKILL.md
├── agents/                  # 에이전트 번들
│   └── my-agent.md
├── commands/                # 커스텀 명령어
│   └── my-command.md
└── hooks/                   # 훅 스크립트
    └── pre-build.sh
```

#### 6.2 plugin.json 예시
```json
{
  "name": "my-dev-toolkit",
  "version": "1.0.0",
  "description": "개발 생산성 향상 플러그인",
  "skills": ["skills/"],
  "agents": ["agents/"],
  "commands": ["commands/"],
  "hooks": {
    "PostToolUse": ["hooks/post-tool.sh"]
  }
}
```

### Phase 7: 메모리 시스템 설정 (신규) 🧠

#### 7.1 메모리 디렉토리 구조
```
~/.claude/projects/<project>/memory/
├── MEMORY.md                # 인덱스 파일
├── user_role.md             # 사용자 정보
├── feedback_testing.md      # 피드백 메모리
├── project_auth.md          # 프로젝트 메모리
└── reference_api.md         # 참조 메모리
```

#### 7.2 메모리 파일 형식
```markdown
---
name: user-role
description: 사용자의 역할과 기술 수준
type: user
---

풀스택 개발자, TypeScript/React 전문.
백엔드는 Supabase 활용 중.
```

#### 7.3 메모리 관련 명령어
```bash
/memory          # 현재 메모리 조회 및 관리
```

## ⚡ Workflow 도구 (신규)

대규모 멀티 에이전트 오케스트레이션을 **인라인 JS 스크립트**로 기술하는 도구입니다. 스크립트는 반드시 순수 리터럴인 `meta` export로 시작합니다.

```js
export const meta = {
  name: "release-pipeline",
  description: "여러 패키지를 병렬 리뷰 후 단계별로 처리",
  phases: ["review", "fix", "verify"],
};

// 본문에서는 전역 함수를 await로 직접 호출합니다.
phase("review");
const findings = await parallel([
  () => agent("packages/api 리뷰", { label: "api", agentType: "code-reviewer" }),
  () => agent("packages/web 리뷰", { label: "web", agentType: "code-reviewer" }),
]);

// 항목별 독립 파이프라인 (단계 간 배리어 없음)
await pipeline(
  args().packages,
  (pkg) => agent(`${pkg} 빌드`, { phase: "fix", isolation: "worktree" }),
  (pkg) => agent(`${pkg} 검증`, { phase: "verify", schema: VerifySchema }),
);
```

### 핵심 API 시그니처 (이 형태만 유효)
| 함수 | 설명 |
|------|------|
| `export const meta = { name, description, phases }` | 스크립트 첫머리. **순수 리터럴**이어야 함 |
| `agent(prompt, opts?)` | 서브에이전트 실행. `opts = { label, phase, schema, model, effort, isolation: 'worktree', agentType }`. `schema`를 주면 검증된 객체 반환 |
| `parallel(thunks)` | 동시 실행 + 배리어(모두 완료 후 반환). 실패 항목은 `null` |
| `pipeline(items, stage1, stage2, ...)` | 항목별 독립 파이프라인, 단계 간 배리어 없음 |
| `phase(title)` | 단계 구분 |
| `log(message)` | 로그 출력 |
| `args()` | 입력값 접근 |
| `budget(...)` | 토큰 예산 지정 |
| `workflow(name, args)` | 중첩 워크플로우 호출 (1단계) |

### 동시성 / 실행 제어
- 동시 실행은 자동으로 `min(16, CPU 코어 수 - 2)`로 캡됩니다.
- 전체 에이전트 상한은 **1000개**입니다.
- 백그라운드로 실행한 뒤 완료 시 알림을 보냅니다.
- `isolation: 'worktree'`로 각 에이전트를 독립된 Git worktree에서 실행할 수 있습니다(미변경 시 자동 정리).

> **⚠️ 날조 표현 주의 (실재하지 않음)**: `workflow.pipeline([{ task, agent, depends }])`, `.withIsolation().run()`, `workflow.background()`, 그리고 fluent builder 체인은 실제 API가 아닙니다. 위 전역 함수 형태(`pipeline(items, stage1, ...)`, `agent(prompt, { isolation: 'worktree' })`)만 사용하세요.

## 🧰 신규 빌트인 도구 카탈로그 (신규)

옛 가이드에 없던, 모던 Claude Code 환경에서 사용 가능한 도구/스킬 모음입니다.

### 검증 / 리뷰
- **advisor**: 전체 트랜스크립트를 보는 상위 리뷰어(파라미터 없음). 접근법을 확정하기 전, 또는 완료를 선언하기 전에 호출하는 검증 게이트.
- **/code-review ultra** (= ultrareview): 멀티 에이전트 클라우드 리뷰. 사용자가 트리거합니다.

### 반복 / 스케줄링
- **/loop** (스킬): 프롬프트/슬래시 커맨드를 반복 실행. 간격을 지정하거나 모델 자율 페이싱.
- **ScheduleWakeup**: `/loop`의 동적 페이싱 재개를 위한 스케줄 도구.
- **/schedule** (스킬): cron 기반 클라우드 에이전트(routine) 관리.
- **CronCreate / CronList / CronDelete**: cron 예약 에이전트 생성/조회/삭제.

### Worktree / 백그라운드 모니터링
- **EnterWorktree / ExitWorktree**: worktree 라이프사이클 진입/이탈 도구.
- **Monitor**: 백그라운드 프로세스 또는 조건 모니터링.

### 스킬 / 도구 로딩
- **Skill 도구**: 스킬을 명시적으로 호출.
- **ToolSearch**: 디퍼드(지연 로드) 도구의 스키마를 동적으로 로드. 토큰 절약용 lazy loading.

### 산출물 / 알림 / 동기화
- **SendUserFile**: 산출 파일을 사용자에게 전달.
- **PushNotification**: 푸시 알림 전송.
- **RemoteTrigger**: 원격 트리거.
- **DesignSync**: 디자인 동기화.

### 빌트인 스킬
- **deep-research**: 다중 소스 팬아웃 검색 + 출처 검증 + 인용 리포트 합성.
- **skill-creator**: 스킬 생성/수정/최적화.
- **frontend-design**: 의도적인 시각 디자인 가이드.
- **simplify**: 변경된 코드의 재사용/단순화/효율 정리.
- **document-skills**: 문서 작업 스킬 묶음 (xlsx / docx / pptx / pdf).

### MCP 생태계 (ToolSearch로 동적 로드)
claude-in-chrome, Figma, Canva, Atlassian, Notion, Slack, Gmail, Google(Calendar/Drive), Context7, Playwright 등 다수의 MCP 서버를 사용할 수 있으며, 필요 시 `ToolSearch`로 도구 스키마를 동적으로 로드합니다.

## 📦 프로젝트 타입별 Skills & Agents

### 모델 선택 가이드 (2026-06 기준)

| 모델             | 컨텍스트   | 용도              | 속도     | 비용     |
| -------------- | ------ | --------------- | ------ | ------ |
| **Haiku 4.5**  | 200K   | 간단한 작업, 빠른 반복   | 🚀🚀🚀 | 💰     |
| **Sonnet 5** | **1M** | 일반 개발, 코딩, 에이전트 | 🚀🚀   | 💰💰   |
| **Opus 4.8**   | **1M** | 복잡한 추론, 엔터프라이즈, 최신 플래그십 | 🚀 | 💰💰💰 |
| **Fable 5**    | **1M** | 가장 까다로운 추론·장기 에이전트 작업 (최대 출력 128K) | 🚀 | 💰💰💰💰 |

> **모델 ID**: `claude-haiku-4-5-20251001`, `claude-sonnet-5`, `claude-opus-4-8`, `claude-fable-5`
> **가격(per MTok, API 기준)**: Fable 5 input $10 / output $50, Opus 4.8 $5 / $25, Sonnet 5 $3 / $15 (2026-08-31까지 인트로 $2 / $10), Haiku 4.5 $1 / $5. Fable 5는 Opus-tier보다 비싸므로(2배) "가장 까다로운 작업"에만 권장.
> **1M 컨텍스트**: Max/Team/Enterprise 플랜에서 Opus 4.8, Sonnet 5 사용 시 최대 1M 토큰 컨텍스트 지원 (Opus 4.8은 1M 컨텍스트 변형 존재). Fable 5도 1M(기본=최대) 지원.
> **변경 이력**: 2026-03 Opus 4.6 → 2026-05 Opus 4.7 → 2026-06 Opus 4.8 (플래그십). Fable 5 신규 세대 추가. Sonnet/Haiku는 유지.

### Effort 레벨 가이드
| 레벨 | 용도 | 사용 예 |
|------|------|---------|
| `/effort low` | 간단한 질문, 빠른 수정 | 오타 수정, 변수명 변경 |
| `/effort medium` | 일반 개발 작업 (기본값) | 함수 작성, 버그 수정 |
| `/effort high` | 복잡한 추론, 아키텍처 설계 | 대규모 리팩토링, 설계 |

### 웹 개발 프로젝트
| Type | Name | Purpose |
|------|------|---------|
| **Skills** | | |
| | component-generator | React/Vue 컴포넌트 생성 |
| | api-integrator | API 연동 코드 생성 |
| | style-system | CSS/Tailwind 스타일링 |
| **Agents** | | |
| | ui-designer | 디자인 시스템 적용 |
| | performance-optimizer | 번들 최적화 |
| | accessibility-auditor | A11y 검사 |

### 백엔드 프로젝트
| Type | Name | Purpose |
|------|------|---------|
| **Skills** | | |
| | api-designer | OpenAPI 스펙 생성 |
| | database-migrator | 스키마 마이그레이션 |
| | auth-implementer | 인증/인가 구현 |
| **Agents** | | |
| | api-architect | API 설계 전문가 |
| | security-auditor | 보안 검사 |
| | performance-tuner | 성능 최적화 |

### 데이터 분석/ML 프로젝트
| Type | Name | Purpose |
|------|------|---------|
| **Skills** | | |
| | data-processor | 데이터 전처리 |
| | model-trainer | 모델 학습 |
| | visualizer | 시각화 생성 |
| **Agents** | | |
| | data-scientist | 분석 전략 수립 |
| | ml-engineer | 모델 최적화 |
| | experiment-tracker | 실험 관리 |

## 🎯 Best Practices 2026

### Daily Workflow
```bash
# 세션 시작
claude

# 이전 메모리 확인
/memory

# 작업 시작 (effort 레벨 설정)
/effort high

# Skills 확인
ls .claude/skills/

# Agents 상태 확인
/agents list

# 작업 시작
"Review my recent changes using the code-reviewer skill"
```

### 효율적인 사용 팁
1. **Context Management**: 긴 세션에서 `/compact`로 컨텍스트 압축
2. **Skill Chaining**: 여러 Skills를 순차적으로 활용
3. **Agent Delegation**: 복잡한 작업은 여러 agents로 분할
4. **Memory 활용**: 세션 간 중요 정보를 메모리로 보존
5. **Version Control**: Skills, Agents, Plugins를 Git으로 관리
6. **Team Sharing**: `.mcp.json`과 Skills를 팀과 공유
7. **Effort 조절**: 작업 복잡도에 맞게 `/effort` 조절
8. **Fast 모드**: 간단한 작업은 `/fast`로 빠르게 처리

### 주요 명령어 (v2.1.210)
| 명령어 | 설명 |
|--------|------|
| `/clear` | 컨텍스트 초기화 |
| `/compact` | 컨텍스트 압축 |
| `/agents` | Sub-agents 관리 |
| `/model` | 모델 변경 |
| `/effort` | effort 레벨 설정 (환경별 지원 차이) |
| `/fast` | 빠른 모드 토글 (Opus 4.8/4.7 지원 — 작은 모델로 다운그레이드가 아니라 Opus를 빠른 출력으로 실행) |
| `/memory` | 메모리 관리 |
| `/branch` | 세션 분기 (/fork 대체) |
| `/copy N` | N번째 응답 복사 |
| `/context` | 컨텍스트 최적화 제안 |
| `/loop` | 반복 작업 (간격 지정 또는 자율 페이싱, 신규) |
| `/schedule` | 원격 cron 에이전트 (routine) 관리 (신규) |
| `/statusline` | 상태 표시줄 설정 |
| `/hooks` | Hooks 설정 |
| `/permissions` | 권한 관리 |
| `/help` | 도움말 |
| `/bug` | 버그 리포트 |
| `Ctrl+B` | 백그라운드 실행 |
| `Ctrl+R` | Transcript 모드 |

**Plan Mode** (v2.1.x 기본 통합):
- 사용자가 plan 모드를 활성화하면 Claude는 읽기 전용 작업만 수행하며, 최종 계획을 `~/.claude/plans/*.md`에 작성한 뒤 `ExitPlanMode` 도구로 승인 요청합니다. `AskUserQuestion`으로 모호한 요구사항을 사전 명확화할 수 있습니다.

## 🚨 보안 주의사항

### 필수 보안 규칙
- ❌ `--dangerously-skip-permissions`는 Docker 컨테이너에서만 사용
- ❌ 민감 정보는 Skills에 하드코딩하지 않기
- ❌ 알 수 없는 출처의 Executable Skills 사용 금지
- ❌ 샌드박스 우회 경고 무시하지 않기
- ✅ 정기적인 권한 검토
- ✅ `.env` 파일은 `.gitignore`에 포함
- ✅ API 키는 환경 변수로 관리
- ✅ 시크릿 필터링 기능 활용

## 📚 추가 리소스

### 공식 문서
- [Claude Code Overview](https://code.claude.com/docs/en/overview)
- [Agent Skills Documentation](https://code.claude.com/docs/en/skills)
- [Sub-agents Guide](https://code.claude.com/docs/en/sub-agents)
- [Agent Teams](https://code.claude.com/docs/ko/agent-teams)
- [Claude Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)
- [Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)

### 커뮤니티 리소스
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)
- [Claude Developers Discord](https://discord.gg/anthropic)

### 유용한 블로그 & 가이드
- [Claude Code Best Practices (Anthropic)](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

## 📝 CLAUDE.md 핵심 템플릿

```markdown
# Project Context for Claude Code

## 🎯 Project Overview
- **Name**: [프로젝트 이름]
- **Purpose**: [프로젝트 목적]
- **Tech Stack**: [사용 기술]
- **Current Phase**: [현재 개발 단계]

## 🛠️ Development Guidelines

### Code Style
- Language: [JavaScript/Python/etc]
- Style Guide: [ESLint/Prettier 설정]
- Naming Conventions:
  - Functions: camelCase
  - Classes: PascalCase
  - Constants: UPPER_SNAKE_CASE

### Git Workflow
- Branch naming: feature/[feature-name]
- Commit format: [type]: [description]
  - feat: 새 기능
  - fix: 버그 수정
  - docs: 문서 수정
  - refactor: 코드 리팩토링

## ⚡ Common Tasks
[자주 수행하는 작업들의 단계별 가이드]

## 🔒 Security & Permissions
- Never modify: [보호된 파일들]
- Always test before: [중요 작업들]
- Require review for: [리뷰 필요 항목]

## 📝 Important Notes
- [프로젝트 특수 사항]
- [주의사항]
- [팀 규칙]
```

## 🎓 학습 로드맵

### Week 1: 기초
- [ ] Claude Code 설치 및 설정 (현재 v2.1.210)
- [ ] 기본 명령어 익히기 (/effort, /fast, /compact, /loop, /schedule)
- [ ] 첫 CLAUDE.md 작성
- [ ] 간단한 코드 생성 테스트

### Week 2: Skills 마스터
- [ ] skill-creator로 첫 Skill 생성
- [ ] 3개 이상의 다양한 Skills 작성 (번들 리소스 포함)
- [ ] Skill chaining 연습
- [ ] 팀과 Skills 공유

### Week 3: Sub-agents & Memory 활용
- [ ] 첫 Sub-agent 생성 (effort, maxTurns 설정)
- [ ] Multi-agent 워크플로우 구성
- [ ] 메모리 시스템 설정 및 활용
- [ ] 프로젝트별 최적 agent 구성

### Week 4: 고급 기능
- [ ] Hooks 설정 및 자동화 (PostToolUseFailure, PreCompact, SubagentStart 포함)
- [ ] 플러그인 설치 및 커스텀 플러그인 작성
- [ ] MCP 서버 연동 (claude-in-chrome, context7, playwright 등)
- [ ] Worktree 격리 + run_in_background 활용
- [ ] Plan Mode + ExitPlanMode + AskUserQuestion 워크플로우

## 💡 팁 & 트릭

### 성능 최적화
1. **컨텍스트 관리**: `/compact`로 압축, `/clear`로 리셋
2. **모델 선택**: 가벼운 작업은 Haiku/`/fast`, 복잡한 작업은 Opus + `/effort high`
3. **Skill 설계**: Progressive Disclosure 원칙, 캐릭터 버짓(~2%) 준수
4. **Agent 분할**: 큰 작업을 작은 전문 태스크로 분할
5. **1M 컨텍스트 활용**: 대규모 코드베이스도 한 세션에서 처리

### 일반적인 문제 해결
| 문제 | 해결 방법 |
|------|-----------|
| Skill이 로드되지 않음 | YAML frontmatter 확인, description 구체화 |
| Agent가 호출되지 않음 | description 필드 구체화, model 지정 |
| 권한 오류 | .claude/settings.json 권한 설정 확인 |
| 컨텍스트 오버플로우 | `/compact` 사용, 작업 분할 |
| 메모리 미작동 | MEMORY.md 인덱스 확인, frontmatter 형식 검증 |
| 플러그인 미인식 | plugin.json 매니페스트 경로 확인 |

## 🔄 업데이트 내역

### 2026년 6월 기준 주요 업데이트 (5월 대비)
- **Claude Opus 4.8**: 최신 플래그십 모델 (ID `claude-opus-4-8`, 1M 컨텍스트 변형 존재, 4.7 후속)
- **Claude Fable 5**: 신규 세대 모델 (ID `claude-fable-5`)
- **Claude Sonnet 4.6 / Haiku 4.5**: 유지 → 이후 Sonnet 5로 갱신 (현행 SSOT: Sonnet 5)
- **`/fast` 모드**: Opus 4.8/4.7 지원 (작은 모델로 다운그레이드가 아니라 Opus를 빠른 출력으로 실행)
- **Workflow 도구**: 인라인 JS 스크립트 오케스트레이션 (agent/parallel/pipeline/phase/budget, worktree 격리, 동시성 캡, 백그라운드+알림) — 아래 "Workflow 도구" 섹션 참조
- **신규 빌트인 도구/스킬**: advisor, ScheduleWakeup, Cron{Create,List,Delete}, EnterWorktree/ExitWorktree, Monitor, Skill, ToolSearch, SendUserFile, PushNotification, RemoteTrigger, DesignSync 등 — 아래 "신규 빌트인 도구 카탈로그" 참조
- **에이전트 네임스페이스 정정**: "완전 평탄화"가 아니라 플랫 빌트인 + 플러그인 스코프(`ecc:*`) 공존

### 2026년 5월 기준 주요 업데이트 (3월 대비)
- **Claude Code CLI**: v2.1.143 (3월의 v2.1.78에서 65 patch 진행)
- **Claude Opus 4.7**: 최신 플래그십 모델 (1M 컨텍스트, 4.6 후속)
- **Claude Sonnet 4.6**: 코딩/에이전트 메인 (유지)
- **Claude Haiku 4.5**: 경량 (유지, ID: `claude-haiku-4-5-20251001`)
- **3대 프레임워크 공식화**: GSD/Superpowers/Gstack 모두 공식 스킬 등록 (수동 설치 불필요)
- **Plan Mode 통합**: ExitPlanMode + AskUserQuestion 정식 도구화
- **ToolSearch**: deferred 도구 동적 로딩 — 토큰 절약을 위한 lazy loading
- **/loop, /schedule**: 반복 작업 및 cron 기반 routine
- **Hooks 이벤트**: `PostToolUseFailure`/`SubagentStart`/`PermissionRequest`/`Setup` 등이 유효 이벤트 목록에 포함(위 "Hooks 종류" 참조)
- **subagent_type 정리**: `feature-dev:*` 네임스페이스 제거. 단 "완전 평탄화"는 아니며, 플랫 빌트인 타입과 플러그인 스코프(`ecc:*`) 에이전트가 공존
- **MCP 다양화**: claude-in-chrome, computer-use, Figma, Slack, Google Drive, playwright, context7 등 정식 통합

### 2026년 3월 시점 (참고용 히스토리)
- v2.1.78, Opus 4.6, Sonnet 4.6 (1M), 플러그인 시스템, 메모리 시스템 도입, effort/maxTurns/disallowedTools, .claudecode.json → .claude/settings.json 이전

---

*이 가이드는 지속적으로 업데이트됩니다. 최신 정보는 공식 문서를 참고하세요.*

#claude-code #ai-development #2026-guide #macos