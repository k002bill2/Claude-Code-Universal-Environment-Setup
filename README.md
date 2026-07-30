# Claude Code Universal Environment Setup

**`./install.sh --full --project <dir>` 한 번으로 — `docs/` 폴더의 모든 기능까지 — Claude Code 환경 전체를 설치합니다.**

8개 프로젝트 운영 경험에서 추출한 범용(Universal) 설정 + `docs/` 하위 두 번들(system-setup, codex-advisor-worker)을 단일 오케스트레이터로 통합했습니다.

## Quick Start

```bash
git clone https://github.com/k002bill2/Claude-Code-Universal-Environment-Setup.git
cd Claude-Code-Universal-Environment-Setup

./install.sh --full --project /path/to/project   # docs 폴더 기능 포함 전체 설치
./install.sh --project /path/to/project          # 코어만 (글로벌 + 프로젝트 + system-setup 위임)
./install.sh --global-only                       # ~/.claude/ 글로벌 설정만
./install.sh --dry-run --full --project /path    # 실제 쓰기 없이 계획만 출력
```

사전 요구: `jq` 또는 `node` 필수(settings.json 병합 엔진). `--with-advisor` 사용 시 `python3` 또는 `jq`.

대화형 프롬프트는 없습니다. 유일한 예외: 플래그 없이 실행했고 stdin이 TTY일 때만 프로젝트 경로를 질문합니다(비TTY면 프로젝트 단계를 스킵하고 안내만 출력).

## Flags

| 플래그 | 의미 |
|--------|------|
| `--project PATH` | 프로젝트 자산(.claude/ 스킬·에이전트·커맨드·settings 병합 등)을 PATH에 설치 |
| `--global-only` | 글로벌 단계(~/.claude/ rules·skills)만 실행 |
| `--dry-run` | 모든 쓰기·하위 설치기 위임을 `[DRY RUN] Would ...`로만 출력, 실제 실행 없음 |
| `--full` | `--with-advisor` + `--with-examples` + `--with-pm2` + verify-hooks 조각 파일 설치 (settings 병합은 `--with-verify-hooks` / `--with-pm2` 를 **명시**했을 때만) |
| `--with-advisor` | codex-advisor-worker-bundle 설치기 위임 (조언자–작업자–검증 체계) |
| `--with-examples` | `examples/` 스킬·에이전트를 프로젝트 `.claude/`에 추가 설치 |
| `--with-pm2` | PM2 템플릿을 `<project>/docs/templates/pm2/`에 복사 + pm2-hooks 조각을 `settings.json`에 병합 |
| `--with-verify-hooks` | verify-hooks 조각을 `.claude/settings.json`에 실제 병합 |
| `-h` / `--help` | 사용법 출력 |

## Directory Structure

```
.
├── install.sh                  # 오케스트레이터 (하위 설치기에 위임)
├── lib/
│   └── merge-settings.sh       # settings.json 공용 병합 엔진 (jq 우선, node 폴백)
├── global/
│   ├── rules/                  # → ~/.claude/rules/ (관리 파일)
│   └── skills/                 # → ~/.claude/skills/ (19개, 관리 파일)
├── project/
│   ├── skills/                 # → .claude/skills/
│   ├── agents/                 # → .claude/agents/ (7종)
│   ├── commands/               # → .claude/commands/
│   ├── hooks/                  # → .claude/hooks/*.sh (실행형 advisory 훅 4종, chmod +x)
│   ├── settings-fragments/     # guardrails/cli-orchestration(항상) + verification-hooks/pm2-hooks(옵트인)
│   ├── skill-rules.json        # → .claude/skill-rules.json (skip-if-exists)
│   └── mcp.json.example        # → <project>/.mcp.json.example (skip-if-exists)
├── examples/                   # --with-examples 옵트인 스킬·에이전트
├── templates/pm2/              # --with-pm2 비파괴 템플릿
├── CLAUDE.md.template          # → CLAUDE.md (skip-if-exists)
└── docs/
    ├── Claude code system setup/       # 하위 install.sh = 이 번들의 정본(SSOT)
    └── codex-advisor-worker-bundle/    # 하위 install.sh = 이 번들의 정본(SSOT)
```

`docs/` 하위 두 번들은 각자의 `install.sh`가 정본(SSOT)입니다. 루트 `install.sh`는 이들을 재구현하지 않고 **위임 호출**합니다. 실행 순서가 충돌 해소 수단입니다: 루트가 `.claude/settings.json`을 먼저 생성/병합하므로, 이후 위임되는 system-setup은 settings.json이 이미 존재해 `model` 키 주입이 구조적으로 발생하지 않습니다.

## Feature Matrix — docs 문서 → 설치 주체

| docs 기능 | 설치 주체 |
|-----------|----------|
| 글로벌 rules/skills, 프로젝트 skills·agents·commands | 루트 직접 |
| settings.json 병합 (guardrails, cli-orchestration) | 루트 직접 (`lib/merge-settings.sh`) |
| Parallel Agents Safety Protocol v3.1.0 | 루트 직접 → `<project>/docs/` (관리 파일) |
| CLAUDE.md, skill-rules.json, .mcp.json.example, dev/ 골격, 메모리 시드 | 루트 직접 (skip-if-exists) |
| 시스템 셋업 가이드 본체 (Dev Docs, Skills 자동 활성화 등) | system-setup `install.sh` 위임 |
| 조언자–작업자–검증(Codex) 체계 | advisor-worker `install.sh` 위임 (`--with-advisor`/`--full`) |
| Agent Skills 예시 모음 | `--with-examples` 옵트인 |
| PM2 백엔드 디버깅 | `--with-pm2` 옵트인 (템플릿 복사 + pm2-hooks 병합) |
| verify-hooks settings 병합 | `--with-verify-hooks` 옵트인 |
| codex 플러그인·login, MCP 시크릿, GSD/Gstack, pm2-logrotate | POST-INSTALL 체크리스트 수동 |
| 실행형 훅 4종 (stop 자가검증·build-checker·post-tool-failure·service-health-check) | 루트 직접 → `.claude/hooks/` (파일은 항상, 배선은 옵트인 — 아래 참조) |

## Install Policy (파일 정책 · 멱등성)

세 부류로 나뉩니다:

1. **관리 파일** (rules, skills, agents, commands, Safety Protocol 등): 내용 동일 시 스킵(UNCHANGED), 변경 시 `.bak`(`.bak.1`, ...) 백업 후 갱신(BACKED_UP).
2. **사용자 소유 파일** (CLAUDE.md, skill-rules.json, .mcp.json.example, 메모리 시드): 존재하면 절대 건드리지 않음(SKIPPED) — skip-if-exists.
3. **병합 파일** (`.claude/settings.json`): 덮어쓰지 않고 병합 — hooks는 이벤트 단위 append(동일 command 존재 시 미추가), `permissions.allow`는 합집합, 기타 키는 기존 값 우선. `model` 키는 절대 넣지 않습니다.

요약에 `INSTALLED · UNCHANGED · BACKED_UP · SKIPPED` 카운트를 출력합니다.

**멱등성 계약**: 같은 명령의 2회차 실행은 변경 0건이어야 합니다. 병합 엔진은 신규 생성 시에도 병합 경로와 동일한 직렬화로 정규화해 이 계약을 보장합니다.

## 실행형 훅 4종 (`project/hooks/`)

docs의 TypeScript 개념 스켈레톤을 **실행 가능한 bash**로 재작성한 것들입니다. 파일은 기본 설치에서도 항상 `.claude/hooks/`에 깔리고 `chmod +x` 되지만, **`settings.json` 배선은 옵트인**입니다 — 즉 플래그 없이 설치하면 파일만 존재하고 아무것도 실행되지 않습니다.

| 훅 | 이벤트 | 배선 플래그 | 동작 |
|----|--------|------------|------|
| `stop-self-check.sh` | `Stop` | `--with-verify-hooks` | git 작업트리 변경 파일에서 리스크 패턴(try/async/prisma/throw) 감지 → 자가검증 질문 출력 |
| `build-checker.sh` | `PostToolUse` (`Edit\|Write`) | `--with-verify-hooks` | `.ts/.tsx` 편집 시 로컬 `node_modules/.bin/tsc --noEmit` 실행 → 오류 요약 |
| `post-tool-failure.sh` | `PostToolUseFailure` | `--with-pm2` | 실패 도구·점검 순서 안내 + PM2 비정상 서비스 표시 |
| `service-health-check.sh` | `Stop` | `--with-pm2` | PM2 서비스 중 `status != online` 또는 재시작 5회 초과 감지 (수동 실행도 가능) |

공통 계약: stdin으로 이벤트 JSON 수신, stdout은 advisory 컨텍스트로 주입, **항상 exit 0**(세션 미차단). `jq` 부재 시(PM2 훅은 `pm2` 부재 시에도) 조용한 no-op. 외부 명령은 자체 타임아웃으로 유계 실행하며 `npx` 네트워크 설치는 하지 않습니다.

## Out of Scope (v1) — 사유

- **플러그인 내용물** (codex 플러그인 등): 플러그인 마켓플레이스가 소유하는 영역. 설치 명령만 체크리스트로 안내.
- **네트워크·세션·계정 결합 단계**: `codex login`, MCP `npx` 서버 기동+시크릿 주입, GSD/Gstack 마켓플레이스 설치 — 비대화형 스크립트가 대신할 수 없는 단계이므로 POST-INSTALL 체크리스트로 안내.

## Layering Note — 글로벌 스킬 vs 프로젝트 커맨드

`dev-docs` 등 4종은 글로벌 스킬(`~/.claude/skills/`)과 프로젝트 커맨드(`.claude/commands/`) 양쪽에 존재합니다. 이는 중복이 아니라 층위입니다: 글로벌 = 하네스가 설치되지 않은 프로젝트용 폴백, 프로젝트 커맨드가 설치된 곳에서는 **프로젝트 커맨드가 우선**합니다.

## Why no hooks.json

과거의 `project/hooks.json`은 폐기되었습니다. Claude Code는 **settings.json에 등록된 훅만 실행**하며 `.claude/hooks.json`은 읽지 않습니다. 훅 정의는 `project/settings-fragments/`의 조각 파일로 이식되어 `.claude/settings.json`에 병합됩니다(실행 스크립트 자체는 `project/hooks/*.sh` → `.claude/hooks/`).

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
