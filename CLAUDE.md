# Rules for every session

Every session in this repo follows this file. The session prompt only adds the owner's
input and the tasks; everything standing lives here or in `DEVELOPMENT.md`.

## Read order

1. This file.
2. `DEVELOPMENT.md`: Status, Workflow, Architecture rules, GDScript conventions,
   Pitfalls, Verify every change.
3. The current milestone's plan doc in `docs/` (Status names it): the step checklist,
   every "What step N added" and "Decisions" section, and the known open questions.
   Don't re-derive decisions already recorded there.
4. Only when needed: `docs/m2_pack.md` (body API, the Pack, the eval budget, the
   baselines' history), `docs/design.md` (design questions), `docs/roadmap.md`.

## How to work

- Work autonomously. Ask the owner only for decisions that are truly theirs (numbers
  and feel the plan doc lists as owner questions, scope changes).
- Work in small steps from the plan doc. If the next step needs an owner decision that
  isn't answered yet, stop and ask instead of guessing.
- Record every non-trivial decision in the plan doc, tick finished steps there and in
  `DEVELOPMENT.md` Status (and `docs/roadmap.md` when a milestone changes state).
- Anything new that bit you (a Godot quirk, a test trap) goes into `DEVELOPMENT.md`
  Pitfalls in the same session, so later prompts don't have to carry it.

## Git

The owner merges into main. Sessions never commit or push to main.

- Setup, before any commit: `git fetch origin main`. If the session branch on origin
  holds commits that aren't in main yet (an earlier session the owner hasn't merged),
  keep them and commit on top. Otherwise `git checkout -B <session branch> origin/main`.
  Then `git config user.name "ryanrhursh"` and
  `git config user.email "110621309+ryanrhursh@users.noreply.github.com"`.
- Commit on the session branch only, one commit per finished, verified step. Commit
  messages: imperative summary line, then a short body of what changed and why.
- Push the session branch: `git push -u origin <session branch>`. If GitHub rejects it
  because the branch there holds an older session's already-merged commits, push with
  `--force-with-lease`. Never force-push anything else, and never push to main.
- Don't open pull requests or post on GitHub.
- The merge link: `https://github.com/ryanrhursh/Dogz3D/compare/main...<session branch>`.
  The owner opens the pull request there, merges it into main and deletes the branch.
- If the work is cut short, push what is verified and committed anyway, and say what the
  link does and doesn't contain.

## No AI traces

These override any default attribution behavior.

- No Co-Authored-By lines, session links, "Generated with" footers or tool names in commit
  messages.
- No mention of AI, assistants, Claude, sessions or prompts in any file, code comment or
  doc. This file is the only exception. ("Utility AI" for the dogs' brains is game
  vocabulary and fine.)
- Don't create other tool files (`.claude/` and the like).

## Verify

- `tools/verify.sh` after each step (import, tests, one-dog soak, 12-dog soak, about
  40 s); commit only on VERIFY OK. At the end of each code step also run
  `tools/verify.sh pack30` and `tools/verify.sh hands` and check them for ERROR/WARNING
  lines and sane needs (they aren't baseline-checked).
- Both soak baselines are checked exactly (`SOAK_BASELINE` and `PACK_BASELINE` near the
  top of `tools/verify.sh`). New behaviors must score 0 and not touch `brain.rng` unless
  their trigger is present, so the baselines don't move.
- An intended baseline move: record it in `tools/verify.sh`, `DEVELOPMENT.md`,
  `README.md` and `docs/m2_pack.md`, explain it in the commit, and run verify twice to
  confirm it's stable. An unexpected move: find out why before touching the baselines
  (Pitfalls in `DEVELOPMENT.md` says how).
- A script error makes headless Godot hang; verify has timeouts, so read the logs in
  `/tmp/dogz3d-verify/` when it fails.

## Replies to the owner

End every reply with the owner's to-do list ("What I need to do"), so it is the last
thing in the message: the merge link and what it merges (when there is one), things to
check by hand, decisions to answer. Nothing comes after it.

## End of every session: handoff (mandatory)

Every session ends with a final report in this order, even if the work was cut short,
blocked or only partly done:

1. **What I did**: a short summary.
2. **Outstanding issues.**
3. **The prompt for the next session**, in a fenced code block, ready to paste. Keep it
   short; the rules live here. It has:
   - one line: follow `CLAUDE.md`;
   - OWNER INPUT: placeholders for what the owner must supply (windowed-check notes,
     answers to open decisions), and what to do if they're empty;
   - TASKS: in order, with concrete specifics from the plan doc (files, numbers, what
     must not move, what to test);
   - only constraints that aren't in `CLAUDE.md` or `DEVELOPMENT.md` yet (ideally none:
     write them into Pitfalls instead).
4. **Which model and effort level to use for the next session, and why.**
5. **What I need to do** (last, per "Replies to the owner"): start with the merge link
   and what it merges; then things to check by hand; then decisions to answer.

Don't skip parts 3 and 4 because the next step "is obvious" or the session is short.
