---
description: Review a planner's sub-issues against their parent epic before any task is dispatched, and publish a PLAN PASS/FIX/REJECT verdict on the epic
argument-hint: <epic-number>
---

Review the plan under epic #$ARGUMENTS in stardustsuperwizard/gladiator-engine
against the epic it claims to implement.

**This command reads. It never writes to the plan.** It applies no label,
files no Issue, and amends neither the epic nor any sub-issue. Its only
output is one verdict comment on the epic.

## GitHub access

`gh` exists in a desktop terminal and does **not** exist in a cloud session
(Claude Code on the web, the Claude mobile app). Settle which one you are in
once, with one command, before any GitHub call:

```bash
command -v gh >/dev/null 2>&1 && echo ENV=LOCAL || echo ENV=CLOUD
```

- `ENV=LOCAL` — use the `LOCAL` form at each call site below.
- `ENV=CLOUD` — use the `CLOUD` form. `gh` is absent by design: do not
  install it, do not curl the REST API, do not go looking for a token, and
  do not treat its absence as an error worth reporting.

Every call site below gives you both forms, written out in full. Use them
verbatim. Never translate one form into the other yourself, and never guess
a tool name — the `CLOUD` tools may need their schema loaded first — if one
is not already callable, run `ToolSearch` once with `select:<tool-name>`,
then call it.

Repository is always `owner="stardustsuperwizard"`,
`repo="gladiator-engine"`.

## 1. The epic

```bash
# LOCAL
gh issue view $ARGUMENTS --repo stardustsuperwizard/gladiator-engine \
  --json number,title,body,url,comments
```

```text
CLOUD — two calls to mcp__github__issue_read, same arguments except
`method`:
  method="get"           -> number, title, body, url
  method="get_comments"  -> comments (author, body, created_at)
  owner="stardustsuperwizard"
  repo="gladiator-engine"
  issue_number=$ARGUMENTS
```

If the title does not start with `[epic]`, confirm with the user before
proceeding — this command reviews a plan against an epic, and running it
against an Implementation Task Issue instead reviews nothing.

## 2. Its sub-issues — the planned tasks

```bash
# LOCAL — no --json field exposes sub-issues, so use the title convention the
# planner guarantees: it titles every child "[task] [<parent>] <title>".
gh issue list --repo stardustsuperwizard/gladiator-engine \
  --search "[task] [$ARGUMENTS] in:title" \
  --state all --limit 50 \
  --json number,title,body,url
```

```text
CLOUD — mcp__github__issue_read with:
  method="get_sub_issues"
  owner="stardustsuperwizard"
  repo="gladiator-engine"
  issue_number=$ARGUMENTS

That call gives you the child Issue numbers, not reliably their full bodies.
Follow it with one mcp__github__issue_read method="get" call per sub-issue
number (same owner/repo) to get each task's title, body and url.
```

If there are no sub-issues at all, stop: there is no plan to review. Tell
the user the epic has not been planned yet and post nothing.

If a sub-issue's body cannot be read — the fetch fails, or comes back
null — stop and tell the user which Issue and why, rather than reviewing a
partial plan.

## 3. Write the bundle and assemble the request

Write what you fetched as one JSON file matching the assembler's bundle
shape:

```json
{
  "epic": {
    "number": <epic-number>,
    "title": "<epic title>",
    "body": "<epic body>",
    "comments": [
      {"author": "<login>", "body": "<comment body>", "created_at": "<ISO 8601>"}
    ]
  },
  "tasks": [
    {"number": <n>, "title": "<task title>", "body": "<task body>", "url": "<task url>"}
  ]
}
```

Write it to a scratch location — `mktemp -d` a working directory, never the
repository working tree — then run the assembler:

```bash
bundle="$(mktemp -d)/bundle.json"
# write the JSON above to "$bundle"
request="$(mktemp -d)/request.md"
python3 .github/scripts/build-plan-review-request.py --bundle "$bundle" --out "$request"
```

The assembler performs no network access and no model call — it is
deterministic, and it is what resolves the greppable half of checks 5, 6
and 8 before the review ever reasons about the plan. If it exits non-zero,
it names the epic or the task the bundle is missing something for and
writes no output file: stop there, tell the user why, and do not delegate.

## 4. Delegate

Otherwise, delegate the review to the `plan-reviewer` subagent, giving it
the epic number and the assembled request file's contents (or the file
path, if the subagent can read it directly) as context. Do not summarize or
trim the request before handing it over — the subagent's eight checks read
specific sections of it (`# UNRESOLVED ARTIFACT NAMES`,
`# DECLARED EXPECTED FILES` in particular), and a trimmed request is a
review of less than the plan.

The subagent posts the verdict comment on the epic itself; this command
does not post anything on its own.
