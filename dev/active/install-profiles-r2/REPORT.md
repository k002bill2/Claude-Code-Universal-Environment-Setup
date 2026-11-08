# REPORT — install-profiles R2

## 변경 파일
- `install.sh` — `--components`(17키, 정규화·자동 의존·합집합·minimal 배타·기록), `step_on` 키 단위 게이트, settings 선생성, 첫 설치 TTY 메뉴(`--yes`/`--non-interactive`, `CCUES_FORCE_TTY`/`CCUES_MENU_TIMEOUT` 테스트 훅), 글로벌 드리프트 사전 점검(`--force-global`), 요약 `~/.claude 쓰기: 예/아니오`
- `tests/test-components.sh` (신규 74), `tests/test-menu.sh` (신규 39), `tests/test-drift.sh` (신규 17), `tests/README.md` (신규)
- `README.md` — 개별 선택 표·규칙, full ≠ 모든 키, 첫 설치 메뉴, 드리프트 점검, Flags 3행, "Orca / git worktree 운영" 절
- 커밋: C1 `cb3d062`, C2 `75b2043`, C3 `a026625`, shellcheck `9a863b1`

## 결정 이탈·해석
- 키 수: 브리프 표는 16행이나 `agents / skills` 가 별개 키라 **17키**로 구현.
- 메뉴 3(직접 선택)은 번호·이름을 섞어 받는다. 잘못된 키는 결정 1 규칙대로 즉시 exit 1(재질문은 1~4 선택에만 적용).
- 기록의 `components=` 에 알 수 없는 키가 있으면 조용히 core 로 가지 않고 exit 1(fail-closed).
- 명시(프로필·components·메뉴 중 하나라도)는 기록 전체를 대체(R1 규칙 연장). 기록 minimal 위에 `--components memory-seed` 만 주면 minimal 기반이 아니므로 허용(K7r).
- 드리프트 advisor 비교: `sync-from-live.sh` 에 `--check` 를 추가하지 않고 **5절과 같은 알고리즘을 install.sh 에 읽기 전용으로 구현**(CLAUDE.md 마커 블록 1종). 마커가 아예 없으면 번들 미설치로 보고 드리프트 아님, 앵커 개수 비정상·순서 역전은 드리프트로 간주(차단).
- 드리프트 점검은 `resolve_project_dir` 이후에 돈다 — 존재하지 않는 `--project` 경로는 exit 1 전에 mkdir 될 수 있음(기존 R1 동작과 같은 순서).
- `system-setup` 선생성 `{}` 는 저널(rb_track)로 롤백되지만 `--uninstall` 은 빈 settings.json 을 남길 수 있음(미검증).

## 테스트 결과 (/bin/bash 3.2, 마지막 커밋 `9a863b1` 이후 실행)
| 파일 | 결과 | exit |
|------|------|------|
| test-components.sh | PASS 74 / FAIL 0 | 0 |
| test-drift.sh | PASS 17 / FAIL 0 | 0 |
| test-fragments.sh | PASS 100 / FAIL 0 | 0 |
| test-git-cleanup.sh | PASS 41 / FAIL 0 | 0 |
| test-in-session-cross-review.sh | PASS 306 / FAIL 0 / SKIP 1 | 0 |
| test-install.sh | PASS 92 / FAIL 0 | 0 |
| test-lifecycle.sh | PASS 149 / FAIL 0 (포그라운드) | 0 |
| test-manifest.sh | PASS 24 / FAIL 0 | 0 |
| test-menu.sh | PASS 39 / FAIL 0 | 0 |
| test-merge-settings.sh | PASS 46 / FAIL 0 | 0 |
| test-profiles.sh | PASS 83 / FAIL 0 | 0 |
| test-sync-from-live.sh | PASS 11 / FAIL 0 | 0 |

- lifecycle·cross-review 는 포그라운드 단독, 나머지 10개는 `&` 병렬로 실행.
- `bash -n install.sh` OK. shellcheck `-S warning install.sh`: 17 → 17 (신규 0). 신규 테스트 3개 0건.
- 비TTY/CI 무대기: test-menu M7 — 빈 stdin(`< /dev/null`)에서 CI=1·기록 있음·--yes·--non-interactive·비TTY·--dry-run 전부 exit 0 + 메뉴 미표시(메뉴가 뜨면 EOF 로 exit 1 이 되므로 exit 0 이 증거). 모든 신규 케이스는 `< /dev/null` 또는 유한 파이프 입력.

## RED 증명 (임시 사본에서 되돌림 → FAIL → 사본 삭제, 되돌린 상태 미커밋)
| 대상 | 되돌림 | 결과 |
|------|--------|------|
| test-components | 구현 전 install.sh | FAIL 43 |
| test-menu | C1 install.sh(메뉴 전) | FAIL 22 |
| T1 (R1 이월, TTY 경로 full 재사용) | TTY 경로 뒤 `apply_profile_options` 재호출 제거 | FAIL 3 |
| P11 (FIFO 기록) | 쓰기 전 유형 검사 제거 | FAIL 1 (설치 멈춤) |
| P12 (링크 경로 uninstall) | `managed_path_safe` 검사 제거 | FAIL 1 |
| test-drift | C2 install.sh(점검 전) | FAIL 8 |
| K12 (Codex P2) | 수정 전 | FAIL 2 |

메뉴·드리프트는 구현을 먼저 쓰고 테스트를 붙였으나, 구현 전 install.sh 로 RED 를 사후 확인했다.

## Codex 리뷰 (1회, `review --scope branch --base 9c50914`, C2 시점)
- [P2] `--components commands --with-cross-review` 가 global 없이 cross-review 를 조용히 무시하고 체크리스트는 설치됐다고 안내 → **반영**: core/full/minimal 이 아니고 `global` 키가 없으면 쓰기 전 exit 1. 회귀 K12 RED(FAIL 2) → GREEN.
- 그 외 지적 없음. C3(드리프트·README)는 리뷰 이후 커밋이라 Codex 미검토.

## 남은 일
- advisor heredoc 3종 중 **CLAUDE.md 블록만** 점검. 훅 JS(`ADVCTXJS`)·statusline 브리지(`CTXBRIDGE`) 드리프트 점검은 미구현 — `sync-from-live.sh` 의 `sync_heredoc_block` 을 읽기 전용 `--check` 로 노출하는 방식 권장.
- C3 변경분(드리프트 점검)에 대한 Codex 재리뷰.
- `--uninstall` 이 선생성 `{}` settings.json 을 정리하는지 확인.
- `--dry-run` 시 남은 자산 N건 표시 생략(R1 이월, 그대로).
