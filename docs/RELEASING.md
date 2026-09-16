# Releasing

## What a version means

A release is tagged `v0.<slice>.<patch>`. The operator supplies the version
input as `0.<slice>.<patch>` — no leading `v`; the workflow prepends it to
form the tag.

- **`0.`** is the pre-alpha major. It stays `0` for as long as this repository
  has no public API to version and makes no stability promise about anything
  it ships.
- **`<slice>`** tracks the extraction plan's build order —
  `docs/moba-to-hex-skirmish-extraction-plan.md` §5.x. Today's slice is §5.2,
  so current releases are `0.2.y`.
- **`<patch>`** increments by one for each release made inside a slice, and
  resets to `0` when the slice advances.

Slice is the one number worth carrying, because it is the one number everyone
in this repository already reasons in — the extraction plan's build order —
where semantic versioning's major/minor/patch split would be describing an API
this project does not have. This is a scheme, not semver: do not read `0.2.y`
as "semver 0.x" or expect the usual semver compatibility guarantees from it.

## Why releasing is manual

`.github/workflows/release.yml` has exactly one trigger, `workflow_dispatch`,
and no `push`, `schedule`, `release`, or `repository_dispatch` trigger beside
it. That is deliberate, not an automation gap to close later.

This repository practices continuous delivery, not continuous deployment:
every green commit on `main` is *releasable*, but deciding that a commit
should actually be *released* — cut a tag, publish an asset, put it in front
of someone — is a judgment call reserved to the owner. Adding an automatic
trigger is a decision to revisit deliberately, not an oversight to patch.

## Dispatch procedure

Dispatch `.github/workflows/release.yml` (Actions tab, or `gh workflow run
release.yml`) with two inputs:

- **`commit`** — the full 40-character SHA of the commit to release. It must
  be on `main`.
- **`version`** — the release version without a leading `v`, e.g. `0.2.0`.

The workflow itself creates nothing until its preflight check clears the
commit; see *Releasability and refusal* below.

## What is verified, and how

Releasability is decided from `commit`'s own `ci.yml` run: specifically, the
`conclusion` of that run's `Godot Export` and `Godot Smoke Run` jobs, read as
JSON from GitHub's own API rather than re-run. Both must have concluded
`success`.

A `skipped` conclusion on either job is a refusal, not a pass, even though the
run's own aggregate `ci` check can report green: a docs-only push to `main`
skips both the export and the smoke jobs while `ci` still succeeds, because
neither job had anything to do. `release-preflight.py` treats that shape as
not releasable — a green `ci` check is not the same claim as "this commit's
build was exported and smoke-run."

## What gets published

The asset attached to the release is the artifact that commit's `ci.yml` run
already produced and smoke-ran — downloaded from that run, not rebuilt. The
release workflow has no `setup-godot` step, no export step, and no engine on
its runner at all: "the release" and "the thing that was verified" are the
same bytes by construction, not two builds that happen to agree.

## Pre-release, always

Every release this workflow creates is published as a pre-release. This is
hard-coded — a literal `--prerelease` flag with no input, variable, or
condition around it — not an option the operator can leave off. Changing that
requires editing `.github/workflows/release.yml` itself.

## Releasability and refusal

`release-preflight.py` decides releasable/not-releasable and prints one of
seven refusal reasons when it refuses. Each reason names the first thing
wrong, in this order:

| Reason | Meaning | Operator's next step |
| --- | --- | --- |
| `bad-version` | The `version` input does not match `0.<digits>.<digits>` (pre-1.0 only). | Re-dispatch with a version in the required shape. |
| `not-on-main` | `commit` is not an ancestor of `main` — a typo, a fork SHA, or a deleted branch tip all look the same here. | Confirm the SHA and that it has landed on `main`, then re-dispatch. |
| `no-run` | No completed `ci.yml` run exists for `commit`'s head SHA. | Wait for (or trigger) a `ci.yml` run against that commit, then re-dispatch. |
| `stage-not-passed` | The selected run's `Godot Export` or `Godot Smoke Run` job did not conclude `success` — including `skipped`, `failure`, or `cancelled`. | Find a commit, or a re-run, where both jobs actually ran and passed, then re-dispatch against that. |
| `artifact-missing` | No artifact named `godot-linux-<commit>` exists on the selected run. | Confirm the export job actually uploaded an artifact for that commit; a run predating the export job, or one whose upload failed, cannot be released. |
| `artifact-expired` | The artifact exists but has aged past the export upload's retention window. | The commit can no longer be released as those exact bytes; re-run `ci.yml` for that commit (or a later one) to produce a fresh artifact, then re-dispatch. |
| `tag-exists` | The tag `v<version>` already exists. | Choose the next `<patch>` (or `<slice>`) that has not been used, then re-dispatch. |

A refused preflight, or a publish step that fails partway through, leaves no
tag and no release behind: the workflow's failure handler deletes any tag or
release it may have half-created, so a failed dispatch returns the repository
to exactly the state it was in before.
