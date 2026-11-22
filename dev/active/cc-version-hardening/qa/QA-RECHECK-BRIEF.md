등급: Q (재검증 QA — 코드 수정 금지)
서브에이전트 분할: 불필요

# QA-RECHECK-BRIEF — FIX `f83a3d1` 재검증

대상: 브랜치 `k002bill2/cc-version-hardening` HEAD(`f83a3d1` 이후). 이전 판정: `qa/QA-REPORT.md`(조건부 PASS, M-1·L-3~L-5·I-3). 수정 지시: `FIX-BRIEF.md`.

## 확인 항목 (실행 근거 필수, mktemp 샌드박스·PATH 앞 가짜 claude만)
1. `qa/repro.sh "$PWD"` 를 다시 돌려 이전 결함 행(M-1 3경로, `00`/`08`/20자리, `dev2.1.300`)의 기대/실제를 새 표로. 이전 PASS 행 회귀 0 확인.
2. M-1 추가 사례: TERM 무시 + 자식 생성(`trap '' TERM; sleep 44 & sleep 45; wait`) × 3경로(`/usr/bin/timeout`, gtimeout만, `CC_VERSION_FORCE_BASH_TIMEOUT=1`) — 경과 시간(목표 ≤ secs+2초), 잔존 `sleep 4[45]` 0.
3. 정규화 경계: `1`, `300`, `301`, `000`, `0300`, `-1`, ` 5`(공백) → 실효 초.
4. I-3: `rev2.1.100 2.1.330` → 2.1.100 채택(경고), `v2.1.292`·`(v2.1.292)` → 2순위 매칭(경고).
5. 실제 `~/.claude` 무변경 증명: 이전 리포트는 "목록 해시 변화"를 동시 세션 탓으로 추정했다. 이번엔 **install.sh 실행 직전·직후 `find ~/.claude -newer <마커파일> -print`** 로, 실행 구간에 바뀐 경로를 나열하고 그 경로가 설치기 산출물 이름(rules/·skills/·settings.json·CLAUDE.md·.manifest 등)과 겹치는지 판정. 실제 HOME에 쓰는 실행은 금지 — install.sh 는 HOME=샌드박스로만 돌리고, 실제 ~/.claude 는 읽기만.

## 산출물
`dev/active/cc-version-hardening/qa/QA-RECHECK.md`: 판정(PASS / 조건부 PASS / FAIL), 대조표, 남은 결함, 미검증. 재현 스크립트 추가 시 `qa/` 아래 새 파일(기존 파일 수정 금지).
로컬 커밋 1개(`test(qa): ...`). 코드·테스트 수정 금지, push 금지, 테스트 파일 병렬 실행 금지.
