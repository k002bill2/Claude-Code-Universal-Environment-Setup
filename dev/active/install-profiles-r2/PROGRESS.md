# PROGRESS — install-profiles R2

- [x] C1: tests/test-components.sh RED → --components 구현 GREEN → 커밋
- [x] C2: 첫 설치 TTY 메뉴 + --yes/--non-interactive (tests/test-menu.sh) + tests/README.md
- [x] C2: R1 이월 — TTY 경로 full 재사용 회귀 테스트
- [x] C2: R1 이월 — P11/P12 RED 확인 (되돌림 → FAIL → 복원)
- [x] C3: 글로벌 드리프트 사전 점검 (rules/skills WARN, advisor CLAUDE.md 블록 exit 1, --force-global)
- [x] C3: README — components 표, full ≠ 모든 키, 메뉴, Orca / git worktree 운영 절
- [x] C3: Codex 리뷰 1회 + 반영
- [ ] 전체 tests/*.sh 실행 (마지막 커밋 후), bash -n, shellcheck 신규 0
- [ ] REPORT.md

## 기록
- C1 cb3d062: test-components RED FAIL 43 → GREEN 72/0. 회귀: profiles 83/0, install 92/0, lifecycle 149/0.
- C2: test-menu 39/0. RED(임시 사본): C1 install.sh 대비 FAIL 22, T1(재적용 제거) FAIL 3, P11(FIFO 검사 제거) FAIL 1, P12(managed_path_safe 제거) FAIL 1. 사본 삭제, 되돌린 상태 미커밋.
- C3: test-drift 17/0 (RED: C2 install.sh 대비 FAIL 8). Codex P2(components+cross-review 무시) → K12 RED FAIL 2 → GREEN 74/0.
