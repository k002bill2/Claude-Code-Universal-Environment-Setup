# Claude Code Universal Environment Setup
# 설치 범용성 검토 보고서

> **상태:** 영환님 확인 대기 — 본 문서는 검토·제안 문서이며, 코드 수정과 커밋은 포함하지 않습니다.
>
> **검토일:** 2026-09-05
> **검토 대상:** `/Users/younghwankang/Work/Claude-Code-Universal-Environment-Setup`
> **기준 HEAD:** `6521fcac835e00cb8a8f4d85e8a550d9fcef214f`
> **검토 경로:** Buzz `#general` 새 최상위 설치 내용 범용성 재검토 안건
> **응답 상태:** 3 replies 확인 — Claude-Fable 2건, Honey 독립 재검토 1건. GPT-Luna·GPT-Sol·Gemini3.8의 이번 안건 독립 답변은 확인되지 않음.

---

## 1. 결론

현재 프로젝트의 성격은 다음과 같이 판정한다.

- **범용 배포 엔진:** `PASS (조건부)`
  - Bash 3.2 계열, `~/.claude` 고정 구조, jq 또는 node 전제를 만족하는 Unix 환경에서는 설치·manifest·merge·rollback 기반이 동작한다는 검토 결과가 있음.
  - 다만 운영체제·설정 루트·하위 설치기까지 포함한 완전한 범용성은 아직 검증되지 않았다.
- **범용 개발환경 계약:** `FAIL`
  - 항상 설치되는 payload에 특정 개인 하네스, Claude Code, npm/TypeScript/PM2, macOS 전제가 섞여 있다.
  - 기능별 선택·비활성화·capability loss 표시가 충분하지 않다.
- **종합:** `PARTIAL`

### 핵심 판단

이 프로젝트는 현재 **안전한 파일 배포·설정 병합 엔진**에 가깝다. 다양한 OS·셸·런타임·에디터가 공유할 수 있는 **중립적인 개발환경 계약**으로 보려면 P0 범위의 수정이 선행되어야 한다.

---

## 2. 검토 범위와 원칙

### 검토 범위

다음 설치 진입점과 산출물을 실제 파일·라인 근거로 검토하는 것을 요청했다.

- `install.sh`
- `lib/manifest.sh`
- `lib/merge-settings.sh`
- `global/`
- `project/`
- `fragments`
- `hooks`
- `scripts/sync-from-live.sh`
- `docs/Claude code system setup/install.sh`
- `docs/codex-advisor-worker-bundle/install.sh`
- 관련 README·문서·테스트

### 제외 범위

- 코드 수정
- 설치 실행에 따른 사용자 환경 변경
- 외부 발송·배포·Git push
- 인증·로그인·시크릿 발급
- 프로젝트 애플리케이션의 빌드·배포 결정
- 모든 IDE의 네이티브 플러그인 구현

---

## 3. 현재 설치 표면

### 3.1 글로벌 설치

- `global/rules` 7개
- `global/skills` 11개 디렉터리
- `global/agents` 2개
- 대상: `~/.claude/`
- 근거: `install.sh:1416-1444`

### 3.2 글로벌 settings 병합

- `global/settings-fragments/skill-overrides.json`의 87개 항목
- 대상: `~/.claude/settings.json`
- 근거: `install.sh:1387-1413`

현재 이 fragment에는 gsd/gstack/superpowers/Codex 등 특정 플러그인·개인 하네스와 연결된 항목이 포함될 가능성이 있다. 공통 코어와 개인 선호 설정을 분리해야 한다.

### 3.3 프로젝트 설치

- skills 3개
- agents 6개
- commands 3개
- hooks 및 settings fragments
- `CLAUDE.md`
- `skill-rules.json`
- `.mcp.json.example`
- Safety Protocol 문서
- `dev/` 골격 및 memory seed
- 근거: `install.sh:1451-1472`, `1476-1503`, `1554-1572`

### 3.4 선택·전체 설치

`--full` 및 하위 설치기 경로에서는 다음 산출물이 추가될 수 있다.

- advisor·examples·PM2
- 글로벌 agents/hooks/settings
- statusline 블록
- `~/.codex/config.toml`
- Codex 전역 설치
- 근거: `install.sh:158-166`, `1737-1768`
- Codex 전역 npm 설치 근거: `docs/codex-advisor-worker-bundle/install.sh:1568-1584`

### 3.5 현재 문서에 명시된 전제

현재 README는 다음을 전제로 한다.

- `jq` 또는 `node`
- `--with-advisor` 시 `python3` 또는 `jq`
- macOS/Bash 중심 실행
- Node 20+, VS Code/Cursor, TypeScript/Next.js 전제 문서
- 근거: `README.md:19-21`, `docs/Claude code system setup/README.md:202-214`

---

## 4. 발견 사항

표현을 다음과 같이 구분한다.

- **사실:** Buzz 검토 답변에서 파일·라인 또는 직접 확인 결과가 제시된 항목
- **추정:** 실제 consumer·플랫폼 동작을 추가 재현해야 하는 항목
- **확인 필요:** 현재 답변만으로 단정할 수 없거나 별도 환경 검증이 필요한 항목

### 4.1 설정 루트 고정 — P0

**사실**

- `$HOME/.claude`, `$HOME/.codex`를 직접 계산하는 경로가 존재한다.
- 근거: `install.sh:59`, `scripts/sync-from-live.sh:40`, advisor `install.sh:18-20`
- `CLAUDE_CONFIG_DIR`, XDG, `--claude-home`, `--codex-home` 처리 확인이 없다.

**위험**

사용자가 설정 위치를 옮긴 환경에서 설치기는 성공해도 런타임이 읽지 않는 위치에 쓸 수 있다.

**필수 추가**

- 최종 config root resolver
- `--claude-home`, `--codex-home` 또는 동등한 명시 override
- `--scope project|user|all`
- `doctor` 출력에 최종 경로와 실제 쓰기 대상 표시
- 기본 scope는 `project-only`

### 4.2 Hook identity가 args를 보존하지 않음 — P0

**사실**

- `lib/merge-settings.sh:10-25`, `248-278`에서 identity가 event·matcher·command 중심으로 처리된다.
- `args`가 다른 exec-form hook이 같은 command로 오인될 수 있다.

**위험**

- merge 시 hook 충돌
- unmerge 시 다른 hook 삭제
- 업그레이드 시 hook 유실

**필수 추가**

manifest schema v2에 다음을 canonical identity로 포함한다.

- event
- matcher
- type
- command
- args
- env
- timeout

`args`가 다른 두 hook을 병합하고, 각각 자기 identity만 제거하는 회귀 테스트를 추가한다.

### 4.3 사용자 seed의 broken symlink 경계 — P0

**사실**

- 관리 파일은 `-L`, 조상 링크, root boundary를 검사한다.
- 근거: `install.sh:221-237`, `350-425`
- 사용자 파일 설치 경로는 별도 검사 흐름을 사용한다.
- 근거: `install.sh:589-632`

**위험**

깨진 `CLAUDE.md`·memory seed symlink가 있을 때 복사 또는 redirection이 링크 대상 바깥에 쓰는 경로가 남을 수 있다.

**필수 추가**

- 사용자 파일에도 동일한 symlink·ancestor·root-boundary 검사
- broken symlink는 `BLOCKED`
- 경로 이탈 0건 테스트

### 4.4 하위 설치기가 root transaction 밖에 있음 — P0

**사실**

- root rollback이 하위 설치기 산출물을 모두 되돌리지 않는 범위 한계가 있다.
- 근거: `install.sh:846-849`
- advisor는 settings·agents·statusline·`~/.codex/config.toml` 등을 별도로 변경한다.

**필수 추가**

다음 중 하나를 선택한다.

1. 하위 설치기가 직접 쓰지 않고 operation plan을 반환하며, root installer가 단일 transaction으로 실행
2. 모든 하위 설치기가 동일한 manifest/journal/snapshot에 참여

`uninstall`, `rollback`, `SIGINT`, 부분 실패 테스트가 하위 산출물까지 포함해야 한다.

### 4.5 `--full`의 암묵적 network·global install — P0

**사실**

- `--full`은 advisor를 자동 활성화한다.
- 근거: `install.sh:158-166`
- Codex가 없으면 `npm install -g @openai/codex`를 수행한다.
- 근거: `docs/codex-advisor-worker-bundle/install.sh:1568-1584`

**필수 추가**

- 기본 `plan/apply` network 호출 0
- `--allow-network --install-tools` 같은 명시 동의
- 패키지 버전 pin
- 전역 설치·네트워크·Codex config 생성 여부를 plan에 표시
- 실패 시 rollback

### 4.6 개인 설정과 공통 코어 혼재 — P0/P1

**사실**

- `skill-overrides.json` 87개 항목이 글로벌 settings에 병합된다.
- 일부 rules와 문서가 특정 plugin·개인 하네스·AOS 경로를 참조한다.
- 검토 근거: `global/settings-fragments/skill-overrides.json`, `sync-from-live`, `git-workflow.md:24-25`, `verification.md:4`, `interaction.md:23-25`, `golden-principles.md:13`

**필수 추가**

다음 profile 계층을 명시한다.

```text
core
→ os
→ agent/editor
→ language/package-manager
→ team
→ user-local
```

개인 plugin·모델·경로·선호 권한은 user-local opt-in profile로 이동한다.

### 4.7 의존성 탐지와 실제 hook 활성화 불일치 — P0/P1

**사실**

- 설치기는 `jq 또는 node`를 전제로 설명한다.
- 실제 hook은 jq 의존성이 강하다.
- 근거: `build-checker.sh:27`, `stop-self-check.sh:25`, `post-tool-failure.sh:24`, `service-health-check.sh:22`
- Python 미설치 시 guardrails가 skip된다.
- 근거: `install.sh:1523-1530`
- advisor가 절대 Node 경로를 settings hook에 기록한다.
- 근거: advisor `install.sh:486-495`

**위험**

node-only 환경에서 설치는 성공하지만 hook이 동작하지 않을 수 있다. nvm·Volta 등의 Node 변경 후 advisor hook이 깨질 수 있다.

**필수 추가**

- dependency별 `PASS/WARN/BLOCKED/SKIPPED`
- hook별 활성화 여부와 비활성 사유
- 절대 Node 경로 대신 runtime resolver 또는 안정적인 launcher
- jq-only/node-only/python-only fixture
- npm/pnpm/yarn/bun·uv/poetry 및 nvm/Volta/mise/asdf/pyenv 감지
- environment lock

### 4.8 OS·셸·경로 범용성 부족 — P0/P1

**사실**

- Bash 3.2 중심이다.
- zsh/fish는 launcher 수준이며 별도 엔진이 아니다.
- native PowerShell adapter가 없다.
- `CLAUDE_CONFIG_DIR`·XDG 처리 확인이 없다.
- Windows 경로에 대한 보호 hook의 portable contract가 없다.

**권장 1차 범위**

- macOS
- Linux
- WSL 또는 Git Bash
- Bash installer/hook engine

**후순위**

- native Windows PowerShell
- junction·ACL·CRLF 테스트
- Windows 전용 경로·권한 adapter

**경로 테스트 필수 항목**

- 공백
- 유니코드 및 NFC/NFD
- 대괄호·glob 문자
- 긴 경로
- 심볼릭 링크
- broken/ancestor symlink
- read-only 경로
- LF/CRLF

### 4.9 MCP·문서 payload의 재현성 문제 — P1

**사실**

- `project/mcp.json.example`에 `npx -y` 및 unpinned MCP package가 있다.
- `install_global_docs`가 `docs/**/*.md`를 광범위하게 복사한다.
- 근거: `install.sh:1360-1383`
- 문서에 AOS·Agent-System·실제 사용자 경로와 macOS/Next.js 전제가 섞일 수 있다.

**필수 추가**

- MCP package version pin
- MCP 실행·설치는 opt-in
- 공개 release payload와 maintainer research/archive 분리
- 개인 경로·사용자명·provider/model pin 정적 검사

### 4.10 메모리 seed slug 규칙 — P1

**사실**

- 프로젝트 경로를 `/`와 `.` 기준으로 치환해 Claude 내부 memory 경로를 생성한다.
- 근거: `install.sh:1564-1572`

**확인 필요**

이 slug가 Claude consumer에서 공식적으로 보장되는 portable contract인지 별도 확인이 필요하다.

**권장**

- consumer가 제공하는 project identity 조회
- 자동 생성은 opt-in adapter로 제한
- Windows·경로 정규화 테스트 추가

---

## 5. 반드시 추가할 기능 목록

### P0 — 설치 안전성·범위·rollback

- config root resolver
- `--scope project|user|all`
- project-only 기본값
- hook identity schema v2
- broken/ancestor symlink 차단
- 사용자 파일 root boundary 검사
- 하위 설치기 unified transaction/journal
- `--full` network/global install opt-in화
- 개인 설정·개인 경로·개인 plugin 분리
- 설치 성공과 hook 보호 기능 활성화 상태 분리

### P1 — 재현성·운영성

- neutral manifest
- profile precedence/provenance
- `doctor --json`
- environment lock
- runtime/package-manager resolver
- `plan/apply/verify/rollback`
- upgrade schema와 migration
- 공통 backup retention
- MCP version pin
- release payload 정적 개인정보·절대경로 검사

### P2 — 확장성

- macOS/Linux/WSL CI matrix
- Codex/Gemini/VS Code/Cursor adapter
- capability loss 표시
- native Windows PowerShell adapter
- junction·ACL·CRLF 테스트
- 문서 catalog와 cold-machine onboarding UX

---

## 6. 범위와 비범위 제안

### 1차 릴리스 범위

- 결정론적 desired-state installer
- macOS/Linux/WSL 또는 Git Bash
- Bash engine
- Claude Code 공식 adapter
- project/user scope
- dependency doctor
- plan/apply/verify/rollback/uninstall
- package/runtime 감지와 정확한 설치 안내
- network 0 기본 정책
- 개인 설정과 공통 payload 분리

### 1차 릴리스 비범위

- native Windows 완전 지원
- 모든 IDE의 네이티브 plugin
- 로그인·계정 연결·시크릿 발급
- 모든 런타임의 무조건 자동 설치
- 개인 `~/.claude`를 무검사 release payload로 승격
- Claude/Codex/Gemini 기능의 가짜 1:1 동등성
- 프로젝트 앱의 빌드·배포 결정

---

## 7. 구현 순서 제안

영환님 승인 후 다음 순서로 진행한다.

1. **설치 계약 확정**
   - scope
   - config root
   - profile precedence
   - network consent
   - 지원 OS/셸
2. **P0 안전성**
   - path/symlink boundary
   - hook identity schema v2
   - user/project ownership
3. **transaction 통합**
   - 하위 installer operation plan
   - unified manifest/journal
   - rollback/uninstall 범위 확장
4. **의존성·상태 가시화**
   - doctor
   - hook 활성화 상태
   - runtime/package manager resolver
   - environment lock
5. **중립 profile 구조**
   - 개인 설정·문서·plugin profile 분리
   - MCP pin
   - capability loss 표시
6. **실제 lifecycle 검증**
   - macOS/Linux/WSL
   - clean HOME
   - 멱등·업그레이드·rollback·uninstall
7. **추가 adapter**
   - Codex/Gemini/editor
   - native Windows는 별도 단계

---

## 8. 완료 수용 기준

### 설치 범위

- project-only 설치가 글로벌·Codex 경로를 쓰지 않는다.
- `--full`도 명시 동의 없이는 network/global package install을 수행하지 않는다.
- 모든 설치 산출물이 manifest/journal에 기록된다.
- uninstall 후 installer 소유 artifact가 0개다.

### 경로·보안

- clean `HOME` 및 임시 `CLAUDE_CONFIG_DIR`에서 예상 밖 `$HOME/.claude` 쓰기 0
- broken/ancestor symlink 경로 이탈 0
- 공백·유니코드·대괄호·glob·read-only 경로 통과
- release payload의 사용자명·개인 절대경로·model/provider pin 0건
- hook command·args·env·timeout identity가 정확히 보존된다.

### 재현성·lifecycle

- 동일 설치 2회차 변경 0
- 사용자 수정본 보존 후 N-1 → N upgrade 성공
- source fragment 제거 후 stale 소유 파일만 정리
- 모든 phase 강제 실패·SIGINT 후 byte/mode/link 동등 복구
- 하위 installer 산출물도 rollback/uninstall 대상에 포함
- 동일 release/profile/lock에서 동일 산출물 생성

### 의존성·지원 환경

- jq/node/python3 조합별 상태 표시
- npm/pnpm/yarn/bun 및 runtime manager 탐지 결과 표시
- hook 활성·비활성·미검증 사유 표시
- macOS Bash 3.2
- Ubuntu Bash 5
- WSL/Git Bash
- 지원하지 않는 기능은 조용히 생략하지 않고 `WARN` 또는 `BLOCKED`

### 테스트 증거

Buzz 답변에는 macOS와 Linux 테스트 수치가 보고되었으나, 해당 수치는 현재 HEAD에서 Jarvis가 독립 재실행한 결과가 아니다. 최종 완료 판단에는 현재 HEAD 기준 전체 suite와 신규 matrix를 다시 실행한 실제 출력이 필요하다.

---

## 9. 영환님 확인이 필요한 결정

개발 시작 전에 다음 네 가지를 확인한다.

1. **1차 지원 OS:** macOS + Linux + WSL/Git Bash로 제한할지
2. **기본 설치 범위:** `project-only`를 기본값으로 채택할지
3. **네트워크 정책:** 기본 0, 도구 설치는 명시 동의로 제한할지
4. **1차 adapter:** Claude Code만 공식 지원하고 Codex/Gemini/editor는 선택 profile로 둘지

이 네 가지가 승인되면 P0 계약 문서를 기준으로 구현 계획을 확정하고, 전용 worktree에서 개발·테스트를 시작한다.

---

## 10. 현재 상태

- Buzz 설치 내용 검토 안건: 게시 및 검증 완료
- 확인된 답변: Fable 2건, Honey 1건
- 코드 수정: 없음
- 커밋: 없음
- 원격 반영: 없음
- 기존 미추적 파일: `.aos-project.json`, `CLAUDE.md`
- 본 문서: 영환님 확인용으로 새로 작성

**다음 단계:** 영환님이 본 문서의 범위·P0 계약을 확인한 뒤, 승인된 범위만 개발 계획으로 전환한다.
