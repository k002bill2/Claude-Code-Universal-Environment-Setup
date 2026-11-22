등급: Q (독립 QA — 코드 수정 금지)
서브에이전트 분할: 선택(정적 리뷰 / 실행 검증 2개까지 병렬, 쓰기는 qa/ 경로만)

# QA-BRIEF — 버전 점검 보강 (L-1 토큰 선택·L-2 타임아웃)

## 대상
브랜치 `k002bill2/cc-version-hardening`, 기준 `4f71a12`(main) 대비 `ad1304a`.
변경: `install.sh` `_kill_tree` / `_claude_version_with_timeout` / `_pick_claude_version` / `check_claude_version`, `tests/test-claude-version.sh`.
계약: `dev/active/cc-version-hardening/BRIEF.md`. 이전 QA: `dev/active/cc-min-version/qa/QA-REPORT.md`(회귀 기준).

## 검증 항목 (실행 근거 필수, mktemp 샌드박스·PATH 앞 가짜 claude만)
1. L-1 대조표(테스트 파일과 독립 재현): `built 2026.11.22 version 2.1.292`, 2줄 `build 2026.11.22` / `2.1.330 (Claude Code)`, `release 3.0.0 v2.1.292`, `2.1.292-beta.1 (Claude Code)`, `claude 12.3.4`, `10.0.0 (Claude Code)`, `2.1.330 (Claude Code) built 2026.01.01`, `dev2.1.300`(오탐 여부 기록), 빈 출력 — 이전 QA 19사례 중 결과가 바뀐 것이 있으면 결함
2. L-2 타임아웃: 경로 3종(`/usr/bin/timeout`, `gtimeout`만 있는 PATH, `CC_VERSION_FORCE_BASH_TIMEOUT=1` bash 폴백) 각각
   - fake가 자식 프로세스를 만든 뒤 멈추는 경우(`sleep 41 & sleep 42; wait`)와 TERM을 무시하는 경우(`trap '' TERM; sleep 43`) — 경과 시간, 잔존 프로세스(`pgrep -f 'sleep 4[123]'`), 설치 계속 여부 기록
   - `CLAUDE_VERSION_TIMEOUT` 값: `1`, `0`, `abc`, `-3`, 빈 값 → 실효 초 기록
   - 응답 직전(타임아웃 1초 vs fake `sleep 0.5; echo 2.1.292`) 경계에서 결과 안정성 3회
3. 정상 경로 비용: 실제 `claude --version`(2.1.330)로 `--dry-run` smoke, 소요 시간과 경고 0 확인, 실제 `~/.claude` 해시 전후 동일
4. 버전 미달 vs 정상 버전 `--profile core` 산출물 바이트 동일(이전 QA 방식 재사용)
5. 정적: 폴백 경로의 `$((secs*5))` 큰 값, `mktemp` 실패, `wait`/`kill` 경쟁, `set -euo pipefail` 아래 비정상 종료 경로

## 산출물
`dev/active/cc-version-hardening/qa/QA-REPORT.md`: 판정(PASS / 조건부 PASS / FAIL), 결함(심각도·재현·기대/실제), 대조표, 미검증 항목. 재현 스크립트는 `qa/` 아래.
로컬 커밋 1개(`test(qa): ...`). 코드·테스트 수정 금지, 실제 HOME 쓰기 금지, push 금지. 테스트 파일들을 서로 병렬로 돌리지 말 것(pgrep 전역 매칭 간섭).
