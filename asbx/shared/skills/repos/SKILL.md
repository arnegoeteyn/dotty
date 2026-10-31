---
name: repos
description: Where the user's other repositories/services are on local disk ({{range $i, $r := .Repos}}{{if $i}}, {{end}}{{$r.Name}}{{end}}). Use when the user mentions another repo or service, or asks how code in another service works.
---

# Repositories on disk

These repositories are on local disk in this sandbox. Read them directly at
these paths. Never clone them or fetch them from GitHub to look at them.

| repo | path |
|------|------|
{{- range .Repos}}
| {{.Name}} | `{{.Path}}` |
{{- end}}

- The repo in your current working directory is your private clone. That's
  where you work and commit.
- All the others are read-only, live views of the user's own checkouts. They
  show whatever branch the user currently has checked out there. Don't try to
  edit them.
- To see which branch one is on: `git -C <path> branch --show-current`.
- To see its recent history: `git -C <path> log --oneline -10`.
