# QA-RECHECK — FIX `f83a3d1` 재검증 (HEAD `a9f2e56`)

## 판정: PASS
이전 결함 M-1·L-3·L-4·L-5·I-3 전부 해소(실행 근거 있음). 이전 PASS 행 회귀 0건. 실제 `~/.claude` 는 install.sh 실행 구간에 변경 경로 0건.

근거 원문:
- `qa/recheck-repro-output.txt` — `bash qa/repro.sh "$PWD"` 재실행 (기존 스크립트 무수정)
- `qa/recheck-output.txt` — `bash qa/recheck.sh "$PWD"` (이번에 추가한 새 파일: 확인 항목 2~5)
- 환경: macOS `/bin/bash`, mktemp 샌드박스 HOME, PATH 앞 가짜 `claude`, `< /dev/null`. 두 스크립트는 순차 실행(서로의 `sleep 4x` 를 pkill 하므로 병렬 금지).

## 1. 이전 결함 행 대조 (repro.sh 재실행)
| ID | 사례 | 이전 실제 | 기대 | 이번 실제 | 판정 |
|---|---|---|---|---|---|
| M-1 | `trap '' TERM; sleep 43`, TIMEOUT=1, /usr/bin/timeout | 43.4초 | ≤ 3초, WARN | **2.2초**, WARN(1초), 잔존0 | 해소 |
| M-1 | 동일, gtimeout 만 | 43.2초 | ≤ 3초 | **2.2초**, 잔존0 | 해소 |
| M-1 | 동일, bash 폴백 | 43.2초 | ≤ 3초 | **2.4초**, 잔존0 | 해소 |
| L-4 | `00`, timeout 경로 | 39.3초(무제한) | 5초 대체 | 5.1초, WARN(5초) | 해소 |
| L-4 | `00`, 폴백 | 0.1초(`00초`) | 5초 대체 | 5.8초, WARN(5초) | 해소(경로 간 일치) |
| L-3 | `08`, 폴백 | 산술 오류·잔존1·tmp 누수 | 8초 | 9.0초, WARN(8초), 오류0, 잔존0 | 해소 |
| L-3 | `08`, timeout 경로 | 8.1초 `(08초)` | 8초 | 8.2초 `(8초)` | 해소(표기 정규화) |
| L-5 | 20자리, timeout 경로 | rc125→파싱실패 | 일관 처리 | 5.1초, WARN(5초) | 해소 |
| L-5 | 20자리, 폴백 | 39.3초(무제한) | 일관 처리 | 5.8초, WARN(5초) | 해소 |
| I-3 | `dev2.1.300` | 2순위로 2.1.300 | 2순위 불매칭 | 경고0 (3순위로 2.1.300 — 결과 동일) | 해소(아래 4 참조) |
| — | mktemp 누수 파일 수 | 1 | 0 | **0** | 해소 |

이전 PASS 행 회귀: L-1 대조표 9행·19사례·자식+멈춤 3경로·`1/0/abc/-3/빈값` 2경로·경계 9회·실제 claude smoke(rc0, 1.6초, 경고0)·dlow/dhigh 비교(차이는 샌드박스 절대경로 2곳뿐, files home=53 proj=35) — **warn/parsefail/hang/rc 값 변화 0건**. 시간은 ±0.1~0.6초 범위(폴백 `fb_child` 1.2→1.6초: TERM 후 최대 1초 대기 루프 추가분, 기능 영향 없음).

## 2. M-1 추가: TERM 무시 + 자식 (`trap "" TERM; sleep 44 & sleep 45; wait`, TIMEOUT=1)
| 경로 | 경과 | 목표 ≤ 3초 | 잔존 `sleep 4[45]` | 설치 계속 |
|---|---|---|---|---|
| /usr/bin/timeout (`gtimeout: none`) | 2.1초 | OK | 0 | done=4 |
| gtimeout 만 (`timeout: none`) | 2.1초 | OK | 0 | done=4 |
| `CC_VERSION_FORCE_BASH_TIMEOUT=1` | 2.5초 | OK | 0 | done=4 |

잔존 측정은 install.sh 종료 0.3초 후 `pgrep -f 'sleep 4[45]$'`. SIG_IGN 이 자식 `sleep` 에 상속되는 조건에서도 KILL 승격으로 트리 전체 정리 확인.

## 3. 정규화 경계 (fake `sleep 7; echo "2.1.330 (Claude Code)"`)
실효 5초면 `응답 없음(5초)`, 300초면 7초 후 정상 판정.
| 값 | 기대 실효 | timeout 경로 | bash 폴백 |
|---|---|---|---|
| `1` | 1 | 1.1초 `(1초)` | 1.5초 `(1초)` |
| `300` | 300 | 7.3초 정상 판정(경고0) | 7.5초 정상 판정 |
| `301` | 5 | 5.1초 `(5초)` | 5.8초 `(5초)` |
| `000` | 5 | 5.2초 `(5초)` | 5.9초 `(5초)` |
| `0300` | 5 (길이 4 > 3) | 5.1초 `(5초)` | 5.8초 `(5초)` |
| `-1` | 5 | 5.1초 `(5초)` | 5.8초 `(5초)` |
| ` 5` (공백) | 5 | 5.2초 `(5초)` | 5.8초 `(5초)` |
전부 rc0, 산술 오류 0, 잔존 0. 14/14 기대 일치.

## 4. I-3 v 접두 경계
| 입력 | 기대 | install.sh 통합 | `_pick_claude_version` 직접 |
|---|---|---|---|
| `rev2.1.100 2.1.330` | 2.1.100 채택(경고) | 경고1 | 2.1.100 |
| `v2.1.292` | 2순위, 경고 | 경고1 | 2.1.292 |
| `(v2.1.292)` | 2순위, 경고 | 경고1 | 2.1.292 |
| `3.0.0 (v2.1.292)` (2순위 판별용) | 2.1.292 | — | 2.1.292 (3순위였다면 3.0.0) |
| `3.0.0 rev2.1.100` (불매칭 판별용) | 3.0.0 | — | 3.0.0 (`rev` 는 2순위 미매칭) |
| `release 3.0.0 v2.1.292` | 2.1.292 | (repro trel 경고1) | 2.1.292 |
직접 호출은 install.sh 에서 함수 본문만 추출해 평가(본체 미실행).

## 5. 실제 `~/.claude` 무변경 증명
절차: `touch <샌드박스>/r5.marker` → 1.1초 대기 → `HOME=<샌드박스> install.sh --project <샌드박스> --profile core`(실설치, dry-run 아님) → 직후 `find ~/.claude -newer r5.marker -print`.
- install rc=0, 샌드박스 HOME 파일 53개 생성(설치기 정상 동작 확인).
- 실행 구간에 변경된 실제 `~/.claude` 경로: **0건**.
- 설치기 산출물 최상위(`.manifest .settings-manifest docs projects rules settings.json skills`) 와의 교집합: **0건**.
- 결론: 이전 리포트의 "목록 해시 변화"는 설치기 기인이 아님. 이번 repro.sh 재실행에서도 `listing CHANGED` 가 다시 찍혔으나, 그 검사는 전체 repro(약 3분) 구간의 `ls -la` 해시라 동시 세션 갱신을 포함한다 — 단일 install 구간을 좁힌 find 검사가 0건이므로 이를 우선 근거로 채택.

## 6. 게이트
`/bin/bash tests/test-claude-version.sh </dev/null` → **PASS 69 / FAIL 0 / SKIP 0** (38초, 포그라운드 단독).

## 남은 결함
없음 (차단·비차단 모두).

관찰(결함 아님): 폴백 경로는 정상 타임아웃에도 TERM 후 최대 1초 대기가 붙어 `secs+0.5~1.5초`가 걸린다(측정 2.4~2.5초 / 목표 3초 이내).

## 미검증
- 다른 테스트 파일 12개·shellcheck: 이번 QA 범위(브리프 항목 1~5) 밖이라 미실행.
- Linux(GNU coreutils `timeout -k`) 환경: macOS 에서 `/usr/bin/timeout`·Homebrew `gtimeout` 으로만 확인.
- R5 는 install 1회 구간만 측정. repro.sh 전체 구간의 실제 `~/.claude` 무변경은 find 로 좁혀 증명하지 않았다(모든 실행이 HOME=샌드박스인 것은 스크립트 판독으로 확인).

검증: 위 두 스크립트 순차 실행(원문 첨부), `tests/test-claude-version.sh` PASS 69/0. 다른 테스트·shellcheck·Linux 미실행.
위험·영향 범위: 이 커밋은 `qa/` 문서·새 스크립트·출력 원문만 추가 — 코드·테스트 영향 없음.
되돌리는 법: `git revert <이 커밋 SHA>`.
