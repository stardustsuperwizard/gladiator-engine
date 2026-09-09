# Third-Party Notices

Material in this repository that originates outside it, with the licence terms
that come with it and a decision log for each item.

`EXTRACTION_LOG.md` is the log for `mikeys_game_bones-rules-moba` and only for
that source — its header names the repo and pins the commit. Anything from a
different source is recorded here instead, so neither document has to say
"except when".

---

## Claude-Code-Game-Studios

- **Source:** <https://github.com/Donchitos/Claude-Code-Game-Studios>
- **Reviewed at:** default branch, cloned 2026-09-09
- **Licence:** MIT

MIT requires the copyright notice and the permission notice to be included
with copies and with substantial portions. It is reproduced in full below and
covers every item in the table that follows.

```text
MIT License

Copyright (c) 2026 Donchitos

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### What was taken

Verdicts follow `EXTRACTION_LOG.md`'s convention: **extract** = copied
near-verbatim · **adapt** = rewritten here from a source idea or contract ·
**rebuild** = new work, source not usable · **reject** = deliberately not
brought over.

Nothing was copied near-verbatim. Every item below is **adapt** or **reject**,
so no file in this repository is a substantial portion of that Software — but
the notice above is reproduced anyway rather than reasoned about, because the
cost of including it is nothing and the cost of being wrong about "substantial"
is not.

| # | Item | Verdict | Rationale |
| --- | --- | --- | --- |
| 1 | `docs/engine-reference/<engine>/` — a version-pinned sheet of post-training-cutoff engine changes | adapt | The strongest idea in the source. Ours is `docs/engine-reference/godot/`, pinned to 4.7.1-stable, written from the official `godot-docs` migration pages rather than from theirs, and filtered to what can reach `rules/`, `scripts/`, `tests/` or headless validation. Their 4.6 tables were not carried over. |
| 2 | Path-scoped rules (`.claude/rules/*.md` with `paths:` frontmatter) | adapt | The idea, not the mechanism: their frontmatter is read by nothing. We already had the Copilot half (`.github/instructions/rules.instructions.md`, `applyTo:`); the missing Claude Code half is now `rules/CLAUDE.md`, a pointer to that same file. One contract, two loaders, no second copy. |
| 3 | `.claude/hooks/session-start.sh` | adapt | Shape only. Theirs prints sprint files, milestones and bug counts against a directory layout we do not have. Ours prints what is derived from this tree — actions built, actions missing, whether Godot can be found — because `AGENTS.md`'s prose state section has already been wrong once. |
| 4 | `.claude/hooks/validate-commit.sh` | adapt | Reduced hard. Theirs warns on hardcoded gameplay values, missing GDD sections and unowned TODOs. Ours (`guard-rules-boundary.sh`) checks only the two commitments that are honestly one grep, is advisory, and says in its own header that the contract tests are the authority. |
| 5 | `.claude/statusline.sh` | adapt | Shape only. Their production-stage detection reads `production/stage.txt` and a GDD layout we do not have. Ours shows context, model, branch, actions built, and whether Godot is on this machine. |
| 6 | `.claude/settings.json` — permissions allowlist and hook wiring | adapt | The read-only Bash allowlist is a good default; ours names this project's own validation scripts instead. Their `SubagentStart` / `PostCompact` wiring was not carried over unverified. |
| 7 | `/skill-test static` — a structural linter over skill files | adapt | Generalised to the real risk here: four agent roles written down on three surfaces with nothing linking them. Part 6 of `.github/scripts/test-workflow-logic.sh`, in the harness that already existed. |
| 8 | `tr-registry.yaml` + `/propagate-design-change` — stable requirement IDs and a spec-change impact report | adapt (deferred) | Aimed squarely at the failure this repo already paid for: spec §3/§6/§7 revised, code silently stale, epic #83 opened to reconcile. Their version assumes a GDD/ADR/story pipeline we do not have. Filed as an Issue rather than built here. |
| 9 | `docs/examples/session-*.md` — narrated end-to-end sessions | adapt (deferred) | `docs/AGENT_WORKFLOW.md` is 2,100 lines of reference with no worked run. Filed as an Issue. |
| 10 | 49 agent personas (`art-director`, `community-manager`, `economy-designer`, …) | reject | `docs/AGENT_ROLE_DESIGN.md` requires a new role to clear a tool boundary, a cost tier, or a context wall, and says a job title is none of them. These are 49 job titles. Adopting them would reverse a settled decision, not extend it. |
| 11 | ~70 skills (`/art-bible`, `/live-ops`, `/localize`, `/patch-notes`, …) | reject | Same test as #10, plus most target a lifecycle this project does not have. |
| 12 | The collaborative protocol — ask "May I write this to [filepath]?" before every write, no commits without instruction | reject | Inverts the autonomous label-driven control plane. The two cannot both hold. |
| 13 | Directory structure (`src/gameplay/`, `design/gdd/`, `production/`) | reject | This is a Godot project; `rules/`, `scripts/`, `scenes/`, `resources/` are the engine's own shape and are settled by extraction plan §4. |
| 14 | CI | n/a | The source has none — its `.github/` holds CODEOWNERS, funding and templates only. Nothing to take. |

### Where the boundary sits

Every file listed as **adapt** was written here from scratch against the idea,
not edited down from their text. That is a deliberate standard rather than a
licence requirement: MIT would permit copying with the notice attached. It is
the same standard `EXTRACTION_LOG.md` #12 applied to the source repo's
`AGENTS.md`, and it keeps every line in this tree one someone here can defend.
