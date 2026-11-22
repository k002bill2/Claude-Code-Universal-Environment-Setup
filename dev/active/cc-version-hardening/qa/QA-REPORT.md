# QA-REPORT — cc-version-hardening (기준 4f71a12 → ad1304a)

## 판정: 조건부 PASS
수용 기준(BRIEF)은 전부 충족. L-1 회귀 0건. 단 **TERM 무시 CLI 는 타임아웃이 걸리지 않음**(M-1) — 계약 문구("멈춘 CLI가 설치를 무한 지연" 해소)를 TERM 무시 경우에는 못 지킴. 머지 전 M-1 반영 권고, L-3~L-5 는 후속 가능.

근거: `qa/repro.sh` 실행 원문 `qa/repro-output.txt` (macOS `/bin/bash`, mktemp 샌드박스 HOME, PATH 앞 가짜 claude, `< /dev/null`).

## 결함
| ID | 심각도 | 내용 | 재현 | 기대 / 실제 |
|---|---|---|---|---|
| M-1 | Medium | 타임아웃이 TERM 만 보냄(KILL 승격 없음). `timeout`/`gtimeout` 에 `-k` 없고, bash 폴백은 `_kill_tree` 가 TERM 후 `wait` 로 무기한 대기 | fake `trap '' TERM; sleep 43`, `CLAUDE_VERSION_TIMEOUT=1`, 경로 3종 | ~1초 후 WARN / **43.2~43.4초** 지연 후 WARN(3경로 모두). 잔존 프로세스 0, 설치 계속 |
| L-3 | Low | 폴백 경로 `$((secs*5))` 가 선행 0 값을 8진수로 해석 → 산술 오류 | `CLAUDE_VERSION_TIMEOUT=08 CC_VERSION_FORCE_BASH_TIMEOUT=1` + fake `sleep 39` | WARN(8초) / `line 550: 08: value too great for base`, 파싱실패 WARN, **백그라운드 claude 잔존 1, mktemp 임시파일 1개 누수**. exit 0·설치 계속 |
| L-4 | Low | `00` 이 검증(`0` 만 거부)을 통과 → GNU `timeout 00` 은 타임아웃 비활성 | `CLAUDE_VERSION_TIMEOUT=00` (timeout 경로) | 5초로 대체 / **39.3초** 대기(타임아웃 없음). 폴백 경로는 즉시 124(0.1초) — 경로 간 불일치 |
| L-5 | Low | 매우 큰 값: timeout 경로는 `invalid time interval`(rc125)→파싱실패 WARN, 폴백은 `secs*5` 오버플로로 사실상 무제한 | `CLAUDE_VERSION_TIMEOUT=99999999999999999999` | 일관 처리 / tool: 0.1초 파싱실패, fb: 39.3초 대기 후 정상 판정 |
| I-3 | Info | 2순위 `v` 접두가 단어 내부 `v` 에도 매칭(`dev2.1.300` → 2.1.300). 1순위 `(Claude Code)` 가 있으면 무관 | tdev | 결과는 3순위와 같아 현 사례에선 무해. `rev2.1.100 2.1.330` 형태면 2.1.100 채택(비현실적) |

L-3~L-5 는 테스트용 env 에만 해당(기본 5초 경로 영향 없음). 권고: `case` 를 `''|*[!0-9]*|0|0*)` 또는 `secs=$((10#$secs))`+상한(예: 300)으로, M-1 은 `timeout -k 1`·폴백에서 TERM 후 1초 뒤 `kill -9` 트리.

## 1. L-1 대조표 (테스트 파일과 독립 재현, `--dry-run --components commands`)
| 사례 | 출력 | 결과 | 판정 |
|---|---|---|---|
| tdate | `built 2026.11.22 version 2.1.292` | 경고1 | OK (L-1 해소) |
| tbuild | `build 2026.11.22` / `2.1.330 (Claude Code)` | 경고0 | OK |
| trel | `release 3.0.0 v2.1.292` | 경고1 | OK (2순위) |
| tbeta | `2.1.292-beta.1 (Claude Code)` | 경고1 | OK |
| t1234 | `claude 12.3.4` | 경고0 | OK |
| t1000 | `10.0.0 (Claude Code)` | 경고0 | OK |
| tafter | `2.1.330 (Claude Code) built 2026.01.01` | 경고0 | OK |
| tdev | `dev2.1.300` | 경고0 (2.1.300 채택) | I-3 기록 |
| tempty | 빈 출력 | 파싱실패1 | OK |

이전 QA 19사례 회귀(t292·t293·t1000·t2129·tv292·t000·tempty·tmulti·tmulti2·t4f·t4flow·t0lead·t08·tbig·tdate·texit1·texit1n·tstderr·thang): tdate(의도된 수정) 외 **결과 변화 0건**, 전부 rc0·오류0. thang(`read x`)은 `</dev/null` 로 즉시 EOF → 파싱실패(이전과 동일 조건).

## 2. L-2 타임아웃
경로 확인: p_sys PATH 에서 `timeout`→/usr/bin/timeout, p_gt PATH 에서 `timeout: none`·gtimeout 만 존재.

| 경로 | 자식+멈춤 (`sleep 41 & sleep 42; wait`) | TERM 무시 (`trap '' TERM; sleep 43`) |
|---|---|---|
| /usr/bin/timeout | 1.1초, WARN(1초), 잔존0, 설치 계속 | **43.4초**, WARN, 잔존0, 설치 계속 |
| gtimeout 만 | 1.2초, 동일 | **43.2초**, 동일 |
| bash 폴백 | 1.2초, 동일 | **43.2초**, 동일 |

`CLAUDE_VERSION_TIMEOUT` 실효값 (fake `sleep 39; echo 2.1.292`):
| 값 | timeout 경로 | bash 폴백 |
|---|---|---|
| `1` | 1초 | 1초 |
| `0` / `abc` / `-3` / 빈 값 | 5초 | 5초 |
| `00` | **무제한(39.3초)** — L-4 | 0초(즉시) |
| `08` | 8초 | **산술 오류·잔존1·tmp 누수** — L-3 |
| `99999999999999999999` | rc125 → 파싱실패 | **무제한(39.3초)** — L-5 |

경계(타임아웃 1초 vs `sleep 0.5; echo 2.1.292`) 3회 × 3경로 = 9/9 모두 버전 판정 성공(경고1), 0.7~0.9초. 불안정 0.

## 3. 정상 경로 비용
실제 `claude --version` = `2.1.330 (Claude Code)` (단독 0.04초). 샌드박스 HOME `--dry-run --profile core`: rc0, 1.6초, 버전 관련 경고 0.
실제 `~/.claude` 최상위 목록 해시: **전후 다름** — 모든 실행이 HOME=샌드박스였으므로 설치기 기인이 아니라 동시 실행 중인 Claude 세션(이 세션 포함)의 `~/.claude` 갱신으로 판단(추정, 미분리). 엄밀 검증은 미완.

## 4. 버전 미달 vs 정상 `--profile core`
dlow(2.1.292) rc0 경고1 / dhigh(2.1.330) rc0 경고0. `diff -r` 차이는 샌드박스 절대경로가 들어간 2곳뿐(`.settings-backups` 경로 문자열 — 해시 `90cec73e…` 동일, `~/.claude/projects/<경로 슬러그>` 디렉터리명). 경로 정규화 시 동일. files home=53 proj=35.

## 5. 정적
- `$((secs*5))`: 선행 0(L-3)·오버플로(L-5). `secs` 는 숫자만 통과하므로 주입 위험 없음.
- `mktemp` 실패 → `return 0` 무출력 → 파싱실패 WARN. 안전(미실행, 코드 판독).
- `kill -0` 루프 vs 종료 경쟁: 프로세스가 사이에 끝나면 `_kill_tree` 의 kill 은 `|| true`, `wait` 은 `|| true` — 안전. PID 재사용 경쟁은 0.2초 창에서 이론상만 존재.
- TERM 후 `wait` 무기한 → M-1.
- `set -euo pipefail`: `raw="$(…)" || rc=$?` 로 보호. 산술 오류는 명령 치환 서브셸만 종료(L-3 실측: 설치 계속). 단 이 경우 정리 코드가 실행되지 않아 누수.
- 게이트: `/bin/bash tests/test-claude-version.sh </dev/null` → PASS 46 / FAIL 0 / SKIP 0 (10.0초).

## 미검증
- 다른 테스트 파일(test-components·test-profiles 등 12개)·shellcheck 카운트: 시간 예산으로 미실행.
- 실제 `~/.claude` 무변경의 엄밀 증명(동시 세션 간섭으로 판정 불가, 위 3 참조).
- Linux(GNU coreutils 기본) 환경.

검증: `bash dev/active/cc-version-hardening/qa/repro.sh "$PWD"` (원문 repro-output.txt), `tests/test-claude-version.sh` PASS 46/0. 나머지 테스트·shellcheck 미실행.
위험·영향 범위: 이 커밋은 qa/ 문서·스크립트만 추가 — 코드 영향 없음.
되돌리는 법: `git revert <이 커밋 SHA>`.
