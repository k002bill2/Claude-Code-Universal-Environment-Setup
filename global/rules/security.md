# Security Rules

- SQL 파라미터 바인딩 필수
- 사용자 입력 검증/새니타이징
- 민감 데이터 로깅 금지
- Private key, API key 커밋 금지
- 시크릿은 환경변수 사용 (하드코딩 금지) — 상세는 아래 Secret Management 참조

## 커밋 전 보안 체크리스트

- [ ] XSS 방지 (사용자 입력 이스케이핑)
- [ ] CSRF 보호 활성화
- [ ] Rate limiting 적용
- [ ] 에러 메시지에 민감 정보 미포함
- [ ] 인증/인가 검증 완료

## Security Response Protocol

보안 이슈 발견 시:
1. 즉시 STOP
2. 네이티브 `/security-review` 사용
3. CRITICAL 이슈 수정 전 진행 금지
4. 노출된 시크릿 즉시 교체
5. 유사 이슈 코드베이스 전체 검토

## Secret Management

시크릿은 환경변수로만 읽는다 — 하드코딩 금지, 미설정 시 기동 시점에 명시적으로 throw (조용한 폴백 금지).
