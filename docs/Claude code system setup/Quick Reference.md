---
tags:
  - claude
  - setup
---

# Claude Code Quick Reference
#claude-code #reference #cheatsheet

## 🚀 빠른 시작 체크리스트

### 설치 (macOS)
```bash
# 1. Node.js 설치 확인 (v20+)
node --version

# 2. Claude Code CLI 설치
npm install -g @anthropic-ai/claude-code

# 3. 버전 확인 (2026-07 기준 최신: v2.1.210)
claude --version

# 4. 로그인
claude
/login
```

### 프로젝트 초기 설정
```bash
# 1. 프로젝트 디렉토리 생성
mkdir my-project && cd my-project

# 2. 필수 디렉토리 구조 생성
mkdir -p .claude/skills .claude/agents .claude/commands .claude/plugins

# 3. CLAUDE.md 생성 (가장 중요!)
touch CLAUDE.md

# 4. 설정 파일 생성
mkdir -p .claude && touch .claude/settings.json .mcp.json

# 5. Git 초기화
git init
echo ".env" >> .gitignore
```

## 📁 필수 파일 구조

```
my-project/
├── CLAUDE.md                    # ⭐ 프로젝트 가이드 (필수)
├── .claude/
│   ├── settings.json            # 권한, Hooks, 모델 설정
│   ├── skills/                  # Agent Skills
│   │   └── [skill-name]/
│   │       ├── SKILL.md
│   │       └── resources/       # 번들 리소스
│   ├── agents/                  # Sub-agents
│   │   └── [agent-name].md
│   ├── commands/                # 커스텀 명령어
│   │   └── [command].md
│   ├── plugins/                 # 🔌 플러그인
│   │   └── [plugin-name]/
│   │       └── plugin.json
│   └── memory/                  # 🧠 프로젝트 메모리
│       └── MEMORY.md
├── .mcp.json                    # MCP 서버 설정
└── PRD.md                       # 프로젝트 요구사항
```

## 🎮 주요 명령어 (v2.1.210)

### 기본 명령어
| 명령어 | 설명 | 사용 예시 |
|--------|------|-----------|
| **`double-esc`** | 이전 프롬프트 분기 | 다른 결과 시도 |
| **Planning Mode** | 계획 모드 시작 | 모든 작업 전 필수! |
| `/clear` | 컨텍스트 초기화 | 새 작업 시작 전 |
| `/compact` | 컨텍스트 압축 | 긴 세션 중 공간 확보 |
| `/agents` | Sub-agents 관리 | agent 생성/수정 |
| `/model` | 모델 변경 | sonnet/opus/haiku |
| `/effort` | effort 레벨 설정 | low/medium/high |
| `/fast` | 빠른 모드 토글 | Opus 4.8/4.7에서 출력 가속 (작은 모델로 다운그레이드 X) |
| `/help` | 도움말 | 명령어 목록 확인 |
| `/bug` | 버그 리포트 | 문제 발생 시 |

### 고급 명령어
| 명령어 | 설명 | 사용 예시 |
|--------|------|-----------|
| `/memory` | 메모리 관리 | 세션 간 정보 보존 |
| `/branch` | 세션 분기 | /fork 대체, 분기점 생성 |
| `/copy N` | N번째 응답 복사 | 결과물 클립보드 복사 |
| `/context` | 컨텍스트 최적화 제안 | 효율성 개선 힌트 |
| `/loop [N분] /명령` | 반복 작업 (간격 지정 또는 자율 페이싱) | 배포 모니터링, 폴링 |
| `/schedule` | 원격 cron 에이전트(routine) 관리 | 매일 X시 자동 실행 |
| `/statusline` | 상태 표시줄 설정 | 토큰/비용 표시 |
| `/hooks` | Hooks 설정 | 자동화 설정 |
| `/permissions` | 권한 관리 | 도구 권한 설정 |
| `/rewind` | 이전 상태로 복원 | 실수 되돌리기 |
| `Ctrl+B` | 백그라운드 실행 | dev server 실행 |
| `Ctrl+R` | Transcript 모드 | 대화 기록 모드 |

### 신규 도구/스킬 (※ 2026-06-16 갱신)
| 명령어/도구 | 설명 | 사용 예시 |
|--------|------|-----------|
| **Workflow 도구** | 인라인 JS 워크플로우로 병렬/파이프라인 오케스트레이션. `export const meta = { name, description, phases }`로 시작하고 본문에서 `agent()`, `parallel()`, `pipeline()`, `phase()` 등을 사용 | 다수 서브에이전트 병렬 실행 + 배리어 |
| `agent(prompt, opts?)` | 서브에이전트 실행. `opts = { label, phase, schema, model, effort, isolation:'worktree', agentType }`, schema 지정 시 검증된 객체 반환 | Workflow 본문에서 호출 |
| `parallel(thunks)` | 동시 실행 + 배리어(모두 완료 후 반환, 실패 항목은 null) | 독립 작업 동시 처리 |
| `pipeline(items, stage1, ...)` | 항목별 독립 파이프라인 (단계 간 배리어 없음) | 항목별 다단계 처리 |
| **advisor** | 전체 트랜스크립트를 보는 상위 리뷰어(파라미터 없음). 접근법 확정 전/완료 선언 전 검증 게이트 | 접근법 확정 전 호출 |
| `/loop` | 반복 실행 스킬 (간격 지정 또는 자율 페이싱). `ScheduleWakeup`로 동적 재개 | `/loop 5m /명령` |
| `/schedule` | cron 클라우드 에이전트(routine) 관리. `CronCreate`/`CronList`/`CronDelete` | 매일 X시 자동 실행 |
| **Skill 도구** | 스킬 명시 호출 | 특정 스킬 직접 실행 |
| **ToolSearch** | 디퍼드(지연 로드) 도구 스키마 동적 로드 | MCP 도구 동적 로드 |
| `/code-review ultra` | 멀티에이전트 클라우드 리뷰 (=ultrareview, 사용자 트리거) | PR 심층 리뷰 |
| `EnterWorktree` / `ExitWorktree` | worktree 라이프사이클 관리 | 격리 작업공간 진입/정리 |
| **Monitor** | 백그라운드 프로세스/조건 모니터링 | `run_in_background` 작업 감시 |

> Workflow 동시 실행은 자동으로 min(16, CPU코어-2)로 캡, 총 1000 에이전트 상한. 백그라운드 실행 후 완료 알림.

## 🔥 실전 핵심 워크플로우

### 1. Planning Mode (필수!)
```bash
# 계획 없이 시작 = 실패
"I need to implement [feature]. Let's start with planning mode."

# 에이전트 활용 계획
"Use the Plan agent to design the implementation for [feature]"
```

### 2. Dev Docs 시스템
```bash
# 대규모 작업시 필수
mkdir -p dev/active/[task-name]/
# plan.md, context.md, tasks.md 생성
/dev-docs  # Custom command
```

### 3. Effort & Fast 모드 활용
```bash
# 복잡한 작업 - 높은 추론 강도
/effort high

# 간단한 작업 - 빠른 처리
/fast

# 기본으로 복귀
/effort medium
```

### 4. 메모리 활용
```bash
# 메모리 확인
/memory

# 중요 정보 저장 요청
"이 프로젝트에서 Supabase RLS를 사용한다는 것을 기억해줘"
```

### 5. PM2 백엔드 관리
```bash
pnpm pm2:start      # 모든 서비스 시작
pm2 logs [service]  # Claude가 직접 로그 확인
pm2 restart [service]  # 문제 해결
```

## 🌟 Agent Skills 빠른 생성

### 방법 1: skill-creator 사용 (권장)
```bash
"Use the skill-creator skill to create a skill for [task]"
```

### 방법 2: 수동 생성
```bash
# 1. 디렉토리 생성 (번들 리소스 포함)
mkdir -p .claude/skills/my-skill/resources

# 2. SKILL.md 생성
cat > .claude/skills/my-skill/SKILL.md << EOF
---
name: my-skill
description: What this skill does and when to use it
---

# My Skill

## Instructions
1. Step one
2. Step two
3. Step three

## Resources
- resources/guide.md

## Examples
Example usage here
EOF

# 3. Claude 재시작
```

## 🤖 Sub-agent 빠른 생성

### 인터랙티브 생성
```bash
/agents
# 메뉴에서 선택:
# 1. Create new agent
# 2. Project-specific
# 3. Define purpose
# 4. Select tools
# 5. Choose color
```

### 수동 생성 (v2.1.210 형식)
```markdown
# .claude/agents/specialist.md
---
name: specialist
description: Specializes in specific tasks
tools: Edit, Write, Read, Grep, Glob, Bash
model: sonnet-5
# 참고: effort/maxTurns/disallowedTools는 환경별 지원 차이가 있어 권장 X.
# tools 화이트리스트가 안전한 도구 제한 방법.
---

You are a specialist in...
```

## ⚙️ Hooks 예시

### .claude/settings.json
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write(*.py)",
        "hooks": [{
          "type": "command",
          "command": "black \"$file\""
        }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo 'Tool execution failed' >> .claude/logs/errors.log"
        }]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo 'Context about to compact at $(date)'"
        }]
      }
    ]
  }
}
```

## 🔒 권한 설정

### .claude/settings.json
```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write(src/**)",
      "Bash(npm *)",
      "Bash(git *)"
    ],
    "deny": [
      "Read(.env*)",
      "Bash(sudo *)",
      "Bash(rm -rf *)"
    ]
  }
}
```

## 💡 실전 Pro Tips

### "Ask not what Claude can do for you, ask what context you can give to Claude"

### 핵심 교훈
1. **Planning 없이 시작 = 망함**
2. **Skills + 플러그인으로 자동화**
3. **Dev Docs + Memory = Claude의 기억**
4. **때로는 인간이 2분에 할 일 Claude가 30분 → 개입하라**
5. **Re-prompt often** - double-esc로 다시 시도
6. **/effort high로 복잡한 문제, /fast로 간단한 작업**

## 💡 프로 팁

### 효율성 극대화
1. **매일 시작**: `/compact`로 이전 컨텍스트 정리 또는 `/clear`
2. **작업 분할**: 큰 작업은 여러 agents로 (Worktree 격리 활용)
3. **Skill 재사용**: 자주 쓰는 작업은 Skill로
4. **백그라운드**: `Ctrl+B`로 서버 실행
5. **Git 통합**: Skills/Agents/Plugins를 버전 관리
6. **메모리 활용**: 반복되는 맥락은 메모리로 저장

### 문제 해결
| 증상 | 해결 |
|------|------|
| Skill 미작동 | description 구체화, YAML frontmatter 점검 |
| Agent 미호출 | description 구체화, model 지정 |
| 권한 오류 | .claude/settings.json 확인 |
| 컨텍스트 오버 | `/compact` 사용 |
| 느린 응답 | `/fast` 또는 모델을 haiku로 변경 |
| 메모리 미작동 | MEMORY.md 인덱스 + frontmatter 확인 |
| 플러그인 미인식 | plugin.json 경로 확인 |

## 📊 모델 선택 가이드 (2026-05 기준)

| 모델 | 컨텍스트 | 용도 | 속도 | 비용 |
|------|----------|------|------|------|
| **Haiku 4.5** | 200K | 간단한 작업, 빠른 반복 | 🚀🚀🚀 | 💰 |
| **Sonnet 5** | **1M** | 일반 개발, 코딩, 에이전트 | 🚀🚀 | 💰💰 |
| **Opus 4.8** | **1M** | 복잡한 추론, 엔터프라이즈, 최신 플래그십 (1M 컨텍스트 변형 존재) | 🚀 | 💰💰💰 |
| **Fable 5** | **1M** | 가장 까다로운 추론·장기 에이전트 작업 (최대 출력 128K) | 🚀 | 💰💰💰💰 |

> 모델 ID: `claude-opus-4-8`, `claude-fable-5`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`
> 가격(per MTok): Fable 5 $10/$50, Opus 4.8 $5/$25, Sonnet 5 $3/$15 (2026-08-31까지 인트로 $2/$10), Haiku 4.5 $1/$5
> 변경 이력: 2026-03 시점 Opus 4.6 → 2026-05 Opus 4.7 → 2026-06 Opus 4.8 (※ 2026-06-16 갱신)

## 🔗 필수 링크

- [공식 문서](https://docs.anthropic.com/en/docs/claude-code)
- [Skills 문서](https://docs.anthropic.com/en/docs/claude-code/skills)
- [Sub-agents 가이드](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Agent Teams](https://code.claude.com/docs/ko/agent-teams)
- [커뮤니티](https://discord.gg/anthropic)

---

*빠른 참조를 위한 체크리스트. 마지막 업데이트: 2026-07-15*
*환경: macOS (VS Code, Cursor 호환) | Claude Code v2.1.210 | Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5*

#quick-reference #cheatsheet #claude-code