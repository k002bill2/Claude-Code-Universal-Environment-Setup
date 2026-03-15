# Verification Rules

- "아마 될 거예요" 금지 - 실행 증거 필수
- 코드 변경 후 반드시: tsc --noEmit + lint + test 실행
- 같은 수정 2회 실패시 멈추고 근본 원인 분석
- 이전 실행 결과는 증거 불인정 - fresh 실행만 유효
- 빌드 깨진 채 커밋 금지
