# QA-REPORT — 설치기 최소 Claude Code 버전 경고

- 대상: `k002bill2/cc-min-version` (`6b885fb` + `c73ef35`), 기준 `6fa38ba`
- 일자: 2026-11-22 · 환경: macOS, `/bin/bash` 3.2.57 (PATH 의 `bash` 도 `/bin/bash`)
- 방식: 테스트 파일과 독립된 재현 스크립트(`qa/repro.sh` — 실행 시 `/tmp` 사본), HOME·프로젝트 모두 `mktemp -d` 샌드박스, PATH 앞 가짜 `claude`, `tests/helpers.sh` 의 네트워크 shim 사용
- 코드·테스트 수정: 없음

## 판정: **PASS** (Low 2건·Info 2건은 비차단)

계약 1~5 모두 실행 근거로 확인. 모든 사례 exit 0, 산술/unbound 오류 0건, 버전 미달 시 산출물 바이트 동일.

## 대조표 (fake `claude --version` 출력 → 기대/실제)

`--components commands` 기준. rc=exit 코드, 경고=「최소 2.1.293」 줄 수, 파싱실패=「버전을 읽지 못」 줄 수.

| 사례 | 출력 | 기대 | 실제 | 결과 |
|---|---|---|---|---|
| t292 | `2.1.292 (Claude Code)` | 경고, rc0 | rc0 경고1 | OK |
| t293 | `2.1.293 (Claude Code)` | 경고 없음 | rc0 경고0 | OK |
| t1000 | `10.0.0 (Claude Code)` | 경고 없음 | rc0 경고0 | OK |
| t2129 | `2.1.29 (Claude Code)` | 경고(숫자 비교) | rc0 경고1 | OK |
| tv292 | `v2.1.292` | 경고 | rc0 경고1 | OK |
| t000 | `0.0.0` | 경고 | rc0 경고1 | OK |
| tempty | (빈 출력) | 파싱실패 WARN | rc0 파싱실패1 | OK |
| tmulti | 1줄 `Claude Code CLI` / 2줄 `build 2.1.300 …` | 경고 없음 | rc0 경고0 | OK |
| tmulti2 | 1줄 버전 없음 / 2줄 `version 2.1.100` | 경고 | rc0 경고1 | OK |
| t4f | `2.1.293.1` | 경고 없음 | rc0 경고0 | OK |
| t4flow | `2.1.292.9` | 경고 | rc0 경고1 | OK |
| t0lead | `2.01.300` | 경고 없음(01=1, 300>293) | rc0 경고0 | OK |
| t08 | `2.1.08` | 경고(8진 오류 없어야 함) | rc0 경고1, 오류0 | OK |
| tbig | `99999999999999999999.0.0` | 오류 없이 진행 | rc0 경고0, 오류0 | OK |
| tdate | `built 2026.11.22 version 2.1.292` | 경고 | rc0 **경고0** | L-1 참조 |
| texit1 | `2.1.292` 출력 후 exit 1 | 경고, 설치 계속 | rc0 경고1 | OK |
| texit1n | 출력 없이 exit 1 | 파싱실패 WARN | rc0 파싱실패1 | OK |
| tstderr | stderr 로만 `2.1.292` | 파싱실패 WARN(stderr 무시) | rc0 파싱실패1 | OK (I-1) |
| thang | `sleep 8; echo 2.1.292` | — | rc0, 8초 지연 | L-2 참조 |

`/bin/bash` 3.2 로 명시 재실행(8개 버전 + 빈 출력): 위 결과와 동일, 오류 0.

## 흐름별 점검

| 흐름 | 결과 |
|---|---|
| `--profile minimal` (2.1.292) | rc0, 경고1, 설치 완료 |
| `--components commands` (2.1.292) | rc0, 경고1, `check-health.md` 등 설치됨 |
| `--dry-run --components commands` (2.1.292) | rc0, 경고1, `[DRY RUN] Would install` 만 출력 |
| `--uninstall --yes` (2.1.292) | rc0, 경고1, `REMOVED: 3` 정상 제거 (I-2) |

## 산출물 바이트 동일성 (버전 미달 vs 2.1.330)

- `--profile minimal`: 프로젝트 6 파일 `diff -r` IDENTICAL (HOME 쓰기 0)
- `--profile core --yes`: 같은 샌드박스 경로에서 순차 실행 후 HOME+프로젝트 스냅샷 `diff -r` → **IDENTICAL, 88 파일**
  - 다른 경로로 병렬 실행하면 `~/.claude/projects/<경로>` 이름·`.settings-backups` 경로 문자열만 다름(경로 유래, 버전과 무관)
- core 실행 stdout: 경고 2줄을 제외하면 diff 0줄

## 실제 claude smoke

- `claude --version` → `2.1.330 (Claude Code)` (`~/.local/bin/claude`)
- 샌드박스 HOME 에서 `install.sh --dry-run --components commands`: rc0, 경고0, 파싱실패0, 샌드박스 내 파일 생성 0
- 실제 `~/.claude` 목록 해시 실행 전후 동일

## 정적 점검: `10#$c`

- `c` 는 `grep -Eo '[0-9]+\.[0-9]+\.[0-9]+'` 매치의 `cut -d. -f1..3` 이라 항상 1자리 이상 숫자 → 빈 문자열·비숫자 불가. `m` 은 상수. `set -u`/산술 오류 경로 없음(빈 출력·비숫자 출력은 `[ -z "$ver" ]` 에서 먼저 반환).
- 선행 0(`08`, `01`)은 `10#` 로 8진 해석 회피 — 실측 오류 0.
- 20자리 초과 필드는 bash 64bit 산술에서 오버플로 가능하나 오류 없이 진행(비현실적 입력, 결함 아님).
- `|| true` 로 `claude` 비정상 종료·`grep` 무매치가 `set -euo pipefail` 을 트리거하지 않음 — texit1/texit1n/tempty 로 확인.

## 결함 목록

| ID | 심각도 | 내용 | 재현 | 기대 / 실제 |
|---|---|---|---|---|
| L-1 | Low | 출력의 **첫** `X.Y.Z` 패턴을 버전으로 채택 — 버전 앞에 다른 점 3필드 숫자(날짜 등)가 있으면 오인 | fake `claude` 가 `built 2026.11.22 version 2.1.292` 출력 → `install.sh --components commands` | 경고 / 경고 없음(2026.11.22 로 읽음). 현재 실제 출력 형식 `2.1.330 (Claude Code)` 에서는 발생 안 함 |
| L-2 | Low | `claude --version` 호출에 타임아웃 없음 — 멈춘 CLI가 설치(및 `--dry-run`)를 그만큼 막음 | fake `claude` 가 `sleep 8; echo 2.1.292` → 설치 8초 지연 | 계약 위반은 아님(실패 없이 계속). 무한 대기 시 무한 지연 |
| I-1 | Info | stderr 만 출력하는 경우 `2>/dev/null` 로 버려져 파싱실패 WARN | tstderr | 계약 2(파싱 불가 → WARN, exit 0)와 일치 |
| I-2 | Info | `--uninstall` 에서도 버전 경고 출력(`check_prereqs` 가 공통 경로) | 위 uninstall 실행 | 흐름 차단 없음. 제거 시 경고는 소음일 수 있음 |

## 회귀 테스트 (참고)

`bash tests/test-claude-version.sh` (포그라운드) → `PASS 28 / FAIL 0 / SKIP 0`

## 미검증 항목

- 네트워크 호출 0건의 패킷 수준 확인은 하지 않음 — 코드상 `claude --version` 외 외부 호출 없음(정적), 실행은 네트워크 shim 하에서만.
- 실제 `claude --version` 이 자동 업데이트를 트리거하지 않는지는 CLI 내부 동작이라 미검증(이 실행에서 버전 변화 없음: 2.1.330 유지).
- Linux bash 4/5 환경은 미실행(macOS bash 3.2 만).
- `--profile full`/`--with-advisor`/`--with-cross-review` 조합은 미실행(점검 위치가 `check_prereqs` 말미라 동일 경로로 판단).

## 재현

```bash
bash dev/active/cc-min-version/qa/repro.sh "$PWD"   # 저장소 루트에서 (core 바이트 비교·hang·bash 3.2 재실행은 보고서 본문 명령)
```
