---
name: git-cleanup
description: Use when the user asks to clean up, prune, or delete git branches or worktrees ("브랜치 정리", "워크트리 정리", "머지된 브랜치 삭제", "stale branches"), especially after squash-merged PRs where `git branch --merged` misses them.
argument-hint: "[--remote] [--base <branch>]"
---

# git-cleanup — 머지된 브랜치·워크트리 정리

`git branch --merged` 는 squash 머지를 못 잡는다. 이 스킬의 스크립트는 ancestor·트리 동일·patch-id·gh PR(MERGED, head SHA 일치) 4가지로 "내용 손실 없음"을 판정하고, 그 판정을 통과한 것만 지운다.

```bash
S=~/.claude/skills/git-cleanup/scripts/git-cleanup.sh
bash "$S" scan                 # 읽기 전용 분류표 (fetch --prune 포함)
bash "$S" apply                # 로컬 브랜치·워크트리만 삭제 (분류를 다시 계산)
bash "$S" apply --remote       # 원격 브랜치까지 삭제
bash "$S" --help               # 옵션: --base, GIT_CLEANUP_NO_GH 등
```

## 절차

1. 대상 레포 루트에서 `scan` 을 실행한다.
2. 결과를 ACTION 별로 묶어 사용자에게 보여준다. `KEEP` 행은 사유(unmerged N commits / dirty / locked)와 함께 보여준다.
3. 삭제 범위를 확인받는다. 원격 브랜치 삭제는 공유 상태를 바꾸므로 `--remote` 포함 여부를 따로 묻는다.
4. 승인 범위대로 `apply` 를 실행한다. 권한 분류기가 거부하면 우회하지 말고, 사용자가 직접 실행할 명령을 준다:
   `! bash ~/.claude/skills/git-cleanup/scripts/git-cleanup.sh apply [--remote]`
5. `scan` 을 다시 실행해 남은 행을 보고한다.

## 출력 해석

| ACTION | 의미 | apply 동작 |
|---|---|---|
| `DELETE local` | 머지 확인된 로컬 브랜치 | `git branch -D` |
| `DELETE remote` | 머지 확인된 원격 브랜치 | `--remote` 일 때만 `git push <remote> --delete` |
| `REMOVE worktree` | clean + 머지된 브랜치의 워크트리 | `git worktree remove` (no `--force`) 후 브랜치 삭제 |
| `PRUNE worktree` | 디렉토리가 사라진 워크트리 | `git worktree prune` |
| `KEEP` | 미머지·dirty·locked·detached | 건드리지 않음 |

보호 대상: 기준 브랜치, `main`/`master`/`develop`, 현재 체크아웃 브랜치, 메인 워크트리.

## 주의

- `KEEP` 을 지우려면 사용자가 브랜치를 지정해 명시적으로 요청해야 한다. 스크립트에 강제 옵션은 없다.
- `~/.claude` 처럼 작업 트리가 곧 라이브 환경인 레포에서는 `apply` 전에 현재 브랜치를 옮기지 않는다.
- 기준이 `origin/HEAD` 가 아니면 `--base <branch>` 로 지정한다.
