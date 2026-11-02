# Working in this sandbox

You run in an isolated sandbox on a private git clone of the repository.
The user's own checkout (on their machine) is mounted read-only at
`/run/sandbox/source`. Other repositories are mounted read-only at their host
paths, for reference only.

GitHub is read-only for you: cloning, fetching and API reads work (e.g. for
Go modules or looking at another repo), but pushing, adding remotes for
pushing, and API writes are blocked on purpose. Do not try to work around it.
The user fetches your branches from the sandbox to review them.

GraphQL is blocked too (it's always a POST), so `gh pr view/list/diff/checks`
and other GraphQL-based `gh` commands fail with 403. Use REST via `gh api`:

- PR details: `gh api repos/{owner}/{repo}/pulls/N`
- List PRs: `gh api 'repos/{owner}/{repo}/pulls?state=open&per_page=50'`
- Diff: `gh api -H 'Accept: application/vnd.github.diff' repos/{owner}/{repo}/pulls/N`
- Changed files: `gh api --paginate repos/{owner}/{repo}/pulls/N/files`
- Review comments: `gh api --paginate repos/{owner}/{repo}/pulls/N/comments`
- Reviews: `gh api repos/{owner}/{repo}/pulls/N/reviews`
- Conversation comments: `gh api --paginate repos/{owner}/{repo}/issues/N/comments`
- Checks: `gh api repos/{owner}/{repo}/commits/<sha>/check-runs`

Use `--jq` to keep the output small.

## Branches

- `host/<branch>`: a read-only copy of one of the user's branches. Never commit
  to these.
- `agent/<short-description>`: your work. Commits are only allowed on
  `agent/*` branches (a pre-commit hook enforces this).

To get a fresh copy of one of the user's branches:

    git fetch /run/sandbox/source +<branch>:refs/heads/host/<branch>

The user's currently checked-out branch:

    git -C /run/sandbox/source branch --show-current

## When asked to implement or change something

1. Pick the starting point. Default is the user's `main`. If the user names a
   different branch, or says "my current branch", use that instead.
2. Fetch it fresh as `host/<start>` (see above), even if it already exists.
3. Create a new branch before editing anything:
   `git switch -c agent/<short-description> host/<start>`.
4. Commit your work on that branch, checking it as described in
   "Checking your changes" below (targeted tests, then lint before each
   commit).
5. After your last commit, run the full test suite (`just test` /
   `make test`) exactly once. This step is required for every change, even a
   one-line comment; do not skip it or replace it with targeted tests.
6. When done, report the branch name, the starting point, the lint and full
   test suite results, and how to review it. Run `echo $SANDBOX_NAME` to get the sandbox name and put the actual
   value in the commands (don't print the variable):

       git fetch sandbox-<sandbox-name>
       git diff <start>..sandbox-<sandbox-name>/agent/<short-description>

Never commit to `main`, to `host/*`, or on a detached HEAD.

## Checking your changes

These checks are mandatory for every change, however small (comments, docs
and renames included). Never skip them because a change looks trivial.

Use the repo's `justfile` (`just <recipe>`) or, if it has none, its `Makefile`
(`make <recipe>`). Go tests need the `test` build tag (`-tags=test`).

- While working: run only the tests for the packages you changed, e.g.
  `go test -tags=test ./internal/foo/...`. If you changed interfaces, regenerate
  mocks first (`just mocks` / `make mocks`).
- Before every commit: run `lint` and fix what it reports. If
  `bin/golangci-lint` is missing or `.custom-gcl.yml` changed, run
  `preparelint` first.
- Once, when the whole change is done: run the full suite (`test`). It uses
  Docker (testcontainers), which is available in the sandbox. Fix failures you
  caused and report the result.
- If the repo has no `lint` or `test` recipe, say so and skip that step. Don't
  invent one.
- If Docker Hub rate-limits an image pull, tell the user, but keep going with
  the rest of the work.

## When asked to look at one of the user's branches

For example "look at my current branch" or "review nova-1092".

When asked to review, use the `pr-review` skill: it also reads the PR body,
existing comments and CI checks. Otherwise:

1. Fetch it fresh as `host/<branch>`, and fetch `main` as `host/main`.
2. Review it read-only, e.g. `git log host/main..host/<branch>` and
   `git diff host/main...host/<branch>`.
3. Don't create a branch or commit unless the user asks you to change
   something. In that case, follow the steps above with that branch as the
   starting point.

The user commits before asking, so uncommitted changes in their checkout are
out of scope.
