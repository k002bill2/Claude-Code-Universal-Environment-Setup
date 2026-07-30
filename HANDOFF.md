# HANDOFF — 통합 설치기(one-shot install) 구현

> 작성: 2026-07-31 (같은 날 2차 갱신).
> 상태: **전체 완료** — 커밋 2건(4ffdf01 본체, 5fad7d0 백로그+2차 리뷰 반영), 워킹트리 클린, 스위트 70/70 PASS. 푸시는 미실행.

## 1. 요청 원문

docs/ 폴더(신규, 미추적)의 내용을 검토해 **폴더 안의 모든 기능까지 한 번의 install로 설치**할 수 있게 구현 (ultracode).

## 2. 설계 결정 (조언자 확정 — 근거: 인벤토리 워크플로우의 갭 12·충돌 13·차단 10 판정)

| 결정 | 내용 |
|------|------|
| 아키텍처 | 루트 install.sh = 오케스트레이터: 글로벌 → 프로젝트 자산 → system-setup 위임 → advisor-worker 위임(--full/--with-advisor) → POST-INSTALL 체크리스트 |
| 비대화형 | read -p 전면 제거. 관리 파일=동일 스킵/변경 시 .bak 후 갱신, 사용자 소유(CLAUDE.md·skill-rules.json·.mcp.json.example)=skip-if-exists. 유일 예외: 플래그 없이 TTY일 때만 프로젝트 경로 질문 |
| model 충돌 해소 | settings.json을 **위임 전에 선생성** → system-setup의 `"model": "claude-sonnet-5"` 강제 주입은 신규 파일에만 발동하므로 구조적으로 차단 (패치 아닌 실행 순서로 해소, install.sh 주석에 명시) |
| 훅 체계 | project/hooks.json **삭제**(Claude Code는 settings.json 훅만 실행 — 사문이었음). 내용은 project/settings-fragments/guardrails.json으로 이식, lib/merge-settings.sh(jq→node 폴백, hooks 이벤트 단위 append+command 멱등, permissions.allow 합집합, 기타 키 기존 값 우선)로 병합 |
| SSOT | docs/ 하위 번들 2종(system-setup·codex-advisor-worker)은 각자의 install.sh heredoc이 정본 — 루트는 **위임 호출만** (내용 복제 금지, 드리프트 방지). advisor-worker 상류는 Agent-System 리포이므로 여기서 수정하지 않음 |
| 유령 스킬 해소 | project/skill-rules.json을 루트가 선점 설치(실제 설치 자산만 참조: feature-planner·verification-loop·verify-implementation·dev-docs) → system-setup의 예시 rules(존재하지 않는 스킬 추천)는 skip-if-exists로 자동 양보 |
| 자산 승격 | Parallel Agents 5종을 명세→완성 md로 저작해 project/agents/에 커밋(설치 시점 LLM 생성 금지). 예시 스킬 7종·에이전트 3종 → examples/(--with-examples 설치), CLAUDE.md 템플릿 7종 → templates/claude-md/(리포 참조용), PM2 → templates/pm2/(--with-pm2로 docs/templates/pm2/ 비파괴 복사) |
| --full 의미 | --with-advisor + --with-examples + --with-pm2 + verify-hooks **조각 파일 설치**(settings 병합은 --with-verify-hooks 명시 시에만 — 언어 특화 훅을 임의 프로젝트에 자동 배선하지 않는 의도적 제한) |
| 범위 제외(v1 계약) | 개념용 훅 4종(stop 자가검증·buildChecker·postToolUseFailure·serviceHealthCheck — 실행형 소스 부재), 플러그인 내용물, 네트워크·세션·계정 결합(codex login·MCP npx·GSD/Gstack) → POST-INSTALL 체크리스트로 출력 |
| 층위 공존 | dev-docs 등 4종이 글로벌 스킬(루트)과 프로젝트 커맨드(system-setup) 양쪽 존재 — 의도적 유지(글로벌=폴백), README에 문서화. 자산 삭제는 요청 범위 밖(Surgical) |

## 3. 변경 파일 (전부 미커밋, `/Users/younghwankang/Work/Claude-Code-Universal-Environment-Setup`)

- **M** `install.sh`(608줄, 전면 재작성) · `README.md`(118줄, 전면 갱신) · `project/agents/code-reviewer.md`(프로토콜 정합 통합)
- **D** `project/hooks.json`
- **신규** `lib/merge-settings.sh`(215줄) · `project/settings-fragments/{guardrails,cli-orchestration,verification-hooks}.json` · `project/skill-rules.json` · `project/agents/{primary-coordinator,code-explorer,code-architect,test-automation-specialist}.md` · `project/mcp.json.example` · `examples/skills/` 7종(+references 스텁) · `examples/agents/` 3종 · `templates/claude-md/` 7종 · `templates/pm2/` 2종 · `tests/test-install.sh`(267줄)
- `docs/`는 사용자가 추가한 원본 — 이번 작업에서 **무수정** (untracked 상태 유지)

## 4. 검증 상태 (증거)

- `tests/test-install.sh` **28/28 PASS** (fresh 실행): A 풀설치 산출물 18항목(model 키 부재 포함), B 멱등성(2회차 내용 해시 diff 0·신규 .bak 0), C dry-run 쓰기 0건, D global-only 프로젝트 미변경. 샌드박스 HOME 격리 + npm/codex PATH 셔임(네트워크 차단), `< /dev/null`로 비TTY 강제
- w1이 자체 발견·수리한 버그 1건: jq `$frag + $orig` 최상위 병합의 키 순서 역전으로 재실행마다 재병합(비멱등) → `reduce`로 기존 키 순서 보존, 3회 실행 멱등 확인
- 워크플로우 run ID(캐시 재개용): 인벤토리 `wf_82a2da2d-f73`, 구현 `wf_24530f6b-c8b`

## 5. Codex 리뷰 관문 결과 (통과 — 지적 4건 전부 반영)

1. **[P1] guardrails python3 의존**: 병합 지점에 `command -v python3` 게이트 — 부재 시 경고+스킵+체크리스트 7번 안내 (하드 실패 없음). 존재/부재 양방향 실측 검증
2. **[P2] 관리 디렉토리 스테일 잔존**: 백업→목적지 제거→재복사 교체 의미론으로 수정. **Red-Green 검증**(수정 되돌리면 Codex 지적 증상 그대로 3 FAIL 재현) + 회귀 테스트 E 8건 추가
3. **[P2×2] mcp.json.example**: filesystem 허용 경로·postgres URI를 env가 아닌 positional args로, npx `-y` 통일
- 최종: `tests/test-install.sh` **36/36 PASS** (A 산출물 18 · B 멱등 4 · C dry-run 3 · D global-only 3 · E 스테일 정리 8). 조언자 승인 완료
- 주의: 관리 디렉토리 교체 의미론으로 docs/templates/pm2/ 등에 사용자가 **추가**한 파일은 재설치 시 .bak로 이동 (README의 관리 파일 정책과 일치하는 의도된 UX)

## 6. 백로그 소진 결과 (2026-07-31 커밋 5fad7d0)

1. ~~커밋~~ → 사용자 승인으로 docs/ 포함 전량 커밋 (4ffdf01)
2. ~~guardrails 영구 테스트~~ → Test A에 python3 게이트 하 영구 어서션 추가
3. ~~개념용 훅 4종~~ → project/hooks/ 실행형 저작 (advisory 계약: 항상 exit 0, jq/pm2 부재 no-op). 배선은 옵트인 유지: verification-hooks 조각(--with-verify-hooks)에 Stop·PostToolUse 편입, pm2-hooks 조각 신설(--with-pm2) — **기본 설치의 settings 배선 불변**
4. ~~references 스텁~~ → 5종 실내용 저작(각 94~120줄, SKILL.md 정합)
- 2차 Codex 리뷰 P2 2건 반영: stop-self-check 스캔 3중 상한(단일 패스·CLAUDE_HOOK_MAX_BYTES 256KB·CLAUDE_HOOK_MAX_SECONDS 3s, Red-Green 검증), api-template GET/POST 분리
- 스위트 36 → **70 어서션 전체 PASS** (Test F: 옵트인 배선·멱등 검증 신설)
- 잔여: **푸시 미실행** (사용자 결정 대기). 알려진 트레이드오프는 stop-self-check.sh 소스 주석 참조(부분 스캔 무음, 시간 상한은 파일 간 검사 — 크기 상한이 백스톱)

## 7. 함정 메모

- 하위 설치기 경로에 공백 2곳: `"docs/Claude code system setup/install.sh"` — 항상 인용
- 1회차 정상 .bak 2개는 기대 동작(cli-orchestration 병합 1 + system-setup 딥머지 1) — 테스트 baseline에 반영됨
- advisor-worker 위임은 `~/.claude/CLAUDE.md` 마커 블록·`~/.codex` 등 글로벌 파급 — 마커 없는 기존 CLAUDE.md는 백업 후 재생성됨(설치기가 경고 출력)
