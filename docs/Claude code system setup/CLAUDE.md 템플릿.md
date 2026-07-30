---
tags:
  - claude
  - setup
---

# CLAUDE.md 템플릿
#template #claude-code #project-setup

> 최종 업데이트: 2026-07-15 (이전: 2026-03-21)
> Boris Cherny 원칙 기반: "Claude가 추측할 수 없는 것만 넣어라"
> 대상 환경: Claude Code v2.1.210 (Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5)

## 핵심 원칙

Boris Cherny(Claude Code 창시자)의 CLAUDE.md 철학:

| 원칙 | 설명 |
|------|------|
| **500토큰 목표** | Boris 팀의 CLAUDE.md는 ~500토큰(40-80줄). 길면 규칙이 무시됨 |
| **Shortcut** | 포괄적 문서가 아니라, Claude가 반복적으로 틀리는 것만 고치는 지름길 |
| **삭제 테스트** | "이걸 빼면 Claude가 실수하나?" — 아니면 삭제 |
| **살아있는 문서** | 매주 업데이트, 모델 발전하면 항목 제거 |
| **Claude가 자체 작성** | "Update your CLAUDE.md so you don't make that mistake again" |

### Include / Exclude (Anthropic 공식)

| Include | Exclude |
|---------|---------|
| Claude가 추측할 수 없는 bash 명령어 | Claude가 코드를 읽으면 아는 것 |
| 기본값과 다른 코드 스타일 규칙 | 표준 언어 관습 (camelCase 등) |
| 테스트 러너 및 실행 방법 | 파일별 코드베이스 설명 |
| 프로젝트 특유의 아키텍처 결정 | 자주 변경되는 정보 |
| 환경 변수, 개발 환경 quirks | 긴 설명이나 튜토리얼 |
| Common gotchas | "write clean code" 같은 자명한 것 |

---

## 템플릿

```markdown
# CLAUDE.md

## Project Overview

**[프로젝트명]** - [한 줄 설명]

| Layer | Stack |
|-------|-------|
| Frontend | [React 19, TypeScript, Tailwind, Vite] |
| Backend | [FastAPI, PostgreSQL, Redis] |
| Deploy | [Docker, AWS] |

## Quick Start

\`\`\`bash
# 설치
npm install

# 개발서버
npm run dev          # Frontend (localhost:3000)
cd backend && uvicorn app:app --reload  # Backend (localhost:8000)

# 인프라
docker compose up -d  # DB, Redis
\`\`\`

## Testing

\`\`\`bash
npm test                    # 전체 테스트
npm run test:coverage       # 커버리지
npx tsc --noEmit            # 타입체크
npm run lint                # 린트
\`\`\`

## Environment Variables

\`\`\`bash
DATABASE_URL=postgresql://...
REDIS_URL=redis://localhost:6379
API_KEY=...                  # [어디서 발급]
\`\`\`

## Architectural Decisions

- [프로젝트 특유의 패턴이나 결정 — Claude가 코드만 봐서는 모르는 것]
- [예: "React Router 대신 커스텀 useNavigationStore로 라우팅"]
- [예: "Service Layer 패턴 — 비즈니스 로직은 services/에 분리"]

## Gotchas

- [Claude가 반복적으로 틀리는 것]
- [예: "Metro 재시작 필요 — .env 변경 후"]
- [예: "asyncpg prepared statement 캐시 충돌 주의"]
```

---

## 사용 가이드

### 작성 순서
1. 위 템플릿을 프로젝트 루트에 `CLAUDE.md`로 저장
2. `[placeholder]`를 실제 값으로 대체
3. Claude가 실수할 때마다 Gotchas에 추가
4. 주기적으로 "이걸 빼도 되나?" 테스트 → 삭제

### 주의사항
- **200줄 이하 유지** — 길면 Claude가 중요한 규칙을 무시
- **표준 관습은 생략** — naming convention, git commit format 등 Claude가 이미 앎
- **디렉토리 구조 금지** — Claude가 도구로 직접 탐색 가능
- **파일별 설명 금지** — 코드를 읽으면 알 수 있는 정보
- **상세 내용은 docs/에 분리** 후 CLAUDE.md에서 참조만

### 프로젝트별 추가 섹션 (필요시만)

| 상황 | 추가 섹션 |
|------|----------|
| 슬래시 커맨드가 있을 때 | `## Commands` (표로 간결하게) |
| 멀티에이전트 사용 시 | `## Multi-Agent Orchestration` |
| 스킬 라우팅이 있을 때 | `## Skill Routing` |
| 상세 문서가 별도일 때 | `## Reference Docs` (링크 표) |

---

*태그: #template #claude-code #project-setup*
