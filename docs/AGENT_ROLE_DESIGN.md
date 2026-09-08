# Agent Role Design

> **Written 2026-09-08**, from a review session that had no originating Issue.
> It records *why the four roles are the four roles*, and what would have to
> become true before a fifth, sixth or seventh is worth adding.
>
> This answers a different question from `docs/AGENT_WORKFLOW.md`, which is why
> it is a separate file rather than another section of one that is already
> 2,100 lines. That document answers *how does the control plane fire, and
> which model runs which role*. This one answers *why is there a role here at
> all, and when should there be another*. Same three-documents-three-jobs
> discipline `AGENTS.md` applies to the spec, the plan and the guide.

## The question this came from

The owner saw a presentation in which an agent system was organised along
**associate lines**: an "engineering manager" agent delegating to
`technical-writer`, `researcher`, `data-engineer`, `data-analyst`,
`cloud-engineer`, `ui-ux-engineer`. This repository's four agents are named
`planner`, `implementer`, `reviewer`, `fixer`. The question was whether to
build the first shape here, alongside or instead of the second.

The short answer is *two of them, yes, and not for the reason the framing
suggests* — #101 and #102. The rest of this file is why, and what would change
the answer.

## The two shapes decompose along different axes

| | This repository | The org-chart shape |
| --- | --- | --- |
| Axis | Lifecycle stage | Discipline |
| Roles | plan → implement → review → fix | writer, researcher, data, cloud, UI |
| Handoff | A durable artifact | Conversation inside one session |
| Ordering | Fixed, and each stage consumes the last one's output | None; disciplines do not queue |

The org chart is not a better-organised version of the pipeline. It is a cut
along a different dimension, and the dimension matters because of **what
carries the handoff**.

Every stage here hands the next one a durable artifact that a cold session can
read: the `[task]` sub-issue body, the pull request, the `VERDICT` comment.
`docs/AGENT_WORKFLOW.md` §"Where the handoff contract lives" is explicit that
the sub-issue is authoritative and that anything an implementer needs must be
in it, because the implementer never sees the planner's session. That property
is what makes per-role model routing possible at all, and it is what makes a
failed stage retryable by re-adding a label.

Disciplines do not have that property. A technical writer and a data engineer
are knowledge domains; they do not stand in a fixed order and there is no
artifact one owes the other. An org chart of agents therefore tends to keep its
coordination in a single session's context, which is the thing this repository
spent its design budget getting away from.

## What actually makes the existing roles work

Not their names. Three mechanisms, in descending order of load-bearing:

1. **Capability removal.** The planner has no `Edit` tool; the reviewer has no
   `Edit` tool. `docs/AGENT_WORKFLOW.md` §"Why planning and review are CLI
   sessions, not cloud agents" states the finding in one sentence — *"The fix
   is not better prose. It is removing the capability."* — after an agent file
   that said "do not implement" lost the argument with a harness built to
   produce a diff.
2. **Cost tiering.** `implementer` runs on Haiku, `planner` on Opus. The comment
   in `.claude/agents/planner.md`'s frontmatter argues the case: planning is
   where the expensive mistakes are made, and the role that *allocates* the
   other roles' tiers should not be cheaper than what it allocates.
3. **Context isolation.** The reviewer judges the diff against the Issue's
   acceptance criteria without having seen the implementer's reasoning about
   why a shortcut was fine.

**Job title is not one of these.** Two agents that differ only in the prose
describing their expertise get identical tool lists, identical model tiers and
identical context — which is the configuration that already failed once here.

### The test

Split an agent when at least one of these is true:

- it needs **different tool permissions** from an existing role;
- it belongs on a **different cost tier**;
- it must **not see** context an existing role has.

If none of the three holds, the work belongs to an existing role, and the
"new role" is a prompt.

## The manager-delegates-to-specialists shape does not fit this control plane

Not a matter of taste. Four findings, all in this tree:

1. **Sub-agent spawning is disabled in every cloud role.**
   `.github/actions/run-agent-session/action.yml:252` and `:261` exclude
   `task,write_agent` in *both* capability postures. The write case comments it
   explicitly: "keep edit and shell, still no sub-agents."
2. **The picker's model covers the parent and every sub-agent it delegates
   to.** This is `docs/AGENT_WORKFLOW.md`'s §"The constraint that shapes
   everything". A manager delegating in-session would run its cheap specialists
   on the manager's Opus. Per-role routing here requires *separate sessions* —
   which is what the label-driven pipeline is.
3. **`agents:` and `handoffs:` frontmatter are unsupported on github.com.** Both
   are listed under §"Unsupported frontmatter". There is no declarative way to
   express an org chart in an agent profile on that surface.
4. **Locally it is possible but not free.** A Claude Code sub-agent takes a
   per-agent `model:` scalar, so a delegating orchestrator *does* route per
   role. But `fallbackModel` in `.claude/settings.json` is one chain for the
   whole session and escalate-only, and copilot-cli#2564 reports `model:` being
   ignored for sub-agents in the CLI. Verify before trusting it.

**Conclusion:** an orchestrator agent is a local-only pattern here. It cannot
live in the label-driven control plane without undoing the separation that
control plane exists to provide.

## The roster, assessed against the test

### Build now

**Spec steward** — #101. Passes on *tool permissions*: it edits `docs/`,
`EXTRACTION_LOG.md` and `AUDIT_NOTES.md`, and must not write `rules/`. That
boundary already exists as a rule in `AGENTS.md` — a session that believes a
rule is wrong says so and stops; a rule that lives only in code is a bug — and
is currently enforced by prose alone, against an implementer holding
unrestricted `Edit`. It also has work waiting: the spec has moved ahead of the
code (#83, #91).

**Workflow steward** — #102. Passes on *tool permissions* in the strongest
form available: `GITHUB_TOKEN` cannot push `.github/workflows/` or
`.github/actions/` at all, per `RESTRICTED_PREFIXES` in
`.github/scripts/task_scope.py`, so this role can only run from a
human-credentialed Claude Code session. The control plane is now the largest
artifact in the repository by volume — 13 workflows and 6 composite actions
against ~15k lines of GDScript including tests — it has documented drift
history (`agent-06-claude.yml`), and it has an unowned backlog (#68, #69, #98,
#99).

### Gated on something else existing

**Balance analyst.** The numbers are meant to be tuned; that is why they live
in `.tres` rather than the resolver (spec §12). But the `sim/` Python balance
harness was deliberately not ported — see the header note in
`docs/AGENT_WORKFLOW.md`. An analyst with nothing to run is a prompt, not a
role. *Gate: a balance harness exists and has been run at least once by hand.*

### Later, on real conditions

**UI/UX engineer.** `scenes/main.tscn` is a bare `Node`. There is no UI, no
hotseat loop, and extraction plan §5.4's "play a full 3-round match" is some
way off. *Gate: §5.2 is complete and hotseat work has started.* At that point
re-run the test above — the likely honest answer is still "no", because a UI
session and a rules session differ in **which paths they touch**, which the
`⚠️` delicate-paths mechanism in `task_scope.py` already flags, and in
**whether a human must check it in the editor**, which the pull request
template's "Human Validation Required" section already captures. Two existing
mechanisms covering the boundary is evidence the role is a prompt.

### Not for this repository

**Data engineer, data analyst, cloud engineer.** There is no data layer, no
database, and no cloud infrastructure beyond GitHub Actions. `AGENTS.md`
forbids third-party dependencies and addons outright, which removes most of
what these roles would reach for. *No gate — these would need the product to
become a different product.*

**Researcher, technical writer as standalone roles.** The planner already does
the research half: it reads the Issue body, its comments as amendments, and a
repository file inventory, and it is the role that decides what becomes work.
The writing half is a documentation contract, and #101 gives it an owner.
Splitting these further would be title-driven.

### The empty-role trap

`docs/AGENT_WORKFLOW.md` makes this argument about the deleted pre-vendor
labels, and it transfers exactly: *"A label that exists and does nothing is a
trap. Someone adds it from a phone, sees no run start, and has nothing to
read."* An agent profile with no work is the same trap wearing a job title. It
is also worse than a dead label, because a model asked to pick a role will pick
a plausible-sounding empty one.

This is why #101 and #102 both forbid adding an `agent:*` label or a workflow
in their own scope. Prove a role locally; give it a button afterwards.

## Revisiting this

Re-read this file when any of these becomes true:

- [ ] A balance harness exists → reconsider **balance analyst**.
- [ ] §5.2 is complete and hotseat/UI work has started → reconsider
      **UI/UX engineer** against the test, not against the job title.
- [ ] Sub-agent spawning is deliberately re-enabled in
      `run-agent-session/action.yml` → the orchestrator shape becomes possible
      on the cloud surface, and §"The manager-delegates-to-specialists shape"
      above needs re-deriving rather than re-reading.
- [ ] GitHub supports `agents:` or `handoffs:` frontmatter → same.
- [ ] A fifth or sixth role has been added and two of them keep getting
      confused for each other → that is the signal the split was title-driven,
      and one of them should be merged back.

And the standing rule, which is the part most worth keeping: **a new agent
needs a tool boundary, a cost tier, or a context wall. If it has none of the
three, write a better prompt for a role that already exists.**

## On the framing

The "miniature company" metaphor is good at one thing and misleading at
another.

It is good at legibility. A system you can describe as a set of roles is one
you can hold in your head, explain to someone else, and reason about when it
misbehaves.

It misleads because real org charts solve constraints agents do not have.
Humans specialise because context-switching is expensive and because a person
cannot be in two places at once. Neither is true of a session. Roles that exist
*for those reasons* do not transfer; roles that encode a boundary you actually
want enforced do. The four here, and the two in #101 and #102, are all the
second kind.

Worth stating plainly, since it was the part of the question that stung: the
judgment layer in this repository is not what got automated. `AGENTS.md`
reserves rules changes to the owner as an explicit decision with a dated note.
Extraction plan §5.3 is a list of things deliberately not built, which is a
judgment nothing in the pipeline could have made. `docs/AGENT_WORKFLOW.md`
§"Verifying the local planner's label transition by hand" hands a step back to
a human precisely because nothing automated covers it. The agents move work
through a contract; deciding what is true and what should exist is the contract
itself, and that is still authored here.
