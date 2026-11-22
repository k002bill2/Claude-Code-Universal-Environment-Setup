등급: S
서브에이전트 분할: 불필요(정규식 1곳 + 테스트 케이스 추가)

# FIX-BRIEF — 버전 추출 정규식 결함 (재현 확인됨)

## 결함 (Jarvis 실측)
`install.sh` `check_claude_version()`의 sed 정규식이 앞쪽 탐욕 `.*` 때문에 2자리 이상 메이저 버전의 앞자리를 잃는다.
```
"10.0.0 (Claude Code)" → 0.0.0   (기대 10.0.0 — 경고 오발)
"claude 12.3.4"        → 2.3.4   (기대 12.3.4)
"2.1.330 (Claude Code)"→ 2.1.330 (정상)
```

## 수정
- 첫 번째 `X.Y.Z` 토큰을 앞자리 손실 없이 추출(예: `grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1`, 또는 sed 앞에 비숫자 경계 강제). bash 3.2 / BSD 도구 호환, `set -euo pipefail` 안전(`|| true`).
- 테스트 `tests/test-claude-version.sh`에 케이스 추가:
  - `10.0.0 (Claude Code)` → 경고 없음
  - `claude 12.3.4` → 경고 없음
  - `v2.1.292` → 경고 (접두사 v)
  - `2.1.292-beta.1 (Claude Code)` → 경고 (접미사)

## 쓰기 경로
`install.sh`(check_claude_version 함수만), `tests/test-claude-version.sh`, `dev/active/cc-min-version/REPORT.md`(FIX 절 추가)

## 검증
```
/bin/bash -n install.sh
/bin/bash tests/test-claude-version.sh < /dev/null
/bin/bash tests/test-components.sh < /dev/null
shellcheck install.sh | grep -c '^In '   # 19 유지
```

## 금지
push·PR 금지, 위 경로 밖 수정 금지. 로컬 커밋 1개(`fix(install): ...`).
