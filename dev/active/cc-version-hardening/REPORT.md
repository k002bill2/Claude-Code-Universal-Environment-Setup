# REPORT — cc-version-hardening (QA L-1·L-2)

## 변경 요약
- `install.sh`: `_pick_claude_version`(L-1: `X.Y.Z (Claude Code)` → `version |Version |v` 접두 → 첫 토큰), `_claude_version_with_timeout`(L-2: timeout → gtimeout → bash 폴백, 기본 5초, env `CLAUDE_VERSION_TIMEOUT`, 잘못된 값은 5), `_kill_tree`(폴백 자식 정리) 추가. `check_claude_version` 은 이를 호출. 초과 시 WARN 1줄, exit 0. `MIN_CLAUDE_VERSION`·경고 문구·호출 위치 불변.
- 테스트 전용 env: `CC_VERSION_FORCE_BASH_TIMEOUT=1` (폴백 경로 강제).
- `tests/test-claude-version.sh`: T1~T4, TO(native/bash) 추가 (기존 V1~V8 유지).
- README 변경 없음.

## 테스트 (macOS /bin/bash, < /dev/null)
- `bash -n install.sh`: OK
- test-claude-version.sh: PASS 46 / FAIL 0 (연속 3회)
- test-components.sh: PASS 74 / FAIL 0
- test-profiles.sh: PASS 83 / FAIL 0
- shellcheck `^In ` 건수: 전 19 → 후 19
- 실행 후 `pgrep -f "sleep 37"` 잔존 0
- 참고: test-profiles 를 백그라운드로 동시에 돌리던 중 1회 2건 FAIL 관측(동시 실행 간섭 추정, pgrep 전역 매칭). 단독 재실행 3회 모두 0 FAIL. 원인 미확정.
- 전체 13개 파일 게이트는 미실행 — Jarvis 회수 시 실행.

검증: 위 명령 실행·확인. 13개 전체 게이트, GNU `gtimeout`-only 환경은 미검증.
위험·영향 범위: `install.sh` 설치 사전점검만 영향. 오판 시 경고 누락/오발 또는 점검 생략(설치·exit 코드 불변).
되돌리는 법: 이 레인의 커밋을 `git revert <SHA>`.

---

# FIX 절 — QA 지적 반영 (M-1, L-3~L-5, I-3)

## 변경
- `install.sh`
  - M-1: 네이티브 경로 `"$tool" -k 1 "$secs" claude --version`(macOS `/usr/bin/timeout`·gtimeout 모두 `-k` 지원 확인). bash 폴백은 `_kill_tree "$pid" TERM` 후 0.2초×5 대기, 생존 시 `_kill_tree "$pid" KILL`, 이후 `wait`. `_kill_tree` 에 시그널 인자 추가. `check_claude_version` 은 rc 124·137 모두 "응답 없음" WARN.
  - L-3~L-5: `CLAUDE_VERSION_TIMEOUT` 숫자만 → 길이 3 초과면 5 → `10#` 변환 → 1~300 밖이면 5. 산술 오류 경로 자체가 사라짐.
  - I-3: 2순위 `v` 는 `(^|[^A-Za-z])v` 단어 경계일 때만. `version `/`Version ` 불변.
  - 폴백: 산술 오류 경로 제거, TERM→KILL→wait 로 종료 후 항상 `rm -f "$tmp"`.
- `tests/test-claude-version.sh`: M1(native/bash), NZ(00/08/20자리), B1·B2 추가 (46 → 69건).

## 검증 (모두 fresh, 순차 실행, `< /dev/null`)
- `/bin/bash -n install.sh`: OK
- `tests/test-claude-version.sh`: PASS 69 / FAIL 0, 전체 실행 34초(목표 60초 이내)
- `tests/test-components.sh`: PASS 74 / FAIL 0
- `shellcheck install.sh | grep -c '^In '`: 19 (유지)
- `qa/repro.sh "$PWD"` 요약: 타임아웃 `00`→응답 없음(5초), `08`→(8초), 20자리→(5초) 이며 산술 오류(err)=[] , 잔존 left=0 (tool/fallback 양 경로). 경계 1초 vs sleep 0.5 는 정상 응답(warn=1, hang 없음). 실제 claude 2.1.330 smoke 경고 0. 버전 미달/정상 core 프로파일 diff 는 경로 이름 차이뿐.
- repro 출력 중 `REAL ~/.claude listing CHANGED`: 라이브 `~/.claude` 는 다른 세션이 계속 바꾸므로 본 수정과 무관한 것으로 추정(미확정). `잔존 tmp 1` 은 00:47 생성의 선행 파일(삭제 후 M-1 폴백 재현 → 누수 0 확인).
- 미검증: 13개 전체 게이트, gtimeout-only 환경, test-profiles 재실행.

선택: ★bash 폴백 TERM 유예 1초(브리프 지정)

위험·영향 범위: `install.sh` 버전 점검 함수들만. 오판 시 경고 누락/오발 또는 점검 생략(설치·exit 코드 불변). `-k 1` 로 timeout 경로 최대 지연 +1초.
되돌리는 법: 이 레인의 `fix(install)` 커밋을 `git revert <SHA>`.
