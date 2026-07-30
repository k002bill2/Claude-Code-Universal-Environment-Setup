// 출처: docs/Claude code system setup/PM2 백엔드 디버깅.md
// 경고: 서비스명·경로(cwd)·포트는 예시값입니다. 실제 프로젝트에 맞게 커스터마이징 필수.
module.exports = {
  apps: [
    {
      name: 'api-gateway',
      script: 'npm',
      args: 'start',
      cwd: './api-gateway',
      error_file: './api-gateway/logs/error.log',
      out_file: './api-gateway/logs/out.log',
      merge_logs: true,
      time: true,
      env: {
        NODE_ENV: 'development',
        PORT: 3000
      }
    },
    {
      name: 'auth-service',
      script: 'npm',
      args: 'start',
      cwd: './auth',
      error_file: './auth/logs/error.log',
      out_file: './auth/logs/out.log',
      merge_logs: true,
      time: true,
      env: {
        NODE_ENV: 'development',
        PORT: 3001
      }
    },
    {
      name: 'email-service',
      script: 'npm',
      args: 'start',
      cwd: './email',
      error_file: './email/logs/error.log',
      out_file: './email/logs/out.log',
      merge_logs: true,
      time: true,
      env: {
        NODE_ENV: 'development',
        PORT: 3002,
        SMTP_HOST: 'smtp.gmail.com'
      }
    },
    {
      name: 'notification-service',
      script: 'npm',
      args: 'start',
      cwd: './notification',
      error_file: './notification/logs/error.log',
      out_file: './notification/logs/out.log',
      merge_logs: true,
      time: true,
      instances: 2,  // 클러스터 모드
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'development',
        PORT: 3003
      }
    },
    {
      name: 'database-service',
      script: 'npm',
      args: 'start',
      cwd: './database',
      error_file: './database/logs/error.log',
      out_file: './database/logs/out.log',
      merge_logs: true,
      time: true,
      env: {
        NODE_ENV: 'development',
        PORT: 3004,
        DATABASE_URL: process.env.DATABASE_URL
      }
    },
    {
      name: 'worker-service',
      script: 'npm',
      args: 'start',
      cwd: './worker',
      error_file: './worker/logs/error.log',
      out_file: './worker/logs/out.log',
      merge_logs: true,
      time: true,
      max_restarts: 10,
      min_uptime: '10s',
      env: {
        NODE_ENV: 'development',
        PORT: 3005
      }
    },
    {
      name: 'scheduler',
      script: 'npm',
      args: 'start',
      cwd: './scheduler',
      error_file: './scheduler/logs/error.log',
      out_file: './scheduler/logs/out.log',
      merge_logs: true,
      time: true,
      cron_restart: '0 0 * * *',  // 매일 자정 재시작
      env: {
        NODE_ENV: 'development',
        PORT: 3006
      }
    }
  ]
};
