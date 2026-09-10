#!/usr/bin/env python3
# ============================================================================
# safe-fs.py — 관리 루트 안에서만 도는 심볼릭 링크 안전 파일 연산
# ----------------------------------------------------------------------------
# 계약: docs/plans/2026-09-09-global-in-session-cross-review.md §7.3.3
#
# **존재 이유.** bash 에는 openat/unlinkat/O_NOFOLLOW 가 없다. 그래서 순수 bash 로는
# "경로를 검사한 뒤 그 경로로 연산" 하는 형태밖에 만들 수 없고, 검사와 연산 사이에
# 조상 디렉터리가 링크로 바뀌면 연산이 링크 너머로 간다(TOCTOU). 실측으로 확인된
# 피해는 두 가지다:
#   - 삭제: `rm -rf <task>/run.<hex>` 가 관리 루트 밖 항목을 지운다.
#   - 쓰기: `mv tmp <task>/state.tsv` 가 관리 루트 밖에 파일을 만든다.
#           (경합 테스트 X43 에서 피해자 디렉터리에 state.tsv 가 실제로 생겼다.)
#
# **해법.** 루트에서 시작해 경로 성분을 하나씩 `O_NOFOLLOW|O_DIRECTORY` 로 열어
# 내려가고, 마지막 연산은 그렇게 고정(pin)된 부모 디렉터리 **fd 기준**으로 한다.
# 검사와 사용이 같은 syscall 이므로 "검사 후 스왑" 창이 존재하지 않는다:
#   - 스왑이 walk 보다 먼저면 → 그 성분이 링크라 open 이 ELOOP 로 실패한다.
#   - 스왑이 walk 보다 나중이면 → 이미 실제 inode 에 fd 가 걸려 있어 영향이 없다.
# 어느 쪽도 링크 너머로 재지향되지 않는다.
#
# **fail closed.** 이 헬퍼가 없거나 python3 가 없으면 호출자(review-state.sh)는
# 연산을 조용히 건너뛰지 않고 BLOCKED 로 끝낸다. 안전하게 쓸 수 없으면 쓰지 않는다.
#
# **<root> 는 신뢰 접두부다** (기본: `$CLAUDE_CONFIG_DIR`/`~/.claude` 같은 사용자 홈).
# root 자체는 일반 open 으로 열지만, 그 **아래의 모든 성분**(`state`, `cross-review`,
# 샤드, task, run …)은 O_NOFOLLOW 로 걸어 내려간다. 즉 관리 대상 성분 중 하나라도
# 링크면 거부한다. 예전에는 root 를 `<home>/state/cross-review` 로 잡아서 `state`·
# `cross-review` 자체가 링크여도 그냥 따라갔다 — 그 두 성분이 관리 경계 안인데도
# 검사 대상이 아니었다.
#
# 사용법 (전부 <root> 기준 상대경로. 절대경로·`..`·빈 성분은 거부):
#   safe-fs.py mkdir    <root> <rel>     디렉터리 생성 (이미 있으면 실패 — O_EXCL 상당)
#   safe-fs.py mkdirp   <root> <rel>     디렉터리 보장 (있으면 성공, 링크면 실패)
#   safe-fs.py write    <root> <rel> [max]  stdin → 새 파일 (O_CREAT|O_EXCL|O_NOFOLLOW)
#                                        max 지정 시 **스트리밍 중** 초과하면 중단하고
#                                        부분 파일을 삭제한다 (사후 검사가 아니다)
#   safe-fs.py chmod700 <root> <rel>     pinned fd 로 fchmod 0700 (경로 chmod 금지)
#   safe-fs.py replace  <root> <rel>     stdin → 원자적 교체 (임시파일 + renameat)
#   safe-fs.py read     <root> <rel>     파일 → stdout (링크면 실패)
#   safe-fs.py unlink   <root> <rel>     일반 파일 하나 삭제 (링크면 링크만 삭제)
#   safe-fs.py rmtree   <root> <rel>     디렉터리 트리 삭제 (링크는 따라가지 않음)
#   safe-fs.py isfile   <root> <rel>     일반 파일이면 exit 0
#   safe-fs.py nolink   <root> <rel>     없거나 링크가 아니면 exit 0 (정책 검사용)
#   safe-fs.py age      <root> <rel>     mtime 으로부터 경과 초를 stdout (없으면 exit 1)
#   safe-fs.py rename   <root> <rel> <rel2>  renameat 으로 원자적 이동 (둘 다 pinned fd)
#   safe-fs.py touch    <root> <rel>     링크를 따르지 않고 파일을 있게 한다 (없으면 생성)
#   safe-fs.py flockfd  <root> <rel> <fd>  **호출자가 연 fd** 에 flock(LOCK_EX|LOCK_NB).
#                                        fd 가 그 경로의 그 파일인지 (dev,ino) 로 대조한
#                                        뒤에만 잠근다. 잠금은 호출자의 OFD 에 남으므로
#                                        이 프로세스가 끝나도 유지된다 (상주 헬퍼 없음).
#                                        성공 "OK", 점유 중 "BUSY" + exit 1.
#   safe-fs.py listdir  <root> <rel>     항목 이름을 NUL 구분으로 stdout
#
# 종료 코드: 0 성공 · 1 실패(안전하지 않거나 없음) · 2 max-bytes 초과. stderr 에 짧은 사유.
# ============================================================================
import errno
import os
import sys

WALK_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_DIRECTORY
if hasattr(os, "O_CLOEXEC"):
    WALK_FLAGS |= os.O_CLOEXEC


EXIT_FAIL = 1
EXIT_TOO_BIG = 2      # 스트리밍 중 max-bytes 초과 (호출자가 사유를 구분해야 한다)


def die(msg, code=EXIT_FAIL):
    sys.stderr.write("safe-fs: %s\n" % msg)
    sys.exit(code)


def split_rel(rel):
    """상대경로를 성분으로 쪼갠다. 조금이라도 수상하면 거부한다."""
    if rel.startswith("/"):
        die("relative path required: %r" % rel)
    parts = [p for p in rel.split("/") if p != ""]
    if not parts:
        die("empty relative path")
    for p in parts:
        if p in (".", ".."):
            die("path traversal component: %r" % rel)
        if "\0" in p:
            die("NUL in path")
    return parts


def open_root(root):
    """관리 루트를 연다. 루트 자체가 링크면 거부한다."""
    try:
        return os.open(root, WALK_FLAGS)
    except OSError as e:
        die("cannot open root %r: %s" % (root, e.strerror))


def walk_parent(root, rel):
    """<root>/<rel> 의 **부모**까지 O_NOFOLLOW 로 내려간다.

    반환: (parent_fd, leaf_name). 호출자가 parent_fd 를 닫는다.
    성분 중 하나라도 링크면 ELOOP 로 실패한다 — 그것이 이 함수의 요점이다.
    """
    parts = split_rel(rel)
    fd = open_root(root)
    try:
        for comp in parts[:-1]:
            try:
                nxt = os.open(comp, WALK_FLAGS, dir_fd=fd)
            except OSError as e:
                if e.errno in (errno.ELOOP, errno.EMLINK):
                    die("symlinked ancestor %r in %r" % (comp, rel))
                die("cannot descend into %r: %s" % (comp, e.strerror))
            os.close(fd)
            fd = nxt
    except BaseException:
        os.close(fd)
        raise
    return fd, parts[-1]


def cmd_mkdir(root, rel):
    """마지막 성분을 **배타적으로** 만든다. 이미 있으면(링크 포함) 실패한다."""
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            os.mkdir(leaf, 0o700, dir_fd=fd)
        except FileExistsError:
            die("already exists: %r" % rel)
        except OSError as e:
            die("cannot mkdir %r: %s" % (rel, e.strerror))
    finally:
        os.close(fd)


def cmd_mkdirp(root, rel):
    """`mkdir -p` 상당. 중간 성분까지 전부 만들되, **성분마다 O_NOFOLLOW** 로 연다.

    이미 있는 성분이 링크면 거기서 실패한다 — 링크를 조용히 따라가지 않는다.
    """
    parts = split_rel(rel)
    fd = open_root(root)
    try:
        for comp in parts:
            try:
                nxt = os.open(comp, WALK_FLAGS, dir_fd=fd)
            except OSError as e:
                if e.errno != errno.ENOENT:
                    die("not a usable directory: %r in %r (%s)" % (comp, rel, e.strerror))
                try:
                    os.mkdir(comp, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                except OSError as e2:
                    die("cannot mkdir %r in %r: %s" % (comp, rel, e2.strerror))
                try:
                    nxt = os.open(comp, WALK_FLAGS, dir_fd=fd)
                except OSError as e2:
                    die("cannot open created %r: %s" % (comp, e2.strerror))
            os.close(fd)
            fd = nxt
    finally:
        os.close(fd)


def _open_new(fd, name):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    return os.open(name, flags, 0o600, dir_fd=fd)


def _write_all(fd, buf):
    """`write(2)` 는 **짧은 쓰기**가 허용된다(자원 압박 등). 그것을 무시하면 뒷부분이
    조용히 잘린 채 성공으로 보고되고, 잘린 동결 diff 의 해시로 PASS 가 난다."""
    view = memoryview(buf)
    while view:
        n = os.write(fd, view)
        if n <= 0:
            die("short write: no progress")
        view = view[n:]


def _pump(out_fd):
    src = sys.stdin.buffer
    while True:
        chunk = src.read(65536)
        if not chunk:
            break
        _write_all(out_fd, chunk)


def cmd_write(root, rel, max_bytes=None):
    """새 파일을 만들고 stdin 을 흘려 넣는다.

    max_bytes 가 있으면 **쓰는 중에** 한도를 검사한다. 프로세스가 끝난 뒤 크기를 재는
    방식은 이미 한도를 넘긴 바이트가 디스크에 다 올라간 뒤이므로 상한이 아니다.
    초과하면 부분 파일을 지우고 실패한다.
    """
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            out = _open_new(fd, leaf)
        except FileExistsError:
            die("refusing to overwrite existing entry: %r" % rel)
        except OSError as e:
            die("cannot create %r: %s" % (rel, e.strerror))
        total = 0
        try:
            src = sys.stdin.buffer
            while True:
                chunk = src.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                if max_bytes is not None and total > max_bytes:
                    os.close(out)
                    out = None
                    try:
                        os.unlink(leaf, dir_fd=fd)
                    except OSError:
                        pass
                    die("exceeds max bytes (%d) while streaming: %r" % (max_bytes, rel),
                        EXIT_TOO_BIG)
                _write_all(out, chunk)
        finally:
            if out is not None:
                os.close(out)
    finally:
        os.close(fd)


def cmd_chmod700(root, rel):
    """pinned fd 로 fchmod 한다. 경로 기반 chmod 는 링크를 따라가 남의 파일 모드를 바꾼다."""
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            target = os.open(leaf, WALK_FLAGS, dir_fd=fd)
        except OSError as e:
            die("cannot open %r for chmod: %s" % (rel, e.strerror))
        try:
            os.fchmod(target, 0o700)
        except OSError as e:
            die("cannot fchmod %r: %s" % (rel, e.strerror))
        finally:
            os.close(target)
    finally:
        os.close(fd)


def cmd_replace(root, rel):
    """임시 이름으로 쓰고 renameat 으로 갈아끼운다. 둘 다 같은 pinned fd 기준이다."""
    fd, leaf = walk_parent(root, rel)
    tmp = ".%s.%d.tmp" % (leaf, os.getpid())
    try:
        try:
            os.unlink(tmp, dir_fd=fd)
        except OSError:
            pass
        try:
            out = _open_new(fd, tmp)
        except OSError as e:
            die("cannot create temp for %r: %s" % (rel, e.strerror))
        try:
            _pump(out)
        finally:
            os.close(out)
        try:
            os.rename(tmp, leaf, src_dir_fd=fd, dst_dir_fd=fd)
        except OSError as e:
            try:
                os.unlink(tmp, dir_fd=fd)
            except OSError:
                pass
            die("cannot replace %r: %s" % (rel, e.strerror))
    finally:
        os.close(fd)


def cmd_read(root, rel):
    fd, leaf = walk_parent(root, rel)
    try:
        flags = os.O_RDONLY | os.O_NOFOLLOW
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        try:
            src = os.open(leaf, flags, dir_fd=fd)
        except OSError as e:
            die("cannot read %r: %s" % (rel, e.strerror))
        try:
            st = os.fstat(src)
            if not os.path.stat.S_ISREG(st.st_mode):
                die("not a regular file: %r" % rel)
            while True:
                chunk = os.read(src, 65536)
                if not chunk:
                    break
                sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
        finally:
            os.close(src)
    finally:
        os.close(fd)


def cmd_unlink(root, rel):
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            os.unlink(leaf, dir_fd=fd)
        except FileNotFoundError:
            pass
        except IsADirectoryError:
            die("is a directory: %r" % rel)
        except OSError as e:
            die("cannot unlink %r: %s" % (rel, e.strerror))
    finally:
        os.close(fd)


def _rmtree_at(parent_fd, name):
    """parent_fd 기준으로 name 을 지운다. 링크는 따라가지 않고 링크만 끊는다."""
    try:
        sub = os.open(name, WALK_FLAGS, dir_fd=parent_fd)
    except OSError as e:
        # 디렉터리가 아니거나(ENOTDIR) 링크(ELOOP)면 항목 자체만 지운다.
        if e.errno in (errno.ENOTDIR, errno.ELOOP, errno.EMLINK):
            try:
                os.unlink(name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
            return
        if e.errno == errno.ENOENT:
            return
        die("cannot open %r: %s" % (name, e.strerror))
    try:
        for entry in os.listdir(sub):
            _rmtree_at(sub, entry)
    finally:
        os.close(sub)
    try:
        os.rmdir(name, dir_fd=parent_fd)
    except FileNotFoundError:
        pass
    except OSError as e:
        die("cannot rmdir %r: %s" % (name, e.strerror))


def cmd_rmtree(root, rel):
    fd, leaf = walk_parent(root, rel)
    try:
        _rmtree_at(fd, leaf)
    finally:
        os.close(fd)


def cmd_isfile(root, rel):
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            st = os.stat(leaf, dir_fd=fd, follow_symlinks=False)
        except OSError:
            sys.exit(1)
        if not os.path.stat.S_ISREG(st.st_mode):
            sys.exit(1)
    finally:
        os.close(fd)


def cmd_nolink(root, rel):
    """정책 검사 전용. **보안 통제가 아니다** — 실제 안전은 pinned fd 연산이 진다.
    (링크 위에 replace 를 해도 renameat 은 링크를 따라가지 않고 링크를 갈아끼운다.)
    운영자가 심어둔/잘못 놓인 링크를 조용히 덮지 않고 드러내기 위한 것이다."""
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            st = os.stat(leaf, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        except OSError as e:
            die("cannot stat %r: %s" % (rel, e.strerror))
        if os.path.stat.S_ISLNK(st.st_mode):
            die("symlink in managed output path: %r" % rel)
    finally:
        os.close(fd)


def cmd_touch(root, rel):
    """링크를 따라가지 않고 파일을 **있게** 한다 (없으면 생성, 있으면 그대로).

    잠금 파일을 셸이 직접 열기(`exec 9>>`) 전에 먼저 안전하게 만들어 둔다. 셸의
    리다이렉션은 링크를 따라가므로, 존재하지 않는 경로를 셸이 처음 만들게 두면
    미리 심어 둔 링크의 **대상**이 만들어진다.
    """
    fd, leaf = walk_parent(root, rel)
    try:
        flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        try:
            lf = os.open(leaf, flags, 0o600, dir_fd=fd)
        except OSError as e:
            die("cannot touch %r: %s" % (rel, e.strerror))
        os.close(lf)
    finally:
        os.close(fd)


def cmd_flockfd(root, rel, fd_s):
    """**호출자가 이미 연 fd** 에 flock(LOCK_EX|LOCK_NB) 을 건다.

    왜 이 형태인가. 잠금을 별도 상주 헬퍼가 잡으면, 그 헬퍼가 리뷰보다 먼저 죽는
    순간 커널은 잠금을 놓는데 리뷰는 그것을 모른 채 상태를 계속 고친다. PID 를
    폴링해도 그 창은 닫히지 않고 PID 재사용이라는 새 구멍을 만든다.

    flock 은 **열린 파일 기술(OFD)** 에 걸린다. 그래서 리뷰 셸이 연 fd 를 물려받아
    여기서 잠그면, 이 프로세스가 끝나도 셸이 그 fd 를 들고 있는 한 잠금이 유지되고,
    셸이 죽으면 커널이 해제한다 — 감시할 보조 프로세스 자체가 없어진다.

    fd 가 **정말 그 경로의 그 파일인지** 대조한 뒤에만 잠근다. 셸 리다이렉션은
    링크를 따라가므로, 안전 walk 로 연 파일과 (dev, ino) 가 같은지 확인해야
    바꿔치기된 fd 를 잠그지 않는다.
    """
    import fcntl
    try:
        fd_n = int(fd_s)
    except (TypeError, ValueError):
        die("flockfd needs an fd number: %r" % fd_s)
    if fd_n < 0:
        die("flockfd needs an fd number: %r" % fd_s)
    try:
        st_caller = os.fstat(fd_n)
    except OSError as e:
        die("cannot stat fd %d: %s" % (fd_n, e.strerror))
    dfd, leaf = walk_parent(root, rel)
    try:
        flags = os.O_RDWR | os.O_NOFOLLOW
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        try:
            ref = os.open(leaf, flags, dir_fd=dfd)
        except OSError as e:
            die("cannot open lock %r: %s" % (rel, e.strerror))
    finally:
        os.close(dfd)
    try:
        st_ref = os.fstat(ref)
    finally:
        os.close(ref)
    if (st_caller.st_dev, st_caller.st_ino) != (st_ref.st_dev, st_ref.st_ino):
        die("lock fd does not refer to %r (swapped)" % rel)
    if not os.path.stat.S_ISREG(st_caller.st_mode):
        die("lock fd is not a regular file")
    try:
        fcntl.flock(fd_n, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.stdout.write("BUSY\n")
        sys.stdout.flush()
        sys.exit(1)
    # **잠근 뒤 경로를 다시 대조한다.** 대조와 flock 사이에 같은 사용자가 경로를
    # 다른 파일로 바꾸면, 우리는 이미 이름이 떨어져 나간 옛 inode 를 잠그고 다음
    # 실행은 새 inode 를 잠가 **둘 다 소유자라고 믿는다**. 사후 대조를 넣으면 그
    # 창에서 바뀐 쪽이 잠금을 놓고 실패하므로, 스왑이 조용히 통과하지 못한다.
    dfd2, leaf2 = walk_parent(root, rel)
    try:
        try:
            ref2 = os.open(leaf2, flags, dir_fd=dfd2)
        except OSError as e:
            fcntl.flock(fd_n, fcntl.LOCK_UN)
            die("lock path vanished after flock (%r): %s" % (rel, e.strerror))
    finally:
        os.close(dfd2)
    try:
        st_ref2 = os.fstat(ref2)
    finally:
        os.close(ref2)
    if (st_ref2.st_dev, st_ref2.st_ino) != (st_caller.st_dev, st_caller.st_ino):
        fcntl.flock(fd_n, fcntl.LOCK_UN)
        die("lock path swapped during flock (%r)" % rel)
    # 잠금은 호출자의 OFD 에 남는다. 이 프로세스가 끝나도 풀리지 않는다.
    sys.stdout.write("OK\n")
    sys.stdout.flush()


def cmd_rename(root, rel, rel2):
    """renameat 으로 원자적으로 옮긴다. 양쪽 부모를 각각 O_NOFOLLOW 로 pin 한다.

    **stale lock 인수(takeover)의 핵심.** "나이를 보고 → 지우고 → 다시 만든다" 는
    다단계라 두 경쟁자가 모두 통과해 **둘 다 소유자라고 믿는** 상태를 만든다.
    rename 은 원자적이라 그 디렉터리를 옮기는 데 성공하는 쪽이 정확히 하나다.
    """
    fd, leaf = walk_parent(root, rel)
    try:
        fd2, leaf2 = walk_parent(root, rel2)
        try:
            try:
                os.rename(leaf, leaf2, src_dir_fd=fd, dst_dir_fd=fd2)
            except OSError as e:
                die("cannot rename %r -> %r: %s" % (rel, rel2, e.strerror))
        finally:
            os.close(fd2)
    finally:
        os.close(fd)


def cmd_age(root, rel):
    """pinned fd 로 fstat 해서 mtime 경과 초를 낸다.

    `stat` 은 BSD(`-f %m`)와 GNU(`-c %Y`) 플래그가 달라 셸에서 이식성이 없다.
    잠금 회수(stale lock)의 판정 근거이므로 여기서 한 번에 처리한다.
    """
    import time
    fd, leaf = walk_parent(root, rel)
    try:
        try:
            st = os.stat(leaf, dir_fd=fd, follow_symlinks=False)
        except OSError:
            sys.exit(1)
        age = int(time.time() - st.st_mtime)
        if age < 0:
            age = 0
        sys.stdout.write("%d\n" % age)
    finally:
        os.close(fd)


def cmd_listdir(root, rel):
    parts = split_rel(rel)
    fd = open_root(root)
    try:
        for comp in parts:
            try:
                nxt = os.open(comp, WALK_FLAGS, dir_fd=fd)
            except OSError:
                sys.exit(1)
            os.close(fd)
            fd = nxt
        out = sys.stdout.buffer
        for entry in os.listdir(fd):
            out.write(entry.encode("utf-8", "surrogateescape") + b"\0")
        out.flush()
    finally:
        os.close(fd)


def main(argv):
    if len(argv) < 4:
        die("usage: safe-fs.py <op> <root> <rel> [max-bytes]")
    op, root, rel = argv[1], argv[2], argv[3]
    max_bytes = None
    if op not in ("rename", "flockfd") and len(argv) > 4 and argv[4] != "":
        try:
            max_bytes = int(argv[4])
        except ValueError:
            die("max-bytes must be an integer: %r" % argv[4])
        if max_bytes < 0:
            die("max-bytes must be >= 0")
    ops = {
        "mkdir": lambda: cmd_mkdir(root, rel),
        "mkdirp": lambda: cmd_mkdirp(root, rel),
        "chmod700": lambda: cmd_chmod700(root, rel),
        "write": lambda: cmd_write(root, rel, max_bytes),
        "replace": lambda: cmd_replace(root, rel),
        "read": lambda: cmd_read(root, rel),
        "unlink": lambda: cmd_unlink(root, rel),
        "rmtree": lambda: cmd_rmtree(root, rel),
        "isfile": lambda: cmd_isfile(root, rel),
        "nolink": lambda: cmd_nolink(root, rel),
        "age": lambda: cmd_age(root, rel),
        "rename": lambda: cmd_rename(root, rel, argv[4] if len(argv) > 4 else die("rename needs <rel2>")),
        "touch": lambda: cmd_touch(root, rel),
        "flockfd": lambda: cmd_flockfd(root, rel, argv[4] if len(argv) > 4 else die("flockfd needs <fd>")),
        "listdir": lambda: cmd_listdir(root, rel),
    }
    fn = ops.get(op)
    if fn is None:
        die("unknown op: %r" % op)
    fn()


if __name__ == "__main__":
    main(sys.argv)
