# myproject

@.devcontainer/claude/container.md

## The project
<!-- What this is, the question it answers, and what "done" looks like. A paragraph. -->

## Layout
- `src/myproject/`: the package. Code that runs goes here, not in loose scripts or notebooks.
- `tests/`: pytest.
- `docs/decisions.md`: decisions and their reasons, newest first.
- `outputs/`: everything a run writes. Not committed.

## How I work
- I review every commit in magit, so make them easy to review: one logical change per
  commit, a message that says what and why, no unrelated reformatting or renames.
- Before each commit: `pytest` and `pyright` pass, and the files you changed are formatted
  (`isort <files> && yapf -i <files>`; settings in pyproject.toml).
- Prefer simple, readable code to clever or general code. Add no abstraction, option or
  dependency the task does not need.
- If the task is ambiguous or the plan has to change, ask rather than guess. Record agreed
  decisions in docs/decisions.md.
