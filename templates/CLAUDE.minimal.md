# CLAUDE.md

<!-- 이 프로젝트가 무엇인지 2~3줄로 적으세요: 목적, 주요 스택, 진입점. -->

## Commands

| 용도 | 명령 |
|------|------|
| install | @@install@@ |
| dev | @@dev@@ |
| test | @@test@@ |
| lint | @@lint@@ |
| build | @@build@@ |

## Do not

- git push 등 원격 쓰기는 사람이 승인한 뒤에만 실행한다.
- 비밀값(API 키, 토큰, .env)을 커밋하지 않는다.

## 검증

작업을 마쳤다고 말하기 전에 `/verify-app` 으로 테스트·린트·빌드를 실행해 확인한다.
