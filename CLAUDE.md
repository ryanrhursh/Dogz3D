# Rules for every session

These apply to every session in this repo, on top of whatever the session prompt says.
Project docs: start with `DEVELOPMENT.md` (status, workflow, architecture, GDScript
conventions, verification), then the current milestone's plan doc in `docs/`.

## End of every session: handoff (mandatory)

Every session ends with a final report containing all five parts, even if the work was cut
short, blocked or only partly done:

1. **What I need to do**: actions for the owner. Always start with the merge link (see Git)
   and say what it merges; then things to check by hand.
2. **What you did**: a short summary.
3. **Outstanding issues.**
4. **The exact, fully detailed prompt for the next session**, in a fenced code block, ready
   to paste. Use the same structure as the prompt this session received:
   - read order;
   - git setup;
   - the no-AI-traces rules;
   - tasks with concrete specifics taken from the plan doc;
   - constraints, including everything that bit this session;
   - verify steps;
   - a FINISH section that asks for this same five-part handoff.
5. **Which model and effort level to use for the next session, and why.**

Don't skip parts 4 and 5 because the next step "is obvious" or the session is short.

## Git

The owner merges into main. Sessions never commit or push to main.

- Before any commit: `git fetch origin main && git checkout -B <session branch> origin/main`,
  `git config user.name "ryanrhursh"`,
  `git config user.email "110621309+ryanrhursh@users.noreply.github.com"`.
- Commit on the session branch only, one commit per finished, verified step.
- Push the session branch: `git push -u origin <session branch>`. If GitHub rejects it
  because the branch there holds an older session's already-merged commits, push with
  `--force-with-lease`. Never force-push anything else, and never push to main.
- Don't open pull requests or post on GitHub yourself.
- When done, give the owner the merge link:
  `https://github.com/ryanrhursh/Dogz3D/compare/main...<session branch>`
  The owner opens the pull request there, merges it into main and deletes the branch.
- If the work is cut short, push what is verified and committed anyway, and say in the
  handoff what the link does and doesn't contain.

## No AI traces

- No Co-Authored-By lines, session links, "Generated with" footers or tool names in commit
  messages.
- No mention of AI, assistants, sessions or prompts in any file, code comment or doc.
  This file is the only exception.
- Don't create other tool files (`.claude/` and the like).

## Verify

`tools/verify.sh` after each step; commit only on VERIFY OK. Both soak baselines are
checked exactly. New behaviors must score 0 and not touch `brain.rng` unless their trigger is
present, so the baselines don't move. A script error makes headless Godot hang; read the logs
in `/tmp/dogz3d-verify/` when verify fails.
