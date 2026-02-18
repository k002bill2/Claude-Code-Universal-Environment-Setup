# Claude Code Universal Environment Setup

Claude Code 프로젝트 환경을 빠르게 구축하기 위한 범용 설치 패키지입니다.

## Quick Start

```bash
# 1. 설치 스크립트 실행
bash install.sh /path/to/your/project

# 2. 대화형 설정 따라가기
# - 프로젝트 타입 선택
# - 설치할 기능 선택
# - 프로젝트 정보 입력

# 3. 설치 완료 후 Claude Code 실행
cd /path/to/your/project
claude
```

## 설치되는 구조

```
your-project/
├── CLAUDE.md                          # 프로젝트 가이드 (가장 중요!)
├── .claudecode.json                   # 권한 & 훅 설정
├── .mcp.json                          # MCP 서버 설정
├── skill-rules.json                   # Skills 자동 활성화 규칙
├── .claude/
│   ├── skills/                        # Agent Skills
│   │   ├── code-reviewer/SKILL.md     # 코드 리뷰
│   │   ├── test-runner/SKILL.md       # 테스트 실행
│   │   └── docs-generator/SKILL.md    # 문서 생성
│   ├── agents/                        # Sub-agents
│   │   ├── frontend-specialist.md     # 프론트엔드 전문가
│   │   ├── backend-specialist.md      # 백엔드 전문가
│   │   ├── test-engineer.md           # 테스트 엔지니어
│   │   └── shared/                    # 공유 프레임워크
│   │       ├── quality-gates.md       # 품질 게이트
│   │       ├── effort-scaling.md      # 작업 규모 가이드
│   │       └── parallel-agents-protocol.md  # 병렬 실행 프로토콜
│   ├── commands/                      # 커스텀 슬래시 명령어
│   │   ├── dev-docs.md                # /dev-docs
│   │   ├── update-dev-docs.md         # /update-dev-docs
│   │   ├── verify.md                  # /verify
│   │   ├── review.md                  # /review
│   │   └── resume.md                  # /resume
│   └── hooks/                         # Hook 스크립트
│       ├── skill-activator.js         # Skills 자동 활성화
│       └── post-edit-check.sh         # 편집 후 검사
└── dev/                               # Dev Docs (대규모 작업용)
    ├── active/                        # 진행 중 작업
    └── completed/                     # 완료된 작업
```

## 핵심 구성요소

### 1. CLAUDE.md
프로젝트 컨텍스트 파일. Claude Code가 프로젝트를 이해하는 핵심 문서.

### 2. Skills (`.claude/skills/`)
재사용 가능한 전문 지식 모듈:
- **code-reviewer**: 코드 품질, 보안, 성능 리뷰
- **test-runner**: 테스트 실행, 커버리지 분석
- **docs-generator**: 문서 자동 생성

### 3. Sub-agents (`.claude/agents/`)
독립 컨텍스트를 가진 전문 에이전트:
- **frontend-specialist**: React/TypeScript UI 개발
- **backend-specialist**: API, DB, 서비스 아키텍처
- **test-engineer**: 테스트 자동화

### 4. Commands (`.claude/commands/`)
커스텀 슬래시 명령어:
| Command | Description |
|---------|-------------|
| `/dev-docs <name>` | 3-파일 Dev Docs 생성 |
| `/update-dev-docs` | Dev Docs 업데이트 |
| `/verify` | 타입체크+린트+테스트+빌드 |
| `/review` | 코드 리뷰 |
| `/resume` | 이전 작업 컨텍스트 복원 |

### 5. Skill Auto-Activation
`skill-rules.json`에 정의된 키워드/패턴 매칭으로 Skills를 자동 활성화하는 Hook 시스템.

### 6. Dev Docs System
대규모 작업의 컨텍스트를 3개 파일로 관리:
- `plan.md`: 승인된 계획
- `context.md`: 핵심 결정사항과 현재 상태
- `tasks.md`: 체크리스트

## 커스터마이징

### CLAUDE.md 수정
설치 후 반드시 프로젝트에 맞게 수정하세요:
- 실제 디렉토리 구조
- 기술 스택 상세
- 코딩 컨벤션
- 보안 규칙

### skill-rules.json 수정
프로젝트 도메인에 맞는 키워드/패턴 추가:
```json
{
  "my-custom-skill": {
    "type": "domain",
    "enforcement": "suggest",
    "priority": "high",
    "promptTriggers": {
      "keywords": ["my-keyword"],
      "intentPatterns": ["(create|add).*?my-pattern"]
    }
  }
}
```

### 새 Skill 추가
```bash
mkdir -p .claude/skills/my-skill
# SKILL.md 작성 (frontmatter + instructions)
```

### 새 Agent 추가
```bash
# .claude/agents/my-agent.md 생성
# frontmatter: name, description, tools, model
```

## 요구사항

- macOS / Linux / WSL
- Node.js v18+
- Git
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)

## 기반 자료

이 설치 패키지는 다음 가이드를 분석하여 범용화한 결과입니다:
- Claude Code 완벽 가이드북 2025
- Skills 자동 활성화 시스템
- Dev Docs 3-파일 시스템
- Parallel Agents Safety Protocol v3.0.1
- 프로젝트별 템플릿 모음
- 실전 예제 모음

---

*Version: 1.0.0*
# Claude-Code-Universal-Environment-Setup
# Claude-Code-Universal-Environment-Setup
# Claude-Code-Universal-Environment-Setup
