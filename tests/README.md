# tests/

실행: `bash tests/<file>.sh` (macOS `/bin/bash` 3.2, **포그라운드**로 실행할 것).
모든 테스트는 `mktemp` 샌드박스 + `HOME` 오버라이드로만 `install.sh` 를 돌린다 — 실제 `~/.claude` 는 건드리지 않는다.

## 테스트 전용 환경변수 (usage 에는 싣지 않는다)

| 변수 | 의미 |
|------|------|
| `CCUES_FORCE_TTY=1` | stdin TTY 판정만 강제한다(입력은 그대로 stdin 에서 읽음). 첫 설치 메뉴·프로젝트 경로 프롬프트 분기를 파이프 입력으로 태울 때 쓴다. |
| `CCUES_MENU_TIMEOUT=<초>` | 첫 설치 메뉴 `read -t` 타임아웃(기본 60). 타임아웃 → exit 1 경로를 빠르게 검증할 때 쓴다. |

`CI` 가 설정돼 있으면 `CCUES_FORCE_TTY=1` 이어도 메뉴는 뜨지 않는다.

## 파일

- `test-components.sh` — `--components` (단독/합집합/알 수 없는 키/자동 의존/minimal 배타/settings 선생성/기록 재사용)
- `test-menu.sh` — 첫 설치 TTY 메뉴, 미표시 조건, R1 이월(TTY 경로 full 기록 재사용)
- `test-drift.sh` — 글로벌 드리프트 사전 점검(rules/skills WARN, advisor 블록 exit 1, `--force-global`)
- 그 외 `test-*.sh` — R1 이전부터 있던 스위트
