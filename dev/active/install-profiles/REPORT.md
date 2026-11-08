# REPORT — install-profiles R1

## 변경 파일
- `project/settings-fragments/cli-orchestration.json` — `Bash(git push:*)` 1줄 삭제 (C1 ce5e1b2)
- `tests/test-fragments.sh` — F2: push 를 필수 목록에서 빼고 "push 사전 허용 없음" 검사 추가
- `tests/test-profiles.sh` (신규) — P0 push 업그레이드 회귀(jq/node), P1~P10 브리프 필수 케이스, P11·P12 Codex 회귀
- `install.sh` — `--profile`, 프로필 결정/기록/배타/fail-closed, `step_on` 게이트, minimal 자산, 남은 자산 N건, 요약·체크리스트 컴포넌트 인식 (C2 fd48d47 + Codex 반영)
- `templates/CLAUDE.minimal.md` (신규, 21줄)
- `README.md` — Quick Start, Profiles 절, Flags (3b39628)

## 결정 이탈·해석
- 기록 파일은 **명시(explicit)·기록(recorded) 프로필일 때만** 쓴다. 미명시 core(default)는 기록하지 않음 — "기존 계약 보존"을 위해. 따라서 `--full` 산출물은 push 외에 `.claude/.install-profile` 1개가 추가된다(P8 은 이 파일·settings 백업·.settings-manifest 의 push identity 줄을 제외하고 비교).
- `--profile minimal` + 프로젝트 미지정 → exit 1 (브리프 미규정, minimal 은 프로젝트 전용이라 추가).
- `--profile` 에 알 수 없는 값 → exit 1.
- `.install-profile` 은 manifest 가 아닌 전용 함수로 관리(rb_track 저널 포함, uninstall 이 직접 제거).
- legacy-identities.tsv 미수정, push 제거 보완 코드 없음(엔진이 처리 — P0 로 확인).

## 테스트 결과 (/bin/bash 3.2, 포그라운드)
| 파일 | 결과 | exit |
|------|------|------|
| test-fragments.sh | PASS 100 / FAIL 0 | 0 |
| test-git-cleanup.sh | PASS 41 / FAIL 0 | 0 |
| test-in-session-cross-review.sh | PASS 306 / FAIL 0 / SKIP 1 | 0 |
| test-install.sh | PASS 92 / FAIL 0 | 0 |
| test-lifecycle.sh | PASS 149 / FAIL 0 | 0 |
| test-manifest.sh | PASS 24 / FAIL 0 | 0 |
| test-merge-settings.sh | PASS 46 / FAIL 0 | 0 |
| test-profiles.sh | PASS 83 / FAIL 0 (Codex 반영 후 재실행) | 0 |
| test-sync-from-live.sh | PASS 11 / FAIL 0 | 0 |

- 위 9개 중 profiles 외 8개는 Codex 반영 **이전** 커밋(fd48d47) 기준 실행. Codex 반영은 install.sh 의 프로필 경로 3곳만 바꿨다 — 재실행 필요(아래 남은 일).
- `bash -n install.sh` OK. shellcheck `-S warning`: 변경 전 17 → 변경 후 17 (신규 0).
- `grep -rn "git push" project/settings-fragments/` → 0건.
- RED: 프로필 케이스 작성 직후 FAIL 37 확인 후 구현.

## Codex 리뷰 (1회, `review --scope branch --base c39be55`)
- [P2] TTY 경로에서 기록된 full 재사용 시 FULL 파생 옵션 미적용 → `apply_profile_options` 를 최종 결정 뒤 재호출. **회귀 테스트 없음**(pty 필요 — 시간 부족).
- [P2] `.install-profile` 이 FIFO 면 `cat` 무기한 대기 → 유형 검사를 먼저. P11 GREEN (RED 미확인 — 시간 부족).
- [P2] `.claude` 상위 링크 시 uninstall 이 링크 너머 기록 삭제 → `managed_path_safe` 검사 추가. P12 GREEN (RED 미확인).

## 2차 레인으로 넘길 사항
- `--components`, TTY 메뉴: `step_on` 게이트만 확장하면 된다.
- TTY 경로(full 기록 재사용) 회귀 테스트 — `script` 로 pty 를 띄우는 방식.
- 드리프트 preflight, Orca 커밋 정책 문서.
- `--dry-run` 시 남은 자산 N건 계산 불가(저널 없음) — 표시만 생략됨.
