# Same key as asbx/justfile; resolved by `op run`.
export GPG_PASSPHRASE := "op://itsme/clanker-learnings/password"

gpg := "gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3"
repos := "repos.yaml"

# Encrypt repos.yaml and everything encrypted in asbx.
encrypt: repos-encrypt
    cd asbx && just encrypt

# Decrypt repos.yaml and everything encrypted in asbx.
decrypt: repos-decrypt
    cd asbx && just decrypt

repos-encrypt:
    #!/usr/bin/env -S op run -- bash -eo pipefail
    {{gpg}} --symmetric --cipher-algo AES256 -o {{repos}}.gpg {{repos}} 3<<<"$GPG_PASSPHRASE"

repos-decrypt:
    #!/usr/bin/env -S op run -- bash -eo pipefail
    {{gpg}} --decrypt -o {{repos}} {{repos}}.gpg 3<<<"$GPG_PASSPHRASE"
