learnings := "asbx/learnings"
archive := "asbx/learnings.tar"

unlock:
    git-crypt unlock <(op document get dotty-git-crypt --vault itsme)
    just learnings-unpack

setup-hooks:
    git config core.hooksPath .githooks

# Pack learnings/ into the reproducible tar (no-op when nothing changed).
learnings-pack:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    just _tar > "$tmp"
    if cmp -s "$tmp" {{archive}}; then echo "learnings.tar up to date"; else cp "$tmp" {{archive}}; echo "learnings.tar updated"; fi

# Fail if learnings/ and learnings.tar disagree.
learnings-check:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -d {{learnings}} ] || exit 0
    if ! just _tar | cmp -s - {{archive}}; then
        echo "learnings.tar is out of date: run 'just learnings-pack' and stage it" >&2
        exit 1
    fi

# Restore learnings/ from the tar; refuses to overwrite unpacked local changes.
learnings-unpack force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d {{learnings}} ] && [ "{{force}}" != "force" ] && ! just _tar | cmp -s - {{archive}}; then
        echo "learnings/ has changes not in learnings.tar; pack first or run 'just learnings-unpack force'" >&2
        exit 1
    fi
    n=$(tar -tf {{archive}} | wc -l)
    if [ "$n" -eq 0 ]; then echo "{{archive}} is empty; refusing to unpack" >&2; exit 1; fi
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    tar -xmf {{archive}} -C "$tmp"
    mkdir -p {{learnings}}
    # rsync (not rm+mv) so the directory inode stays valid for sandbox mounts
    rsync -a --delete "$tmp"/ {{learnings}}/

# Reproducible tar of learnings/ on stdout: sorted, fixed mtime/owner/mode.
# bsdtar has no --mtime, so normalize a temp copy first.
[private]
_tar:
    #!/usr/bin/env bash
    set -euo pipefail
    work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
    mkdir "$work/files"
    cp -R {{learnings}}/. "$work/files"/
    cd "$work/files"
    find . -name .DS_Store -delete
    find . -type f -exec chmod 644 {} + -exec env TZ=UTC touch -t 197001020000 {} +
    find . -type f | LC_ALL=C sort | sed 's|^\./||' > "$work/list"
    tar -cf "$work/out.tar" --format ustar --uid 0 --gid 0 --uname '' --gname '' \
        --no-mac-metadata --no-xattrs -T "$work/list"
    # bsdtar exits 0 even when it skips files, so verify the archive
    want=$(wc -l < "$work/list"); got=$(tar -tf "$work/out.tar" | wc -l)
    if [ "$got" -eq 0 ] || [ "$want" -ne "$got" ]; then
        echo "tar sanity check failed: $got of $want files archived" >&2
        exit 1
    fi
    cat "$work/out.tar"
