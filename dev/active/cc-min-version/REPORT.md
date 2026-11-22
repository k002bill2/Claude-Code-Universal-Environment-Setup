# REPORT — cc-min-version

## 변경 파일
- `install.sh`: `MIN_CLAUDE_VERSION="2.1.293"` + `check_claude_version()` 추가, `check_prereqs()` 끝에서 호출(경고 전용, exit·설치 단계 불변)
- `tests/test-claude-version.sh`: 신규 (가짜 claude PATH 주입, 샌드박스 HOME)
- `README.md`: 사전 요구 절에 최소 버전 안내 1줄

## 테스트 (macOS /bin/bash, < /dev/null)
- test-claude-version.sh: PASS 20 / FAIL 0 / SKIP 0 (2.1.292·2.1.29 경고, 2.1.293/330/2.2.0/3.0.0 무경고, claude 없음, garbage, --dry-run)
- test-components.sh: PASS 74 / FAIL 0
- test-profiles.sh: PASS 83 / FAIL 0
- `bash -n install.sh` EXIT=0
- shellcheck install.sh: 경고 19 → 19 (신규 0)
- 전체 12개 파일 게이트 미실행 — Jarvis 위임

검증: 위 명령 실행. 전체 12개 테스트 파일·실제 claude 바이너스 대상 smoke 미검증.
위험·영향 범위: install.sh check_prereqs 끝에서 호출; 파싱/명령 실패는 `|| true`로 흡수되어 설치 흐름 영향 없음. 모든 설치 실행에 INFO/WARN 1~2줄 추가(기존 출력 단언 테스트가 있다면 영향 가능 — 전체 게이트에서 확인 필요).
되돌리는 법: 이 커밋 `git revert <SHA>` (또는 check_prereqs의 `check_claude_version` 호출 한 줄 삭제).
