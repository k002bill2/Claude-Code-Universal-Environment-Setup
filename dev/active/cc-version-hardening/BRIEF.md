등급: S
서브에이전트 분할: 불필요(함수 1개 + 테스트 1파일, 강결합)

# BRIEF — 버전 점검 보강 (QA L-1·L-2 후속)

근거: `dev/active/cc-min-version/qa/QA-REPORT.md`(PR #15에 포함, main `4f71a12`)의 L-1·L-2.
대상 함수: `install.sh` `check_claude_version()` (514행 근처에서 `check_prereqs` 가 호출).

## L-1 — 버전 토큰 선택 규칙
현재: 출력의 **첫** `X.Y.Z` 를 채택 → `built 2026.11.22 version 2.1.292` 를 2026.11.22 로 오인.
수정: 아래 우선순위로 하나를 고른다(위에서 찾으면 멈춤).
1. 바로 뒤에 ` (Claude Code)` 가 오는 `X.Y.Z`
2. 바로 앞이 `version ` / `Version ` / `v` 인 `X.Y.Z` (`v2.1.292` 포함)
3. 그 외에는 첫 `X.Y.Z`(현행 동작 유지)
기존 테스트 사례(`2.1.292-beta.1 (Claude Code)`, `claude 12.3.4`, `10.0.0 (Claude Code)`, 여러 줄 출력)는 결과가 바뀌면 안 된다.

## L-2 — `claude --version` 타임아웃
현재: 타임아웃 없음 → 멈춘 CLI가 설치를 무한 지연.
수정:
- 기본 5초. 테스트용 덮어쓰기 env `CLAUDE_VERSION_TIMEOUT`(정수 초, 잘못된 값이면 5).
- `timeout` → `gtimeout` → 순수 bash 폴백 순으로 사용. 폴백은 백그라운드 실행 + 임시 파일 + 대기 루프 + 초과 시 `kill`(자식 정리). 임시 파일은 `mktemp`, 함수 종료 시 삭제. 이 머신은 `/usr/bin/timeout` 이 있으므로 **폴백 경로를 강제하는 테스트 훅**을 둔다(예: env `CC_VERSION_FORCE_BASH_TIMEOUT=1`, 문서화된 테스트 전용 이름).
- 초과 시 `log_warn` 1줄("claude --version 응답 없음(N초) — 버전 점검 생략"), 설치 계속, exit 코드 불변.
- bash 3.2 호환, `set -euo pipefail` 안전, 남는 백그라운드 프로세스 0.

## 범위 밖 (건드리지 말 것)
- QA I-1(stderr 무시)·I-2(`--uninstall` 경고)는 현행 유지.
- `MIN_CLAUDE_VERSION`, 경고 문구, 호출 위치 변경 금지.

## 쓰기 경로
`install.sh`(check_claude_version 와 그 헬퍼만), `tests/test-claude-version.sh`, `README.md`(필요 시 1줄), `dev/active/cc-version-hardening/REPORT.md`

## 수용 기준 (테스트로 고정)
- `built 2026.11.22 version 2.1.292` → 경고
- `build 2026.11.22\n2.1.330 (Claude Code)` → 경고 없음
- `release 3.0.0 v2.1.292` → 경고(2순위)
- 기존 V1~V8 전부 유지
- fake `sleep 30; echo 2.1.292` + `CLAUDE_VERSION_TIMEOUT=1` → 응답 없음 WARN, exit 0, 전체 실행 10초 이내, 실행 후 해당 fake 프로세스 잔존 0(`pgrep -f` 로 확인)
- 위 사례를 `CC_VERSION_FORCE_BASH_TIMEOUT=1` 로도 한 번 더(폴백 경로)
- 정상 fake(즉시 응답)는 타임아웃 경로를 타지 않음

## 검증 (macOS `/bin/bash`, `< /dev/null`)
```
/bin/bash -n install.sh
/bin/bash tests/test-claude-version.sh < /dev/null
/bin/bash tests/test-components.sh < /dev/null
/bin/bash tests/test-profiles.sh < /dev/null
shellcheck install.sh | grep -c '^In '   # 기존 19 유지
```
전체 13개 파일 게이트는 Jarvis가 회수 시 실행한다(REPORT에 명시).

## 금지
push·PR 금지, 쓰기 경로 밖 수정 금지, 네트워크 호출 금지. 로컬 커밋 1~2개(Conventional Commits, 한국어 본문).

## 보고
REPORT.md: 변경 요약, 테스트 결과(파일별), shellcheck 전후, `검증 / 위험·영향 범위 / 되돌리는 법`.
