등급: S
서브에이전트 분할: 불필요(단일 함수 추가 + 테스트 1파일 + README 1절, 서로 강하게 결합)

# BRIEF — 설치기 최소 Claude Code 버전 경고

## 목적
이 설치기가 배포하는 에이전트는 모델 별칭(`opus`·`sonnet`·`haiku`)을 쓴다. 공식 문서(code.claude.com/docs/en/model-config, 2026-11-19 갱신) 기준:
- Opus 5.5 ≥ v2.1.280, Sonnet 5.5 ≥ v2.1.284, **Haiku 5.5 ≥ v2.1.293**
낮은 버전에서는 `quality-validator`(model: haiku) 같은 에이전트 호출이 "Claude Code does not support this model"로 실패할 수 있다.
→ 설치 시작 시 `claude --version`을 읽어 **2.1.293 미만이면 경고만** 출력한다(설치는 계속).

## 대상 경로 (쓰기 허용)
- `install.sh` — `check_prereqs()`(487행 근처) 안 또는 바로 뒤에 버전 점검 추가
- `tests/test-install.sh` 또는 새 `tests/test-claude-version.sh` (기존 helpers.sh 패턴·샌드박스 HOME 사용)
- `README.md` — 사전 요구 사항(Prerequisites) 절에 최소 버전 1~2줄

## 동작 계약
1. 상수 1개: `MIN_CLAUDE_VERSION="2.1.293"` (근거 주석에 위 문서 URL·모델별 버전).
2. `claude` 명령이 없으면: INFO/WARN 1줄("claude CLI 미발견 — 버전 점검 생략")만, exit 영향 없음.
3. `claude --version` 출력에서 첫 `X.Y.Z`를 추출. 파싱 실패 시 WARN 1줄, 계속.
4. 비교는 숫자 필드별(major/minor/patch) — 문자열 비교 금지(2.1.300 > 2.1.293, 2.1.29 < 2.1.293 처리).
5. 미만이면 `log_warn` 2줄 이내: 현재 버전·최소 버전·`claude update` 안내. **exit 코드·설치 단계는 바뀌지 않는다.**
6. `--dry-run`에서도 경고 출력(읽기 전용이라 무해).
7. bash 3.2 호환(macOS `/bin/bash`), `set -euo pipefail` 아래에서 안전(서브셸·`|| true` 처리).
8. 테스트용으로 실제 claude를 부르지 않도록: PATH 앞에 가짜 `claude` 스크립트를 두는 방식으로 검증.

## 수용 기준 (테스트로 고정)
- 가짜 claude `2.1.292 (Claude Code)` → 경고 출력, exit 0, 설치 산출물 기존과 동일
- `2.1.293` / `2.1.330` / `2.2.0` / `3.0.0` → 경고 없음
- `2.1.29` → 경고 (문자열 비교 회귀 방지)
- claude 미존재 → 생략 메시지, exit 0
- 파싱 불가 출력(`garbage`) → WARN, exit 0
- 기존 테스트 12개 파일 전부 PASS 유지

## 검증 명령 (각 파일 `< /dev/null`, macOS /bin/bash)
```
bash -n install.sh; echo EXIT=$?
for t in <새 버전 테스트> tests/test-components.sh tests/test-profiles.sh; do /bin/bash "$t" < /dev/null > "$TMPDIR/x" 2>&1; echo "$t rc=$? $(grep -E 'RESULT' "$TMPDIR/x")"; done
shellcheck install.sh  # 신규 경고 0 (기존 경고 수와 비교)
```
시간 예산(15분)상 레인은 위 3개만 돌린다. 전체 12개 파일 게이트는 Jarvis가 회수 시 직접 재실행한다(REPORT에 "전체 게이트 미실행 — Jarvis 위임"으로 명시).

## 금지 사항
- 버전 미달 시 exit 1·설치 중단 금지(경고만).
- 네트워크 호출·`claude update` 자동 실행 금지.
- 위 쓰기 경로 밖 파일 수정 금지(특히 `global/`·`docs/`·`project/` 페이로드).
- push·PR 금지. 로컬 커밋 1~2개로 끝낸다(Conventional Commits, 한국어 본문).

## 보고
`dev/active/cc-min-version/REPORT.md`: 변경 파일, 테스트 결과(파일별 PASS/FAIL 수), shellcheck 전후 경고 수, `검증 / 위험·영향 범위 / 되돌리는 법` 3칸.
