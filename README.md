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
| `--uninstall` | installer가 소유한 파일과 settings hooks/permissions만 제거 (아래 *Uninstall Policy*) |
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
└── docs/                       # *.md → ~/.claude/docs/claude-code-setup/ (글로벌, 관리 파일)
    ├── Claude code system setup/       # 하위 install.sh = 이 번들의 정본(SSOT) → system-setup/
    └── codex-advisor-worker-bundle/    # 하위 install.sh = 이 번들의 정본(SSOT)
```

`docs/` 하위 두 번들은 각자의 `install.sh`가 정본(SSOT)입니다. 루트 `install.sh`는 이들을 재구현하지 않고 **위임 호출**합니다. 루트는 `settings.json`의 hooks/permissions만 병합하고 `model` 필드는 주입하지 않습니다 — 모델 ID는 사용자가 직접 설정해야 하므로 시스템이 강제하지 않습니다.

## Feature Matrix — docs 문서 → 설치 주체

| docs 기능 | 설치 주체 |
|-----------|----------|
| 글로벌 rules/skills, 프로젝트 skills·agents·commands | 루트 직접 |
| docs 가이드 문서 (`docs/**/*.md`, install.sh 제외) | 루트 직접 → `~/.claude/docs/claude-code-setup/` (글로벌, 관리 파일) |
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

1. **관리 파일 · 관리 디렉토리** (rules, skills, agents, commands, Safety Protocol 등)

   디렉토리도 **파일 단위**로 동기화합니다. 디렉토리를 `rm -rf`로 통째 교체하지 않습니다.
   소유권은 `~/.claude/.manifest` / `<project>/.manifest`(TSV: `상대경로<TAB>설치 시점 해시`)로 판정합니다.

   | 상태 | 판정 | 동작 |
   |------|------|------|
   | installer 소유·미변경 | 기록 해시 == 현재 해시 | 갱신 / stale이면 삭제 |
   | 이주(adopt) | manifest에 없지만 내용이 소스와 동일 | 소유권 인수 후 UNCHANGED |
   | 사용자 추가 | manifest에 없고 내용도 다름 | **보존** |
   | 사용자 수정 | 기록 해시 ≠ 현재 해시 | **보존** |

   - **stale 정리**: 소스에서 사라진 파일은 *installer 소유·미변경*일 때만 제거합니다.
   - **백업**: 관리 *파일* 갱신 시에만 `.bak`(`.bak.1`, ...) — bounded retention(기본 3개).
     관리 *디렉토리*는 디렉토리 단위 백업을 만들지 않습니다. 덮어쓰는 대상이
     "installer가 쓴 뒤 아무도 안 건드린 파일"뿐이라 백업할 사용자 내용이 없기 때문입니다.
   - **상태**: UNCHANGED / BACKED_UP / INSTALLED / SKIPPED

2. **사용자 소유 파일** (CLAUDE.md, skill-rules.json, .mcp.json.example, 메모리 시드): 존재하면 절대 건드리지 않음(SKIPPED) — skip-if-exists.

3. **병합 파일** (`.claude/settings.json`): 덮어쓰지 않고 병합
   - hooks: 이벤트 단위 append (동일 command 존재 시 미추가, 멱등)
   - permissions.allow: 합집합
   - 기타 키: 기존 값 우선
   - model 필드: 절대 주입 안함 (settings.json에서 사용자가 명시적으로 설정)
   - 소유권은 `settings.json` 옆의 `.settings-manifest`에 `(event, matcher, command)` identity로 기록됩니다.

요약에 `INSTALLED · UNCHANGED · BACKED_UP · SKIPPED` 카운트를 출력합니다.

### 업스트림에서 제거된 자산 (stale sweep)

관리 디렉토리 안의 stale 정리만으로는 **디렉토리째 사라진 스킬**이나 **삭제된 rules/agents 파일**을
잡지 못합니다(그 디렉토리가 애초에 열거되지 않으므로). 그래서 설치 마지막에 manifest를 루트 단위로
훑어, **그 자산을 만든 소스가 더 이상 없는** 항목을 정리합니다.

- 삭제 조건은 다른 곳과 동일합니다 — manifest 기록 해시 == 현재 해시(installer 소유·미변경).
  사용자가 수정한 파일은 보존하고 경고만 남깁니다.
- 판정 기준은 "이번 실행에서 건드렸는가"가 **아니라 소스 존재 여부**입니다. 전자로 하면
  `--with-examples` 없이 재실행했을 때 이전에 설치한 examples 자산이 지워집니다 — 사용자가 이번에
  요청하지 않았을 뿐 업스트림에는 그대로 있는데도요.
- 관리 접두(`rules/`, `skills/`, `docs/claude-code-setup/`, `.claude/{skills,agents,commands,hooks,settings-fragments}/`,
  `docs/templates/pm2/`) 밖의 항목은 아예 대상이 아닙니다 — 위임 설치기와 사용자 파일을 보호합니다.

### 레거시 `.claude/MODELS.md`

이전 버전의 system-setup 설치기는 `.claude/MODELS.md`를 설치했습니다. 지금은 만들지 않으며,
**이미 깔린 사본은 내용 해시가 과거 배포본과 일치할 때만 자동 삭제**합니다(= 사용자가 손대지 않은
installer 소유물). 한 글자라도 다르면 사용자 편집으로 보고 삭제하지 않고, 설치 후 체크리스트에
`[LEGACY-MODELS-KEPT]` 안내와 함께 수동 삭제를 요청합니다.

> 자동 삭제하지 않는 이유: 그 파일은 낡은 모델 ID·CLI 버전을 "SSOT"라고 주장하므로 방치하면
> 해롭지만, 사용자가 자기 내용을 덧붙였을 수 있어 무조건 지우면 데이터 손실입니다.
> 보존된 파일을 가리키는 문장이 `CLAUDE.md`(사용자 소유라 덮어쓰지 않음)에 남아 있을 수 있으니
> 함께 정리하세요.

## Uninstall Policy (`--uninstall`)

설치 정책의 정확한 역연산입니다. **사용자 것은 절대 지우지 않습니다.**

- **파일**: manifest 기록 해시 == 현재 해시일 때만 제거. 사용자가 수정했거나 manifest에
  없는 파일(사용자 추가, `CLAUDE.md` 등 skip-if-exists 자산)은 그대로 둡니다.
- **settings.json**: `.settings-manifest`가 기록한 hooks/permissions identity만 제거합니다.
  사용자 훅·사용자 `allow`·알 수 없는 최상위 키는 불변입니다.
- **디렉토리**: 제거 결과로 비게 된 것만 정리합니다.
- **백업**: `*.bak`은 남깁니다 — 복구 수단을 제거가 지우면 안 됩니다.
- **위임 설치기**(system-setup / advisor 번들) 산출물은 이 manifest 밖이므로 제거 대상이 아닙니다.
- 재실행은 멱등입니다.

```bash
./install.sh --uninstall                      # 글로벌만
./install.sh --uninstall --project ./my-app   # 글로벌 + 프로젝트
./install.sh --uninstall --dry-run            # 미리보기
```

## Failure Rollback (원자성)

설치 도중 실패하거나 `Ctrl-C`(INT)/TERM이 들어오면 **이번 실행이 바꾼 모든 파일·settings·manifest를
실행 전 상태로 되돌리고** 부분 설치를 남기지 않습니다.

- 어떤 경로를 이번 실행에서 처음 건드리기 직전에 그 시점 상태(내용 사본 또는 "없었음")를
  저널에 기록하고, 실패 시 역순으로 복원합니다.
- 트리거는 EXIT 트랩 + 완료 센티널입니다. ERR 트랩만으로는 위임 단계의 `exit 1`을 잡지 못하고,
  시그널 트랩만으로는 `set -e` 실패를 잡지 못하기 때문입니다.
- **범위 밖**: 위임 설치기(system-setup / advisor 번들)가 쓴 파일은 저널에 없으므로 롤백되지
  않습니다. 두 번들은 각자의 백업 정책을 따릅니다.

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
