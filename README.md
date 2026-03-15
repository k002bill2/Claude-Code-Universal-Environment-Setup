# Claude Code Universal Environment Setup

Production-tested Claude Code 설정을 새 프로젝트에 빠르게 적용하는 starter kit.

8개 프로젝트 운영 경험에서 추출한 **범용(Universal)** 설정만 포함합니다.

## What's Included

### Global Settings (`~/.claude/`)
프로젝트에 무관하게 모든 Claude Code 세션에 적용되는 설정:

| Category | Count | Description |
|----------|-------|-------------|
| Rules | 4 | 코딩 원칙, 보안, 검증, 소통 규칙 |
| Skills | 19 | 워크플로우, Git, 검증, 에이전트 관리 |

### Project Settings (`.claude/`)
개별 프로젝트에 복사하여 사용하는 템플릿:

| Category | Count | Description |
|----------|-------|-------------|
| Skills | 3 | Feature Planning, Verification Loop, Verify Implementation |
| Agents | 2 | Code Reviewer, Quality Validator |
| Commands | 3 | check-health, verify-app, auto pipeline |
| Hooks | 1 | Base hooks.json template |

### CLAUDE.md Template
프로젝트별 CLAUDE.md 생성을 위한 템플릿 (200줄 이하 가이드라인 준수).

## Quick Start

```bash
# 1. Clone
git clone https://github.com/k002bill2/Claude-Code-Universal-Environment-Setup.git
cd Claude-Code-Universal-Environment-Setup

# 2. Install (interactive)
./install.sh

# 3. Options
./install.sh --global-only      # Global 설정만 설치
./install.sh --project /path    # 특정 프로젝트에 설정 복사
./install.sh --dry-run          # 변경사항 미리보기
```

## Directory Structure

```
.
├── global/                     # → ~/.claude/ 에 설치
│   ├── rules/                  # 글로벌 규칙 (4개)
│   └── skills/                 # 범용 스킬 (19개)
├── project/                    # → .claude/ 에 복사
│   ├── skills/                 # 프로젝트 스킬 템플릿
│   ├── agents/                 # 에이전트 템플릿
│   ├── commands/               # 커맨드 템플릿
│   └── hooks.json              # 기본 hooks
├── examples/
│   └── CLAUDE.md.example       # CLAUDE.md 예시
├── CLAUDE.md.template          # CLAUDE.md 템플릿
├── install.sh                  # 설치 스크립트
└── README.md
```

## Customization

### Rules 커스터마이징
`global/rules/interaction.md`에서 언어 설정을 변경:
```markdown
# 기본값: 한국어
- 한국어로 소통
# 영어로 변경 시:
- Communicate in English
```

### 프로젝트별 스킬 추가
`project/skills/` 에 프로젝트 특화 스킬을 추가한 후 `install.sh --project` 실행.

### Hooks 설정
`project/hooks.json`을 프로젝트 요구사항에 맞게 수정.

## Skill Categories

### Workflow & Planning
| Skill | Purpose |
|-------|---------|
| `dev-docs` | 대규모 작업을 위한 3-파일 문서 시스템 |
| `update-dev-docs` | Context Compaction 전 문서 업데이트 |
| `save-and-compact` | 저장 후 compact 안내 |
| `resume` | 이전 세션 컨텍스트 복원 |
| `feature-planner` | TDD 기반 단계별 기능 계획 |
| `run-workflow` | YAML DAG 기반 워크플로우 실행 |

### Git & Code Quality
| Skill | Purpose |
|-------|---------|
| `commit-push-pr` | Conventional Commits + PR 자동화 |
| `draft-commits` | 변경사항 분석 및 커밋 초안 |
| `review` | Git diff 기반 코드 리뷰 |
| `simplify-code` | 코드 복잡도 분석 및 단순화 |
| `verification-loop` | Boris Cherny 스타일 검증 루프 |
| `verify-implementation` | 모든 verify 스킬 순차 실행 |

### Infrastructure & Meta
| Skill | Purpose |
|-------|---------|
| `skill-creator` | 새 스킬 생성 가이드 |
| `subagent-creator` | 서브에이전트 생성 가이드 |
| `hook-creator` | 훅 생성 가이드 |
| `slash-command-creator` | 슬래시 커맨드 생성 가이드 |
| `config-backup` | .claude/ 설정 백업/복원 |
| `cli-orchestration` | CLI 병렬/순차/DAG 실행 |

### Multi-Agent Governance
| Skill | Purpose |
|-------|---------|
| `ace-framework` | 4-Pillar 거버넌스 모델 |
| `agent-improvement` | 에이전트 자기개선 루프 |
| `agent-observability` | 프로덕션 추적 및 메트릭 |
| `external-memory` | 장기 실행 컨텍스트 지속성 |

## Origin

이 설정은 다음 프로젝트들의 운영 경험에서 추출되었습니다:
- Agent-System (AOS) - 멀티 에이전트 오케스트레이션
- AOS_web - 웹 대시보드
- image-maker - AI 이미지 생성
- youtube-maker - AI 영상 제작
- ppt-maker - AI 프레젠테이션
- LiveMetro - 실시간 지하철 앱

## License

MIT
