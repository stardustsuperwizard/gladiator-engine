# Severe Rules Overhauls

## What this document is for

`AGENTS.md` already says how a rule changes: revise the spec first, as an owner
decision, with the dated revision note the spec's own convention requires; then
run `.github/scripts/spec-impact-report.py` and turn anything not classified
`still-valid` into an Implementation Task.

That procedure was written for changing **one section**, and it has worked
twice at that size — §11's rewrite into four configurable dials (#173) and
§5.2's derived Turn allowance (#377). It does not describe what to do when the
change is large enough that the answer to "turn it into an Implementation Task"
is "which one, out of thirty-one?"

This document covers that case, and only that case. For an ordinary revision,
follow `AGENTS.md` and ignore this file.

## What counts as an overhaul

A spec change is an overhaul if **any one** of these holds. They are not a
judgement call about how the change feels; each one is checkable before the
work starts.

| Trigger | Check |
| --- | --- |
| It touches more than one top-level section | The impact report lists more than one of §1–§12 |
| It removes or reverses a rule that built code implements | Any changed section classifies `likely-superseded` and its entry cites a module |
| It would shrink the test suite | Retiring the rule means deleting tests that assert it |

The third is the one most easily missed and the most expensive to discover
late, because it is the one CI refuses — see *Gates an overhaul will trip*.

**Tuning is not an overhaul.** Dice counts, damage values, target numbers,
modifiers and point costs live in `.tres` data precisely so they can be changed
without any of this; spec §12 says so. A change that moves only numbers is a
data edit, however large the numbers.

**A rewording is not an overhaul.** `spec-impact-report.py` collapses internal
whitespace before comparing, so a rewrap classifies `still-valid`. If every
changed section comes back `still-valid`, there is nothing here to do.

## Why the incremental procedure does not scale

This is measurable rather than theoretical, and the repository carries its own
worked example. The span from `v0.0.1` to `v0.2.0` contains every rules change
made so far, including two the project already calls out as deliberate
divergences — symbol-faced dice replaced by d6 against a target number, and the
fighter/weapon split collapsed into a single six-stat fighter.

```console
$ python3 .github/scripts/spec-impact-report.py --base v0.0.1 --head v0.2.0 --json
```

| Measure | Value |
| --- | --- |
| Changed sections | 31 |
| `still-valid` | 0 |
| `needs-review` | 20 |
| `likely-superseded` | 11 |
| Top-level sections superseded | 11 of 12 — every one but §2 |
| Distinct modules cited | 26 |
| Distinct tests cited | 31 |

Applied literally, `AGENTS.md`'s rule yields 31 Implementation Tasks with no
stated order, no way to tell which of the 147 hits are the same underlying
change counted twice, and no answer for the tasks already open against the
sections being rewritten. The rule is not wrong; it is under-specified at this
size. Everything below is the missing specification.

## The procedure

### 0. Cut a baseline release first

Before the first character of the spec changes, tag the current `main` through
`.github/workflows/release.yml` — see `docs/RELEASING.md`. The baseline exists
for three reasons:

- `spec-impact-report.py --base` takes any git ref, so a tag makes the whole
  overhaul diffable **as one unit** at any point during it. Without it, each PR
  can only be diffed against its own parent, which is precisely the view that
  loses the shape of the change.
- It is the last commit where the spec and the code agreed. During the window
  below they will not, and the disagreement needs a fixed point to be measured
  from.
- It is the rollback target if the overhaul is abandoned.

`v0.2.0` (`6357ebc`) is the baseline for the first overhaul to use this
document.

One ordering trap: the spec-only PR of step 2 **cannot itself be released**.
`docs/**` is in `ci.yml`'s `GODOT_DENY` list, so a docs-only push to `main`
skips the `Godot Export` and `Godot Smoke Run` jobs while the aggregate `ci`
check still reports green — and `release-preflight.py` treats a `skipped`
conclusion on either job as `stage-not-passed`, a refusal. Tag before the spec
lands, not after.

### 1. Clear the in-flight work

Every open epic and task is either **landed before the spec PR opens** or
**closed as superseded by the overhaul**, explicitly, with a comment saying
which. Nothing straddles the boundary.

This is not tidiness. An Implementation Task carries its acceptance criteria in
its body, written against the spec as it read when the task was filed. Merged
mid-overhaul, it faithfully re-implements the rule the overhaul is removing,
and it will pass its own review for doing so — the reviewer checks the PR
against the Issue, not against the spec.

At the time of writing that means epic #374 (the pre-action Power Step) and its
four open tasks #418–#421, which rewrite §5.1 and §5.3 — sections any overhaul
touching turn structure would also rewrite.

### 2. Revise the spec in one pull request

The whole rewrite lands as a **single spec-only PR**: no code, no test, no
resource file. One Issue, one PR, one squashed commit, as `CONTRIBUTING.md`
requires — the Issue is the overhaul epic's first task.

Interleaving spec and code edits across several PRs is the failure this
forbids. The impact report diffs two texts; if the spec arrives in five
instalments there is no single "after" to diff against, and each instalment's
report describes a spec state that never governed anything.

Every rewritten section carries the dated revision note the spec's convention
requires, saying what it previously said and why that changed. The notes are
load-bearing here beyond their usual job: at overhaul scale they are the only
per-section record of intent, and `spec-impact-report.py` ignores `>` lines
when classifying, so writing them cannot change any classification.

### 3. Run the report against the baseline

```console
$ python3 .github/scripts/spec-impact-report.py --base v0.2.0 --head HEAD --json
```

Exit `1` means at least one changed section is **unmapped** — the spec grew a
section the traceability index does not cover. Fix the index before triaging;
an unmapped section is a section whose impact nobody has measured.

### 4. Triage into an overhaul epic

One epic, one task per **superseded rule** — not per changed section. The
distinction matters because a single rule change routinely lands in three
sections (the rule, its cross-reference, and §12's implementation note), and
filing three tasks for it produces two that cannot be worked.

| Classification | What it means | Action |
| --- | --- | --- |
| `likely-superseded` | The section lost or altered a normative line | A retirement task — see below |
| `needs-review` | Normative lines were only added to | A task, **or** a recorded decision that nothing is needed, with the reasoning in the epic |
| `still-valid` | Revision notes and whitespace only | Nothing |

A `needs-review` dismissed silently is indistinguishable at the next overhaul
from one that was never looked at. Record it.

Order the tasks by the spec's own dependency direction — the data model before
the rules that read it, the round structure before the actions that occupy it —
not by section number, and not by the report's output order.

### 5. Retire the code, do not leave it

A retirement task's job is that the old rule stops existing: the module is
deleted or rewritten, its tests go with it, and the traceability index stops
pointing at it. A retirement task that adds the new rule beside the old one and
leaves both standing has not retired anything, and the resolver now implements
two contradictory rules.

### 6. Close the window

The overhaul is over when every triage task has merged or been explicitly
declined. Then, in one PR:

- Rewrite `AGENTS.md`'s *Current state* and the corresponding section of
  `CLAUDE.md` — both carry a dated, superseding revision note rather than a
  silent edit.
- Confirm the index has no section left pointing at a module that no longer
  exists.
- Cut the next release. That tag becomes the baseline for whatever comes next.

## The declared divergence window

`AGENTS.md` is unambiguous: a rule that lives only in code is a bug regardless
of how right it is. Between step 2 and step 6, the reverse is deliberately
true — the spec describes rules the resolver does not implement yet.

That window is a bounded, declared exception, not a suspension of the rule. It
is declared in two places, and an overhaul that skips either has not declared
it:

1. The spec's own revision note for each rewritten section, which says the code
   has not caught up.
2. `AGENTS.md`'s *Current state*, which names the overhaul epic and says which
   sections are ahead of the tree.

Both exist so that a session reading the spec mid-overhaul reaches the same
conclusion a session reading it afterwards would: the divergence is known and
tracked, not a defect to be helpfully corrected. `AGENTS.md` already carries a
smaller version of this for #374 and #377; the difference here is scale, not
kind.

What the window does **not** license is a session closing the gap on its own
initiative. The rule that an implementation session does not redesign mechanics
holds throughout. A session that believes the spec is wrong says so and stops.

## Retiring code: the `superseded` status

`docs/spec-traceability.json` has supported a third status since the index was
built, alongside `active` and `unimplemented`. Nothing in the tree has ever
used it — all 24 entries are `active` or `unimplemented`. Retirement is what it
is for.

When a section's rule is replaced, the old entry flips to `superseded` and
**keeps its module and test lists**. It becomes the historical record of what
implemented the rule that used to be there. A new entry takes the section with
the new modules.

`spec_traceability.py` already enforces the constraints this relies on, and
they are worth knowing before editing the index by hand:

| Rule | Consequence for a retirement |
| --- | --- |
| `resolve()` prefers a non-superseded entry, falling back to a superseded one | Two entries may share a section during retirement; the live one wins |
| Only one `active` entry per section | Flip the old entry **before** adding the new one, or the index fails validation |
| An `active` entry needs at least one module | A section whose code is deleted and not replaced becomes `unimplemented`, not `active` with an empty list |
| Every module path must start with `rules/` | Retiring something under `scripts/` is not recorded here at all |

`.github/scripts/test-spec-traceability.sh` is the check, and `ci.yml`'s
`Spec Traceability` job runs it — the spec and the index are both in
`CONTROL_PLANE_ALLOW`, so a spec-only PR does trigger it.

## Gates an overhaul will trip

Three CI gates exist to stop exactly the kind of change an overhaul makes
legitimately. None of them is wrong; each needs a human, and an overhaul that
has not planned for that will stall at the first retirement task.

| Gate | Why an overhaul trips it | Override |
| --- | --- | --- |
| `test-ratchet` | Retiring a rule deletes the tests asserting it; the suite or `_expect(` count falls below the merge base | `test-removal-approved` — **human-only** |
| `red-gate` | Only if a task adds a test that already passes at the merge base | `characterization-test` — **human-only** |
| `Spec Traceability` | An index left mid-edit, or a section the index does not cover | None — fix the index |

`test-ratchet` is the one that matters, and the constraint on it is procedural
rather than technical: **agents are forbidden from applying
`test-removal-approved`** (`AGENTS.md`, and PR #290 which established it). So
every retirement task that deletes tests needs a human to apply that label
before it can merge. Plan the overhaul knowing its retirement tasks cannot be
driven start to finish unattended.

`red-gate` is usually not a problem — a task that only deletes tests adds none
for the gate to judge — but a task that replaces a rule adds new tests, and
those must genuinely fail at the merge base. Against a baseline where the old
rule still stands, they will.

## What an overhaul does not get to change

An overhaul is licensed to rewrite the rules of the game. It is not licensed to
rewrite how the repository is built. `AGENTS.md` says everything outside the
two architectural commitments is negotiable; a rules overhaul is not the
occasion on which they become negotiable.

1. `rules/` keeps its strictly one-way dependency arrow.
2. Every action still goes through the one authority object.
3. The resolver still takes its randomness as an explicit input.

A proposed rule that cannot be expressed within those three is a reason to stop
and raise the conflict, exactly as `AGENTS.md`'s architecture rules already
require. It is not evidence that the commitments should bend.
