# PROGRESS — install-profiles (R1)

- [x] C1: push 삭제 + P0 회귀 → ce5e1b2
- [x] C2-RED: test-profiles.sh 케이스 1~10 (FAIL 37 확인)
- [x] C2-GREEN: install.sh 프로필 구현 → fd48d47
- [x] C2: templates/CLAUDE.minimal.md
- [x] C2: 전체 tests/*.sh 9개 exit 0 (fd48d47 기준), profiles 는 Codex 반영 후 재실행 83/0
- [x] C3: README 갱신 → 3b39628
- [x] C3: Codex 리뷰 1회, P2 3건 반영 (P11·P12 회귀 추가; TTY 케이스 테스트는 BLOCKED: pty 필요·시간 부족)
- [x] C3: REPORT.md → 커밋
- [ ] Codex 반영 후 나머지 8개 테스트 재실행 — BLOCKED: 시간 예산 소진, 다음 세션에서 `for t in tests/test-*.sh; do /bin/bash $t; done`

서브에이전트: 사용 안 함 (브리프 "서브에이전트 분할: 불필요").
