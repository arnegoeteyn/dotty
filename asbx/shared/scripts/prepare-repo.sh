#!/bin/sh
# Runs inside the sandbox after creation: build the repo's custom linter and
# generate mocks, if the repo has those recipes. Best-effort.
cd "$WORKSPACE_DIR" 2>/dev/null || cd "$(git rev-parse --show-toplevel)" || exit 0

if [ -f justfile ] || [ -f Justfile ]; then
  has() { just --summary 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }
  run() { just "$1"; }
elif [ -f Makefile ]; then
  has() { make -qp 2>/dev/null | grep -q "^$1:"; }
  run() { make "$1"; }
else
  echo "prepare-repo: no justfile or Makefile, nothing to do"; exit 0
fi

for recipe in preparelint mocks; do
  if has "$recipe"; then
    echo "prepare-repo: running $recipe"
    run "$recipe" || echo "prepare-repo: WARNING: $recipe failed" >&2
  fi
done
exit 0
