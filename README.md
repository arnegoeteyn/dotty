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

`repos.yaml` and `asbx/learnings/` are encrypted in git with
[git-crypt](https://github.com/AGWA/git-crypt) (see `.gitattributes`); locally
they're plain files. The key is in 1Password (`itsme/dotty-git-crypt`).

On a fresh clone:
```sh
brew install git-crypt
just unlock   # decrypts and installs a pre-commit guard
```
