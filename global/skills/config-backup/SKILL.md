---
name: config-backup
description: Claude Code 설정 백업/복원 시스템 - backup, restore, verify, diff, list 지원
argument-hint: "backup [name] | restore [name] | verify [name] | diff [b1] [b2] | list"
disable-model-invocation: true
---

# Claude Code Config Backup System

설정 백업/복원/검증/비교 시스템.

**저장 위치**: `.claude/backups/` (프로젝트 내)

> 샌드박스 모드에서는 홈 디렉토리(`~/.claude/backups/`) 접근이 제한될 수 있습니다.
> 프로젝트 내 `.claude/backups/`를 기본 사용하며, `.gitignore`에 추가 권장.

## 서브커맨드 라우팅

인자 `$ARGUMENTS`를 파싱:

| 인자 | 동작 | 상세 절차 |
|------|------|----------|
| `backup [name]` | 백업 생성 | [references/create-and-verify.md](references/create-and-verify.md) §1 |
| `verify <name>` | 백업 검증 | [references/create-and-verify.md](references/create-and-verify.md) §2 |
| `list` | 백업 목록 | [references/restore-list-diff.md](references/restore-list-diff.md) §1 |
| `restore <name>` | 백업 복원 | [references/restore-list-diff.md](references/restore-list-diff.md) §2 |
| `diff [b1] [b2]` | 백업 비교 | [references/restore-list-diff.md](references/restore-list-diff.md) §3 |
| (없음) | 도움말 표시 | 아래 |

## 도움말 (인자 없음)

```
📦 Claude Code Config Backup System
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Usage: /config-backup <command> [options]

Commands:
  backup [name]     Create a new backup (optional custom name)
  restore <name>    Restore from a backup
  verify <name>     Verify backup integrity
  diff [b1] [b2]    Compare backups or backup vs current
  list              List all available backups

Options:
  --dry-run         Preview changes without applying (restore, diff)
  --only <path>     Restore specific path only (restore)

Examples:
  /config-backup backup pre-refactor
  /config-backup list
  /config-backup verify 20260111_143022_aos
  /config-backup diff 20260111_143022_aos
  /config-backup restore 20260111_143022_aos --dry-run

Storage: .claude/backups/
```

## 에러 처리

| 에러 | 처리 |
|------|------|
| 백업 디렉토리 없음 | 자동 생성 (`mkdir -p`) |
| 백업명 중복 | 카운터 추가 (`_1`, `_2`) |
| 백업 없음 | 사용 가능한 백업 목록 표시 |
| 검증 실패 | 구체적 실패 항목 표시 |
| 권한 오류 | 경로 및 권한 안내 |

## 백업 디렉토리 구조 (참고)

```
.claude/backups/{BACKUP_NAME}/
├── claude-config.tar.gz       # .claude/ 전체 아카이브
├── checksums.sha256          # 무결성 검증용
├── backup-manifest.json      # 메타데이터 (version, git, stats)
└── quick-reference.txt       # 사람이 읽기 위한 요약
```

복원 시 `settings.local.json`은 항상 보존 (개인 환경설정).
