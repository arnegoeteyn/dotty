unlock: setup-hooks
    git-crypt unlock <(op document get dotty-git-crypt --vault private)

# Pre-commit hook: refuse to commit if a file that should be encrypted isn't.
setup-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    hook="$(git rev-parse --git-path hooks)/pre-commit"
    printf '#!/bin/sh\ngit-crypt status -e >/dev/null 2>&1 || { git-crypt status -e; echo "git-crypt: unencrypted file(s) staged, aborting" >&2; exit 1; }\n' > "$hook"
    chmod +x "$hook"
