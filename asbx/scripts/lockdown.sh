#!/usr/bin/env bash
# GitHub is read-only for the sandbox: clone/fetch and API reads are allowed,
# pushes (git-receive-pack, SSH) and API writes are blocked.
set -euo pipefail

S="${SBX_SANDBOX_NAME:?run via sbx env}"

deny() { sbx policy deny network --sandbox "$S" "$@" >/dev/null; }

deny github.com:22,ssh.github.com
deny github.com --method ANY --path "/**/git-receive-pack"
deny api.github.com --method POST,PUT,PATCH,DELETE

sbx exec "$S" sh -c 'git remote remove origin 2>/dev/null || true'
echo "lockdown applied to $S"
