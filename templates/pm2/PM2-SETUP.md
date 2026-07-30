<!-- 출처: docs/Claude code system setup/PM2 백엔드 디버깅.md -->
# PM2 셋업 템플릿

> ⚠️ **경고**: 아래 서비스명·경로·포트는 모두 예시값입니다. 실제 프로젝트 구조에 맞게 커스터마이징 필수.
> ecosystem 설정은 `ecosystem.config.example.js`를 `ecosystem.config.js`로 복사 후 수정하세요.

## package.json 스크립트 추가

```json
{
  "scripts": {
    "pm2:start": "pm2 start ecosystem.config.js",
    "pm2:stop": "pm2 stop all",
    "pm2:restart": "pm2 restart all",
    "pm2:delete": "pm2 delete all",
    "pm2:logs": "pm2 logs",
    "pm2:monitor": "pm2 monit",
    "pm2:status": "pm2 list",
    "pm2:save": "pm2 save",
    "pm2:startup": "pm2 startup"
  }
}
```

## 로그 로테이션 설정

```bash
# PM2 로그 로테이션 설치
pm2 install pm2-logrotate

# 설정
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true
```

## CLAUDE.md에 추가할 PM2 섹션

```markdown
## Backend Services

All backend services are managed by PM2:

### Starting Services
\`\`\`bash
pnpm pm2:start  # Start all services
\`\`\`

### Debugging
\`\`\`bash
# Check service status
pm2 list

# View logs for specific service
pm2 logs [service-name] --lines 200

# Restart problematic service
pm2 restart [service-name]
\`\`\`

### Available Services
- api-gateway (port 3000)
- auth-service (port 3001)
- email-service (port 3002)
- notification-service (port 3003)
- database-service (port 3004)
- worker-service (port 3005)
- scheduler (port 3006)
```
