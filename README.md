# Claude Code Universal Environment Setup

**`./install.sh --profile minimal --project <dir>` 로 프로젝트만 안전하게 시작하고, 필요할 때 `--profile full` 한 번으로 — `docs/` 폴더의 모든 기능까지 — Claude Code 환경 전체를 설치합니다.**

8개 프로젝트 운영 경험에서 추출한 범용(Universal) 설정 + `docs/` 하위 두 번들(system-setup, codex-advisor-worker)을 단일 오케스트레이터로 통합했습니다.

## Quick Start

```bash
git clone https://github.com/k002bill2/Claude-Code-Universal-Environment-Setup.git
cd Claude-Code-Universal-Environment-Setup

./install.sh --profile minimal --project /path/to/project  # 프로젝트 초기 권장 — ~/.claude 쓰기 0건
./install.sh --profile core --project /path/to/project     # 글로벌 + 프로젝트 + system-setup 위임 (미지정 기본값)
./install.sh --profile full --project /path/to/project     # = --full, docs 폴더 기능 포함 전체 설치
./install.sh --global-only                       # ~/.claude/ 글로벌 설정만
./install.sh --dry-run --full --project /path    # 실제 쓰기 없이 계획만 출력
```

사전 요구: `jq` 또는 `node` 필수(settings.json 병합 엔진). `--with-advisor` 사용 시 `python3` 또는 `jq`.

대화형 프롬프트는 없습니다. 유일한 예외: 플래그 없이 실행했고 stdin이 TTY일 때만 프로젝트 경로를 질문합니다(비TTY면 프로젝트 단계를 스킵하고 안내만 출력).

## Profiles (`--profile minimal|core|full`)

| 프로필 | 설치물 | `~/.claude` 쓰기 |
|--------|--------|------------------|
| `minimal` | guardrails 훅 병합(`.claude/settings.json`), `.claude/commands/verify-app.md`, minimal `CLAUDE.md` 골격(이미 있으면 건드리지 않음), `.claude/.install-profile`. **permissions allow 는 추가하지 않습니다** | **없음** (메모리 시드 포함 0건) |
| `core` | 기존 `--project` 기본 동작: 글로벌 rules·skills·docs·settings + 프로젝트 스킬·에이전트·커맨드·훅·settings + system-setup 위임 | 있음 |
| `full` | `core` + `--with-advisor` `--with-examples` `--with-pm2` + verify-hooks 조각 파일 (= `--full`) | 있음 |

- **기록·재사용:** 설치한 프로필은 `<project>/.claude/.install-profile` (`profile=<name>`)에 남습니다. 다음 실행에서 프로필을 지정하지 않으면 기록을 재사용합니다(비TTY/CI 포함, 요약에 `recorded`). 기록도 없으면 기존 계약대로 `core` 이며 stderr 에 경고 1줄을 냅니다. `--uninstall` 은 기록을 지웁니다.
- **배타 규칙(exit 1, 무변경):** 실효 프로필이 `minimal` 인데 `--with-advisor` / `--with-cross-review` / `--global-only` 를 지정한 경우, `--full` 과 `--profile minimal|core` 를 함께 지정한 경우. `--with-examples` / `--with-pm2` / `--with-verify-hooks` 는 프로젝트 전용이라 minimal 위에 허용됩니다(요약 `minimal+<옵션>`; pm2·verify-hooks 는 훅 파일 설치를 함께 켭니다).
- **minimal 은 python3 필수(fail-closed):** guardrails 훅이 유일한 보호 장치라 python3 가 없으면 어떤 쓰기도 하기 전에 exit 1 합니다. core/full 은 기존처럼 경고 후 병합만 건너뜁니다.
- **프로필 축소는 무삭제:** full→minimal 재실행은 이전에 깐 installer 소유 자산을 지우지도 갱신하지도 않습니다. 요약에 "이전 설치에서 남은 installer 소유 자산 N건" 을 표시합니다. 지우려면 `--uninstall`.
- **이미 하네스가 깔린 머신에서는 core/full 을 프로젝트마다 돌리지 마세요.** 글로벌 단계는 무동작이거나, 리포가 라이브보다 낡았으면 구버전으로 롤백합니다(아래 *Sync From Live*). 새 프로젝트는 `minimal` 로 충분합니다.
- **`git push` 사전 허용 제거(2026-11):** 원격 쓰기는 사람 승인 원칙이라 `cli-orchestration.json` allow 에서 뺐습니다. 재설치 시 설치기가 넣었던 항목만 제거되고, 사용자가 직접 넣은 같은 문자열은 보존됩니다.
- guardrails 는 일부 위험 패턴을 막는 **보조 가드**이며 사람 승인·샌드박스를 대체하지 않습니다.

### 개별 선택 (`--components a,b,c`)

`--components` 단독이면 **정확히 그 목록**(+자동 의존)만 설치합니다. `--profile`/`--full` 과 함께 쓰면 **합집합**입니다.

| 키 | 설치물 | `~/.claude` 쓰기 | 의존 |
|---|---|---|---|
| `global` | rules·skills·agents·docs·skill-overrides·글로벌 스윕 | 예 | — |
| `guardrails` | guardrails.json 병합 | 아니오 | python3 (없으면 exit 1) |
| `permissions` | cli-orchestration.json 병합 | 아니오 | — |
| `claude-md` | core/full 계열이면 기존 템플릿, 그 외는 `templates/CLAUDE.minimal.md` (이미 있으면 건드리지 않음) | 아니오 | — |
| `commands` | check-health.md, verify-app.md | 아니오 | — |
| `commands-auto` | auto.md | 아니오 | — |
| `agents` / `skills` | project/agents, project/skills | 아니오 | — |
| `skill-rules` | skill-rules.json | 아니오 | system-setup (없으면 WARN) |
| `hooks` | .claude/hooks/*.sh 4종 | 아니오 | — |
| `verify-hooks` | 조각 파일 + 병합 | 아니오 | hooks (자동 추가 + INFO) |
| `pm2` | 템플릿 + pm2-hooks 병합 | 아니오 | hooks (자동 추가 + INFO) |
| `system-setup` | 위임 설치기 | 아니오 | settings 선생성 불변식(아래) |
| `extras` | mcp example·Safety 문서·dev/ gitkeep | 아니오 | — |
| `memory-seed` | `~/.claude/projects/<slug>/memory/MEMORY.md` | 예 | — |
| `advisor` | 위임 설치기 | 예 | python3 또는 jq |
| `examples` | examples/ 스킬·에이전트 | 아니오 | — |

- 알 수 없는 키(또는 빈 목록) → exit 1 + 사용 가능한 키 목록. `cross-review` 는 키가 아닙니다 — `--with-cross-review` 전용이며, 글로벌 단계가 없는 구성(`global` 미포함 components 단독)과는 함께 쓸 수 없습니다(exit 1).
- 실효 구성이 minimal 기반(`--profile minimal` 또는 기록된 minimal)인데 `global`/`memory-seed`/`advisor` 를 고르면 exit 1 (minimal 배타 규칙과 같은 경로). `--components` 단독으로 글로벌 쓰기 키를 고르는 것은 허용되며 요약에 `~/.claude 쓰기: 예` 가 표시됩니다.
- **settings 선생성:** `system-setup` 을 고르고 `guardrails`·`permissions` 가 둘 다 없으면 위임 전에 빈 `{}` `.claude/settings.json` 을 만들어 위임 설치기의 신규 템플릿(model 키 주입) 경로를 막습니다. 이미 있으면 건드리지 않습니다.
- 기록: `.claude/.install-profile` 에 `components=a,b,c` (프로필과 함께면 `profile=` 과 두 줄). 재사용 규칙은 프로필과 같습니다 — 무엇이든 명시하면 기록 전체를 대체합니다.
- **`full` ≠ 모든 키:** `--profile full` 은 verify-hooks 를 조각 파일만 깔고(병합 없음), pm2 는 템플릿만 깝니다(pm2-hooks 병합 없음). 키 `verify-hooks`/`pm2` 는 병합까지 합니다.

### 첫 설치 메뉴 (TTY)

다음이 **모두** 참일 때만 메뉴를 띄웁니다: `--project` 지정 ∧ `--profile`/`--components`/`--full` 미지정 ∧ `.install-profile` 기록 없음 ∧ stdin 이 TTY ∧ `CI` 환경변수 미설정 ∧ `--yes`/`--non-interactive`/`--dry-run`/`--uninstall` 아님.

```
1) minimal (기본 — 프로젝트 초기 권장)  2) full  3) 직접 선택  4) core
```

빈 Enter = 1. 3 은 키 목록을 번호로 보여 주고 번호·이름 쉼표 입력을 받습니다(위 규칙으로 검증). 알 수 없는 선택은 1회 재질문 후 exit 1, 60초 타임아웃/EOF 도 exit 1 입니다 — 조용히 core 로 가지 않습니다. 선택 결과는 기록됩니다. `--yes`/`--non-interactive` 는 메뉴를 건너뛰고 위 미지정 규칙(기록 재사용, 없으면 core+경고)을 따릅니다.

### 글로벌 드리프트 사전 점검

글로벌 단계가 실행될 때(core/full/`global` 키) 쓰기 전에 읽기 전용으로 점검합니다.

- rules·skills: 라이브 파일이 저장소 소스와 다르면 목록을 WARN 으로 출력합니다(“저장소 스냅샷이 라이브보다 뒤처졌을 수 있음 — scripts/sync-from-live.sh 로 역동기화 검토”). manifest 가 사용자 수정을 보존하므로 **차단하지 않습니다**.
- advisor 위임(`--with-advisor`/`advisor` 키/full): 라이브 `~/.claude/CLAUDE.md` 의 `codex-advisor-worker-bundle` 마커 블록이 저장소 heredoc 과 다르면 **exit 1** 합니다(위임 설치기가 저널 밖에서 덮어쓰기 때문). `--force-global` 을 붙여야만 진행합니다. 라이브가 없으면(새 머신·번들 미설치) 드리프트 없음입니다.

## Flags

| 플래그 | 의미 |
|--------|------|
| `--profile NAME` | `minimal` / `core` / `full` (위 *Profiles*). 미지정 시 기록 재사용, 없으면 `core` |
| `--project PATH` | 프로젝트 자산(.claude/ 스킬·에이전트·커맨드·settings 병합 등)을 PATH에 설치 |
| `--global-only` | 글로벌 단계(~/.claude/ rules·skills)만 실행 |
| `--dry-run` | 모든 쓰기·하위 설치기 위임을 `[DRY RUN] Would ...`로만 출력, 실제 실행 없음 |
| `--full` | `--profile full` 별칭. `--with-advisor` + `--with-examples` + `--with-pm2` + verify-hooks 조각 파일 설치 (settings 병합은 `--with-verify-hooks` / `--with-pm2` 를 **명시**했을 때만) |
| `--with-advisor` | codex-advisor-worker-bundle 설치기 위임 (조언자–작업자–검증 체계) |
| `--with-examples` | `examples/` 스킬·에이전트를 프로젝트 `.claude/`에 추가 설치 |
| `--with-pm2` | PM2 템플릿을 `<project>/docs/templates/pm2/`에 복사 + pm2-hooks 조각을 `settings.json`에 병합 |
| `--with-verify-hooks` | verify-hooks 조각을 `.claude/settings.json`에 실제 병합 |
| `--with-cross-review` | **글로벌** Claude↔Codex 교차리뷰 번들을 `~/.claude/hooks/cross-review/`에 설치 + opt-in Stop 가드를 `~/.claude/settings.json`에 병합. **기본 설치와 `--full` 은 파일조차 설치하지 않습니다** (아래 *교차리뷰 게이트*) |
| `--components LIST` | 쉼표 키 목록 — 단독이면 정확히 그 목록, `--profile`/`--full` 과 함께면 합집합 (위 *개별 선택*) |
| `--yes` / `--non-interactive` | 첫 설치 메뉴를 띄우지 않음(기록 재사용, 없으면 core+경고) |
| `--force-global` | advisor 블록 드리프트가 있어도 진행(라이브 블록이 덮어써짐) |
| `--uninstall` | installer가 소유한 파일과 settings hooks/permissions만 제거 (아래 *Uninstall Policy*) |
| `-h` / `--help` | 사용법 출력 |

## Orca / git worktree 운영

git worktree·Orca 레인은 **git 추적 파일만** 가집니다. Orca 는 저장소 setup 스크립트(`npm install`/`pnpm install` 등)만 실행하며 미추적 `.claude/` 를 복사하지 않습니다(2026-11-08 실측: 메인 체크아웃의 미추적 `.claude/<파일>`·루트 파일이 `orca worktree create --setup inherit` 로 만든 새 worktree 에 생기지 않음). 그래서 레인에서도 같은 구성을 쓰려면 설치 산출물을 커밋해야 합니다.

- **커밋 권장:** `.claude/settings.json`, `CLAUDE.md`, `.claude/commands/`, `.claude/.install-profile`, `.manifest`, `.claude/.settings-manifest`
- **커밋하지 않기 권장:** `*.bak*`, `.manifest-backups/`, `.settings-backups/` — 설치기는 `.gitignore` 를 수정하지 않습니다(기존 원칙). 필요하면 직접 추가하세요.
- **설치·업그레이드는 메인 체크아웃에서만** 실행하고 커밋하세요. 레인(worktree)에서는 `install.sh` 를 실행하지 않습니다 — 레인은 커밋된 결과를 받아 쓰기만 합니다.

## Directory Structure

```
.
├── install.sh                  # 오케스트레이터 (하위 설치기에 위임)
├── lib/
│   └── merge-settings.sh       # settings.json 공용 병합 엔진 (jq 우선, node 폴백)
├── global/
│   ├── rules/                  # → ~/.claude/rules/ (관리 파일)
│   └── skills/                 # → ~/.claude/skills/ (7개, 관리 파일)
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
| codex 플러그인·login, MCP 시크릿, pm2-logrotate | POST-INSTALL 체크리스트 수동 |
| 실행형 훅 4종 (stop 자가검증·build-checker·post-tool-failure·service-health-check) | 루트 직접 → `.claude/hooks/` (파일은 항상, 배선은 옵트인 — 아래 참조) |

## Sync From Live (설치 전 역동기화)

이 리포는 라이브 하네스(`~/.claude`)의 **설치 가능한 스냅샷**이다. 라이브가 앞서
진화한 상태에서 `install.sh` 를 재실행하면 라이브가 구버전으로 롤백된다.
설치(특히 재설치) 전에 반드시 스냅샷을 라이브 기준으로 갱신하라:

```bash
scripts/sync-from-live.sh              # rules / skills / skillOverrides 동기화 + heredoc 블록 3종 드리프트 보고
scripts/sync-from-live.sh --write-blocks   # heredoc 블록 3종까지 갱신 (재설치 전 권장)
git diff                               # 검토 후 커밋 → install.sh
```

heredoc 블록 3종(스플라이스는 구조를 깨뜨릴 수 있어 기본은 **보고만** 한다):

| 블록 | 라이브 원본 | 개별 플래그 |
|---|---|---|
| CLAUDE.md 마커 블록 | `~/.claude/CLAUDE.md` | `--write-claude-block` |
| 훅 JS (`ADVCTXJS`) | `~/.claude/hooks/advisor-context-budget.js` | `--write-hook-blocks` |
| statusline 브리지 (`CTXBRIDGE`) | 활성 statusline 의 `ctx-budget` 마커 블록 | `--write-hook-blocks` |

`--write-blocks` 는 위 두 플래그를 모두 켠다. **재설치 전에는 이쪽을 쓰라** —
`--write-claude-block` 만 쓰면 훅·브리지가 낡은 채 남아 `install.sh` 가 라이브 모니터를
구버전으로 롤백시킨다(2026-08-21 실제 발생: 훅이 두 세대 앞선 상태로 방치돼 있었다).

라이브에서 삭제된 스킬·심볼릭링크 스킬은 자동 처리하지 않고 경고만 출력한다
(파괴적 결정은 사람이 한다). 페이로드에서 스킬을 제거하면 이후 업그레이드에서
manifest 소유분에 한해 stale sweep 으로 정리된다 (아래 '업스트림에서 제거된 자산').

**개인 항목 제외.** 설치기 범위 밖인 개인 설정(개인 pstack 모델 rule, 개인 브라우저 정책
override 키 등)은 `scripts/sync-exclude.txt` 에 `rule:<파일명>` / `override:<키>`
(`skill:<이름>`, `agent:<파일명>` 도 가능) 형식으로 적어 두며, 동기화가 `SKIP(개인 제외)` 로 건너뛴다.
나만의 제외 항목은 커밋하지 말고 `~/.claude/.sync-exclude.local` 에 같은 형식으로 적으면 합쳐진다.
제외를 끄고 전부 동기화하려면 `--no-exclude`.

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
     retention은 **installer가 만든 백업만** 지웁니다 — 아래 *백업 소유 색인* 참조.
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

### 서드파티 스킬 팩 skillOverrides 은퇴 (2026-10)

GSD·Gstack 스킬 팩은 더 이상 지원·권장하지 않으며, `skill-overrides.json` 에서 해당 키를 뺐습니다.
`skillOverrides` 는 기존 값이 이기므로(병합하지 않음) **이미 설치된 settings.json 의 키는 그대로 남고**,
설치기는 사용자 소유 스킬을 지우지 않습니다. 남은 `~/.claude/skills/gsd-*`·`gstack*` 은 직접 제거하세요 —
새로 설치한 환경에서는 override 가 없어 그 스킬들이 자동 호출 대상이 됩니다.
이 키들은 라이브 `settings.json` 에서도 이미 제거되었습니다. 다시 생기면 `scripts/sync-from-live.sh` 가 저장소로 되살리므로, 라이브에서 지우거나 `~/.claude/.sync-exclude.local` 에 `override:<키>` 로 제외하세요.

### 레거시 `.claude/MODELS.md`

이전 버전의 system-setup 설치기는 `.claude/MODELS.md`를 설치했습니다. 지금은 만들지 않으며,
**이미 깔린 사본은 내용 해시가 과거 배포본과 일치할 때만 자동 삭제**합니다(= 사용자가 손대지 않은
installer 소유물). 한 글자라도 다르면 사용자 편집으로 보고 삭제하지 않고, 설치 후 체크리스트에
`[LEGACY-MODELS-KEPT]` 안내와 함께 수동 삭제를 요청합니다.

> 자동 삭제하지 않는 이유: 그 파일은 낡은 모델 ID·CLI 버전을 "SSOT"라고 주장하므로 방치하면
> 해롭지만, 사용자가 자기 내용을 덧붙였을 수 있어 무조건 지우면 데이터 손실입니다.
> 보존된 파일을 가리키는 문장이 `CLAUDE.md`(사용자 소유라 덮어쓰지 않음)에 남아 있을 수 있으니
> 함께 정리하세요.

## 백업 소유 색인 (`.manifest-backups` / `.settings-backups`)

installer가 만든 백업만 정리하기 위해 **소유 색인 2종**을 남깁니다.
이름(`<파일>.bak.N`)만 보고 지우면, 사용자가 같은 이름으로 만들어 둔 파일까지
지워집니다. 그래서 우리가 만든 백업의 **경로와 그 시점 내용 해시**를 기록하고,
지울 때 해시가 여전히 일치하는 것만 지웁니다.

| 색인 | 위치 | 대상 |
|------|------|------|
| `.manifest-backups` | `~/.claude/` · `<project>/` (각 `.manifest` 옆) | 관리 파일의 `.bak*` |
| `.settings-backups` | `~/.claude/` · `<project>/.claude/` (각 `settings.json` 옆) | `settings.json`의 `.bak*` |

- **형식**: TSV 한 줄 = `백업 절대경로<TAB>기록 시점 해시`
- **삭제 조건**: 색인에 있고 **현재 내용 해시가 기록과 일치**할 때만 정리 대상입니다.
  경로가 재사용되었으면(내용이 다르면) 사용자 파일로 보고 건드리지 않습니다.
- **fail-closed**: 색인을 읽거나 만들 수 없으면 **아무것도 지우지 않습니다**.
  "전부 우리 것"으로 되돌아가는 폴백은 두지 않습니다.
- **제거 시**: `*.bak`과 마찬가지로 `--uninstall` 이후에도 **남습니다**(복구 수단의
  근거를 제거가 지우지 않기 위해서). 완전히 비우려면 백업과 함께 직접 삭제하세요:

  ```bash
  rm -f ~/.claude/.manifest-backups ~/.claude/.settings-backups
  rm -f <project>/.manifest-backups <project>/.claude/.settings-backups
  ```

## Uninstall Policy (`--uninstall`)

설치 정책의 정확한 역연산입니다. **사용자 것은 절대 지우지 않습니다.**

- **파일**: manifest 기록 해시 == 현재 해시일 때만 제거. 사용자가 수정했거나 manifest에
  없는 파일(사용자 추가, `CLAUDE.md` 등 skip-if-exists 자산)은 그대로 둡니다.
- **settings.json**: `.settings-manifest`가 기록한 hooks/permissions identity만 제거합니다.
  사용자 훅·사용자 `allow`·알 수 없는 최상위 키는 불변입니다.
  설치기가 새로 만든 settings.json 이라도 파일 자체는 지우지 않습니다 — 소유 항목을 걷어 낸 뒤
  `{"hooks": {}}` 같은 빈 껍데기가 남을 수 있으며, 동작에는 영향이 없습니다(필요하면 직접 삭제).
  `system-setup` 위임분이 병합한 훅(PreCompact·UserPromptSubmit)은 위임 산출물이라 남습니다.
- **디렉토리**: 제거 결과로 비게 된 것만 정리합니다.
- **백업**: `*.bak`과 백업 소유 색인(`.manifest-backups` / `.settings-backups`)은
  남깁니다 — 복구 수단과 그 소유 근거를 제거가 지우면 안 됩니다.
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

## 교차리뷰 게이트 (`--with-cross-review`, 글로벌 opt-in)

작성한 agent 가 "완료" 를 선언하기 전에 **반대편 provider** 가 같은 worktree 를 read-only 로
검토하게 하는 번들입니다. 계약 정본은
`docs/plans/2026-09-09-global-in-session-cross-review.md`.

| 설치물 | 위치 |
|--------|------|
| 실행 스크립트 6종 | `~/.claude/hooks/cross-review/` |
| settings 조각 | `~/.claude/settings-fragments/cross-review.json` |
| Stop 가드 배선 | `~/.claude/settings.json` 의 `hooks.Stop` (identity 1개) |
| 리뷰 상태 | `~/.claude/state/cross-review/<sha256(realpath)>/` (mode 700) |

- **리뷰는 author 세션이 동기로 부릅니다.** Stop 훅은 리뷰를 실행하지 않습니다 — 미검토
  diff 로 종료했다는 사실만 상태에 기록하고 **항상 exit 0** 입니다(세션 미차단).
- **대상 저장소를 오염시키지 않습니다.** 상태·로그는 전부 `~/.claude/state/` 아래에 있고,
  프로젝트의 `.gitignore` 를 편집하지 않습니다.
- **기본 설치·`--full` 은 배선도 파일 설치도 하지 않습니다.** 다른 옵트인(verify-hooks)과
  달리 조각 *파일*조차 깔지 않습니다 — Stop 훅과 provider 호출 경로를 여는 번들이라
  "파일이 있으니 켜진 줄 알았다" 가 생기지 않게 합니다.
- **기존 Stop 훅과 공존합니다.** 조각 병합은 identity 단위 누적이라 사용자가 직접 쓴 Stop
  훅이나 `stop-self-check` 가 그대로 남습니다.
- **한 번 켜면 점착(sticky)입니다.** `--with-cross-review` 없이 재설치해도 이미 설치된
  번들과 병합된 Stop 엔트리는 남습니다. **해제는 `--uninstall` 뿐입니다** — 플래그를 빼는
  것은 해제가 아닙니다.

**위협 모델 (중요):** 이것은 **협력적 워크플로 게이트이지 적대적 보안 경계가 아닙니다.**
Stop 가드는 항상 exit 0 이라 리뷰를 한 번도 부르지 않고 끝낼 수 있고(상태에 기록만 남습니다),
reviewer 는 diff 내용에 유도될 수 있는 LLM 이며, 프롬프트 구분자 nonce 는 인젝션의 문턱을 올릴 뿐
닫지 못합니다. 이 게이트가 막는 것은 **실수와 성급한 완료 선언**이지, 게이트를 적극적으로
속이려는 행위자가 아닙니다. 자세한 내용은 계획 문서 §11.

**MCP 격리 (양쪽 reviewer 모두).** 두 provider 다 reviewer 실행 시 MCP 서버를 하나도
로드하지 않습니다 — 수단만 다릅니다.

| reviewer | 플래그 | 효과 |
|---|---|---|
| Codex | `--ignore-user-config` | `~/.codex/config.toml` 자체를 읽지 않음 → 거기 정의된 MCP 서버 전부 미로드. 부작용: model/profile 설정도 빠져 **CLI 기본 모델**로 동작 |
| Claude | `--strict-mcp-config` | `--mcp-config` 로 준 것만 사용. **아무것도 주지 않으므로 0개** |

두 플래그 모두 각 CLI 의 `--help` 로 실측 확인했습니다(codex-cli 0.153.4). 이 격리는
**reviewer 호출에만** 적용되며, author 래퍼(`codex-with-review.sh`)는 사용자의 평소 설정으로
동작합니다.

**보존.** 동결 diff·프롬프트(소스 전문)와 provider stdout 원문 봉투는 성공·차단·타임아웃 어느
결말에서도 삭제됩니다. reviewer 결과는 256KiB 상한을 넘으면 저장하지 않고 차단합니다.
삭제 경로는 관리 루트 안이고 심볼릭 링크가 아닐 때만 동작합니다(링크 너머는 건드리지 않음).

> **현재 상태: rollout HOLD.** 이 번들은 fake provider fixture 로만 검증됐습니다. 실제
> `codex exec` / `claude -p` 를 호출하는 live smoke 는 **PENDING** 입니다.

## Out of Scope (v1) — 사유

- **플러그인 내용물** (codex 플러그인 등): 플러그인 마켓플레이스가 소유하는 영역. 설치 명령만 체크리스트로 안내.
- **네트워크·세션·계정 결합 단계**: `codex login`, MCP `npx` 서버 기동+시크릿 주입 — 비대화형 스크립트가 대신할 수 없는 단계이므로 POST-INSTALL 체크리스트로 안내.

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
