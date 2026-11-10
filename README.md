# Fish

Install fisher
```sh
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
```

Install plugins
```sh
fisher install
```

# Secrets

Encrypted in git with [git-crypt](https://github.com/AGWA/git-crypt) (see
`.gitattributes`); the key is in 1Password (`itsme/dotty-git-crypt`).

- `repos.yaml`: encrypted per file, plain locally.
- `asbx/learnings/`: plain and gitignored locally (sandboxes write to it). Git
  only holds `asbx/learnings.tar`, a reproducible tar of it, so filenames stay
  hidden. After changing learnings: `just learnings-pack`, then commit the tar.
  The optional pre-commit hook warns if the tar is stale.

On a fresh clone:
```sh
brew install git-crypt
just unlock         # decrypts, unpacks learnings/
just setup-hooks    # optional: pre-commit warns about a stale tar
```
`just learnings-unpack` after pulling a new tar (refuses if local changes
aren't packed; `just learnings-unpack force` overrides).
