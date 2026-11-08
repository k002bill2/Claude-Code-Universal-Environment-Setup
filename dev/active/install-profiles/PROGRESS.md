# PROGRESS — install-profiles (R1)

- [x] C1: `Bash(git push:*)` 삭제 + 회귀 테스트(P0: 업그레이드 제거 / 사용자 문자열 보존 / jq·node) → ce5e1b2
- [x] C2-RED: tests/test-profiles.sh 프로필 케이스 1~10 (RED: FAIL 37 확인)
- [x] C2-GREEN: install.sh `--profile` / minimal / 기록·재사용 / 배타 / 축소 무삭제 / 요약 → fd48d47
- [x] C2: templates/CLAUDE.minimal.md (21줄)
- [ ] C2: 전체 tests/*.sh 통과 (/bin/bash 3.2) — test-lifecycle/manifest/merge-settings/profiles/sync 실행 중
- [x] C3: README 갱신 (Profiles 절, Quick Start, Flags)
- [ ] C3: Codex 리뷰 1회 + P1/P2 반영 — 실행 중
- [ ] C3: REPORT.md → 커밋

서브에이전트: 사용 안 함 (브리프 "서브에이전트 분할: 불필요").
