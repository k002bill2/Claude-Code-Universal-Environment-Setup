---
tags:
  - claude
  - setup
---

# Skills Guide - Claude Code 완벽 가이드

> **최신 업데이트**: 2026-06-16 갱신 (이전 2026-05-16, 2026-03-18에서 재최신화)
> **환경**: macOS (VS Code, Cursor 등)
> **대상**: Claude Code 초보자 ~ 중급자
> **CLI 버전**: v2.1.210 | **모델**: Opus 4.8 / Fable 5 / Sonnet 5 (1M 컨텍스트) / Haiku 4.5

---

## 📚 가이드 구성

이 폴더는 Claude Code를 효과적으로 활용하기 위한 완벽한 가이드 모음입니다.

### 🌟 핵심 가이드

| 파일명 | 설명 | 난이도 |
|--------|------|--------|
| **Claude Code 완벽 가이드북 2026.md** | 가장 포괄적인 통합 가이드 | 초급~중급 |
| **Quick Reference.md** | 빠른 참조용 치트시트 | 모든 레벨 |
| **실전 예제.md** | 실무 적용 예제 모음 | 중급 |

### 🛠️ 시스템 구축 가이드

| 파일명                      | 설명                        |
| ------------------------ | ------------------------- |
| **Skills 자동 활성화 시스템.md** | Skills 활성화 Hook 시스템 구축 |
| **Dev Docs 시스템.md**      | 대규모 작업용 3-파일 문서 시스템 + 메모리 연계 |
| **PM2 백엔드 디버깅.md**       | 마이크로서비스 관리 및 디버깅          |
| **Parallel Agents Safety Protocol v3.1.0.md** | 멀티에이전트 안전 프로토콜 |
| **CLI Orchestration 설정.md** | CLI 오케스트레이션 가이드 |

### 📋 템플릿

| 파일명 | 설명 |
|--------|------|
| **CLAUDE.md 템플릿.md** | 프로젝트별 컨텍스트 파일 템플릿 |
| **프로젝트별 템플릿.md** | 웹/백엔드/ML/모바일 등 프로젝트 타입별 설정 |
| **Agent Skills 예시 모음.md** | 재사용 가능한 Skills 코드 모음 |

### 📖 참고 자료

| 파일명 | 설명 |
|--------|------|
| **온톨로지 정의와 구축 방법론.md** | 지식 표현 체계 이론 |
| **시스템 구축단계 정리.md** | 외부 참조 링크 모음 |

---

## 🚀 빠른 시작

### 1단계: 기본 이해
```bash
# 먼저 읽어야 할 순서
1. Claude Code 완벽 가이드북 2026.md  # 전체 개요
2. Quick Reference.md                  # 명령어 익히기
3. CLAUDE.md 템플릿.md                 # 첫 프로젝트 설정
```

### 2단계: 시스템 구축
```bash
# 필요에 따라 선택
- Skills 자동 활성화 시스템.md   # Skills 제대로 활용하기
- Dev Docs 시스템.md            # 대규모 작업 관리
- PM2 백엔드 디버깅.md          # 백엔드 개발자용
```

### 3단계: 실전 적용
```bash
# 실무 예제로 학습
- 실전 예제.md                  # 실제 워크플로우 익히기
- 프로젝트별 템플릿.md          # 프로젝트 타입별 설정
- Agent Skills 예시 모음.md     # 재사용 가능한 코드
```

---

## 💡 핵심 개념 요약

### Claude Code란?
- Anthropic의 AI 기반 터미널 코딩 도구
- 2026년 7월 기준 최신 버전: **v2.1.210** (3월 v2.1.78에서 132 patch 진행)
- Agent Skills, Sub-agents, Hooks, **플러그인**, **메모리**, **Plan Mode**, **공식 스킬 프레임워크(GSD/Superpowers/Gstack)** 등 강력한 기능 제공
- **Opus 4.8 / Fable 5 / Sonnet 5** 모델 지원 (**1M 컨텍스트**), Haiku 4.5는 200K 컨텍스트

| 모델 | ID | 컨텍스트 | 비고 |
|------|-----|---------|------|
| **Opus 4.8** | `claude-opus-4-8` | 1M 변형 존재 | 플래그십 |
| **Fable 5** | `claude-fable-5` | — | 신규 세대 |
| **Sonnet 5** | `claude-sonnet-5` | 1M | — |
| **Haiku 4.5** | `claude-haiku-4-5-20251001` | 200K | 경량 |

> `/fast` 모드는 Opus 4.8/4.7을 지원합니다. 작은 모델로 다운그레이드하는 것이 아니라, Opus를 빠른 출력으로 실행합니다.

### 필수 4대 시스템
1. **Skills + 플러그인**: Hook 기반 활성화 + 플러그인 마켓플레이스
2. **Dev Docs 3-파일**: plan.md, context.md, tasks.md
3. **메모리 시스템**: 세션 간 영속 정보 (user/feedback/project/reference)
4. **설정 파일**: `.claude/settings.json`으로 권한, 훅, 모델 통합 관리

---

## 🧩 신규 도구/메커니즘 (※ 2026-06-16 갱신)

최근 환경에 추가된 도구/스킬/메커니즘 요약입니다. 옛 가이드에 없던 항목입니다.

### Workflow 도구 (인라인 JS 오케스트레이션)
- 반드시 `export const meta = { name, description, phases }` (순수 리터럴)로 시작.
- 본문에서 전역 함수를 직접 `await`:
  - `agent(prompt, opts?)` — 서브에이전트 실행. `opts = { label, phase, schema, model, effort, isolation:'worktree', agentType }`. `schema`를 주면 검증된 객체 반환.
  - `parallel(thunks)` — 동시 실행 + 배리어(모두 완료 후 반환). 실패 항목은 `null`.
  - `pipeline(items, stage1, stage2, ...)` — 항목별 독립 파이프라인, 단계 간 배리어 없음.
  - `phase(title)`, `log(message)`, `args(입력값)`, `budget(토큰 예산)`, `workflow(name, args)` (중첩 1단계).
- 동시 실행은 `min(16, CPU코어-2)`로 자동 캡, 총 1000 에이전트 상한. 백그라운드 실행 후 완료 알림.
- 참고: `workflow.pipeline([...])`, `.withIsolation().run()`, `workflow.background()` 같은 fluent 빌더 체인 표현은 실재하지 않습니다.

### advisor
- 전체 트랜스크립트를 보는 상위 리뷰어(파라미터 없음). 접근법 확정 전 / 완료 선언 전에 호출하는 검증 게이트.

### 스케줄링 — ScheduleWakeup / /loop / /schedule / Cron
- `/loop` 스킬: 반복 실행(인터벌 지정 또는 모델 셀프 페이싱). `ScheduleWakeup`은 `/loop`의 동적 페이싱 재개를 스케줄.
- `/schedule` 스킬: cron 클라우드 에이전트(routine).
- `CronCreate` / `CronList` / `CronDelete`: cron 예약 에이전트 관리.

### Skill 도구 + ToolSearch
- `Skill` 도구: 스킬 명시 호출.
- `ToolSearch`: 디퍼드(지연 로드) 도구 스키마를 동적으로 로드.

### 빌트인 스킬
- `deep-research` — 다중 소스 팬아웃 + 검증 + 인용 리포트.
- `skill-creator` — 스킬 생성/개선/평가.
- `frontend-design` — 의도적 비주얼 디자인 가이드.
- `simplify` — 변경 코드의 재사용/단순화/효율 정리(품질 전용, 버그 헌팅은 `/code-review`).
- `document-skills` — xlsx/docx/pptx/pdf 문서 처리.
- `/code-review ultra` (=ultrareview) — 멀티에이전트 클라우드 리뷰(사용자 트리거).

### MCP 생태계
- claude-in-chrome, Figma, Canva, Atlassian, Notion, Slack, Gmail, Google(Calendar/Drive), Context7, Playwright 등 다수. `ToolSearch`로 동적 로드.

### Worktree 라이프사이클 + 모니터링
- `EnterWorktree` / `ExitWorktree` — worktree 라이프사이클 관리(자체 git worktree, 미변경 시 자동 정리).
- `Monitor` — 백그라운드 프로세스/조건 모니터링.
- 보조 도구: `SendUserFile`(산출 파일 전달), `PushNotification`, `RemoteTrigger`, `DesignSync`.

---

## 🎯 학습 로드맵

### Week 1: 기초 다지기
- [ ] Claude Code v2.1.210 설치 및 설정
- [ ] 기본 명령어 익히기 (/effort, /fast, /compact, /loop, /schedule 포함)
- [ ] 첫 CLAUDE.md 작성

### Week 2: Skills & 플러그인
- [ ] Agent Skills 이해 (번들 리소스, 캐릭터 버짓)
- [ ] skill-creator로 첫 Skill 생성
- [ ] 플러그인 설치 및 활용

### Week 3: Advanced 기능
- [ ] Sub-agents 활용 (effort, maxTurns, worktree)
- [ ] 메모리 시스템 설정
- [ ] Dev Docs 시스템 도입
- [ ] Hooks와 자동화 설정

### Week 4: 실전 프로젝트
- [ ] 실전 예제로 연습
- [ ] Parallel Agents 프로토콜 적용
- [ ] 팀과 공유

---

## 🔥 자주 묻는 질문

### Q: 처음 시작하는데 어디서부터?
**A**: `Claude Code 완벽 가이드북 2026.md` → `Quick Reference.md` 순서로 읽으세요.

### Q: Skills를 만들었는데 Claude가 안 써요
**A**: `Skills 자동 활성화 시스템.md`를 보고 Hook 시스템을 구축하세요. v2.1.x에서 자동 인식이 개선되었고 `superpowers:using-superpowers` 같은 메타 스킬도 도입되었지만, 복잡한 프로젝트에서는 여전히 Hook이 유효합니다.

### Q: 대규모 작업시 Claude가 길을 잃어요
**A**: `Dev Docs 시스템.md`의 3-파일 시스템 + 메모리 시스템을 병행하세요. Dev Docs는 대규모 작업용, 메모리는 세션 간 영속 정보용입니다.

### Q: 백엔드 서비스가 여러 개인데 관리가 힘들어요
**A**: `PM2 백엔드 디버깅.md`를 참고하여 PM2로 통합 관리하세요.

### Q: 메모리가 세션마다 초기화돼요
**A**: `/memory` 명령어로 영구 메모리를 확인하세요. 메모리 파일은 `~/.claude/projects/<project>/memory/`에 자동 저장됩니다.

### Q: 플러그인은 어떻게 설치하나요?
**A**: `.claude/plugins/` 디렉토리에 플러그인을 설치하거나, 마켓플레이스에서 검색하세요. `plugin.json` 매니페스트가 필수입니다.

### Q: .claudecode.json은 더 이상 안 쓰나요?
**A**: `.claude/settings.json`으로 이전되었습니다. 기존 .claudecode.json도 호환되지만, 새 형식을 권장합니다.

---

## 📊 환경 요구사항

### 필수
- macOS (Intel 또는 Apple Silicon)
- Node.js **v20 이상**
- Git
- VS Code, Cursor 등 에디터

### 권장
- Claude Code CLI **v2.1.210** 이상 (2026-07 기준)
- TypeScript 5.5+
- Next.js 15+ (웹 개발시)
- Docker (백엔드 개발시)

---

## 🔗 유용한 링크

### 공식 문서
- [Claude Code 공식 문서](https://docs.anthropic.com/en/docs/claude-code)
- [Agent Skills 가이드](https://docs.anthropic.com/en/docs/claude-code/skills)
- [Sub-agents 문서](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Agent Teams](https://code.claude.com/docs/ko/agent-teams)

### 커뮤니티
- [Claude Developers Discord](https://discord.gg/anthropic)
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)

### 엔지니어링 블로그
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)

---

## 📝 기여 및 피드백

이 가이드는 실전 경험을 바탕으로 지속적으로 업데이트됩니다.
- 오류 발견시: Issues 등록
- 개선 제안: Pull Request 환영
- 추가 예제: 공유 환영

---

**Happy Coding with Claude Code! 🚀**

*마지막 업데이트: 2026-07-15 갱신 (이전 2026-05-16)*
*환경: macOS | Claude Code v2.1.210 | Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5*

#claude-code #ai-coding #guide #macos