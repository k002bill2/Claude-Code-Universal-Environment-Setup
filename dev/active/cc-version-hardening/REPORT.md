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
