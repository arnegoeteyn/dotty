---
name: pr-review
description: Review a pull request or branch including its PR description, existing reviews and comments, and failing CI checks, not just the code. Use when the user asks to review a PR, a PR number, or a branch (e.g. "review nova-1092", "/pr-review 123").
---

# PR review

Read-only: don't create branches, commit, or post anything to GitHub.
GraphQL is blocked, so never use `gh pr ...`; use the `gh api` REST calls
below. Run them from the repo's working directory so `{owner}/{repo}`
resolves. Use `--jq` to keep output small.

## 1. Find the PR

- Given a number: use it.
- Given a branch (or "my current branch", see
  `git -C /run/sandbox/source branch --show-current`):

      gh api 'repos/{owner}/{repo}/pulls?state=open&per_page=100' \
        --jq '.[] | select(.head.ref == "<branch>") | .number'

- No PR found: say so, and do a code-only review against `host/main`
  (steps 3 and 4, skipping everything PR-related).

## 2. Read the PR context

    gh api repos/{owner}/{repo}/pulls/N \
      --jq '{title, body, state, draft, user: .user.login, base: .base.ref, head: .head.ref, sha: .head.sha}'
    gh api --paginate repos/{owner}/{repo}/pulls/N/reviews \
      --jq '.[] | {user: .user.login, state, body}'
    gh api --paginate repos/{owner}/{repo}/pulls/N/comments \
      --jq '.[] | {id, in_reply_to_id, user: .user.login, path, line, original_line, outdated: (.position == null), body}'
    gh api --paginate repos/{owner}/{repo}/issues/N/comments \
      --jq '.[] | {user: .user.login, body}'

Group inline comments into threads via `in_reply_to_id`.

Failing and pending CI checks on the PR's head commit:

    gh api 'repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100' \
      --jq '.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral") | {id, name, status, conclusion, url: .html_url}'

For a failing check, read its annotations to find the cause:

    gh api repos/{owner}/{repo}/check-runs/<id>/annotations \
      --jq '.[] | {path, start_line, message}'

## 3. Get the code

Fetch base and head. Prefer the user's local branches:

    git fetch /run/sandbox/source +<base>:refs/heads/host/<base>
    git fetch /run/sandbox/source +<head>:refs/heads/host/<head>

If a branch isn't in the user's checkout, fetch it from GitHub instead
(`git` doesn't expand `{owner}/{repo}`, so look it up first):

    repo=$(gh api 'repos/{owner}/{repo}' --jq .full_name)
    git fetch "https://github.com/$repo.git" +refs/pull/N/head:refs/heads/host/<head>
    git fetch "https://github.com/$repo.git" +<base>:refs/heads/host/<base>

Then review `git log host/<base>..host/<head>` and
`git diff host/<base>...host/<head>`. If `host/<head>` differs from the PR's
`sha`, mention it (local commits not pushed yet, or the PR is ahead).

## 4. Review

- **Intent vs change**: does the diff do what the title and body say? Point
  out missing parts, unrelated changes, and claims in the body the code
  doesn't back up.
- **Existing feedback**: for each review thread and comment, decide whether
  it's addressed, still open, or no longer relevant. Don't repeat points
  reviewers already made; refer to them instead.
- **Your own findings**: bugs, edge cases, tests, structure, conventions.
- **CI**: for each failing check, the likely cause and where in the diff.

## 5. Report

1. Summary: what the PR does and your overall verdict.
2. Failing or pending CI checks, with the likely cause.
3. Existing feedback: status per thread or comment (who, where, status).
4. New findings, grouped by severity (blocking, should fix, nit), each with
   `file:line`.
5. Questions for the author.
