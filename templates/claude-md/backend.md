<!-- 출처: docs/Claude code system setup/프로젝트별 템플릿.md (백엔드 API 프로젝트) -->
# Backend API Project Context

## Project Overview
- **Name**: API Service
- **Tech Stack**: Node.js, Express, TypeScript, PostgreSQL
- **Architecture**: RESTful API with layered architecture
- **Authentication**: JWT with refresh tokens
- **Documentation**: OpenAPI 3.0

## API Standards
- RESTful conventions
- Consistent error responses
- Request validation with Zod
- Rate limiting
- API versioning (v1, v2)

## Security Requirements
- Input validation
- SQL injection prevention
- XSS protection
- CORS configuration
- Environment variables for secrets
