등급: Q (독립 QA — 코드 수정 금지)
서브에이전트 분할: 선택(정적 리뷰 / 실행 검증 2개까지 병렬 가능, 쓰기는 qa/ 경로만)

# QA-BRIEF — 설치기 최소 Claude Code 버전 경고

## 대상
브랜치 `k002bill2/cc-min-version`, 기준 `6fa38ba`(main) 대비 커밋 `6b885fb`(기능) + `c73ef35`(정규식 수정).
변경: `install.sh` `check_claude_version()` / `MIN_CLAUDE_VERSION="2.1.293"`, `tests/test-claude-version.sh`, README 1줄.

## 계약 (BRIEF.md 참조)
1. `claude --version` < 2.1.293 → `log_warn` 2줄 이내, 설치 계속, exit 코드 불변
2. claude 미존재 → 생략 메시지, exit 0 / 파싱 불가 → WARN, exit 0
3. 숫자 필드별 비교(문자열 비교 금지), 2자리 이상 메이저·`v` 접두사·`-beta` 접미사 정상 처리
4. `--dry-run`에서도 경고, 네트워크 호출·자동 업데이트 없음
5. bash 3.2(macOS `/bin/bash`), `set -euo pipefail` 안전

## 검증 항목 (실행 근거 필수)
- 테스트 파일이 아닌 **독립 재현**: 샌드박스 HOME + PATH 앞 가짜 `claude`로 install.sh 직접 실행. 최소 사례: `2.1.292`, `2.1.293`, `10.0.0`, `2.1.29`, `v2.1.292`, `0.0.0`, 빈 출력, 여러 줄 출력(첫 줄에 버전 없음), `2.1.293.1`(4필드), 선행 0(`2.01.300`) — 예상과 실제 대조표
- 가짜 `claude`가 exit 1을 내거나 stderr만 출력할 때 설치가 계속되는지
- `--profile minimal`·`--components commands`·`--uninstall`에서도 점검이 설치 흐름을 막지 않는지(경고 여부 기록)
- 버전 미달 시 설치 산출물이 동일 조건 2.1.330 실행과 바이트 동일한지(diff -r)
- 실제 claude(로컬 `claude --version`)로 `--dry-run` 1회 smoke
- 정적: `10#$c`가 빈 문자열·비숫자일 때 `set -u`/산술 오류 가능성
- 금지: 실제 `$HOME`·`~/.claude` 쓰기. 반드시 mktemp 샌드박스.

## 산출물
`dev/active/cc-min-version/qa/QA-REPORT.md`: 판정(PASS / 조건부 PASS / FAIL), 결함 목록(심각도·재현 명령·기대/실제), 대조표, 미검증 항목.
로컬 커밋 1개(`test(qa): ...`). 코드·테스트 수정 금지, push 금지.
