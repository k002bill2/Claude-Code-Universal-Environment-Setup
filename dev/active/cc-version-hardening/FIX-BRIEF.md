등급: S
서브에이전트 분할: 불필요(함수 2곳 + 테스트 추가)

# FIX-BRIEF — QA 조건부 PASS 지적 반영 (M-1, L-3~L-5, I-3)

근거: `dev/active/cc-version-hardening/qa/QA-REPORT.md` (커밋 `6519c04`), 재현 `qa/repro.sh`.

## 수정
1. **M-1 (TERM 무시 CLI)** — 타임아웃이 KILL로 승격돼야 한다.
   - `timeout`/`gtimeout` 경로: `-k 1` 추가(`"$tool" -k 1 "$secs" claude --version`). macOS `/usr/bin/timeout`·GNU 모두 `-k` 지원 — `--help`/`man`으로 확인 후 사용.
   - bash 폴백: `_kill_tree` TERM 후 최대 1초(0.2초 × 5) 대기, 살아 있으면 트리 전체 `kill -9`, 그 뒤 `wait`. 무기한 `wait` 금지.
   - 이 경우 rc 는 124 또는 137 이 될 수 있다 → `check_claude_version`에서 **124·137 모두** "응답 없음" WARN으로 처리.
2. **L-3·L-4·L-5 (`CLAUDE_VERSION_TIMEOUT` 정규화)** — 숫자만 허용 후 `10#` 로 10진 변환, 범위 1~300 밖이면 5. 20자리 초과 같은 오버플로 값도 5로(문자열 길이 3 초과면 5로 처리하는 식으로 산술 전에 거른다). `00`→5, `08`→8, `300`→300, `301`→5, `99999999999999999999`→5.
3. **I-3** — 2순위 `v` 접두는 단어 경계일 때만: 줄 처음 또는 영문자가 아닌 문자 뒤의 `v`. `dev2.1.300`은 2순위에서 매칭되지 않고 3순위로 간다(결과는 같아도 규칙을 명확히). `version `/`Version ` 은 그대로.
4. 폴백 경로에서 산술·조기 종료 시에도 임시 파일·백그라운드 프로세스가 남지 않게(정규화로 산술 오류 경로 자체가 사라지는지 확인).

## 테스트 (`tests/test-claude-version.sh`에 추가, 기존 46건 유지)
- TERM 무시 fake(`trap '' TERM; sleep 43; echo 2.1.292`) × 경로 2종(native, `CC_VERSION_FORCE_BASH_TIMEOUT=1`) + `CLAUDE_VERSION_TIMEOUT=1` → 응답 없음 WARN, exit 0, **경과 6초 미만**, 잔존 `sleep 43` 0
- `CLAUDE_VERSION_TIMEOUT` 값 `00`·`08`·`99999999999999999999` (fake `sleep 39; echo 2.1.292`, 폴백 경로 포함) → 산술 오류 문자열(`value too great`) 0, 잔존 0, 각 실효 초(5/8/5)를 WARN 문구 `응답 없음(N초)`로 검증 — `08`은 8초를 기다리므로 `sleep 39` 대신 `sleep 12` 등으로 시간 예산을 지켜라
- `dev2.1.300` → 경고 없음(3순위 결과), `rev2.1.100 2.1.330` → **3순위 첫 토큰 2.1.100 채택 → 경고**(2순위 미매칭 증명)
- 프로세스 잔존 확인은 고유 sleep 값(예: 43, 12)으로 `pgrep -f` — 다른 테스트와 겹치지 않게
- 새 테스트는 sleep 비용이 크므로 전체 파일 실행 시간을 REPORT에 기록(목표 60초 이내)

## 쓰기 경로
`install.sh`(버전 점검 함수들만), `tests/test-claude-version.sh`, `dev/active/cc-version-hardening/REPORT.md`(FIX 절 추가)

## 검증
```
/bin/bash -n install.sh
/bin/bash tests/test-claude-version.sh < /dev/null
/bin/bash tests/test-components.sh < /dev/null
shellcheck install.sh | grep -c '^In '   # 19 유지
/bin/bash dev/active/cc-version-hardening/qa/repro.sh "$PWD"   # M-1·L-3~L-5 행이 기대대로 바뀌었는지 (qa/ 파일은 수정 금지, 출력만 REPORT에 요약)
```
테스트 파일을 서로 병렬 실행하지 말 것.

## 금지
push·PR 금지, 쓰기 경로 밖 수정 금지(특히 `qa/` 산출물), 네트워크 호출 금지. 로컬 커밋 1개(`fix(install): ...`).
