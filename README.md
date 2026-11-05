# myproject

<!-- One line on what this is. -->

## Development
Development runs in a sandboxed container with Claude Code.

**First time, or a new machine: follow [Getting started](.devcontainer/README.md#getting-started).**
It covers creating a project from the template, the requirements, tokens and the first launch.

Every session, where `<repo>` is this repository's name (the folder `~/repo/<repo>`):
```bash
~/repo/<repo>/.devcontainer/up.sh            # build or start the container, open bash in it
claude --dangerously-skip-permissions        # inside
```
`up.sh --rebuild` after a change to `.devcontainer/` or `.devcontainer-domains`; an
`environment.yml` change applies at the next start. Get Claude's work with `git fetch agent` in your clone, and review it
as in [step 7](.devcontainer/README.md#7-review-and-merge-claudes-work).
