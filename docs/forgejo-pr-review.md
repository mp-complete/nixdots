# Automated PR review on Forgejo

Two workflows review pull requests against this repo. They run on the
self-hosted runner (`euler`, `modules/service/forgejo-runner.nix`) using the
`native:host` label, so nix evaluation reuses the host's store instead of
re-bootstrapping nix inside a container on every run.

| workflow | what it does | gates merge? |
| --- | --- | --- |
| `.forgejo/workflows/pr-check.yml` | `nix fmt -- --ci` + `nix flake check --no-build`, then posts an `APPROVE` / `REQUEST_CHANGES` review | yes, with branch protection |
| `.forgejo/workflows/pr-ai-review.yml` | sends the PR diff to an OpenAI-compatible endpoint, posts the result as a `COMMENT` review | no — advisory only |

`flake-update.yml` is unchanged: the weekly lock bump still pushes straight to
`main` and is not reviewed.

## Why the split

The deterministic job is the only thing allowed to block a merge. The model job
is deliberately incapable of it — it can only leave a comment — so a bad model
response, an expired API key, or an outage can never wedge the merge button.

## Setup

### 1. Bot account

Create a second Forgejo user (e.g. `forgejo-bot`) and give it write access to
the repo. Two reasons a bot account is required rather than your own PAT:

- Forgejo will not count an approval from the PR's author, so a review posted
  as you is inert on your own PRs.
- The built-in `GITHUB_TOKEN` cannot trigger further workflow runs and cannot
  cast an approval that satisfies branch protection.

Generate a PAT for that account (`<instance>/user/settings/applications`) with
`write:repository` scope.

### 2. Install the Actions secrets

The workflows read these from Forgejo repo secrets
(`<instance>/miles/nixdots/settings/actions/secrets`):

| secret | required | used by |
| --- | --- | --- |
| `FORGEJO_BOT_TOKEN` | yes | both — posting reviews |
| `OPENAI_API_KEY` | no | `pr-ai-review.yml` (skips itself if absent) |

Optional Actions *variables* (same settings page) tune the model without
editing YAML: `AI_REVIEW_MODEL` (default `gpt-4.1-mini`) and
`AI_REVIEW_BASE_URL` (default `https://api.openai.com/v1`, so any
OpenAI-compatible endpoint works).

You can paste both values in by hand and stop here. If you'd rather keep sops
as the single source of truth, see [Secrets handling](#secrets-handling) below.

### 3. Branch protection

`<instance>/miles/nixdots/settings/branches` → protect `main`:

- **Enable status check** → require `pr-check / check`.
- **Required approvals**: 1, and add the bot to the allowed-approvers whitelist.
- **Dismiss stale approvals** on new commits, so a green review can't carry
  over onto a later push.

Leave "Block on rejected reviews" on — that's what turns a `REQUEST_CHANGES`
from the bot into an actual block.

### 4. Reviewer auto-assignment (optional)

Forgejo honours a `CODEOWNERS` file in the repo root, `docs/`, or `.forgejo/`
on the default branch. It only auto-assigns *users/teams*, not bots, so it's
only worth adding if someone else ever opens PRs here.

## Secrets handling

This is the part worth being picky about, so, explicitly:

- **Nothing new is committed in plaintext.** No secret values live in the
  workflow files; they reference `secrets.*` / `vars.*` which Forgejo injects at
  run time and masks in logs.
- **Forgejo needs its own copy.** Actions secrets are stored in the instance
  database. sops-nix decrypts onto host filesystems, which is a different
  mechanism — the runner's job containers can't read `/run/secrets`. So the
  values must be installed into Forgejo one way or another.
- **`scripts/forgejo-sync-secrets.sh` is optional convenience**, not a
  dependency. It decrypts from sops and `PUT`s to the Forgejo API so you rotate
  in one place. It:
  - never writes plaintext to disk (values move through the environment and
    stdin only);
  - keeps values out of `argv` — `jq -n '{data: $ENV.SECRET_VALUE}'` instead of
    `--arg`, `curl --config <0600 tempfile>` instead of `-H "Authorization: …"`
    — so `ps` on a shared host shows nothing;
  - requires `FORGEJO_ADMIN_TOKEN` in the environment, which is intentionally
    *not* stored in sops: it's a bootstrap credential, delete it afterwards.
  - must not be run under `bash -x`, which would defeat all of the above.
- **`forgejo-bot-token` is not yet in `secrets/general.yaml`** — add it with
  `sops secrets/general.yaml` once the bot PAT exists, or skip sops entirely and
  paste it into the Forgejo UI.
- **Fork PRs never see secrets.** `pr-ai-review.yml` guards on
  `head.repo.full_name == github.repository`; `pr_check` only exposes the bot
  token, and neither workflow uses `pull_request_target`.

Threat model note: any workflow file on a PR branch runs on `euler` with the
runner's privileges. That is inherent to a self-hosted runner on a repo you
control — fine for a personal dots repo, but do not grant other people push
access to branches without also reading their workflow changes.

## Local sanity checks

```sh
nix fmt -- --ci                 # same gate as CI
nix flake check --no-build      # same gate as CI
```

Both are what `pr-check.yml` runs, so a PR that passes locally passes CI.
