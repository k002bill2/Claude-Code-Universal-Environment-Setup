# Verification Rules

원칙 정전: golden-principles.md (Evidence-Based Completion: 실행 증거 없이 완료 선언 금지).
완료 검증 절차는 네이티브 `superpowers:verification-before-completion` 참조. 이 파일은 고유 절차(Iron Law·Red-Green·코드 상태 검증)에 집중한다.

- 코드 변경 후 게이트: `tsc --noEmit` + lint + test 실행 (이 파일 고유의 구체 게이트 명령)
- 같은 수정 2회 실패시 멈추고 근본 원인 분석
- 이전 실행 결과는 증거 불인정 - fresh 실행만 유효
- 빌드 깨진 채 커밋 금지

## The Iron Law: Gate Function

```
1. IDENTIFY — 이 주장을 증명할 명령어는?
2. RUN      — 전체 명령어 실행 (fresh, complete)
3. READ     — 전체 출력 읽기, exit code 확인, 실패 수 카운트
4. VERIFY   — 출력이 주장을 확인하는가?
              No → 실제 상태를 증거와 함께 보고
              Yes → 증거와 함께 주장
5. CLAIM    — 이제야 결과를 말할 수 있다
```

## Red-Green Verification (TDD)

회귀 테스트와 버그 수정 시 단일 pass로 불충분:
1. 테스트 작성 → 실행 → PASS (테스트 작동 확인)
2. 수정 되돌리기 → 실행 → FAIL (테스트가 버그를 잡는지 확인)
3. 수정 복원 → 실행 → PASS (수정이 버그를 해결하는지 확인)

## 코드 상태 질문 시 검증 필수

스크린샷이나 사용자 제보만으로 코드 상태를 판단 금지. 반드시 Grep/Glob으로 현재 코드베이스를 직접 검색한 후 답변:
- "처리됐나?", "남아있는데?" → 답변 전 Grep/Glob 실행
- 스크린샷의 검색 결과가 어느 디렉토리 기준인지 (메인 레포 vs worktree) 구분
- 외부 정보(스크린샷, 사용자 말)는 힌트일 뿐, 코드 검색 결과가 진실

## Verification Patterns

| 주장 | 필요한 증거 |
|------|------------|
| 테스트 통과 | 테스트 명령 출력: 0 failures |
| 빌드 성공 | 빌드 명령: exit 0 |
| 버그 수정 | 회귀 테스트: pass (Red-Green) |
| 요구사항 충족 | 항목별 체크리스트 검증 |

자신감·"될 거예요"·만족 표현은 증거가 아니다. 검증 명령 출력만이 증거다.
